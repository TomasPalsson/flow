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
