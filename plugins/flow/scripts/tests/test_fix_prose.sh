#!/usr/bin/env bash
# test_fix_prose.sh — prose assertions for skills/fix/ (SKILL.md,
# execution-prompt.md, diagnosis.md). Sourced by run.sh; HERE (this dir) and
# SCAN_DIR (its parent, "scripts/") are already set. Tests prefixed t_fix_.
#
# The fix skill was rewritten to: drop .claude/workflow-state.local.md
# entirely (spec 004 abolished it) and keep exactly one artefact,
# .claude/fix-diagnosis.local.md; make direct execution the default and
# --loop opt-in; commit the failing reproduction before the fix and prove it
# with `git revert --no-commit`, never `git stash`; drop the Simple/Medium/
# Complex self-classification in favour of the frontend/backend/integration/
# infrastructure category; and give the loop verifier literal commands, never
# the markdown field "$TEST_CMD" which expands to nothing in a real shell.
# Nothing checked any of this before, which is how four independent
# regressions of exactly these shapes survived a rewrite.

FIX_SKILL="$SCAN_DIR/../skills/fix/SKILL.md"
FIX_EXEC="$SCAN_DIR/../skills/fix/execution-prompt.md"
FIX_DIAG="$SCAN_DIR/../skills/fix/diagnosis.md"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# _fix_all → concatenated content of all three fix skill files
_fix_all() {
	cat "$FIX_SKILL" "$FIX_EXEC" "$FIX_DIAG"
}

# _fix_bash_blocks → content of every fenced ```bash block across the three files
_fix_bash_blocks() {
	awk '/^```bash/{f=1;next} /^```/{f=0} f{print}' "$FIX_SKILL" "$FIX_EXEC" "$FIX_DIAG"
}

# _fix_loop_init_blocks → content of fenced ```bash blocks that run `flow loop init`
# ponytail: block detection is line-range per file, not per open/close pair; fine
# while skills/fix/ has exactly one such block, re-check by hand if a second appears.
_fix_loop_init_blocks() {
	awk '
    /^```bash/ { f=1; buf=""; has=0; next }
    /^```/ { if (f && has) print buf; f=0; next }
    f { buf = buf $0 "\n"; if ($0 ~ /flow loop init/) has=1 }
  ' "$FIX_SKILL" "$FIX_EXEC" "$FIX_DIAG"
}

# ---------------------------------------------------------------------------
# banned strings — each was a confirmed defect in the rewrite
# ---------------------------------------------------------------------------

t_fix_no_workflow_state_file() {
	assert_not_contains "$(_fix_all)" 'workflow-state.local.md' \
		"skills/fix/ must not reference workflow-state.local.md — spec 004 abolished it; the skill keeps exactly one artefact, .claude/fix-diagnosis.local.md"
}

t_fix_no_test_cmd_literal_in_bash_block() {
	assert_not_contains "$(_fix_bash_blocks)" '"$TEST_CMD"' \
		'no fenced bash block may paste "$TEST_CMD" — it is a markdown field, not a shell variable, and expands to nothing, which made flow loop init exit 1'
}

t_fix_no_git_stash() {
	assert_not_contains "$(_fix_all)" 'git stash' \
		"skills/fix/ must not use git stash — the fix is committed before the check, so stash would hide the test instead of the fix; the red-green proof is git revert --no-commit"
}

t_fix_no_stopped_cap_string() {
	assert_not_contains "$(_fix_all)" 'stopped: cap' \
		"skills/fix/ must not print 'stopped: cap' — flow loop status prints status: and stop_reason: on separate lines and never emits this compound form"
}

t_fix_prompt_file_is_anchored() {
	local blocks
	blocks=$(_fix_bash_blocks)
	assert_not_contains "$blocks" '--prompt-file ".claude/' \
		'no fenced bash block may pass --prompt-file a bare ".claude/..." path — it must be anchored with $(git rev-parse --show-toplevel), or a relative path throws an uncaught ENOENT from any subdirectory'
	assert_not_contains "$blocks" "--prompt-file '.claude/" \
		"no fenced bash block may pass --prompt-file a bare '.claude/...' path — same ENOENT risk as the double-quoted form"
	assert_not_contains "$blocks" '--prompt-file .claude/' \
		"no fenced bash block may pass --prompt-file an unquoted bare .claude/... path — same ENOENT risk"
}

