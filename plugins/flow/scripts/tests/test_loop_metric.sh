#!/usr/bin/env bash
# test_loop_metric.sh — `flow loop init --metric`: the hillclimb form of a
# loop (keep a change only when the number moves past noise, otherwise undo it
# with `git revert`, never a hard reset). Tests: bin/lib/loop/metric.js.
#
# Self-contained for TEST_ONLY runs: defines its own CLI helpers.
set -u

LM_CLI_PATH=""
LM_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
LM_CLI_PATH="$LM_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && LM_CLI_PATH="$SCAN_DIR/../bin/flow"
LM_LOOP_LIB="$SCAN_DIR/../bin/lib/loop"

lm_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$LM_CLI_PATH" "$@"
}

# lm_repo — a clean repo whose committed score.txt holds 3.
lm_repo() {
	local d
	d=$(tmp_repo)
	printf '3\n' >"$d/score.txt"
	(cd "$d" && git add score.txt && git commit -q -m "score 3") >/dev/null 2>&1
	printf '%s' "$d"
}

# lm_edit <proj> <value> <message> — commit score.txt = value.
lm_edit() {
	printf '%s\n' "$2" >"$1/score.txt"
	(cd "$1" && git add score.txt && git commit -q -m "$3") >/dev/null 2>&1
}

t_loop_metric_keeps_improvement_reverts_worsening() {
	local proj home rows reverts
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "raise the score" --metric "cat score.txt" --direction max --runs 3 --min-attempts 2
	assert_rc 0 "t_loop_metric_keeps_improvement_reverts_worsening init rc"

	lm_edit "$proj" 5 "try five"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "5" "t_loop_metric_keeps_improvement_reverts_worsening improvement kept"

	lm_edit "$proj" 2 "try two"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "5" "t_loop_metric_keeps_improvement_reverts_worsening worsening undone"
	reverts=$(cd "$proj" && git log --format=%s | grep -c '^Revert "try two"')
	assert_eq "$reverts" "1" "t_loop_metric_keeps_improvement_reverts_worsening revert commit exists"
	assert_contains "$(cd "$proj" && git log --format=%s)" "try two" "t_loop_metric_keeps_improvement_reverts_worsening attempt stays in history"

	rows=$(grep -c . "$proj/.claude/loop/decisions.tsv")
	assert_eq "$rows" "3" "t_loop_metric_keeps_improvement_reverts_worsening header plus two rows"
	assert_contains "$(sed -n 2p "$proj/.claude/loop/decisions.tsv")" "try five	3	5	2	yes" "t_loop_metric_keeps_improvement_reverts_worsening kept row"
	assert_contains "$(sed -n 3p "$proj/.claude/loop/decisions.tsv")" "try two	5	2	-3	no" "t_loop_metric_keeps_improvement_reverts_worsening rejected row"
	rm -rf "$home" "$proj"
}

t_loop_metric_min_direction() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "lower the score" --metric "cat score.txt" --direction min --runs 1
	lm_edit "$proj" 1 "lower"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "1" "t_loop_metric_min_direction lower is kept"
	lm_edit "$proj" 4 "higher"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "1" "t_loop_metric_min_direction higher is undone"
	rm -rf "$home" "$proj"
}

t_loop_metric_noise_recorded_from_init_spread() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	# Three runs read 0, 1, 2 from a counter kept inside .git: spread 2, median 1.
	lm_cli_in "$proj" "$home" loop init "noisy" --direction max --runs 3 \
		--metric 'c=$(cat "$(git rev-parse --git-dir)/cnt" 2>/dev/null || echo 0); echo $((c+1)) >"$(git rev-parse --git-dir)/cnt"; echo $((c%3))'
	assert_rc 0 "t_loop_metric_noise_recorded_from_init_spread init rc"
	grep -q '^metric_noise: 2$' "$proj/.claude/loop/loop.md"
	assert_rc 0 "t_loop_metric_noise_recorded_from_init_spread noise recorded as the init spread"
	rm -rf "$home" "$proj"
}

