#!/usr/bin/env bash
# test_core.sh — unit U1 (hooks-core) tests for session-context.sh,
# turn-stamp.sh, git-guard.sh and pre-compact-backup.sh.
# Sourced by run.sh; every t_core_* function below is discovered and run.
set -u

# ---------------------------------------------------------------------------
# session-context.sh
# ---------------------------------------------------------------------------

t_core_session_context_non_git_repo_silent() {
	local dir
	dir=$(tmp_dir)
	run_hook "$SCAN_DIR/session-context.sh" '{}' CLAUDE_PROJECT_DIR="$dir"
	assert_rc 0 "t_core_session_context_non_git_repo_silent rc"
	assert_eq "$OUT" "" "t_core_session_context_non_git_repo_silent no-stdout"
	rm -rf "$dir"
}

t_core_session_context_basic_repo_state_no_overrides() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/session-context.sh" '{}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_core_session_context_basic_repo_state_no_overrides rc"
	assert_contains "$OUT" "## Repo state" "t_core_session_context_basic_repo_state_no_overrides repo-state-heading"
	assert_contains "$OUT" "branch:" "t_core_session_context_basic_repo_state_no_overrides branch-line"
	assert_contains "$OUT" "uncommitted files:" "t_core_session_context_basic_repo_state_no_overrides uncommitted-line"
	assert_contains "$OUT" "last 3 commits:" "t_core_session_context_basic_repo_state_no_overrides commits-heading"
	assert_contains "$OUT" "init" "t_core_session_context_basic_repo_state_no_overrides commit-message"
	assert_not_contains "$OUT" "## PROGRESS.md" "t_core_session_context_basic_repo_state_no_overrides no-progress-section"
	assert_not_contains "$OUT" "REVIEW.md present" "t_core_session_context_basic_repo_state_no_overrides no-review-note"
	assert_not_contains "$OUT" "harness override" "t_core_session_context_basic_repo_state_no_overrides no-harness-override"
	rm -rf "$repo"
}

t_core_session_context_output_capped_at_20_lines() {
	local repo i line_count
	repo=$(tmp_repo)
	: >"$repo/PROGRESS.md"
	i=0
	while [ "$i" -lt 29 ]; do
		printf 'progress line %s\n' "$i" >>"$repo/PROGRESS.md"
		i=$((i + 1))
	done
	printf '# Review\n' >"$repo/REVIEW.md"
	mkdir -p "$repo/.claude"
	cat >"$repo/.claude/harness.json" <<'JSON'
{
  "maxFileLines": 200,
  "maxFuncLines": 30,
  "stopGate": true,
  "stopGateFullEverySec": 60,
  "sizeGuard": false,
  "formatOnEdit": false,
  "ignore": ["custom/"]
}
JSON
	run_hook "$SCAN_DIR/session-context.sh" '{}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_core_session_context_output_capped_at_20_lines rc"
	line_count=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
	if [ "$line_count" -le 20 ]; then
		_pass "t_core_session_context_output_capped_at_20_lines line-count"
	else
		_fail "t_core_session_context_output_capped_at_20_lines line-count" "got $line_count lines, want <=20"
	fi
	assert_contains "$OUT" "## Repo state" "t_core_session_context_output_capped_at_20_lines repo-state-still-present"
	rm -rf "$repo"
}

t_core_session_context_progress_review_and_harness_override() {
	local repo
	repo=$(tmp_repo)
	printf '# Progress\nfirst line\nsecond line\n' >"$repo/PROGRESS.md"
	printf '# Review\n' >"$repo/REVIEW.md"
	mkdir -p "$repo/.claude"
	printf '{"maxFileLines": 200, "sizeGuard": false}\n' >"$repo/.claude/harness.json"
	run_hook "$SCAN_DIR/session-context.sh" '{}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_core_session_context_progress_review_and_harness_override rc"
	assert_contains "$OUT" "## PROGRESS.md" "t_core_session_context_progress_review_and_harness_override progress-heading"
	assert_contains "$OUT" "first line" "t_core_session_context_progress_review_and_harness_override progress-content"
	assert_contains "$OUT" "note: REVIEW.md present" "t_core_session_context_progress_review_and_harness_override review-note"
	assert_contains "$OUT" "note: harness override: maxFileLines=200" "t_core_session_context_progress_review_and_harness_override maxFileLines-override"
	assert_contains "$OUT" "note: harness override: sizeGuard=false" "t_core_session_context_progress_review_and_harness_override sizeGuard-override"
	rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# turn-stamp.sh
# ---------------------------------------------------------------------------

t_core_turn_stamp_creates_file_no_stdout() {
	local session stamp_base stamp
	session="core-test-session-$$"
	stamp_base="${TMPDIR:-/tmp}"
	stamp_base="${stamp_base%/}"
	stamp="$stamp_base/claude-turn-$session"
	rm -f "$stamp"
	run_hook "$SCAN_DIR/turn-stamp.sh" "{\"session_id\":\"$session\"}"
	assert_rc 0 "t_core_turn_stamp_creates_file_no_stdout rc"
	assert_file_exists "$stamp" "t_core_turn_stamp_creates_file_no_stdout stamp-file"
	assert_eq "$OUT" "" "t_core_turn_stamp_creates_file_no_stdout no-stdout"
	rm -f "$stamp"
}

t_core_turn_stamp_no_session_id_uses_nosession() {
	local stamp_base stamp
	stamp_base="${TMPDIR:-/tmp}"
	stamp_base="${stamp_base%/}"
	stamp="$stamp_base/claude-turn-nosession"
	rm -f "$stamp"
	run_hook "$SCAN_DIR/turn-stamp.sh" '{}'
	assert_rc 0 "t_core_turn_stamp_no_session_id_uses_nosession rc"
	assert_file_exists "$stamp" "t_core_turn_stamp_no_session_id_uses_nosession stamp-file"
	rm -f "$stamp"
}

# ---------------------------------------------------------------------------
# git-guard.sh — the six required named test cases from C10, plus coverage
# of the remaining blocked/allowed patterns.
# ---------------------------------------------------------------------------

t_core_git_guard_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}'
	assert_rc 0 "t_core_git_guard_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_force_denied denied"
}

t_core_git_guard_push_force_with_lease_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force-with-lease origin main"}}'
	assert_rc 0 "t_core_git_guard_push_force_with_lease_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_push_force_with_lease_allowed allowed"
}

t_core_git_guard_push_dash_f_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push -f"}}'
	assert_rc 0 "t_core_git_guard_push_dash_f_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_dash_f_denied denied"
}

t_core_git_guard_commit_message_mentioning_force_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"add force flag\""}}'
	assert_rc 0 "t_core_git_guard_commit_message_mentioning_force_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_commit_message_mentioning_force_allowed allowed"
}

