#!/usr/bin/env bash
# stop-gate.sh — Stop hook. Exact behavior: SPEC C10.
#
# Refuses to let a turn end while the project's gates are red. "scoped"
# mode (the default) runs only the tests related to what changed this turn
# (test-changed) and occasionally promotes to a full check-all sweep;
# "true" runs the full sweep every turn; "false" turns this off. A wedge
# valve stops the same failure signature from blocking a session forever:
# after 3 identical blocks it degrades to a non-blocking exit 2 instead.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

# --- C20 spec gate helpers (unit V7) -----------------------------------
# _sg20_mtime <path> — portable last-modification epoch: GNU stat, then
# BSD stat, then a python3 fallback. Empty string when none work.
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
# 1=problems), PL_OUT (plan-lint's stdout). Caches the result per plan
# mtime in ${TMPDIR:-/tmp}/claude-plan-ok-<8-char cksum of plan path> so
# repeated calls in the same turn stay fast.
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
# plan exists. Degrades to "ok" (do not deny) when plan-lint is
# unavailable — a hook must never block on a missing tool it cannot judge.
_sg_approved_plan_ok() {
	_ap_plan="$1/.claude/feature-plan.local.md"
	[ -f "$_ap_plan" ] || return 1
	grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2}' "$_ap_plan" 2>/dev/null || return 1
	_plan_lint_check "$_ap_plan"
	[ "$PL_AVAILABLE" -eq 0 ] && return 0
	[ "$PL_OK" -eq 0 ] && return 0
	return 1
}
# -------------------------------------------------------------------------

[ "$(hook_field '.stop_hook_active')" = "true" ] && hook_ok
[ "${CC_NO_STOP_GATE:-}" = "1" ] && hook_ok

dir=$(hook_project_dir)
cfg="$dir/.claude/harness.json"

_stop_gate_mode="scoped"
_full_every=900
if have jq && [ -f "$cfg" ]; then
	v=$(jq -r 'if has("stopGate") then (.stopGate|tostring) else empty end' "$cfg" 2>/dev/null)
	[ -n "$v" ] && _stop_gate_mode="$v"
	v=$(jq -r 'if has("stopGateFullEverySec") then (.stopGateFullEverySec|tostring) else empty end' "$cfg" 2>/dev/null)
	[ -n "$v" ] && _full_every="$v"
fi
# NOTE (C20): stopGate:false disables only the test/lint sweep below, never
# the C20 spec-gate block — the spec gate's PreToolUse counterpart already
# runs regardless of stopGate, and C20 explicitly requires stop-gate.sh's
# spec-gate additions to be "independent of stopGate". So the stopGate:false
# short-circuit is applied further down, only once the spec-gate block has
# had a chance to set _block.

git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

# --- "changed this turn" (C3): union of files newer than the turn stamp
# and every path git status --porcelain reports; both empty = nothing to do.
_stamp=$(hook_stamp_path)
_sg_changed=0
_sg_newer=""
if [ -f "$_stamp" ]; then
	_sg_newer=$(find "$dir" -newer "$_stamp" -type f \
		-not -path '*/.git/*' -not -path '*/node_modules/*' \
		-not -path '*/.venv/*' -not -path '*/target/*' -not -path '*/dist/*' 2>/dev/null)
	[ -n "$_sg_newer" ] && _sg_changed=1
fi
_porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)
[ -n "$_porcelain" ] && _sg_changed=1
[ "$_sg_changed" -eq 0 ] && hook_ok

_block=0
_sig=""
_reason=""

# --- C20 spec gate (unit V7): uses the C3 changed set above.
# (a) always: if the plan file changed this turn, run plan-lint on it and
#     block on failure with its output.
# (b) when requireSpec is active on this branch: block when any source
#     file changed this turn without an approved, lint-clean plan.
# Wedge valve signature for both: "spec-gate".
_sg20_plan_path="$dir/.claude/feature-plan.local.md"
_sg20_plan_changed=0
_sg20_source_changed=0
_sg20_source_example=""