t_fix_no_simple_medium_complex_classification() {
	local all
	all=$(_fix_all)
	assert_not_contains "$all" 'Simple' \
		"skills/fix/ must not self-classify Simple/Medium/Complex — only the frontend/backend/integration/infrastructure category survives, and it alone picks the verification tier"
	assert_not_contains "$all" 'Medium' \
		"skills/fix/ must not self-classify Simple/Medium/Complex — the Medium rung is gone with the rest of the ladder"
	assert_not_contains "$all" 'Complex' \
		"skills/fix/ must not self-classify Simple/Medium/Complex — the Complex rung is gone with the rest of the ladder"
}

# ---------------------------------------------------------------------------
# required strings
# ---------------------------------------------------------------------------

t_fix_frontmatter_has_argument_hint() {
	assert_contains "$(cat "$FIX_SKILL")" 'argument-hint:' \
		"SKILL.md frontmatter must carry an argument-hint: field"
}

t_fix_has_next_line() {
	assert_contains "$(cat "$FIX_SKILL")" 'Next:' \
		"SKILL.md must contain a Next: line — house rule: every turn ends with one"
}

t_fix_loop_init_block_has_max_usd() {
	assert_contains "$(_fix_loop_init_blocks)" '--max-usd' \
		"every fenced bash block that runs flow loop init must cap --max-usd — an uncapped fresh loop costs roughly \$0.80 an iteration"
}

t_fix_loop_init_block_is_toplevel_anchored() {
	assert_contains "$(_fix_loop_init_blocks)" 'git rev-parse --show-toplevel' \
		"every fenced bash block that runs flow loop init must anchor --prompt-file with git rev-parse --show-toplevel"
}

t_fix_revert_no_commit_proof() {
	assert_contains "$(cat "$FIX_SKILL")" 'git revert --no-commit' \
		"SKILL.md must prove the fix red-green with git revert --no-commit"
}

t_fix_revert_restore_is_not_bare_checkout() {
	assert_not_contains "$(_fix_all)" 'git checkout -- .' \
		"skills/fix/ must not restore a no-commit revert with 'git checkout -- .' — the revert stages itself in the index, so a bare checkout restores the REVERTED tree and silently leaves the bug in the working copy (proved in a scratch repo 2026-09-09)"
	assert_contains "$(cat "$FIX_SKILL")" 'git reset --hard HEAD' \
		"SKILL.md must restore the revert-proof with 'git reset --hard HEAD' — the only form that actually puts the fix back"
}

t_fix_explorer_model_matches_its_definition() {
	assert_not_contains "$(cat "$FIX_SKILL")" '`explorer` agent (`model: sonnet`' \
		"SKILL.md must not pin explorer to sonnet — agents/explorer.md pins model: haiku, and an undocumented override is a silent cost change"
}

t_fix_pr_ready_is_gated_on_the_verdict() {
	assert_contains "$(cat "$FIX_SKILL")" '`gh pr ready` only on a `verified` verdict' \
		"SKILL.md must gate gh pr ready on a verified verdict — an unconditional 'create --draft then ready' contradicts the partial-stays-draft rule and ships an unverified PR looking reviewed"
}

# The revert-proof reverts the fix BY SHA, so the fix must already be committed
# when it runs. Ordering, not substring presence — the one class of defect the
# rest of this file cannot see.
t_fix_commit_precedes_the_revert_proof() {
	local hits line_commit line_proof
	hits=$(grep -n 'Commit: `fix(<scope>)\|git revert --no-commit' "$FIX_SKILL")
	line_commit=$(printf '%s\n' "$hits" | grep 'Commit: `fix(<scope>)' | head -1 | cut -d: -f1)
	line_proof=$(printf '%s\n' "$hits" | grep 'git revert --no-commit' | head -1 | cut -d: -f1)
	if [ -z "$line_commit" ] || [ -z "$line_proof" ]; then
		_fail "SKILL.md must contain both a 'Commit: fix(<scope>)' step and a 'git revert --no-commit' proof"
	elif [ "$line_commit" -ge "$line_proof" ]; then
		_fail "SKILL.md must commit the fix BEFORE the revert-proof (commit line $line_commit, proof line $line_proof) — the proof reverts the fix by sha, which does not exist until it is committed"
	else
		_pass "fix commit precedes the revert-proof"
	fi
}
