---
name: fix
description: "Systematic bug fix from triage through regression test and PR. Use when: (1) a specific behavior is broken and needs a permanent fix with regression test and PR, (2) the user reports something stopped working, crashes, or returns wrong results, (3) a known error needs root-cause diagnosis and targeted resolution. Classifies bugs (frontend/backend/integration/infrastructure), drives reproducibility, performs root cause analysis, implements targeted fixes with Ralph Loop, adds mandatory regression tests, and applies tiered verification. Do NOT use for: general debugging exploration without a clear fix target, performance profiling, refactoring, or feature development. Trigger keywords: fix, bug, error, broken, crash, regression, not working, failing, issue, defect, wrong behavior."
---

# Fix Workflow

You are executing an adaptive bug fix workflow. This workflow detects the project environment at runtime — never assume specific tools, paths, or frameworks.

## NEVER Do

- **NEVER fix without reproducing** — a fix that can't be verified against a reproduction is a guess; guesses break other things
- **NEVER expand scope beyond the reported bug** — opportunistic refactoring during fix work introduces untested changes and makes the fix harder to review and revert
- **NEVER skip regression tests** — a fix without a test is a time bomb; the same bug WILL recur; the regression test is the proof of fix, not the code change
- **NEVER hardcode tool commands** — always use detected `$TEST_CMD`, `$LINT_CMD`, etc.; hardcoded commands break silently in projects that use different toolchains
- **NEVER modify files outside the bug's scope without documenting why** — if you must touch unrelated code, add a comment to the state file explaining the dependency; this prevents scope-creep confusion during review
- **NEVER commit with failing tests** — a green test suite is the minimum bar before any commit; red tests mean the fix isn't ready
- **NEVER suppress or skip a test to make the suite pass** — suppressing a test is hiding a bug, not fixing one
- **NEVER ignore test validity** — before modifying a failing test, verify it's testing the correct behavior, not just asserting old (buggy) behavior
- **NEVER output a false completion promise** — the Ralph Loop's integrity depends on honest completion signals; lying to exit the loop wastes more time than iterating honestly

## Step -1: Resume Check

Check if `.claude/workflow-state.local.md` exists:

**If it exists and `type: fix`** — this is a resumed fix workflow after a context reset:
1. Read the state file to restore: workflow type, branch, bug description, complexity, category, detected commands, current position
2. Verify git state: `git branch --show-current` matches the stored branch
3. Verify last commit: `git log --oneline -1`
4. Skip to the first incomplete item in the Progress section
5. Tell the user: **"Resuming fix workflow from [current position]. Continuing with [next step]."**

**If it exists but `type` is NOT `fix`** — a different workflow is in progress. Tell the user and stop.

**If neither exists** — fresh start. Proceed to Step 0.

---

