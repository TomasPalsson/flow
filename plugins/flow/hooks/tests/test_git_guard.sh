#!/usr/bin/env bash
# test_git_guard.sh — git-guard.sh, spec 003 slice G2.
#
# Covers B1/FU-01 (shell keywords and wrappers in front of a part), B16/FU-01
# (heredoc bodies are text, not commands), FU-22 (per-project deny list),
# FU-34 (the deny reason names a real escape hatch) and C-B (`flow off` no
# longer silences this hook; `.claude/flow.unsafe` and CC_NO_GIT_GUARD=1 do).
# The pre-existing cases live in test_core.sh and stay there.

# _t_gg_repeat_char <char> <count> — <count> copies of <char>, built by
# doubling chunks so the fixture itself is never the slow part.
_t_gg_repeat_char() {
	local ch=$1 n=$2 chunk='' s='' i=0
	while [ "$i" -lt 64 ]; do
		chunk="${chunk}${ch}"
		i=$((i + 1))
	done
	while [ "${#s}" -lt "$n" ]; do s="${s}${chunk}"; done
	printf '%s' "${s:0:$n}"
}

# --- B1/FU-01: leading shell keywords and wrappers -------------------------

t_gg_keyword_then_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"if true; then git push --force origin main; fi"}}'
	assert_rc 0 "t_gg_keyword_then_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_keyword_then_push_force_denied denied"
}

t_gg_keyword_do_branch_delete_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"for b in a b; do git branch -D \"$b\"; done"}}'
	assert_rc 0 "t_gg_keyword_do_branch_delete_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_keyword_do_branch_delete_denied denied"
}

t_gg_nohup_rm_rf_root_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"nohup rm -rf /"}}'
	assert_rc 0 "t_gg_nohup_rm_rf_root_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_nohup_rm_rf_root_denied denied"
}

t_gg_var_assignment_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"X=1 git reset --hard"}}'
	assert_rc 0 "t_gg_var_assignment_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_var_assignment_reset_hard_denied denied"
}

t_gg_time_git_status_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"time git status"}}'
	assert_rc 0 "t_gg_time_git_status_allowed rc"
	assert_eq "$OUT" "" "t_gg_time_git_status_allowed allowed"
}

t_gg_if_git_fetch_then_reset_hard_denied() {
	# finance/opengym-live deploy.sh:17-18 verbatim: the first part is a safe
	# `git fetch`, the second is the destructive one behind `then`.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"if git fetch; then git reset --hard origin/main; fi"}}'
	assert_rc 0 "t_gg_if_git_fetch_then_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_if_git_fetch_then_reset_hard_denied denied"
}

# `case` puts the git call after a pattern token, so the head is never `git`
# even after stripping — this is the "scan for git anywhere in a part that had
# a wrapper" half of the rule.
t_gg_case_wrapper_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"case $x in a) git push --force origin main;; esac"}}'
	assert_rc 0 "t_gg_case_wrapper_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_case_wrapper_push_force_denied denied"
}

t_gg_env_wrapper_with_options_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"env -i git push --force origin main"}}'
	assert_rc 0 "t_gg_env_wrapper_with_options_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_env_wrapper_with_options_push_force_denied denied"
}

t_gg_plain_word_before_git_still_allowed() {
	# No wrapper was stripped, so a bare `git` deeper in the part is an
	# argument (here: a grep pattern), not a command to judge.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"grep git push --force notes.txt"}}'
	assert_rc 0 "t_gg_plain_word_before_git_still_allowed rc"
	assert_eq "$OUT" "" "t_gg_plain_word_before_git_still_allowed allowed"
}

# --- B16/FU-01: heredoc bodies are not commands ---------------------------

t_gg_heredoc_body_reset_hard_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > d.sh <<'"'"'EOF'"'"'\ngit reset --hard origin/main\nEOF"}}'
	assert_rc 0 "t_gg_heredoc_body_reset_hard_allowed rc"
	assert_eq "$OUT" "" "t_gg_heredoc_body_reset_hard_allowed allowed"
}