t_core_git_guard_commit_message_containing_dash_n_word_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"please do -n now\""}}'
	assert_rc 0 "t_core_git_guard_commit_message_containing_dash_n_word_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_commit_message_containing_dash_n_word_allowed allowed"
}

t_core_git_guard_commit_message_containing_no_verify_word_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"please --no-verify this change\""}}'
	assert_rc 0 "t_core_git_guard_commit_message_containing_no_verify_word_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_commit_message_containing_no_verify_word_allowed allowed"
}

t_core_git_guard_branch_list_quoted_dash_d_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git branch --list \"feature -D thing\""}}'
	assert_rc 0 "t_core_git_guard_branch_list_quoted_dash_d_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_branch_list_quoted_dash_d_allowed allowed"
}

t_core_git_guard_stash_and_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git stash && git reset --hard"}}'
	assert_rc 0 "t_core_git_guard_stash_and_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_stash_and_reset_hard_denied denied"
}

t_core_git_guard_rm_rf_dot_dist_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf ./dist"}}'
	assert_rc 0 "t_core_git_guard_rm_rf_dot_dist_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_rm_rf_dot_dist_allowed allowed"
}

t_core_git_guard_reset_hard_alone_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git reset --hard HEAD~1"}}'
	assert_rc 0 "t_core_git_guard_reset_hard_alone_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_reset_hard_alone_denied denied"
}

t_core_git_guard_clean_dash_f_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git clean -fd"}}'
	assert_rc 0 "t_core_git_guard_clean_dash_f_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_clean_dash_f_denied denied"
}

t_core_git_guard_checkout_dashdash_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git checkout -- ."}}'
	assert_rc 0 "t_core_git_guard_checkout_dashdash_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_checkout_dashdash_dot_denied denied"
}

t_core_git_guard_restore_dot_bare_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git restore ."}}'
	assert_rc 0 "t_core_git_guard_restore_dot_bare_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_restore_dot_bare_denied denied"
}

t_core_git_guard_restore_staged_dot_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git restore --staged ."}}'
	assert_rc 0 "t_core_git_guard_restore_staged_dot_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_restore_staged_dot_allowed allowed"
}

t_core_git_guard_branch_dash_capital_d_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git branch -D feature/old"}}'
	assert_rc 0 "t_core_git_guard_branch_dash_capital_d_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_branch_dash_capital_d_denied denied"
}

t_core_git_guard_branch_combined_short_flags_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git branch -Df feature/old"}}'
	assert_rc 0 "t_core_git_guard_branch_combined_short_flags_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_branch_combined_short_flags_denied denied"
}

t_core_git_guard_commit_no_verify_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit --no-verify -m x"}}'
	assert_rc 0 "t_core_git_guard_commit_no_verify_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_commit_no_verify_denied denied"
}

t_core_git_guard_commit_dash_n_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -n -m x"}}'
	assert_rc 0 "t_core_git_guard_commit_dash_n_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_commit_dash_n_denied denied"
}

t_core_git_guard_push_combined_short_flags_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push -uf origin main"}}'
	assert_rc 0 "t_core_git_guard_push_combined_short_flags_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_combined_short_flags_denied denied"
}

t_core_git_guard_commit_combined_short_flags_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -nm \"quick fix\""}}'
	assert_rc 0 "t_core_git_guard_commit_combined_short_flags_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_commit_combined_short_flags_denied denied"
}

t_core_git_guard_rm_rf_root_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf /"}}'
	assert_rc 0 "t_core_git_guard_rm_rf_root_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_root_denied denied"
}

t_core_git_guard_rm_rf_home_var_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf $HOME"}}'
	assert_rc 0 "t_core_git_guard_rm_rf_home_var_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_home_var_denied denied"
}

t_core_git_guard_rm_rf_tilde_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf ~"}}'
	assert_rc 0 "t_core_git_guard_rm_rf_tilde_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_tilde_denied denied"
}

t_core_git_guard_rm_rf_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf ."}}'
	assert_rc 0 "t_core_git_guard_rm_rf_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_dot_denied denied"
}

t_core_git_guard_chmod_recursive_777_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"chmod -R 777 ."}}'
	assert_rc 0 "t_core_git_guard_chmod_recursive_777_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_chmod_recursive_777_denied denied"
}

t_core_git_guard_double_space_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git  push --force origin main"}}'
	assert_rc 0 "t_core_git_guard_double_space_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_double_space_push_force_denied denied"
}

t_core_git_guard_tab_push_force_denied() {
	# \t here is a literal backslash-t inside the JSON text (single-quoted, not
	# ANSI-C quoted), so jq/python3 JSON-decode it into a real tab character in
	# tool_input.command — a raw tab byte embedded directly in a JSON string
	# would be invalid JSON and rejected by the parser.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git\tpush --force origin main"}}'
	assert_rc 0 "t_core_git_guard_tab_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_tab_push_force_denied denied"
}

t_core_git_guard_double_space_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git  reset  --hard"}}'
	assert_rc 0 "t_core_git_guard_double_space_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_double_space_reset_hard_denied denied"
}

t_core_git_guard_triple_space_commit_no_verify_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git   commit --no-verify -m x"}}'
	assert_rc 0 "t_core_git_guard_triple_space_commit_no_verify_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_triple_space_commit_no_verify_denied denied"
}

t_core_git_guard_tab_separated_rm_rf_root_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm\t-rf\t/"}}'
	assert_rc 0 "t_core_git_guard_tab_separated_rm_rf_root_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_tab_separated_rm_rf_root_denied denied"
}

t_core_git_guard_stash_and_double_space_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git stash && git  reset --hard"}}'
	assert_rc 0 "t_core_git_guard_stash_and_double_space_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_stash_and_double_space_reset_hard_denied denied"
}

t_core_git_guard_trailing_whitespace_after_verb_still_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force  origin main"}}'
	assert_rc 0 "t_core_git_guard_trailing_whitespace_after_verb_still_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_trailing_whitespace_after_verb_still_denied denied"
}

t_core_git_guard_no_command_field_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{}}'
	assert_rc 0 "t_core_git_guard_no_command_field_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_no_command_field_allowed allowed"
}

t_core_git_guard_commitment_no_verify_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commitment --no-verify"}}'
	assert_rc 0 "t_core_git_guard_commitment_no_verify_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_commitment_no_verify_allowed allowed"
}

t_core_git_guard_branches_dash_capital_d_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git branches -D"}}'
	assert_rc 0 "t_core_git_guard_branches_dash_capital_d_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_branches_dash_capital_d_allowed allowed"
}

t_core_git_guard_cleaner_dash_f_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git cleaner -f"}}'
	assert_rc 0 "t_core_git_guard_cleaner_dash_f_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_cleaner_dash_f_allowed allowed"
}

t_core_git_guard_checkouts_dashdash_dot_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git checkouts -- ."}}'
	assert_rc 0 "t_core_git_guard_checkouts_dashdash_dot_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_checkouts_dashdash_dot_allowed allowed"
}

