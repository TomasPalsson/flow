#!/usr/bin/env bash
# test_grill_prose.sh — prose assertions for skills/grill/SKILL.md. Sourced by
# run.sh; SCAN_DIR is already set. Tests prefixed t_grill_.

GRILL_SKILL="$SCAN_DIR/../skills/grill/SKILL.md"

# Every question is explained: what it decides, the options, cost and undo.
t_grill_every_question_is_explained() {
	local content
	content=$(cat "$GRILL_SKILL")
	assert_contains "$content" 'what this decides, and what waits on it' "grill round format states what the question decides"
	assert_contains "$content" 'Three lines per option, no more' "grill options stay short"
	assert_contains "$content" 'Undo: <easy or hard, in a few words>' "grill options carry cost and undo"
	assert_contains "$content" '⭐ recommended' "grill round format keeps the recommended answer"
	assert_contains "$content" 'Every real option' "grill explains every option, not only the recommended one"
}

# The words are Simplified Technical English with the project's own nouns.
t_grill_words_are_plain() {
	local content
	content=$(cat "$GRILL_SKILL")
	assert_contains "$content" 'ASD-STE100' "grill names the Simplified Technical English register"
	assert_contains "$content" '20 words max for a step, 25 max for a description' "grill caps sentence length"
	assert_contains "$content" 'in parentheses' "grill explains hard words in parentheses"
	assert_contains "$content" 'I reply `more` with a question number' "grill holds the deep detail until asked"
}

# No question cap (the reason this is not /flow:prep), and a lost user is not an answer.
t_grill_no_cap_and_lost_user_reopens() {
	local content
	content=$(cat "$GRILL_SKILL")
	assert_contains "$content" 'ask the three that unblock the most' "a round shows at most three questions"
	assert_contains "$content" 'No inline code formatting (backticks) in a question' "grill questions carry no backticks"
	assert_contains "$content" 'There is no cap on the number of questions or rounds' "grill has no question cap"
	assert_contains "$content" 'This is not an answer; the question stays open' "a ? reply re-explains and keeps the question open"
	assert_contains "$content" 'A choice I waved through without that sentence is still open' "you-pick is not a decision"
	assert_contains "$content" 'disable-model-invocation: true' "grill fires only on the explicit slash call"
}
