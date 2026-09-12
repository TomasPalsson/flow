# test_prep_consumer.sh — prose tests for the PREP.md consumer side: the gate
# /flow:spec checks before discovery. Sourced by run.sh; HERE (this dir) and
# SCAN_DIR (its parent, "scripts/") are already set. Tests prefixed t_prepc_.
#
# Spec 004 renamed the consumer: skills/flow-spec/ and skills/flow/steps/ are
# gone and skills/spec/SKILL.md carries the gate (plus the --reuse clause that
# used to live in steps/00-setup.md), so these assertions were repointed
# rather than deleted.

FLOW_SPEC_SKILL="$SCAN_DIR/../skills/spec/SKILL.md"

# ---------------------------------------------------------------------------
# spec/SKILL.md: the PREP.md gate itself
# ---------------------------------------------------------------------------

t_prepc_skill_has_gate_heading() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "PREP.md gate" \
		"spec/SKILL.md names the PREP.md gate"
}

t_prepc_skill_never_re_ask() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "never re-asked" \
		"spec/SKILL.md's gate states D-NN decisions are never re-asked"
}

t_prepc_skill_needs_clarification_conflict_marker() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "[NEEDS CLARIFICATION: conflicts with D-NN]" \
		"spec/SKILL.md carries the exact conflicting-decision marker"
}

t_prepc_skill_do_not_load_question_bank() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "do NOT load \`references/question-bank.md\` at all" \
		"spec/SKILL.md's gate says not to load the question bank"
}

t_prepc_skill_write_spec_beside_prep() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" 'write `spec.md` beside' \
		"spec/SKILL.md's Phase 3 writes spec.md beside the PREP.md"
}

t_prepc_skill_never_section_has_prep_item() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" "re-ask a decision recorded as a" \
		"spec/SKILL.md's NEVER list bans re-asking a D-NN decision"
}

t_prepc_question_bank_load_is_conditional_on_gate() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" \
		'unless the PREP.md gate above fired' \
		"spec/SKILL.md's mandatory question-bank load is conditional on the PREP.md gate"
}

t_prepc_setup_step_passes_reuse() {
	assert_contains "$(cat "$FLOW_SPEC_SKILL")" \
		'--reuse .specs/NNN-<slug>' \
		"spec/SKILL.md passes --reuse to new-spec when PREP.md exists"
}
