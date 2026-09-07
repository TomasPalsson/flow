#!/usr/bin/env bash
# test_loop.sh — `flow loop` (spec .specs/006-loop-engineering/spec.md,
# K-A..K-L) tests for plugins/flow/bin/lib/loop.js and bin/flow's loop
# dispatch/help/doctor/next/init deltas.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_cli.sh's CLI_PATH/cli_in having
# been sourced in the same run — it defines its own equivalents below.
set -u

LP_CLI_PATH=""
LP_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
LP_CLI_PATH="$LP_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && LP_CLI_PATH="$SCAN_DIR/../bin/flow"

# lp_cli_in <project-dir> <home-dir> <harness-args...>
lp_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$LP_CLI_PATH" "$@"
}

# lp_cli_env_in <project-dir> <home-dir> <extra-PATH-prefix> <harness-args...>
# Like lp_cli_in but also prepends a directory to PATH (for a fake `claude`).
lp_cli_env_in() {
	local dir home prefix
	dir=$1
	home=$2
	prefix=$3
	shift 3
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3:$PATH"; shift 3; exec "$@"' \
		_ "$dir" "$home" "$prefix" node "$LP_CLI_PATH" "$@"
}

# lp_repo — a tmp_repo with a tracked test file (so test_files > 0 at init,
# needed by the K-F "removed" tamper case).
lp_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/tests"
	printf 'echo test\n' >"$d/tests/foo_test.sh"
	(cd "$d" && git add tests/foo_test.sh && git commit -q -m "add test file") >/dev/null 2>&1
	printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# init (K-B, K-C)
# ---------------------------------------------------------------------------

t_loop_init_writes_contract_kb() {
	local proj home contract
	proj=$(lp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop init "make done.txt exist" --verify "test -f done.txt"
	assert_rc 0 "t_loop_init_writes_contract_kb rc"

	contract=$(cat "$proj/.claude/loop/loop.md")
	assert_contains "$contract" "version: 1" "t_loop_init_writes_contract_kb version"
	assert_contains "$contract" "slug: make-done-txt-exist" "t_loop_init_writes_contract_kb slug"
	assert_contains "$contract" 'goal: "make done.txt exist"' "t_loop_init_writes_contract_kb quoted-goal"
	assert_contains "$contract" 'verify: "test -f done.txt"' "t_loop_init_writes_contract_kb quoted-verify"
	assert_contains "$contract" "shape: session" "t_loop_init_writes_contract_kb shape"
	assert_contains "$contract" "status: active" "t_loop_init_writes_contract_kb status"
	assert_contains "$contract" "You are one iteration of a loop" "t_loop_init_writes_contract_kb body-present"

	rm -rf "$home" "$proj"
}

t_loop_init_refuses_green_verifier() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop init "readme exists" --verify "test -f README.md"
	assert_rc 1 "t_loop_init_refuses_green_verifier rc"
	assert_contains "$ERR" "verifier already passes; nothing to loop (use --allow-green to loop anyway)" \
		"t_loop_init_refuses_green_verifier message"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_loop_init_refuses_green_verifier writes-nothing"

	rm -rf "$home" "$proj"
}

t_loop_init_allow_green() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop init "readme exists" --verify "test -f README.md" --allow-green
	assert_rc 0 "t_loop_init_allow_green rc"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "status: active" "t_loop_init_allow_green active"

	rm -rf "$home" "$proj"
}

t_loop_init_refuses_second_active_without_force() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop init "first goal" --verify "test -f done.txt"
	assert_rc 0 "t_loop_init_refuses_second_active_without_force first-rc"

	lp_cli_in "$proj" "$home" loop init "second goal" --verify "test -f other.txt"
	assert_rc 1 "t_loop_init_refuses_second_active_without_force second-rc"
	assert_contains "$ERR" "active loop contract exists" "t_loop_init_refuses_second_active_without_force message"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "first goal" "t_loop_init_refuses_second_active_without_force unchanged"

	lp_cli_in "$proj" "$home" loop init "second goal" --verify "test -f other.txt" --force
	assert_rc 0 "t_loop_init_refuses_second_active_without_force force-rc"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "second goal" "t_loop_init_refuses_second_active_without_force force-replaces"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# check (K-D, K-F)
# ---------------------------------------------------------------------------