t_core_git_guard_pushmine_force_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git pushmine --force"}}'
	assert_rc 0 "t_core_git_guard_pushmine_force_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_pushmine_force_allowed allowed"
}

t_core_git_guard_resetter_hard_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git resetter --hard"}}'
	assert_rc 0 "t_core_git_guard_resetter_hard_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_resetter_hard_allowed allowed"
}

t_core_git_guard_push_quoted_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push \"--force\" origin main"}}'
	assert_rc 0 "t_core_git_guard_push_quoted_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_quoted_force_denied denied"
}

t_core_git_guard_reset_quoted_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git reset \"--hard\""}}'
	assert_rc 0 "t_core_git_guard_reset_quoted_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_reset_quoted_hard_denied denied"
}

t_core_git_guard_commit_quoted_no_verify_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit \"--no-verify\" -m x"}}'
	assert_rc 0 "t_core_git_guard_commit_quoted_no_verify_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_commit_quoted_no_verify_denied denied"
}

t_core_git_guard_branch_quoted_dash_d_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git branch \"-D\" old"}}'
	assert_rc 0 "t_core_git_guard_branch_quoted_dash_d_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_branch_quoted_dash_d_denied denied"
}

t_core_git_guard_push_single_quoted_dash_f_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" "{\"tool_input\":{\"command\":\"git push '-f'\"}}"
	assert_rc 0 "t_core_git_guard_push_single_quoted_dash_f_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_single_quoted_dash_f_denied denied"
}

t_core_git_guard_push_force_with_lease_and_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force-with-lease --force origin main"}}'
	assert_rc 0 "t_core_git_guard_push_force_with_lease_and_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_force_with_lease_and_force_denied denied"
}

t_core_git_guard_push_dash_f_and_force_with_lease_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push -f --force-with-lease origin main"}}'
	assert_rc 0 "t_core_git_guard_push_dash_f_and_force_with_lease_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_push_dash_f_and_force_with_lease_denied denied"
}

t_core_git_guard_restore_worktree_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git restore --worktree ."}}'
	assert_rc 0 "t_core_git_guard_restore_worktree_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_restore_worktree_dot_denied denied"
}

# C22 (frozen 2026-09-04) changes this from denied to allowed: the restore
# exception is now "neither --staged nor -S present in args" checked across
# the whole arg list, not "exactly the 4-token --staged-then-. form", so
# --staged in EITHER order relative to "." is allowed. Renamed from
# t_core_git_guard_restore_dot_staged_denied (was: denied) accordingly.
t_core_git_guard_restore_dot_staged_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git restore . --staged"}}'
	assert_rc 0 "t_core_git_guard_restore_dot_staged_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_restore_dot_staged_allowed allowed"
}

t_core_git_guard_quoted_semicolon_push_force_in_message_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"a; git push --force\""}}'
	assert_rc 0 "t_core_git_guard_quoted_semicolon_push_force_in_message_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_quoted_semicolon_push_force_in_message_allowed allowed"
}

t_core_git_guard_unquoted_semicolon_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m x; git push --force"}}'
	assert_rc 0 "t_core_git_guard_unquoted_semicolon_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_unquoted_semicolon_push_force_denied denied"
}

# ---------------------------------------------------------------------------
# Fix round 2 (significant finding): the PART_CAP trigger used to count
# ';'/'&'/'|' characters with a raw, quote-blind `tr`, so an ordinary safe
# command with hundreds of literal operator characters INSIDE quotes (a
# commit message, an echo argument) blew the cap purely on quoted content
# and fell into the coarse, quote-blind grep fallback below — reopening the
# exact quote-leak the quote-aware splitter above exists to close, for
# ordinary-sized commands, not just pathological ones. The cap now counts
# real (quote-aware) split parts, so quoted operators never inflate it.
# `_t_core_repeat_char` (defined further below) builds the padding.
# ---------------------------------------------------------------------------

t_core_git_guard_quoted_semicolons_in_commit_message_allowed() {
	local semis
	semis=$(_t_core_repeat_char ';' 300)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git commit -m \\"%s this mentions git push --force in a msg\\""}}' "$semis")"
	assert_rc 0 "t_core_git_guard_quoted_semicolons_in_commit_message_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_quoted_semicolons_in_commit_message_allowed allowed"
}

t_core_git_guard_quoted_pipes_in_echo_message_allowed() {
	local pipes
	pipes=$(_t_core_repeat_char '|' 250)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"echo \\"%s see: rm -rf / is dangerous, do not chmod -R 777 root\\""}}' "$pipes")"
	assert_rc 0 "t_core_git_guard_quoted_pipes_in_echo_message_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_quoted_pipes_in_echo_message_allowed allowed"
}

# ---------------------------------------------------------------------------
# Fix round (fatal finding): git-guard dispatched the git-subcommand rules by
# reading token[1] (the word immediately after literal "git") as if it were
# always the subcommand. A global git option in that position (-C, -c,
# --no-pager, --git-dir=, ...) made the dispatch match nothing, silently
# skipping every C10 deny rule for that command. _gg_git_find_subcommand now
# walks past any recognised global option to find the real subcommand.
# ---------------------------------------------------------------------------

t_core_git_guard_no_pager_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --no-pager reset --hard"}}'
	assert_rc 0 "t_core_git_guard_no_pager_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_no_pager_reset_hard_denied denied"
}

t_core_git_guard_dash_capital_c_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -C /tmp push --force"}}'
	assert_rc 0 "t_core_git_guard_dash_capital_c_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_dash_capital_c_push_force_denied denied"
}

t_core_git_guard_dash_c_config_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -c user.name=x reset --hard"}}'
	assert_rc 0 "t_core_git_guard_dash_c_config_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_dash_c_config_reset_hard_denied denied"
}

t_core_git_guard_dash_c_config_commit_no_verify_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -c x=y commit --no-verify -m x"}}'
	assert_rc 0 "t_core_git_guard_dash_c_config_commit_no_verify_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_dash_c_config_commit_no_verify_denied denied"
}

t_core_git_guard_git_dir_equals_branch_dash_capital_d_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --git-dir=/foo branch -D old"}}'
	assert_rc 0 "t_core_git_guard_git_dir_equals_branch_dash_capital_d_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_git_dir_equals_branch_dash_capital_d_denied denied"
}

t_core_git_guard_global_option_then_safe_command_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -C /tmp status"}}'
	assert_rc 0 "t_core_git_guard_global_option_then_safe_command_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_global_option_then_safe_command_allowed allowed"
}

# ---------------------------------------------------------------------------
# Fix round 2 (fatal finding): _gg_git_find_subcommand's global-option
# allowlist only recognised a fixed set of literal flags; any OTHER real git
# global option (documented in `git --help`'s own usage synopsis, e.g. -P,
# --icase-pathspecs, --glob-pathspecs, --no-lazy-fetch) aborted the scan with
# the subcommand left unresolved, silently skipping every C10 deny rule. The
# fix makes "skip one token" the default for any "-*" token instead of
# aborting; only the small set of documented two-token forms (-C, -c, ...)
# still explicitly consumes two.
# ---------------------------------------------------------------------------

