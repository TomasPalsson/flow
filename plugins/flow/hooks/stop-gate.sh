#!/usr/bin/env bash
# stop-gate.sh — Stop hook. Exact behaviour: SPEC C10 (decision table R0-R16).
#
# Refuses to end a turn while THIS turn's change set is verifiably red, and
# says so out loud whenever it could not check. First match wins:
#
#   R0 stop_hook_active / CC_NO_STOP_GATE / flow.off / not a git tree → silent
#   R1 stopGate outside {true,false,"scoped"} → note, the gate did not run
#   R2 background tasks still running → note · R3 nothing changed → silent
#   R4 docs/config only (flow-lint iff the active TASKS.md changed) → silent
#   K-E an [x] in the active TASKS.md with no "— done:" sha → block
#   R5 source changed, no ecosystem → note once a session
#   R6 the root manifest is gone and the root was written this turn → block
#   R7 a gate could not run (missing tool, crash) → note, names the fix
#   R8-R10  scoped run over this turn's files: green → silent, red → block
#   R11-R13 a sweep is due (commits since the last one) → check-all --json
#   R9/R12 a red proven older than this turn → note, no block
#   R14 third identical block → soft · R15 fourth → release · R16 over budget
#
# "Cannot judge" is never "pass": every allow that skipped a check says so.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
# shellcheck source=lib/specgate.sh
. "$HERE/lib/specgate.sh"
hook_skip_if_off # `flow off` wrote .claude/flow.off here: no judging hooks

_started=$(date +%s)

# --- R0 ------------------------------------------------------------------
[ "$(hook_field '.stop_hook_active')" = "true" ] && hook_ok
[ "${CC_NO_STOP_GATE:-}" = "1" ] && hook_ok
dir=$(hook_project_dir)
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

_tmp="${TMPDIR:-/tmp}"
_tmp="${_tmp%/}"
_toplevel=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -z "$_toplevel" ] && _toplevel="$dir"
_repo_base=$(basename "$_toplevel")
_hash_num=$(printf '%s' "$_toplevel" | cksum | awk '{print $1}')
_hash8=$(printf '%s' "$_hash_num" | tail -c 8)
_branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$_branch" ] && _branch="detached"
_branch_safe=$(printf '%s' "$_branch" | tr -c 'A-Za-z0-9_-' '_')
# FU-24: the sweep stamp holds the sha the last sweep ran at, not a clock.
_sweep_stamp="$_tmp/claude-gates-${_repo_base}-${_hash8}"
_baseline="$_tmp/claude-baseline-${_repo_base}-${_branch_safe}"

_NOWEAKEN="Do not delete, skip, xfail, or weaken a test to make this pass, and do not lower a threshold in config. If a check is genuinely inapplicable here, say so explicitly and stop."
_HATCH="(escape: CC_NO_STOP_GATE=1 for this session, stopGate:false in .claude/flow.config.json, or ask the user to run the gate.)"

# _sg_q <text> — <text> as ONE single-quoted shell word. Every command this
# hook prints must be runnable as printed, including from a directory whose
# path contains a space or a quote.
_sg_q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
_dirq=$(_sg_q "$dir")

# _sg_clip <gate output> — the output block of a block reason: at most 25 lines
# AND at most 300 characters per line, so the whole reason stays well under the
# platform's hook-output cap. The two load-bearing parts (the no-weakening
# sentence and the reproduce command) are printed AFTER this block, and an
# unbounded gate — one 200-column line per assertion, say — would push exactly
# those past the cap. Says so when it dropped anything: a clipped block
# presented as the full output is a claim the hook cannot back.
_sg_clip() {
	_cl_n=$(printf '%s\n' "$1" | grep -c '')
	_cl_max=$(printf '%s\n' "$1" | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')
	printf '%s\n' "$1" | head -25 | cut -c1-300
	if [ "$_cl_n" -gt 25 ] || [ "$_cl_max" -gt 300 ]; then
		printf '… (clipped here to 25 lines x 300 chars — this is not all of it)\n'
	fi
}

_budget=$(hook_config stopGateBudgetSec)
case "$_budget" in '' | *[!0-9]*) _budget=150 ;; esac

# _sg_over_budget — rc 0 once this hook has spent its wall-clock budget (R16).
_sg_over_budget() {
	_ob_now=$(date +%s)
	[ $((_ob_now - _started)) -ge "$_budget" ]
}

