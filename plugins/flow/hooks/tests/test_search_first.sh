#!/usr/bin/env bash
# search-first.sh: one model-facing additionalContext line when a prompt asks
# to add/implement/create/introduce a new symbol; silent otherwise, and off
# via CC_SEARCH_FIRST=0, searchFirst:false, or `flow off`.

t_search_first_matching_prompt_gets_receipt_context() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-1","prompt":"Please add a new method to the User class"}' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "match: rc 0"
	assert_contains "$OUT" "additionalContext" "match: additionalContext present"
	assert_contains "$OUT" "UserPromptSubmit" "match: hookEventName is UserPromptSubmit"
	assert_contains "$OUT" "searched: <terms and dirs>; found: <path:line | nothing>" "match: receipt phrase present"
	rm -rf "$repo"
}

t_search_first_non_matching_prompt_is_silent() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-2","prompt":"explain this function to me"}' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "no-match: rc 0"
	assert_not_contains "$OUT" "additionalContext" "no-match: no additionalContext"
	rm -rf "$repo"
}

t_search_first_slash_prompt_is_silent() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-3","prompt":"/flow:next add a new helper function"}' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "slash: rc 0"
	assert_not_contains "$OUT" "additionalContext" "slash: no additionalContext"
	rm -rf "$repo"
}

t_search_first_env_disable() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-4","prompt":"add a new method to the User class"}' \
		CLAUDE_PROJECT_DIR="$repo" CC_SEARCH_FIRST=0
	assert_rc 0 "env off: rc 0"
	assert_not_contains "$OUT" "additionalContext" "env off: no additionalContext"
	rm -rf "$repo"
}

t_search_first_config_disable() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"searchFirst": false}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-5","prompt":"add a new method to the User class"}' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "config off: rc 0"
	assert_not_contains "$OUT" "additionalContext" "config off: no additionalContext"
	rm -rf "$repo"
}

t_search_first_flow_off_marker_is_silent() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/flow.off"
	run_hook "$SCAN_DIR/search-first.sh" \
		'{"session_id":"sf-6","prompt":"add a new method to the User class"}' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "flow off: rc 0"
	assert_not_contains "$OUT" "additionalContext" "flow off: no additionalContext"
	rm -rf "$repo"
}

t_search_first_malformed_stdin_is_silent() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/search-first.sh" \
		'not json at all {{{' \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "malformed: rc 0"
	assert_eq "$OUT" "" "malformed: no stdout"
	rm -rf "$repo"
}
