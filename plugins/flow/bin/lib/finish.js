'use strict';

// finish.js — `flow finish on|off|status|check --hook`.
//
// /flow:next --finish means the user pre-approved every gate of ONE spec. This
// file owns the FINISH.md marker and the Stop-hook body that keeps the session
// going until the spec is done. Evidence is never pre-approved; nothing here
// writes Approved:/Verified: or ticks anything.

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { spawnSync } = require('child_process');
const { resolveFeature, routeWithCount } = require('./router.js');

const DONE = new Set(['shipped', 'idle', 'no-project']);
const HARD = new Set(['scan-failed', 'blocked', 'disagreement', 'looping', 'lying',
  'loop-active', 'ambiguous', 'prep-interviewing', 'prep-ready']);
const WORK = new Set(['drafting', 'unapproved', 'building', 'checkpoint', 'gating',
  'unverified', 'stale-pass', 'shippable', 'invalid']);
const MAX_BLOCKS = 3;

const USAGE = `usage: flow finish <on|off|status|check>
  on [--dir <d>] [--note "<text>"]   Arm finish mode for the active feature (writes FINISH.md)
  off [--dir <d>]                    Disarm it
  status [--json] [--dir <d>]        Armed or not, plus the router's current state (never moves the loop counter)
  check --hook [--session <id>]      The Stop-hook body: block while work remains, else stay silent
`;

function branchOf(root) {
  const r = spawnSync('git', ['-C', root, 'rev-parse', '--abbrev-ref', 'HEAD'], { encoding: 'utf8', timeout: 15000 });
  return r.status === 0 ? r.stdout.trim() : '';
}

function parse(argv) {
  const o = { dir: null, note: null, json: false, hook: false, session: null, help: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--dir') o.dir = argv[++i];
    else if (a === '--note') o.note = argv[++i];
    else if (a === '--json') o.json = true;
    else if (a === '--hook') o.hook = true;
    else if (a === '--session') o.session = argv[++i];
    else if (a === '--help' || a === '-h') o.help = true;
  }
  return o;
}

// feature(root, o, env) -> { dir (abs), slug } | { why }
function feature(root, o, env) {
  if (o.dir) {
    const abs = path.resolve(root, o.dir);
    return { dir: abs, slug: path.basename(abs) };
  }
  const res = resolveFeature(root, branchOf(root), env);
  if (res.error) return { why: `scan-failed: ${res.error}` };
  if (!res.slug) return { why: res.miss ? `${res.via} names ${res.miss}, which is not on disk` : 'no feature is current' };
  return { dir: path.join(root, '.specs', res.slug), slug: res.slug };
}

function disarm(dir) {
  let had = false;
  for (const f of ['FINISH.md', '.finish-blocks']) {
    try { fs.unlinkSync(path.join(dir, f)); if (f === 'FINISH.md') had = true; } catch { /* absent */ }
  }
  return had;
}

