#!/usr/bin/env bash
# format-lint.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# Runs a formatter — never a linter — over the file that was just written,
# and only a formatter this project asked for. Every tool except the
# canonical ones (gofmt, fish_indent, terraform fmt) needs its own config
# file, looked up by walking from the file's directory up to the git
# toplevel; the nearest config wins and the formatter runs with that
# directory as its cwd, so the tool reads the same settings the developer
# does. Reformatting a file whose project never opted in is a diff nobody
# asked for.
#
# A formatter that fails is advisory: it prints a note and the turn goes on.
# The gates in stop-gate decide what is broken; a missing or unhappy
# formatter must never be the thing that stops work.
#
# Escape hatches: `formatOnEdit: false` in .claude/flow.config.json, or
# `flow off` for the directory.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off # `flow off` wrote .claude/flow.off here: no judging hooks

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok
[ -f "$file_path" ] || hook_ok

[ "$(hook_config formatOnEdit)" = "false" ] && hook_ok

case "${file_path##*/}" in
*.min.* | *.lock) hook_ok ;;
esac
# Vendored, generated, git-ignored and pruned paths are not ours to rewrite;
# git is still the enforcement boundary for everything else.
hook_excluded_path "$file_path" && hook_ok
hook_git_managed "$file_path" || hook_ok

_fl_dir=$(cd "$(dirname "$file_path")" 2>/dev/null && pwd -P) || hook_ok
_FL_TOP=$(git -C "$_fl_dir" rev-parse --show-toplevel 2>/dev/null || printf '')
if [ -n "$_FL_TOP" ]; then
	_FL_TOP=$(cd "$_FL_TOP" 2>/dev/null && pwd -P) || _FL_TOP=$_fl_dir
else
	_FL_TOP=$_fl_dir
fi
case "$file_path" in
"$_FL_TOP"/*) rel=${file_path#"$_FL_TOP"/} ;;
*) rel=${file_path##*/} ;;
esac