t_loop_metric_spread_above_target_refuses_init() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "too noisy" --direction max --runs 3 --target 15 \
		--metric 'c=$(cat "$(git rev-parse --git-dir)/cnt" 2>/dev/null || echo 0); echo $((c+1)) >"$(git rev-parse --git-dir)/cnt"; echo $((c*10))'
	assert_eq "$RC" "1" "t_loop_metric_spread_above_target_refuses_init rc"
	assert_contains "$ERR" "exceeds the distance to the target" "t_loop_metric_spread_above_target_refuses_init reason"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_loop_metric_spread_above_target_refuses_init nothing armed"
	rm -rf "$home" "$proj"
}

t_loop_metric_no_number_refuses_init() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "no number" --direction max --metric "echo hello"
	assert_eq "$RC" "1" "t_loop_metric_no_number_refuses_init rc"
	assert_contains "$ERR" "printed no number" "t_loop_metric_no_number_refuses_init reason"
	rm -rf "$home" "$proj"
}

t_loop_metric_dirty_tree_refuses_init() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	printf 'wip\n' >"$proj/scratch.txt"
	lm_cli_in "$proj" "$home" loop init "dirty" --direction max --metric "cat score.txt"
	assert_eq "$RC" "1" "t_loop_metric_dirty_tree_refuses_init rc"
	assert_contains "$ERR" "dirty" "t_loop_metric_dirty_tree_refuses_init reason"
	rm -rf "$home" "$proj"
}

t_loop_metric_dirty_tree_refuses_run() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "dirty run" --direction max --metric "cat score.txt" --shape fresh
	printf 'wip\n' >"$proj/scratch.txt"
	mkdir -p "$home/bin"
	printf '#!/bin/sh\nexit 0\n' >"$home/bin/claude"
	chmod +x "$home/bin/claude"
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$2/bin:$PATH"; node "$3" loop run' _ "$proj" "$home" "$LM_CLI_PATH"
	assert_eq "$RC" "1" "t_loop_metric_dirty_tree_refuses_run rc"
	assert_contains "$ERR" "dirty" "t_loop_metric_dirty_tree_refuses_run reason"
	rm -rf "$home" "$proj"
}

t_loop_metric_gate_red_rejects_improvement() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "gated" --direction max --runs 1 --metric "cat score.txt" --verify "test ! -f broken.txt"
	assert_rc 0 "t_loop_metric_gate_red_rejects_improvement init rc"
	printf 'x\n' >"$proj/broken.txt"
	printf '9\n' >"$proj/score.txt"
	(cd "$proj" && git add -A && git commit -q -m "better but broken") >/dev/null 2>&1
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "3" "t_loop_metric_gate_red_rejects_improvement undone"
	assert_file_missing "$proj/broken.txt" "t_loop_metric_gate_red_rejects_improvement gate-breaking file gone"
	assert_contains "$(sed -n 2p "$proj/.claude/loop/decisions.tsv")" "better but broken	3	9	6	no" "t_loop_metric_gate_red_rejects_improvement row"
	rm -rf "$home" "$proj"
}

t_loop_metric_uncommitted_edit_is_committed_then_judged() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "wip" --direction max --runs 1 --metric "cat score.txt"
	printf '1\n' >"$proj/score.txt"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_eq "$(cat "$proj/score.txt")" "3" "t_loop_metric_uncommitted_edit_is_committed_then_judged undone"
	assert_eq "$(cd "$proj" && git status --porcelain | grep -v '^??' | wc -l | tr -d ' ')" "0" "t_loop_metric_uncommitted_edit_is_committed_then_judged tree clean"
	rm -rf "$home" "$proj"
}

t_loop_metric_target_reached_is_done_after_min_attempts() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "reach" --direction max --runs 1 --min-attempts 2 --target 8 --metric "cat score.txt"
	assert_rc 0 "t_loop_metric_target_reached_is_done_after_min_attempts init rc"
	lm_edit "$proj" 9 "jump"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_metric_target_reached_is_done_after_min_attempts target met but under min-attempts"
	lm_edit "$proj" 10 "more"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"status": "done"' "t_loop_metric_target_reached_is_done_after_min_attempts done at min-attempts"
	rm -rf "$home" "$proj"
}