t_core_git_guard_dash_capital_p_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -P push --force origin main"}}'
	assert_rc 0 "t_core_git_guard_dash_capital_p_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_dash_capital_p_push_force_denied denied"
}

t_core_git_guard_icase_pathspecs_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --icase-pathspecs reset --hard"}}'
	assert_rc 0 "t_core_git_guard_icase_pathspecs_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_icase_pathspecs_reset_hard_denied denied"
}

t_core_git_guard_glob_pathspecs_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --glob-pathspecs reset --hard"}}'
	assert_rc 0 "t_core_git_guard_glob_pathspecs_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_glob_pathspecs_reset_hard_denied denied"
}

t_core_git_guard_no_lazy_fetch_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --no-lazy-fetch reset --hard"}}'
	assert_rc 0 "t_core_git_guard_no_lazy_fetch_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_no_lazy_fetch_reset_hard_denied denied"
}

t_core_git_guard_config_then_unlisted_flag_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -c core.pager=cat -P reset --hard"}}'
	assert_rc 0 "t_core_git_guard_config_then_unlisted_flag_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_config_then_unlisted_flag_reset_hard_denied denied"
}

t_core_git_guard_unlisted_flag_then_safe_command_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -P status"}}'
	assert_rc 0 "t_core_git_guard_unlisted_flag_then_safe_command_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_unlisted_flag_then_safe_command_allowed allowed"
}

# Fix-round regression (round-2 fatal finding): a backslash-escaped quote
# (\" or \') anywhere in an unquoted span used to be misread as a real
# quote-open, silently swallowing everything after it — including a `;`
# separator and the exact "git push --force" pattern C10 requires denying.
# `git push \" --force origin main` is a real `git push --force ...` in
# bash (verified token-by-token: `for a in git push \" --force origin
# main; do echo "[$a]"; done` -> [git][push]["][--force][origin][main]).
t_core_git_guard_escaped_quote_before_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push \\\" --force origin main"}}'
	assert_rc 0 "t_core_git_guard_escaped_quote_before_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_escaped_quote_before_force_denied denied"
}

# `echo hi \" ; git push --force origin main` genuinely executes both
# commands in real bash (the `;` is a real unquoted separator, not swallowed
# by the escaped quote).
t_core_git_guard_escaped_quote_before_semicolon_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo hi \\\" ; git push --force origin main"}}'
	assert_rc 0 "t_core_git_guard_escaped_quote_before_semicolon_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_escaped_quote_before_semicolon_push_force_denied denied"
}

# Same escaped-quote-before-semicolon shape, padded past _gg_LINEAR_THRESHOLD
# so both _gg_split_compound and _gg_tokenize run their python3 dispatch
# (not just the bash char-by-char path) and must still catch the escape.
t_core_git_guard_escaped_quote_long_command_denied() {
	local pad json
	pad=$(_t_core_repeat_char x 600)
	# Built without printf-format-string interpolation of the \\\" segment
	# (printf's own escape processing would corrupt it); $pad is spliced in
	# via a plain double-quoted expansion between single-quoted literals.
	json='{"tool_input":{"command":"echo '"$pad"' hi \\\" ; git push --force origin main"}}'
	run_hook "$SCAN_DIR/git-guard.sh" "$json"
	assert_rc 0 "t_core_git_guard_escaped_quote_long_command_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_escaped_quote_long_command_denied denied"
}

t_core_git_guard_long_command_returns_quickly() {
	local big start end elapsed
	big=''
	while [ "${#big}" -lt 4000 ]; do
		big="${big}echo hi && "
	done
	big="${big}echo done"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_long_command_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_long_command_returns_quickly allowed"
	if [ "$elapsed" -le 2 ]; then
		_pass "t_core_git_guard_long_command_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_long_command_returns_quickly elapsed" "took ${elapsed}s, want <=2s"
	fi
}

# _t_core_repeat_char <char> <count> — builds a <count>-char string of
# <char> repeated, via doubling chunks (not one append per char) so building
# the fixture itself never becomes the thing under test.
_t_core_repeat_char() {
	local ch chunk s n i
	ch=$1
	n=$2
	chunk=''
	i=0
	while [ "$i" -lt 64 ]; do
		chunk="${chunk}${ch}"
		i=$((i + 1))
	done
	s=''
	while [ "${#s}" -lt "$n" ]; do
		s="${s}${chunk}"
	done
	printf '%s' "${s:0:$n}"
}

t_core_git_guard_long_single_argument_returns_quickly() {
	# A single long unsplit argument (no compound operators at all) — the
	# shape of a heredoc body or a multi-KB commit message — used to defeat
	# the tokenizer's O(n^2) char-by-char scan even though _gg_split_compound
	# itself split cheaply (one part). 32,000 chars is the size the adversary
	# measured taking 22.95s end-to-end on the pre-fix script (blowing the
	# PreToolUse timeout:10 from C5 more than 2x over); 5s leaves generous
	# headroom above this fix's real (sub-second) runtime while still catching
	# a quadratic regression.
	local big start end elapsed
	big=$(_t_core_repeat_char x 32000)
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git commit -m \\"%s\\""}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_long_single_argument_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_long_single_argument_returns_quickly allowed"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_core_git_guard_long_single_argument_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_long_single_argument_returns_quickly elapsed" "took ${elapsed}s, want <=5s"
	fi
}

t_core_git_guard_long_non_git_command_returns_quickly() {
	# No watched verb at all, so the tokenizer runs unconditionally before any
	# verb dispatch (per C10) on a long, operator-free single token.
	local big start end elapsed
	big=$(_t_core_repeat_char x 32000)
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"echo %s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_long_non_git_command_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_long_non_git_command_returns_quickly allowed"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_core_git_guard_long_non_git_command_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_long_non_git_command_returns_quickly elapsed" "took ${elapsed}s, want <=5s"
	fi
}

t_core_git_guard_long_argument_then_denied_verb_returns_quickly() {
	# A huge quoted chunk precedes the real operator and the denied verb, so
	# both the compound splitter and the tokenizer must get past the long
	# span quickly and still catch the deny.
	local big start end elapsed
	big=$(_t_core_repeat_char x 32000)
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git commit -m \\"%s\\" && git push --force"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_long_argument_then_denied_verb_returns_quickly rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_long_argument_then_denied_verb_returns_quickly denied"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_core_git_guard_long_argument_then_denied_verb_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_long_argument_then_denied_verb_returns_quickly elapsed" "took ${elapsed}s, want <=5s"
	fi
}

