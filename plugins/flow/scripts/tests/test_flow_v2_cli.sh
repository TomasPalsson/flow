#!/usr/bin/env bash
# test_flow_v2_cli.sh — the flow v2 subcommands (spec 004 K-C/K-D): use, lint,
# tick, publish, new-spec --current, and the invariant that every command the
# router can print actually resolves to something this plugin ships.
#
# Sourced by run.sh; t_v2_* functions are discovered and run.
set -u

V2_CLI=""
V2_CLI=$(cd "$HERE/../../../.." && pwd -P)
V2_CLI="$V2_CLI/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && V2_CLI="$SCAN_DIR/../bin/flow"
V2_PLUGIN=$(cd "$SCAN_DIR/.." && pwd -P)
V2_NEW_SPEC="$SCAN_DIR/new-spec"

v2_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$V2_CLI" "$@"
}

# v2_repo — a tmp_repo with one feature, one commit past Base, and a TASKS.md
# holding one open task and one ticked task. Echoes "<repo> <base> <sha>".
v2_repo() {
	local d base sha
	d=$(tmp_repo)
	base=$(git -C "$d" rev-parse --short HEAD)
	mkdir -p "$d/.specs/001-x"
	printf '# Spec\n' >"$d/.specs/001-x/spec.md"
	printf '001-x\n' >"$d/.specs/.current"
	(
		cd "$d" || exit 1
		printf 'a\n' >a.py
		git add -A && git commit -qm a
	) >/dev/null 2>&1
	sha=$(git -C "$d" rev-parse --short HEAD)
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		printf 'Approved: 2026-09-08 by user\n'
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [x] T001 done already — files: a.py — verify: `true` — done: %s\n' "$sha"
		printf -- '- [ ] T002 still open — files: b.py — verify: `true`\n'
		printf -- '- [ ] CHK003 a human looks — files: ui.tsx — verify: human: user says yes\n'
		printf '\n## Gates\n- [ ] G001 clean — verify: `true`\n'
	} >"$d/.specs/001-x/TASKS.md"
	printf '%s %s %s' "$d" "$base" "$sha"
}

# ---------------------------------------------------------------------------
# flow use — the pointer is authoritative (11 §6)
# ---------------------------------------------------------------------------

t_v2_use_writes_the_pointer() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a" "$proj/.specs/002-b"
	v2_cli_in "$proj" "$home" use 002-b
	assert_rc 0 "flow use exits 0"
	OUT=$(cat "$proj/.specs/.current")
	assert_eq "$OUT" "002-b" "flow use writes .specs/.current"
	rm -rf "$home" "$proj"
}

t_v2_use_accepts_the_slug_without_its_number() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/003-entry-tagging"
	v2_cli_in "$proj" "$home" use entry-tagging
	assert_rc 0 "flow use <slug> without the NNN- prefix exits 0"
	OUT=$(cat "$proj/.specs/.current")
	assert_eq "$OUT" "003-entry-tagging" "the full NNN-slug is written"
	rm -rf "$home" "$proj"
}

t_v2_use_unknown_feature_names_the_options() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	v2_cli_in "$proj" "$home" use 009-nope
	assert_rc 1 "flow use on a missing feature exits 1"
	assert_contains "$ERR" "fix:" "the failure carries a fix:"
	assert_contains "$ERR" "001-a" "the fix: names what is actually on disk"
	assert_file_missing "$proj/.specs/.current" "a failed use writes no pointer"
	rm -rf "$home" "$proj"
}

t_v2_use_resets_the_call_counter() {
	local home proj i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a" "$proj/.specs/002-b"
	printf '001-a\n' >"$proj/.specs/.current"
	i=0
	while [ "$i" -lt 3 ]; do
		v2_cli_in "$proj" "$home" next >/dev/null 2>&1
		i=$((i + 1))
	done
	v2_cli_in "$proj" "$home" use 002-b
	# --peek: --json counts a real turn (F6), so observing the reset must not
	# be the thing that moves the counter off 0.
	v2_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"consecutive_calls": 0' "switching feature resets the loop counter"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# flow lint — one implementation of the grammar, reached two ways
# ---------------------------------------------------------------------------

t_v2_lint_passes_through_to_flow_lint() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" lint
	assert_rc 0 "flow lint on a valid TASKS.md exits 0"
	assert_contains "$OUT" "OK TASKS.md" "flow lint prints flow-lint's own verdict"
	v2_cli_in "$proj" "$home" lint --waves
	assert_contains "$OUT" "wave 0:" "flow lint --waves reaches the wave computation"
	rm -rf "$home" "$proj"
}

