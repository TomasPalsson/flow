#!/usr/bin/env bash
# test_doctor_progress.sh — unit V3 (flow doctor PROGRESS.md checks, C17).
# Sourced by run.sh; every t_v3_* function below is discovered and run.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_cli.sh's CLI_PATH/cli_in having
# been sourced in the same run — it defines its own equivalents below.
set -u

V3_CLI_PATH=""
V3_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
V3_CLI_PATH="$V3_CLI_PATH/bin/.local/bin/flow"; [ -x "$SCAN_DIR/../bin/flow" ] && V3_CLI_PATH="$SCAN_DIR/../bin/flow"

# v3_cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $V3_CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>,
# without touching this test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
v3_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$V3_CLI_PATH" "$@"
}

# ---------------------------------------------------------------------------
# doctor — PROGRESS.md check (C17 delta)
# ---------------------------------------------------------------------------

t_v3_progress_not_a_git_repo_is_pass_skip() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir) # no `git init` — not a git repo

	v3_cli_in "$proj" "$home" doctor --json
	assert_contains "$OUT" '"id": "progress-md"' "t_v3_progress_not_a_git_repo_is_pass_skip check-present"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_not_a_git_repo_is_pass_skip status-pass"
	assert_contains "$OUT" "not a git repo" "t_v3_progress_not_a_git_repo_is_pass_skip names-reason"

	rm -rf "$home" "$proj"
}

t_v3_progress_missing_in_git_repo_warns() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_repo) # git repo, one commit, no PROGRESS.md

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "WARN"' "t_v3_progress_missing_in_git_repo_warns status-warn"
	assert_contains "$OUT" "PROGRESS.md not found" "t_v3_progress_missing_in_git_repo_warns names-not-found"

	rm -rf "$home" "$proj"
}

t_v3_progress_present_well_formed_is_pass() {
	local home proj block today
	home=$(tmp_dir)
	proj=$(tmp_repo)
	today=$(date +%Y-%m-%d)
	cat >"$proj/PROGRESS.md" <<EOF
# Progress

## Now
- doing the thing

## Next
- next thing

## Done
- $today: shipped the thing (abc1234)

## Rulings
- Ruling: none yet — n/a — n/a

## Blocked / open questions
- (none)
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_present_well_formed_is_pass status-pass"

	rm -rf "$home" "$proj"
}

t_v3_progress_over_60_lines_warns() {
	local home proj block i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	{
		printf '# Progress\n\n## Now\n- doing the thing\n\n## Next\n'
		for i in $(seq 1 60); do printf -- '- filler item %s\n' "$i"; done
		printf '\n## Done\n- %s: shipped the thing (abc1234)\n' "$(date +%Y-%m-%d)"
	} >"$proj/PROGRESS.md"

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "WARN"' "t_v3_progress_over_60_lines_warns status-warn"
	assert_contains "$OUT" "lines (> 60 max)" "t_v3_progress_over_60_lines_warns names-line-count"

	rm -rf "$home" "$proj"
}

t_v3_progress_exactly_60_lines_does_not_warn_line_count() {
	# Boundary test: the line-count check is "> 60", so a file totaling
	# exactly 60 lines must PASS with no line-count warning. Guards against
	# an off-by-one in the threshold comparison or the line-counting math.
	local home proj block today filler i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	today=$(date +%Y-%m-%d)
	filler=52 # 6 header lines + filler + 2 footer lines = 60
	{
		printf '# Progress\n\n## Now\n- doing the thing\n\n## Next\n'
		for i in $(seq 1 "$filler"); do printf -- '- filler item %s\n' "$i"; done
		printf '## Done\n- %s: shipped the thing (abc1234)\n' "$today"
	} >"$proj/PROGRESS.md"

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_exactly_60_lines_does_not_warn_line_count status-pass"
	assert_not_contains "$OUT" '> 60 max' "t_v3_progress_exactly_60_lines_does_not_warn_line_count no-line-count-warning"

	rm -rf "$home" "$proj"
}

t_v3_progress_61_lines_warns_line_count() {
	# One line over the 60-line boundary must WARN naming "> 60 max".
	local home proj block today filler i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	today=$(date +%Y-%m-%d)
	filler=53 # 6 header lines + filler + 2 footer lines = 61
	{
		printf '# Progress\n\n## Now\n- doing the thing\n\n## Next\n'
		for i in $(seq 1 "$filler"); do printf -- '- filler item %s\n' "$i"; done
		printf '## Done\n- %s: shipped the thing (abc1234)\n' "$today"
	} >"$proj/PROGRESS.md"

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "WARN"' "t_v3_progress_61_lines_warns_line_count status-warn"
	assert_contains "$OUT" '61 lines (> 60 max)' "t_v3_progress_61_lines_warns_line_count names-line-count"

	rm -rf "$home" "$proj"
}

