#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_spec_prose.sh — unit V8 (flow prose: Approved line, C20) tests.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set. Tests prefixed t_v8_.

PLAN_STEP="$SCAN_DIR/../skills/flow/steps/03-plan.md"
PLANNING="$SCAN_DIR/../skills/flow/planning.md"
WRAP="${COMMANDS_DIR:-$SCAN_DIR/../commands}/wrap.md"

# ---------------------------------------------------------------------------
# 03-plan.md: exact "Approved:" instructions (C20)
# ---------------------------------------------------------------------------

t_v8_plan_approved_by_user_line() {
	assert_contains "$(cat "$PLAN_STEP")" \
		'Approved: <YYYY-MM-DD> by user' \
		"03-plan.md instructs the exact 'Approved: <YYYY-MM-DD> by user' line"
}

t_v8_plan_approved_unattended_variant() {
	assert_contains "$(cat "$PLAN_STEP")" \
		'Approved: <YYYY-MM-DD> auto (--unattended)' \
		"03-plan.md instructs the unattended 'Approved: ... auto (--unattended)' variant"
}

t_v8_plan_never_before_approval() {
	assert_contains "$(cat "$PLAN_STEP")" \
		'never before' \
		"03-plan.md states the Approved line is written never before approval"
}

# ---------------------------------------------------------------------------
# planning.md documents the header line
# ---------------------------------------------------------------------------

t_v8_planning_documents_approved_line() {
	local content
	content=$(cat "$PLANNING")
	assert_contains "$content" 'Approved: <YYYY-MM-DD> by user' \
		"planning.md documents the by-user Approved line"
	assert_contains "$content" 'Approved: <YYYY-MM-DD> auto (--unattended)' \
		"planning.md documents the unattended Approved line"
}

# ---------------------------------------------------------------------------
# wrap.md keeps the line intact
# ---------------------------------------------------------------------------

t_v8_wrap_keeps_approved_line_intact() {
	assert_contains "$(cat "$WRAP")" \
		"Never touch the plan's" \
		"wrap.md instructs never touching the plan's Approved line"
}

# ---------------------------------------------------------------------------
# line-budget caps (C12)
# ---------------------------------------------------------------------------

t_v8_line_caps() {
	local n
	n=$(wc -l <"$PLAN_STEP" | tr -d ' ')
	if [ "$n" -le 80 ]; then _pass "03-plan.md is <= 80 lines (got $n)"; else _fail "03-plan.md is <= 80 lines (got $n)" "over the C12 cap"; fi

	n=$(wc -l <"$PLANNING" | tr -d ' ')
	if [ "$n" -le 110 ]; then _pass "planning.md is <= 110 lines (got $n)"; else _fail "planning.md is <= 110 lines (got $n)" "over the C12 cap"; fi

	n=$(wc -l <"$WRAP" | tr -d ' ')
	if [ "$n" -le 35 ]; then _pass "wrap.md is <= 35 lines (got $n)"; else _fail "wrap.md is <= 35 lines (got $n)" "over the C12 cap"; fi
}
