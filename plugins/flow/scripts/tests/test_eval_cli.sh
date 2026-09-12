#!/usr/bin/env bash
# test_eval_cli.sh — Slice 5 (.claude/slices/5-brief.md) tests for
# `flow eval` (plugins/flow/bin/lib/eval.js, bin/lib/eval/contract.js),
# bin/flow's eval dispatch/help/doctor row, and loop/init.js's --test-files.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_cli.sh's CLI_PATH/cli_in having
# been sourced in the same run — it defines its own equivalents below
# (matching test_loop.sh's convention).
set -u

EV_CLI_PATH=""
EV_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
EV_CLI_PATH="$EV_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && EV_CLI_PATH="$SCAN_DIR/../bin/flow"

EV_FIXTURES="$HERE/fixtures/eval"

# ev_cli_in <project-dir> <home-dir> <harness-args...> — inherits this
# runner's PATH, so the real `claude` (and the real absence of `socat`) on
# the machine running the suite is what these tests see, matching the
# spec's own assumption (7.1: no socat here; claude >= 2.1.269 available).
ev_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; unset DOTFILES; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$EV_CLI_PATH" "$@"
}

# ev_cli_bare_in <project-dir> <home-dir> <harness-args...> — PATH stripped
# to /bin only: no `claude`, no `socat`, deterministic regardless of what a
# developer happens to have installed.
ev_cli_bare_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="/bin"; unset DOTFILES; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$EV_CLI_PATH" "$@"
}

# ev_cli_stub_in <project-dir> <home-dir> <fakebin-dir> <harness-args...> —
# PATH is <fakebin-dir>:/bin only, so the fake `claude` in <fakebin-dir> is
# the only `claude` found, and `socat` stays absent (not in /bin on any
# machine this suite runs on).
ev_cli_stub_in() {
	local dir home fakebin
	dir=$1
	home=$2
	fakebin=$3
	shift 3
	run_cmd env CLAUDE_STUB_RESULT="${CLAUDE_STUB_RESULT:-aggregate-ok}" CLAUDE_STUB_EXIT="${CLAUDE_STUB_EXIT:-0}" \
		EVAL_FIXTURES_DIR="$EV_FIXTURES" \
		bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3:/bin"; shift 3; exec "$@"' \
		_ "$dir" "$home" "$fakebin" node "$EV_CLI_PATH" "$@"
}

# ev_fakebin — a tmp dir with the claude stub installed as `claude`.
ev_fakebin() {
	local d
	d=$(tmp_dir)
	cp "$EV_FIXTURES/claude-stub.sh" "$d/claude"
	chmod +x "$d/claude"
	printf '%s' "$d"
}

# ev_repo — a tmp_repo with plugins/flow/evals/<case>/case.yaml fixtures for
# tag-grouping, matching aggregate-ok.json/aggregate-partial.json's case
# names: quality-reuse-slugify tagged quality, routing-fix-skill tagged
# routing.
ev_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/plugins/flow/evals/quality-reuse-slugify" "$d/plugins/flow/evals/routing-fix-skill"
	printf 'tags: [quality]\n' >"$d/plugins/flow/evals/quality-reuse-slugify/case.yaml"
	printf 'tags: [routing]\n' >"$d/plugins/flow/evals/routing-fix-skill/case.yaml"
	printf '%s' "$d"
}

t_eval_help_exits_0() {
	local home
	home=$(tmp_dir)
	ev_cli_in "$home" "$home" eval --help
	assert_rc 0 "t_eval_help_exits_0 rc"
	assert_contains "$OUT" "flow eval" "t_eval_help_exits_0 mentions-eval"
}

t_eval_dry_run_prints_pinned_models() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_in "$proj" "$home" eval --dry-run --tag quality
	assert_rc 0 "t_eval_dry_run_prints_pinned_models rc"
	assert_contains "$OUT" "plugin eval plugins/flow" "t_eval_dry_run_prints_pinned_models cli-target"
	assert_contains "$OUT" "--model claude-sonnet-5" "t_eval_dry_run_prints_pinned_models model"
	assert_contains "$OUT" "--judge-model claude-haiku-4-5" "t_eval_dry_run_prints_pinned_models judge-model"
	assert_contains "$OUT" "--trust-plugin" "t_eval_dry_run_prints_pinned_models trust-plugin"
	assert_contains "$OUT" "--allow-tools Write Edit" "t_eval_dry_run_prints_pinned_models allow-tools"
}