t_core_git_guard_many_short_semicolon_parts_returns_quickly() {
	# Fix-round regression (C15 U1 packet item c: "keep the tokenizer
	# linear-time"): a fix that only swaps the per-part normalise step's
	# `sed` fork for another per-part $(...) call still forks a subshell once
	# per compound part, so a command built from many SHORT `;`-joined parts
	# (a generated multi-step script, or `a;a;a;...`) pays one fork per part
	# and never crosses the single-long-argument python3 dispatch threshold
	# the 4,000-char test above relies on. Measured on the live script before
	# this fix: 2000 such parts took ~3.0s, scaling with part count, not
	# total length.
	local big i start end elapsed
	big='x'
	i=1
	while [ "$i" -lt 3000 ]; do
		big="${big};x"
		i=$((i + 1))
	done
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_many_short_semicolon_parts_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_many_short_semicolon_parts_returns_quickly allowed"
	if [ "$elapsed" -le 3 ]; then
		_pass "t_core_git_guard_many_short_semicolon_parts_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_many_short_semicolon_parts_returns_quickly elapsed" "took ${elapsed}s, want <=3s"
	fi
}

t_core_git_guard_many_short_and_parts_with_denied_verb_returns_quickly() {
	# Same regression as above but with `&&` operators, thousands of short
	# parts, and a denied verb at the end, so the splitter, normaliser and
	# tokenizer must all stay fork-free per part to finish inside the hook's
	# own PreToolUse timeout:10 (C5). This shape (many short && parts) is
	# what silently degraded git-guard from a fast gate to an
	# unreliable/timing-out one pre-fix.
	local big i start end elapsed
	big='echo hi'
	i=1
	while [ "$i" -lt 3000 ]; do
		big="${big} && echo hi"
		i=$((i + 1))
	done
	big="${big} && git push --force"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_many_short_and_parts_with_denied_verb_returns_quickly rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_many_short_and_parts_with_denied_verb_returns_quickly denied"
	if [ "$elapsed" -le 3 ]; then
		_pass "t_core_git_guard_many_short_and_parts_with_denied_verb_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_many_short_and_parts_with_denied_verb_returns_quickly elapsed" "took ${elapsed}s, want <=3s"
	fi
}

# Fix-round regression (round-2 significant finding: python3-absent
# fallback): _gg_tokenize/_gg_split_compound's bash fallback used to
# string-concatenate one character at a time (`_gg_tok="$_gg_tok$_gg_c"`),
# which is O(n^2) wall clock for one long unsplit argument. This builds a
# PATH with only symlinked core tools (no python3), matching the repo fact
# that "hook subprocesses may run with a minimal PATH." NOTE: at 32,000
# chars this input is over _gg_CHAR_CAP (20000), so it actually exercises the
# coarse BIG_PATTERN grep fast-path (which runs regardless of python3), not
# _gg_tokenize_bash/_gg_split_compound_bash — see the *_under_cap test below
# for a size that stays under CHAR_CAP and actually runs the bash tokenizer.
# Kept because it is still a real regression guard for the over-cap path.
t_core_git_guard_no_python3_long_single_argument_returns_quickly() {
	local minpath tool p big start end elapsed
	minpath="$(tmp_dir)/minpath"
	mkdir -p "$minpath"
	for tool in bash sh cat printf dirname env jq date grep; do
		p=$(command -v "$tool" 2>/dev/null) || continue
		ln -sf "$p" "$minpath/$tool"
	done
	big=$(_t_core_repeat_char x 32000)
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git commit -m \\"%s\\""}}' "$big")" "PATH=$minpath"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_no_python3_long_single_argument_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_no_python3_long_single_argument_returns_quickly allowed"
	# Generous headroom under the 10s PreToolUse timeout (C5): the pre-fix
	# quadratic bash path took 22.85s at this size with no python3 on PATH.
	if [ "$elapsed" -le 9 ]; then
		_pass "t_core_git_guard_no_python3_long_single_argument_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_no_python3_long_single_argument_returns_quickly elapsed" "took ${elapsed}s, want <=9s (no python3 on PATH)"
	fi
	rm -rf "$minpath"
}

# Fix round (significant finding): the test above pads to 32,000 chars,
# which is over the 20,000-char cap and so hits the coarse grep fast-path
# regardless of PATH — it never reaches the awk normaliser, so it did not
# actually guard the under-cap path. This test stays *under* the cap
# (19,000 chars), so the awk-based normalise/split pass (C22) is what
# actually runs and must still finish comfortably inside the 10s
# PreToolUse timeout (C5). C22 drops python3 entirely (no longer needed as
# a fallback) and replaces the old bash char-loop tokenizer with a single
# awk pass, so this minimal PATH now includes awk (the one tool the C22
# design actually depends on for the under-cap path) instead of the
# python3-absence the test was originally named for.
t_core_git_guard_no_python3_under_cap_single_argument_returns_quickly() {
	local minpath tool p big start end elapsed
	minpath="$(tmp_dir)/minpath-undercap"
	mkdir -p "$minpath"
	for tool in bash sh cat printf dirname env jq date grep awk; do
		p=$(command -v "$tool" 2>/dev/null) || continue
		ln -sf "$p" "$minpath/$tool"
	done
	big=$(_t_core_repeat_char x 19000)
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git commit -m \\"%s\\""}}' "$big")" "PATH=$minpath"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_no_python3_under_cap_single_argument_returns_quickly rc"
	assert_eq "$OUT" "" "t_core_git_guard_no_python3_under_cap_single_argument_returns_quickly allowed"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_core_git_guard_no_python3_under_cap_single_argument_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_no_python3_under_cap_single_argument_returns_quickly elapsed" "took ${elapsed}s, want <=5s (bash tokenizer fallback, under CHAR_CAP)"
	fi
	rm -rf "$minpath"
}

# Fix-round regression (round-2 significant finding): the "rm "* dispatch's
# rm-target extraction forked a subshell per matching compound part via
# `_gg_target=$(_gg_last_word "$_part")` — the same per-part-fork class of
# bug round 1 already fixed once for _gg_normalize_ws's old `sed` call, left
# unaudited at this second fork site. Thousands of `;`-joined "rm -rf x"
# parts (all matching the "rm "* + recursive+force gate) ending in one
# "rm -rf /" must still deny well inside the 10s PreToolUse timeout (C5).
t_core_git_guard_many_rm_rf_parts_with_denied_target_returns_quickly() {
	local big i start end elapsed
	big='rm -rf x'
	i=1
	while [ "$i" -lt 5000 ]; do
		big="${big};rm -rf x"
		i=$((i + 1))
	done
	big="${big};rm -rf /"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_many_rm_rf_parts_with_denied_target_returns_quickly rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_many_rm_rf_parts_with_denied_target_returns_quickly denied"
	if [ "$elapsed" -le 8 ]; then
		_pass "t_core_git_guard_many_rm_rf_parts_with_denied_target_returns_quickly elapsed"
	else
		_fail "t_core_git_guard_many_rm_rf_parts_with_denied_target_returns_quickly elapsed" "took ${elapsed}s, want <=8s"
	fi
}

