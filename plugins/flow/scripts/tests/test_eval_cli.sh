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
# runner's PATH, so the real `claude` on the machine running the suite is
# what these tests see (spec's own assumption, 7.1: claude >= 2.1.269
# available). A test that additionally needs `socat` to read as absent
# (deterministically, regardless of what this machine's PATH actually has —
# /bin being a symlink to /usr/bin on usrmerge systems means a system socat
# package can share a directory with binaries the CLI needs, like git or
# node, so PATH can no longer be pared down to exclude just socat) sets
# FLOW_EVAL_TEST_HIDE_SOCAT=1 before calling this helper; eval.js honors it
# as a test-only override of the PATH-based socat lookup.
ev_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; unset DOTFILES; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$EV_CLI_PATH" "$@"
}

# ev_cli_bare_in <project-dir> <home-dir> <harness-args...> — PATH stripped
# to /bin only: no `claude`, deterministic regardless of what a developer
# happens to have installed.
ev_cli_bare_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="/bin"; unset DOTFILES; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$EV_CLI_PATH" "$@"
}

# ev_cli_stub_in <project-dir> <home-dir> <fakebin-dir> <harness-args...> —
# PATH is <fakebin-dir>:/bin, so the fake `claude` in <fakebin-dir> is the
# only `claude` found. A test that needs `socat` absent regardless of what
# this machine's /bin actually has sets FLOW_EVAL_TEST_HIDE_SOCAT=1 before
# calling this helper (see ev_cli_in above); a test that needs `socat`
# present stubs one into <fakebin-dir> instead (ev_fakebin_with_socat).
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

# ev_repo_pipeline_bash — a tmp_repo with one case tagged [pipeline,
# needs-bash], matching the real pipeline-fix-bug/pipeline-flow-feature
# case.yaml shape: `--tag pipeline` alone must still select it.
ev_repo_pipeline_bash() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/plugins/flow/evals/pipeline-fix-bug"
	printf 'tags: [pipeline, needs-bash]\n' >"$d/plugins/flow/evals/pipeline-fix-bug/case.yaml"
	printf '%s' "$d"
}

# ev_fakebin_with_socat — ev_fakebin plus a no-op `socat` stub, so the child
# argv is built as if this machine had socat (Slice 6 review: proving Bash
# gets granted needs a machine where the socat gate would let needs-bash
# cases through in the first place).
ev_fakebin_with_socat() {
	local d
	d=$(ev_fakebin)
	printf '#!/usr/bin/env bash\nexit 0\n' >"$d/socat"
	chmod +x "$d/socat"
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
	assert_contains "$OUT" "--tag quality" "t_eval_dry_run_prints_pinned_models tag-forwarded"
	assert_not_contains "$OUT" "--tag routing" "t_eval_dry_run_prints_pinned_models tag-not-selected-absent"
}

# t_eval_dry_run_drops_needs_bash_tag_from_argv — proves the socat-missing
# skip (FR-00x, code-design.md decision 5) actually narrows what gets
# forwarded to `claude plugin eval`, not just what the printed notice claims.
# FLOW_EVAL_TEST_HIDE_SOCAT=1 keeps `socat` reading as absent regardless of
# the host (see ev_cli_in's doc comment).
t_eval_dry_run_drops_needs_bash_tag_from_argv() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	FLOW_EVAL_TEST_HIDE_SOCAT=1 ev_cli_in "$proj" "$home" eval --dry-run
	assert_rc 0 "t_eval_dry_run_drops_needs_bash_tag_from_argv rc"
	assert_contains "$OUT" "socat" "t_eval_dry_run_drops_needs_bash_tag_from_argv notice"
	assert_contains "$OUT" "--tag quality" "t_eval_dry_run_drops_needs_bash_tag_from_argv quality-kept"
	assert_contains "$OUT" "--tag routing" "t_eval_dry_run_drops_needs_bash_tag_from_argv routing-kept"
	assert_contains "$OUT" "--tag invariant" "t_eval_dry_run_drops_needs_bash_tag_from_argv invariant-kept"
	assert_not_contains "$OUT" "--tag needs-bash" "t_eval_dry_run_drops_needs_bash_tag_from_argv needs-bash-dropped"
}

