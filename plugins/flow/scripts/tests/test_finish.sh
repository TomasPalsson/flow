#!/usr/bin/env bash
# test_finish.sh — `flow finish` (on/off/status/check --hook) and the router's
# `finish` field, over fixture .specs/ trees in a tmp_repo.
#
# Sourced by run.sh; every t_finish_* function below is discovered and run.
# Self-contained: TEST_ONLY can restrict a run to this one file.
set -u

FIN_CLI_PATH="$SCAN_DIR/../bin/flow"

# fin_cli_in <project-dir> <home-dir> <args...> — run the CLI with cwd=<dir>.
fin_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$FIN_CLI_PATH" "$@"
}

# fin_building <repo> — an approved feature with one unchecked task: `building`.
fin_building() {
	local repo=$1 base
	base=$(git -C "$repo" rev-parse --short HEAD)
	mkdir -p "$repo/.specs/001-x"
	printf '# Spec\n' >"$repo/.specs/001-x/spec.md"
	printf '001-x\n' >"$repo/.specs/.current"
	{
		printf '# Tasks — fixture\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		printf 'Approved: 2026-09-08 by user\n'
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf '%s\n' '- [ ] T001 first — files: a.py — verify: `true`'
	} >"$repo/.specs/001-x/TASKS.md"
}

t_finish_on_off_status() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish status
	assert_rc 0 "status exits 0"
	assert_contains "$OUT" "finish: not armed" "status says not armed"
	assert_contains "$OUT" "state: building" "status names the router state"
	fin_cli_in "$proj" "$home" finish on --note "I approve everything"
	assert_rc 0 "on exits 0"
	assert_contains "$OUT" "finish: armed for .specs/001-x — flow finish off disarms" "on says what it armed"
	assert_file_exists "$proj/.specs/001-x/FINISH.md" "on writes FINISH.md"
	assert_contains "$(cat "$proj/.specs/001-x/FINISH.md")" "# Finish mode — 001-x" "FINISH.md header names the feature"
	assert_contains "$(cat "$proj/.specs/001-x/FINISH.md")" "Note: I approve everything" "FINISH.md keeps the user's words"
	assert_contains "$(cat "$proj/.specs/001-x/FINISH.md")" "Never pre-approved: evidence" "FINISH.md says evidence is never pre-approved"
	fin_cli_in "$proj" "$home" finish on
	assert_rc 0 "second on exits 0"
	assert_contains "$OUT" "finish: already armed for .specs/001-x" "second on leaves it armed"
	assert_contains "$(cat "$proj/.specs/001-x/FINISH.md")" "Note: I approve everything" "second on does not rewrite the file"
	fin_cli_in "$proj" "$home" finish status --json
	assert_contains "$OUT" '"armed": true' "status --json reports armed"
	fin_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"finish"' "router json carries the finish field"
	assert_contains "$OUT" '"armed": true' "router reports the feature armed"
	assert_contains "$OUT" '.specs/001-x/FINISH.md' "router names the FINISH.md path"
	fin_cli_in "$proj" "$home" finish off
	assert_rc 0 "off exits 0"
	assert_contains "$OUT" "finish: disarmed .specs/001-x" "off says disarmed"
	assert_file_missing "$proj/.specs/001-x/FINISH.md" "off deletes FINISH.md"
	fin_cli_in "$proj" "$home" finish off
	assert_rc 0 "off when not armed exits 0"
	assert_contains "$OUT" "finish: not armed" "off when not armed says so"
	fin_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"armed": false' "router reports disarmed after off"
	rm -rf "$home" "$proj"
}

t_finish_on_without_feature_fails_with_fix() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_cli_in "$proj" "$home" finish on
	assert_rc 1 "on with no active feature exits 1"
	assert_contains "$ERR" "flow finish: no active feature (" "stderr names the problem"
	assert_contains "$ERR" "fix: flow use <NNN-slug>" "stderr carries the fix line"
	rm -rf "$home" "$proj"
}

t_finish_unknown_subcommand_exits_2() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_cli_in "$proj" "$home" finish bogus
	assert_rc 2 "unknown subcommand exits 2"
	assert_contains "$ERR" "usage: flow finish" "unknown subcommand prints usage"
	rm -rf "$home" "$proj"
}

t_finish_check_silent_when_unarmed() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish check --hook --session s1
	assert_rc 0 "unarmed check exits 0"
	assert_eq "$OUT" "" "unarmed check prints nothing"
	rm -rf "$home" "$proj"
}

t_finish_check_blocks_in_building() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish on
	fin_cli_in "$proj" "$home" finish check --hook --session s1
	assert_rc 0 "check exits 0 even when blocking"
	assert_eq "$(printf '%s' "$OUT" | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);process.stdout.write(j.decision)})')" "block" "stdout is one JSON object with decision=block"
	assert_contains "$OUT" "001-x is at building" "reason names the feature and state"
	assert_contains "$OUT" "SKILL.md §Finish" "reason points at the skill section"
	assert_file_exists "$proj/.specs/001-x/.finish-blocks" "the block counter is written"
	rm -rf "$home" "$proj"
}

t_finish_check_releases_after_three_identical_blocks() {
	local home proj i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish on
	for i in 1 2 3; do
		fin_cli_in "$proj" "$home" finish check --hook
		assert_contains "$OUT" '"decision":"block"' "identical call $i still blocks"
	done
	fin_cli_in "$proj" "$home" finish check --hook
	assert_rc 0 "4th identical call exits 0"
	assert_eq "$OUT" "" "4th identical call prints nothing (the model is stuck)"
	assert_file_exists "$proj/.specs/001-x/FINISH.md" "release keeps FINISH.md armed"
	rm -rf "$home" "$proj"
}

