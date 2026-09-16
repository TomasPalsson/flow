'use strict';

// stealth.js — `flow stealth [<store>] [--check [--offline] [--json]]` and the
// detect() every other command (router, tick, publish) calls on every route.
// Stealth = <toplevel>/.specs is an UNTRACKED SYMLINK to <store>/.specs, a
// private git repo outside the target repo (docs/research/16-stealth-specs-
// 2026.md §0, §3). Nothing is saved as config — every command reads disk.

const fs = require('fs');
const path = require('path');
const os = require('os');
const crypto = require('crypto');
const { spawnSync } = require('child_process');

function safeRead(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function isFile(p) {
  try { return fs.statSync(p).isFile(); } catch { return false; }
}

function git(cwd, args) {
  const r = spawnSync('git', ['-C', cwd].concat(args), { encoding: 'utf8', timeout: 10000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

// resolveSymlinkAbs(link) -> the absolute path the symlink's own target
// names (readlink, resolved against the link's dir) — NOT realpath: must
// answer for a dangling target, and flow only ever writes literal absolute
// targets so a plain string compare against them is exact.
function resolveSymlinkAbs(link) {
  const target = fs.readlinkSync(link);
  return path.isAbsolute(target) ? target : path.resolve(path.dirname(link), target);
}

// detect(root) -> { active, store }. Pure fs, no git spawn.
function detect(root) {
  const specsLink = path.join(root, '.specs');
  let lst;
  try { lst = fs.lstatSync(specsLink); } catch { return { active: false, store: null }; }
  if (!lst.isSymbolicLink()) return { active: false, store: null };

  let rroot;
  try { rroot = fs.realpathSync(root); } catch { rroot = root; }

  let real;
  try {
    real = fs.realpathSync(specsLink);
  } catch {
    // Dangling link: store = dirname of the readlink target. Still apply
    // the inside-root test to that target — a link dangling to something
    // in-tree (or a .specs -> .specs self-loop) is not stealth, and bash's
    // is-stealth test already agrees (it only ever sees a resolved outside
    // path); disagreeing here would scan-fail a plain broken in-tree link.
    let abs;
    try { abs = resolveSymlinkAbs(specsLink); } catch { return { active: false, store: null }; }
    if (abs === root || abs.startsWith(root + path.sep) || abs === rroot || abs.startsWith(rroot + path.sep)) {
      return { active: false, store: null };
    }
    return { active: true, store: path.dirname(abs) };
  }
  if (real === rroot || real.startsWith(rroot + path.sep)) return { active: false, store: null };
  return { active: true, store: path.dirname(real) };
}

// publicSignals(root) -> offline reasons a repo looks public. One `git
// remote` spawn (the upstream check); file tests for the rest. [] when the
// repo already commits its specs.
function publicSignals(root) {
  const tracked = git(root, ['ls-files', '--', '.specs']);
  if (tracked.ok && tracked.out !== '') return [];

  const reasons = [];
  const remotes = git(root, ['remote']);
  if (remotes.ok && remotes.out.split('\n').map((s) => s.trim()).indexOf('upstream') !== -1) {
    reasons.push('an upstream remote');
  }
  const licenseFiles = ['LICENSE', 'LICENSE.md', 'LICENSE.txt', 'COPYING', 'COPYING.md'];
  if (licenseFiles.some((f) => fs.existsSync(path.join(root, f)))) reasons.push('a LICENSE file');
  const contributingFiles = ['CONTRIBUTING.md', path.join('.github', 'CONTRIBUTING.md'), path.join('docs', 'CONTRIBUTING.md')];
  if (contributingFiles.some((f) => isFile(path.join(root, f)))) {
    reasons.push('a CONTRIBUTING guide');
  }
  return reasons;
}

// networkSignals(root) -> reasons from `gh repo view`, only when an
// `origin` remote exists and gh resolves on PATH (spawnSync's own ENOENT
// covers "not on PATH"). Any failure -> [].
function networkSignals(root) {
  const remotes = git(root, ['remote']);
  if (!remotes.ok) return [];
  if (remotes.out.split('\n').map((s) => s.trim()).indexOf('origin') === -1) return [];
  const r = spawnSync('gh', ['repo', 'view', '--json', 'visibility,viewerPermission'], {
    cwd: root, encoding: 'utf8', timeout: 10000,
  });
  if (r.error || r.status !== 0) return [];
  let data;
  try { data = JSON.parse(r.stdout || ''); } catch { return []; }
  const reasons = [];
  if (data.visibility === 'PUBLIC') reasons.push('public on GitHub');
  if (['ADMIN', 'MAINTAIN', 'WRITE'].indexOf(data.viewerPermission) === -1) reasons.push('you cannot push to it');
  return reasons;
}

// appendMissingLines(file, lines) -> append each line from `lines` absent
// from `file`, exact-line match, idempotent. Never throws.
function appendMissingLines(file, lines) {
  try {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const cur = safeRead(file) || '';
    const existing = cur.split('\n');
    let out = cur;
    for (const line of lines) {
      if (existing.indexOf(line) === -1) {
        out += `${out === '' || out.endsWith('\n') ? '' : '\n'}${line}\n`;
        existing.push(line);
      }
    }
    if (out !== cur) fs.writeFileSync(file, out);
  } catch { /* not fatal */ }
}

// excludeLocally(root, lines) -> appendMissingLines on the file named by
// `git -C root rev-parse --git-path info/exclude` (resolved against root) —
// correct inside a linked worktree (.git is a file there), unlike joining
// `.git/info/exclude` directly.
function excludeLocally(root, lines) {
  const gp = git(root, ['rev-parse', '--git-path', 'info/exclude']);
  if (!gp.ok || !gp.out) return;
  const exclude = path.isAbsolute(gp.out) ? gp.out : path.resolve(root, gp.out);
  appendMissingLines(exclude, lines);
}

const { hooksActive, writeHooks } = require('./stealth-hooks.js');

// ─────────────────────────────────────────────────────────────────────────
// flow stealth --check
// ─────────────────────────────────────────────────────────────────────────

function runCheck(argv, root, stdout) {
  const offline = argv.includes('--offline');
  const jsonMode = argv.includes('--json');
  const st = detect(root);
  const reasons = publicSignals(root);
  if (!offline) {
    for (const r of networkSignals(root)) if (reasons.indexOf(r) === -1) reasons.push(r);
  }
  const suggest = !st.active && reasons.length > 0;
  const result = { active: st.active, store: st.store, suggest, reasons };
  if (st.active) result.hooks = hooksActive(root);
  if (jsonMode) {
    stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return 0;
  }
  stdout.write(st.active ? `stealth: on — specs in ${st.store}/.specs\n` : 'stealth: off\n');
  if (st.active) stdout.write(`hooks: ${result.hooks ? 'active' : 'missing'}\n`);
  if (suggest) {
    stdout.write(`suggest: yes — this repo looks public (${reasons.join(', ')})\n`);
    stdout.write('fix: flow stealth\n');
  }
  return 0;
}

// ─────────────────────────────────────────────────────────────────────────
// flow stealth <store> — setup. VALIDATE EVERYTHING FIRST (trackedSpecsMessage,
// resolveStore, specsLinkState — none of these mutate), MUTATE AFTER
// (applyPendingMove onward) — a refusal must leave the disk byte-identical.
// ─────────────────────────────────────────────────────────────────────────

// defaultStore(root, env) -> <HOME>/.flow/stealth/<name>-<hash6>, stable
// across every linked worktree of one clone (they share --git-common-dir).
function defaultStore(root, env) {
  const home = env.HOME || os.homedir();
  const commonDirR = git(root, ['rev-parse', '--path-format=absolute', '--git-common-dir']);
  let commonDir = commonDirR.out;
  try { commonDir = fs.realpathSync(commonDirR.out); } catch { /* keep the raw answer */ }
  const name = path.basename(path.dirname(commonDir));
  const hash6 = crypto.createHash('sha1').update(commonDir).digest('hex').slice(0, 6);
  return path.join(home, '.flow', 'stealth', `${name}-${hash6}`);
}

// trackedSpecsMessage(root) -> fail message when .specs/ is already
// tracked, else null. Pure validation.
function trackedSpecsMessage(root) {
  const tracked = git(root, ['ls-files', '--', '.specs']);
  if (!tracked.ok || tracked.out === '') return null;
  return 'this repo commits its specs (.specs/ is tracked) — stealth would hide them\n'
    + '  fix: nothing to do, or git rm -r --cached .specs first if they should leave the repo';
}

// canonicalizeExisting(p) -> p with every existing leading component
// resolved through realpath (a non-existent tail is kept lexical). Both root
// and an explicit --store arg must compare on the same footing — e.g. macOS
// aliases /var to /private/var — or "inside root" containment can miss a
// store given through a different alias than the one git reports for root.
function canonicalizeExisting(p) {
  let cur = p;
  const suffix = [];
  for (let i = 0; i < 64; i++) {
    try {
      const real = fs.realpathSync(cur);
      return suffix.length ? path.join(real, ...suffix) : real;
    } catch {
      const up = path.dirname(cur);
      if (up === cur) return p;
      suffix.unshift(path.basename(cur));
      cur = up;
    }
  }
  return p;
}

// validateStorePath(store, root) -> null | error message. Shared by the
// explicit --store arg path (resolveStore) and the "adopt an existing
// .specs link" path (symlinkState) so both refuse the same things: a
// shell-unsafe path, a store inside root, or a store that is an ANCESTOR of
// root (R9 — root would then sit inside the very thing meant to keep it out).
function validateStorePath(store, root) {
  let rroot;
  try { rroot = fs.realpathSync(root); } catch { rroot = root; }
  if (store === rroot || store.startsWith(rroot + path.sep)) {
    return `store ${store} is inside this repo\n  fix: pick a store path outside ${rroot}`;
  }
  if (rroot === store || rroot.startsWith(store + path.sep)) {
    return `store ${store} is an ancestor of this repo\n  fix: pick a store outside and not above this repo`;
  }
  if (store.indexOf("'") !== -1 || store.indexOf('\n') !== -1) {
    return 'store path contains a quote or a newline — pick a plain path';
  }
  return null;
}

// resolveStore(argv, root, env) -> { store, storeArg } | { error }. Pure
// validation — refuses a store inside root, above root, or with a
// shell-unsafe path.
function resolveStore(argv, root, env) {
  const storeArg = argv.find((a) => !a.startsWith('-'));
  const rawStore = storeArg ? path.resolve(process.cwd(), storeArg) : defaultStore(root, env);
  const store = canonicalizeExisting(rawStore);
  const err = validateStorePath(store, root);
  if (err) return { error: err };
  return { store, storeArg };
}

// symlinkState -> the three symlink sub-cases of step 3: already pointed at
// <store>/.specs, adopted from elsewhere (no explicit store arg), or a
// conflict with an explicit different store arg. Adopting an existing link
// is NOT free — a quote in the target's path is shell injection into the
// generated post-checkout hook, and a link that is not literally named
// .specs or that resolves inside the repo is not "stealth" at all.
function symlinkState(specsLink, store, storeArg, root) {
  let abs;
  try {
    abs = resolveSymlinkAbs(specsLink);
  } catch {
    return { error: `${specsLink} is a symlink flow cannot read — fix it by hand` };
  }
  const targetStoreDir = path.dirname(abs);
  if (abs === path.join(store, '.specs')) return { alreadyLinked: true, pendingMove: null, store };
  if (storeArg) {
    return { error: `already stealth with ${targetStoreDir}; fix: remove the .specs link first` };
  }
  if (path.basename(abs) !== '.specs') {
    return { error: `${specsLink} -> ${abs} is not named .specs\n  fix: point .specs at <store>/.specs, or remove the link and re-run` };
  }
  let rroot;
  try { rroot = fs.realpathSync(root); } catch { rroot = root; }
  const insideRoot = (r) => abs === r || abs.startsWith(r + path.sep);
  if (insideRoot(root) || insideRoot(rroot)) {
    return { error: `${specsLink} -> ${abs} resolves inside this repo\n  fix: point .specs at a store outside this repo` };
  }
  const adoptedStore = canonicalizeExisting(targetStoreDir);
  const err = validateStorePath(adoptedStore, root);
  if (err) return { error: err };
  return { alreadyLinked: true, pendingMove: null, store: adoptedStore };
}

const { dirState, applyPendingMove } = require('./stealth-move.js');

// specsLinkState -> dispatches on what <root>/.specs currently is. Pure
// validation, no mutation.
function specsLinkState(specsLink, store, storeArg, root) {
  let lst = null;
  try { lst = fs.lstatSync(specsLink); } catch { lst = null; }
  if (!lst) return { alreadyLinked: false, pendingMove: null, store };
  if (lst.isSymbolicLink()) return symlinkState(specsLink, store, storeArg, root);
  if (lst.isDirectory()) return dirState(specsLink, store);
  return { alreadyLinked: false, pendingMove: null, store };
}

// ensureStoreRepo(store, isDefault) -> mkdir -p, git init if needed,
// .specs/.gitignore. `git -C store rev-parse --git-dir` succeeds for ANY dir
// inside some outer repo (e.g. HOME is a dotfiles repo) — that is not "the
// store is a repo", so check --show-toplevel resolves to the store itself,
// not an ancestor.
//
// isDefault: when flow picked the store path itself (no explicit arg), both
// <HOME>/.flow/stealth and the store dir it creates under it get mode 0700
// — private by default, since flow chose the location and nobody asked for
// it to be readable. An explicit --store arg's permissions are left alone,
// and an already-existing dir (this run didn't create it) is never chmoded.
function ensureStoreRepo(store, isDefault) {
  const stealthDir = path.dirname(store);
  if (isDefault) {
    const stealthDirExisted = fs.existsSync(stealthDir);
    fs.mkdirSync(stealthDir, { recursive: true });
    if (!stealthDirExisted) { try { fs.chmodSync(stealthDir, 0o700); } catch { /* best-effort */ } }
  }
  const storeExisted = fs.existsSync(store);
  fs.mkdirSync(store, { recursive: true });
  if (isDefault && !storeExisted) { try { fs.chmodSync(store, 0o700); } catch { /* best-effort */ } }
  let realStore = store;
  try { realStore = fs.realpathSync(store); } catch { /* keep as-is */ }
  const top = git(store, ['rev-parse', '--show-toplevel']);
  let realTop = top.ok ? top.out : null;
  if (realTop) { try { realTop = fs.realpathSync(realTop); } catch { /* keep as-is */ } }
  if (realTop !== realStore) spawnSync('git', ['init', '-q', store], { encoding: 'utf8', timeout: 10000 });
  fs.mkdirSync(path.join(store, '.specs'), { recursive: true });
  appendMissingLines(path.join(store, '.specs', '.gitignore'), ['.current', '.next-call-count']);
}

function runSetup(argv, root, stdout, stderr, env) {
  const trackedMsg = trackedSpecsMessage(root);
  if (trackedMsg) { stderr.write(`flow stealth: ${trackedMsg}\n`); return 1; }

  const resolved = resolveStore(argv, root, env);
  if (resolved.error) { stderr.write(`flow stealth: ${resolved.error}\n`); return 1; }
  let store = resolved.store;

  const specsLink = path.join(root, '.specs');
  const state = specsLinkState(specsLink, store, resolved.storeArg, root);
  if (state.error) { stderr.write(`flow stealth: ${state.error}\n`); return 1; }
  // isDefault: no --store arg, and nothing redirected us to some OTHER
  // existing store (adopting a link, or state.store otherwise diverging
  // from what resolveStore actually computed) — only flow's own pick gets
  // the private-by-default 0700 treatment.
  const isDefault = !resolved.storeArg && state.store === resolved.store;
  store = state.store;
  const alreadyLinked = state.alreadyLinked;

  const moveErr = applyPendingMove(state.pendingMove, state.cleanEntries || [], specsLink, store);
  if (moveErr) { stderr.write(`flow stealth: ${moveErr}\n`); return 1; }

  ensureStoreRepo(store, isDefault);
  if (!alreadyLinked) fs.symlinkSync(path.join(store, '.specs'), specsLink);
  excludeLocally(root, ['.specs', '.claude/', 'CLAUDE.local.md', 'PROGRESS.md', 'REVIEW.md']);
  const warnings = writeHooks(root, store);

  stdout.write(`flow: stealth on${alreadyLinked ? ' (already)' : ''} — specs live in ${store}/.specs (a private git repo)\n`);
  stdout.write(`  linked  .specs -> ${store}/.specs (hidden by .git/info/exclude)\n`);
  stdout.write('  hooks   post-checkout re-links it in new worktrees · commit-msg blocks spec vocabulary\n');
  for (const w of warnings) stdout.write(`${w}\n`);
  return 0;
}

function run(argv, root, io, env) {
  const { stdout, stderr } = io;
  if (argv.includes('--check')) return runCheck(argv, root, stdout);
  return runSetup(argv, root, stdout, stderr, env || process.env);
}

module.exports = {
  detect, publicSignals, networkSignals, excludeLocally, hooksActive, run,
};