_sg20_relpath() {
	# One path per line: callers stream this into `while read` loops, so a
	# missing newline glues consecutive files into one bogus path.
	case "$1" in
	"$dir"/*) printf '%s\n' "${1#"$dir"/}" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

# _sg20_expand_porcelain_path <relpath> — echoes one relpath per line. Git
# collapses a brand-new UNTRACKED directory into a single "?? <dir>/"
# porcelain line instead of listing the files inside it. Treating that
# directory path itself as "the changed file" breaks both C20 checks this
# unit owns: a lockfile-only new dir ("vendor/composer.lock") looks like an
# opaque source path because "vendor/" does not end in "*.lock", and a plan
# file created inside a brand-new ".claude/" is invisible to the
# plan-changed check because ".claude/" != ".claude/feature-plan.local.md".
# When relpath ends in "/" (the collapsed-directory marker), expand it to
# every real file underneath (same excludes as the C3 find-newer scan);
# otherwise relpath already names a single file, so echo it unchanged.
_sg20_expand_porcelain_path() {
	_ep_rel=$1
	case "$_ep_rel" in
	*/)
		find "$dir/$_ep_rel" -type f \
			-not -path '*/.git/*' -not -path '*/node_modules/*' \
			-not -path '*/.venv/*' -not -path '*/target/*' -not -path '*/dist/*' 2>/dev/null |
			while IFS= read -r _ep_f; do
				_sg20_relpath "$_ep_f"
			done
		;;
	*)
		printf '%s\n' "$_ep_rel"
		;;
	esac
}

if [ -n "$_sg_newer" ]; then
	while IFS= read -r _sg20_f; do
		[ -z "$_sg20_f" ] && continue
		_sg20_rel=$(_sg20_relpath "$_sg20_f")
		[ "$_sg20_rel" = ".claude/feature-plan.local.md" ] && _sg20_plan_changed=1
		if _sg20_is_source "$_sg20_rel"; then
			_sg20_source_changed=1
			[ -z "$_sg20_source_example" ] && _sg20_source_example="$_sg20_rel"
		fi
	done <<EOF
$_sg_newer
EOF
fi