t_v2_lint_exit_1_on_an_error() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	printf -- '- [ ] T004 no verify — files: c.py\n' >>"$proj/.specs/001-x/TASKS.md"
	v2_cli_in "$proj" "$home" lint
	assert_rc 1 "flow lint exits 1 on an ERROR"
	assert_contains "$OUT" "missing-verify" "the rule is named"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# flow tick — K-D, the only writer of [x]
# ---------------------------------------------------------------------------

t_v2_tick_measures_the_sha() {
	local home proj set sha line
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	(
		cd "$proj" || exit 1
		printf 'b\n' >b.py && git add -A && git commit -qm "T002: b"
	) >/dev/null 2>&1
	sha=$(git -C "$proj" log -n 1 --format=%h -- b.py)
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 0 "flow tick on an open task exits 0"
	assert_contains "$OUT" "T002 ticked at $sha" "the receipt names the measured sha"
	line=$(grep '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md")
	assert_contains "$line" "— done: $sha" "the done: sha is appended, not claimed"
	rm -rf "$home" "$proj"
}

t_v2_tick_is_the_only_writer_and_never_double_ticks() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T001
	assert_rc 1 "ticking an already-ticked task exits 1"
	assert_contains "$ERR" "already ticked" "it says why"
	assert_contains "$ERR" "fix:" "and carries a fix:"
	rm -rf "$home" "$proj"
}

t_v2_tick_unknown_id_exits_1() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T099
	assert_rc 1 "ticking a task that is not in the file exits 1"
	assert_contains "$ERR" "not a task" "it says why"
	v2_cli_in "$proj" "$home" tick nonsense
	assert_rc 1 "a malformed id exits 1"
	rm -rf "$home" "$proj"
}

t_v2_tick_refuses_when_nothing_was_committed() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	mkdir -p "$proj/.specs/001-x"
	printf '001-x\n' >"$proj/.specs/.current"
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		printf 'Approved: 2026-09-08 by user\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 a — files: a.py — verify: `true`\n'
	} >"$proj/.specs/001-x/TASKS.md"
	v2_cli_in "$proj" "$home" tick T001
	assert_rc 1 "ticking with HEAD still at Base exits 1"
	assert_contains "$ERR" "nothing was committed" "it says nothing was committed"
	OUT=$(grep -c '^- \[x\]' "$proj/.specs/001-x/TASKS.md" || true)
	assert_eq "$OUT" "0" "and the box stays unchecked"
	rm -rf "$home" "$proj"
}

t_v2_tick_checkpoint_needs_a_human() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick CHK003
	assert_rc 1 "a CHK checkpoint cannot be ticked by the model"
	assert_contains "$ERR" "--by user" "the fix: names the flag only a person supplies"
	v2_cli_in "$proj" "$home" tick CHK003 --by user
	assert_rc 1 "a CHK tick with no evidence in verify/ fails"
	assert_contains "$ERR" "no evidence for CHK003" "it says there is no evidence"
	assert_contains "$ERR" "verify/CHK003" "the fix: names the file to write"
	mkdir -p "$proj/.specs/001-x/verify"
	: >"$proj/.specs/001-x/verify/CHK003.md"
	v2_cli_in "$proj" "$home" tick CHK003 --by user
	assert_rc 1 "an empty evidence file does not count"
	printf 'opened the page, 375px, chip wraps\n' >"$proj/.specs/001-x/verify/CHK003-screenshot.png"
	v2_cli_in "$proj" "$home" tick CHK003 --by user
	assert_rc 0 "flow tick CHK003 --by user exits 0 with a non-empty CHK003-* file"
	OUT=$(grep '^- \[x\] CHK003' "$proj/.specs/001-x/TASKS.md")
	assert_contains "$OUT" "by user" "the checkpoint records who answered it"
	rm -rf "$home" "$proj"
}