t_loop_check_pass_fail_exit_codes() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null

	lp_cli_in "$proj" "$home" loop check
	assert_rc 1 "t_loop_check_pass_fail_exit_codes fail-rc"
	assert_contains "$OUT" "verdict: fail" "t_loop_check_pass_fail_exit_codes fail-verdict"

	: >"$proj/done.txt"
	lp_cli_in "$proj" "$home" loop check
	assert_rc 0 "t_loop_check_pass_fail_exit_codes pass-rc"
	assert_contains "$OUT" "verdict: pass" "t_loop_check_pass_fail_exit_codes pass-verdict"

	rm -rf "$home" "$proj"
}

t_loop_check_suspect_on_removed_test_file_kf() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	: >"$proj/done.txt"

	(cd "$proj" && rm tests/foo_test.sh && git add -A) >/dev/null 2>&1

	lp_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_loop_check_suspect_on_removed_test_file_kf rc"
	assert_contains "$OUT" "verdict: suspect" "t_loop_check_suspect_on_removed_test_file_kf verdict"
	assert_contains "$OUT" "test files removed" "t_loop_check_suspect_on_removed_test_file_kf finding"

	rm -rf "$home" "$proj"
}

t_loop_check_suspect_on_added_skip_kf() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	: >"$proj/done.txt"

	printf 'it.skip("later", () => {})\n' >>"$proj/tests/foo_test.sh"

	lp_cli_in "$proj" "$home" loop check
	assert_rc 2 "t_loop_check_suspect_on_added_skip_kf rc"
	assert_contains "$OUT" "verdict: suspect" "t_loop_check_suspect_on_added_skip_kf verdict"
	assert_contains "$OUT" "skip/xfail added in" "t_loop_check_suspect_on_added_skip_kf finding"

	rm -rf "$home" "$proj"
}

t_loop_check_timeout_kd() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "never finishes" --verify "sleep 5" --verify-timeout 1
	assert_rc 0 "t_loop_check_timeout_kd init-rc"

	lp_cli_in "$proj" "$home" loop check
	assert_rc 1 "t_loop_check_timeout_kd check-rc"
	assert_contains "$OUT" "verify timed out after 1 s" "t_loop_check_timeout_kd message"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# tick (K-H)
# ---------------------------------------------------------------------------

t_loop_tick_allow_without_contract() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_rc 0 "t_loop_tick_allow_without_contract rc"
	assert_eq "$OUT" "" "t_loop_tick_allow_without_contract silent"

	rm -rf "$home" "$proj"
}

t_loop_tick_session_mismatch_allows_kh3() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --session "sess-a" >/dev/null

	lp_cli_in "$proj" "$home" loop tick --hook --session "sess-b"
	assert_rc 0 "t_loop_tick_session_mismatch_allows_kh3 rc"
	assert_eq "$OUT" "" "t_loop_tick_session_mismatch_allows_kh3 silent"

	lp_cli_in "$proj" "$home" loop tick --hook --session "sess-a"
	assert_contains "$OUT" "decision" "t_loop_tick_session_mismatch_allows_kh3 matching-session-proceeds"

	rm -rf "$home" "$proj"
}

t_loop_tick_fresh_from_hook_allows_kh2() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape fresh >/dev/null

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_rc 0 "t_loop_tick_fresh_from_hook_allows_kh2 rc"
	assert_eq "$OUT" "" "t_loop_tick_fresh_from_hook_allows_kh2 silent-from-hook"

	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_tick_fresh_from_hook_allows_kh2 non-hook-proceeds"

	rm -rf "$home" "$proj"
}

t_loop_tick_continue_reason_kj() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --prompt "CUSTOM PROMPT BODY" >/dev/null

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "[flow loop] iteration 1 of" "t_loop_tick_continue_reason_kj iteration-line"
	assert_contains "$OUT" "verifier \`test -f done.txt\` exited 1" "t_loop_tick_continue_reason_kj verify-tail"
	assert_contains "$OUT" "CUSTOM PROMPT BODY" "t_loop_tick_continue_reason_kj prompt-body"

	rm -rf "$home" "$proj"
}

t_loop_tick_done_finishes_once_kh4() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	: >"$proj/done.txt"

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "finished: verifier passed" "t_loop_tick_done_finishes_once_kh4 finish-message"

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_eq "$OUT" "" "t_loop_tick_done_finishes_once_kh4 silent-after"

	rm -rf "$home" "$proj"
}

t_loop_tick_blocked_md_stops_kh5() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	mkdir -p "$proj/.claude/loop"
	printf 'cannot do this\n' >"$proj/.claude/loop/BLOCKED.md"

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "stopped: blocked" "t_loop_tick_blocked_md_stops_kh5 message"

	rm -rf "$home" "$proj"
}

