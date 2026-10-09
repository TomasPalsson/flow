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
  "Discovered: ... defer" lines, then Assumption: lines, then Ruling: lines.
  Prints nothing when there is nothing to review.
`;

const KINDS = ['discovered', 'assumption', 'ruling'];
const LINE = /^\s*(?:[-*]\s+)?(Discovered|Assumption|Ruling):\s*(.*?)\s*$/;
const EVIDENCE = /(?:\s+[—–;|-]+)?\s+evidence:\s*(.*)$/i;
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
    items.push({ kind, line: i + 1, text: body, evidence });
  });
  return items.sort((a, b) => KINDS.indexOf(a.kind) - KINDS.indexOf(b.kind) || a.line - b.line);
}

function label(kind) {
  if (kind === 'discovered') return 'Discovered (unfiled defer)';
  return kind === 'assumption' ? 'Assumption' : 'Ruling';
}

function render(items) {
  if (!items.length) return '';
  const out = ['Attention'];
  for (const it of items) {
    out.push(`  NOTES.md:${it.line} ${label(it.kind)}: ${it.text}${it.evidence ? ` [evidence: ${it.evidence}]` : ''}`);
  }
  return `${out.join('\n')}\n`;
}

// digestFor(dir) -> items ([] when NOTES.md is absent).
function digestFor(dir) {
  try { return collect(fs.readFileSync(path.join(dir, 'NOTES.md'), 'utf8')); } catch { return []; }
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
  if (!f.dir) return 0;
  const items = digestFor(f.dir);
  if (o.json) {
    if (items.length) io.stdout.write(`${JSON.stringify(items, null, 2)}\n`);
    return 0;
  }
  io.stdout.write(render(items));
  return 0;
}

module.exports = { run, collect, render, digestFor };
