#!/usr/bin/env bash
# test_qa_prose.sh — prose assertions for skills/qa/ and the shared browser
# references. Sourced by run.sh; SCAN_DIR (scripts/) is already set.
# Tests prefixed t_qa_.

QA_DIR="$SCAN_DIR/../skills/qa"
QA_SKILL="$QA_DIR/SKILL.md"
QA_SHARED="$SCAN_DIR/../skills/shared"

# _qa_section <file> <start-regex> <end-regex> → lines from the first start
# match up to (not including) the next end match
_qa_section() {
	awk -v s="$2" -v e="$3" '
		$0 ~ s && !on { on = 1; print; next }
		on && $0 ~ e { exit }
		on { print }
	' "$1"
}

# --- F09: no stash/checkout/pull in the user's tree ---------------------------

t_qa_never_touches_user_tree() {
	local hits
	hits=$(grep -nE 'git stash|git checkout|git pull' "$QA_SKILL" || true)
	assert_eq "$hits" "" "qa/SKILL.md has no git stash, checkout or pull (the stash stack is shared across worktrees)"
}

t_qa_branch_runs_in_scratch_worktree() {
	local skill
	skill=$(cat "$QA_SKILL")
	assert_contains "$skill" 'git worktree add' "a branch argument runs in a scratch worktree"
	assert_contains "$skill" 'git worktree remove' "cleanup removes the scratch worktree"
	assert_contains "$skill" 'git -C <tmp> status --porcelain' "a refused removal shows the worktree status"
	assert_contains "$skill" 'invoking tree' "the report is written in the invoking tree, outside the scratch worktree"
}

t_qa_cleanup_has_no_force() {
	local sec
	sec=$(_qa_section "$QA_SKILL" '^### 4c' '^## References')
	assert_contains "$sec" 'git worktree remove' "4c cleanup section found and removes the worktree"
	assert_not_contains "$sec" '--force' "4c cleanup never forces the removal"
}

# --- F10: observed vs hypothesis, replayed blockers --------------------------

t_qa_report_splits_observed_from_hypothesis() {
	local sec
	sec=$(_qa_section "$QA_SKILL" '^### Step 3' '^---')
	assert_contains "$sec" 'Observed' "Step 3 findings carry Observed"
	assert_contains "$sec" 'Expected' "Step 3 findings carry Expected"
	assert_contains "$sec" 'Hypothesis' "Step 3 findings carry a separate Hypothesis"
	assert_contains "$sec" 'Observed-once' "Step 3 names the Observed-once blocker state"
	assert_contains "$sec" 'replay needed' "Observed-once blockers go to Should Fix as replay needed"
	assert_contains "$sec" 'Confirmed' "Step 3 names the Confirmed blocker state"
	assert_contains "$sec" 'clean state' "a replay starts from a clean state"
}

t_qa_agent_prompts_use_finding_fields() {
	local f
	f=$(cat "$QA_DIR/references/agent-prompts.md")
	assert_contains "$f" 'Observed' "agent-prompts finding format has Observed"
	assert_contains "$f" 'Hypothesis' "agent-prompts finding format has Hypothesis"
}

t_qa_checklist_requires_replay() {
	assert_contains "$(cat "$QA_DIR/references/qa-checklists.md")" \
		'[ ] every ship-blocker is Confirmed by a replay' "report checklist requires a replay"
}

# --- F11: functional contracts -----------------------------------------------

t_qa_functional_contracts_reference() {
	local f skill n
	f=$(cat "$QA_DIR/references/functional-contracts.md")
	skill=$(cat "$QA_SKILL")
	assert_contains "$f" 'Credit: adapted from garrytan/gstack qa/sections/system-functional.md @ 5b9b837 (MIT).' "credit line carries the sha the borrow was read from"
	assert_contains "$f" 'exactly-once' "reference says not to assume exactly-once"
	assert_contains "$f" 'dead-letter' "reference separates retry and dead-letter"
	assert_contains "$f" 'exit code' "reference covers the CLI exit code"
	assert_contains "$f" 'Not Tested' "a service that cannot start goes under Not Tested"
	assert_contains "$f" 'never as passed' "a blocked service is never recorded as passed"
	assert_contains "$skill" 'Contract Tester' "Wave 2 has a Contract Tester row"
	assert_contains "$skill" 'API/CLI/job changes' "Contract Tester deploys on API/CLI/job changes"
	n=$(grep -c 'references/functional-contracts.md' "$QA_SKILL")
	if [ "$n" -ge 2 ]; then
		_pass "functional-contracts.md linked from both the Wave 2 table and the references table"
	else
		_fail "functional-contracts.md linked from both tables" "found $n link(s)"
	fi
}

# --- F12: --fix mode ----------------------------------------------------------

t_qa_fix_mode_section() {
	local sec
	sec=$(_qa_section "$QA_SKILL" '^### 4a-fix' '^### 4b')
	assert_contains "$sec" 'flow:fix' "--fix routes blockers through flow:fix"
	assert_contains "$sec" 'two reverts' "--fix stops after two reverts"
	assert_contains "$sec" 'unrelated file' "--fix stops on an edit to an unrelated file"
	assert_contains "$sec" 'branch under test' "--fix says where commits land"
	assert_contains "$sec" 'every 5 fixes' "--fix reports every 5 fixes"
	assert_contains "$sec" 'Confirmed' "--fix only touches Confirmed blockers"
}

# --- F13: browser content is untrusted ---------------------------------------

