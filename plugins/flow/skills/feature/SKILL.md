---
name: feature
description: "TDD-first feature development pipeline. Triggers on: feature, implement, build, create, add, develop, new component, new endpoint, new page, new API, ship, resume feature, continue feature, worktree, TDD. Use WHENEVER a user asks to implement, build, or create new functionality — from branch creation through Red/Green/Refactor TDD cycles, parallel quality gates (security, performance, accessibility, type-safety), browser verification, mandatory user approval (HARD GATE), to PR with quality metrics. Stages: branch → plan (with TDD phases + verification steps) → Red/Green/Refactor per phase → lint/tsc/test → quality agents → browser verification → user verification → PR. Do NOT use for: bug fixes (/fix), refactoring without new behavior, docs-only changes, config tweaks."
---

# TDD-First Feature Development Pipeline

You are executing a TDD-first feature pipeline. Every implementation phase follows the Red→Green→Refactor cycle. The pipeline detects the project environment at runtime — never assume specific tools, paths, or frameworks.

## Pipeline Overview

```
Branch → Plan → [RED: failing tests] → [GREEN: make pass] → [REFACTOR] →
Inline Gates → Quality Agents → Browser Verification → User Verification → QA → PR
                  ↑                         |
                  └── fix loop (max 2) ─────┘
```

Every stage gates the next. The plan MUST include TDD phases, verification steps, and PR gate — these are not optional stages the agent may skip.

## NEVER Do

### TDD Discipline
- **NEVER write implementation code during a Red phase** — Red commits contain ONLY test files and stubs. Implementation files in a Red commit = TDD violation.
- **NEVER write new test files during a Green phase** — Green commits contain ONLY implementation files. New tests in a Green commit = retrofitted tests, not TDD.
- **NEVER accept an agent's self-report of "tests fail" as ground truth** — always run `$TEST_CMD` independently and verify exit code is NON-ZERO during Red.
- **NEVER proceed from Red to Green if tests pass (exit 0)** — tests that pass before implementation exists are green-bar tests that test nothing. Rewrite them to target actual behavior.
- **NEVER modify test files during Green to make them pass** — if tests need changing, return to Red. Test modification during Green = retroactive TDD.
- **NEVER skip the Refactor phase** — "tests pass, ship it" is Test-First Development, not TDD. The design feedback loop requires all three phases. Every Refactor phase MUST apply the `clean-code` skill — this is not optional.
- **NEVER write tests that only assert `toBeDefined()`, `toBeTruthy()`, or `not.toThrow()`** — these are green-bar tests that pass on any implementation. Every test must assert on specific return values, state changes, or error types.
- **NEVER delete, skip, or comment out a failing test to reach green** — the test is the specification. If it fails, fix the implementation, not the test.
- **NEVER test through private methods, internal collaborators, or mocked internals** — assert on behavior through the module's PUBLIC interface only. A test coupled to internals breaks on every refactor and stops being a specification; a test written at the public seam survives refactoring and is what makes the Refactor phase safe. If an issue names a deep-module seam, that seam IS the interface to test at.
- **NEVER write tests for behavior the current phase doesn't implement** — one behavior's full Red→Green→Refactor cycle at a time. Writing tests for imagined future features is speculation that locks in a design before you understand it.

### Pipeline Integrity
- **NEVER start planning with load-bearing assumptions ungathered** — a plan built on guessed scope, users, or success criteria targets the wrong feature; re-planning after the user corrects you mid-execution costs more than asking 3 questions up front
- **NEVER start execution without user-approved plan** — silent scope drift is the #1 cause of wasted work; the plan is the contract between agent and user
- **NEVER launch more than 4 parallel subagents per wave** — beyond 4, context switching overhead and parallel reasoning degradation produce worse output than sequential execution
- **NEVER skip size classification** — a "small" feature executed as "large" wastes hours; a "large" as "small" ships regressions without quality gates
- **NEVER add functionality beyond the stated scope** — scope creep in agent execution is invisible to the user until PR review; document additions as follow-ups instead
- **NEVER hardcode tool commands** — detected commands encode the project's actual toolchain; hardcoded commands silently fail in monorepos, Docker, or CI environments
- **NEVER create a monolith phase** — if a phase has >8 task-table rows (T-IDs), split it; large phases hide dependency cycles and make Red/Green boundaries impossible to enforce
- **NEVER skip inline gates for ANY feature size** — inline gates (tsc/lint/format/test) are the cheapest quality check; skipping them wastes expensive quality agent tokens on code with basic errors

