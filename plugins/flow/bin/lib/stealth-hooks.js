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

// TOK_HITS_SH -> a pure-shell whole-token boundary check (T4b): no id/slug
// is ever interpolated into a regex (a slug with a regex metacharacter,
// e.g. "005-c++", still matches literally via `case`/parameter-expansion
// prefix stripping). Boundary class is [A-Za-z0-9_] only — a '-' no longer
// counts as a boundary, so "T001-regression" is a hit on real id T001.
const TOK_HITS_SH = 'tab=$(printf \'\\t\')\n'
  + 'tok_hits() {\n'
  + '  rest=$1\n'
  + '  tok=$2\n'
  + '  [ -n "$tok" ] || return 1\n'
  + '  while :; do\n'
  + '    case "$rest" in\n'
  + '    *"$tok"*) ;;\n'
  + '    *) return 1 ;;\n'
  + '    esac\n'
  + '    before=${rest%%"$tok"*}\n'
  + '    after=${rest#*"$tok"}\n'
  + '    lastc=${before#"${before%?}"}\n'
  + '    firstc=${after%"${after#?}"}\n'
  + '    okb=0; oka=0\n'
  + '    case "$lastc" in [A-Za-z0-9_]) okb=1 ;; esac\n'
  + '    case "$firstc" in [A-Za-z0-9_]) oka=1 ;; esac\n'
  + '    [ "$okb" = 0 ] && [ "$oka" = 0 ] && return 0\n'
  + '    rest=$after\n'
  + '  done\n'
  + '}\n';

// IDS_SLUGS_SH -> real ids (T4d: sort -u dedupes across many features'
// TASKS.md files) and real slugs. T4a: a top-level `.specs` entry is a slug
// ONLY when it matches NNN-*; only an archive dir (YYYY-MM-DD-NNN-slug)
// strips the date prefix, and only when the remaining tail is NNN-* too —
// no generic *-*-*-* fallback that shreds a plain hyphenated dir name.
// T4d: `${d%/}` / `${b##*/}` instead of a `basename` process per dir.
const IDS_SLUGS_SH = 'ids=$(grep -h -o -E \'^- \\[[ x~]\\] (T|CHK|G)[0-9]{3}\' "$store"/.specs/*/TASKS.md "$store"/.specs/archive/*/TASKS.md 2>/dev/null | sed -E \'s/^.*\\] //\' | sort -u)\n'
  + 'slugs=""\n'
  + 'for d in "$store"/.specs/*/; do\n'
  + '  [ -d "$d" ] || continue\n'
  + '  b=${d%/}; b=${b##*/}\n'
  + '  case "$b" in\n'
  + '  [0-9][0-9][0-9]-*) slugs="$slugs\n$b" ;;\n'
  + '  esac\n'
  + 'done\n'
  + 'for d in "$store"/.specs/archive/*/; do\n'
  + '  [ -d "$d" ] || continue\n'
  + '  b=${d%/}; b=${b##*/}\n'
  + '  case "$b" in\n'
  + '  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[0-9][0-9][0-9]-*)\n'
  + '    slugs="$slugs\n${b#[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-}" ;;\n'
  + '  esac\n'
  + 'done\n';

// commitMsgScript(store) -> a POSIX sh hook that refuses ONLY real ids/slugs
// (read from the store's own TASKS.md files and feature dir names) plus a
// short list of unambiguous spec-vocabulary patterns — not a generic
// T###/CHK###/G### regex, which false-positived on "Bump G123 driver" or
// "HTTP T100 support" and missed a `-m "#T001 …"` line (git keeps the '#'
// for -m; only an editor-cleaned message strips it, so `grep -v '^#'` was
// wrong). The message is read up to (not including) the `-v` scissors line.
// T4c: git's own template comment lines ('#', '# ...', '#<TAB>...') are
// skipped from BOTH the id/slug scan and the vocabulary scan; a real line
// that merely starts with '#' (e.g. "#T001 done") is still scanned.
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
    + TOK_HITS_SH
    + IDS_SLUGS_SH
    + 'scanbody=""\n'
    + 'while IFS= read -r msgline || [ -n "$msgline" ]; do\n'
    + '  case "$msgline" in\n'
    + '  "#") continue ;;\n'
    + '  "# "*) continue ;;\n'
    + '  "#$tab"*) continue ;;\n'
    + '  esac\n'
    + '  for tok in $ids; do tok_hits "$msgline" "$tok" && refuse "$tok"; done\n'
    + '  for tok in $slugs; do tok_hits "$msgline" "$tok" && refuse "$tok"; done\n'
    + '  scanbody="$scanbody$msgline\n"\n'
    + 'done <<__FLOW_STEALTH_MSG__\n'
    + '$body\n'
    + '__FLOW_STEALTH_MSG__\n'
    + 'hit=$(printf \'%s\\n\' "$scanbody" | grep -Eo \'\\.specs/|TASKS\\.md|PASS-[0-9a-f]{7,}|(^|[^A-Za-z])[Ss]pec [0-9]{3}([^0-9]|$)|Ruling:|/flow:|flow (tick|lint|stealth)\' | head -1)\n'
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
