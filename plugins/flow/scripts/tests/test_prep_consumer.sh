# test_prep_consumer.sh — prose tests for the PREP.md consumer side: the
# gate flow-spec/SKILL.md checks before discovery, and the one-clause
# pointer in flow/steps/01-spec.md. Sourced by run.sh; HERE (this dir) and
# SCAN_DIR (its parent, "scripts/") are already set. Tests prefixed t_prepc_.

FLOW_SPEC_SKILL="$SCAN_DIR/../skills/flow-spec/SKILL.md"
STEP01_SPEC="$SCAN_DIR/../skills/flow/steps/01-spec.md"

# ---------------------------------------------------------------------------
# flow-spec/SKILL.md: the PREP.md gate itself
# ---------------------------------------------------------------------------

t_prepc_skill_has_gate_heading() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "PREP.md gate" \
		"flow-spec/SKILL.md names the PREP.md gate"
}

t_prepc_skill_never_re_ask() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "never re-asked" \
		"flow-spec/SKILL.md's gate states D-NN decisions are never re-asked"
}

t_prepc_skill_needs_clarification_conflict_marker() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "[NEEDS CLARIFICATION: conflicts with D-NN]" \
		"flow-spec/SKILL.md carries the exact conflicting-decision marker"
}

t_prepc_skill_do_not_load_question_bank() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "do NOT load \`references/question-bank.md\` at all" \
		"flow-spec/SKILL.md's gate says not to load the question bank"
}

t_prepc_skill_write_spec_beside_prep() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" 'write `spec.md` beside' \
		"flow-spec/SKILL.md's Phase 3 writes spec.md beside the PREP.md"
}

t_prepc_skill_never_section_has_prep_item() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "re-ask a decision recorded as a" \
		"flow-spec/SKILL.md's NEVER list bans re-asking a D-NN decision"
}

# ---------------------------------------------------------------------------
# flow/steps/01-spec.md: the one-clause pointer to the gate
# ---------------------------------------------------------------------------

t_prepc_step01_mentions_prep() {
	assert_contains "$(cat "$STEP01_SPEC")" "PREP.md" \
		"flow/steps/01-spec.md mentions PREP.md"
}

t_prepc_question_bank_load_is_conditional_on_gate() {
	assert_contains "$(cat "$SCAN_DIR/../skills/flow-spec/SKILL.md")" \
		'unless the PREP.md gate above fired' \
		"flow-spec's mandatory question-bank load is conditional on the PREP.md gate"
}

t_prepc_setup_step_passes_reuse() {
	assert_contains "$(cat "$SCAN_DIR/../skills/flow/steps/00-setup.md")" \
		'--reuse .specs/NNN-<slug>' \
		"00-setup step 0.5 passes --reuse to new-spec when PREP.md exists"
}