t_loop_tick_cap_stops_kh8() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --max-iterations 1 >/dev/null

	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "stopped: cap after 1 iterations" "t_loop_tick_cap_stops_kh8 message"

	rm -rf "$home" "$proj"
}

t_loop_tick_stall_stops_kh7() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --stall-after 2 >/dev/null

	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_tick_stall_stops_kh7 tick1-continue"
	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_tick_stall_stops_kh7 tick2-continue"
	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "stopped: stall after" "t_loop_tick_stall_stops_kh7 tick3-stall"

	rm -rf "$home" "$proj"
}

t_loop_tick_wedge_stops_kh7() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "echo always-red; exit 1" --stall-after 2 >/dev/null

	printf 'change 1\n' >>"$proj/README.md"
	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_tick_wedge_stops_kh7 tick1-continue"

	printf 'change 2\n' >>"$proj/README.md"
	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" '"action": "continue"' "t_loop_tick_wedge_stops_kh7 tick2-continue"

	printf 'change 3\n' >>"$proj/README.md"
	lp_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "stopped: wedge after" "t_loop_tick_wedge_stops_kh7 tick3-wedge"

	rm -rf "$home" "$proj"
}

t_loop_tick_corrupt_contract_self_disarms_kb() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null

	# Corrupt the contract directly: an empty verify (K-B corrupt rule).
	sed 's#^verify: .*#verify: ""#' "$proj/.claude/loop/loop.md" >"$proj/.claude/loop/loop.md.new"
	mv "$proj/.claude/loop/loop.md.new" "$proj/.claude/loop/loop.md"

	lp_cli_in "$proj" "$home" loop tick --json
	assert_contains "$OUT" "corrupt contract:" "t_loop_tick_corrupt_contract_self_disarms_kb reason"
	assert_contains "$OUT" '"action": "allow"' "t_loop_tick_corrupt_contract_self_disarms_kb allow"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_loop_tick_corrupt_contract_self_disarms_kb renamed-away"
	assert_file_exists "$proj/.claude/loop/loop.md.corrupt" "t_loop_tick_corrupt_contract_self_disarms_kb corrupt-file"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# log (K-E)
# ---------------------------------------------------------------------------

t_loop_log_lines_ke() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	lp_cli_in "$proj" "$home" loop tick --hook >/dev/null

	lp_cli_in "$proj" "$home" loop log
	assert_rc 0 "t_loop_log_lines_ke rc"
	assert_contains "$OUT" " init " "t_loop_log_lines_ke init-event"
	assert_contains "$OUT" "iter=" "t_loop_log_lines_ke iter-field"
	assert_contains "$OUT" "verify=" "t_loop_log_lines_ke verify-field"
	assert_contains "$OUT" "sig=" "t_loop_log_lines_ke sig-field"
	assert_contains "$OUT" "changed=" "t_loop_log_lines_ke changed-field"
	assert_contains "$OUT" "cost=" "t_loop_log_lines_ke cost-field"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# run (K-I)
# ---------------------------------------------------------------------------

t_loop_run_dry_run_ki() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape fresh >/dev/null

	lp_cli_in "$proj" "$home" loop run --dry-run
	assert_rc 0 "t_loop_run_dry_run_ki rc"
	assert_contains "$OUT" "argv:" "t_loop_run_dry_run_ki plan"
	assert_contains "$OUT" "claude" "t_loop_run_dry_run_ki mentions-claude"
	assert_file_missing "$proj/.claude/loop/iterations" "t_loop_run_dry_run_ki no-spawn"

	rm -rf "$home" "$proj"
}

_lp_write_fake_claude() {
	local fakebin countfile
	fakebin=$(tmp_dir)
	countfile=$(tmp_dir)/count
	printf '0' >"$countfile"
	cat >"$fakebin/claude" <<EOF
#!/bin/sh
n=\$(cat "$countfile")
n=\$((n + 1))
printf '%s' "\$n" >"$countfile"
if [ "\$n" -eq 2 ]; then touch done.txt; fi
printf '{"total_cost_usd":0.5,"session_id":"x","is_error":false}\n'
EOF
	chmod +x "$fakebin/claude"
	printf '%s' "$fakebin"
}