t_loop_metric_three_rejects_pivot_note() {
	local proj home i
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "pivot" --direction max --runs 1 --min-attempts 9 --metric "cat score.txt"
	for i in 1 2 3; do
		lm_edit "$proj" "$((3 - i))" "worse $i"
		lm_cli_in "$proj" "$home" loop tick --json
	done
	assert_contains "$OUT" "decisions.tsv" "t_loop_metric_three_rejects_pivot_note prompt points at the tsv"
	assert_contains "$OUT" "pivot to a different category" "t_loop_metric_three_rejects_pivot_note pivot after 3 rejects"
	rm -rf "$home" "$proj"
}

t_loop_metric_commit_failure_stops_with_named_reason() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "hook" --direction max --runs 1 --metric "cat score.txt"
	assert_rc 0 "t_loop_metric_commit_failure_stops_with_named_reason init rc"
	printf '#!/bin/sh\necho lint-rejected >&2\nexit 1\n' >"$proj/.git/hooks/pre-commit"
	chmod +x "$proj/.git/hooks/pre-commit"
	printf '9\n' >"$proj/score.txt"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "finish"' "t_loop_metric_commit_failure_stops_with_named_reason finishes"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "stop_reason: commit-failed" "t_loop_metric_commit_failure_stops_with_named_reason reason"
	assert_contains "$OUT$ERR" "lint-rejected" "t_loop_metric_commit_failure_stops_with_named_reason stderr tail shown"
	rm -rf "$home" "$proj"
}

t_loop_metric_init_refuses_when_metric_dirties_tree() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "artifact" --direction max --runs 1 --metric "cat score.txt | tee metric.out"
	assert_eq "$RC" "1" "t_loop_metric_init_refuses_when_metric_dirties_tree rc"
	assert_contains "$ERR" "metric.out" "t_loop_metric_init_refuses_when_metric_dirties_tree names the file"
	assert_contains "$ERR" "gitignore" "t_loop_metric_init_refuses_when_metric_dirties_tree says gitignore"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_loop_metric_init_refuses_when_metric_dirties_tree nothing armed"
	rm -rf "$home" "$proj"
}

t_loop_metric_tick_stops_when_metric_dirties_tree() {
	local proj home
	proj=$(lm_repo)
	home=$(tmp_dir)
	lm_cli_in "$proj" "$home" loop init "artifact2" --direction max --runs 1 --metric "cat score.txt; [ -f .git/arm ] && echo x >out.txt; true"
	assert_rc 0 "t_loop_metric_tick_stops_when_metric_dirties_tree init rc"
	: >"$proj/.git/arm"
	lm_edit "$proj" 9 "better"
	lm_cli_in "$proj" "$home" loop tick --json
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "stop_reason: metric-wrote-files" "t_loop_metric_tick_stops_when_metric_dirties_tree reason"
	assert_file_missing "$proj/.claude/loop/decisions.tsv" "t_loop_metric_tick_stops_when_metric_dirties_tree no fake row"
	rm -rf "$home" "$proj"
}

t_loop_metric_no_hard_reset_in_loop_lib() {
	local hits
	hits=$(grep -rn 'reset --hard\|"reset"' "$LM_LOOP_LIB" "$SCAN_DIR/../bin/lib/loop.js" 2>/dev/null | wc -l | tr -d ' ')
	assert_eq "$hits" "0" "t_loop_metric_no_hard_reset_in_loop_lib"
}

t_loop_metric_help_names_the_flags() {
	local home
	home=$(tmp_dir)
	lm_cli_in "$home" "$home" loop init --metric --help
	assert_rc 0 "t_loop_metric_help_names_the_flags rc"
	assert_contains "$OUT" "--direction max|min" "t_loop_metric_help_names_the_flags direction"
	assert_contains "$OUT" "--min-attempts" "t_loop_metric_help_names_the_flags min-attempts"
	rm -rf "$home"
}