# _sg_release_over_budget <clause> — R16: end the turn saying what the budget
# cost. Checked BEFORE a phase starts (it never began) and again AFTER one that
# would block (it ran long, so its verdict is not enforced): the knob bounds
# the turn, not just the number of phases.
_sg_release_over_budget() {
	hook_note "stop gate exceeded its ${_budget}s budget: $1 Run: cd $_dirq && flow check"
}

# _sg_finish <sig> <name> <reason> — the R14/R15 ladder. First two IDENTICAL
# blocks block; the third is soft (no hook-error styling); the fourth and later
# end the turn with a note that states nothing was verified.
#
# <sig> is the failure's identity, not the gate's: a signature counted per gate
# family would let a brand-new regression inherit an older failure's count and
# walk out soft on its first ever block. Every caller folds the failing ids into
# it. <name> is the readable half, and the only one a message shows.
_sg_finish() {
	_fi_n=$(hook_count "stop-gate:$1")
	case "$_fi_n" in '' | *[!0-9]*) _fi_n=1 ;; esac
	if [ "$_fi_n" -ge 4 ]; then
		hook_note "ending the turn with $2 still red after $_fi_n blocks this session. Nothing was verified. Run: cd $_dirq && flow check"
	fi
	if [ "$_fi_n" -eq 3 ]; then
		hook_soft "$3

This is the 3rd identical block this session. Fix it, or state why it is out of scope and stop."
	fi
	hook_block "$3"
}

# _sg_in_list <needle> <newline-separated list> — rc 0 on an exact line match.
_sg_in_list() { printf '%s\n' "$2" | grep -q -x -F -e "$1"; }

# _sg_disjoint <newline-separated paths> — rc 0 when THIS turn's change set
# shares no file with <paths>. An empty <paths> is disjoint from everything.
_sg_disjoint() {
	_dj_prev=$1
	while IFS= read -r _dj_p; do
		[ -z "$_dj_p" ] && continue
		_sg_in_list "$_dj_p" "$_dj_prev" && return 1
	done <<EOF
$_rel_changed
EOF
	return 0
}

# _sg_baseline <newline-separated ids> — the R9/R12 record for this repo+branch
# at this HEAD, and BL_KNOWN=1 when every id in it is a failure THIS turn
# cannot have caused. That is only provable one way: the id was recorded red at
# the end of an EARLIER turn whose change set shares no file with this one (or
# it was already confirmed that way at this HEAD, which stays true until HEAD
# moves). A red first seen in a turn that touched the code under it is this
# turn's to answer for, and goes up the R10 -> R14 -> R15 ladder instead.
# File: line 1 the HEAD sha, then "D <path>" (last observation's change set),
# "O <id>" (last observation's red ids), "B <id>" (ids confirmed pre-existing).
_sg_baseline() {
	_bl_ids=$1
	_bl_head=$(git -C "$dir" rev-parse HEAD 2>/dev/null)
	[ -z "$_bl_head" ] && _bl_head="nohead"
	_bl_prev_d=""
	_bl_prev_o=""
	_bl_conf=""
	if [ -f "$_baseline" ] && [ "$(sed -n '1p' "$_baseline" 2>/dev/null)" = "$_bl_head" ]; then
		_bl_body=$(tail -n +2 "$_baseline" 2>/dev/null)
		_bl_prev_d=$(printf '%s\n' "$_bl_body" | sed -n 's/^D //p')
		_bl_prev_o=$(printf '%s\n' "$_bl_body" | sed -n 's/^O //p')
		_bl_conf=$(printf '%s\n' "$_bl_body" | sed -n 's/^B //p')
	fi
	_bl_older=0
	_sg_disjoint "$_bl_prev_d" && _bl_older=1
	BL_KNOWN=0
	_bl_any=0
	while IFS= read -r _bl_id; do
		[ -z "$_bl_id" ] && continue
		[ "$_bl_any" -eq 0 ] && BL_KNOWN=1
		_bl_any=1
		if _sg_in_list "$_bl_id" "$_bl_conf"; then continue; fi
		if [ "$_bl_older" -eq 1 ] && _sg_in_list "$_bl_id" "$_bl_prev_o"; then
			_bl_conf="$_bl_conf
$_bl_id"
			continue
		fi
		BL_KNOWN=0
	done <<EOF
$_bl_ids
EOF
	{
		printf '%s\n' "$_bl_head"
		printf '%s\n' "$_rel_changed" | sed -n 's/^\(..*\)$/D \1/p'
		printf '%s\n' "$_bl_ids" | sed -n 's/^\(..*\)$/O \1/p'
		printf '%s\n' "$_bl_conf" | sed -n 's/^\(..*\)$/B \1/p'
	} >"$_baseline" 2>/dev/null || true
}

