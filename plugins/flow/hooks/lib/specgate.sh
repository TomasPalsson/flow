#!/usr/bin/env bash
# lib/specgate.sh — the spec gate's shared half: what counts as a source file,
# where the ACTIVE plan lives, and whether that plan is approved and lint-clean.
#
# Sourced by hooks/spec-gate.sh (PreToolUse) and hooks/stop-gate.sh (Stop),
# which used to carry 110 identical lines of this between them. Source it AFTER
# lib/hookout.sh (it uses `have`, `hook_config`); never execute it.
#
#   _sg20_mtime <path>             last-modification epoch, portably ("" if none)
#   _sg20_is_source <relpath>      rc 0 when relpath is a C20 "source file"
#   _sg_plan_path <project-dir>    absolute path of the ACTIVE plan (FU-18)
#   _sg_require_spec_active <dir>  rc 0 when requireSpec applies here
#   _plan_lint_check <plan>        sets PL_AVAILABLE (0/1), PL_OK (0=ok), PL_OUT
#   _sg_approved_plan_ok <plan>    rc 0 when <plan> is approved and lint-clean
#
# The plan pointer (FU-18): `.claude/flow.json` key "plan", else
# `.claude/flow.config.json` key "plan", else `feature-plan.local.md`. A value
# with no "/" is relative to `.claude/`, a relative value with a "/" is relative
# to the project dir, and an absolute value is used as it stands.

_SPECGATE_DIR=${BASH_SOURCE[0]%/*}
[ "$_SPECGATE_DIR" = "${BASH_SOURCE[0]}" ] && _SPECGATE_DIR="."

# _sg20_mtime <path> — GNU stat, then BSD stat, then python3.
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

# _sg_plan_path <project-dir> — the ACTIVE plan's absolute path.
_sg_plan_path() {
	_pp_dir=$1
	_pp_rel=""
	if have jq && [ -f "$_pp_dir/.claude/flow.json" ]; then
		_pp_rel=$(jq -r 'if type == "object" and (.plan | type) == "string" then .plan else empty end' \
			"$_pp_dir/.claude/flow.json" 2>/dev/null)
	fi
	[ -n "$_pp_rel" ] || _pp_rel=$(hook_config plan)
	[ -n "$_pp_rel" ] || _pp_rel="feature-plan.local.md"
	case "$_pp_rel" in
	/*) printf '%s' "$_pp_rel" ;;
	*/*) printf '%s/%s' "$_pp_dir" "$_pp_rel" ;;
	*) printf '%s/.claude/%s' "$_pp_dir" "$_pp_rel" ;;
	esac
}

# _sg_require_spec_active <project-dir> — rc 0 when the "no build without an
# approved plan" rule applies here: requireSpec true, or "flow-branches" (the
# default) on a flow/* branch. CC_NO_SPEC_GATE=1 turns it off for one session.
_sg_require_spec_active() {
	[ "${CC_NO_SPEC_GATE:-}" = "1" ] && return 1
	_rs=$(hook_config requireSpec)
	[ -n "$_rs" ] || _rs="flow-branches"
	case "$_rs" in
	true) return 0 ;;
	false) return 1 ;;
	esac
	case "$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)" in
	flow/*) return 0 ;;
	esac
	return 1
}

# _pl_resolve — the plan-lint executable: CC_SCRIPTS_DIR (default the plugin's
# own scripts/ dir), falling back to $HOME/.claude/scripts for a dotfiles-style
# deployment that set neither.
_pl_resolve() {
	_pl_dir="${CC_SCRIPTS_DIR:-$_SPECGATE_DIR/../../scripts}"
	_pl_bin="$_pl_dir/plan-lint"
	if [ ! -e "$_pl_bin" ]; then
		_pl_bin="$HOME/.claude/scripts/plan-lint"
	fi
	printf '%s' "$_pl_bin"
}

# _plan_lint_check <plan-file> — sets PL_AVAILABLE (0/1), PL_OK (0=OK,
# 1=problems), PL_OUT (plan-lint's stdout). Caches the result per plan mtime in
# ${TMPDIR:-/tmp}/claude-plan-ok-<8-char cksum of plan path> so repeated calls
# in one turn stay fast.
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

# _sg_approved_plan_ok <plan-file> — rc 0 when that plan exists, carries an
# "Approved: <date>" line and passes plan-lint. Degrades to "ok" when plan-lint
# is unavailable: a hook must never block on a tool it cannot run.
_sg_approved_plan_ok() {
	[ -f "$1" ] || return 1
	grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null || return 1
	_plan_lint_check "$1"
	[ "$PL_AVAILABLE" -eq 0 ] && return 0
	[ "$PL_OK" -eq 0 ] && return 0
	return 1
}