# ---------------------------------------------------------------------------
# Fix round (fatal finding): rm -rf targets and the git checkout -- . rule
# used to match on the raw, unstripped part, so a quoted form of the same
# dangerous target bypassed the deny while bash executes it identically.
# Every rule now matches on the same quote-stripped token array.
# ---------------------------------------------------------------------------

t_core_git_guard_rm_rf_quoted_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf \".\""}}'
	assert_rc 0 "t_core_git_guard_rm_rf_quoted_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_quoted_dot_denied denied"
}

t_core_git_guard_rm_rf_quoted_tilde_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" "{\"tool_input\":{\"command\":\"rm -rf '~'\"}}"
	assert_rc 0 "t_core_git_guard_rm_rf_quoted_tilde_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_quoted_tilde_denied denied"
}

t_core_git_guard_rm_rf_quoted_home_var_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf \"$HOME\""}}'
	assert_rc 0 "t_core_git_guard_rm_rf_quoted_home_var_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_quoted_home_var_denied denied"
}

t_core_git_guard_rm_rf_quoted_root_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf \"/\""}}'
	assert_rc 0 "t_core_git_guard_rm_rf_quoted_root_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_rm_rf_quoted_root_denied denied"
}

t_core_git_guard_checkout_dashdash_quoted_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git checkout -- \".\""}}'
	assert_rc 0 "t_core_git_guard_checkout_dashdash_quoted_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_checkout_dashdash_quoted_dot_denied denied"
}

t_core_git_guard_restore_staged_quoted_dot_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git restore --staged \".\""}}'
	assert_rc 0 "t_core_git_guard_restore_staged_quoted_dot_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_restore_staged_quoted_dot_allowed allowed"
}

t_core_git_guard_rm_rf_quoted_dist_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf \"./dist\""}}'
	assert_rc 0 "t_core_git_guard_rm_rf_quoted_dist_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_rm_rf_quoted_dist_allowed allowed"
}

# ---------------------------------------------------------------------------
# Fix round (significant finding): the bash fallback tokenizer is one loop
# iteration per character, which is too slow at scale even though it never
# string-concatenates. Above a size/part-count cap, git-guard now skips
# tokenization entirely and decides with one linear grep pass instead, so a
# huge command can never blow the PreToolUse timeout:10 (C5) into a silent
# allow. Measured with `date +%s` (bash 3.2 has no EPOCHREALTIME).
# ---------------------------------------------------------------------------

t_core_git_guard_huge_command_with_force_denied_fast() {
	local big start end elapsed
	big=$(_t_core_repeat_char x 100000)
	big="git push --force ${big}"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_huge_command_with_force_denied_fast rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_huge_command_with_force_denied_fast denied"
	if [ "$elapsed" -le 2 ]; then
		_pass "t_core_git_guard_huge_command_with_force_denied_fast elapsed"
	else
		_fail "t_core_git_guard_huge_command_with_force_denied_fast elapsed" "took ${elapsed}s, want <=2s"
	fi
}

t_core_git_guard_huge_command_without_force_allowed_fast() {
	local big start end elapsed
	big=$(_t_core_repeat_char x 100000)
	big="echo ${big}"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_huge_command_without_force_allowed_fast rc"
	assert_eq "$OUT" "" "t_core_git_guard_huge_command_without_force_allowed_fast allowed"
	if [ "$elapsed" -le 2 ]; then
		_pass "t_core_git_guard_huge_command_without_force_allowed_fast elapsed"
	else
		_fail "t_core_git_guard_huge_command_without_force_allowed_fast elapsed" "took ${elapsed}s, want <=2s"
	fi
}

t_core_git_guard_thousand_part_compound_force_denied_fast() {
	local part big i start end elapsed
	part=$(_t_core_repeat_char x 600)
	big=''
	i=0
	while [ "$i" -lt 1000 ]; do
		big="${big}echo ${part};"
		i=$((i + 1))
	done
	big="${big}git push --force"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_thousand_part_compound_force_denied_fast rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_thousand_part_compound_force_denied_fast denied"
	if [ "$elapsed" -le 2 ]; then
		_pass "t_core_git_guard_thousand_part_compound_force_denied_fast elapsed"
	else
		_fail "t_core_git_guard_thousand_part_compound_force_denied_fast elapsed" "took ${elapsed}s, want <=2s"
	fi
}

# Regression: the huge-command fallback pattern for rm must fire from a
# single "rm -rf" occurrence alone (a combined "-rf" cluster has only one
# dash), not rely on a second, unrelated "-" appearing later in the padding
# to complete a two-part flag match.
t_core_git_guard_huge_command_single_rm_rf_root_denied_fast() {
	local big start end elapsed
	big=$(_t_core_repeat_char x 100000)
	big="echo ${big}; rm -rf /"
	start=$(date +%s)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%s"}}' "$big")"
	end=$(date +%s)
	elapsed=$((end - start))
	assert_rc 0 "t_core_git_guard_huge_command_single_rm_rf_root_denied_fast rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_huge_command_single_rm_rf_root_denied_fast denied"
	if [ "$elapsed" -le 2 ]; then
		_pass "t_core_git_guard_huge_command_single_rm_rf_root_denied_fast elapsed"
	else
		_fail "t_core_git_guard_huge_command_single_rm_rf_root_denied_fast elapsed" "took ${elapsed}s, want <=2s"
	fi
}

# ---------------------------------------------------------------------------
# C22 (frozen 2026-09-04) required new test cases, beyond the behaviour kept
# from the prior tokenizer design (still exercised above).
# ---------------------------------------------------------------------------

t_core_git_guard_backslash_newline_continuation_push_force_denied() {
	# The command field (after JSON decoding) is: git push \<REALNEWLINE>
	# --force origin main — a real line-continuation, joined by step 2(a)
	# into "git push --force origin main". In this single-quoted bash JSON
	# literal, \\\n is 4 literal characters: \\ (JSON escape for one
	# backslash) followed by \n (JSON escape for one real newline) — the
	# same technique the existing tab test above uses for a literal tab.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push \\\n --force origin main"}}'
	assert_rc 0 "t_core_git_guard_backslash_newline_continuation_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_backslash_newline_continuation_push_force_denied denied"
}

t_core_git_guard_attr_source_head_reset_hard_denied() {
	# C22 finds the subcommand by scanning ALL tokens after "git" for the
	# first one that is an exact watched-verb match, so an unlisted global
	# option/value pair like "--attr-source HEAD" is simply skipped, no
	# allowlist needed.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git --attr-source HEAD reset --hard"}}'
	assert_rc 0 "t_core_git_guard_attr_source_head_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_attr_source_head_reset_hard_denied denied"
}

