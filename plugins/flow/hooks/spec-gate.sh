#!/usr/bin/env bash
# spec-gate.sh — PreToolUse/Edit|Write|NotebookEdit hook. SPEC C20.
#
# Deterministic "no build without an approved plan". Activated per-project
# via .claude/flow.config.json "requireSpec" (default "flow-branches": only on
# branches named flow/*), or CC_NO_SPEC_GATE=1 to disable for one session.
# Denies editing a source file when no approved, lint-clean plan exists.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off   # `flow off` wrote .claude/flow.off here: no judging hooks

# _sg20_mtime <path> — portable last-modification epoch: GNU stat, then BSD
# stat, then a python3 fallback. Empty string when none work.
_sg20_mtime() {
	_sm=$(stat -c %Y "$1" 2>/dev/null) # portable-ok
	if [ -z "$_sm" ]; then
		_sm=$(stat -f %m "$1" 2>/dev/null) # portable-ok
	fi
	if [ -z "$_sm" ] && have python3; then
		_sm=$(python3 -c 'import os,sys
print(int(os.path.getmtime(sys.argv[1])))' "$1" 2>/dev/null)
	fi
	printf '%s' "$_sm"
}

# _sg20_is_source <relpath> — rc 0 when relpath counts as a "source file"
# under C20 (i.e. is NOT excluded).
_sg20_is_source() {
	_sp=$1
	case "$_sp" in
	.specs/* | .claude/* | docs/*) return 1 ;;
	esac
	case "$_sp" in
	*.md | *.txt) return 1 ;;
	esac
	case "$_sp" in
	*_test.* | *.test.* | *.spec.*) return 1 ;;
	esac
	case "$_sp" in
	tests/* | */tests/* | __tests__/* | */__tests__/*) return 1 ;;
	esac
	case "$_sp" in
	*.lock | package-lock.json | yarn.lock | pnpm-lock.yaml | Cargo.lock | Gemfile.lock | poetry.lock | go.sum | composer.lock) return 1 ;;
	esac
	case "$_sp" in
	*/*) : ;;
	.gitignore | .editorconfig) return 1 ;;
	esac
	return 0
}

# _pl_resolve — echo the plan-lint executable path: CC_SCRIPTS_DIR (default
# the sibling scripts/ dir next to this hooks/ directory), falling back to
# $HOME/.claude/scripts for a dotfiles-style deployment that set neither.
_pl_resolve() {
	_pl_dir="${CC_SCRIPTS_DIR:-$HERE/../scripts}"
	_pl_bin="$_pl_dir/plan-lint"
	if [ ! -e "$_pl_bin" ]; then
		_pl_bin="$HOME/.claude/scripts/plan-lint"
	fi
	printf '%s' "$_pl_bin"
}

# _plan_lint_check <plan-file> — sets PL_AVAILABLE (0/1), PL_OK (0=OK,
# 1=problems), PL_OUT (plan-lint's stdout). Caches the result per plan mtime
# in ${TMPDIR:-/tmp}/claude-plan-ok-<8-char cksum of plan path> so repeated
# PreToolUse calls in the same turn stay fast.
_plan_lint_check() {
	_pl_plan=$1
	PL_AVAILABLE=1
	PL_OK=1
	PL_OUT=""
	_pl_bin=$(_pl_resolve)
	if [ ! -e "$_pl_bin" ]; then
		PL_AVAILABLE=0
		return 0
	fi
	_pl_mtime=$(_sg20_mtime "$_pl_plan")
	_pl_hashnum=$(printf '%s' "$_pl_plan" | cksum | awk '{print $1}')
	_pl_hash8=$(printf '%s' "$_pl_hashnum" | tail -c 8)
	_pl_tmp="${TMPDIR:-/tmp}"
	_pl_tmp="${_pl_tmp%/}"
	_pl_cache="$_pl_tmp/claude-plan-ok-$_pl_hash8"
	if [ -n "$_pl_mtime" ] && [ -f "$_pl_cache" ]; then
		_pl_cached_mtime=$(sed -n '1p' "$_pl_cache" 2>/dev/null)
		if [ "$_pl_cached_mtime" = "$_pl_mtime" ]; then
			_pl_cached_status=$(sed -n '2p' "$_pl_cache" 2>/dev/null)
			PL_OUT=$(tail -n +3 "$_pl_cache" 2>/dev/null)
			if [ "$_pl_cached_status" = "OK" ]; then PL_OK=0; else PL_OK=1; fi
			return 0
		fi
	fi
	_pl_run_out=$(bash "$_pl_bin" "$_pl_plan" 2>/dev/null)
	_pl_run_rc=$?
	PL_OUT="$_pl_run_out"
	if [ "$_pl_run_rc" -eq 0 ]; then
		PL_OK=0
		_pl_status="OK"
	else
		PL_OK=1
		_pl_status="FAIL"
	fi
	if [ -n "$_pl_mtime" ]; then
		{
			printf '%s\n%s\n' "$_pl_mtime" "$_pl_status"
			printf '%s\n' "$_pl_run_out"
		} >"$_pl_cache" 2>/dev/null || true
	fi
	return 0
}

# _sg_approved_plan_ok <project-dir> — rc 0 when an approved, lint-clean
# plan exists. Degrades to "ok" (do not deny) when plan-lint is unavailable
# — a hook must never block on a missing tool it cannot judge with.
_sg_approved_plan_ok() {
	_ap_plan="$1/.claude/feature-plan.local.md"
	[ -f "$_ap_plan" ] || return 1
	grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$_ap_plan" 2>/dev/null || return 1
	_plan_lint_check "$_ap_plan"
	[ "$PL_AVAILABLE" -eq 0 ] && return 0
	[ "$PL_OK" -eq 0 ] && return 0
	return 1
}

dir=$(hook_project_dir)
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

[ "${CC_NO_SPEC_GATE:-}" = "1" ] && hook_ok

cfg="$dir/.claude/flow.config.json"
_require_spec="flow-branches"
if have jq && [ -f "$cfg" ]; then
	v=$(jq -r 'if has("requireSpec") then (.requireSpec|tostring) else empty end' "$cfg" 2>/dev/null)
	[ -n "$v" ] && _require_spec="$v"
fi

_active=0
case "$_require_spec" in
true)
	_active=1
	;;
false)
	_active=0
	;;
*)
	_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
	case "$_branch" in
	flow/*) _active=1 ;;
	esac
	;;
esac
[ "$_active" -eq 0 ] && hook_ok

_file=$(hook_field '.tool_input.file_path')
[ -z "$_file" ] && hook_ok
hook_git_managed "$_file" || hook_ok   # ignored paths (scratch, build output) are never gated

_rel=$_file
case "$_rel" in
"$dir"/*) _rel=${_rel#"$dir"/} ;;
esac

_sg20_is_source "$_rel" || hook_ok

_sg_approved_plan_ok "$dir" && hook_ok

_branch_disp=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
hook_deny "Spec gate: this branch ($_branch_disp) has no approved plan (.claude/feature-plan.local.md with an 'Approved: <date>' line that passes plan-lint). Run /flow to spec and plan it, get the plan approved, then build. To edit without a plan, set requireSpec:false in .claude/flow.config.json or CC_NO_SPEC_GATE=1 for this session."
