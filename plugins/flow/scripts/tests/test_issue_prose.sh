#!/usr/bin/env bash
# test_issue_prose.sh — prose assertions for skills/issue/SKILL.md. Sourced by
# run.sh; SCAN_DIR is already set. Tests prefixed t_issue_.

ISSUE_SKILL="$SCAN_DIR/../skills/issue/SKILL.md"

# Evidence names the enclosing symbol, not only path:line (stale-proof).
t_issue_evidence_rule_names_symbol() {
	local content
	content=$(cat "$ISSUE_SKILL")
	assert_contains "$content" '`path:line (symbol)`' \
		"issue Evidence row asks for path:line (symbol)"
	assert_contains "$content" '`(top level)`' \
		"issue Evidence row allows (top level) when no enclosing symbol"
}

# The worked example entry teaches the symbol form.
t_issue_example_evidence_has_symbol() {
	if grep -Eq '^Evidence: [^ ]+:[0-9]+ \([^)]+\)$' "$ISSUE_SKILL"; then
		_pass "issue example Evidence line carries a symbol"
	else
		_fail "issue example Evidence line carries a symbol" "no line matching Evidence: path:N (symbol)"
	fi
}

# Dedupe searches the concept (synonyms), confirms synonym-only matches, and
# reports where it looked.
t_issue_dedupe_synonyms_confirm_and_searched() {
	local content
	content=$(cat "$ISSUE_SKILL")
	assert_contains "$content" 'synonyms' "issue dedupe searches synonyms of the domain concept"
	assert_contains "$content" 'night theme' "issue dedupe gives the night theme / dark mode example"
	assert_contains "$content" 'same problem as <ref>' "issue dedupe asks y/n on a synonym-only match"
	assert_contains "$content" 'before any append or' "issue dedupe confirms before any append or gh comment"
	assert_contains "$content" '— searched: <queries> in <ISSUES.md|gh>' "issue ref line ends with a searched: clause"
	assert_contains "$content" '`Filed: I-003 — <title> — searched: <queries> in <ISSUES.md|gh>`' "issue Filed template carries the searched: clause"
	assert_contains "$content" 'phrasing, because GitHub search ANDs' "issue dedupe runs one query per phrasing"
}