## Step 0: Setup

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/project-detection.md` and detect the project environment
2. Parse `$ARGUMENTS` for: bug description, error messages, `--max-iterations N` (default: 30), `--skip-verification`
3. Create `.claude/workflow-state.local.md`:
   ```markdown
   # Workflow State

   ## Workflow
   - type: fix
   - description: [from arguments]
   - branch: [will be set after triage]
   - complexity: [pending classification]
   - category: [pending classification]
   - started: [ISO timestamp]

   ## Project Environment
   [values from project detection]

   ## Current Position
   - step: 0 (setup)
   - status: triaging
   - last_commit: [current HEAD hash]

   ## Progress
   - [ ] Triage & classification
   - [ ] Reproduction
   - [ ] Diagnosis
   - [ ] Fix implementation
   - [ ] Regression test
   - [ ] Verification
   - [ ] PR creation

   ## Resume Instructions
   If reading this after a context reset:
   1. You are in the middle of a fix workflow
   2. Read .claude/fix-diagnosis.local.md for diagnosis notes
   3. Verify you're on branch [branch] via git branch --show-current
   4. Continue from the first unchecked item in Progress above
   5. Use the Project Environment commands above — do NOT re-detect
   ```

---

## PHASE A: Triage

### Before Diagnosis — Think First

Before doing anything, ask yourself:
- **Is this actually a bug?** Could it be expected behavior, a configuration issue, or user error? Read the docs/comments around the reported area first.
- **Is this the right symptom?** The user reports what they see, but the root cause may be upstream. Don't fix the symptom — find the cause.
- **What changed recently?** Run `git log --oneline -10` on the affected files. A recent commit is often the cause.
- **Is the test suite trustworthy?** If existing tests pass but the bug exists, the tests might be testing the wrong thing. Verify test validity before relying on them.
- **What's the blast radius?** How many code paths touch the buggy area? This determines complexity.
- **Is there a quick fix vs a proper fix?** If they differ, do the proper fix. Quick fixes become the next bug.

### Step 1: Classify the Bug

Based on the description, error messages, and initial exploration, classify:

**Category** (determines exploration scope):
- **Frontend**: UI rendering, interaction, styling, client-side logic
- **Backend**: API, database, server-side logic, data processing
- **Integration**: Cross-system communication, API contracts, data flow between components
- **Infrastructure**: Build, deploy, environment, config, dependency issues

**Complexity** (determines iteration budget and verification tier):
- **Simple** (1-2 files, clear cause): typo, wrong value, missing null check, CSS fix
- **Medium** (3-5 files, requires tracing): logic error across functions, state management bug, race condition
- **Complex** (5+ files, deep investigation): architectural issue, intermittent failure, multi-system interaction bug

Present to the user: **"I've classified this as a [COMPLEXITY] [CATEGORY] bug. [Brief reasoning]. Branch name suggestion: `fix/[short-description]`. Does that seem right?"**

Create the branch after confirmation. Update state file with complexity, category, and branch.

### Step 2: Reproduce

Spawn the `triage` agent with the pasted error text and what changed recently; continue with its returned minimal failing command, exact error text, and file:line origin.

**Goal**: A reliable way to trigger the bug that can be re-run after the fix.

1. Based on category, determine reproduction strategy:
   - **Frontend**: Browser-based reproduction (read `shared/agent-browser-reference.md` first)
   - **Backend**: Test-based or CLI reproduction
   - **Integration**: End-to-end reproduction with both systems
   - **Infrastructure**: Environment reproduction

   **Do NOT load** `agent-browser-reference.md` for backend, integration, or infrastructure bugs.

2. Create a minimal reproduction:
   - Write a failing test that captures the bug behavior, OR
   - Document exact steps to reproduce manually
   - Verify the reproduction actually fails (not a flaky test)

3. Record in state file: **reproduction method, expected vs actual behavior**

**If the bug is intermittent** (can't reproduce reliably on every attempt):
- Look for race conditions: shared mutable state accessed without synchronization, async operations without proper awaiting
- Check for time-dependent logic: `Date.now()`, `setTimeout`, retry loops, cache TTLs in the affected path
- Run the suspected code path in a loop (10+ iterations with logging) to establish a failure rate
- Strategy: instrument with logging first, collect 3+ failure samples, THEN diagnose. Do not fix blind.
- If the failure rate is <10%, document the intermittent nature in the diagnosis and PR description

**If reproduction fails entirely**: Tell the user: **"I can't reliably reproduce this bug. Here's what I tried: [list]. Can you provide more details about the environment, steps, or input data?"** Do not proceed to diagnosis without reproduction or strong code-analysis evidence.

### Step 3: Diagnose

Read `${CLAUDE_PLUGIN_ROOT}/skills/fix/diagnosis.md` for the diagnosis template.

1. Launch up to 3 Explore agents (model: `haiku`) to investigate based on category:
   - Agent 1: Trace the code path from input to the bug symptom
   - Agent 2: Check recent git history on affected files (`git log --oneline -10 <files>`)
   - Agent 3: Search for related issues, similar patterns, or existing workarounds

2. Create `.claude/fix-diagnosis.local.md` with the diagnosis template filled in:
   - Root cause (with evidence — file:line references)
   - Affected files (complete list)
   - Fix approach (specific changes needed)
   - Risk assessment (what could break)
   - Additional files discovered during diagnosis (if any beyond the initial list)

3. Present diagnosis to user: **"Root cause: [explanation]. Fix approach: [what I'll change]. Risk: [what could break]. Shall I proceed?"**

**If diagnosis is ambiguous** (multiple possible causes): Present all candidates with evidence. Ask the user which to pursue first. If confident in ranking, recommend: "I believe [cause A] is most likely because [evidence]. Shall I start there?"

---

## PHASE B: Fix

### Execution — Ralph Loop Path

Check if `ralph-wiggum` or `ralph-loop` plugin is installed. If available, invoke:

```
Skill tool call:
  skill: "ralph-loop:ralph-loop"
  args: "<execution prompt below>" --completion-promise "BUG FIXED" --max-iterations <N>
```

Where `<N>` comes from: `--max-iterations` argument if provided, otherwise default by complexity (simple=15, medium=30, complex=60).

#### Execution Prompt

**MANDATORY — READ ENTIRE FILE**: Load [`execution-prompt.md`](execution-prompt.md) in full. Pass its contents (everything after the `---` separator) as the prompt argument to ralph-loop.

#### Post-Loop Check

After ralph-loop returns (whether by completion promise or iteration exhaustion):

1. Check if `.claude/workflow-state.local.md` still exists
2. **If it exists** — the loop exhausted iterations without completing:
   - Read the state file's Progress section
   - Report to the user: **"Ralph Loop exhausted [N] iterations. Progress: [completed steps] done, [remaining steps] remaining. Current position: [step]. Would you like me to continue with another ralph-loop invocation, or switch to manual execution?"**
3. **If it doesn't exist** — completion promise fired, bug is fixed. Report the PR URL.

### Execution — Fallback Path (no ralph-loop)

If ralph-loop is not available:
1. Tell the user: "The ralph-loop plugin is not installed. I'll execute the fix directly."
2. Load [`execution-prompt.md`](execution-prompt.md) and follow its instructions manually — execute each step sequentially.
3. If stuck after 3 attempts on any step, stop and ask the user for guidance.
4. On completion: delete `.claude/workflow-state.local.md`.
