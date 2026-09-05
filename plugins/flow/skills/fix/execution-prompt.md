---
name: fix-execution-prompt
description: Ralph Loop execution prompt for bug fixes — state restoration, error recovery, fix/test/verify/PR steps, and completion verification
---

# Fix Execution Prompt

Pass this as the prompt argument to ralph-loop. Also used as the execution guide for the fallback (no ralph-loop) path.

---

You are executing a bug fix via Ralph Loop.

## 1. STATE RESTORATION (do this every iteration)
Read .claude/workflow-state.local.md. Extract and hold these values:
- COMPLEXITY: [simple/medium/complex] — governs verification tier
- CATEGORY: [frontend/backend/integration/infrastructure] — governs approach
- CURRENT_STEP: first unchecked item in Progress section
- TEST_CMD, LINT_CMD, FORMAT_CMD: from Project Environment

Then read .claude/fix-diagnosis.local.md for the root cause and fix approach.
If all Progress items are checked, jump to COMPLETION CHECK.

## 2. ERROR RECOVERY (know this BEFORE starting work)
- Same test failure after 3 fix attempts → STOP. You may be fixing the wrong root cause. Report to user with the 3 approaches you tried and what each produced. Ask whether to continue or re-diagnose.
- Fix breaks existing tests → revert to last good commit (`git stash` or `git checkout -- <files>`), analyze WHY the existing test broke, adjust approach
- Regression test itself is wrong (testing buggy behavior) → document this in the state file, write correct test asserting correct behavior
- Fix requires changing files outside diagnosed scope → document the additional file and reasoning in the state file's Progress section, then proceed
- State file corrupted or missing → recreate from git log and diagnosis file, continue from last known good commit

## 3. RULES
- Follow CLAUDE.md conventions
- Use commands from state file's Project Environment (NOT hardcoded)
- ONLY modify files identified in the diagnosis, plus test files. If you must touch additional files, document why in the state file.
- Commit after fix implementation, and again after regression test, using conventional commit format
- Update .claude/workflow-state.local.md after each completed step

## 4. EXECUTE CURRENT STEP

### If current step is "Fix implementation":
a) Implement the fix from the diagnosis — minimal, targeted changes only
b) Run $TEST_CMD — all existing tests must still pass
c) Run $LINT_CMD && $FORMAT_CMD — code must be clean
d) Commit: `fix(<scope>): <what was fixed>`
e) Mark step [x] in state file

### If current step is "Regression test":
a) Write a test that WOULD HAVE CAUGHT this bug — it should fail on the old code and pass on the new code
b) Verify: `git stash && $TEST_CMD` should show the NEW test failing. Then `git stash pop`.
c) Run full $TEST_CMD — all tests pass including the new one
d) Commit: `test(<scope>): add regression test for <bug>`
e) Mark step [x] in state file

### If current step is "Verification":
a) **MANDATORY — READ FIRST**: Load ${CLAUDE_PLUGIN_ROOT}/skills/shared/verification.md in full
b) Execute at tier: simple→quick, medium→standard, complex→full
c) After verification: grep source files for [VERIFY] strings — remove any found, commit
d) Mark step [x] in state file

### If current step is "PR creation":
a) **MANDATORY — READ FIRST**: Load ${CLAUDE_PLUGIN_ROOT}/skills/shared/review.md in full
b) Execute at tier: simple→quick, medium→standard, complex→full
c) PR title format: `fix(<scope>): <description>`
d) PR body must include: what was broken, root cause, what was fixed, regression test description
e) Mark step [x] in state file

## 5. COMPLETION CHECK
Before outputting the completion promise, verify ALL of these:
- [ ] All Progress items in state file are marked [x]
- [ ] $TEST_CMD passes (run it now to confirm)
- [ ] $LINT_CMD passes (run it now)
- [ ] No [VERIFY] strings remain in source files (grep for them)
- [ ] Regression test exists and is specific to this bug
- [ ] PR has been created (gh pr view shows a URL)
- [ ] .claude/workflow-state.local.md has been deleted

If ANY check fails, fix it before continuing. Do NOT output the promise until all checks pass.

Output <promise>BUG FIXED</promise>