# _sg_red <name> <ids> <reason> — one red verdict, filtered through the
# baseline: failures proven to predate this turn end it with a note (R9/R12),
# everything else goes up the block ladder (R10/R13). The ladder counts <name>
# TOGETHER WITH the failing ids, so "the lint gate is red" twice never softens
# the first block of a different failure in the same gate.
_sg_red() {
	_sg_baseline "$2"
	if [ "$BL_KNOWN" -eq 1 ]; then
		hook_note "$(printf '%s' "$2" | grep -c .) failing check(s) were already failing before this turn ($1): they were red at the end of an earlier turn that touched none of the files you changed this turn. Not blocking; not fixed either."
	fi
	_sg_finish "$1|$(printf '%s\n' "$2" | sort | tr '\n' ',')" "$1" "$3"
}

# --- R1: an unrecognised stopGate is loud, never a silent default ---------
_mode=$(hook_config stopGate)
case "$_mode" in
'') _mode="scoped" ;;
true | false | scoped) ;;
*) hook_note "stopGate=\"$_mode\" in .claude/flow.config.json is not true | false | \"scoped\" — the gate did not run this turn. Fix: set stopGate to one of those three." ;;
esac

# --- R2: work still in flight is not a turn to gate -----------------------
_bg=$(hook_field '.background_tasks')
case "$_bg" in
'' | '[]' | '{}' | 'null') ;;
*)
	_bg_n=$(printf '%s' "$_bg" | jq -r 'if type=="array" then length else 1 end' 2>/dev/null)
	case "$_bg_n" in '' | *[!0-9]*) _bg_n=1 ;; esac
	_bg_kinds=$(printf '%s' "$_bg" | jq -r '[.[]? | (.description? // .type? // .status? // "task") | tostring] | unique | join(", ")' 2>/dev/null)
	[ -z "$_bg_kinds" ] && _bg_kinds="unnamed"
	hook_note "$_bg_n background task(s) still running ($_bg_kinds) — the gate did not run this turn; what they change is unverified."
	;;
esac

# --- Δ: what THIS turn changed (C3/B6/FU-04) ------------------------------
# find-newer over the turn stamp only. git status is consulted for exactly one
# thing below (a manifest that disappeared), because a repo that was dirty
# before the turn started is not this turn's doing. No turn stamp = no turn to
# scope to = nothing to gate.
_changed=$(hook_changed_since "$(hook_stamp_path)")
_porcelain=$(git -C "$dir" status --porcelain 2>/dev/null)

# _sg_rel <abs> — one project-relative path per line.
_sg_rel() {
	case "$1" in
	"$dir"/*) printf '%s\n' "${1#"$dir"/}" ;;
	*) printf '%s\n' "$1" ;;
	esac
}

_rel_changed=$(
	while IFS= read -r _f; do
		[ -n "$_f" ] && _sg_rel "$_f"
	done <<EOF
$_changed
EOF
)

# _sg_manifest_gone — rc 0 when git status shows a ROOT project manifest that
# disappeared: a plain delete, or a rename whose OLD side was the manifest (a
# rename whose NEW side is one CREATES it). Exact basename: package.json.orig
# never counts. Names it in MG_NAME.
#
# The index is not the working tree, so the porcelain line alone never proves
# the manifest is gone: `git mv package.json package.json.bak` followed by a
# fresh package.json, or `git rm --cached package.json`, both report a delete
# while the manifest sits right there. R6 exists to catch a gate dodged by
# removing what defines it; a manifest still on disk removed nothing, so a
# path that still holds a REGULAR FILE is skipped here rather than blocked on a
# false claim. A regular file and nothing else: `git rm package.json && mkdir
# package.json` leaves an inode at the path but no manifest, and that is the
# dodge this row exists to catch.
_sg_manifest_gone() {
	_mg=1
	MG_NAME=""
	while IFS= read -r _mg_line; do
		[ -z "$_mg_line" ] && continue
		_mg_st=${_mg_line:0:2}
		_mg_path=${_mg_line:3}
		case "$_mg_st" in
		*R*) _mg_path=${_mg_path%% -> *} ;;
		*D*) : ;;
		*) continue ;;
		esac
		case "$_mg_path" in
		\"*\") _mg_path=${_mg_path#\"} && _mg_path=${_mg_path%\"} ;;
		esac
		case "$_mg_path" in */*) continue ;; esac
		case "$_mg_path" in
		package.json | pyproject.toml | Cargo.toml | go.mod | deno.json)
			[ -f "$dir/$_mg_path" ] && continue
			_mg=0
			[ -z "$MG_NAME" ] && MG_NAME="$_mg_path"
			;;
		esac
	done <<EOF