### Quality & Verification
- **NEVER use the same agent context for scanning AND fixing** — a fixer agent that saw its own finding produces confirmation bias; separate contexts ensure clean-slate verification
- **NEVER auto-fix low-confidence findings** — access control and business logic vulnerabilities have 78%+ false positive rates at static analysis; an incorrect auto-fix creates a false-clean pipeline that ships a real vulnerability
- **NEVER skip Browser Verification** — there is no flag, size, or time pressure that exempts it. Unit tests verify behavior contracts; browser verification catches CSS composition failures, asset loading, JS runtime errors, and accessibility tree corruption that tests cannot detect
- **NEVER skip User Verification** — this is a HARD GATE. The pipeline STOPS until the human approves. Do NOT proceed after a timeout, infer approval from prior approval, or skip because "the feature is straightforward"
- **NEVER create a PR before User Verification approval and QA pass** — the human gate and QA swarm come before PR creation, not after. A PR without user approval and QA pass ships the agent's interpretation of "correct," not the user's
- **NEVER promote a PR to ready if ANY gate is failing** — a draft PR with failing gates is a checkpoint; a ready PR with failing gates ships broken code to reviewers

## Stage -1: Resume Check

Check if `.claude/workflow-state.local.md` exists:

**If it exists and `type: feature`** — resumed workflow:
1. Read the state file to restore: workflow type, branch, description, size, detected commands, current position, worktree path
2. Verify git state: `git branch --show-current` matches stored branch. **If mismatch**: check if the stored worktree path exists (`git worktree list`). If it does, tell the user: **"You're in the main repo. The feature worktree is at [path]. Switch there to resume."** Stop.
3. Read `.claude/feature-plan.local.md` for the full plan
4. Skip to the first incomplete item in Progress section
5. Tell the user: **"Resuming from [current position]. [N] phases complete, continuing with [next phase]."**
6. Jump directly to the incomplete stage — do NOT re-plan

**If it exists but `type` is NOT `feature`** — different workflow in progress. Tell the user and stop.

**If state file is missing but `.claude/feature-plan.local.md` exists** — partial state:
1. Read the plan, check git log for phase commits to reconstruct progress
2. Re-run project detection, create fresh state file
3. Ask: **"I found an in-progress feature plan. Continue from where it left off?"**

**If neither exists** — fresh start. Proceed to Stage 0.

---

## Stage 0: Setup

1. Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/project-detection.md` and detect the project environment (all shared references use the `${CLAUDE_PLUGIN_ROOT}/skills/shared/` prefix)
2. Parse `$ARGUMENTS` for: feature description, `--size small|medium|large`, `--max-iterations N` (default: small=25, medium=50, large=100), `--no-worktree`. Note: there is NO flag to skip verification or quality gates.
3. Create branch: ask user for name (suggest `feature/<ticket>-<short-desc>`, always lowercase, no special chars beyond `-/`)
4. Create worktree (`git worktree add ../code-worktrees/<branch> -b <branch>`) or branch in-place if `--no-worktree`
5. Create `.claude/workflow-state.local.md` with initial values (see planning.md for template)

---

## Stage 1: Planning

### 1.0: Clarification Gate

**Before exploring the codebase or drafting a plan, surface what's unclear in the request.** A plan built on guessed requirements ships the wrong thing or forces re-planning mid-execution — both waste far more time than asking up front.

1. **List every assumption** you'd have to make to draft the plan. Cover: scope boundaries, target users and triggers, input/output shape, success criteria, constraints (perf, compat, style, deadline), and which existing patterns to follow.

2. **Classify each assumption as load-bearing or cosmetic.** Load-bearing = guessing wrong would change the file list, data model, API shape, test cases, or acceptance criteria. Cosmetic = details the user is unlikely to care about.

3. **If ANY load-bearing assumption remains, STOP and ask the user.** Batch into a single message (max 5 questions). Offer concrete options where possible so the user can answer fast:

   > Before I plan this, I need to confirm:
   > 1. [question — with 2-3 concrete options]
   > 2. [question]
   > Anything else I should know?

4. **Wait for the response. Do NOT proceed until the user replies.** Fold the answers into the request and re-run step 2. When only cosmetic assumptions remain, continue to Stage 1.1.

**Do NOT ask questions the codebase can answer.** File layouts, existing patterns, naming conventions, test framework, available utilities — look these up with `Grep`/`Read`, don't burn user attention on them. Reserve questions for intent, priorities, edge-case preferences, and constraints only the user has.

**Skip this gate only if:** the request already specifies exact files, exact behavior, and exact test cases, OR the user explicitly says "just start" / "you decide" / "use your judgment" — in which case, document the assumptions you made at the top of the plan so the user can correct them at plan approval.

### 1.1: UI Showcase Gate

**If the feature involves UI** (new page, component, layout, dashboard, visual interface):

1. Invoke the `showcase` skill first — it explores the codebase, brainstorms approaches, and produces an interactive HTML findings deck
2. Open the showcase page for the user and ask: **"Which direction interests you? Pick an idea or describe what you'd like to combine."**
3. **STOP until user responds.** Their selection becomes the design direction for the rest of the pipeline.

**Skip this step if:** the feature is backend-only, API-only, CLI, config, or the user already provided a specific visual design/mockup.

### Before Planning — Think First

- **Scope**: Is this truly one feature? If you'd need "and" in the PR title, it's probably two features.
- **Risk**: What's the riskiest part? Plan that phase first so failures surface early.
- **Testability**: How will each behavior be tested? If you can't describe the test, the behavior is underspecified.
- **Blast radius**: How many existing tests will break? If >10, the approach may be wrong.

### 1.2: Codebase Exploration

Launch up to 3 Explore agents in parallel (model: `haiku`) to understand:
- Existing components, patterns, and utilities relevant to this feature
- Test patterns, test file naming conventions, and existing test files
- Code that can be reused

### 1.3: Create TDD Implementation Plan

**MANDATORY — READ ENTIRE FILE**: Load [`planning.md`](planning.md) for the plan template.

The plan MUST include:
- TDD Phase Triplets (Red/Green/Refactor) for every implementation phase
- A Behavior Inventory (Given/When/Then table)
- Browser Verification Steps section
- User Verification Steps section
- All inline gates and quality pipeline phases

### 1.4: Size Classification

If `--size` not provided, classify:
- **Small** (1-3 files, single concern): config, CSS, copy, simple refactor
- **Medium** (4-15 files, 1-2 areas): new component, API endpoint, moderate feature
- **Large** (15+ files, cross-cutting): full-stack, major refactor, new subsystem

### 1.5: Plan Validation & Approval

**Before presenting the plan, validate it against the TDD Plan Validation Checklist in planning.md.** A plan that fails validation MUST be fixed before presenting to the user.

Show the full plan with TDD phases, behavior inventory, verification steps, and quality gates.

**DO NOT proceed until the user explicitly approves.** Valid approval: "looks good", "approved", "go ahead", "yes", "start". Ambiguous signals are NOT approval — ask: **"Should I start implementation, or would you like changes first?"**

---

## Stage 2: TDD Execution

### Resource Loading by Size

| Size | When current phase is... | Load | Do NOT Load |
|------|--------------------------|------|-------------|
| Small | Quality Pipeline | `references/quality-gates.md` | `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` |
| Small | Browser Verification | `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` | `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` |
| Medium | Quality Pipeline | `references/quality-gates.md` | `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` |
| Medium | Browser Verification | `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` | `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` |
| Large | Quality Pipeline | `references/quality-gates.md` | — |
| Large UI | E2E Tests | `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` | — |
| Large | Browser Verification | `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` | — |

**If a shared reference file is not found**: Fall back to manual execution of that gate. **NEVER skip a gate entirely because a reference file is missing.**

### Execution Path

**MANDATORY — READ ENTIRE FILE**: Load [`execution-prompt.md`](execution-prompt.md) for full execution instructions.

**Primary path (direct execution)**: Follow execution-prompt.md manually — execute each section sequentially, using the Agent tool with `run_in_background: true` (max 4, model: `sonnet`) for parallelizable wave tasks. If stuck after 3 attempts on any step, stop and ask the user.

**Accelerated path (if ralph-loop plugin is installed)**: Invoke ralph-loop with the execution prompt contents and `--completion-promise "FEATURE COMPLETE" --max-iterations <N>` (where N = small:25, medium:50, large:100). Note: ralph-loop will pause at the User Verification hard gate — this is by design.

**If neither path works**: Execute execution-prompt.md as a direct instruction set. Run one iteration: read state → execute current phase → update state → continue. At ~70% context capacity, write state and start a fresh context.

---

## Stage 3: Inline Gates

**Preferred: Use check-all script** — runs all gates in one call:

```bash
"${CLAUDE_PLUGIN_ROOT}"/skills/shared/scripts/check-all --fix
```

Runs typecheck → lint → format → test in sequence, outputs JSON results. Gates that don't exist in the project are auto-skipped. Add `--continue` to run all gates even if some fail.

**Manual fallback** (if script unavailable):

```
$TYPECHECK_CMD  →  $LINT_CMD --fix  →  $FORMAT_CMD  →  $TEST_CMD
```

Skip any gate where the command is empty.

If any fail: fix inline, commit, re-run. Do NOT proceed to quality agents until all four pass.

---

## Stage 4: Quality Pipeline

> Runs AFTER all TDD phases complete and AFTER inline gates pass.
> Detailed agent prompts in [`references/quality-gates.md`](references/quality-gates.md).

### 4.1: Parallel Quality Agents (MANDATORY — ALL SIZES)

**MANDATORY — READ ENTIRE FILE**: Load [`references/quality-gates.md`](references/quality-gates.md) before spawning agents.

Launch up to 4 quality agents in parallel (all write artifacts to `.claude/quality/`):

| Agent | Model | Artifact |
|-------|-------|----------|
| Security Scanner | `sonnet` | `.claude/quality/security.md` |
| Performance Analyzer | `sonnet` | `.claude/quality/performance.md` |
| Accessibility Auditor | `sonnet` | `.claude/quality/accessibility.md` |
| Type-Safety Checker | `sonnet` | `.claude/quality/type-safety.md` |

Wait for ALL agents to complete. Each MUST produce a valid `## Verdict` block.

