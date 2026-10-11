#!/usr/bin/env bash
# test_ultracode_gate.sh — the ultracode spec gate: the SKILL.md sentences that
# state it are pinned, and the skill's own python tests (check-orders and the
# session analyzer) run from here so a red one fails the suite.
set -u

UG_DIR="$(cd "$SCAN_DIR/../.." && pwd -P)/flow-extras/skills/ultracode"

t_ultracode_gate_text_pinned() {
	local skill econ
	skill=$(cat "$UG_DIR/SKILL.md")
	econ=$(cat "$UG_DIR/references/fleet-economics.md")
	assert_contains "$skill" "the one kind of finding only it looks for" "Phase 1 names a finding kind per parallel agent"
	assert_contains "$skill" "Two agents with the same kind get merged" "same-kind agents are merged"
	assert_contains "$skill" "one \`ORDERS\` constant" "briefs build from one ORDERS constant"
	assert_contains "$skill" "scripts/check-orders" "Phase 2 runs check-orders"
	assert_contains "$skill" ".ultracode/<slug>/prompts/" "the trial logs rendered prompts"
	assert_contains "$skill" "Read the plan before fan-out on four points" "the four-point plan read"
	assert_contains "$econ" "analyze-sessions.mjs" "fleet-economics points at the analyzer"
	assert_contains "$econ" "never into a repo" "the analyzer output stays out of repos"
}

t_ultracode_check_orders_unit_tests() {
	run_cmd python3 -I "$UG_DIR/tests/test_check_orders.py"
	assert_rc 0 "check-orders tests pass"
}

t_ultracode_analyze_sessions_unit_tests() {
	if ! command -v node >/dev/null 2>&1; then
		_pass "node not installed; analyzer tests not applicable"
		return 0
	fi
	run_cmd python3 -I "$UG_DIR/tests/test_analyze_sessions.py"
	assert_rc 0 "analyze-sessions tests pass"
}

t_ultracode_scripts_executable() {
	[ -x "$UG_DIR/scripts/check-orders" ] && _pass "check-orders is executable" || _fail "check-orders is executable" "mode bits"
}
