'use strict';

// stealth-hooks.js — the two git hooks `flow stealth` generates
// (post-checkout, commit-msg) and writeHooks(), which installs them.
// Split out of stealth.js to keep that file under the size guard.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

function safeRead(p) {
  try { return fs.readFileSync(p, 'utf8'); } catch { return null; }
}

function git(cwd, args) {
  const r = spawnSync('git', ['-C', cwd].concat(args), { encoding: 'utf8', timeout: 10000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function postCheckoutScript(store) {
  return '#!/bin/sh\n'
    + '# flow-stealth: git worktree add never copies untracked files; re-link the private specs\n'
    + 'top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0\n'
    + `[ -e "$top/.specs" ] || [ -L "$top/.specs" ] || ln -s '${store}/.specs' "$top/.specs" 2>/dev/null\n`
    + 'exit 0\n';
}

// commitMsgScript(store) -> a POSIX sh hook that refuses ONLY real ids/slugs
// (read from the store's own TASKS.md files and feature dir names) plus a
// short list of unambiguous spec-vocabulary patterns — not a generic
// T###/CHK###/G### regex, which false-positived on "Bump G123 driver" or
// "HTTP T100 support" and missed a `-m "#T001 …"` line (git keeps the '#'
// for -m; only an editor-cleaned message strips it, so `grep -v '^#'` was
// wrong). The message is read up to (not including) the `-v` scissors line;
// everything else, including other '#' lines, is kept.
function commitMsgScript(store) {
  return '#!/bin/sh\n'
    + '# flow-stealth: this repo must not learn about the private specs\n'
    + `store='${store}'\n`
    + 'msgfile=$1\n'
    + 'cut=$(grep -n -F -x \'# ------------------------ >8 ------------------------\' "$msgfile" 2>/dev/null | head -1 | cut -d: -f1)\n'
    + 'if [ -n "$cut" ]; then\n'
    + '  body=$(head -n $((cut - 1)) "$msgfile")\n'
    + 'else\n'
    + '  body=$(cat "$msgfile" 2>/dev/null)\n'
    + 'fi\n'
    + 'refuse() {\n'
    + '  echo "commit-msg (flow stealth): \\"$1\\" names a private spec — describe the change for the maintainers instead" >&2\n'
    + '  exit 1\n'
    + '}\n'
    + '# Real ids: every T###/CHK###/G### that STARTS a task line.\n'
    + 'for id in $(grep -h -o -E \'^- \\[[ x~]\\] (T|CHK|G)[0-9]{3}\' "$store"/.specs/*/TASKS.md "$store"/.specs/archive/*/TASKS.md 2>/dev/null | sed -E \'s/^.*\\] //\'); do\n'
    + '  case "$body" in\n'
    + '  *"$id"*) printf \'%s\\n\' "$body" | grep -Eq "(^|[^A-Za-z0-9_-])$id([^A-Za-z0-9_-]|\\$)" && refuse "$id" ;;\n'
    + '  esac\n'
    + 'done\n'
    + '# Real slugs: NNN-slug dirs under .specs, and the NNN-slug tail of an\n'
    + '# archive dir (YYYY-MM-DD-NNN-slug).\n'
    + 'for d in "$store"/.specs/*/ "$store"/.specs/archive/*/; do\n'
    + '  [ -d "$d" ] || continue\n'
    + '  b=$(basename "$d")\n'
    + '  slug=""\n'
    + '  case "$b" in\n'
    + '  [0-9][0-9][0-9]-*) slug=$b ;;\n'
    + '  *-*-*-*) slug=${b#*-*-*-} ;;\n'
    + '  esac\n'
    + '  [ -n "$slug" ] || continue\n'
    + '  case "$body" in\n'
    + '  *"$slug"*) printf \'%s\\n\' "$body" | grep -Eq "(^|[^A-Za-z0-9_-])$slug([^A-Za-z0-9_-]|\\$)" && refuse "$slug" ;;\n'
    + '  esac\n'
    + 'done\n'
    + 'hit=$(printf \'%s\\n\' "$body" | grep -Eo \'\\.specs/|TASKS\\.md|PASS-[0-9a-f]{7,}|(^|[^A-Za-z])[Ss]pec [0-9]{3}([^0-9]|$)|Ruling:|/flow:|flow (tick|lint|stealth)\' | head -1)\n'
    + '[ -n "$hit" ] && refuse "$hit"\n'
    + 'exit 0\n';
}

// writeHooks(root, store) -> warn[] lines. Writes nothing when hooks are
// managed elsewhere (core.hooksPath); leaves a foreign hook byte-identical.
function writeHooks(root, store) {
  const warnings = [];
  const hooksPathCfg = git(root, ['config', '--get', 'core.hooksPath']);
  if (hooksPathCfg.ok && hooksPathCfg.out !== '') {
    warnings.push(`warn: core.hooksPath is set (${hooksPathCfg.out}) — hooks are managed elsewhere; add post-checkout and commit-msg there by hand`);
    return warnings;
  }
  const hooksDirR = git(root, ['rev-parse', '--git-path', 'hooks']);
  const hooksDir = path.isAbsolute(hooksDirR.out) ? hooksDirR.out : path.resolve(root, hooksDirR.out);
  fs.mkdirSync(hooksDir, { recursive: true });
  const bodies = { 'post-checkout': postCheckoutScript(store), 'commit-msg': commitMsgScript(store) };
  for (const name of Object.keys(bodies)) {
    const hp = path.join(hooksDir, name);
    const existing = safeRead(hp);
    if (existing === null || existing.indexOf('# flow-stealth') !== -1) {
      fs.writeFileSync(hp, bodies[name]);
      fs.chmodSync(hp, 0o755);
    } else {
      warnings.push(`warn: ${hp} exists and is not flow's — add the flow-stealth lines by hand`);
    }
  }
  return warnings;
}

// hooksActive(root) -> true when the two hooks `flow stealth` installs are
// actually the ones that will run: core.hooksPath is not redirecting git
// elsewhere, and both post-checkout and commit-msg are still flow's own
// (marked) scripts. A repo can drift out of this quietly — a later `git
// config core.hooksPath`, a framework that replaces the hooks dir — and
// nothing else would ever say so again.
function hooksActive(root) {
  const hooksPathCfg = git(root, ['config', '--get', 'core.hooksPath']);
  if (hooksPathCfg.ok && hooksPathCfg.out !== '') return false;
  const hooksDirR = git(root, ['rev-parse', '--git-path', 'hooks']);
  if (!hooksDirR.ok) return false;
  const hooksDir = path.isAbsolute(hooksDirR.out) ? hooksDirR.out : path.resolve(root, hooksDirR.out);
  for (const name of ['post-checkout', 'commit-msg']) {
    const body = safeRead(path.join(hooksDir, name));
    if (body === null || body.indexOf('# flow-stealth') === -1) return false;
  }
  return true;
}

module.exports = {
  postCheckoutScript, commitMsgScript, writeHooks, hooksActive,
};