# t_eval_dry_run_grants_bash_for_case_selected_by_other_tag — Slice 6 review:
# a case tagged [pipeline, needs-bash] must get the Bash tool when selected
# via `--tag pipeline` alone, not only when the literal tag `needs-bash` is
# itself in the user's --tag selection (evals/README.md's own documented
# contract: "--allow-tools Write Edit (and Bash for needs-bash cases)").
t_eval_dry_run_grants_bash_for_case_selected_by_other_tag() {
	local proj home fakebin
	proj=$(ev_repo_pipeline_bash)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin_with_socat)
	ev_cli_stub_in "$proj" "$home" "$fakebin" eval --dry-run --tag pipeline
	assert_rc 0 "t_eval_dry_run_grants_bash_for_case_selected_by_other_tag rc"
	assert_contains "$OUT" "--allow-tools Write Edit Bash" "t_eval_dry_run_grants_bash_for_case_selected_by_other_tag bash-granted"
}

# t_eval_dry_run_no_bash_when_no_selected_case_needs_it — the flip side: a
# selection whose cases never carry needs-bash must not grant Bash at all,
# even when socat is present.
t_eval_dry_run_no_bash_when_no_selected_case_needs_it() {
	local proj home fakebin
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin_with_socat)
	ev_cli_stub_in "$proj" "$home" "$fakebin" eval --dry-run --tag quality
	assert_rc 0 "t_eval_dry_run_no_bash_when_no_selected_case_needs_it rc"
	assert_not_contains "$OUT" "Bash" "t_eval_dry_run_no_bash_when_no_selected_case_needs_it no-bash"
}

# t_eval_dry_run_concurrency_forwarded — -j N is a shorthand for
# --concurrency N, and both forward `--concurrency N` (not `-j N`) to the
# child CLI.
t_eval_dry_run_concurrency_forwarded() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_in "$proj" "$home" eval --dry-run --tag quality -j 4
	assert_rc 0 "t_eval_dry_run_concurrency_forwarded rc"
	assert_contains "$OUT" "--concurrency 4" "t_eval_dry_run_concurrency_forwarded forwarded"
}

# t_eval_concurrency_out_of_range_refuses_before_spawning — the CLI accepts
# 1..8; anything else must be rejected with exit 1 and no argv printed
# (--dry-run would otherwise still print it), before any spawn is attempted.
t_eval_concurrency_out_of_range_refuses_before_spawning() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	ev_cli_in "$proj" "$home" eval --dry-run --tag quality -j 9
	assert_rc 1 "t_eval_concurrency_out_of_range_refuses_before_spawning rc"
	assert_not_contains "$OUT" "plugin eval plugins/flow" "t_eval_concurrency_out_of_range_refuses_before_spawning no-argv-printed"
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
	CLAUDE_STUB_RESULT=aggregate-ok CLAUDE_STUB_EXIT=0 FLOW_EVAL_TEST_HIDE_SOCAT=1 \
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