t_eval_dry_run_config_override() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/.claude"
	printf '{"evalModel":"claude-opus-5","evalJudgeModel":"claude-sonnet-5"}\n' >"$proj/.claude/flow.config.json"
	ev_cli_in "$proj" "$home" eval --dry-run
	assert_rc 0 "t_eval_dry_run_config_override rc"
	assert_contains "$OUT" "--model claude-opus-5" "t_eval_dry_run_config_override model"
	assert_contains "$OUT" "--judge-model claude-sonnet-5" "t_eval_dry_run_config_override judge-model"
}

t_eval_no_claude_refuses_with_doctor_hint() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_bare_in "$proj" "$home" eval --tag quality
	assert_rc 1 "t_eval_no_claude_refuses_with_doctor_hint rc"
	assert_contains "$ERR" "flow doctor" "t_eval_no_claude_refuses_with_doctor_hint doctor-hint"
}

t_eval_needs_bash_skipped_without_socat() {
	local proj home fakebin
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-ok CLAUDE_STUB_EXIT=0 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag needs-bash --tag quality
	assert_rc 0 "t_eval_needs_bash_skipped_without_socat rc"
	assert_contains "$OUT" "needs-bash" "t_eval_needs_bash_skipped_without_socat notice-mentions-tag"
	assert_contains "$OUT" "socat" "t_eval_needs_bash_skipped_without_socat notice-mentions-socat"
}

t_eval_ok_run_appends_ledger_and_summary() {
	local proj home fakebin ledger
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-ok CLAUDE_STUB_EXIT=0 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality --tag routing
	assert_rc 0 "t_eval_ok_run_appends_ledger_and_summary rc"
	assert_contains "$OUT" "quality:" "t_eval_ok_run_appends_ledger_and_summary quality-row"
	assert_contains "$OUT" "routing:" "t_eval_ok_run_appends_ledger_and_summary routing-row"
	ledger="$proj/plugins/flow/evals/ledger.jsonl"
	assert_file_exists "$ledger" "t_eval_ok_run_appends_ledger_and_summary ledger-file"
	assert_contains "$(cat "$ledger")" '"partial":false' "t_eval_ok_run_appends_ledger_and_summary ledger-partial-false"
	assert_contains "$(cat "$ledger")" '"quality"' "t_eval_ok_run_appends_ledger_and_summary ledger-quality-tag"
	assert_contains "$(cat "$ledger")" '"routing"' "t_eval_ok_run_appends_ledger_and_summary ledger-routing-tag"
}

t_eval_partial_run_marks_ledger_and_exits_2() {
	local proj home fakebin ledger
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-partial CLAUDE_STUB_EXIT=2 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality
	assert_rc 2 "t_eval_partial_run_marks_ledger_and_exits_2 rc"
	assert_contains "$OUT" "cost_ceiling" "t_eval_partial_run_marks_ledger_and_exits_2 reason"
	ledger="$proj/plugins/flow/evals/ledger.jsonl"
	assert_contains "$(cat "$ledger")" '"partial":true' "t_eval_partial_run_marks_ledger_and_exits_2 ledger-partial-true"
}

t_eval_cli_fail_exit_passthrough() {
	local proj home fakebin
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-ok CLAUDE_STUB_EXIT=1 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality
	assert_rc 1 "t_eval_cli_fail_exit_passthrough rc"
}

t_eval_unparsable_result_exits_1() {
	local proj home fakebin
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	printf '#!/usr/bin/env bash\nexit 0\n' >"$fakebin/claude"
	chmod +x "$fakebin/claude"
	ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality
	assert_rc 1 "t_eval_unparsable_result_exits_1 rc"
	assert_contains "$ERR" "unparsable" "t_eval_unparsable_result_exits_1 message"
}

t_eval_doctor_reports_eval_ready_row() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_in "$proj" "$home" doctor
	assert_contains "$OUT" "eval-ready" "t_eval_doctor_reports_eval_ready_row row-present"
}

t_eval_loop_init_test_files_flag_writes_paths() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_in "$proj" "$home" loop init "goal text" --verify "exit 1" \
		--test-files "plugins/flow/evals/a" --test-files "plugins/flow/evals/b"
	assert_rc 0 "t_eval_loop_init_test_files_flag_writes_paths rc"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "plugins/flow/evals/a" "t_eval_loop_init_test_files_flag_writes_paths path-a"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "plugins/flow/evals/b" "t_eval_loop_init_test_files_flag_writes_paths path-b"
}
