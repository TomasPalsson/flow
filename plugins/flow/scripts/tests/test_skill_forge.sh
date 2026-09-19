#!/usr/bin/env bash
# test_skill_forge.sh — prose assertions for skills/skill-forge/SKILL.md's
# Step 0 reuse check (B10). Sourced by run.sh; HERE (this dir) and SCAN_DIR
# (its parent, "scripts/") are already set. Tests prefixed t_forge_.

FORGE_SKILL="$SCAN_DIR/../skills/skill-forge/SKILL.md"

# _forge_process_block → content of "## The Process" section, stopping
# before Step 0's own heading (and before Step 1, as a fallback if Step 0
# is missing) — isolates the short mention from the dedicated section.
_forge_process_block() {
	awk '
    /^## The Process/ { f=1 }
    /^## Step 0/ { exit }
    /^## Step 1/ { exit }
    f { print }
  ' "$FORGE_SKILL"
}

t_forge_step0_precedes_step1() {
	local step0_line step1_line
	step0_line=$(grep -n '^## Step 0: Reuse check' "$FORGE_SKILL" | head -1 | cut -d: -f1)
	step1_line=$(grep -n '^## Step 1: Research' "$FORGE_SKILL" | head -1 | cut -d: -f1)
	if [ -n "$step0_line" ] && [ -n "$step1_line" ] && [ "$step0_line" -lt "$step1_line" ]; then
		_pass "SKILL.md's Step 0 heading precedes Step 1"
	else
		_fail "SKILL.md's Step 0 heading precedes Step 1" \
			"Step 0 at line '$step0_line', Step 1 at line '$step1_line'"
	fi
}

t_forge_process_overview_mentions_step0() {
	assert_contains "$(_forge_process_block)" 'Step 0' \
		"## The Process overview names Step 0 before its own heading"
}

t_forge_reuse_check_greps_skill_dirs() {
	local content
	content=$(cat "$FORGE_SKILL")
	assert_contains "$content" 'grep -ril' \
		"Step 0 searches existing skills with grep -ril"
	assert_contains "$content" 'plugins/*/skills/*/SKILL.md' \
		"Step 0 searches plugin skills"
	# shellcheck disable=SC2088  # literal doc text under test, no expansion intended
	assert_contains "$content" '~/.claude/skills/*/SKILL.md' \
		"Step 0 searches user-level skills"
	# shellcheck disable=SC2088  # literal doc text under test, no expansion intended
	assert_contains "$content" '~/.claude/skills/*/skills/*/SKILL.md' \
		"Step 0 searches nested user-level skills"
}

t_forge_close_match_offers_three_choices() {
	local content
	content=$(cat "$FORGE_SKILL")
	assert_contains "$content" 'STOPS before Step 1' \
		"a close match stops the pipeline before Step 1"
	assert_contains "$content" 'use the existing skill' \
		"choice 1: use the existing skill"
	assert_contains "$content" 'skill-improver' \
		"choice 2: improve it with skill-improver"
	assert_contains "$content" 'build fresh anyway' \
		"choice 3: build fresh anyway"
}

t_forge_no_close_match_prints_receipt_line() {
	assert_contains "$(cat "$FORGE_SKILL")" \
		'reuse check: searched <terms> in <dirs>; nothing close' \
		"no close match prints the one-line reuse-check receipt"
}