if [ -n "$_porcelain" ]; then
	while IFS= read -r _sg20_pline; do
		[ -z "$_sg20_pline" ] && continue
		_sg20_rest=${_sg20_pline:3}
		case "$_sg20_rest" in
		*' -> '*) _sg20_rest=${_sg20_rest#*' -> '} ;;
		esac
		case "$_sg20_rest" in
		\"*\") _sg20_rest=${_sg20_rest#\"} && _sg20_rest=${_sg20_rest%\"} ;;
		esac
		while IFS= read -r _sg20_expanded; do
			[ -z "$_sg20_expanded" ] && continue
			[ "$_sg20_expanded" = ".claude/feature-plan.local.md" ] && _sg20_plan_changed=1
			if _sg20_is_source "$_sg20_expanded"; then
				_sg20_source_changed=1
				[ -z "$_sg20_source_example" ] && _sg20_source_example="$_sg20_expanded"
			fi
		done <<EOF
$(_sg20_expand_porcelain_path "$_sg20_rest")
EOF
	done <<EOF
$_porcelain
EOF
fi

if [ "$_sg20_plan_changed" -eq 1 ] && [ -f "$_sg20_plan_path" ]; then
	_plan_lint_check "$_sg20_plan_path"
	if [ "$PL_AVAILABLE" -eq 1 ] && [ "$PL_OK" -ne 0 ]; then
		_block=1
		_sig="spec-gate"
		_reason="Gate failed: plan-lint (.claude/feature-plan.local.md)
$PL_OUT

Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop."
	fi
fi

if [ "$_block" -eq 0 ] && [ "$_sg20_source_changed" -eq 1 ]; then
	_sg20_require_spec="flow-branches"
	if have jq && [ -f "$cfg" ]; then
		_sg20_v=$(jq -r 'if has("requireSpec") then (.requireSpec|tostring) else empty end' "$cfg" 2>/dev/null)
		[ -n "$_sg20_v" ] && _sg20_require_spec="$_sg20_v"
	fi
	[ "${CC_NO_SPEC_GATE:-}" = "1" ] && _sg20_require_spec="false"
	_sg20_active=0
	case "$_sg20_require_spec" in
	true) _sg20_active=1 ;;
	false) _sg20_active=0 ;;
	*)
		_sg20_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
		case "$_sg20_branch" in flow/*) _sg20_active=1 ;; esac
		;;
	esac
	if [ "$_sg20_active" -eq 1 ] && ! _sg_approved_plan_ok "$dir"; then
		_sg20_branch_disp=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
		_block=1
		_sig="spec-gate"
		_reason="Spec gate: this branch ($_sg20_branch_disp) has no approved plan (.claude/feature-plan.local.md with an 'Approved: <date>' line that passes plan-lint), and $_sg20_source_example changed this turn without one. Run /flow to spec and plan it, get the plan approved, then build. To edit without a plan, set requireSpec:false in .claude/harness.json or CC_NO_SPEC_GATE=1 for this session.
revert the source change or get the plan approved."
	fi
fi

# stopGate:false (C4) disables only the test/lint sweep below, per C20's
# requirement that the spec-gate additions above run independently of it.
# A spec-gate block already set above must still proceed to the wedge valve
# and hook_block below, even when stopGate is false.
[ "$_block" -eq 0 ] && [ "$_stop_gate_mode" = "false" ] && hook_ok

# Hash/session stamps computed unconditionally: the wedge valve below (which
# reads _gatesig_stamp) runs whether the block below came from a red gate or
# from the C20 spec gate above.
_toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -z "$_toplevel" ] && _toplevel="$dir"
_tmp="${TMPDIR:-/tmp}"
_tmp="${_tmp%/}"
_hash_num=$(printf '%s' "$_toplevel" | cksum | awk '{print $1}')
_hash8=$(printf '%s' "$_hash_num" | tail -c 8)
_repo_base=$(basename "$_toplevel")
_gates_stamp="$_tmp/claude-gates-${_repo_base}-${_hash8}"

_session_id=$(hook_field '.session_id')
[ -z "$_session_id" ] && _session_id="nosession"
_session_id=$(printf '%s' "$_session_id" | tr -c 'A-Za-z0-9_-' '_')
_gatesig_stamp="$_tmp/claude-gatesig-${_session_id}"

if [ "$_block" -eq 0 ]; then

	_shared="${CC_SHARED_SCRIPTS:-$HERE/../skills/shared/scripts}"
	_check_all="$_shared/check-all"
	_test_changed="$_shared/test-changed"
	if [ ! -e "$_check_all" ] && [ ! -e "$_test_changed" ]; then
		hook_ok
	fi

	# check-all/test-changed are node scripts and their JSON output is parsed
	# with jq; degrade to allow (cannot judge) when either tool is missing.
	have node || hook_ok
	have jq || hook_ok

	# _sg_is_manifest_basename <path> — true (rc 0) when <path>'s exact basename
	# is one of the recognized project manifests. Directory components are
	# stripped first so `foo/package.json.orig` never matches `package.json`
	# (a plain substring check would false-positive on that and on things like
	# `mypackage.json`).
	_sg_is_manifest_basename() {
		_mb_path=$1
		# git quotes paths containing special/non-ASCII bytes in double quotes;
		# strip a matching pair before taking the basename.
		case "$_mb_path" in
		\"*\") _mb_path=${_mb_path#\"} && _mb_path=${_mb_path%\"} ;;
		esac
		case "$_mb_path" in
		*/*) _mb_base=${_mb_path##*/} ;;
		*) _mb_base=$_mb_path ;;
		esac
		case "$_mb_base" in
		package.json | pyproject.toml | Cargo.toml | go.mod | deno.json)
			return 0
			;;
		*)
			return 1
			;;
		esac
	}

	# _sg_manifest_deleted — true (rc 0) when this turn's git status shows a
	# project-manifest file that disappeared: a plain delete of the manifest, or
	# a rename whose OLD side was the manifest (the manifest no longer exists at
	# that path). A rename whose NEW side is the manifest (e.g. `git mv foo.json
	# package.json`) is the manifest being *created*, not deleted, even if the
	# resulting file is still incomplete — that is check-all's job to judge, not
	# this check, so it must not match on the new side. Matching is by exact
	# basename, not substring, so `package.json.orig` never triggers this.
	_sg_manifest_deleted() {
		_md=1
		while IFS= read -r pline; do
			[ -z "$pline" ] && continue
			_sg_status=${pline:0:2}
			_sg_rest=${pline:3}
			case "$_sg_status" in
			*R*)
				_sg_old=${_sg_rest%% -> *}
				# Only a manifest at the repository ROOT defines the ecosystem; nested
				# manifests (node_modules/x/package.json, vendored crates) never count.
				case "$_sg_old" in */*) continue ;; esac
				if _sg_is_manifest_basename "$_sg_old"; then
					_md=0
				fi
				;;
			*D*)
				case "$_sg_rest" in */*) continue ;; esac
				if _sg_is_manifest_basename "$_sg_rest"; then
					_md=0
				fi
				;;
			esac
		done <<EOF
