#!/usr/bin/env bash
# test_prep_prose.sh — pins the load-bearing sentences of the /flow:prep
# skill (docs/research/13-flow-prep-2026-09-07.md §5). Sourced by run.sh;
# HERE (this dir) and SCAN_DIR (its parent, "scripts/") are already set.
# Tests prefixed t_prep_prose_.

PREP_SKILL="$SCAN_DIR/../skills/prep/SKILL.md"
PREP_TEMPLATE="$SCAN_DIR/../skills/prep/references/prep-template.md"
PLUGINS_DOC="$SCAN_DIR/../../../docs/reference/plugins.md"

# ---------------------------------------------------------------------------
# frontmatter
# ---------------------------------------------------------------------------

t_prep_prose_disable_model_invocation() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'disable-model-invocation: true' \
		"SKILL.md sets disable-model-invocation: true"
}

# ---------------------------------------------------------------------------
# body: load-bearing sentences from §5.3 and the mechanics
# ---------------------------------------------------------------------------

t_prep_prose_one_decision_per_turn() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'One decision per turn' \
		"SKILL.md states one decision per turn"
}

t_prep_prose_negative_scope_probe() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'what should this explicitly NOT do' \
		"SKILL.md carries the exact negative-scope probe"
}

t_prep_prose_verify_probe() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'what single check would convince you this shipped' \
		"SKILL.md carries the exact Verify probe"
}

t_prep_prose_questions_zero_of_twelve() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'Questions: 0 of 12' \
		"SKILL.md writes the file with Questions: 0 of 12 before the first question"
}

t_prep_prose_prep_lint() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'prep-lint' \
		"SKILL.md runs prep-lint before closing"
}

t_prep_prose_next_flow_spec() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'Next: /flow:spec' \
		"SKILL.md ends the oneshot/dispatch route with Next: /flow:spec"
}

t_prep_prose_references_template_path() {
	assert_contains "$(cat "$PREP_SKILL")" \
		'references/prep-template.md' \
		"SKILL.md references references/prep-template.md by relative path"
}

# ---------------------------------------------------------------------------
# template file: section headers and D-01 grammar
# ---------------------------------------------------------------------------

t_prep_prose_template_sections() {
	local content
	content=$(cat "$PREP_TEMPLATE")
	assert_contains "$content" '## Not this' "prep-template.md has a ## Not this section"
	assert_contains "$content" '## Verify' "prep-template.md has a ## Verify section"
	assert_contains "$content" '## Discretion' "prep-template.md has a ## Discretion section"
	assert_contains "$content" '- D-01' "prep-template.md shows the D-01 decision grammar"
}

# ---------------------------------------------------------------------------
# borrows from mattpocock/skills (logic demo, split signal, claim check)
# ---------------------------------------------------------------------------

t_prep_prose_logic_demo_offer() {
	local c
	c=$(cat "$PREP_SKILL")
	assert_contains "$c" 'offer a logic demo' \
		"SKILL.md offers a logic demo when the question is whether a state model holds"
	assert_contains "$c" 'proto/<slug>' "SKILL.md names the proto/<slug> branch"
	assert_contains "$c" 'evidence: proto/<slug>:<path>' \
		"SKILL.md records the demo answer as an A-NN with evidence: proto/<slug>:<path>"
	assert_contains "$c" 'a throwaway logic demo may back the answer' \
		"SKILL.md lets a throwaway logic demo back a spike answer"
	assert_contains "$c" 'only after the user says yes' \
		"SKILL.md builds the demo only after an explicit yes"
}

t_prep_prose_split_rule() {
	local c
	c=$(cat "$PREP_SKILL")
	assert_contains "$c" 'Before counting, resolve any Open line the tree can answer' \
		"SKILL.md resolves tree-answerable Open lines before counting"
	assert_contains "$c" '## Not yet specified' \
		"SKILL.md sends the remaining Open lines under ## Not yet specified"
	assert_contains "$(cat "$PREP_TEMPLATE")" '## Not yet specified' \
		"prep-template.md carries the ## Not yet specified heading"
}

t_prep_prose_claim_vs_code() {
	local c
	c=$(cat "$PREP_SKILL")
	assert_contains "$c" 'When an answer states how existing code behaves, open the code first' \
		"SKILL.md opens the code before recording a claim about it"
	assert_contains "$c" 'On a contradiction, quote path:line in the question' \
		"SKILL.md quotes path:line on a contradiction (the question itself follows rule 2)"
}

# ---------------------------------------------------------------------------
# line-budget cap
# ---------------------------------------------------------------------------

t_prep_prose_skill_line_cap() {
	local n
	n=$(wc -l <"$PREP_SKILL" | tr -d ' ')
	if [ "$n" -le 160 ]; then _pass "prep/SKILL.md is <= 160 lines (got $n)"; else _fail "prep/SKILL.md is <= 160 lines (got $n)" "over the cap"; fi
}

# ---------------------------------------------------------------------------
# listing: docs/reference/plugins.md carries the skill
# ---------------------------------------------------------------------------

t_prep_prose_listed_in_plugins_doc() {
	assert_contains "$(cat "$PLUGINS_DOC")" '- prep' \
		"docs/reference/plugins.md lists - prep"
}

t_prep_contradiction_question_keeps_the_hypothesis_rule() {
	local body
	body=$(cat "$PREP_SKILL")
	assert_contains "$body" "still follows rule 2" \
		"rule 5's contradiction question keeps rule 2's hypothesis and '— confirm or correct?'"
	assert_not_contains "$body" "ask once which is right" \
		"the bare 'ask once which is right' template is gone (it displaced rule 2 in a live eval)"
}