### 4.2: Aggregate & Gate

Build gate table from artifacts. Gate rules:
- Any `VERDICT=FAIL` → must fix before proceeding
- IMPORTANT findings → auto-fix if high confidence, otherwise document
- MINOR findings → document in PR only

### 4.3: Auto-Remediation Loop

Follow the protocol in `references/quality-gates.md`:
- Scanner, fixer, verifier MUST be **separate agent contexts**
- **2 fix attempts per finding** — then "Requires human review"
- If fix makes scan worse → **REVERT** and flag for human

---

## Stage 5: Browser Verification (NON-SKIPPABLE)

**There is no flag, argument, size, or time pressure that exempts this stage.**

### 5.1: Agent-Driven Verification

**MANDATORY — READ FIRST**: Load `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` (or `${CLAUDE_PLUGIN_ROOT}/skills/shared/verification.md` if no browser needed).

For UI features:
1. Start dev server — **prefer** `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/start-dev-server` (auto-detects command, polls until ready, returns `{url, pid}`). Fall back to manual `$DEV_CMD`.
2. Inject `[VERIFY]` debug logs at key code paths
3. Execute each Browser Verification Step from the plan
4. For each step: record PASS/FAIL assertion
5. Check console for errors (HARD GATE — same-origin errors = FAIL)
6. Capture screenshots as evidence
7. Write results to `.claude/verification/browser-results.md`