t_core_git_guard_dash_c_core_pager_push_dash_f_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -c core.pager=cat push -f"}}'
	assert_rc 0 "t_core_git_guard_dash_c_core_pager_push_dash_f_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_dash_c_core_pager_push_dash_f_denied denied"
}

t_core_git_guard_dash_capital_c_restore_staged_dot_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git -C /tmp restore --staged ."}}'
	assert_rc 0 "t_core_git_guard_dash_capital_c_restore_staged_dot_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_dash_capital_c_restore_staged_dot_allowed allowed"
}

t_core_git_guard_clean_dash_xdf_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git clean -xdf"}}'
	assert_rc 0 "t_core_git_guard_clean_dash_xdf_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_clean_dash_xdf_denied denied"
}

t_core_git_guard_header_comment_present() {
	local content
	content=$(cat "$SCAN_DIR/git-guard.sh")
	assert_contains "$content" "This is a regex blocklist over a command string" "t_core_git_guard_header_comment_present opening"
	assert_contains "$content" "it is not a security boundary" "t_core_git_guard_header_comment_present disclaimer"
	assert_contains "$content" "CI is the real backstop." "t_core_git_guard_header_comment_present closing"
}

# ---------------------------------------------------------------------------
# Fix round 1 (fatal finding): if the single awk normalize/split pass fails
# to emit a well-formed "N..." record — awk missing, or an awk that exists
# on PATH but returns no stdout (a stand-in for a non-GNU awk whose RS/
# string-escape handling diverges) — git-guard must fall back to gg_coarse's
# grep-based deny check instead of silently allowing every command through.
# ---------------------------------------------------------------------------

t_core_git_guard_broken_awk_falls_back_to_coarse_deny() {
	local fakebin
	fakebin=$(tmp_dir)
	cat >"$fakebin/awk" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
	chmod +x "$fakebin/awk"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' PATH="$fakebin:$PATH"
	assert_rc 0 "t_core_git_guard_broken_awk_falls_back_to_coarse_deny rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_broken_awk_falls_back_to_coarse_deny denied"
	rm -rf "$fakebin"
}

t_core_git_guard_broken_awk_still_allows_safe_command() {
	local fakebin
	fakebin=$(tmp_dir)
	cat >"$fakebin/awk" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
	chmod +x "$fakebin/awk"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo hello"}}' PATH="$fakebin:$PATH"
	assert_rc 0 "t_core_git_guard_broken_awk_still_allows_safe_command rc"
	assert_eq "$OUT" "" "t_core_git_guard_broken_awk_still_allows_safe_command allowed"
	rm -rf "$fakebin"
}

t_core_git_guard_no_awk_on_path_falls_back_to_coarse_deny() {
	# Build a PATH with every tool git-guard/hookout need except awk, by
	# symlinking each real binary in (none of these live only alongside awk,
	# so this genuinely removes awk from resolution without losing the rest).
	local fakebin tool tp
	fakebin=$(tmp_dir)
	for tool in bash cat dirname jq python3 grep printf; do
		tp=$(type -P "$tool" 2>/dev/null) || continue
		[ -n "$tp" ] || continue
		ln -s "$tp" "$fakebin/$tool"
	done
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"rm -rf /"}}' PATH="$fakebin"
	assert_rc 0 "t_core_git_guard_no_awk_on_path_falls_back_to_coarse_deny rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_no_awk_on_path_falls_back_to_coarse_deny denied"
	rm -rf "$fakebin"
}

# ---------------------------------------------------------------------------
# Fix round 1 (significant finding): a backslash-escaped operator (\;, \&,
# \|) outside quotes is inert in real bash — it escapes the operator away,
# so the command never actually splits there. git-guard must not treat it
# as a real separator either.
# ---------------------------------------------------------------------------

t_core_git_guard_escaped_semicolon_before_push_force_allowed() {
	# Raw command after JSON-decode: echo a\; git push --force — one
	# harmless echo in real bash (verified: bash -c 'set -x; echo a\;
	# git push --force' -> `+ echo 'a;' git push --force`, git never runs).
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo a\\; git push --force"}}'
	assert_rc 0 "t_core_git_guard_escaped_semicolon_before_push_force_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_escaped_semicolon_before_push_force_allowed allowed"
}

# ---------------------------------------------------------------------------
# Fix round 1 (fatal finding): bash's own unescaping of a stray backslash
# inside an unquoted word produces the exact denied flag/verb text (real
# bash: `for a in git push --forc\e origin main; do echo [$a]; done` ->
# [git][push][--force][origin][main]), so git-guard's normaliser must strip
# that backslash the same way instead of comparing "--forc\e" != "--force".
# ---------------------------------------------------------------------------

t_core_git_guard_backslash_stray_in_force_flag_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --forc\\e origin main"}}'
	assert_rc 0 "t_core_git_guard_backslash_stray_in_force_flag_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_backslash_stray_in_force_flag_denied denied"
}

t_core_git_guard_backslash_stray_in_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git rese\\t --hard"}}'
	assert_rc 0 "t_core_git_guard_backslash_stray_in_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_backslash_stray_in_reset_hard_denied denied"
}

t_core_git_guard_backslash_stray_in_no_verify_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit --no-verif\\y -m x"}}'
	assert_rc 0 "t_core_git_guard_backslash_stray_in_no_verify_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_backslash_stray_in_no_verify_denied denied"
}

# ---------------------------------------------------------------------------
# Fix round 1 (significant findings): C22's stated "Target <= 160 lines
# including comments" for git-guard.sh had no oracle-visible check anywhere
# (unlike REVIEW.md/PROGRESS.md/step-file budgets), so a 33% overage shipped
# invisibly. Enforce it from this unit's own test file, and pin the portable
# (non-\0-dependent) awk RS the rewrite uses to slurp multi-line commands.
# ---------------------------------------------------------------------------

t_core_git_guard_line_count_within_c22_budget() {
	local n
	n=$(wc -l <"$SCAN_DIR/git-guard.sh")
	if [ "$n" -le 160 ]; then
		_pass "t_core_git_guard_line_count_within_c22_budget"
	else
		_fail "t_core_git_guard_line_count_within_c22_budget" "wc -l = $n, want <= 160 (C22 target)"
	fi
}

t_core_git_guard_awk_uses_portable_paragraph_mode_rs() {
	local begin_line
	begin_line=$(grep -m1 '^BEGIN{' "$SCAN_DIR/git-guard.sh")
	assert_contains "$begin_line" 'RS=""' "t_core_git_guard_awk_uses_portable_paragraph_mode_rs uses RS=\"\""
	assert_not_contains "$begin_line" 'RS="\0"' "t_core_git_guard_awk_uses_portable_paragraph_mode_rs no RS=\"\\0\" dependency"
}