t_gg_heredoc_unquoted_delimiter_rm_rf_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > runbook.md <<MD\nrm -rf /\nMD"}}'
	assert_rc 0 "t_gg_heredoc_unquoted_delimiter_rm_rf_allowed rc"
	assert_eq "$OUT" "" "t_gg_heredoc_unquoted_delimiter_rm_rf_allowed allowed"
}

t_gg_heredoc_dash_delimiter_indented_terminator_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat <<-\"EOF\" > x.sh\n\tgit push --force origin main\n\tEOF"}}'
	assert_rc 0 "t_gg_heredoc_dash_delimiter_indented_terminator_allowed rc"
	assert_eq "$OUT" "" "t_gg_heredoc_dash_delimiter_indented_terminator_allowed allowed"
}

t_gg_command_after_heredoc_terminator_still_denied() {
	# Only the body is excised; a real command on the line after the
	# delimiter is still a part and still judged.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > d.sh <<EOF\nharmless\nEOF\ngit push --force origin main"}}'
	assert_rc 0 "t_gg_command_after_heredoc_terminator_still_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_command_after_heredoc_terminator_still_denied denied"
}

t_gg_herestring_is_not_a_heredoc() {
	# `<<<` opens no body, so nothing after it may be swallowed.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"grep x <<<\"foo\"\ngit push --force origin main"}}'
	assert_rc 0 "t_gg_herestring_is_not_a_heredoc rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_herestring_is_not_a_heredoc denied"
}

t_gg_left_shift_is_not_a_heredoc() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo $((1<<2))\ngit reset --hard"}}'
	assert_rc 0 "t_gg_left_shift_is_not_a_heredoc rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_left_shift_is_not_a_heredoc denied"
}

# --- FU-22: per-project deny list -----------------------------------------

t_gg_project_deny_list_terraform_destroy_denied() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy","task tf:destroy"]}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"terraform destroy -auto-approve"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_project_deny_list_terraform_destroy_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_project_deny_list_terraform_destroy_denied denied"
	assert_contains "$OUT" 'terraform destroy' "t_gg_project_deny_list_terraform_destroy_denied names the entry"
	rm -rf "$repo"
}

t_gg_project_deny_list_after_keyword_denied() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["task tf:destroy"]}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"if true; then task tf:destroy:main:approve; fi"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_project_deny_list_after_keyword_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_project_deny_list_after_keyword_denied denied"
	rm -rf "$repo"
}

# A prefix ends at a non-alphanumeric boundary, so "terraform destroy" covers
# `terraform destroy -auto-approve` and "task tf:destroy" covers
# `task tf:destroy:main:approve` (above) without swallowing a longer word.
t_gg_project_deny_list_prefix_only_matches_whole_words() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"terraform destroyer --dry-run"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_project_deny_list_prefix_only_matches_whole_words rc"
	assert_eq "$OUT" "" "t_gg_project_deny_list_prefix_only_matches_whole_words allowed"
	rm -rf "$repo"
}

# Fix round 1: hook_config returns "" without jq (frozen by C-A), so the deny
# list used to be silently inert on a jq-less machine while the builtin rules
# kept working — protection a project asked for, gone with no message.
# _t_gg_bin_without <tool>... — a PATH dir holding every tool git-guard needs
# EXCEPT the named ones.
_t_gg_bin_without() {
	local bin t p s skip
	bin=$(tmp_dir)/without
	mkdir -p "$bin"
	for t in bash awk grep sed cat tr head date mktemp git dirname jq python3; do
		skip=0
		for s in "$@"; do [ "$t" = "$s" ] && skip=1; done
		[ "$skip" = 1 ] && continue
		p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$bin/$t"
	done
	printf '%s' "$bin"
}

t_gg_project_deny_list_without_jq_still_denies() {
	local repo bin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	bin=$(_t_gg_bin_without jq)
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"terraform destroy -auto-approve"}}' "PATH=$bin" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_project_deny_list_without_jq_still_denies rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_project_deny_list_without_jq_still_denies denied"
	assert_contains "$OUT" 'terraform destroy' "t_gg_project_deny_list_without_jq_still_denies names the entry"
	rm -rf "$repo" "$bin"
}