t_v2_tick_resets_the_call_counter() {
	local home proj set i
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	(
		cd "$proj" || exit 1
		printf 'b\n' >b.py && git add -A && git commit -qm "T002: b"
	) >/dev/null 2>&1
	i=0
	while [ "$i" -lt 3 ]; do
		v2_cli_in "$proj" "$home" next >/dev/null 2>&1
		i=$((i + 1))
	done
	v2_cli_in "$proj" "$home" tick T002
	# --peek: see the note in t_v2_use_resets_the_call_counter.
	v2_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"consecutive_calls": 0' "a tick is progress, so the loop counter resets"
	rm -rf "$home" "$proj"
}

t_v2_tick_output_passes_the_lint_it_creates() {
	# The tick → lint join is the point: what tick writes must satisfy the rule
	# flow-lint enforces, or the router lands in state 1e immediately after.
	local home proj set sha
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	sha=${set##* }
	v2_cli_in "$proj" "$home" tick T002 --sha "$sha"
	v2_cli_in "$proj" "$home" lint
	assert_rc 1 "T002's commit did not touch b.py, so the lint catches it"
	assert_contains "$OUT" "done-touches-nothing" "the join rule fires on a tick against the wrong commit"
	rm -rf "$home" "$proj"
}

t_v2_tick_refuses_when_its_files_were_never_committed() {
	# BUG: resolveSha() used to fall back to HEAD when no commit since Base
	# touched the task's files:, writing a false "done: <HEAD>" that flow-lint
	# only caught one call later (done-touches-nothing). It must refuse instead.
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 1 "ticking a task whose files: were never committed exits 1"
	assert_contains "$ERR" "b.py" "the message names the untouched files"
	assert_contains "$ERR" "fix:" "and carries a fix:"
	OUT=$(grep -c '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md" || true)
	assert_eq "$OUT" "0" "and TASKS.md is unchanged"
	rm -rf "$home" "$proj"
}

t_v2_tick_by_user_answers_a_task_whose_files_live_outside_the_repo() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002 --by user
	assert_rc 0 "an external T task ticked --by user exits 0"
	OUT=$(grep '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md" || true)
	assert_contains "$OUT" " — done: $(git -C "$proj" rev-parse --short HEAD) by user" "the line records HEAD by user"
	rm -rf "$home" "$proj"
}

t_v2_tick_external_task_without_by_user_points_at_by_user() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 1 "an external T task ticked without --by user still exits 1"
	assert_contains "$ERR" "flow tick T002 --by user" "the fix line names the way out"
	rm -rf "$home" "$proj"
}

t_v2_tick_by_user_is_no_bypass_for_tracked_files() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	sed 's/T002 still open — files: b.py/T002 still open — files: README.md/' "$proj/.specs/001-x/TASKS.md" >"$proj/t.tmp" &&
		mv "$proj/t.tmp" "$proj/.specs/001-x/TASKS.md"
	v2_cli_in "$proj" "$home" tick T002 --by user
	assert_rc 1 "--by user on a task with a tracked file still needs a commit"
	assert_contains "$ERR" "README.md" "the existing message names the file"
	rm -rf "$home" "$proj"
}

# v2_wave_repo — a v2_repo with a parallel wave landed: a commit touching b.py
# (T002's file) and then a later commit touching c.py, so HEAD is not T002's
# commit. Echoes "<repo> <b-sha> <head-sha>".
v2_wave_repo() {
	local set d bsha head
	set=$(v2_repo)
	d=${set%% *}
	(
		cd "$d" || exit 1
		printf 'b\n' >b.py && git add -A && git commit -qm "T002: b"
		printf 'c\n' >c.py && git add -A && git commit -qm "T009: c"
	) >/dev/null 2>&1
	bsha=$(git -C "$d" log -n 1 --format=%h -- b.py)
	head=$(git -C "$d" rev-parse --short HEAD)
	printf '%s %s %s' "$d" "$bsha" "$head"
}