For non-UI features (API/CLI/backend):
1. Execute Runtime Verification Steps from the plan
2. Run `$TEST_CMD --grep "integration"` subset if applicable
3. Write results to `.claude/verification/runtime-results.md`

### 5.2: Verification Gate

ALL assertions must PASS. If any fail:
- Implementation bug → return to appropriate TDD phase, fix, re-run from inline gates
- Plan/test bug → flag to user, do NOT auto-fix plan assertions

Remove all `[VERIFY]` debug strings after verification passes.

---

## Stage 6: User Verification (NON-SKIPPABLE — HARD GATE)

**This stage CANNOT be automated, delegated to a subagent, or inferred from prior results.**

### 6.1: Present to User

Show:
- Feature description (from plan)
- Browser verification results / screenshots
- Quality gate summary table
- Dev server URL (if applicable)
- The **User Verification Steps** from the plan — these are specific criteria, NOT generic "does this look right?"

### 6.2: Get Explicit Approval

Ask: **"Please verify the feature using the steps above. Respond with 'approved' to proceed to PR, or describe any issues to fix."**

**STOP. Do NOT proceed until user responds.**
- "yes", "looks good", "approved", "ship it" → proceed to PR
- "no", "fix X", specific issues → fix, re-run from Stage 5
- "maybe", "interesting", "hmm" → NOT approval. Ask: **"Should I proceed to PR, or would you like changes?"**

### 6.3: If Rejected

Fix reported issues, re-run verification stages (5 and 6), get new approval.

---

## Stage 7: QA Pass (NON-SKIPPABLE)

**Run the `/qa` skill against the current branch before creating a PR.**

This deploys a full agent swarm (code analysis, browser testing, accessibility, security, edge cases) that catches issues the earlier quality pipeline may miss — particularly cross-cutting integration bugs, runtime behavior in the browser, and edge cases.

### 7.1: Invoke QA

Invoke the `qa` skill with the current branch name:
- The QA skill will detect changed files, start the dev server, and deploy its agent swarm
- It produces a comprehensive QA report at `.qa-report/QA-REPORT.md`

### 7.2: QA Gate

Read `.qa-report/QA-REPORT.md` and check the verdict:
- **PASS** → proceed to PR Creation
- **PASS WITH NOTES** → review "Should Fix" items. Fix any that are quick wins (< 5 min each), then proceed
- **FAIL** → fix all ship-blockers, re-run inline gates (Stage 3), then re-run `/qa`

### 7.3: User Manual Testing

The QA skill offers the user a live browser session for manual verification. **Let the user test if they want to** — do not skip or rush this. If the user declines, proceed.

---

## Stage 8: PR Creation

### 8.1: Push & Create Draft PR

```bash
git push -u origin $(git branch --show-current)
gh pr create --draft --title "<type>(<scope>): <description>" --body "$(cat .claude/pr-description.md)"
```

### 8.2: PR Description

Generate from:
1. `git log main..HEAD --oneline` — commit history (should show Red/Green/Refactor pattern)
2. `.claude/feature-plan.local.md` — the "Why"
3. `.claude/quality/*.md` — quality gate results
4. `.claude/verification/browser-results.md` — verification results
5. `.qa-report/QA-REPORT.md` — QA swarm results

Use the quality badge pattern:

```markdown
## Why
[One sentence from the plan]

## What
- [Bullet point changes, grouped by concept]

## TDD Evidence
- [N] Red/Green/Refactor cycles completed
- [N] behaviors tested (from Behavior Inventory)

## Quality Gate
| Check | Status | Details |
|-------|--------|---------|
| Tests | PASS | N passed |
| Lint | PASS | 0 errors |
| Typecheck | PASS | 0 errors |
| Security | PASS | N findings |
| Performance | PASS | N findings |
| Accessibility | PASS | N findings |
| Type Safety | PASS | N findings |
| Browser Verification | PASS | N/N steps |
| User Verification | PASS | Approved by user |
| QA Swarm | PASS | Verdict from /qa |

## How to Test
- [ ] [Exact test commands or manual steps]
```