t_gg_without_jq_unlisted_command_still_allowed() {
	# The python3 fallback must not widen the list it reads.
	local repo bin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	bin=$(_t_gg_bin_without jq)
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"terraform plan"}}' "PATH=$bin" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_without_jq_unlisted_command_still_allowed rc"
	assert_eq "$OUT" "" "t_gg_without_jq_unlisted_command_still_allowed allowed"
	rm -rf "$repo" "$bin"
}

# Fix round 2: the coarse path (>20000 chars, >200 parts, unparsable) greps the
# builtin GG_BIG regex, which contains no user entries — so a project's deny
# list used to fail open there with no message. It has no parts to prefix-match
# against, so the entry is looked for anywhere in the raw text, still ending on
# a non-alphanumeric boundary.

t_gg_coarse_over_size_cap_still_honours_deny_list() {
	local repo pad
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	pad=$(_t_gg_repeat_char x 21000)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"terraform destroy -auto-approve # %s"}}' "$pad")" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_coarse_over_size_cap_still_honours_deny_list rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_coarse_over_size_cap_still_honours_deny_list denied"
	assert_contains "$OUT" 'terraform destroy' "t_gg_coarse_over_size_cap_still_honours_deny_list names the entry"
	rm -rf "$repo"
}

t_gg_coarse_over_part_cap_still_honours_deny_list() {
	local repo cmd i
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	cmd=""
	i=0
	while [ "$i" -lt 205 ]; do
		cmd="${cmd}true; "
		i=$((i + 1))
	done
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"%sterraform destroy"}}' "$cmd")" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_coarse_over_part_cap_still_honours_deny_list rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_coarse_over_part_cap_still_honours_deny_list denied"
	rm -rf "$repo"
}

t_gg_coarse_deny_list_still_ends_on_a_word_boundary() {
	local repo pad
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	pad=$(_t_gg_repeat_char x 21000)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"terraform destroyer --dry-run # %s"}}' "$pad")" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_coarse_deny_list_still_ends_on_a_word_boundary rc"
	assert_eq "$OUT" "" "t_gg_coarse_deny_list_still_ends_on_a_word_boundary allowed"
	rm -rf "$repo"
}

t_gg_coarse_without_a_deny_list_leaves_big_commands_alone() {
	local repo pad
	repo=$(tmp_repo)
	pad=$(_t_gg_repeat_char x 21000)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"echo hi # %s"}}' "$pad")" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_coarse_without_a_deny_list_leaves_big_commands_alone rc"
	assert_eq "$OUT" "" "t_gg_coarse_without_a_deny_list_leaves_big_commands_alone allowed"
	rm -rf "$repo"
}

# Fix round 2: with NEITHER jq nor python3, hook_field cannot read the payload,
# so $cmd is empty and this hook judges nothing — the C-A contract ("cannot
# judge" => hook_ok), unchanged by this slice. Pinned so the file comment
# stating it stays true.
t_gg_without_jq_or_python3_the_hook_cannot_judge() {
	local repo bin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"deny":["terraform destroy"]}\n' >"$repo/.claude/flow.config.json"
	bin=$(_t_gg_bin_without jq python3)
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' "PATH=$bin" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_without_jq_or_python3_the_hook_cannot_judge rc"
	assert_eq "$OUT" "" "t_gg_without_jq_or_python3_the_hook_cannot_judge emits nothing"
	rm -rf "$repo" "$bin"
}

t_gg_no_deny_list_leaves_other_commands_alone() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"terraform destroy -auto-approve"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_no_deny_list_leaves_other_commands_alone rc"
	assert_eq "$OUT" "" "t_gg_no_deny_list_leaves_other_commands_alone allowed"
	rm -rf "$repo"
}

# --- C-B: off/unsafe/env escape hatches -----------------------------------