$_porcelain
EOF
	return "$_mg"
}

# _sg_root_touched — rc 0 when the project root DIRECTORY itself is newer than
# the turn stamp. Removing a file rewrites its parent directory, so this is the
# evidence that a deletion git reports could have happened during this turn;
# without it, `git status` alone cannot date the deletion at all (B6/FU-04).
_sg_root_touched() {
	_rt_stamp=$(hook_stamp_path)
	[ -f "$_rt_stamp" ] || return 1
	[ -n "$(find "$dir" -maxdepth 0 -newer "$_rt_stamp" 2>/dev/null)" ]
}

_manifest_gone=0
if _sg_manifest_gone && _sg_root_touched; then _manifest_gone=1; fi

# --- R3: nothing changed under this turn ---------------------------------
# A deleted manifest is a change no find-newer walk can see, so it is the one
# thing that keeps an otherwise empty turn in the gate.
[ -z "$_changed" ] && [ "$_manifest_gone" -eq 0 ] && hook_ok

# --- what this turn touched: the tasks file, the docs, the source ---------
_tasks=$(_sg_tasks_path "$dir")
_tasks_rel=$(_sg_rel "$_tasks")
_tasks_changed=0
_source_changed=0
_source_example=""
_docs_only=1
while IFS= read -r _rel; do
	[ -z "$_rel" ] && continue
	[ "$_rel" = "$_tasks_rel" ] && _tasks_changed=1
	case "$_rel" in
	*.md | *.mdx | *.txt | *.rst | *.adoc | docs/* | .specs/* | .claude/*) ;;
	*) _docs_only=0 ;;
	esac
	if _sg20_is_source "$_rel"; then
		_source_changed=1
		[ -z "$_source_example" ] && _source_example="$_rel"
	fi
done <<EOF
$_rel_changed
EOF

# --- C20 spec gate: no source change without an approved plan ------------
if [ "$_source_changed" -eq 1 ] && _sg_require_spec_active "$dir" &&
	! _sg_approved_tasks_ok "$_tasks"; then
	_sg_finish "spec-gate:c20" "the spec gate" "Spec gate: $_source_example changed this turn and this branch ($_branch) requires an approved plan, but $(_sg_lint_objection "$_tasks" "$_tasks_rel")
Nothing verified that change against a plan.
(escape: set requireSpec:false in .claude/flow.config.json, CC_NO_SPEC_GATE=1 for this session, or ask the user to approve the plan.)"
fi

# stopGate:false switches off the test/lint ladder below; per C20 it never
# switches off the spec gate above.
[ "$_mode" = "false" ] && hook_ok

# --- R6 ------------------------------------------------------------------
if [ "$_manifest_gone" -eq 1 ]; then
	_sg_finish "manifest-deleted:$MG_NAME" "the deleted $MG_NAME" "the project manifest $MG_NAME is gone from the working tree and the project root was written during this turn; a gate cannot be passed by removing the thing that defines it.
$_HATCH"
fi

# --- R4: TASKS.md is the one doc this gate reads --------------------------
# flow-lint runs only for the ACTIVE feature's TASKS.md, and only when this turn
# touched it: a stale TASKS.md left behind by another feature is not this turn's
# problem, and the lint is not cheap enough to pay for on every turn.
# It is a stop-gate row (10 §5 R4), not the C20 spec gate — so it sits BELOW the
# stopGate:false exit above and prints the stop gate's hatches. CC_NO_SPEC_GATE
# does not silence it and the message must not pretend otherwise.
#
# The reproduce line names the resolved flow-lint by absolute path: the script
# ships in the plugin's scripts/ dir and is not on PATH, so a bare `flow-lint`
# would be printed as a command that exits 127.
if [ "$_tasks_changed" -eq 1 ] && [ -f "$_tasks" ]; then
	_flow_lint_check "$_tasks"
	if [ "$FL_AVAILABLE" -eq 1 ] && [ "$FL_OK" -ne 0 ]; then
		_sg_finish "flow-lint:$_tasks_rel" "flow-lint ($_tasks_rel)" "Gate failed: flow-lint ($_tasks_rel)
$(_sg_clip "$FL_OUT")

$_NOWEAKEN
To reproduce: cd $_dirq && bash $(_sg_q "$(_fl_resolve)") $(_sg_q "$_tasks_rel")
$_HATCH"
	fi
fi

# --- K-E(1): a tick with no measured sha is not a tick --------------------
# `flow tick <ID>` is the only writer of `[x]` and it appends the sha it
# MEASURED, so a checked box with no `— done:` is a box someone typed — the
# honour system this whole grammar exists to replace. One fence-aware awk pass
# over the active TASKS.md, so it costs nothing to check every turn; it sits
# below the `stopGate:false` exit and prints the stop gate's hatches, both of
# which really do escape it.
_sha_less=$(_sg_sha_less_tick "$_tasks")
if [ -n "$_sha_less" ]; then
	_sg_finish "tick-no-sha:$_sha_less" "the sha-less tick $_sha_less" "$_tasks_rel marks $_sha_less as [x] with no '— done: <sha>'. flow tick is the only writer of [x] and it records the sha it measured, so nothing here proves that work landed.
fix: run flow tick $_sha_less (uncheck the box first — tick refuses an ID that is already checked)
$_HATCH"
fi

# --- R4: docs and config only — nothing for a test runner to say ---------
[ "$_docs_only" -eq 1 ] && hook_ok

# --- R7 (tools): a gate that cannot run is never a pass -------------------
_shared="${CC_SHARED_SCRIPTS:-$HERE/../skills/shared/scripts}"
_check_all="$_shared/check-all"
_test_changed="$_shared/test-changed"

# _sg_note_once <key> <msg> — the once-a-session half of R5: "this project has
# nothing to run" is a standing property of the repo, so say it once rather
# than on every turn. A MISSING TOOL is not routed through here: it leaves the
# turn unverified, and a silent unverified turn is exactly what this hook
# exists to prevent, so R7 notes fire every time.
_sg_note_once() {
	hook_once "$1" || hook_ok
	hook_note "$2"
}

if [ ! -e "$_check_all" ] && [ ! -e "$_test_changed" ]; then
	hook_note "gate could not run — neither check-all nor test-changed is in $_shared. Gates were NOT checked this turn. Fix: run 'flow install', or set CC_SHARED_SCRIPTS to the directory that holds them."
fi
have node || hook_note "gate could not run — node is not on PATH, and check-all/test-changed are node scripts. Gates were NOT checked this turn. Fix: install node, or set stopGate:false in .claude/flow.config.json."
have jq || hook_note "gate could not run — jq is not on PATH, so this hook cannot read the gates' JSON. Gates were NOT checked this turn. Fix: install jq, or set stopGate:false in .claude/flow.config.json."

# _sg_json_ok <text> — rc 0 when <text> is one parseable JSON object.
_sg_json_ok() { printf '%s' "$1" | jq -e 'type == "object"' >/dev/null 2>&1; }

# --- the sweep (R5, R11-R13) ---------------------------------------------
# _sg_sweep — CI=true check-all --json --continue, so the test gate runs even
# when lint or format is red (C-C). Sets SW_STATE to
# none|no-ecosystem|no-gates|crashed|pass|fail plus SW_* details. "pass" means
# at least one gate actually ran and was green: a manifest whose every gate is
# "skipped" verified nothing and must not be reported as checked.
_sg_sweep() {
	SW_STATE="none"
	SW_NAMES=""
	SW_IDS=""
	SW_OUTPUT=""
	SW_CMD=""
	[ -e "$_check_all" ] || return 0
	_sw_out=$(cd "$dir" && CI=true node "$_check_all" --json --continue 2>/dev/null)
	_sw_rc=$?
	# The stamp records that a sweep RAN, whatever it found (FU-24).
	git -C "$dir" rev-parse HEAD >"$_sweep_stamp" 2>/dev/null || true
	if ! _sg_json_ok "$_sw_out"; then
		SW_STATE="crashed"
		SW_CMD="cd $_dirq && node $(_sg_q "$_check_all") --json --continue"
		SW_OUTPUT="exit $_sw_rc, no parseable JSON on stdout"
		return 0
	fi
	if [ -z "$(printf '%s' "$_sw_out" | jq -r '.ecosystem // empty' 2>/dev/null)" ]; then
		SW_STATE="no-ecosystem"
		SW_OUTPUT=$(printf '%s' "$_sw_out" | jq -r '.message // empty' 2>/dev/null)
		return 0
	fi
	SW_NAMES=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="fail") | .name] | join(", ")' 2>/dev/null)
	if [ -n "$SW_NAMES" ]; then
		SW_STATE="fail"
		SW_IDS=$(printf '%s' "$_sw_out" | jq -r '.gates[]? | select(.status=="fail") | "gate:" + .name' 2>/dev/null)
		SW_OUTPUT=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="fail") | (.name + ":\n" + (.output // ""))] | join("\n")' 2>/dev/null)
		SW_CMD=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="fail") | .cmd // empty] | first // empty' 2>/dev/null)
		[ -n "$SW_CMD" ] || SW_CMD="node $(_sg_q "$_check_all") --continue"
		return 0
	fi
	_sw_un=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="unavailable") | .name] | join(", ")' 2>/dev/null)
	if [ -n "$_sw_un" ]; then
		SW_STATE="crashed"
		SW_CMD=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="unavailable") | .cmd // empty] | first // empty' 2>/dev/null)
		[ -n "$SW_CMD" ] || SW_CMD="node $(_sg_q "$_check_all") --continue"
		SW_OUTPUT="gate(s) $_sw_un could not be executed"
		return 0
	fi
	_sw_ran=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | select(.status=="pass")] | length' 2>/dev/null)
	case "$_sw_ran" in '' | *[!0-9]*) _sw_ran=0 ;; esac
	if [ "$_sw_ran" -eq 0 ]; then
		SW_STATE="no-gates"
		SW_NAMES=$(printf '%s' "$_sw_out" | jq -r '[.gates[]? | .name] | join(", ")' 2>/dev/null)
		SW_OUTPUT=$(printf '%s' "$_sw_out" | jq -r '.ecosystem // "unknown"' 2>/dev/null)
		return 0
	fi
	SW_STATE="pass"
}

# _sg_run_sweep — the sweep plus its verdicts (R5/R7/R12/R13).
_sg_run_sweep() {
	_sg_over_budget && _sg_release_over_budget "the full sweep was still to run and was cut short, so gates were NOT verified this turn."
	_sg_sweep
	case "$SW_STATE" in
	none)
		# test-changed exists but check-all does not: there is no sweep to
		# fall back on, and this turn would otherwise end verified by nothing.
		hook_note "gate could not run — check-all is not in $_shared, so the full sweep could not run and nothing else verified this turn. Fix: run 'flow install', or set CC_SHARED_SCRIPTS to the directory that holds check-all."
		;;
	no-ecosystem)
		[ "$_source_changed" -eq 1 ] || hook_ok
		_sg_note_once "stop-gate-no-ecosystem" "no test/lint ecosystem here — source changed this turn and nothing verified it. Fix: add a test script (package.json / pyproject.toml / Cargo.toml / go.mod), or run 'flow init'."
		;;
	no-gates)
		[ "$_source_changed" -eq 1 ] || hook_ok
		_sg_note_once "stop-gate-no-gates" "no gate ran here — this is a $SW_OUTPUT project, but check-all skipped every gate ($SW_NAMES): there is no test or lint script to run. Source changed this turn and nothing verified it. Fix: add a test script to the manifest, or run 'flow init'."
		;;
	crashed)
		hook_note "gate could not run — check-all in $dir: $SW_OUTPUT. Gates were NOT checked this turn. Fix: $SW_CMD"
		;;
	fail)
		_sg_over_budget && _sg_release_over_budget "the full sweep overran it, so its red result ($SW_NAMES) is not enforced this turn and nothing was verified in time."
		_sg_red "$SW_NAMES" "$SW_IDS" "Gate(s) failed: $SW_NAMES
$(_sg_clip "$SW_OUTPUT")

$_NOWEAKEN
To reproduce: cd $_dirq && $SW_CMD
$_HATCH"
		;;
	esac
	hook_ok
}

# _sg_sweep_due — rc 0 when a full sweep is owed: never swept this repo, or
# HEAD moved since the last sweep (R11: commits, not the clock — a clock stamp
# is absent on the first Stop of every session, so it swept far too often).
_sg_sweep_due() {
	[ -f "$_sweep_stamp" ] || return 0
	_sd_sha=$(sed -n '1p' "$_sweep_stamp" 2>/dev/null)
	case "$_sd_sha" in '' | *[!0-9a-f]*) return 0 ;; esac
	_sd_n=$(git -C "$dir" rev-list --count "$_sd_sha..HEAD" 2>/dev/null)
	case "$_sd_n" in '' | *[!0-9]*) return 0 ;; esac
	[ "$_sd_n" -ge 1 ]
}

[ "$_mode" = "true" ] && _sg_run_sweep

# --- R8-R10: the scoped run over exactly this turn's files ---------------
if [ ! -e "$_test_changed" ]; then _sg_run_sweep; fi
_sg_over_budget && _sg_release_over_budget "the scoped test run was still to run and was cut short, so gates were NOT verified this turn."

_tc_out=$(cd "$dir" && CI=true CC_CHANGED_FILES="$_rel_changed" node "$_test_changed" --json 2>/dev/null)
if ! _sg_json_ok "$_tc_out"; then
	hook_note "gate could not run — test-changed in $dir printed no parseable JSON. Gates were NOT checked this turn. Fix: cd $_dirq && node $(_sg_q "$_test_changed") --json"
fi
_tc_status=$(printf '%s' "$_tc_out" | jq -r '.status // empty' 2>/dev/null)
_tc_cmd=$(printf '%s' "$_tc_out" | jq -r '.test_cmd // empty' 2>/dev/null)

case "$_tc_status" in
unavailable)
	# A resolved command that could not be executed is R7; no command at all
	# means "no test runner configured here", which is the sweep's call (R5's).
	[ -n "$_tc_cmd" ] || _sg_run_sweep
	hook_note "gate could not run — $(printf '%s' "$_tc_out" | jq -r '.message // "test-changed could not execute the runner"' 2>/dev/null). Gates were NOT checked this turn. Fix: cd $_dirq && $_tc_cmd"
	;;
ran)
	if [ "$(printf '%s' "$_tc_out" | jq -r '.passed' 2>/dev/null)" != "true" ]; then
		_sg_over_budget && _sg_release_over_budget "the scoped test run overran it, so its red result is not enforced this turn and nothing was verified in time."
		_tc_files=$(printf '%s' "$_tc_out" | jq -r '(.test_files // []) | join(", ")' 2>/dev/null)
		_tc_ids=$(printf '%s' "$_tc_out" | jq -r 'if ((.test_files // []) | length) > 0 then (.test_files[] | "test:" + .) else "test:" + (.test_cmd // "suite") end' 2>/dev/null)
		_sg_red "test-changed" "$_tc_ids" "Gate failed: test-changed ($_tc_cmd, exit $(printf '%s' "$_tc_out" | jq -r '.exit_code // empty' 2>/dev/null))
test files: $(_sg_clip "$_tc_files")
$(_sg_clip "$(printf '%s' "$_tc_out" | jq -r '.message // empty' 2>/dev/null)")

$_NOWEAKEN
To reproduce: cd $_dirq && $_tc_cmd
$_HATCH"
	fi
	# R8/R11: the scoped run verified something and it was green. A sweep is
	# owed only once per commit, so a clean turn stays silent and fast.
	_sg_sweep_due && _sg_run_sweep
	;;
*)
	# no-tests: the runner resolved nothing for these files, so nothing was
	# verified. Silence is reserved for checked-and-green, so sweep — this is
	# also where a repo with no ecosystem at all lands (R5).
	_sg_run_sweep
	;;
esac

hook_ok