// dirtyOpenTaskFiles(root, dir) -> modified tracked paths (repo-relative) listed in
// the `files:` of an open `[ ]` task of dir/TASKS.md. Paths under .specs/ and paths
// no task owns are ignored. A task commit takes the whole file, so a user's edit
// there would be committed unattended.
function dirtyOpenTaskFiles(root, dir) {
  let tasks;
  try { tasks = fs.readFileSync(path.join(dir, 'TASKS.md'), 'utf8'); } catch { return []; }
  const owned = new Set();
  for (const line of tasks.split('\n')) {
    const m = /^\s*[-*]\s+\[ \]\s.*?\bfiles:\s*(.*?)(?:\s+[—–]\s+\w+:|$)/.exec(line);
    if (!m) continue;
    for (const f of m[1].split(',')) { const t = f.trim().replace(/^\.\//, ''); if (t) owned.add(t); }
  }
  if (!owned.size) return [];
  // -z + core.quotePath=false: raw NUL-separated paths, so non-ASCII, quotes and
  // backslashes compare equal to the `files:` text. A rename/copy record carries
  // its source path as a second NUL field.
  const r = spawnSync('git', ['-C', root, '-c', 'core.quotePath=false', 'status', '--porcelain', '-z', '--untracked-files=no'], { encoding: 'utf8', timeout: 15000 });
  if (r.status !== 0) return [];
  const hits = [];
  const recs = r.stdout.split('\0');
  for (let i = 0; i < recs.length; i++) {
    const l = recs[i];
    if (l.length < 4) continue;
    const paths = [l.slice(3)];
    if ('RC'.includes(l[0]) || 'RC'.includes(l[1])) paths.push(recs[++i] || '');
    for (const p of paths) {
      if (p.startsWith('.specs/')) continue;
      if (owned.has(p)) hits.push(p);
    }
  }
  return hits;
}

function cmdOn(root, o, io, env) {
  const f = feature(root, o, env);
  if (!f.dir) {
    io.stderr.write(`flow finish: no active feature (${f.why})\n  fix: flow use <NNN-slug>\n`);
    return 1;
  }
  if (!fs.existsSync(f.dir)) {
    io.stderr.write(`flow finish: ${f.dir} does not exist\n  fix: flow use <NNN-slug>, or pass an existing --dir\n`);
    return 1;
  }
  const rel = path.relative(root, f.dir) || f.dir;
  const file = path.join(f.dir, 'FINISH.md');
  if (fs.existsSync(file)) {
    io.stdout.write(`finish: already armed for ${rel}\n`);
    return 0;
  }
  const dirty = dirtyOpenTaskFiles(root, f.dir);
  if (dirty.length) {
    io.stderr.write(`flow finish: uncommitted edits to files that open tasks will commit:\n${dirty.map((p) => `  ${p}\n`).join('')}  fix: commit or stash these, then flow finish on\n`);
    return 1;
  }
  const note = o.note && o.note.trim() ? o.note.trim().replace(/\s*\n\s*/g, ' ') : 'none';
  const body = `# Finish mode — ${f.slug}
Armed: ${new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')} by user
Pre-approved: plan approval (Approved:), every CHK checkpoint (flow tick --by user), verification (Verified:), a draft PR
Never pre-approved: evidence — exit codes, verify: re-runs, PASS files, phase Independent tests
Note: ${note}
`;
  try {
    fs.mkdirSync(f.dir, { recursive: true });
    fs.writeFileSync(file, body);
  } catch (e) {
    io.stderr.write(`flow finish: cannot write ${file} (${e.code || e.message})\n  fix: check permissions on ${f.dir}\n`);
    return 1;
  }
  io.stdout.write(`finish: armed for ${rel} — flow finish off disarms\n`);
  return 0;
}

function cmdOff(root, o, io, env) {
  const f = feature(root, o, env);
  if (!f.dir) { io.stdout.write('finish: not armed\n'); return 0; }
  const rel = path.relative(root, f.dir) || f.dir;
  if (!disarm(f.dir)) { io.stdout.write('finish: not armed\n'); return 0; }
  io.stdout.write(`finish: disarmed ${rel}\n`);
  const { digestFor, render } = require('./digest.js');
  io.stdout.write(render(digestFor(f.dir)));
  return 0;
}

function peek(root, env) {
  return routeWithCount(root, { branch: branchOf(root) }, { count: false, env });
}

function cmdStatus(root, o, io, env) {
  const f = feature(root, o, env);
  const armed = !!(f.dir && fs.existsSync(path.join(f.dir, 'FINISH.md')));
  const r = peek(root, env);
  const rel = f.dir ? (path.relative(root, f.dir) || f.dir) : null;
  if (o.json) {
    io.stdout.write(`${JSON.stringify({ armed, feature: rel, state: r.state, why: r.why, command: r.command }, null, 2)}\n`);
    return 0;
  }
  io.stdout.write(`finish: ${armed ? `armed for ${rel}` : 'not armed'}\nstate: ${r.state} — ${r.why}\n`);
  return 0;
}

function cmdCheck(root, o, io, env) {
  const f = feature(root, o, env);
  if (!f.dir || !fs.existsSync(path.join(f.dir, 'FINISH.md'))) return 0;
  const r = peek(root, env);
  const counter = path.join(f.dir, '.finish-blocks');
  if (DONE.has(r.state)) { disarm(f.dir); return 0; }
  if (HARD.has(r.state) || !WORK.has(r.state)) return 0;

  const sig = crypto.createHash('sha1').update(`${r.state}|${r.why}`).digest('hex');
  let prev = null;
  try { prev = JSON.parse(fs.readFileSync(counter, 'utf8')); } catch { /* first block */ }
  const count = prev && prev.sig === sig && Number.isInteger(prev.count) ? prev.count + 1 : 1;
  if (count > MAX_BLOCKS) {
    try { fs.unlinkSync(counter); } catch { /* already gone */ }
    return 0;
  }
  try { fs.writeFileSync(counter, `${JSON.stringify({ sig, count })}\n`); } catch { /* unwritable: still block once per call */ }
  const reason = `flow finish: ${f.slug} is at ${r.state} — ${r.why}. You are in /flow:next --finish: the user pre-approved every gate of this spec. Keep going: run \`flow next --json\` and do what that state says (skills/next/SKILL.md §Finish). Stop only on a hard stop. \`flow finish off\` disarms.`;
  io.stdout.write(`${JSON.stringify({ decision: 'block', reason })}\n`);
  return 0;
}

function run(argv, root, io, env) {
  const sub = argv[0];
  const o = parse(argv.slice(1));
  if (sub === undefined || sub === '--help' || sub === '-h' || sub === 'help' || o.help) {
    io.stdout.write(USAGE);
    return 0;
  }
  if (sub === 'on') return cmdOn(root, o, io, env);
  if (sub === 'off') return cmdOff(root, o, io, env);
  if (sub === 'status') return cmdStatus(root, o, io, env);
  if (sub === 'check') {
    if (!o.hook) { io.stderr.write(`flow finish check: only --hook is supported\n${USAGE}`); return 2; }
    return cmdCheck(root, o, io, env);
  }
  io.stderr.write(`flow finish: unknown subcommand "${sub}"\n${USAGE}`);
  return 2;
}

module.exports = { run, feature };