t_gg_flow_off_still_denies() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/flow.off"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_flow_off_still_denies rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_flow_off_still_denies denied"
	rm -rf "$repo"
}

t_gg_flow_unsafe_marker_allows() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/flow.unsafe"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_gg_flow_unsafe_marker_allows rc"
	assert_eq "$OUT" "" "t_gg_flow_unsafe_marker_allows allowed"
	rm -rf "$repo"
}

t_gg_flow_unsafe_marker_in_ancestor_allows() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude" "$repo/sub/deeper"
	: >"$repo/.claude/flow.unsafe"
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git reset --hard"}}' CLAUDE_PROJECT_DIR="$repo/sub/deeper"
	assert_rc 0 "t_gg_flow_unsafe_marker_in_ancestor_allows rc"
	assert_eq "$OUT" "" "t_gg_flow_unsafe_marker_in_ancestor_allows allowed"
	rm -rf "$repo"
}

t_gg_env_var_disables_guard() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' CC_NO_GIT_GUARD=1
	assert_rc 0 "t_gg_env_var_disables_guard rc"
	assert_eq "$OUT" "" "t_gg_env_var_disables_guard allowed"
}

t_gg_deny_reason_names_escape_hatch() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}'
	assert_contains "$OUT" "CC_NO_GIT_GUARD=1 for this session" "t_gg_deny_reason_names_escape_hatch env var"
	assert_contains "$OUT" "ask the user to run it" "t_gg_deny_reason_names_escape_hatch ask the user"
}

t_gg_coarse_deny_reason_names_escape_hatch() {
	# Over the 20000-char cap: the coarse fallback deny needs the hatch too.
	local pad
	pad=$(_t_gg_repeat_char x 21000)
	run_hook "$SCAN_DIR/git-guard.sh" "$(printf '{"tool_input":{"command":"git push --force origin main # %s"}}' "$pad")"
	assert_rc 0 "t_gg_coarse_deny_reason_names_escape_hatch rc"
	assert_contains "$OUT" "CC_NO_GIT_GUARD=1 for this session" "t_gg_coarse_deny_reason_names_escape_hatch hatch"
}

# --- FU-34: the git clean reason states the fact, not a fake precondition --

t_gg_clean_reason_names_the_command_and_hatch() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git clean -xfd"}}'
	assert_rc 0 "t_gg_clean_reason_names_the_command_and_hatch rc"
	assert_contains "$OUT" 'git clean -f' "t_gg_clean_reason_names_the_command_and_hatch names git clean -f"
	assert_contains "$OUT" 'CC_NO_GIT_GUARD' "t_gg_clean_reason_names_the_command_and_hatch names the hatch"
	assert_not_contains "$OUT" 'run git clean -n first' "t_gg_clean_reason_names_the_command_and_hatch no fake precondition"
}

# --- the dead subcommands are gone ----------------------------------------

t_gg_stash_rebase_merge_not_in_subcommand_scan() {
	local scan
	scan=$(grep -n 'push | reset | clean' "$SCAN_DIR/git-guard.sh")
	# Guard against a vacuous pass: if the sub) line is ever reformatted, grep
	# finds nothing and the three negative assertions below hold trivially.
	assert_contains "$scan" "push | reset | clean" "t_gg_stash_rebase_merge_not_in_subcommand_scan subcommand scan line found"
	assert_not_contains "$scan" "stash" "t_gg_stash_rebase_merge_not_in_subcommand_scan no stash"
	assert_not_contains "$scan" "rebase" "t_gg_stash_rebase_merge_not_in_subcommand_scan no rebase"
	assert_not_contains "$scan" "merge" "t_gg_stash_rebase_merge_not_in_subcommand_scan no merge"
}

t_gg_no_skip_if_off_call() {
	local content
	content=$(cat "$SCAN_DIR/git-guard.sh")
	assert_not_contains "$content" "hook_skip_if_off" "t_gg_no_skip_if_off_call git-guard does not honour flow.off"
}

# --- heredoc detection is a real redirection, not any "<<" on the line -----

