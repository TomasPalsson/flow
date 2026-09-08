'use strict';

// lesson/decide.js — D-3: propose DECIDES the rung, it never presents a menu.
//
//   irreversible class            -> rule   (always wins)
//   command string / path pattern -> rule
//   reproduces in the runner      -> test
//   bookkeeping                   -> script
//   otherwise                     -> note
//
// Every predicate here reads the three lines the user gave (`did`, `should`,
// `input`) plus what is actually on disk. Nothing asks the model.

const fs = require('node:fs');
const path = require('node:path');

// Classes that are irreversible if they land once: no recurrence gate, no
// "just note it" — these force a rule (D-3).
const IRREVERSIBLE = [
  /\brm\s+-[A-Za-z]*[rf]/,
  /\bgit\s+push\b[^\n]*\s(--force\b|-f\b)/,
  /\bgit\s+reset\s+--hard\b/,
  /\bdrop(?:ped|ping|s)?\s+(?:the\s+)?(?:\w+\s+)?(database|table|schema|collection)\b/i,
  /\bchmod\s+-R\s+777\b/,
  /\b(secrets?|passwords?|credentials?)\b/i,
  /\bapi[ _-]?keys?\b/i,
  /\b(access|auth|bearer)[ _-]?tokens?\b/i,
  /\.env\b/,
  /(^|[\s"'`(/])(generated|dist|build|node_modules|vendor|coverage|target|\.next)\//,
];

// A mistake reproduces in a test when the text names code: a source file, a
// call, or an observable behaviour.
const REPRODUCIBLE = [
  /\.(js|jsx|mjs|cjs|ts|tsx|py|rb|go|rs|java|kt|swift|c|cc|cpp|h|hpp|php|ex|exs)\b/,
  /\b[A-Za-z_]\w*\(\)/,
  /\b(returns?|returned|throws?|threw|raises?|raised|crash(?:e[sd])?|undefined|null|NaN|off[- ]by[- ]one|regression|exception|stack trace|infinite loop|empty (?:list|array|string|input))\b/i,
];

const BOOKKEEPING =
  /\b(progress\.md|tasks\.md|changelog|ledger|bookkeeping|tick(?:ed|ing)?|renumber\w*|checklist|version bump|commit message|forgot to (?:update|record|log|note))\b/i;

const EXECUTABLES =
  /^(git|rm|mv|cp|chmod|chown|npm|npx|pnpm|yarn|bun|bunx|node|deno|python3?|pip3?|uv|poetry|cargo|go|make|docker|kubectl|helm|terraform|aws|gcloud|ssh|scp|rsync|curl|wget|psql|mysql|redis-cli|sed|awk|find|xargs|brew|systemctl|launchctl|killall|pkill|dd|truncate)$/;

const PATH_TOKEN = /(?:^|[\s"'`(])((?:\*\*|[\w.@*-]+)(?:\/[\w.@*-]+)+\/?)/;

function slugify(text) {
  return (
    String(text)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .split('-')
      .filter(Boolean)
      .slice(0, 8)
      .join('-')
      .slice(0, 60)
      .replace(/-+$/, '') || 'lesson'
  );
}

// The inverse of slugify: the shape a slug is allowed to have. `undo`, `off`
// and `on` take a slug from argv and join it into a path, so anything that is
// not this shape (`../../elsewhere/notes`, an absolute path) is not a slug.
function isSlug(s) {
  return typeof s === 'string' && s.length <= 60 && /^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(s);
}

// What `lock --choice <choice>` will actually put on disk. `propose` calls it
// to describe the block option honestly and `lock` to do it, so the label and
// the artefact can never disagree.
//
// The choice is final: `note` writes a note, always. D-3's recurrence gate is
// upstream of this — `propose` returns the promoted RUNG for a slug that was
// only noted before, so "a rule will be installed" is on the block label
// before the question is asked. Promoting here instead would let the option
// labelled "Just note it" install a live deny rule the user never agreed to.
function writeFor(rung, choice) {
  if (choice === 'note') return 'note';
  return rung === 'test' ? 'test' : rung === 'rule' ? 'rule' : 'note';
}

function isCommand(input) {
  const s = String(input).trim();
  if (/[|;]|&&|>>|(^|\s)>\s/.test(s)) return true;
  const toks = s.split(/\s+/);
  if (EXECUTABLES.test(toks[0])) return true;
  return toks.length > 1 && /^--?[A-Za-z]/.test(toks[1]);
}

function pathToken(input) {
  const m = String(input).match(PATH_TOKEN);
  return m ? m[1] : null;
}

function ereEscape(s) {
  return s.replace(/[.[\]{}()*+?^$|\\]/g, '\\$&');
}

function globToEre(g) {
  return g
    .split(/(\*\*|\*)/)
    .map((p) => (p === '**' ? '.*' : p === '*' ? '[^/]*' : ereEscape(p)))
    .join('');
}

// The operands of the command that was run are not the lesson — the command
// and its flags are. Keep everything up to the last flag; with no flag at all,
// the whole command is the pattern.
function commandPattern(input) {
  const toks = String(input).trim().split(/\s+/);
  let keep = toks.length;
  for (let i = toks.length - 1; i >= 0; i--) {
    if (/^-/.test(toks[i])) {
      keep = i + 1;
      break;
    }
  }
  return toks.slice(0, keep).map(ereEscape).join('[[:space:]]+');
}

// A file is only ever an example of its directory; the rule scopes to the dir.
function dirOf(token) {
  const t = token.replace(/\/+$/, '');
  return /\.[A-Za-z0-9]+$/.test(path.basename(t)) ? path.dirname(t) : t;
}

function pathPattern(token) {
  const dir = dirOf(token);
  return `${dir.indexOf('*') >= 0 ? globToEre(dir) : ereEscape(dir)}/`;
}

function noteArea(token) {
  const seg = dirOf(token).split('/').filter(Boolean).pop() || 'project';
  return slugify(seg);
}

// ── what the repo can actually run ──────────────────────────────────────────

function firstDir(root, names) {
  for (const n of names) {
    try {
      if (fs.statSync(path.join(root, n)).isDirectory()) return n;
    } catch {
      /* not this one */
    }
  }
  return null;
}

function framework(script) {
  if (/vitest/.test(script)) return 'vitest';
  if (/\bbun\b/.test(script)) return 'bun:test';
  if (/node\s+--test|node:test/.test(script)) return 'node:test';
  if (/jest/.test(script)) return 'jest';
  return '';
}

function detectRunner(root) {
  let pkg = null;
  try {
    pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  } catch {
    /* no manifest, or one that cannot be parsed: not a runner */
  }
  if (pkg && pkg.scripts && pkg.scripts.test) return { kind: 'node', framework: framework(pkg.scripts.test) };
  const pyDir = firstDir(root, ['tests', 'test']);
  const pyMarker = ['pyproject.toml', 'pytest.ini', 'tox.ini'].some((f) => fs.existsSync(path.join(root, f)));
  if (pyMarker || (pyDir && fs.readdirSync(path.join(root, pyDir)).some((f) => /^test_.*\.py$/.test(f)))) {
    return { kind: 'pytest', dir: pyDir || 'tests' };
  }
  if (fs.existsSync(path.join(root, 'Cargo.toml'))) return { kind: 'cargo' };
  if (fs.existsSync(path.join(root, 'go.mod'))) return { kind: 'go' };
  return null;
}

function reproducible(text) {
  return REPRODUCIBLE.some((re) => re.test(text));
}

function irreversible(text) {
  return IRREVERSIBLE.some((re) => re.test(text));
}

// D-3, in order. `text` is did + should + input; `input` alone decides the
// shape of the pattern.
function rungFor(text, input, runner) {
  if (irreversible(text)) return 'rule';
  if (isCommand(input) || pathToken(input)) return 'rule';
  if (runner && reproducible(text)) return 'test';
  if (BOOKKEEPING.test(text)) return 'script';
  return 'note';
}

module.exports = {
  slugify,
  isSlug,
  writeFor,
  isCommand,
  pathToken,
  commandPattern,
  pathPattern,
  noteArea,
  ereEscape,
  detectRunner,
  rungFor,
};
