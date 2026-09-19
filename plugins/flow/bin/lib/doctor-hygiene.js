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

// A candidate is a linked worktree under .claude/worktrees/ — not locked,
// and not the worktree this check itself is running from.
function isCandidateWorktree(e, cwdReal) {
  if (e.path.indexOf('/.claude/worktrees/') === -1) return false;
  if (e.locked) return false;
  return realpath(e.path) !== cwdReal;
}

function warningFor(e, base, clean, merged, idle) {
  if (merged && clean && idle >= 1) {
    return `${e.path} (branch ${e.branch}) is merged and clean, idle ${idle}d — safe to remove: git worktree remove ${e.path}`;
  }
  if (idle >= 14) {
    const ahead = git(e.path, ['rev-list', '--count', `${base.head}..${e.head}`]).out || '0';
    return `${e.path} idle ${idle}d (${ahead} commits not in base, ${clean ? 'clean' : 'dirty'}) — review, then: git worktree remove ${e.path}`;
  }
  return null;
}

function worktreeHygieneCheck(push, cwd) {
  // `git worktree list` itself fails outside a repo (exit 128), which is
  // exactly "not a git repo: no row" — no separate is-inside-work-tree check.
  const list = git(cwd, ['worktree', 'list', '--porcelain']);
  if (!list.ok) return;
  const entries = parseWorktreeList(list.out);
  const base = entries[0];

  const cwdTop = git(cwd, ['rev-parse', '--show-toplevel']);
  const cwdReal = realpath(cwdTop.ok ? cwdTop.out : cwd);

  const warnings = [];
  for (const e of entries) {
    if (!isCandidateWorktree(e, cwdReal)) continue;
    const clean = git(e.path, ['status', '--porcelain']).out === '';
    const merged = git(e.path, ['merge-base', '--is-ancestor', e.head, base.head]).ok;
    const warning = warningFor(e, base, clean, merged, idleDays(e.path));
    if (warning) warnings.push(warning);
  }

  if (warnings.length === 0) {
    push('worktree-hygiene', 'PASS', 'no stale worktrees found');
    return;
  }
  for (const w of warnings) push('worktree-hygiene', 'WARN', w);
}

const PERSONAL_PATH_SUBDIRS = ['skills', 'agents', 'hooks', 'workflows'];
const PERSONAL_PATH_RE = /\/(Users|home)\/([A-Za-z0-9._-]+)\//g;
const PERSONAL_PATH_ALLOW = new Set(['you', 'me', 'user', 'USER', 'username', 'name', 'runner', 'example']);
const PERSONAL_PATH_MAX_BYTES = 1024 * 1024;
const PERSONAL_PATH_MAX_WARNS = 20;

// Every plugins/<name>/{skills,agents,hooks,workflows} dir plus the one
// flow-templates dir — the shipped surfaces a leaked path breaks an install.
function personalPathsRoots(pluginsDir) {
  let names = [];
  try {
    names = fs.readdirSync(pluginsDir, { withFileTypes: true }).filter((e) => e.isDirectory()).map((e) => e.name);
  } catch {
    names = [];
  }
  const roots = [];
  for (const name of names) {
    for (const sub of PERSONAL_PATH_SUBDIRS) roots.push(path.join(pluginsDir, name, sub));
  }
  roots.push(path.join(pluginsDir, 'flow', 'flow-templates'));
  return roots;
}

// Collects { abs, rel } for every regular file under `dir`, skipping
// node_modules, .git and a tests/fixtures dir (fixture text is never
// shipped) — a path-segment match: the dir is named exactly "fixtures" and
// its parent is named exactly "tests", not merely a path ending in that
// string (e.g. skills/unittests/fixtures must still be walked).
function personalPathsWalk(dir, rel, out) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (e.name === 'node_modules' || e.name === '.git') continue;
    const entryRel = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) {
      if (e.name === 'fixtures' && path.basename(rel) === 'tests') continue;
      personalPathsWalk(path.join(dir, e.name), entryRel, out);
    } else if (e.isFile()) {
      out.push({ abs: path.join(dir, e.name), rel: entryRel });
    }
  }
}

// null for anything over 1 MB, unreadable or containing a NUL byte — a
// binary file can't carry a real leaked path a human is meant to fix.
function personalPathReadText(abs) {
  let stat;
  try {
    stat = fs.statSync(abs);
  } catch {
    return null;
  }
  if (!stat.isFile() || stat.size > PERSONAL_PATH_MAX_BYTES) return null;
  const buf = fs.readFileSync(abs);
  if (buf.includes(0)) return null;
  return buf.toString('utf8');
}