# t_eval_single_tag_excludes_other_tag_from_rollup — ev_repo's fixture data
# has both a quality and a routing case; requesting only --tag quality must
# leave routing out of both the summary and the ledger line, not just merge
# every tag the fixture happens to have data for (the rollup half of the
# --tag contract, distinct from the argv-forwarding half covered by the
# --dry-run tests above).
t_eval_single_tag_excludes_other_tag_from_rollup() {
	local proj home fakebin ledger
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-ok CLAUDE_STUB_EXIT=0 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality
	assert_rc 0 "t_eval_single_tag_excludes_other_tag_from_rollup rc"
	assert_contains "$OUT" "quality:" "t_eval_single_tag_excludes_other_tag_from_rollup quality-row-present"
	assert_not_contains "$OUT" "routing:" "t_eval_single_tag_excludes_other_tag_from_rollup routing-row-absent"
	ledger="$proj/plugins/flow/evals/ledger.jsonl"
	assert_contains "$(cat "$ledger")" '"quality"' "t_eval_single_tag_excludes_other_tag_from_rollup ledger-quality-tag"
	assert_not_contains "$(cat "$ledger")" '"routing"' "t_eval_single_tag_excludes_other_tag_from_rollup ledger-routing-tag-absent"
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

# t_eval_doctor_ledger_age_from_subdir — the eval-ready row must find the
# ledger `flow eval` itself wrote (resolved against the git toplevel), not
# just process.cwd(); running `flow doctor` from a subdirectory of the repo
# must still report the real ledger age, not "no ledger yet" (FR-009).
t_eval_doctor_ledger_age_from_subdir() {
	local proj home sub
	proj=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/plugins/flow/evals" "$proj/sub/deeper"
	printf '{"ts":"2020-01-01T00:00:00.000Z","sha":"abc1234","model":"m","judgeModel":"j","tags":{},"meanDelta":0,"costUsd":0,"partial":false,"reason":""}\n' \
		>"$proj/plugins/flow/evals/ledger.jsonl"
	sub="$proj/sub/deeper"
	ev_cli_in "$sub" "$home" doctor
	assert_contains "$OUT" "ledger age" "t_eval_doctor_ledger_age_from_subdir ledger-age-present"
	assert_not_contains "$OUT" "no ledger yet" "t_eval_doctor_ledger_age_from_subdir ledger-not-missing"
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

# ev_repo_with_test_file — a tmp_repo with a tracked test file (so the
# auto-detected test_files count is > 0 at init), matching test_loop.sh's
# lp_repo helper.
ev_repo_with_test_file() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/tests"
	printf 'echo test\n' >"$d/tests/foo_test.sh"
	(cd "$d" && git add tests/foo_test.sh && git commit -q -m "add test file") >/dev/null 2>&1
	printf '%s' "$d"
}

# t_eval_test_files_flag_keeps_auto_detected_tamper_check — regression:
# --test-files must add tamper protection for the named paths, not replace
# test_files' numeric count with a path string (which would silently
# disable the "test files removed" check for the whole loop session, since
# toInt() on a path string is 0 and curCount < 0 never fires).
t_eval_test_files_flag_keeps_auto_detected_tamper_check() {
	local proj home
	proj=$(ev_repo_with_test_file)
	home=$(tmp_dir)
	mkdir -p "$proj/plugins/flow/evals/a"
	printf 'x\n' >"$proj/plugins/flow/evals/a/case.yaml"
	(cd "$proj" && git add -A && git commit -q -m "add protected dir") >/dev/null 2>&1

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt" \
		--test-files "plugins/flow/evals/a/case.yaml"
	assert_rc 0 "t_eval_test_files_flag_keeps_auto_detected_tamper_check init-rc"
	: >"$proj/done.txt"

	(cd "$proj" && rm tests/foo_test.sh && git add -A) >/dev/null 2>&1

	ev_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_eval_test_files_flag_keeps_auto_detected_tamper_check check-rc"
	assert_contains "$OUT" "test files removed" "t_eval_test_files_flag_keeps_auto_detected_tamper_check finding"
}

# t_eval_test_files_flag_protects_named_path — the named path itself is
# tamper-protected: removing it (even though it never matches the
# isTestPath heuristic) must flag the loop as suspect.
t_eval_test_files_flag_protects_named_path() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/plugins/flow/evals/a"
	printf 'x\n' >"$proj/plugins/flow/evals/a/case.yaml"
	(cd "$proj" && git add -A && git commit -q -m "add protected dir") >/dev/null 2>&1

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt" \
		--test-files "plugins/flow/evals/a/case.yaml"
	assert_rc 0 "t_eval_test_files_flag_protects_named_path init-rc"
	: >"$proj/done.txt"

	(cd "$proj" && rm plugins/flow/evals/a/case.yaml && git add -A) >/dev/null 2>&1

	ev_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_eval_test_files_flag_protects_named_path check-rc"
	assert_contains "$OUT" "protected file removed" "t_eval_test_files_flag_protects_named_path finding"
	assert_contains "$OUT" "plugins/flow/evals/a/case.yaml" "t_eval_test_files_flag_protects_named_path path"
}