t_v3_progress_done_bullet_29_days_back_does_not_warn_staleness() {
	# Boundary test: the staleness check is "> 30 days back". A ## Done
	# bullet dated (UTC today - 29 days) must never trigger it, regardless
	# of time-of-day, guarding against a wrong 30-day threshold arithmetic
	# (e.g. an off-by-one day count or a >= instead of > comparison).
	local home proj block d29
	home=$(tmp_dir)
	proj=$(tmp_repo)
	d29=$(python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(days=29)).date().isoformat())")
	cat >"$proj/PROGRESS.md" <<EOF
# Progress

## Now
- doing the thing

## Done
- $d29: shipped the thing (abc1234)
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_done_bullet_29_days_back_does_not_warn_staleness status-pass"
	assert_not_contains "$OUT" '> 30 days back' "t_v3_progress_done_bullet_29_days_back_does_not_warn_staleness no-stale-mention"

	rm -rf "$home" "$proj"
}

t_v3_progress_done_bullet_31_days_back_warns_staleness() {
	# One day past the 29-day-safe zone (31 days back is always > 30 days
	# regardless of time-of-day) must WARN naming the oldest date.
	local home proj block d31
	home=$(tmp_dir)
	proj=$(tmp_repo)
	d31=$(python3 -c "from datetime import datetime,timedelta,timezone; print((datetime.now(timezone.utc)-timedelta(days=31)).date().isoformat())")
	cat >"$proj/PROGRESS.md" <<EOF
# Progress

## Now
- doing the thing

## Done
- $d31: shipped the thing (abc1234)
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "WARN"' "t_v3_progress_done_bullet_31_days_back_warns_staleness status-warn"
	assert_contains "$OUT" "oldest ## Done bullet dated $d31" "t_v3_progress_done_bullet_31_days_back_warns_staleness names-oldest-date"

	rm -rf "$home" "$proj"
}

t_v3_progress_stale_done_bullet_warns_naming_oldest() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_repo)
	cat >"$proj/PROGRESS.md" <<'EOF'
# Progress

## Now
- doing the thing

## Next
- next thing

## Done
- 2020-01-01: ancient thing (aaa1111)
- 2020-06-15: another old thing (bbb2222)

## Rulings
- (none)

## Blocked / open questions
- (none)
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "WARN"' "t_v3_progress_stale_done_bullet_warns_naming_oldest status-warn"
	assert_contains "$OUT" 'oldest ## Done bullet dated 2020-01-01' "t_v3_progress_stale_done_bullet_warns_naming_oldest names-oldest-date"

	rm -rf "$home" "$proj"
}

t_v3_progress_recent_done_bullet_does_not_warn_on_staleness() {
	local home proj block today
	home=$(tmp_dir)
	proj=$(tmp_repo)
	today=$(date +%Y-%m-%d)
	cat >"$proj/PROGRESS.md" <<EOF
# Progress

## Now
- doing the thing

## Done
- $today: shipped the thing (abc1234)
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_recent_done_bullet_does_not_warn_on_staleness status-pass"
	assert_not_contains "$OUT" "> 30 days back" "t_v3_progress_recent_done_bullet_does_not_warn_on_staleness no-stale-mention"

	rm -rf "$home" "$proj"
}

t_v3_progress_bullets_outside_done_section_are_ignored() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_repo)
	# A dated bullet under ## Next (not ## Done) must never trigger the
	# staleness check — only "## Done" bullets are dated-status bullets.
	cat >"$proj/PROGRESS.md" <<'EOF'
# Progress

## Now
- doing the thing

## Next
- 2020-01-01: this looks dated but is not a Done bullet

## Done
EOF

	v3_cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "progress-md"')
	assert_contains "$block" '"status": "PASS"' "t_v3_progress_bullets_outside_done_section_are_ignored status-pass"
	assert_not_contains "$OUT" "> 30 days back" "t_v3_progress_bullets_outside_done_section_are_ignored no-stale-mention"

	rm -rf "$home" "$proj"
}