t_gg_quoted_heredoc_text_does_not_swallow_next_command() {
	# `<<EOF` inside a quoted string opens no body; the destructive command on
	# the next line must still be judged.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo \"cat <<EOF > f\" >> NOTES.md\ngit reset --hard origin/main"}}'
	assert_rc 0 "t_gg_quoted_heredoc_text_does_not_swallow_next_command rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_quoted_heredoc_text_does_not_swallow_next_command denied"
}

t_gg_spaced_left_shift_does_not_swallow_next_command() {
	# `$((1 << N))` looks like `<<` + a delimiter word; it is arithmetic, and
	# even when it is misread the unterminated body must not be dropped.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo $((1 << N))\nrm -rf /"}}'
	assert_rc 0 "t_gg_spaced_left_shift_does_not_swallow_next_command rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_spaced_left_shift_does_not_swallow_next_command denied"
}

t_gg_unterminated_heredoc_still_scans_the_rest() {
	# No delimiter line ever arrives, so nothing may be discarded.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > f <<EOF\ngit push --force origin main"}}'
	assert_rc 0 "t_gg_unterminated_heredoc_still_scans_the_rest rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_unterminated_heredoc_still_scans_the_rest denied"
}

t_gg_heredoc_body_with_blank_line_allowed() {
	# B16 for the ordinary case: a written shell script has blank lines in it.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > setup.sh <<'"'"'EOF'"'"'\nset -e\n\ngit clean -fdx\nEOF"}}'
	assert_rc 0 "t_gg_heredoc_body_with_blank_line_allowed rc"
	assert_eq "$OUT" "" "t_gg_heredoc_body_with_blank_line_allowed allowed"
}

# --- an interpreter heredoc EXECUTES its body, so the body is commands -----

t_gg_bash_heredoc_body_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"bash <<'"'"'EOF'"'"'\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_bash_heredoc_body_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_bash_heredoc_body_push_force_denied denied"
}

t_gg_ssh_heredoc_body_rm_rf_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"ssh host <<EOF\nrm -rf /\nEOF"}}'
	assert_rc 0 "t_gg_ssh_heredoc_body_rm_rf_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_ssh_heredoc_body_rm_rf_denied denied"
}

t_gg_cat_heredoc_body_push_force_allowed() {
	# The same body written to a file with `cat` is text, not commands.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > f.sh <<'"'"'EOF'"'"'\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_cat_heredoc_body_push_force_allowed rc"
	assert_eq "$OUT" "" "t_gg_cat_heredoc_body_push_force_allowed allowed"
}

# --- glued wrapper characters ---------------------------------------------

t_gg_glued_subshell_paren_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(git push --force origin main)"}}'
	assert_rc 0 "t_gg_glued_subshell_paren_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_glued_subshell_paren_push_force_denied denied"
}

t_gg_glued_brace_group_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"{git reset --hard origin/main; }"}}'
	assert_rc 0 "t_gg_glued_brace_group_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_glued_brace_group_reset_hard_denied denied"
}

t_gg_heredoc_piped_into_bash_body_denied() {
	# `cat <<EOF | bash` executes the body too, so the interpreter check looks
	# at the whole line, not just what precedes the `<<`.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat <<EOF | bash\ngit reset --hard\nEOF"}}'
	assert_rc 0 "t_gg_heredoc_piped_into_bash_body_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_heredoc_piped_into_bash_body_denied denied"
}

# --- more interpreters that EXECUTE a heredoc body ------------------------
# Fix round 2: `source`/`.` with /dev/stdin, and the non-POSIX shells, run the
# body just like `bash <<EOF` does. Verified with
# `bash -c "$(printf 'source /dev/stdin <<EOF\necho EXECUTED\nEOF')"` -> EXECUTED.

t_gg_source_dev_stdin_heredoc_body_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"source /dev/stdin <<EOF\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_source_dev_stdin_heredoc_body_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_source_dev_stdin_heredoc_body_push_force_denied denied"
}