### 8.3: Promote to Ready

**STOP. Before promoting, verify ALL of the following — run each check NOW:**

1. `$TEST_CMD` passes — RUN IT NOW
2. `$LINT_CMD` passes — RUN IT NOW
3. `$TYPECHECK_CMD` passes — RUN IT NOW
4. All 4 quality gate artifacts exist with valid `## Verdict` sections
5. All quality gate VERDICTs are PASS (or findings documented as Known Issues)
6. Browser/runtime verification results exist with all assertions PASS
7. User has explicitly approved (this CANNOT be verified programmatically — if you haven't shown the user the verification report and received approval, STOP and do so now)
8. QA swarm verdict is PASS or PASS WITH NOTES (no unresolved ship-blockers)
9. No `[VERIFY]` debug strings remain in source files
9. Git log shows Red→Green→Refactor commit ordering

```bash
gh pr ready $(gh pr view --json number -q .number)
```

### 8.4: Cleanup

1. Delete `.claude/workflow-state.local.md`
2. Delete `.claude/feature-plan.local.md`
3. Delete `.claude/quality/` directory
4. Delete `.claude/verification/` directory
5. Delete `.qa-report/` directory
6. Final commit if cleanup produced changes

### 8.5: Recommend the next step (ALWAYS)

End by telling the user what to do next, so they don't have to remember the flow:

- **If this issue came from a `flow-to-issues` plan** (a `.specs/<NNN>-*/issues/` set exists): name the next unbuilt issue in dependency order and offer to continue — *"#01 shipped. Next unblocked issue is #02 (`<title>`). Mr Claude can `/flow-handoff` it into a fresh session and run `/flow-feature` — start it? HITL issues still need your decision first."* When all issues are built, suggest **`/flow-deepen`** (if installed) or a `/code-review` of the branch.
- **If this was a standalone feature** (no flow plan): suggest the natural follow-up — review the PR, or run `/qa` on the branch.

Keep it to one or two lines. The goal is a clear, single next action — not a menu.

---

## Model Routing Matrix

| Task | Model | Why |
|------|-------|-----|
| Codebase exploration | `haiku` | Read-only, no reasoning |
| Red phase (test writing, subagents) | `sonnet` | Test design needs reasoning |
| Green phase (implementation, subagents) | `sonnet` | Implementation needs reasoning |
| Lint/format/tsc | inline (no agent) | CLI commands, zero LLM cost |
| Quality gate agents | `sonnet` | Cross-file analysis |
| Auto-fix agents | `sonnet` | Scope-constrained fix reasoning |
| Browser verification | inline (orchestrator) | Sequential CLI commands |
| PR description generation | inline (orchestrator) | Has full context |
| Simple file lookups | `haiku` | Never pay sonnet for reads |

---

## Failure Signals & Recovery

| Signal | Meaning | Action |
|--------|---------|--------|
| Red phase tests pass (exit 0) | Tests don't test new behavior | STOP. Rewrite tests. Do NOT proceed to Green. |
| Green phase tests fail after 3 attempts | Implementation approach is wrong | STOP. Report to user. |
| Green modifies test files | Agent is doing retroactive TDD | REVERT. Return to Red. |
| Same test fails 3x after fix attempts | Fix approach is wrong | STOP. Report to user. |
| Quality agent returns empty findings | May have failed silently | Check artifact exists AND contains `## Checked` |
| Fix iteration makes scan worse | Fix introduced regressions | REVERT. Flag for human. |
| Browser verification fails | Feature has runtime bug | Return to TDD phase, fix, re-run pipeline. |
| User rejects at verification | Feature doesn't match intent | Fix issues, re-run from Stage 5. |
| QA verdict is FAIL | Ship-blockers found | Fix blockers, re-run inline gates (Stage 3), then re-run QA. |
| Context at ~70% capacity | Performance cliff | Complete current phase, write state, compress. |