t_loop_run_fake_claude_ki() {
	local proj home fakebin
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape fresh >/dev/null
	fakebin=$(_lp_write_fake_claude)

	lp_cli_env_in "$proj" "$home" "$fakebin" loop run
	assert_rc 0 "t_loop_run_fake_claude_ki rc"
	assert_contains "$OUT" "finished: verifier passed" "t_loop_run_fake_claude_ki finished"

	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "status: done" "t_loop_run_fake_claude_ki status-done"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "cost_usd: 1" "t_loop_run_fake_claude_ki cost"
	assert_contains "$(cd "$proj" && git log --oneline)" "checkpoint" "t_loop_run_fake_claude_ki checkpoint-commit"

	rm -rf "$home" "$proj" "$fakebin"
}

t_loop_run_fake_claude_error_streak_ki() {
	local proj home fakebin
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape fresh >/dev/null
	fakebin=$(tmp_dir)
	cat >"$fakebin/claude" <<'EOF'
#!/bin/sh
printf '{"total_cost_usd":0,"session_id":"x","is_error":true}\n'
EOF
	chmod +x "$fakebin/claude"

	lp_cli_env_in "$proj" "$home" "$fakebin" loop run
	assert_rc 1 "t_loop_run_fake_claude_error_streak_ki rc"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "status: stopped" "t_loop_run_fake_claude_error_streak_ki stopped"
	assert_contains "$(cat "$proj/.claude/loop/loop.md")" "stop_reason: error" "t_loop_run_fake_claude_error_streak_ki reason"

	rm -rf "$home" "$proj" "$fakebin"
}

# ---------------------------------------------------------------------------
# status / stop CLI
# ---------------------------------------------------------------------------

t_loop_status_stop_cli() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" loop status
	assert_rc 3 "t_loop_status_stop_cli no-contract-rc"

	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	lp_cli_in "$proj" "$home" loop status
	assert_rc 0 "t_loop_status_stop_cli active-rc"
	assert_contains "$OUT" "status: active" "t_loop_status_stop_cli active-line"

	lp_cli_in "$proj" "$home" loop stop --reason "manual test"
	assert_rc 0 "t_loop_status_stop_cli stop-rc"
	assert_contains "$OUT" "stopped" "t_loop_status_stop_cli stop-message"

	lp_cli_in "$proj" "$home" loop status
	assert_contains "$OUT" "status: stopped" "t_loop_status_stop_cli stopped-line"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor / next / init deltas (K-L)
# ---------------------------------------------------------------------------

t_loop_doctor_warns_active_kl() {
	local proj home block
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null

	lp_cli_in "$proj" "$home" doctor --json
	assert_contains "$OUT" '"id": "loop-contract"' "t_loop_doctor_warns_active_kl check-present"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "loop-contract"')
	assert_contains "$block" '"status": "WARN"' "t_loop_doctor_warns_active_kl warn"
	assert_contains "$OUT" "loop: active contract since" "t_loop_doctor_warns_active_kl message"

	rm -rf "$home" "$proj"
}

t_loop_next_active_session_kl() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape session >/dev/null

	lp_cli_in "$proj" "$home" next
	assert_rc 0 "t_loop_next_active_session_kl rc"
	assert_eq "$OUT" "Next: flow loop status" "t_loop_next_active_session_kl exact"

	rm -rf "$home" "$proj"
}

t_loop_next_active_fresh_kl() {
	local proj home
	proj=$(lp_repo)
	home=$(tmp_dir)
	lp_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" --shape fresh >/dev/null

	lp_cli_in "$proj" "$home" next
	assert_rc 0 "t_loop_next_active_fresh_kl rc"
	assert_eq "$OUT" "Next: flow loop run" "t_loop_next_active_fresh_kl exact"

	rm -rf "$home" "$proj"
}

t_loop_init_gitignore_lines_kl() {
	local proj home
	proj=$(tmp_dir)
	home=$(tmp_dir)

	lp_cli_in "$proj" "$home" init
	assert_rc 0 "t_loop_init_gitignore_lines_kl rc"
	assert_contains "$(cat "$proj/.gitignore")" ".claude/loop/*" "t_loop_init_gitignore_lines_kl ignore-line"
	assert_contains "$(cat "$proj/.gitignore")" "!.claude/loop/LEARNINGS.md" "t_loop_init_gitignore_lines_kl keep-line"

	lp_cli_in "$proj" "$home" init --force
	local count
	count=$(grep -c '^\.claude/loop/\*$' "$proj/.gitignore")
	assert_eq "$count" "1" "t_loop_init_gitignore_lines_kl idempotent"

	rm -rf "$home" "$proj"
}
