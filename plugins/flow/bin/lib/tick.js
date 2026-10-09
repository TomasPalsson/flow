'use strict';

// tick.js — `flow tick <ID> [--dir <spec-dir>] [--by user] [--sha <commit>]`.
// `--by user` answers a CHK, or a T whose files: all live outside this repo.
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

// commitStoreAfterTick(root, featureDir, slug, id, sha, stdout) — when the
// feature dir lives outside this repo (stealth), commit the tick there too
// so flow lint keeps being able to catch a deleted task. Never changes
// tick's own exit code; a non-stealth tick calls this and it is a no-op —
// and prints NOTHING, so a non-stealth tick's output stays byte-identical.
//
// Commit only when detect(root).active AND the feature dir's own git
// toplevel really IS detect(root).store — `git -C <dir> rev-parse
// --git-dir` succeeds for any dir inside SOME repo, so without this check a
// store nested under an outer repo (HOME as a dotfiles repo) would commit
// the private specs into that outer repo instead.
function commitStoreAfterTick(root, featureDir, slug, id, sha, stdout) {
  const st = require('./stealth.js').detect(root);
  if (!st.active) return;

  let realFeatureDir = featureDir;
  try { realFeatureDir = fs.realpathSync(featureDir); } catch { /* keep as-is */ }

  const top = git(realFeatureDir, ['rev-parse', '--show-toplevel']);
  if (!top.ok) {
    stdout.write(`flow: store not committed (${realFeatureDir} is not a git repo) — commit it by hand so flow lint can catch a deleted task\n`);
    return;
  }
  let realStoreTop = top.out;
  try { realStoreTop = fs.realpathSync(realStoreTop); } catch { /* keep as-is */ }
  let realStore = st.store;
  try { realStore = fs.realpathSync(realStore); } catch { /* keep as-is */ }
  if (realStoreTop !== realStore) {
    stdout.write(`flow: store not committed (store is not its own git repo) — commit ${realStoreTop} by hand so flow lint can catch a deleted task\n`);
    return;
  }

  const storeTop = realStoreTop;
  const added = git(storeTop, ['add', '-A', '--', realFeatureDir]);
  if (!added.ok) {
    stdout.write(`flow: store not committed (git add failed in ${storeTop}) — commit ${storeTop} by hand so flow lint can catch a deleted task\n`);
    return;
  }
  const diff = spawnSync('git', ['-C', storeTop, 'diff', '--cached', '--quiet'], { encoding: 'utf8', timeout: 15000 });
  if (diff.status !== 1) {
    stdout.write(`flow: store not committed (nothing staged in ${storeTop}) — commit ${storeTop} by hand so flow lint can catch a deleted task\n`);
    return;
  }
  // Pathspec: pre-staged unrelated store files (another feature dir mid-edit)
  // must not be swept into this commit.
  const commit = git(storeTop, ['commit', '-q', '-m', `${slug}: ${id} done at ${sha}`, '--', realFeatureDir]);
  if (!commit.ok) {
    stdout.write(`flow: store not committed (git commit failed in ${storeTop}) — commit ${storeTop} by hand so flow lint can catch a deleted task\n`);
    return;
  }
  stdout.write(`flow: store committed (${storeTop})\n`);
}

// External task: files: non-empty and none of them tracked at HEAD (stealth
// store, another repo). Same rule as flow-lint's by-user join skip.
function isExternal(root, files) {
  return files.length > 0 && files.every((f) => !git(root, ['ls-tree', '-r', '--name-only', 'HEAD', '--', f]).out);
}

function filesOf(line) {
  const seg = line.split('—').map((s) => s.trim()).find((s) => s.startsWith('files:'));
  return seg ? seg.slice('files:'.length).split(',').map((s) => s.trim()).filter(Boolean) : [];
}

// Which commit a tick records. `--sha` wins once verified; otherwise the newest
// commit since Base that touched the task's files:. None → HEAD, and
// flow-lint's done-touches-nothing says why.
function resolveSha(root, { id, line, base, head, shaArg, isHuman, by }) {
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
  const files = filesOf(line);
  if (!files.length) return { sha: head };
  const external = isExternal(root, files);
  if (external && by === 'user') return { sha: head, byUser: true };
  const own = git(root, ['log', '-n', '1', '--format=%h', hasBase ? `${base}..HEAD` : 'HEAD', '--'].concat(files));
  if (own.ok && own.out) return { sha: own.out };
  return {
    error: `no commit since Base ${hasBase ? base : 'none'} touched ${files.join(', ')} — commit the work first`,
    fix: `git add ${files.join(' ')} && git commit, or pass --sha <commit>` +
      (external ? `; these files live outside this repo, so a person can answer it: flow tick ${id} --by user` : ''),
  };
}

// hasEvidence(verifyDir, id) -> true when a non-empty file named <id>* exists.
function hasEvidence(verifyDir, id) {
  let names;
  try { names = fs.readdirSync(verifyDir); } catch { return false; }
  return names.some((n) => {
    if (!n.startsWith(id)) return false;
    try { const st = fs.statSync(path.join(verifyDir, n)); return st.isFile() && st.size > 0; } catch { return false; }
  });
}

// humanCheck(id, by, tasksPath) -> null, or {error, fix} for a CHK that may not be ticked.
// Needs --by user AND a non-empty verify/<CHK-id>* file beside TASKS.md: unattended
// runs tick CHKs as "user", so the file is the only proof the work was done.
function humanCheck(id, by, tasksPath) {
  if (by !== 'user') return { error: `${id} is a human checkpoint`, fix: `only a person can answer it: flow tick ${id} --by user` };
  if (!hasEvidence(path.join(path.dirname(tasksPath), 'verify'), id)) {
    return { error: `no evidence for ${id}`, fix: `write verify/${id}*.md (or a ${id}-*.png) first, then flow tick ${id} --by user` };
  }
  return null;
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
  if (isHuman) {
    const bad = humanCheck(id, by, tasksPath);
    if (bad) return fail(stderr, bad.error, bad.fix);
  }

  const head = git(root, ['rev-parse', '--short', 'HEAD']);
  if (!head.ok) return fail(stderr, 'cannot read HEAD', 'run this inside a git repo with at least one commit');

  // "something was committed": HEAD must have moved past the plan's Base.
  const base = (raw.match(/^Base:\s*(\S+)/m) || raw.match(/Base:\s*(\S+)/) || [])[1];
  if (!isHuman && base && base !== 'none' && base === head.out) {
    return fail(stderr, `HEAD is still Base: ${base} — nothing was committed for ${id}`,
      `commit ${id}'s work first, then flow tick ${id}`);
  }

  const r = resolveSha(root, { id, line: lines[hit], base, head: head.out, shaArg, isHuman, by });
  if (r.error) return fail(stderr, r.error, r.fix);
  const sha = r.sha;

  const suffix = isHuman || r.byUser ? ` — done: ${sha} by user` : ` — done: ${sha}`;
  lines[hit] = lines[hit].replace(/^- \[ \]/, '- [x]').replace(/\s*$/, '') + suffix;
  fs.writeFileSync(tasksPath, lines.join('\n'));
  resetCount(root);
  commitStoreAfterTick(root, featureDir, path.basename(featureDir), id, sha, stdout);
  stdout.write(`flow: ${id} ticked at ${sha} (${path.relative(root, tasksPath)})\n`);
  return 0;
}

module.exports = { run };