# t_eval_partial_exit_when_child_exits_0_but_data_partial — regression: the
# child `claude plugin eval` can flag partial/cost_ceiling in its --json
# output while itself exiting 0. flow eval's own exit code must still be 2
# (partial), not 0, since the summary and ledger already say partial.
t_eval_partial_exit_when_child_exits_0_but_data_partial() {
	local proj home fakebin ledger
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	CLAUDE_STUB_RESULT=aggregate-partial CLAUDE_STUB_EXIT=0 \
		ev_cli_stub_in "$proj" "$home" "$fakebin" eval --tag quality
	assert_rc 2 "t_eval_partial_exit_when_child_exits_0_but_data_partial rc"
	assert_contains "$OUT" "cost_ceiling" "t_eval_partial_exit_when_child_exits_0_but_data_partial reason"
	ledger="$proj/plugins/flow/evals/ledger.jsonl"
	assert_contains "$(cat "$ledger")" '"partial":true' "t_eval_partial_exit_when_child_exits_0_but_data_partial ledger-partial-true"
}

# t_eval_empty_tag_selection_refuses_instead_of_running_everything — the
# socat skip can empty an explicit selection (`--tag needs-bash` alone). The
# child CLI's documented default for "no --tag" is every tag, so forwarding an
# empty selection would run the whole suite the caller narrowed away from, at
# full API cost. `flow eval` must refuse and spawn nothing.
# FLOW_EVAL_TEST_HIDE_SOCAT=1 keeps `socat` reading as absent regardless of
# the host, so the skip triggers deterministically.
t_eval_empty_tag_selection_refuses_instead_of_running_everything() {
	local proj home fakebin
	proj=$(ev_repo)
	home=$(tmp_dir)
	fakebin=$(ev_fakebin)
	FLOW_EVAL_TEST_HIDE_SOCAT=1 ev_cli_stub_in "$proj" "$home" "$fakebin" eval --dry-run --tag needs-bash
	assert_rc 1 "t_eval_empty_tag_selection_refuses_instead_of_running_everything rc"
	assert_contains "$ERR" "nothing to evaluate" "t_eval_empty_tag_selection_refuses_instead_of_running_everything message"
	assert_not_contains "$OUT" "plugin eval plugins/flow" "t_eval_empty_tag_selection_refuses_instead_of_running_everything no-child-argv"
	assert_file_missing "$proj/plugins/flow/evals/ledger.jsonl" "t_eval_empty_tag_selection_refuses_instead_of_running_everything no-ledger-line"
}

# ev_repo_with_evals — a tmp_repo with a committed eval case under
# plugins/flow/evals/, the shape FR-008/AC-011 talk about.
ev_repo_with_evals() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/plugins/flow/evals/quality-foo"
	printf 'tags: [quality]\nexpected: reuse the existing helper\n' >"$d/plugins/flow/evals/quality-foo/case.yaml"
	(cd "$d" && git add -A && git commit -q -m "add eval case") >/dev/null 2>&1
	printf '%s' "$d"
}