# _fl_walk_up <start-dir> <predicate> — the nearest directory from <start-dir>
# up to the git toplevel where <predicate> <dir> succeeds, printed on stdout.
_fl_walk_up() {
	local d=$1 fn=$2
	while :; do
		if "$fn" "$d"; then
			printf '%s' "$d"
			return 0
		fi
		[ "$d" = "$_FL_TOP" ] && return 1
		[ "$d" = "/" ] && return 1
		case "$d" in
		*/*)
			d=${d%/*}
			[ -z "$d" ] && d="/"
			;;
		*) return 1 ;;
		esac
	done
}

# _fl_glob_present <dir> <pattern> — true when the (unquoted, glob-expanded)
# pattern matches anything in <dir>. A literal miss leaves the pattern
# unexpanded, which then fails the -e test harmlessly.
_fl_glob_present() {
	local f
	for f in "$1"/$2; do
		[ -e "$f" ] && return 0
	done
	return 1
}

_fl_p_biome() { [ -f "$1/biome.json" ] || [ -f "$1/biome.jsonc" ]; }

_fl_p_prettier() {
	_fl_glob_present "$1" '.prettierrc*' && return 0
	_fl_glob_present "$1" 'prettier.config.*' && return 0
	[ -f "$1/package.json" ] && grep -q '"prettier"' "$1/package.json" 2>/dev/null
}

_fl_p_ruff() {
	if [ -f "$1/ruff.toml" ] || [ -f "$1/.ruff.toml" ]; then return 0; fi
	[ -f "$1/pyproject.toml" ] && grep -q '^\[tool\.ruff' "$1/pyproject.toml" 2>/dev/null
}

_fl_p_rustfmt() { [ -f "$1/rustfmt.toml" ] || [ -f "$1/.rustfmt.toml" ]; }
_fl_p_cargo() { [ -f "$1/Cargo.toml" ]; }

_fl_p_shfmt() {
	[ -f "$1/.editorconfig" ] && grep -qE '^\[\*\.sh\]|shfmt' "$1/.editorconfig" 2>/dev/null
}

_fl_node_runner() {
	if have bun; then
		_FL_R1="bunx"
		_FL_R2="--bun"
		return 0
	fi
	if have npx; then
		_FL_R1="npx"
		_FL_R2="--no-install"
		return 0
	fi
	return 1
}

# _fl_node_cmd <config-dir> <tool> — resolve a node formatter the way the
# project runs it: its own node_modules/.bin first, then an installed copy on
# PATH, and only then bunx/npx. `bunx` has no --no-install, so reaching it for
# a tool nobody installed downloads a package during an edit; a binary that is
# already here never does.
_fl_node_cmd() {
	local tool=$2 d
	for d in "$1" "$_FL_TOP"; do
		if [ -x "$d/node_modules/.bin/$tool" ]; then
			_FL_CMD=("$d/node_modules/.bin/$tool")
			return 0
		fi
	done
	if have "$tool"; then
		_FL_CMD=("$tool")
		return 0
	fi
	_fl_node_runner || return 1
	_FL_CMD=("$_FL_R1" "$_FL_R2" "$tool")
}

# _fl_py_cmd <tool> <config-dir> — resolve a python tool the way the project
# runs it: the project's own venv first, then uv when the lock file says the
# environment is uv-managed, and only then whatever is on PATH.
_fl_py_cmd() {
	local tool=$1 d
	for d in "$2" "$_FL_TOP"; do
		if [ -x "$d/.venv/bin/$tool" ]; then
			_FL_CMD=("$d/.venv/bin/$tool")
			return 0
		fi
	done
	for d in "$2" "$_FL_TOP"; do
		if [ -f "$d/uv.lock" ] && have uv; then
			_FL_CMD=(uv run --no-sync "$tool")
			return 0
		fi
	done
	have "$tool" || return 1
	_FL_CMD=("$tool")
}

# _fl_run <workdir> <tool-label> <cmd...> — run a formatter and exit. Success
# is silent; failure is a note, never a block.
_fl_run() {
	local wd=$1 label=$2 out rc
	shift 2
	[ -d "$wd" ] || hook_ok
	out=$(cd "$wd" && "$@" 2>&1)
	rc=$?
	[ "$rc" -eq 0 ] && hook_ok
	hook_note "formatter $label failed on $rel:
$(printf '%s' "$out" | tail -5)"
}

_fl_node_format() {
	local d=$1 tool=$2
	_fl_node_cmd "$d" "$tool" || hook_ok
	if [ "$tool" = "biome" ]; then
		_fl_run "$d" biome "${_FL_CMD[@]}" format --write "$file_path"
	else
		_fl_run "$d" prettier "${_FL_CMD[@]}" --write "$file_path"
	fi
}

case "$file_path" in
# Markdown never goes to biome (it does not format it); prettier only when
# the project configured prettier.
*.md | *.mdx)
	_fl_cfg=$(_fl_walk_up "$_fl_dir" _fl_p_prettier) || hook_ok
	_fl_node_format "$_fl_cfg" prettier
	;;
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css)
	if _fl_cfg=$(_fl_walk_up "$_fl_dir" _fl_p_biome); then
		_fl_node_format "$_fl_cfg" biome
	elif _fl_cfg=$(_fl_walk_up "$_fl_dir" _fl_p_prettier); then
		_fl_node_format "$_fl_cfg" prettier
	fi
	;;
*.py)
	_fl_cfg=$(_fl_walk_up "$_fl_dir" _fl_p_ruff) || hook_ok
	_fl_py_cmd ruff "$_fl_cfg" || hook_ok
	_fl_run "$_fl_cfg" ruff "${_FL_CMD[@]}" format "$file_path"
	;;
*.rs)
	# cargo fmt from the crate root, so rustfmt.toml and the edition come
	# from the manifest instead of a guess on the command line.
	_fl_walk_up "$_fl_dir" _fl_p_rustfmt >/dev/null || hook_ok
	_fl_cfg=$(_fl_walk_up "$_fl_dir" _fl_p_cargo) || hook_ok
	have cargo || hook_ok
	_fl_run "$_fl_cfg" "cargo fmt" cargo fmt
	;;
*.go)
	have gofmt || hook_ok
	_fl_run "$_fl_dir" gofmt gofmt -w "$file_path"
	;;
*.fish)
	have fish_indent || hook_ok
	_fl_run "$_fl_dir" fish_indent fish_indent -w "$file_path"
	;;
*.sh | *.bash)
	if [ "$(hook_config shfmt)" != "true" ]; then
		_fl_walk_up "$_fl_dir" _fl_p_shfmt >/dev/null || hook_ok
	fi
	have shfmt || hook_ok
	_fl_run "$_fl_dir" shfmt shfmt -w "$file_path"
	;;
*.tf)
	have terraform || hook_ok
	_fl_run "$_fl_dir" terraform terraform fmt "$file_path"
	;;
esac

hook_ok