t_v2_tick_records_the_commit_that_touched_its_files_not_head() {
	# After a parallel wave HEAD is another task's commit. Recording HEAD would
	# make the very next `flow next` report lying.
	local home set proj bsha head line
	home=$(tmp_dir)
	set=$(v2_wave_repo)
	proj=${set%% *}
	set=${set#* }
	bsha=${set%% *}
	head=${set##* }
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 0 "flow tick after a wave exits 0"
	assert_contains "$OUT" "T002 ticked at $bsha" "the receipt names T002's own commit"
	assert_not_contains "$OUT" "$head" "not HEAD"
	line=$(grep '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md")
	assert_contains "$line" "— done: $bsha" "done: is the commit that touched b.py"
	v2_cli_in "$proj" "$home" lint
	assert_rc 0 "and the lint join passes"
	rm -rf "$home" "$proj"
}

t_v2_tick_accepts_a_sha_override() {
	local home set proj bsha head base line
	home=$(tmp_dir)
	set=$(v2_wave_repo)
	proj=${set%% *}
	set=${set#* }
	bsha=${set%% *}
	head=${set##* }
	base=$(git -C "$proj" rev-list --max-parents=0 --abbrev-commit HEAD)
	v2_cli_in "$proj" "$home" tick T002 --sha nonesuch
	assert_rc 1 "--sha with an unknown commit exits 1"
	assert_contains "$ERR" "not a commit" "it says why"
	v2_cli_in "$proj" "$home" tick T002 --sha "$base"
	assert_rc 1 "--sha at Base exits 1"
	assert_contains "$ERR" "at or before Base" "it says why"
	v2_cli_in "$proj" "$home" tick T002 --sha "$head"
	assert_rc 0 "--sha with a real commit since Base exits 0"
	line=$(grep '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md")
	assert_contains "$line" "— done: $head" "done: is the given sha, not the one files: would resolve"
	assert_not_contains "$line" "$bsha" "files: resolution did not override --sha"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# flow pass — BUG 1/2: G002's own verify: line, and the CLI door to
# passCovers() so a gate script never has to reimplement the sha join.
# ---------------------------------------------------------------------------

t_v2_pass_exit_codes() {
	local home proj set sha
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	sha=${set##* }
	v2_cli_in "$proj" "$home" pass
	assert_rc 1 "flow pass with no PASS file exits 1"
	assert_contains "$OUT" "no PASS file covers HEAD — run the gates" "and says so"
	printf 'gates green\n' >"$proj/.specs/001-x/PASS-$sha.md"
	v2_cli_in "$proj" "$home" pass
	assert_rc 0 "flow pass exits 0 once a PASS file covers HEAD"
	assert_contains "$OUT" "PASS-$sha.md covers HEAD" "and names the covering file"
	rm -rf "$home" "$proj"
}

t_v2_pass_resolves_the_feature_the_same_way_next_does() {
	# flow pass must reuse resolveFeature, not guess a feature of its own — a
	# repo with no .specs/.current and no matching branch has nothing to check.
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a" "$proj/.specs/002-b"
	v2_cli_in "$proj" "$home" pass
	assert_rc 1 "flow pass with no resolvable feature exits 1"
	assert_contains "$OUT" "no PASS file covers HEAD" "and reports no covering PASS rather than crashing"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# flow publish — an optional leaf, never on the pipeline
# ---------------------------------------------------------------------------

t_v2_publish_dry_run_lists_open_tasks_only() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" publish --dry-run
	assert_rc 0 "flow publish --dry-run exits 0"
	assert_contains "$OUT" "T002 still open" "an unchecked task would be mirrored"
	assert_not_contains "$OUT" "T001" "a ticked task is not mirrored"
	assert_not_contains "$OUT" "G001" "a gate is not an issue"
	rm -rf "$home" "$proj"
}

t_v2_publish_is_never_named_by_the_router() {
	# 11 §3.1: "Never called by the pipeline." A router that can print it would
	# put GitHub back on the critical path.
	OUT=$(grep -c 'flow publish' "$V2_PLUGIN/bin/lib/router.js" || true)
	assert_eq "$OUT" "0" "the router never names flow publish"
}

# ---------------------------------------------------------------------------
# new-spec --current
# ---------------------------------------------------------------------------

t_v2_new_spec_current_writes_the_pointer() {
	local proj
	proj=$(tmp_repo)
	OUT=$(cd "$proj" && bash "$V2_NEW_SPEC" "Entry tagging" --current --no-branch 2>&1)
	assert_file_exists "$proj/.specs/.current" "new-spec --current writes .specs/.current"
	OUT=$(cat "$proj/.specs/.current")
	assert_eq "$OUT" "001-entry-tagging" "the pointer names the dir it just made"
	rm -rf "$proj"
}

t_v2_new_spec_without_current_writes_no_pointer() {
	local proj
	proj=$(tmp_repo)
	(cd "$proj" && bash "$V2_NEW_SPEC" "Entry tagging" --no-branch) >/dev/null 2>&1
	assert_file_missing "$proj/.specs/.current" "new-spec without --current leaves the pointer alone"
	rm -rf "$proj"
}

# ---------------------------------------------------------------------------
# the invariant: flow next never prints a command the plugin does not ship
# ---------------------------------------------------------------------------

t_v2_every_router_command_resolves() {
	# 11 §6, "flow next prints a command the plugin does not ship": today's
	# router emits `agents <path>` and `/wrap then /ship`. Every literal the new
	# one can print is checked here against what is actually installed.
	local cmds c head bad known
	known=$(grep -o "^const COMMANDS = \[[^]]*\]" "$V2_PLUGIN/bin/flow" | tr -d "'[]" | tr ',' ' ')
	# every second argument of an mk(...) call, plus the two loop-active answers
	cmds=$(grep -oE "mk\('[a-z-]+', '[^']+'" "$V2_PLUGIN/bin/lib/router.js" |
		sed -e "s/.*, '//" -e "s/'$//" | sort -u)
	cmds="$cmds
flow loop run
flow loop status"
	bad=""
	while IFS= read -r c; do
		[ -z "$c" ] && continue
		case "$c" in
		# the two human gates and the checkpoint print an instruction, not a
		# command; they are flagged human_gate:true and tested in test_next.sh
		read\ *) continue ;;
		git\ * | gh\ *) continue ;;
		/flow:*)
			head=${c#/flow:}
			head=${head%% *}
			[ -d "$V2_PLUGIN/skills/$head" ] || bad="$bad $c"
			continue
			;;
		flow\ *)
			head=${c#flow }
			head=${head%% *}
			case " $known " in
			*" $head "*) ;;
			*) bad="$bad $c" ;;
			esac
			continue
			;;
		esac
		bad="$bad $c"
	done <<EOF
$cmds
EOF
	assert_eq "$bad" "" "every command the router can print is a shipped subcommand, a shipped skill, or git/gh"
}

t_v2_subcommands_are_all_dispatched() {
	# A name in COMMANDS with no dispatch line would suggest itself in the
	# "did you mean" list and then fail.
	local c bad known
	known=$(grep -o "^const COMMANDS = \[[^]]*\]" "$V2_PLUGIN/bin/flow" | tr -d "'[]" | tr ',' ' ' | sed 's/^const COMMANDS = //')
	bad=""
	for c in $known; do
		case "$c" in
		const | COMMANDS | '=' | '[' | ']') continue ;;
		esac
		grep -q "cmd === '$c'" "$V2_PLUGIN/bin/flow" || bad="$bad $c"
	done
	assert_eq "$bad" "" "every name in COMMANDS has a dispatch line"
}

t_v2_doctor_reports_the_router_state() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	v2_cli_in "$proj" "$home" doctor
	assert_contains "$OUT" "specs-state" "flow doctor reports the router state"
	assert_contains "$OUT" "building" "and names the state it computed"
	rm -rf "$home" "$proj"
}

t_v2_doctor_fails_on_an_invalid_tasks_file() {
	local home proj set
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	printf -- '- [ ] T004 no verify — files: c.py\n' >>"$proj/.specs/001-x/TASKS.md"
	v2_cli_in "$proj" "$home" doctor
	assert_contains "$OUT" "specs-state" "the check still runs"
	assert_contains "$OUT" "FAIL" "an invalid TASKS.md is a doctor FAIL, not a PASS"
	rm -rf "$home" "$proj"
}

t_v2_review_dir_is_gitignored() {
	# K-A: review/ holds generated diffs and must never become a predicate.
	local root
	root=$(cd "$V2_PLUGIN/../.." && pwd -P)
	OUT=$(grep -c '^\.specs/\*/review/$' "$root/.gitignore" || true)
	assert_eq "$OUT" "1" ".gitignore excludes .specs/*/review/"
}

# ---------------------------------------------------------------------------
# famous-borrows F01 — flow tick runs the task's verify: and ticks only on exit 0.
# ---------------------------------------------------------------------------

# v2_verify_repo <verify-text> — a v2_wave_repo whose T002 carries <verify-text>
# (written verbatim after "verify: "). Echoes "<repo> <b-sha> <head-sha>".
v2_verify_repo() {
	local set d
	set=$(v2_wave_repo)
	d=${set%% *}
	awk -v v="$1" '{ if (index($0, "T002 still open")) print "- [ ] T002 still open — files: b.py — verify: " v; else print }' \
		"$d/.specs/001-x/TASKS.md" >"$d/t.tmp" && mv "$d/t.tmp" "$d/.specs/001-x/TASKS.md"
	printf '%s' "$set"
}

t_v2_tick_failing_verify_leaves_tasks_byte_identical() {
	local home set proj before after
	home=$(tmp_dir)
	set=$(v2_verify_repo '`echo oops; false`')
	proj=${set%% *}
	before=$(cksum <"$proj/.specs/001-x/TASKS.md")
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 1 "a verify: that exits non-zero refuses the tick"
	assert_contains "$ERR" "verify exited 1; T002 NOT ticked" "the message names the exit code and the task"
	assert_contains "$ERR" "oops" "the tail of the log is printed"
	assert_contains "$ERR" "verify/T002.log" "the message names the log path"
	after=$(cksum <"$proj/.specs/001-x/TASKS.md")
	assert_eq "$after" "$before" "TASKS.md is byte-identical after a refused tick"
	assert_contains "$(grep '^- \[ \] T002' "$proj/.specs/001-x/TASKS.md")" "- [ ] T002" "T002 stays open"
	assert_file_exists "$proj/.specs/001-x/verify/T002.log" "the log is written even on failure"
	rm -rf "$home" "$proj"
}

t_v2_tick_passing_verify_ticks_and_writes_a_log() {
	local home set proj
	home=$(tmp_dir)
	set=$(v2_verify_repo '`true`')
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 0 "a verify: that exits 0 ticks"
	assert_contains "$(grep '^- \[x\] T002' "$proj/.specs/001-x/TASKS.md")" "— done:" "T002 is ticked"
	assert_file_exists "$proj/.specs/001-x/verify/T002.log" "the log exists even when the verify prints nothing"
	rm -rf "$home" "$proj"
}

t_v2_tick_runs_a_backtick_wrapped_verify_unwrapped_from_the_repo_root() {
	local home set proj
	home=$(tmp_dir)
	set=$(v2_verify_repo '`pwd > ran.flag && test -f b.py`')
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 0 "the backticks are stripped, so the command runs"
	assert_file_exists "$proj/ran.flag" "the verify ran"
	assert_eq "$(cat "$proj/ran.flag")" "$(cd "$proj" && pwd -P)" "from the repo root"
	rm -rf "$home" "$proj"
}

t_v2_tick_sha_override_does_not_bypass_the_verify() {
	local home set proj head
	home=$(tmp_dir)
	set=$(v2_verify_repo '`false`')
	proj=${set%% *}
	head=${set##* }
	v2_cli_in "$proj" "$home" tick T002 --sha "$head"
	assert_rc 1 "--sha still runs the verify and refuses on failure"
	assert_contains "$ERR" "NOT ticked" "and says so"
	rm -rf "$home" "$proj"
}

t_v2_tick_human_verify_on_a_task_is_not_runnable() {
	local home set proj
	home=$(tmp_dir)
	set=$(v2_verify_repo 'human: user says yes')
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 1 "a T### with a human: verify is refused"
	assert_contains "$ERR" "no runnable verify:" "the message says why"
	rm -rf "$home" "$proj"
}

t_v2_tick_by_user_external_task_never_runs_its_verify() {
	local home set proj
	home=$(tmp_dir)
	set=$(v2_repo)
	proj=${set%% *}
	awk '{ if (index($0, "T002 still open")) print "- [ ] T002 still open — files: b.py — verify: `touch ran.flag`"; else print }' \
		"$proj/.specs/001-x/TASKS.md" >"$proj/t.tmp" && mv "$proj/t.tmp" "$proj/.specs/001-x/TASKS.md"
	v2_cli_in "$proj" "$home" tick T002 --by user
	assert_rc 0 "an external task ticked --by user exits 0"
	assert_file_missing "$proj/ran.flag" "its verify: was never executed"
	rm -rf "$home" "$proj"
}

t_v2_tick_failure_prints_only_the_last_twenty_log_lines() {
	local home set proj
	home=$(tmp_dir)
	set=$(v2_verify_repo '`i=1; while [ $i -le 30 ]; do echo row$i; i=$((i+1)); done; false`')
	proj=${set%% *}
	v2_cli_in "$proj" "$home" tick T002
	assert_rc 1 "a noisy failing verify is refused"
	assert_contains "$ERR" "row30" "the last log line is shown"
	assert_contains "$ERR" "row11" "the 20th line from the end is shown"
	assert_not_contains "$ERR" "row10" "earlier lines are not"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# famous-borrows F02 — a PASS file dated on/after PASS_EXECUTED_FROM carries the
# Executed column and a "Not checked:" line, and no test row at 0.
# ---------------------------------------------------------------------------

# v2_pass_repo <date> <pass-body> — a v2_repo with PASS-abc1234.md committed on
# <date>. Echoes the repo path.
v2_pass_repo() {
	local set d
	set=$(v2_repo)
	d=${set%% *}
	printf '%s\n' "$2" >"$d/.specs/001-x/PASS-abc1234.md"
	(
		cd "$d" || exit 1
		git add -A
		GIT_COMMITTER_DATE="$1T12:00:00" GIT_AUTHOR_DATE="$1T12:00:00" git commit -qm "pass"
	) >/dev/null 2>&1
	printf '%s' "$d"
}

_V2_PASS_GOOD='| Gate | Command | Exit | Executed |
|------|---------|------|----------|
| test | pytest -q | 0 | 12 |
| lint | ruff check | 0 | n/a |

Not checked: none'

t_v2_lint_new_pass_with_executed_column_is_clean() {
	local home d
	home=$(tmp_dir)
	d=$(v2_pass_repo 2026-10-20 "$_V2_PASS_GOOD")
	v2_cli_in "$d" "$home" lint
	assert_rc 0 "a complete new PASS file lints clean"
	assert_not_contains "$OUT" "pass-" "no pass rule fires"
	rm -rf "$home" "$d"
}

t_v2_lint_new_pass_without_executed_column_errors() {
	local home d
	home=$(tmp_dir)
	d=$(v2_pass_repo 2026-10-20 '| Gate | Command | Exit |
|------|---------|------|
| test | pytest -q | 0 |

Not checked: none')
	v2_cli_in "$d" "$home" lint
	assert_rc 1 "a new PASS file with no Executed column is an ERROR"
	assert_contains "$OUT" "pass-executed-missing" "rule name"
	assert_contains "$OUT" "fix:" "carries a fix"
	rm -rf "$home" "$d"
}

t_v2_lint_new_pass_with_zero_executed_test_row_errors() {
	local home d
	home=$(tmp_dir)
	d=$(v2_pass_repo 2026-10-20 '| Gate | Command | Exit | Executed |
|------|---------|------|----------|
| test | cargo test | 0 | 0 |
| lint | ruff check | 0 | n/a |

Not checked: none')
	v2_cli_in "$d" "$home" lint
	assert_rc 1 "a test row with Executed 0 is an ERROR"
	assert_contains "$OUT" "pass-executed-zero" "rule name"
	rm -rf "$home" "$d"
}

t_v2_lint_new_pass_without_not_checked_line_errors() {
	local home d
	home=$(tmp_dir)
	d=$(v2_pass_repo 2026-10-20 '| Gate | Command | Exit | Executed |
|------|---------|------|----------|
| test | pytest -q | 0 | 3 |')
	v2_cli_in "$d" "$home" lint
	assert_rc 1 "a new PASS file with no Not checked: line is an ERROR"
	assert_contains "$OUT" "pass-not-checked-missing" "rule name"
	rm -rf "$home" "$d"
}

t_v2_lint_old_dated_pass_without_executed_is_accepted() {
	local home d
	home=$(tmp_dir)
	d=$(v2_pass_repo 2026-10-01 '| Gate | Command | Exit |
|------|---------|------|
| test | pytest -q | 0 |')
	v2_cli_in "$d" "$home" lint
	assert_rc 0 "a PASS file dated before PASS_EXECUTED_FROM is spared"
	assert_not_contains "$OUT" "pass-" "no pass rule fires"
	rm -rf "$home" "$d"
}

# v2_two_pass <good-name> <good-date> <bad-name> <bad-date>: two committed PASS
# files, one complete and one lacking the Executed column.
v2_two_pass() {
	local set d
	set=$(v2_repo)
	d=${set%% *}
	printf '%s\n' "$_V2_PASS_GOOD" >"$d/.specs/001-x/$1"
	printf '| Gate | Command | Exit |\n|---|---|---|\n| test | pytest -q | 0 |\n' >"$d/.specs/001-x/$3"
	(
		cd "$d" || exit 1
		git add ".specs/001-x/$1"
		GIT_COMMITTER_DATE="$2T12:00:00" GIT_AUTHOR_DATE="$2T12:00:00" git commit -qm "good"
		git add ".specs/001-x/$3"
		GIT_COMMITTER_DATE="$4T12:00:00" GIT_AUTHOR_DATE="$4T12:00:00" git commit -qm "bad"
	) >/dev/null 2>&1
	printf '%s' "$d"
}

t_v2_lint_checks_newest_dated_pass_not_alphabetically_last() {
	local home d
	home=$(tmp_dir)
	d=$(v2_two_pass PASS-fffffff.md 2026-10-19 PASS-1111bbb.md 2026-10-21)
	v2_cli_in "$d" "$home" lint
	assert_rc 1 "a newer bad PASS is checked even though an older one sorts later"
	assert_contains "$OUT" "pass-executed-missing" "rule name"
	rm -rf "$home" "$d"
}

t_v2_lint_ignores_superseded_bad_pass_with_larger_sha() {
	local home d
	home=$(tmp_dir)
	d=$(v2_two_pass PASS-0000aaa.md 2026-10-21 PASS-fffffff.md 2026-10-19)
	v2_cli_in "$d" "$home" lint
	assert_not_contains "$OUT" "pass-executed-missing" "the superseded bad PASS is not flagged"
	rm -rf "$home" "$d"
}

t_v2_next_skill_pins_pass_table_and_tick_runs_verify() {
	local nx ex
	nx=$(cat "$SCAN_DIR/../skills/next/SKILL.md")
	ex=$(cat "$SCAN_DIR/../skills/next/execution-prompt.md")
	assert_contains "$nx" '`| Gate | Command | Exit | Executed |`' "PASS table gains Executed"
	assert_contains "$nx" "Not checked: <gate: reason>" "PASS carries a Not checked line"
	assert_contains "$nx" "A test gate with Executed 0 is not green" "Executed 0 is not green"
	assert_contains "$nx" "The tick runs the verify." "the tick runs the verify"
	assert_contains "$nx" "verify/<ID>.log" "the tick log is named"
	assert_contains "$ex" "fails the test; a test never skips because its data is absent" "missing fixture fails, never skips"
}
