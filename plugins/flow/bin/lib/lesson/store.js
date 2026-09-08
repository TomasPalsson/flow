'use strict';

// lesson/store.js — where a lesson lives and how it is written: the D-4 rule
// files, the path-scoped notes, the per-store index, and the LEDGER ruling.
//
// Every write another process could race goes through the mkdir lock carried
// over from the retired scripts/lesson-record: mkdir is atomic on every POSIX
// filesystem, so it is the one lock primitive that needs no dependency and no
// cleanup handshake beyond rmdir.

const fs = require('node:fs');
const path = require('node:path');

const INDEX = '.lessons.json';

function today() {
  return new Date().toISOString().slice(0, 10);
}

// scope(root, isGlobal, env) — the two stores D-6 knows about. `base` is the
// .claude dir the lesson belongs to; `root` stays the project either way
// because .specs/LEDGER.md is always the project's.
function scope(root, isGlobal, env) {
  const base = isGlobal ? path.join(env.HOME || '', '.claude') : path.join(root, '.claude');
  return {
    global: !!isGlobal,
    root,
    rulesDir: path.join(base, 'flow.rules'),
    notesDir: path.join(base, 'rules'),
    claudeMd: isGlobal ? path.join(base, 'CLAUDE.md') : path.join(root, 'CLAUDE.md'),
  };
}

// A project path is shown relative (the receipt has to be typeable); a global
// one is shown absolute, because "~/.claude" is exactly the phrase the user
// should not have to resolve.
function display(sc, abs) {
  return sc.global ? abs : path.relative(sc.root, abs);
}

function exists(p) {
  try {
    fs.accessSync(p);
    return true;
  } catch {
    return false;
  }
}

function read(p) {
  try {
    return fs.readFileSync(p, 'utf8');
  } catch {
    return null;
  }
}

function ruleFile(sc, slug) {
  return path.join(sc.rulesDir, `${slug}.md`);
}

function ruleSlugs(sc) {
  try {
    return fs
      .readdirSync(sc.rulesDir)
      .filter((f) => f.endsWith('.md'))
      .map((f) => f.slice(0, -3))
      .sort();
  } catch {
    return [];
  }
}

function readIndex(sc) {
  try {
    const j = JSON.parse(fs.readFileSync(path.join(sc.rulesDir, INDEX), 'utf8'));
    return Array.isArray(j) ? j : [];
  } catch {
    return [];
  }
}

// The index is a read-modify-write, so it takes the same lock the markdown
// appends do: two locks of DIFFERENT slugs racing here used to read the same
// entries and write back only the second one's, dropping a live lesson from
// list, undo and the recurrence gate. `fn` runs inside the lock and is handed
// the entries as they are on disk at that moment, never a stale snapshot.
function updateIndex(sc, fn) {
  fs.mkdirSync(sc.rulesDir, { recursive: true });
  const file = path.join(sc.rulesDir, INDEX);
  return withLock(file, () => {
    const entries = fn(readIndex(sc));
    fs.writeFileSync(file, `${JSON.stringify(entries, null, 2)}\n`);
    return entries;
  });
}

// ── rule files (D-4) ────────────────────────────────────────────────────────

// D-4. `pattern` is written raw — it is an ERE, and both readers (parseRule
// above and hooks/flow-rules.sh) keep it verbatim, so a pattern that begins or
// ends with a double quote is enforced exactly as drafted. Only a value that
// would stop being a scalar unquoted (`tool: "*"`) or is free prose (`source`)
// is quoted.
function ruleText(spec) {
  return [
    '---',
    `event: ${spec.event}`,
    `tool: ${spec.tool === '*' ? '"*"' : spec.tool}`,
    `pattern: ${spec.pattern}`,
    `action: ${spec.action}`,
    'enabled: true',
    `created: ${spec.created}`,
    `source: ${JSON.stringify(spec.source)}`,
    'hits: 0',
    '---',
    spec.message,
    '',
  ].join('\n');
}

