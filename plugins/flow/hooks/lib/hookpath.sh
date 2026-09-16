#!/usr/bin/env bash
# lib/hookpath.sh — which files a hook may judge, and what changed this turn.
# Sourced by lib/hookout.sh (which supplies have/hook_project_dir/hook_config/
# hook_stamp_path); never source or execute this file on its own. It lives
# beside hookout.sh so both stay well under the size guard's file limit.
#
#   hook_prune_dirs               prune directory names, one per line
#   hook_ignore_patterns          effective ignore substrings, one per line
#   hook_excluded_path <abs-file> rc 0 when the file must not be judged
#   hook_changed_since <stamp>    files newer than <stamp>, pruned and filtered
#
# Two rules this file exists to keep:
#   1. A path is judged RELATIVE to the project dir. A checkout that happens to
#      live under .../build/ or .../i18n/ must not have every one of its files
#      suppressed, and `find` must not prune its own start point.
#   2. The config parse and the project dir are resolved once per process. The
#      caches are assigned in the CALLING shell — an assignment inside $( )
#      is discarded, which would re-run jq for every file examined.

# Directory names every "what changed" walk prunes, in one place so find, the
# gates and the hooks agree.
_HOOK_PRUNE_DIRS='.git
node_modules
.venv
venv
target
dist
build
out
.next
.nuxt
.turbo
.cache
coverage
__pycache__
.ruff_cache
.mypy_cache
.pytest_cache
.terraform
.open-next
.build
.serena
.skill-forge
.ultracode
.flow-swarm'

hook_prune_dirs() { printf '%s\n' "$_HOOK_PRUNE_DIRS"; }

# Always excluded: code that is checked in here but not authored here.
_HOOK_VENDORED_PATTERNS='vendor/
third_party/
site-packages/
layer/python/
.claude/skills/'

_HOOK_DEFAULT_IGNORE='migrations/
generated/
locales/
i18n/
.generated.'

# The effective ignore list: flow.config.json "ignore" wholesale when it is a
# non-empty array of strings, else the C4 defaults — plus the vendored list.
# A malformed "ignore" (a string, an empty array, an object) keeps the defaults
# rather than silently leaving a repo with no ignore rules at all.
_hook_build_ignore_list() {
	local raw base=""
	raw=$(hook_config ignore)
	if [ -n "$raw" ] && printf '%s' "$raw" |
		jq -e 'type == "array" and length > 0 and (map(type == "string") | all)' >/dev/null 2>&1; then
		base=$(printf '%s' "$raw" | jq -r '.[]' 2>/dev/null || printf '')
	fi
	[ -n "$base" ] || base="$_HOOK_DEFAULT_IGNORE"
	printf '%s\n%s' "$base" "$_HOOK_VENDORED_PATTERNS"
}

hook_ignore_patterns() {
	if [ -z "${_HOOK_IGNORE_LIST+x}" ]; then _HOOK_IGNORE_LIST=$(_hook_build_ignore_list); fi
	printf '%s\n' "$_HOOK_IGNORE_LIST"
}

