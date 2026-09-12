'use strict';

// tick.js — `flow tick <ID> [--dir <spec-dir>] [--by user] [--sha <commit>]`.
//
// K-D: the ONLY writer of `[x]`. It measures the sha rather than trusting a
// claim, which is what makes flow-lint's [x] → sha → files: join meaningful.
// The sha it measures is the newest commit in Base..HEAD that touched the
// task's files: — after a parallel wave HEAD is some other task's commit, so
// recording HEAD would be a lie flow-lint catches one call later.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveFeature, resetCount } = require('./router.js');

function fail(stderr, msg, fix) {
  stderr.write(`flow tick: ${msg}\n  fix: ${fix}\n`);
  return 1;
}

function git(root, args) {
  const r = spawnSync('git', ['-C', root].concat(args), { encoding: 'utf8', timeout: 15000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim() };
}

// Which commit a tick records. `--sha` wins once verified; otherwise the newest
// commit since Base that touched the task's files:. None → HEAD, and
// flow-lint's done-touches-nothing says why.
function resolveSha(root, { id, line, base, head, shaArg, isHuman }) {
  const hasBase = base && base !== 'none';
  if (shaArg) {
    const given = git(root, ['rev-parse', '--short', '--verify', '-q', `${shaArg}^{commit}`]);
    if (!given.ok) return { error: `--sha ${shaArg} is not a commit in this repo`, fix: 'pass a sha from git log' };
    if (!git(root, ['merge-base', '--is-ancestor', given.out, 'HEAD']).ok) {
      return { error: `--sha ${given.out} is not on this branch`, fix: 'pass a commit reachable from HEAD' };
    }
    if (hasBase && git(root, ['merge-base', '--is-ancestor', given.out, base]).ok) {
      return { error: `--sha ${given.out} is at or before Base: ${base}`, fix: `pass a commit made for ${id} since Base` };
    }
    return { sha: given.out };
  }
  if (isHuman) return { sha: head };
  const filesSeg = line.split('—').map((s) => s.trim()).find((s) => s.startsWith('files:'));
  const files = filesSeg ? filesSeg.slice('files:'.length).split(',').map((s) => s.trim()).filter(Boolean) : [];
  if (!files.length) return { sha: head };
  const own = git(root, ['log', '-n', '1', '--format=%h', hasBase ? `${base}..HEAD` : 'HEAD', '--'].concat(files));
  return { sha: own.ok && own.out ? own.out : head };
}

function run(argv, root, io, env) {
  const { stdout, stderr } = io;
  let dirArg = null;
  let by = null;
  let shaArg = null;
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--dir') { dirArg = argv[++i]; } else if (argv[i] === '--by') { by = argv[++i]; } else if (argv[i] === '--sha') { shaArg = argv[++i]; } else if (!argv[i].startsWith('-')) rest.push(argv[i]);
  }
  const id = rest[0];
  if (!id) return fail(stderr, 'no task id', 'flow tick <T###|CHK###|G###>');
  if (!/^(T|CHK|G)\d{3}$/.test(id)) return fail(stderr, `"${id}" is not a task id`, 'ids are T###, CHK### or G###');

  let featureDir;
  if (dirArg) {
    featureDir = path.resolve(root, dirArg);
  } else {
    const resolved = resolveFeature(root, git(root, ['rev-parse', '--abbrev-ref', 'HEAD']).out, env);
    if (!resolved.slug) {
      return fail(stderr, 'no active feature', 'flow use <NNN-slug>, or pass --dir .specs/NNN-slug');
    }
    featureDir = path.join(root, '.specs', resolved.slug);
  }
  const tasksPath = path.join(featureDir, 'TASKS.md');
  let raw;
  try {
    raw = fs.readFileSync(tasksPath, 'utf8');
  } catch {
    return fail(stderr, `no ${tasksPath}`, 'run /flow:next in the drafting state to write it');
  }

  const lines = raw.split('\n');
  let hit = -1;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].replace(/\r$/, '').match(/^- \[([ x~])\] (\S+)/);
    if (m && m[2] === id) { hit = i; break; }
  }
  if (hit === -1) return fail(stderr, `${id} is not a task in ${path.relative(root, tasksPath)}`, `check the id — flow lint --json lists every task in the file`);

  const state = lines[hit].match(/^- \[([ x~])\]/)[1];
  if (state === 'x') return fail(stderr, `${id} is already ticked`, 'nothing to do — a tick is append-only and never re-applied');
  if (state === '~') return fail(stderr, `${id} is dropped`, `restore it to '- [ ] ${id}' first if it is back in scope`);

  const isHuman = /^CHK/.test(id);
  if (isHuman && by !== 'user') {
    return fail(stderr, `${id} is a human checkpoint`, `only a person can answer it: flow tick ${id} --by user`);
  }

  const head = git(root, ['rev-parse', '--short', 'HEAD']);
  if (!head.ok) return fail(stderr, 'cannot read HEAD', 'run this inside a git repo with at least one commit');

  // "something was committed": HEAD must have moved past the plan's Base.
  const base = (raw.match(/^Base:\s*(\S+)/m) || raw.match(/Base:\s*(\S+)/) || [])[1];
  if (!isHuman && base && base !== 'none' && base === head.out) {
    return fail(stderr, `HEAD is still Base: ${base} — nothing was committed for ${id}`,
      `commit ${id}'s work first, then flow tick ${id}`);
  }

  const r = resolveSha(root, { id, line: lines[hit], base, head: head.out, shaArg, isHuman });
  if (r.error) return fail(stderr, r.error, r.fix);
  const sha = r.sha;

  const suffix = isHuman ? ` — done: ${sha} by user` : ` — done: ${sha}`;
  lines[hit] = lines[hit].replace(/^- \[ \]/, '- [x]').replace(/\s*$/, '') + suffix;
  fs.writeFileSync(tasksPath, lines.join('\n'));
  resetCount(root);
  stdout.write(`flow: ${id} ticked at ${sha} (${path.relative(root, tasksPath)})\n`);
  return 0;
}

module.exports = { run };
