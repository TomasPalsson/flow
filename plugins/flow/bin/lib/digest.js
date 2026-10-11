'use strict';

// digest.js — `flow digest [--feature <dir>] [--json]`.
//
// What a human who comes back after an unattended run should look at, read from
// the active feature's NOTES.md and nothing else: unfiled defers, assumptions,
// rulings. Silent (no output, exit 0) when there is nothing to show.

const fs = require('fs');
const path = require('path');

const USAGE = `usage: flow digest [--feature <dir>] [--json]
  Print the Attention list from the active feature's NOTES.md: unfiled
  "Discovered: ... defer" lines, then Assumption: lines (challenge first;
  [mechanical] ones are left out of the text, --json keeps them), then Ruling: lines.
  Minor: lines (deferred review nits, "- Minor: T### <finding>") are in --json only.
  When the security-patterns hook has logged hits (<git dir>/flow-security-hits.tsv), a
  "security rules: <rule> fixed=N open=M" line per rule follows (text output only).
  Prints nothing when there is nothing to review.
`;

const KINDS = ['discovered', 'assumption', 'ruling', 'minor'];
const LINE = /^\s*(?:[-*]\s+)?(Discovered|Assumption|Ruling|Minor):\s*(.*?)\s*$/;
const EVIDENCE = /(?:\s+[—–;|-]+)?\s+evidence:\s*(.*)$/i;
const TAG = /^\[(mechanical|taste|challenge)\]\s*/i;
const FILED = /→\s*I-\d+/;
const DEFER = /(?:^|[\s—–-])defer(?:red)?\b/i;

// collect(text) -> [{ kind, line, text, evidence }] in attention order.
function collect(text) {
  const items = [];
  text.split('\n').forEach((raw, i) => {
    const m = LINE.exec(raw);
    if (!m) return;
    const kind = m[1].toLowerCase();
    let body = m[2];
    if (kind === 'discovered' && (!DEFER.test(body) || FILED.test(body))) return;
    let evidence = null;
    const e = EVIDENCE.exec(body);
    if (e) { evidence = e[1].trim(); body = body.slice(0, e.index).trim(); }
    let tag = null;
    if (kind === 'assumption') {
      const t = TAG.exec(body);
      if (t) { tag = t[1].toLowerCase(); body = body.slice(t[0].length); }
    }
    items.push({ kind, line: i + 1, tag, text: body, evidence });
  });
  const rank = (it) => (it.tag === 'challenge' ? 0 : 1);
  return items.sort((a, b) => KINDS.indexOf(a.kind) - KINDS.indexOf(b.kind) || rank(a) - rank(b) || a.line - b.line);
}

function label(it) {
  if (it.kind === 'discovered') return 'Discovered (unfiled defer)';
  if (it.kind === 'assumption') return it.tag ? `Assumption [${it.tag}]` : 'Assumption';
  if (it.kind === 'minor') return 'Minor';
  return 'Ruling';
}

// Text output omits [mechanical] assumptions and minors (deferred nits for the whole-branch
// reviewer, not decisions for the human); --json keeps every item.
function render(items) {
  const shown = items.filter((it) => it.tag !== 'mechanical' && it.kind !== 'minor');
  if (!shown.length) return '';
  const out = ['Attention'];
  for (const it of shown) {
    out.push(`  NOTES.md:${it.line} ${label(it)}: ${it.text}${it.evidence ? ` [evidence: ${it.evidence}]` : ''}`);
  }
  return `${out.join('\n')}\n`;
}

// digestFor(dir) -> items ([] when NOTES.md is absent).
function digestFor(dir) {
  try { return collect(fs.readFileSync(path.join(dir, 'NOTES.md'), 'utf8')); } catch { return []; }
}

// securityLines(root) -> ["security rules: <rule> fixed=N open=M"] from the hook's
// <git dir>/flow-security-hits.tsv (<rule>\t<file>\t<matched text>). A hit is fixed once
// its matched text is gone from the file (or the file is). No state file: [].
function securityLines(root) {
  let raw;
  try {
    const gitDir = require('child_process').execFileSync('git', ['-C', root, 'rev-parse', '--absolute-git-dir'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    raw = fs.readFileSync(path.join(gitDir, 'flow-security-hits.tsv'), 'utf8');
  } catch { return []; }
  const seen = new Set();
  const byRule = new Map();
  const cache = new Map();
  for (const row of raw.split('\n')) {
    const [rule, file, ...rest] = row.split('\t');
    const text = rest.join('\t');
    if (!rule || !file || !text || seen.has(row)) continue;
    seen.add(row);
    if (!cache.has(file)) {
      let body = null;
      try { body = fs.readFileSync(path.resolve(root, file), 'utf8'); } catch { /* gone: fixed */ }
      cache.set(file, body);
    }
    const body = cache.get(file);
    const open = body !== null && body.includes(text);
    const c = byRule.get(rule) || { fixed: 0, open: 0 };
    c[open ? 'open' : 'fixed']++;
    byRule.set(rule, c);
  }
  return [...byRule].map(([rule, c]) => `security rules: ${rule} fixed=${c.fixed} open=${c.open}`);
}

function run(argv, root, io, env) {
  const o = { feature: null, json: false, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--feature') o.feature = argv[++i];
    else if (a === '--json') o.json = true;
    else if (a === '--help' || a === '-h') o.help = true;
    else { io.stderr.write(`flow digest: unknown argument "${a}"\n${USAGE}`); return 2; }
  }
  if (o.help) { io.stdout.write(USAGE); return 0; }
  const f = require('./finish.js').feature(root, { dir: o.feature }, env);
  const items = f.dir ? digestFor(f.dir) : [];
  if (o.json) {
    if (items.length) io.stdout.write(`${JSON.stringify(items, null, 2)}\n`);
    return 0;
  }
  io.stdout.write(render(items));
  const sec = securityLines(root);
  if (sec.length) io.stdout.write(`${sec.join('\n')}\n`);
  return 0;
}

module.exports = { run, collect, render, digestFor, securityLines };