function parseRule(text) {
  const lines = (text || '').split('\n');
  if (lines[0] !== '---') return null;
  const end = lines.indexOf('---', 1);
  if (end < 0) return null;
  const meta = { message: lines.slice(end + 1).join('\n').trim() };
  for (const line of lines.slice(1, end)) {
    const m = line.match(/^([a-z]+):[ \t]*(.*)$/);
    if (!m) continue;
    const raw = m[2].replace(/[ \t]+$/, '');
    // Same encoding the hook reads with (flow-rules.sh fr_trim): `pattern` is
    // an ERE kept verbatim — a `"` at either end belongs to the pattern —
    // while a value YAML had to quote to stay a scalar sheds one layer.
    meta[m[1]] = m[1] === 'pattern' ? raw : raw.replace(/^"([\s\S]*)"$/, '$1');
  }
  return meta;
}

// Rewrites the enabled: line in place — never the whole frontmatter, so a hand
// edit to any other key survives `flow lesson off`.
function setEnabled(file, value) {
  const text = read(file);
  if (text === null) return false;
  const lines = text.split('\n');
  const end = lines.indexOf('---', 1);
  let hit = false;
  for (let i = 1; i < (end < 0 ? lines.length : end); i++) {
    if (/^enabled:/.test(lines[i])) {
      lines[i] = `enabled: ${value}`;
      hit = true;
    }
  }
  if (!hit) return false;
  fs.writeFileSync(file, lines.join('\n'));
  return true;
}

// ── serialised markdown appends ─────────────────────────────────────────────

function sleepMs(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

function withLock(target, fn) {
  const lock = `${target}.lock`;
  for (let tries = 0; ; tries++) {
    try {
      fs.mkdirSync(lock);
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      if (tries >= 40) throw new Error(`could not take ${lock} after 4s (stale? rmdir it)`);
      sleepMs(100);
    }
  }
  try {
    return fn();
  } finally {
    try {
      fs.rmdirSync(lock);
    } catch {
      /* another run already released it */
    }
  }
}

// True when the file ends inside an open code fence — appending there would
// bury the line inside a code block instead of recording it.
function openFence(text) {
  return text.split('\n').filter((l) => /^\s*(```|~~~)/.test(l)).length % 2 !== 0;
}

// Appends one line to a markdown file, creating it from `header` when missing.
// Returns false when the exact line is already there: a ruling is never
// recorded twice.
function appendLine(file, line, header) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  return withLock(file, () => {
    let text = read(file);
    if (text === null) text = header;
    if (text.split('\n').indexOf(line) >= 0) return false;
    if (openFence(text)) throw new Error(`${file} ends inside an unclosed code fence`);
    if (text && !text.endsWith('\n')) text += '\n';
    fs.writeFileSync(file, `${text}${line}\n`);
    return true;
  });
}

// Under the same lock as appendLine: removing a line is a read-modify-write of
// a file another run may be appending to.
function removeLines(file, matches) {
  if (read(file) === null) return false;
  return withLock(file, () => {
    const text = read(file);
    if (text === null) return false;
    const lines = text.split('\n');
    const kept = lines.filter((l) => !matches(l));
    if (kept.length === lines.length) return false;
    fs.writeFileSync(file, kept.join('\n'));
    return true;
  });
}

// Retires one lesson's line from a notes file. A per-area file with no lessons
// left is a stub flow wrote and flow removes; CLAUDE.md is the user's file and
// is never deleted. `undo`, the recurrence promotion and a re-noted lesson all
// route through here — a promoted note that keeps its old line advertises an
// undo command that no longer owns it. `keep` is the one line to spare: the
// replacement a second `--choice note` just appended.
function dropNote(sc, file, slug, keep) {
  if (!file) return false;
  const gone = removeLines(file, (l) => l !== keep && l.indexOf(`flow lesson undo ${slug})`) >= 0);
  const rest = read(file) || '';
  if (file.indexOf(sc.notesDir) === 0 && rest.indexOf('flow lesson undo ') < 0) {
    try {
      fs.unlinkSync(file);
    } catch {
      /* already gone */
    }
  }
  return gone;
}

function appendLedger(root, line) {
  const file = path.join(root, '.specs', 'LEDGER.md');
  return appendLine(file, line, '# Ledger\n\nAppend-only. One line per shipped feature, plus every Ruling.\n\n');
}

module.exports = {
  today,
  scope,
  display,
  exists,
  read,
  ruleFile,
  ruleSlugs,
  readIndex,
  updateIndex,
  ruleText,
  parseRule,
  setEnabled,
  appendLine,
  removeLines,
  dropNote,
  appendLedger,
};
