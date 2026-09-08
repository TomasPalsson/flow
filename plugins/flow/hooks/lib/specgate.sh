#!/usr/bin/env bash
# lib/specgate.sh — the spec gate's shared half: what counts as a source file,
# which feature is ACTIVE, and whether that feature's TASKS.md is approved and
# lint-clean.
#
# Sourced by hooks/spec-gate.sh (PreToolUse) and hooks/stop-gate.sh (Stop),
# which used to carry 110 identical lines of this between them. Source it AFTER
# lib/hookout.sh (it uses `have`); never execute it.
#
#   _sg20_mtime <path>             last-modification epoch, portably ("" if none)
#   _sg20_is_source <relpath>      rc 0 when relpath is a C20 "source file"
#   _sg_tasks_path <project-dir>   absolute path of the ACTIVE TASKS.md (K-E)
#   _sg_require_spec_active <dir>  rc 0 when requireSpec applies here
#   _fl_resolve                    path of the flow-lint executable
#   _flow_lint_check <tasks>       sets FL_AVAILABLE (0/1), FL_OK (0=ok), FL_OUT
#   _sg_approved_tasks_ok <tasks>  rc 0 when <tasks> is approved and lint-clean
#   _sg_lint_objection <tasks>     one line saying WHY it is not (with the fix:)
#   _sg_sha_less_tick <tasks>      prints the first [x] ID carrying no done: sha
#
# The active feature is resolved EXACTLY as `flow next` resolves it (spec 004
# K-C), anchored at the git toplevel: $FLOW_SPEC, else `.specs/.current`, else
# the branch `flow/<slug>` matching a `.specs/` directory by name or by name
# minus its NNN- prefix. The old per-project plan file under `.claude/` is gone:
# the plan, the progress and the resume point are one tracked TASKS.md.

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
#
# The `.specs/*` exemption is load-bearing for this whole design: the active
# TASKS.md and `.specs/.current` live there, and an extensionless pointer file
# outside `.specs/` would deny its own first write on a flow/* branch.
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
	# The named lockfiles are redundant under *.lock and deliberately kept:
	# the list documents what a lockfile is here. Every arm returns the same.
	# shellcheck disable=SC2221,SC2222
	case "$_sp" in
	*.lock | package-lock.json | yarn.lock | pnpm-lock.yaml | Cargo.lock | Gemfile.lock | poetry.lock | go.sum | composer.lock) return 1 ;;
	esac
	case "$_sp" in
	*/*) : ;;
	.gitignore | .editorconfig) return 1 ;;
	esac
	return 0
}

# _sg_tasks_path <project-dir> — the ACTIVE feature's TASKS.md, absolute.
# Prints "" and returns 1 when no feature resolves; prints the path (which need
# not exist yet, so a deny can name it) and returns 0 otherwise.
_sg_tasks_path() {
	_tp_root=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
	[ -n "$_tp_root" ] || _tp_root=$1
	_tp_slug=""
	if [ -n "${FLOW_SPEC:-}" ]; then
		_tp_slug=$FLOW_SPEC
	else
		if [ -f "$_tp_root/.specs/.current" ]; then
			_tp_slug=$(head -1 "$_tp_root/.specs/.current" 2>/dev/null | tr -d '\r' | tr -d '[:space:]')
		fi
		# A present-but-blank .current is not a decision: router.js guards its
		# miss with `if (want)` and falls through to the branch. Match it, or a
		# zero-byte file wedges the gate against a `flow next` that says BUILD.
		if [ -z "$_tp_slug" ]; then
			_tp_br=$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null)
			case "$_tp_br" in
			flow/*) _tp_slug=${_tp_br#flow/} ;;
			esac
		fi
	fi
	if [ -z "$_tp_slug" ]; then
		printf ''
		return 1
	fi
	if [ -d "$_tp_root/.specs/$_tp_slug" ]; then
		printf '%s/.specs/%s/TASKS.md' "$_tp_root" "$_tp_slug"
		return 0
	fi
	# a branch slug may omit the directory's NNN- prefix
	for _tp_d in "$_tp_root"/.specs/*-"$_tp_slug"; do
		[ -d "$_tp_d" ] || continue
		printf '%s/TASKS.md' "$_tp_d"
		return 0
	done
	printf ''
	return 1
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

# _fl_resolve — the flow-lint executable: CC_SCRIPTS_DIR (default the plugin's
# own scripts/ dir), falling back to $HOME/.claude/scripts for a dotfiles-style
# deployment that set neither.
_fl_resolve() {
	_fl_dir="${CC_SCRIPTS_DIR:-$_SPECGATE_DIR/../../scripts}"
	_fl_bin="$_fl_dir/flow-lint"
	if [ ! -e "$_fl_bin" ]; then
		_fl_bin="$HOME/.claude/scripts/flow-lint"
	fi
	printf '%s' "$_fl_bin"
}

# _flow_lint_check <TASKS.md> — sets FL_AVAILABLE (0/1), FL_OK (0=OK,
# 1=problems), FL_OUT (flow-lint's stdout). Caches the result per file mtime AND
# HEAD sha in ${TMPDIR:-/tmp}/claude-tasks-ok-<8-char cksum of the path> so
# repeated calls in one turn stay fast. flow-lint is run from the file's own
# directory so its git joins (done: sha in Base..HEAD, the HEAD: ID-vanish diff)
# see the repo the TASKS.md belongs to, not whatever directory the hook was
# invoked from. Those joins are why HEAD is half the key: a commit (or an amend)
# flips the verdict without touching the file, so an mtime-only key goes stale
# in both directions — reprinting a fixed ERROR, or approving a broken plan.
_flow_lint_check() {
	_fl_file=$1
	FL_AVAILABLE=1
	FL_OK=1
	FL_OUT=""
	_fl_bin=$(_fl_resolve)
	if [ ! -e "$_fl_bin" ]; then
		FL_AVAILABLE=0
		return 0
	fi
	_fl_mtime=$(_sg20_mtime "$_fl_file")
	if [ -n "$_fl_mtime" ]; then
		_fl_stamp="$_fl_mtime $(git -C "${_fl_file%/*}" rev-parse HEAD 2>/dev/null)"
	else
		_fl_stamp=""
	fi
	_fl_hashnum=$(printf '%s' "$_fl_file" | cksum | awk '{print $1}')
	_fl_hash8=$(printf '%s' "$_fl_hashnum" | tail -c 8)
	_fl_tmp="${TMPDIR:-/tmp}"
	_fl_tmp="${_fl_tmp%/}"
	_fl_cache="$_fl_tmp/claude-tasks-ok-$_fl_hash8"
	if [ -n "$_fl_stamp" ] && [ -f "$_fl_cache" ]; then
		_fl_cached_stamp=$(sed -n '1p' "$_fl_cache" 2>/dev/null)
		if [ "$_fl_cached_stamp" = "$_fl_stamp" ]; then
			_fl_cached_status=$(sed -n '2p' "$_fl_cache" 2>/dev/null)
			FL_OUT=$(tail -n +3 "$_fl_cache" 2>/dev/null)
			if [ "$_fl_cached_status" = "OK" ]; then FL_OK=0; else FL_OK=1; fi
			return 0
		fi
	fi
	_fl_run_out=$(cd "${_fl_file%/*}" 2>/dev/null && bash "$_fl_bin" "$_fl_file" 2>/dev/null)
	_fl_run_rc=$?
	FL_OUT="$_fl_run_out"
	if [ "$_fl_run_rc" -eq 0 ]; then
		FL_OK=0
		_fl_status="OK"
	else
		FL_OK=1
		_fl_status="FAIL"
	fi
	if [ -n "$_fl_stamp" ]; then
		{
			printf '%s\n%s\n' "$_fl_stamp" "$_fl_status"
			printf '%s\n' "$_fl_run_out"
		} >"$_fl_cache" 2>/dev/null || true
	fi
	return 0
}

# _sg_first_lint_error <flow-lint output> — the FIRST "ERROR …" line together
# with its "fix: …" line, and nothing else. flow-lint prints every ERROR with a
# fix; a deny that quoted all of them would bury the one to act on.
_sg_first_lint_error() {
	printf '%s\n' "$1" | awk '
		/^ERROR / { seen = 1 }
		seen { print }
		seen && /^[[:space:]]*fix: / { exit }
	'
}

# _sg_approved_tasks_ok <TASKS.md> — rc 0 when that file exists, carries an
# "Approved: <date>" line and passes flow-lint. Degrades to "ok" when flow-lint
# is unavailable: a hook must never block on a tool it cannot run.
_sg_approved_tasks_ok() {
	[ -n "$1" ] || return 1
	[ -f "$1" ] || return 1
	grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null || return 1
	_flow_lint_check "$1"
	[ "$FL_AVAILABLE" -eq 0 ] && return 0
	[ "$FL_OK" -eq 0 ] && return 0
	return 1
}

# _sg_lint_objection <TASKS.md> [<display path>] — the one thing wrong with
# <TASKS.md>, said out loud: no active feature, no such file, no Approved: line,
# or the FIRST flow-lint ERROR together with its fix: string. spec-gate used to
# capture the linter's output and throw it away, so a deny told the user their
# plan was invalid without ever saying which rule failed (research 11 §5).
_sg_lint_objection() {
	_lo_disp=${2:-$1}
	if [ -z "$1" ]; then
		printf 'no active feature resolves: $FLOW_SPEC is unset, .specs/.current is missing, and no .specs/ directory matches this branch. fix: run /flow:spec <idea>, or flow use <NNN-slug>'
		return 0
	fi
	if [ ! -f "$1" ]; then
		printf '%s does not exist. fix: run /flow:spec <idea> to write it' "$_lo_disp"
		return 0
	fi
	if ! grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$1" 2>/dev/null; then
		printf "%s has no 'Approved: <date> by user' line. fix: read it, then ask the user to approve it" "$_lo_disp"
		return 0
	fi
	_flow_lint_check "$1"
	if [ "$FL_AVAILABLE" -eq 0 ]; then
		printf '%s could not be checked: flow-lint is not installed. fix: run flow install, or set CC_SCRIPTS_DIR to the directory that holds it' "$_lo_disp"
		return 0
	fi
	printf '%s does not pass flow lint:\n%s' "$_lo_disp" "$(_sg_first_lint_error "$FL_OUT")"
}

# _sg_sha_less_tick <TASKS.md> — the first `- [x] <ID>` line carrying no
# `— done: <sha>`; prints <ID>, rc 1 when there is none. `flow tick` is the only
# writer of `[x]` and it appends a MEASURED sha, so a tick with no sha is a box
# the model checked by hand — spec-kit's honour system, which is what this whole
# grammar exists to replace. Fence-aware: an example inside a ``` block is an
# example, never a routing predicate.
_sg_sha_less_tick() {
	[ -n "$1" ] || return 1
	[ -f "$1" ] || return 1
	_st_id=$(awk '
		/^[ \t]*(```|~~~)/ { fence = !fence; next }
		fence { next }
		/^[ \t]*- \[x\][ \t]/ {
			if (index($0, "— done:") == 0) {
				line = $0
				sub(/^[ \t]*- \[x\][ \t]*/, "", line)
				split(line, part, " ")
				print part[1]
				exit
			}
		}
	' "$1" 2>/dev/null)
	[ -n "$_st_id" ] || return 1
	printf '%s' "$_st_id"
}
