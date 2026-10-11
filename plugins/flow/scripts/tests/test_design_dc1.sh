#!/usr/bin/env bash
# test_design_dc1.sh — design plugin text rules from the famous-repos round,
# slice DC1: SHIP floor, vary SAFE/RISK report, craft rules, script escape.
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_dc1_.

DC1_DESIGN="$SCAN_DIR/../../design/skills"
DC1_SKILL="$DC1_DESIGN/design/SKILL.md"
DC1_EVAL="$DC1_DESIGN/design/evaluator-prompt.md"
DC1_VARY="$DC1_DESIGN/vary/SKILL.md"
DC1_VARY_EVAL="$DC1_DESIGN/vary/evaluator-prompt.md"
DC1_CRAFT="$DC1_DESIGN/vary/references/build-craft.md"
DC1_GRAPHICS="$DC1_DESIGN/graphics/SKILL.md"
DC1_EXPLAINER="$DC1_DESIGN/explainer/SKILL.md"
DC1_SMOOTH="$DC1_DESIGN/smoothbrain/SKILL.md"

t_dc1_ship_gate_has_dimension_floor() {
	local t
	t=$(cat "$DC1_SKILL")
	assert_contains "$t" "Composite ≥ 4.0 AND Usability, Interaction and Accessibility each ≥ 3.5 AND no dimension ≤ 2" "SHIP names the composite and the per-dimension floor"
	assert_contains "$t" "apply the top fixes for the lowest dimension" "below the floor the lowest dimension gets the fixes"
	assert_contains "$t" "adapted from garrytan/gstack plan-design-review/sections/review-sections.md.tmpl @ 5b9b837 (MIT)" "SHIP floor credit line"
	assert_contains "$(cat "$DC1_EVAL")" "**Lowest dimension:** <name> X.X" "evaluator report prints the lowest dimension"
}

t_dc1_no_stale_composite_only_ship_rule() {
	assert_not_contains "$(cat "$DC1_EVAL")" "If score ≥ 4.0: SHIP" "evaluator template has no composite-only SHIP line"
	assert_not_contains "$(cat "$DC1_SKILL")" "converges or ≥ 4.0" "SKILL has no composite-only stop rule"
}

t_dc1_ship_gate_keeps_specificity_exception() {
	assert_contains "$(cat "$DC1_SKILL")" "under utility, or when Phase 3 was skipped" "specificity exception for utility builds stays"
}

t_dc1_vary_report_lists_safe_and_risks() {
	local t
	t=$(cat "$DC1_VARY")
	assert_contains "$t" "Safe (category baseline)" "vary report lists the safe choices"
	assert_contains "$t" "Risks (this build's own face)" "vary report lists the risks"
	assert_contains "$t" "what it gains and what it costs" "each risk names gain and cost"
	assert_contains "$t" "--register safer|bolder" "report ends with the register steering flag"
	assert_contains "$t" "--lock concept=<id>" "report ends with the concept lock flag"
	assert_contains "$t" "adapted from garrytan/gstack design-consultation/sections/proposal-and-preview.md.tmpl @ 5b9b837 (MIT)" "vary report credit line"
	assert_not_contains "$(cat "$DC1_VARY_EVAL")" "Safe (category baseline)" "evaluator prompt is unchanged by the report rule"
}

t_dc1_craft_rules_are_positive_and_generator_facing() {
	local t
	t=$(cat "$DC1_CRAFT")
	assert_contains "$t" "One verb per action" "build-craft: one verb per action"
	assert_contains "$t" "Refine what is there before adding" "build-craft: refine before adding"
	assert_contains "$t" "selector specificity" "build-craft: specificity note"
	assert_not_contains "$t" "meta-dot" "build-craft carries no avoid-list of tells"
	assert_contains "$(cat "$DC1_VARY_EVAL")" "keeps one verb through the flow" "evaluator microcopy row has the one-verb rule"
}

t_dc1_phase3_has_genericity_probe() {
	assert_contains "$(cat "$DC1_SKILL")" "would a similar brief land here? revise that part and say why" "Phase 3 self-genericity probe"
	assert_contains "$(cat "$DC1_SKILL")" "adapted from anthropics/skills skills/frontend-design/SKILL.md @ dbd4588 (Apache-2.0)" "Phase 3 credit line"
	assert_contains "$(cat "$DC1_GRAPHICS")" "refine, don't add" "graphics refine step"
}

t_dc1_script_escape_rule_in_build_and_explainer() {
	assert_contains "$(cat "$DC1_CRAFT")" 'escape `<` as `\u003c`' "build-craft: escape < in embedded script strings"
	assert_contains "$(cat "$DC1_EXPLAINER")" 'escape `<` as `\u003c`' "explainer: escape < in embedded script strings"
	assert_contains "$(cat "$DC1_EXPLAINER")" "smoothbrain/scripts/check.mjs" "explainer points to the inline-script parse check"
	assert_contains "$(cat "$DC1_SMOOTH")" "adapted from anthropics/claude-plugins-official plugins/project-artifact/SKILL.md @ a9fd216 (Apache-2.0)" "smoothbrain script-parse credit line"
}