t_finish_check_silent_and_disarms_when_done() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-x" # nothing in it: idle
	printf '001-x\n' >"$proj/.specs/.current"
	fin_cli_in "$proj" "$home" finish on --dir .specs/001-x
	assert_file_exists "$proj/.specs/001-x/FINISH.md" "armed via --dir"
	fin_cli_in "$proj" "$home" finish check --hook
	assert_rc 0 "done check exits 0"
	assert_eq "$OUT" "" "done check prints nothing"
	assert_file_missing "$proj/.specs/001-x/FINISH.md" "a done state auto-disarms"
	rm -rf "$home" "$proj"
}

t_finish_check_silent_on_hard_stop_and_stays_armed() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish on
	printf 'the migration corrupts prod rows\n' >"$proj/.specs/BLOCKED.md"
	fin_cli_in "$proj" "$home" finish check --hook
	assert_rc 0 "hard-stop check exits 0"
	assert_eq "$OUT" "" "hard-stop check prints nothing"
	assert_file_exists "$proj/.specs/001-x/FINISH.md" "a hard stop keeps FINISH.md armed"
	rm -rf "$home" "$proj"
}

t_finish_status_does_not_move_the_loop_counter() {
	local home proj before after
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" next --json
	before=$(cat "$proj/.specs/.next-call-count")
	fin_cli_in "$proj" "$home" finish status
	fin_cli_in "$proj" "$home" finish status --json
	fin_cli_in "$proj" "$home" finish on
	fin_cli_in "$proj" "$home" finish check --hook
	after=$(cat "$proj/.specs/.next-call-count")
	assert_eq "$after" "$before" "status/check leave .next-call-count untouched"
	rm -rf "$home" "$proj"
}

t_finish_extra_files_do_not_trip_flow_lint() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	fin_cli_in "$proj" "$home" finish on
	fin_cli_in "$proj" "$home" finish check --hook
	assert_file_exists "$proj/.specs/001-x/.finish-blocks" "both marker files present"
	fin_cli_in "$proj" "$home" lint
	assert_rc 0 "flow lint ignores FINISH.md and .finish-blocks"
	rm -rf "$home" "$proj"
}

# --- --finish rules 5, 8 and 9 in skills/next/SKILL.md ----------------------
FIN_SKILL_MD="${NX_SKILL_PATH:-$SCAN_DIR/../skills/next/SKILL.md}"

t_finish_pause_rule_names_finish_off_and_excludes_keep_going() {
	local txt rule
	txt=$(cat "$FIN_SKILL_MD")
	rule=$(printf '%s\n' "$txt" | grep '^8\. \*\*Pause on request')
	assert_contains "$rule" "\`flow finish off\`" "pause disarms with flow finish off"
	assert_contains "$rule" "\"keep going\" and \"I'm leaving\" are not pauses" "keep going and leaving are not pauses"
	assert_contains "$rule" "wip: <task> (tree may be red)" "wip commit message"
	assert_contains "$rule" "Do not push and do not open a PR" "no push, no PR"
	assert_contains "$rule" "- Ruling: paused at <state> by user — resume with /flow:next --finish" "ruling line"
	assert_contains "$rule" "\`stop-gate\`" "states which gate still fires"
	assert_contains "$rule" "CC_NO_STOP_GATE=1" "and its escape"
}

t_finish_acceptance_rows_go_through_claim_check_before_verified() {
	local rule
	rule=$(grep '^5\. `unverified`' "$FIN_SKILL_MD")
	assert_contains "$rule" "spawn the \`claim-check\` agent" "claim-check is spawned"
	assert_contains "$rule" "verify/claim-check.md" "output path is named"
	assert_contains "$rule" "UNSUPPORTED is unmet" "unsupported row is unmet"
	assert_contains "$rule" "INCONCLUSIVE and NOT-CHECKABLE rows go into the final report" "inconclusive rows reported"
}

t_finish_done_rule_audits_the_transcript_before_finish_off() {
	local rule
	rule=$(grep '^9\. \*\*Done' "$FIN_SKILL_MD")
	assert_contains "$rule" "before \`flow finish off\`" "audit precedes disarm"
	assert_contains "$rule" "model: sonnet" "audit agent model"
	assert_contains "$rule" "~/.claude/projects/<cwd-slug>/*.jsonl" "transcript location"
	assert_contains "$rule" "every character that is not a letter or digit" "slug replaces dots and underscores too"
	assert_contains "$rule" "no transcript is found" "missing transcript is reported, not silent"
	assert_contains "$rule" "- Assumption: <what> — evidence: transcript:<line> (audit)" "audit line format"
	assert_contains "$rule" "never edit an existing line" "append-only"
}

t_finish_audit_assumption_line_reaches_the_digest() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	fin_building "$proj"
	printf '# Notes\n- Assumption: picked left-pad over a hand-rolled pad — evidence: transcript:412 (audit)\n' >"$proj/.specs/001-x/NOTES.md"
	fin_cli_in "$proj" "$home" digest
	assert_rc 0 "digest exits 0"
	assert_contains "$OUT" "NOTES.md:2 Assumption: picked left-pad over a hand-rolled pad [evidence: transcript:412 (audit)]" "audit line shows in the Attention list"
	fin_cli_in "$proj" "$home" finish on
	fin_cli_in "$proj" "$home" finish off
	assert_contains "$OUT" "transcript:412 (audit)" "finish off carries it too"
	rm -rf "$home" "$proj"
}
