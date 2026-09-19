'use strict';
// doctor-hygiene.js — three WARN-only `flow doctor` checks for repo rot that
// no gate catches: worktrees nobody removed, personal absolute paths in
// shipped files, and reference docs that drifted from the files they list.
// Each check pushes PASS or WARN rows through doctor's own push(id, status,
// detail); none ever pushes FAIL, removes anything or rewrites a file.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// The marketplace repo root, from plugins/flow/bin/lib/.
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..', '..');

function git(dir, args) {
  const r = spawnSync('git', ['-C', dir].concat(args), { encoding: 'utf8', timeout: 15000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim() };
}

function realpath(p) {
  try {
    return fs.realpathSync(p);
  } catch {
    return p;
  }
}

// `git worktree list --porcelain` is entries separated by a blank line; the
// first is always the main worktree. Unrecognized lines (bare, prunable,
// ...) are ignored — this check only needs path/HEAD/branch/locked.
function parseWorktreeList(raw) {
  const entries = [];
  let cur = null;
  for (const line of raw.split('\n')) {
    if (line.startsWith('worktree ')) {
      cur = { path: line.slice('worktree '.length), head: null, branch: null, locked: false };
      entries.push(cur);
    } else if (!cur) {
      continue;
    } else if (line.startsWith('HEAD ')) {
      cur.head = line.slice('HEAD '.length);
    } else if (line.startsWith('branch ')) {
      cur.branch = line.slice('branch '.length).replace(/^refs\/heads\//, '');
    } else if (line === 'locked' || line.startsWith('locked ')) {
      cur.locked = true;
    }
  }
  return entries;
}

// now minus the newer of the HEAD commit time and the worktree dir's own
// mtime — whichever activity (a commit, or just touching files) is more
// recent decides how "idle" the worktree looks.
function idleDays(wtPath) {
  const log = git(wtPath, ['log', '-1', '--format=%ct']);
  const commitMs = log.ok && log.out ? Number(log.out) * 1000 : 0;
  let dirMs = 0;
  try {
    dirMs = fs.statSync(wtPath).mtimeMs;
  } catch {
    /* worktree dir gone out from under us */
  }
  return Math.floor((Date.now() - Math.max(commitMs, dirMs)) / 86400000);
}

function worktreeHygieneCheck(push, cwd) {
  const isRepo = git(cwd, ['rev-parse', '--is-inside-work-tree']);
  if (!isRepo.ok || isRepo.out !== 'true') return;

  const list = git(cwd, ['worktree', 'list', '--porcelain']);
  if (!list.ok) return;
  const entries = parseWorktreeList(list.out);
  const base = entries[0];

  const cwdTop = git(cwd, ['rev-parse', '--show-toplevel']);
  const cwdReal = realpath(cwdTop.ok ? cwdTop.out : cwd);

  const warnings = [];
  for (const e of entries) {
    if (e.path.indexOf('/.claude/worktrees/') === -1) continue;
    if (e.locked) continue;
    if (realpath(e.path) === cwdReal) continue;

    const clean = git(e.path, ['status', '--porcelain']).out === '';
    const merged = git(e.path, ['merge-base', '--is-ancestor', e.head, base.head]).ok;
    const idle = idleDays(e.path);

    if (merged && clean && idle >= 1) {
      warnings.push(
        `${e.path} (branch ${e.branch}) is merged and clean, idle ${idle}d — safe to remove: git worktree remove ${e.path}`
      );
    } else if (idle >= 14) {
      const ahead = git(e.path, ['rev-list', '--count', `${base.head}..${e.head}`]).out || '0';
      warnings.push(
        `${e.path} idle ${idle}d (${ahead} commits not in base, ${clean ? 'clean' : 'dirty'}) — review, then: git worktree remove ${e.path}`
      );
    }
  }

  if (warnings.length === 0) {
    push('worktree-hygiene', 'PASS', 'no stale worktrees found');
    return;
  }
  for (const w of warnings) push('worktree-hygiene', 'WARN', w);
}

function personalPathsCheck(push, repoRoot) {}

function referenceDocsCheck(push, repoRoot) {}

module.exports = { REPO_ROOT, worktreeHygieneCheck, personalPathsCheck, referenceDocsCheck };