t_gg_dot_dev_stdin_heredoc_body_rm_rf_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":". /dev/stdin <<EOF\nrm -rf /\nEOF"}}'
	assert_rc 0 "t_gg_dot_dev_stdin_heredoc_body_rm_rf_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_dot_dev_stdin_heredoc_body_rm_rf_denied denied"
}

t_gg_fish_heredoc_body_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"fish <<EOF\ngit reset --hard origin/main\nEOF"}}'
	assert_rc 0 "t_gg_fish_heredoc_body_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_fish_heredoc_body_reset_hard_denied denied"
}

t_gg_csh_heredoc_body_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"csh <<EOF\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_csh_heredoc_body_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_csh_heredoc_body_push_force_denied denied"
}

t_gg_tcsh_heredoc_body_branch_delete_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"/bin/tcsh <<EOF\ngit branch -D main\nEOF"}}'
	assert_rc 0 "t_gg_tcsh_heredoc_body_branch_delete_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_tcsh_heredoc_body_branch_delete_denied denied"
}

t_gg_su_heredoc_body_rm_rf_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"su root <<EOF\nrm -rf /\nEOF"}}'
	assert_rc 0 "t_gg_su_heredoc_body_rm_rf_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_su_heredoc_body_rm_rf_denied denied"
}

# --- heredoc delimiter forms bash accepts ---------------------------------
# `<<\EOF` quotes the delimiter exactly like `<<'EOF'`, and a delimiter may
# contain - and . — all three write a file, so the body stays text.

t_gg_backslash_quoted_delimiter_body_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > deploy.sh <<\\EOF\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_backslash_quoted_delimiter_body_allowed rc"
	assert_eq "$OUT" "" "t_gg_backslash_quoted_delimiter_body_allowed allowed"
}

t_gg_dashed_delimiter_body_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > deploy.sh <<'"'"'END-OF-FILE'"'"'\ngit push --force origin main\nEND-OF-FILE"}}'
	assert_rc 0 "t_gg_dashed_delimiter_body_allowed rc"
	assert_eq "$OUT" "" "t_gg_dashed_delimiter_body_allowed allowed"
}

t_gg_dotted_delimiter_body_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > deploy.sh <<EOF.TXT\nrm -rf /\nEOF.TXT"}}'
	assert_rc 0 "t_gg_dotted_delimiter_body_allowed rc"
	assert_eq "$OUT" "" "t_gg_dotted_delimiter_body_allowed allowed"
}

# --- the coarse fallback states the condition it actually observed --------

t_gg_coarse_reason_names_awk_unavailable() {
	# With awk off PATH the hook cannot parse at all, so it falls back to the
	# coarse regex. The reason must say that, not "command too large".
	local bin t p
	bin=$(tmp_dir)/binless
	mkdir -p "$bin"
	for t in bash jq grep sed cat tr head date mktemp git dirname; do
		p=$(command -v "$t" 2>/dev/null) && ln -sf "$p" "$bin/$t"
	done
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git push --force origin main"}}' "PATH=$bin"
	assert_rc 0 "t_gg_coarse_reason_names_awk_unavailable rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_coarse_reason_names_awk_unavailable denied"
	assert_contains "$OUT" 'awk is unavailable' "t_gg_coarse_reason_names_awk_unavailable names awk"
	assert_not_contains "$OUT" 'too large' "t_gg_coarse_reason_names_awk_unavailable no size claim"
}

# --- fix round 1: group closers glued to the LAST token -------------------
# Peeling only the opening "(" left ")" glued to the final word, so every rule
# that matches an exact word (--force, --hard, ".", "--" ".") missed inside a
# subshell. `(cd <dir> && git reset --hard)` is a routine agent idiom and bash
# runs it verbatim. pp() now peels a trailing ")"/"}" and splits a "(" glued
# after a keyword, so the head resolves the same way it does unwrapped.

t_gg_subshell_bare_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(git push --force)"}}'
	assert_rc 0 "t_gg_subshell_bare_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_subshell_bare_push_force_denied denied"
}