$_porcelain
EOF
		return "$_md"
	}

	# _sg_run_full_sweep — runs `CI=true check-all --json` (no --continue, so it
	# stops at the first red gate). Sets FS_NO_ECOSYSTEM, FS_BLOCK, FS_REASON,
	# FS_SIG.
	_sg_run_full_sweep() {
		FS_NO_ECOSYSTEM=0
		FS_BLOCK=0
		FS_REASON=""
		FS_SIG=""
		_fs_out=$(cd "$dir" && CI=true node "$_check_all" --json 2>/dev/null)
		if [ -z "$_fs_out" ]; then
			# check-all exits before printing JSON when no ecosystem is detected.
			FS_NO_ECOSYSTEM=1
			return 0
		fi
		_fs_failed_count=$(printf '%s' "$_fs_out" | jq -r '[.gates[]? | select(.status=="fail")] | length' 2>/dev/null)
		case "$_fs_failed_count" in '' | *[!0-9]*) _fs_failed_count=0 ;; esac
		if [ "$_fs_failed_count" -eq 0 ]; then
			return 0
		fi
		FS_BLOCK=1
		FS_SIG=$(printf '%s' "$_fs_out" | jq -r '[.gates[] | select(.status=="fail") | .name] | join(",")' 2>/dev/null)
		_fs_names=$(printf '%s' "$_fs_out" | jq -r '[.gates[] | select(.status=="fail") | .name] | join(", ")' 2>/dev/null)
		_fs_outputs=$(printf '%s' "$_fs_out" | jq -r '[.gates[] | select(.status=="fail") | (.name + ":\n" + .output)] | join("\n\n")' 2>/dev/null)
		FS_REASON="Gate(s) failed: $_fs_names