# rc 0 when a directory on the path of $1 carries a VENDORED.md marker.
_hook_vendored_marker() {
	local d=${1%/*}
	[ "$d" = "$1" ] && d="."
	while [ -n "$d" ]; do
		[ -f "$d/VENDORED.md" ] && return 0
		[ "$d" = "/" ] && return 1
		case "$d" in
		*/*)
			d=${d%/*}
			[ -z "$d" ] && d="/"
			;;
		*) return 1 ;;
		esac
	done
	return 1
}

# rc 0 when an ignore file voids the git-ignore exemption for $1 (dir $2).
# Turn-scoped: only an ignore file NEWER than the turn stamp counts, and only
# for files under that ignore file's own directory — otherwise a .gitignore
# edited last week would un-exempt every build artefact for ever. With no turn
# stamp there is no turn to scope to, so the older rule applies: an uncommitted
# ignore file in the repo voids it (adding a path to .gitignore in the same
# command that writes it must not dodge a gate).
_hook_ignore_voided() {
	local d=$2 stamp top cur gd
	# Cached in the CALLING shell (see rule 2 above): hook_stamp_path resolves
	# the session id with jq, and this runs once per git-ignored candidate.
	if [ -z "${_HOOK_STAMP+x}" ]; then _HOOK_STAMP=$(hook_stamp_path); fi
	stamp=$_HOOK_STAMP
	if [ ! -f "$stamp" ]; then
		git -C "$d" status --porcelain --untracked-files=all 2>/dev/null | awk '{print $NF}' |
			grep -qE '(^|/)\.gitignore$|^\.git/info/exclude$' && return 0
		return 1
	fi
	top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '')
	cur=$(cd "$d" 2>/dev/null && pwd -P) || cur="$d"
	while [ -n "$cur" ]; do
		[ -f "$cur/.gitignore" ] && [ "$cur/.gitignore" -nt "$stamp" ] && return 0
		[ "$cur" = "$top" ] && break
		[ "$cur" = "/" ] && break
		case "$cur" in
		*/*)
			cur=${cur%/*}
			[ -z "$cur" ] && cur="/"
			;;
		*) break ;;
		esac
	done
	# --git-common-dir, not --git-dir: inside a linked worktree the per-worktree
	# git dir has no info/exclude — git reads the COMMON one, so that is the file
	# whose mtime decides. Pre-2.5 git echoes the unknown option back; fall back.
	gd=$(git -C "$d" rev-parse --git-common-dir 2>/dev/null || printf '')
	case "$gd" in
	'' | --*) gd=$(git -C "$d" rev-parse --git-dir 2>/dev/null || printf '') ;;
	esac
	case "$gd" in
	/*) ;;
	?*) gd="$d/$gd" ;;
	*) return 1 ;;
	esac
	[ -f "$gd/info/exclude" ] && [ "$gd/info/exclude" -nt "$stamp" ] && return 0
	return 1
}

# The nearest EXISTING ancestor directory of $1, for `git -C`. A Write can name
# a path whose parent directories do not exist yet (src/new/deep/x.ts); git
# refuses to run in a missing directory, and treating that refusal as "not a
# git repo" is how an unapproved new file used to slip past spec-gate.
# check-ignore itself is path-based, so asking from an ancestor is equivalent.
hook_nearest_dir() {
	local d=${1%/*}
	[ "$d" = "$1" ] && d="."
	while [ ! -d "$d" ]; do
		case "$d" in
		/ | . | '') break ;;
		*/*)
			d=${d%/*}
			[ -z "$d" ] && d="/"
			;;
		*)
			d="."
			break
			;;
		esac
	done
	printf '%s' "$d"
}

# rc 0 when $1 is git-ignored and that exemption still stands this turn.
# check-ignore fails by itself outside a work tree, so this is one git call per
# file, not two.
_hook_git_ignored() {
	local f=$1 d
	have git || return 1
	d=$(hook_nearest_dir "$f")
	[ -d "$d" ] || return 1
	git -C "$d" -c core.quotePath=false check-ignore -q -- "$f" 2>/dev/null || return 1
	_hook_ignore_voided "$f" "$d" && return 1
	return 0
}

hook_excluded_path() {
	local f=$1 p rel
	[ "${CC_HOOKS_ALL_FILES:-}" = "1" ] && return 1
	[ -n "$f" ] || return 1
	if [ -z "${_HOOK_PDIR+x}" ]; then
		# Both spellings: the physical dir (what find prints) and the raw one a
		# tool path is likely to use when /tmp or /var is a symlink.
		_HOOK_PDIR=$(hook_project_dir)
		_HOOK_PDIR_RAW=${CLAUDE_PROJECT_DIR:-$PWD}
		_HOOK_PDIR_RAW=${_HOOK_PDIR_RAW%/}
		[ -n "$_HOOK_PDIR_RAW" ] || _HOOK_PDIR_RAW=$_HOOK_PDIR
	fi
	if [ -z "${_HOOK_IGNORE_LIST+x}" ]; then _HOOK_IGNORE_LIST=$(_hook_build_ignore_list); fi
	# Match on the path relative to the project: /srv/build/app/src/a.ts is a
	# source file, not a build artefact. Outside the project, match the whole path.
	rel=$f
	case "$f" in
	"$_HOOK_PDIR"/*) rel=${f#"$_HOOK_PDIR"/} ;;
	"$_HOOK_PDIR_RAW"/*) rel=${f#"$_HOOK_PDIR_RAW"/} ;;
	esac
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		case "/$rel/" in */"$p"/*) return 0 ;; esac
	done <<EOF
$_HOOK_PRUNE_DIRS
EOF
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		case "$rel" in *"$p"*) return 0 ;; esac
	done <<EOF
$_HOOK_IGNORE_LIST
EOF
	_hook_vendored_marker "$f" && return 0
	_hook_git_ignored "$f" && return 0
	return 1
}

# _hook_find_changed <start-dir> <stamp> — one find-newer walk from
# <start-dir>, same prune/filter rules, printed through hook_excluded_path.
# Factored out so the plain walk and the stealth walk below build IDENTICAL
# find args off different start points.
_hook_find_changed() {
	local start=$1 stamp=$2 p first args
	args=("$start" -mindepth 1 '(')
	first=1
	while IFS= read -r p; do
		[ -z "$p" ] && continue
		if [ "$first" -eq 1 ]; then first=0; else args=("${args[@]}" -o); fi
		args=("${args[@]}" -name "$p")
	done <<EOF
$_HOOK_PRUNE_DIRS
EOF
	args=("${args[@]}" ')' -prune -o -type f -newer "$stamp" -print)
	find "${args[@]}" 2>/dev/null | while IFS= read -r f; do
		hook_excluded_path "$f" || printf '%s\n' "$f"
	done
}

hook_changed_since() {
	local stamp=$1 dir specs_link
	[ -n "$stamp" ] || return 0
	[ -f "$stamp" ] || return 0
	dir=$(hook_project_dir)
	[ -d "$dir" ] || return 0
	# -prune, never -not -path: it stops find descending and BSD find agrees.
	# A worktree's .git is a FILE; -name prunes that too. -mindepth 1 keeps the
	# start point out of the -name test, so a project dir called "build" or
	# "dist" does not prune itself away into an empty change set.
	_hook_find_changed "$dir" "$stamp"
	# Stealth (docs/research/16): .specs is a SYMLINK to a private store repo,
	# so the walk above never descends into it — find without -L does not
	# follow a symlink component, only lists it as a non-"-type f" leaf. A
	# sha-less `[x]` (or any other change) written there this turn would
	# never be seen. Walk it too, starting at "$specs_link/" — the trailing
	# slash follows the start link itself, nothing past it — with the exact
	# same stamp/prune/filter rules, so paths print in the same .specs/...
	# form the plain walk already emits (never `find -L` on the whole tree).
	specs_link="$dir/.specs"
	if [ -L "$specs_link" ] && [ -d "$specs_link" ]; then
		_hook_find_changed "$specs_link/" "$stamp"
	fi
}