// First line carrying a /Users/<name>/ or /home/<name>/ whose <name> isn't
// one of the allow-listed example names — {line, kind, name}, or null.
function personalPathFirstHit(text) {
  const lines = text.split('\n');
  for (let i = 0; i < lines.length; i++) {
    for (const m of lines[i].matchAll(PERSONAL_PATH_RE)) {
      if (!PERSONAL_PATH_ALLOW.has(m[2])) return { line: i + 1, kind: m[1], name: m[2] };
    }
  }
  return null;
}

function personalPathsCheck(push, repoRoot) {
  const pluginsDir = path.join(repoRoot, 'plugins');
  let pluginsStat;
  try {
    pluginsStat = fs.statSync(pluginsDir);
  } catch {
    return;
  }
  if (!pluginsStat.isDirectory()) return;

  const files = [];
  for (const root of personalPathsRoots(pluginsDir)) personalPathsWalk(root, path.relative(repoRoot, root), files);

  const hits = [];
  for (const f of files) {
    const text = personalPathReadText(f.abs);
    if (text === null) continue;
    const hit = personalPathFirstHit(text);
    if (hit) hits.push({ rel: f.rel, line: hit.line, kind: hit.kind, name: hit.name });
  }

  if (hits.length === 0) {
    push('personal-paths', 'PASS', 'no personal paths found');
    return;
  }
  for (const h of hits.slice(0, PERSONAL_PATH_MAX_WARNS)) {
    push('personal-paths', 'WARN', `${h.rel}:${h.line}: personal path /${h.kind}/${h.name}/ — use $HOME, ~ or \${CLAUDE_PLUGIN_ROOT}`);
  }
  if (hits.length > PERSONAL_PATH_MAX_WARNS) {
    push('personal-paths', 'WARN', `… and ${hits.length - PERSONAL_PATH_MAX_WARNS} more files`);
  }
}

// basenames of the *.sh files directly under `dir` — no recursion into
// lib/ or tests/, and no executable requirement (a hook that lost its
// +x bit is still a hook the docs must cover).
function referenceDocsShNames(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries.filter((e) => e.isFile() && e.name.endsWith('.sh')).map((e) => e.name);
}

// regular, executable files directly under `dir` whose name has no dot —
// the same "is this a shipped CLI script" shape flow doctor's own
// --help/install checks use (bin/flow's `(st.mode & 0o111) !== 0`).
function referenceDocsScriptNames(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return [];
  }
  const names = [];
  for (const e of entries) {
    if (!e.isFile() || e.name.indexOf('.') !== -1) continue;
    let stat;
    try {
      stat = fs.statSync(path.join(dir, e.name));
    } catch {
      continue;
    }
    if ((stat.mode & 0o111) !== 0) names.push(e.name);
  }
  return names;
}

// text of every level-2 (`## `) heading in `docPath`, in document order.
function referenceDocsHeadings(docPath) {
  let text;
  try {
    text = fs.readFileSync(docPath, 'utf8');
  } catch {
    return [];
  }
  const headings = [];
  for (const line of text.split('\n')) {
    const m = /^## (.+)$/.exec(line);
    if (m) headings.push(m[1].trim());
  }
  return headings;
}

// One WARN line per name with no matching section, then one per section
// with no matching name — `sections` is already narrowed to the headings
// that document `names` (hooks.md's non-hook headings, e.g. "hooks.json",
// are never in that set).
function referenceDocsDrift(docBasename, names, sections) {
  const nameSet = new Set(names);
  const sectionSet = new Set(sections);
  const warnings = [];
  for (const name of names) {
    if (!sectionSet.has(name)) warnings.push(`${docBasename} has no section for ${name}`);
  }
  for (const section of sections) {
    if (!nameSet.has(section)) warnings.push(`${docBasename} documents ${section}, which does not exist`);
  }
  return warnings;
}

function referenceDocsCheck(push, repoRoot) {
  const hooksDocPath = path.join(repoRoot, 'docs', 'reference', 'hooks.md');
  try {
    fs.statSync(hooksDocPath);
  } catch {
    return;
  }

  const hookNames = referenceDocsShNames(path.join(repoRoot, 'plugins', 'flow', 'hooks'));
  const hookSections = referenceDocsHeadings(hooksDocPath).filter((h) => h.endsWith('.sh'));

  const scriptsDocPath = path.join(repoRoot, 'docs', 'reference', 'scripts.md');
  const scriptNames = referenceDocsScriptNames(path.join(repoRoot, 'plugins', 'flow', 'scripts'));
  const scriptSections = referenceDocsHeadings(scriptsDocPath);

  const warnings = [
    ...referenceDocsDrift('hooks.md', hookNames, hookSections),
    ...referenceDocsDrift('scripts.md', scriptNames, scriptSections),
  ];

  if (warnings.length === 0) {
    push('reference-docs', 'PASS', 'reference docs match shipped hooks and scripts');
    return;
  }
  for (const w of warnings) push('reference-docs', 'WARN', w);
}

module.exports = { REPO_ROOT, worktreeHygieneCheck, personalPathsCheck, referenceDocsCheck };