t_qa_browser_safety_paragraph() {
	local sec
	sec=$(_qa_section "$QA_SHARED/verification.md" '^## Browser safety' '^## Step')
	assert_contains "$sec" 'never followed as instructions' "page text is data, never instructions"
	assert_contains "$sec" 'LOCAL = ' "LOCAL hosts are defined"
	assert_contains "$sec" '*.pc' "LOCAL includes *.pc"
	assert_contains "$sec" '*.localhost' "LOCAL includes *.localhost"
	assert_contains "$sec" 'once per run' "non-local mutation is asked once per run"
	assert_contains "$sec" '--unattended' "unattended runs have their own clause"
	assert_contains "$sec" 'not run: non-local mutation' "unattended runs list the skipped step"
	assert_contains "$sec" 'localStorage' "JS never reads storage tokens"
	assert_contains "$sec" 'isolated' "an isolated profile is preferred"
}

t_qa_browser_safety_linked() {
	local f
	for f in "$QA_SHARED/claude-in-chrome-reference.md" "$QA_SHARED/agent-browser-reference.md" "$QA_DIR/references/browser-qa-workflows.md"; do
		assert_contains "$(cat "$f")" 'verification.md#browser-safety' "$(basename "$f") links the shared browser-safety paragraph"
	done
}

t_qa_agents_work_on_the_branch_under_test() {
	local skill step ap ca tr
	skill=$(cat "$QA_SKILL")
	ap=$(cat "$QA_DIR/references/agent-prompts.md")
	step=$(_qa_section "$QA_SKILL" 'Capture setup context' '^If NO branch')
	assert_contains "$step" 'absolute' "setup context records the absolute scratch worktree path"
	assert_contains "$step" '<tmp>' "setup context names <tmp>"
	ca=$(_qa_section "$QA_DIR/references/agent-prompts.md" '^### Code Analyzer' '^### Test Runner')
	tr=$(_qa_section "$QA_DIR/references/agent-prompts.md" '^### Test Runner' '^### Project Scanner')
	assert_contains "$ca" '[WORKTREE PATH]' "Code Analyzer reads code in the worktree path"
	assert_contains "$tr" '[WORKTREE PATH]' "Test Runner runs tests in the worktree path"
	assert_contains "$ap" 'absolute `.qa-report/wave-1/' "agents write reports to the absolute .qa-report in the invoking tree"
	assert_not_contains "$ap" 'If a branch was checked out' "Project Scanner prompt no longer assumes a checkout"
	assert_contains "$skill" 'git fetch origin <branch>' "branch is fetched before the worktree is added"
	assert_contains "$skill" '.env' "gitignored env files are copied or recorded under Not Tested"
	assert_contains "$skill" 'already checked out' "a branch already checked out has a fallback"
}

t_qa_fix_mode_exempts_test_file() {
	local sec
	sec=$(_qa_section "$QA_SKILL" '^### 4a-fix' '^### 4b')
	assert_contains "$sec" 'red test' "--fix keeps the red-test step"
	assert_contains "$sec" 'test file' "--fix exempts the new test file from the unrelated-file stop"
	assert_contains "$sec" 'no branch argument' "--fix with no branch argument commits on the invoking tree's branch"
}

t_qa_browser_safety_scoped_navigation() {
	local sec
	sec=$(_qa_section "$QA_SHARED/verification.md" '^## Browser safety' '^## Step')
	assert_contains "$sec" 'non-local URL found in page content' "the navigation confirmation applies to non-local URLs only"
	assert_contains "$sec" 'not run: non-local navigation' "unattended runs list a skipped non-local navigation"
}

# --- F157: a11y lines and the 320px reflow viewport --------------------------

t_qa_a11y_checklist_lines() {
	local f
	f=$(cat "$QA_DIR/references/qa-checklists.md")
	assert_contains "$f" '[ ] Skip-to-content link is the first focusable element on pages with nav' "skip link line"
	assert_contains "$f" '[ ] Text zoomed to 200% loses no content or function' "200% resize line"
	assert_contains "$f" '[ ] Name/email/address/password inputs carry the right autocomplete token' "autocomplete line"
}

t_qa_full_tier_has_reflow_viewport() {
	local v full std quick
	v="$QA_SHARED/verification.md"
	full=$(_qa_section "$v" '^### Full' '^## ')
	std=$(_qa_section "$v" '^### Standard' '^### Full')
	quick=$(_qa_section "$v" '^### Quick' '^### Standard')
	assert_contains "$full" 'reflow 320x640 (no horizontal scroll)' "Full tier has the 320px reflow viewport"
	assert_contains "$full" '375x812' "Full tier still lists 375x812"
	assert_contains "$std" '###' "Standard tier section found"
	assert_contains "$quick" '###' "Quick tier section found"
	assert_not_contains "$std" '320' "Standard tier is unchanged"
	assert_not_contains "$quick" '320' "Quick tier is unchanged"
}

# --- F09 follow-up: every agent that reads or runs code gets the worktree path --

t_qa_code_agents_get_worktree_path() {
	local f name sec
	f="$QA_DIR/references/agent-prompts.md"
	for name in 'Security Scanner' 'Edge Case Hunter' 'Contract Tester'; do
		sec=$(_qa_section "$f" "^### $name" '^### ')
		assert_contains "$sec" "### $name" "agent-prompts has a $name prompt"
		assert_contains "$sec" '[WORKTREE PATH]' "$name prompt carries the worktree path"
	done
}

t_qa_step0_guards() {
	local skill
	skill=$(cat "$QA_SKILL")
	assert_contains "$skill" 'origin/<branch>' "Step 0 checks the local branch against origin"
	assert_contains "$skill" 'shows it is clean' "a reused worktree must be clean before use"
	assert_contains "$skill" 'process you started' "the polled port must belong to the scratch-tree server"
}
