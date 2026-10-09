#!/usr/bin/env bash
# test_skill_forge.sh — prose assertions for skill-forge/SKILL.md's
# Step 0 reuse check (B10). Sourced by run.sh; HERE (this dir) and SCAN_DIR
# (its parent, "scripts/") are already set. Tests prefixed t_forge_.
# skill-forge lives in the sibling flow-extras plugin.

FORGE_SKILL="$SCAN_DIR/../../flow-extras/skills/skill-forge/SKILL.md"

# _forge_content → full content of skill-forge/SKILL.md
_forge_content() {
	cat "$FORGE_SKILL"
}

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
	content=$(_forge_content)
	assert_contains "$content" 'grep -ril' \
		"Step 0 searches existing skills with grep -ril"
	assert_contains "$content" 'plugins/*/skills/*/SKILL.md' \
		"Step 0 searches plugin skills"
	assert_contains "$content" '~'/.claude/skills/'*'/SKILL.md \
		"Step 0 searches user-level skills"
	assert_contains "$content" '~'/.claude/skills/'*'/skills/'*'/SKILL.md \
		"Step 0 searches nested user-level skills"
}

t_forge_close_match_offers_three_choices() {
	local content
	content=$(_forge_content)
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
	assert_contains "$(_forge_content)" \
		'reuse check: searched <terms> in <dirs>; nothing close' \
		"no close match prints the one-line reuse-check receipt"
}

# ---- flow-extras round 2: ultracode standing orders / hand-made oracle,
# skill-improver eval step, benchmark-checklist absolute budget ----

EXTRAS_DIR="$SCAN_DIR/../../flow-extras/skills"

t_forge_ultracode_standing_orders() {
	assert_contains "$(cat "$EXTRAS_DIR/ultracode/references/spec-template.md")" '## Standing orders' \
		"spec-template has the Standing orders heading"
	local skill
	skill=$(cat "$EXTRAS_DIR/ultracode/SKILL.md")
	assert_contains "$skill" 'append it there before acting on it' \
		"ultracode appends a mid-run directive before acting"
	assert_contains "$skill" 'every brief, respawn and fix-round prompt' \
		"ultracode pastes standing orders into every spawn"
}

t_forge_ultracode_script_oracle() {
	local skill
	skill=$(cat "$EXTRAS_DIR/ultracode/SKILL.md")
	assert_contains "$skill" 'Do unit 1 by hand and commit it' \
		"script-before-fleet hand-does unit 1"
	assert_contains "$skill" 'scratch worktree' \
		"the tool runs on unit 1 in a scratch worktree"
	assert_contains "$skill" 'The diff must be empty, or each hunk must be explained in SPEC.md' \
		"diff must be empty or explained before the wide run"
}

t_forge_benchmark_absolute_budget() {
	assert_contains "$(cat "$EXTRAS_DIR/benchmark-checklist/SKILL.md")" \
		'If the baseline does not have the feature, there is no ratio' \
		"benchmark question 2 refuses a ratio against a missing baseline"
}

t_forge_improver_eval_step() {
	local skill
	skill=$(cat "$EXTRAS_DIR/skill-improver/SKILL.md")
	assert_contains "$skill" '### Step 2f' "skill-improver has a final eval step"
	assert_contains "$skill" 'flow eval --case <name>... --runs 3' "step runs flow eval --case with 3 runs"
	assert_contains "$skill" 'base=<score> edit=<score>' "step prints base and edit scores"
	assert_contains "$skill" 'no eval cases for <skill>' "step prints one line when nothing is selected"
}

t_forge_improver_select_cases() {
	local sel="$EXTRAS_DIR/skill-improver/scripts/select-cases"
	local root out
	root="$(cd "$SCAN_DIR/../../.." && pwd)"
	out=$("$sel" fix "$root")
	assert_contains "$out" 'evals/routing-fix/case.yaml' "fix selects routing-fix"
	assert_contains "$out" 'evals/pipeline-fix-bug/case.yaml' "fix selects pipeline-fix-bug"
	assert_not_contains "$out" 'evals/routing-audit/case.yaml' \
		"a case that lists fix among wrong answers is not selected"
	assert_eq "$("$sel" no-such-skill-xyz "$root")" "" "a skill with no cases prints nothing"
}