$(printf '%s\n' "$_fs_outputs" | head -40)

Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop."
	}

	# _sg_attempt_full_sweep <rewrite-stamp|""> — runs the full sweep. Returns 0
	# when the turn may proceed (nothing to run, no ecosystem and no manifest
	# deletion, or a clean pass); returns 1 and leaves _block/_sig/_reason set
	# when the turn must be blocked. On a clean pass with the rewrite-stamp
	# argument, rewrites the periodic full-sweep timer.
	_sg_attempt_full_sweep() {
		_rewrite=$1
		if [ ! -e "$_check_all" ]; then
			return 0
		fi
		_sg_run_full_sweep
		if [ "$FS_NO_ECOSYSTEM" -eq 1 ]; then
			if _sg_manifest_deleted; then
				_block=1
				_sig="manifest-deleted"
				_reason="the project manifest disappeared this turn; a gate cannot be passed by removing the thing that defines it."
				return 1
			fi
			[ "$_rewrite" = "rewrite_stamp" ] && { date +%s >"$_gates_stamp" 2>/dev/null || true; }
			return 0
		fi
		if [ "$FS_BLOCK" -eq 1 ]; then
			_block=1
			_sig="$FS_SIG"
			_reason="$FS_REASON"
			return 1
		fi
		[ "$_rewrite" = "rewrite_stamp" ] && { date +%s >"$_gates_stamp" 2>/dev/null || true; }
		return 0
	}

	# _sg_run_test_changed — runs `CI=true test-changed --json`. Sets TC_STATUS
	# to green|red|fallthrough, plus TC_REASON/TC_SIG when red.
	_sg_run_test_changed() {
		TC_STATUS="fallthrough"
		TC_REASON=""
		TC_SIG=""
		_tc_out=$(cd "$dir" && CI=true node "$_test_changed" --json 2>/dev/null)
		[ -z "$_tc_out" ] && return 0
		_tc_cmd=$(printf '%s' "$_tc_out" | jq -r '.test_cmd // empty' 2>/dev/null)
		[ -z "$_tc_cmd" ] && return 0
		_tc_passed=$(printf '%s' "$_tc_out" | jq -r '.passed' 2>/dev/null)
		if [ "$_tc_passed" = "true" ]; then
			TC_STATUS="green"
			return 0
		fi
		TC_STATUS="red"
		_tc_exit=$(printf '%s' "$_tc_out" | jq -r '.exit_code // empty' 2>/dev/null)
		_tc_files=$(printf '%s' "$_tc_out" | jq -r '(.test_files // []) | join(", ")' 2>/dev/null)
		TC_SIG="test-changed"
		TC_REASON="Gate failed: test-changed ($_tc_cmd, exit $_tc_exit)
test files: $_tc_files

Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop."
	}

	if [ "$_stop_gate_mode" = "true" ]; then
		if _sg_attempt_full_sweep ""; then hook_ok; fi
	elif [ "$_stop_gate_mode" = "scoped" ]; then
		if [ ! -e "$_test_changed" ]; then
			if _sg_attempt_full_sweep ""; then hook_ok; fi
		else
			_sg_run_test_changed
			case "$TC_STATUS" in
			fallthrough)
				if _sg_attempt_full_sweep ""; then hook_ok; fi
				;;
			red)
				_block=1
				_sig="$TC_SIG"
				_reason="$TC_REASON"
				;;
			green)
				_now=$(date +%s)
				_last=0
				[ -f "$_gates_stamp" ] && _last=$(cat "$_gates_stamp" 2>/dev/null)
				case "$_last" in '' | *[!0-9]*) _last=0 ;; esac
				_elapsed=$((_now - _last))
				if [ "$_elapsed" -gt "$_full_every" ]; then
					if _sg_attempt_full_sweep "rewrite_stamp"; then hook_ok; fi
				else
					hook_ok
				fi
				;;
			esac
		fi
	fi

fi
# --- end C20 guard: skip the mode dispatch above when spec-gate already blocked ---

# Nothing failed (the code above always exits via hook_ok on success).
[ "$_block" -eq 0 ] && hook_ok

# --- wedge valve: the same failure signature blocking 4+ times in this
# session degrades from a JSON block to a plain exit 2. ---
printf '%s\n' "$_sig" >>"$_gatesig_stamp"
_sig_count=$(awk -v want="$_sig" '
  { lines[NR] = $0 }
  END {
    c = 0
    for (i = NR; i >= 1; i--) {
      if (lines[i] == want) { c++ } else { break }
    }
    print c
  }
' "$_gatesig_stamp")
case "$_sig_count" in '' | *[!0-9]*) _sig_count=1 ;; esac

# Second identical block in a session: the same mistake twice is a /lesson
# trigger (a guardrail, not another retry), so say so in the block reason.
# This is the only counter for stop-gate: hookout's generic _lesson_nudge
# skips reasons that already mention /lesson, so the number is never wrong.
if [ "$_sig_count" -ge 2 ]; then
	_reason="$_reason

the same gate blocked this session $_sig_count times: run /lesson to turn it into a test, hook or script before retrying."
fi

if [ "$_sig_count" -ge 4 ]; then
	hook_feedback "$_reason

these gates were already failing before this turn's edits; fix them or say why they are out of scope."
fi

hook_block "$_reason"
