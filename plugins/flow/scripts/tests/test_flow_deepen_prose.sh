#!/usr/bin/env bash
# test_flow_deepen_prose.sh — pins the flow-deepen prose (heuristics, test replacement,
# rejection memory, interface-shape designs, call-site wins). Sourced by run.sh.

DEEPEN_SKILL="$SCAN_DIR/../skills/flow-deepen/SKILL.md"
DEEPEN_REF="$SCAN_DIR/../skills/flow-deepen/references/detection-heuristics.md"

t_deepen_p18_deletion_test_and_hint() {
	local ref
	ref=$(cat "$DEEPEN_REF")
	assert_contains "$ref" 'Deletion test' "heuristics carry the deletion test"
	assert_contains "$ref" 'hint only' "ratio row is demoted to a hint"
	assert_contains "$ref" 'in-process' "category: in-process"
	assert_contains "$ref" 'local stand-in' "category: local stand-in"
	assert_contains "$ref" 'owned remote' "category: owned remote"
	assert_contains "$ref" 'true external' "category: true external"
	assert_contains "$ref" 'verify:` stays the characterization test' "verify stays the characterization test's command"
}

t_deepen_p19_replaces_exception() {
	local ref skill
	ref=$(cat "$DEEPEN_REF")
	skill=$(cat "$DEEPEN_SKILL")
	assert_contains "$ref" '(replaces: <test path>)' "heuristics define the replaces: task-line exception"
	assert_not_contains "$ref" 'a slice that reduces the suite is rejected' "no unconditional suite-shrink rejection"
	assert_contains "$skill" 'replaces:' "SKILL.md cross-references replaces:"
}

t_deepen_p20_rejection_memory() {
	local skill
	skill=$(cat "$DEEPEN_SKILL")
	assert_contains "$skill" '.out-of-scope/deepen-<module-slug>.md' "Phase 5 writes the rejection file"
	assert_contains "$skill" 'not about timing' "rejections must not be about timing"
	assert_contains "$skill" "'not now', 'later' and 'after X' are timing" "timing replies write nothing"
	assert_contains "$skill" 'drop the candidate' "Phase 1 drops candidates with a matching entry"
}

t_deepen_p21_interface_shape_designs() {
	local skill
	skill=$(cat "$DEEPEN_SKILL")
	assert_contains "$skill" 'fewest entry points' "design constraint 1"
	assert_contains "$skill" 'most common caller' "design constraint 2"
	assert_contains "$skill" 'ports and adapters at the seam' "design constraint 3"
	assert_contains "$skill" 'model: sonnet' "subagents pin sonnet"
	assert_contains "$skill" 'NOTES.md' "designs are attached in NOTES.md"
}

t_deepen_p22_win_is_a_number() {
	local skill
	skill=$(cat "$DEEPEN_SKILL")
	assert_contains "$skill" 'AC-3 call-site number' "Win ties to AC-3"
	assert_contains "$skill" '"Easier to maintain", "cleaner" and "more readable" are not wins' "banned phrases"
}

t_deepen_f55_test_id_set_not_just_count() {
	local ref
	ref=$(cat "$DEEPEN_REF")
	assert_contains "$ref" '`pytest --collect-only -q`' "heuristics name the pytest collector"
	assert_contains "$ref" '`cargo test -- --list`' "heuristics name the cargo collector"
	assert_contains "$ref" '`vitest list`' "heuristics name the vitest collector"
	assert_contains "$ref" 'an unknown runner falls back to the count' "heuristics keep the count as the fallback"
	assert_contains "$ref" 'stays with the gaming lens' "a swapped body stays with the gaming lens"
	assert_not_contains "$ref" 'keeps test count monotonic' "the count-only guard is gone"
}