# ---------------------------------------------------------------------------
# Fix round 2 (fatal finding): the awk normaliser's RS="" (paragraph mode)
# splits a command containing a blank line into multiple awk records; PARTS
# accumulates parts from every record, but the ">200 parts" coarse-grep
# fallback (C10 step 3: "the coarse grep of step 1 applies to the whole
# text") used to run only against the LAST record's normalised text, so a
# denied verb sitting in an EARLIER paragraph was silently dropped whenever
# the total part count crossed 200. The fallback now greps the raw, complete
# $cmd (which grep scans line-by-line regardless of paragraph breaks), so it
# always covers the whole command. Each fixture below pairs a denied verb in
# the FIRST paragraph with a second, blank-line-separated paragraph built
# from 201 ';'-joined parts so the total part count exceeds the 200 cap and
# actually exercises the fallback (not the ordinary per-part loop).
# ---------------------------------------------------------------------------

_t_core_git_guard_many_parts() {
	local n first i s
	n=$1
	first=$2
	s=$first
	i=1
	while [ "$i" -lt "$n" ]; do
		s="${s};x"
		i=$((i + 1))
	done
	printf '%s' "$s"
}

t_core_git_guard_blank_line_paragraph_split_push_force_in_first_paragraph_denied() {
	# The JSON literal's "\\n\\n" (produced by printf's own backslash
	# processing of the format string) decodes, once hook_field runs jq/
	# python3 over it, to two real newlines — a blank line separating the
	# first paragraph from the 201-part tail, same technique as the
	# existing backslash-newline-continuation test above.
	local tail
	tail=$(_t_core_git_guard_many_parts 201 x)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git push --force origin main\\n\\n%s"}}' "$tail")"
	assert_rc 0 "t_core_git_guard_blank_line_paragraph_split_push_force_in_first_paragraph_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_blank_line_paragraph_split_push_force_in_first_paragraph_denied denied"
}

t_core_git_guard_blank_line_paragraph_split_rm_rf_root_in_first_paragraph_denied() {
	local tail
	tail=$(_t_core_git_guard_many_parts 201 x)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"rm -rf /\\n\\n%s"}}' "$tail")"
	assert_rc 0 "t_core_git_guard_blank_line_paragraph_split_rm_rf_root_in_first_paragraph_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_core_git_guard_blank_line_paragraph_split_rm_rf_root_in_first_paragraph_denied denied"
}

t_core_git_guard_blank_line_paragraph_split_safe_first_paragraph_over_cap_allowed() {
	# Same shape (blank line, >200 total parts) but with a harmless first
	# paragraph, so the fallback's coarse grep must not false-positive.
	local tail
	tail=$(_t_core_git_guard_many_parts 201 x)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"echo hello world\\n\\n%s"}}' "$tail")"
	assert_rc 0 "t_core_git_guard_blank_line_paragraph_split_safe_first_paragraph_over_cap_allowed rc"
	assert_eq "$OUT" "" "t_core_git_guard_blank_line_paragraph_split_safe_first_paragraph_over_cap_allowed allowed"
}

# ---------------------------------------------------------------------------
# pre-compact-backup.sh
# ---------------------------------------------------------------------------

t_core_pre_compact_backup_copies_transcript() {
	local backup_dir transcript_src copied
	backup_dir="$(tmp_dir)/backups"
	transcript_src="$(tmp_dir)/transcript.jsonl"
	printf '{"line":1}\n' >"$transcript_src"
	run_hook "$SCAN_DIR/pre-compact-backup.sh" \
		"{\"transcript_path\":\"$transcript_src\",\"session_id\":\"sess1\",\"trigger\":\"manual\"}" \
		CC_BACKUP_DIR="$backup_dir"
	assert_rc 0 "t_core_pre_compact_backup_copies_transcript rc"
	copied=$(ls "$backup_dir" 2>/dev/null | head -1)
	assert_contains "$copied" "_sess1_manual.jsonl" "t_core_pre_compact_backup_copies_transcript filename"
	rm -rf "$backup_dir" "$transcript_src"
}

t_core_pre_compact_backup_missing_transcript_ok() {
	local backup_dir
	backup_dir="$(tmp_dir)/backups-missing"
	run_hook "$SCAN_DIR/pre-compact-backup.sh" '{}' CC_BACKUP_DIR="$backup_dir"
	assert_rc 0 "t_core_pre_compact_backup_missing_transcript_ok rc"
	assert_eq "$OUT" "" "t_core_pre_compact_backup_missing_transcript_ok no-stdout"
	rm -rf "$backup_dir"
}

t_core_pre_compact_backup_retention_keeps_50_newest() {
	local backup_dir i epoch fname transcript_src count oldest newest
	backup_dir="$(tmp_dir)/retention"
	mkdir -p "$backup_dir"
	i=0
	while [ "$i" -lt 52 ]; do
		epoch=$(printf '%010d' "$((1000000000 + i))")
		fname="${epoch}_sess_manual.jsonl"
		printf 'x' >"$backup_dir/$fname"
		i=$((i + 1))
	done
	transcript_src="$(tmp_dir)/final.jsonl"
	printf 'x' >"$transcript_src"
	run_hook "$SCAN_DIR/pre-compact-backup.sh" \
		"{\"transcript_path\":\"$transcript_src\",\"session_id\":\"final\",\"trigger\":\"auto\"}" \
		CC_BACKUP_DIR="$backup_dir"
	assert_rc 0 "t_core_pre_compact_backup_retention_keeps_50_newest rc"
	count=$(ls "$backup_dir" 2>/dev/null | wc -l | tr -d ' ')
	assert_eq "$count" "50" "t_core_pre_compact_backup_retention_keeps_50_newest count"
	oldest="$backup_dir/$(printf '%010d' 1000000000)_sess_manual.jsonl"
	assert_file_missing "$oldest" "t_core_pre_compact_backup_retention_keeps_50_newest oldest-pruned"
	newest=$(ls "$backup_dir" 2>/dev/null | sort | tail -1)
	assert_contains "$newest" "final_auto.jsonl" "t_core_pre_compact_backup_retention_keeps_50_newest newest-kept"
	rm -rf "$backup_dir" "$transcript_src"
}

# C22 follow-up: bare newlines and a single & are statement separators too.
t_core_git_guard_newline_separated_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo hello\ngit push --force origin main"}}'
	assert_rc 0 "newline-separated push --force: rc 0"
	assert_contains "$OUT" '"deny"' "newline-separated push --force: denied"
}
t_core_git_guard_newline_separated_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cd /repo\ngit reset --hard"}}'
	assert_contains "$OUT" '"deny"' "newline-separated reset --hard: denied"
}
t_core_git_guard_background_ampersand_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo hi & git push --force"}}'
	assert_contains "$OUT" '"deny"' "single & separated push --force: denied"
}
t_core_git_guard_quoted_newline_message_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"a\nb; git push --force\""}}'
	assert_rc 0 "quoted newline in message: rc 0"
	assert_not_contains "$OUT" '"deny"' "quoted newline in message: allowed"
}