# t_eval_edit_under_evals_is_suspect_by_default — AC-011: an iteration that
# edits (not deletes) a file under evals/ is suspect, with no --test-files at
# init. Rewriting a case's expectations is exactly how a loop would game the
# suite it is scored on, and the file still exists afterwards, so an
# existence-only check never sees it.
t_eval_edit_under_evals_is_suspect_by_default() {
	local proj home
	proj=$(ev_repo_with_evals)
	home=$(tmp_dir)

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt"
	assert_rc 0 "t_eval_edit_under_evals_is_suspect_by_default init-rc"
	: >"$proj/done.txt"
	printf 'tags: [quality]\nexpected: anything at all\n' >"$proj/plugins/flow/evals/quality-foo/case.yaml"

	ev_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_eval_edit_under_evals_is_suspect_by_default check-rc"
	assert_contains "$OUT" "verdict: suspect" "t_eval_edit_under_evals_is_suspect_by_default verdict"
	assert_contains "$OUT" "plugins/flow/evals/quality-foo/case.yaml" "t_eval_edit_under_evals_is_suspect_by_default path"
}

# t_eval_new_case_under_evals_is_suspect_by_default — the same gate for an
# added (untracked) file: planting a trivially-passing case is tamper too.
t_eval_new_case_under_evals_is_suspect_by_default() {
	local proj home
	proj=$(ev_repo_with_evals)
	home=$(tmp_dir)

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt"
	assert_rc 0 "t_eval_new_case_under_evals_is_suspect_by_default init-rc"
	: >"$proj/done.txt"
	mkdir -p "$proj/plugins/flow/evals/quality-free-points"
	printf 'tags: [quality]\n' >"$proj/plugins/flow/evals/quality-free-points/case.yaml"

	ev_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_eval_new_case_under_evals_is_suspect_by_default check-rc"
	assert_contains "$OUT" "plugins/flow/evals/quality-free-points/case.yaml" "t_eval_new_case_under_evals_is_suspect_by_default path"
}

# t_eval_ledger_append_under_evals_is_not_tamper — the one documented
# exemption: `flow eval` (the verifier itself) appends a line to
# evals/ledger.jsonl on every run, so protecting that path would mark every
# iteration of the very loop FR-008 exists to protect as suspect.
t_eval_ledger_append_under_evals_is_not_tamper() {
	local proj home
	proj=$(ev_repo_with_evals)
	home=$(tmp_dir)

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt"
	assert_rc 0 "t_eval_ledger_append_under_evals_is_not_tamper init-rc"
	: >"$proj/done.txt"
	printf '{"ts":"2020-01-01T00:00:00.000Z","sha":"abc1234","model":"m","judgeModel":"j","tags":{},"meanDelta":0,"costUsd":0,"partial":false,"reason":""}\n' \
		>>"$proj/plugins/flow/evals/ledger.jsonl"

	ev_cli_in "$proj" "$home" loop check
	assert_rc 0 "t_eval_ledger_append_under_evals_is_not_tamper check-rc"
	assert_contains "$OUT" "verdict: pass" "t_eval_ledger_append_under_evals_is_not_tamper verdict"
}

# t_eval_test_files_flag_protects_directory_contents — --test-files takes a
# directory ("a caller can protect data dirs the isTestPath heuristic never
# matches"): removing a file inside it must flag, even though the directory
# itself still exists.
t_eval_test_files_flag_protects_directory_contents() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/data/goldens"
	printf 'x\n' >"$proj/data/goldens/one.txt"
	printf 'y\n' >"$proj/data/goldens/two.txt"
	(cd "$proj" && git add -A && git commit -q -m "add protected dir") >/dev/null 2>&1

	ev_cli_in "$proj" "$home" loop init "goal text" --verify "test -f done.txt" \
		--test-files "data/goldens"
	assert_rc 0 "t_eval_test_files_flag_protects_directory_contents init-rc"
	: >"$proj/done.txt"

	rm "$proj/data/goldens/one.txt"

	ev_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_eval_test_files_flag_protects_directory_contents check-rc"
	assert_contains "$OUT" "data/goldens/one.txt" "t_eval_test_files_flag_protects_directory_contents path"
	assert_contains "$OUT" "verdict: suspect" "t_eval_test_files_flag_protects_directory_contents verdict"
}