t_gg_subshell_bare_reset_hard_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(git reset --hard)"}}'
	assert_rc 0 "t_gg_subshell_bare_reset_hard_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_subshell_bare_reset_hard_denied denied"
}

t_gg_subshell_bare_rm_rf_root_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(rm -rf /)"}}'
	assert_rc 0 "t_gg_subshell_bare_rm_rf_root_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_subshell_bare_rm_rf_root_denied denied"
}

t_gg_subshell_cd_then_push_force_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(cd x && git push --force)"}}'
	assert_rc 0 "t_gg_subshell_cd_then_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_subshell_cd_then_push_force_denied denied"
}

t_gg_subshell_cd_then_checkout_dash_dot_denied() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"(cd repo && git checkout -- .)"}}'
	assert_rc 0 "t_gg_subshell_cd_then_checkout_dash_dot_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_subshell_cd_then_checkout_dash_dot_denied denied"
}

t_gg_keyword_then_subshell_push_force_denied() {
	# The "(" is glued to git AND sits after a keyword, so neither the
	# start-of-part peel nor the plain wrapper list reaches it on its own.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"if true; then (git push --force); fi"}}'
	assert_rc 0 "t_gg_keyword_then_subshell_push_force_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_keyword_then_subshell_push_force_denied denied"
}

t_gg_commit_message_with_glued_parens_allowed() {
	# Peeling a trailing ")" must not turn an ordinary conventional-commit
	# subject into a denied part.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"fix(auth)\""}}'
	assert_rc 0 "t_gg_commit_message_with_glued_parens_allowed rc"
	assert_eq "$OUT" "" "t_gg_commit_message_with_glued_parens_allowed allowed"
}

t_gg_commit_message_with_spaced_parens_allowed() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git commit -m \"wip (round 2)\""}}'
	assert_rc 0 "t_gg_commit_message_with_spaced_parens_allowed rc"
	assert_eq "$OUT" "" "t_gg_commit_message_with_spaced_parens_allowed allowed"
}

# --- fix round 1: a "<<WORD" inside a comment opens no heredoc -------------
# bash never opens a heredoc from a comment, so excising up to the next bare
# WORD line deleted real commands from the scan. Confirmed executable:
# `printf '%s\n' '# writes with cat <<EOF' 'echo EXECUTED' 'EOF' | bash`
# prints EXECUTED (then "EOF: command not found").

t_gg_commented_heredoc_does_not_swallow_rm() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"# see cat <<EOF for the format\nrm -rf /\nEOF"}}'
	assert_rc 0 "t_gg_commented_heredoc_does_not_swallow_rm rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_commented_heredoc_does_not_swallow_rm denied"
}

t_gg_trailing_comment_heredoc_does_not_swallow_push() {
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"git status # cat <<END\ngit push --force origin main\nEND"}}'
	assert_rc 0 "t_gg_trailing_comment_heredoc_does_not_swallow_push rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_gg_trailing_comment_heredoc_does_not_swallow_push denied"
}

t_gg_quoted_hash_still_opens_a_real_heredoc() {
	# The "#" is inside quotes, so it is not a comment and the `cat <<EOF`
	# after it is still a real redirection whose body is text.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"echo \"#\" ; cat <<EOF\nrm -rf /\nEOF"}}'
	assert_rc 0 "t_gg_quoted_hash_still_opens_a_real_heredoc rc"
	assert_eq "$OUT" "" "t_gg_quoted_hash_still_opens_a_real_heredoc allowed"
}

t_gg_heredoc_with_trailing_comment_still_opens() {
	# The comment starts AFTER the redirection, so the body is still excised.
	run_hook "$SCAN_DIR/git-guard.sh" '{"tool_input":{"command":"cat > f.sh <<EOF # write it\ngit push --force origin main\nEOF"}}'
	assert_rc 0 "t_gg_heredoc_with_trailing_comment_still_opens rc"
	assert_eq "$OUT" "" "t_gg_heredoc_with_trailing_comment_still_opens allowed"
}
