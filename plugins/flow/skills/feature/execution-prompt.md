---
name: feature-execution-prompt
description: TDD-first execution state machine — state restoration, Red/Green/Refactor phase handlers with exit-code gates, commit discipline, gate-phase handlers, and error recovery.
---

# Feature Execution Prompt

Follow this as sequential execution instructions, or pass it as the prompt argument to a loop runner. You are executing a TDD-first plan one phase at a time.

## 1. State restoration (every iteration)

Read `.claude/workflow-state.local.md` and hold: `SIZE`, `CURRENT_PHASE` (first unchecked item in `## Progress`), `LAST_COMMIT`, and `TEST_CMD` / `LINT_CMD` / `FORMAT_CMD` / `TYPECHECK_CMD` / `E2E_CMD` from Project Environment. Then read the plan — `.claude/feature-plan.local.md`, or the slice brief when one was handed to you (it is the whole assignment; read only the files it names).

If the plan header names a design file, its `## Contract for this slice` block is **binding for this slice's RED phase**, where stubs and signatures are written — a design arriving later cannot bind, because REFACTOR may not change public API surface. **Never edit the contract file** it points to: import from it. A type this slice needs that is not there is an escalation, not a local declaration.

**Scope check first.** Handed a single slice brief, you own §2–§4 for that slice only: finish its REFACTOR, report, and STOP — §5 and §6 belong to the orchestrator that dispatched you, and running them destroys state the other slices still need. Only a run that owns the whole plan continues: all phases checked → go to §5.

## 2. Rules

- Follow CLAUDE.md. Use the state file's commands, never hardcoded ones.
- Commit after each sub-phase with a conventional message; update the state file after each sub-phase.
- Launch subagents with an explicit `model`; max 4 per wave.
- **Never edit a test to go green, skip it, xfail it, or lower a threshold to pass a gate.** The Stop gate blocks the turn while gates are red and the tamper notice puts any weakening on the record — satisfy the check, do not suppress it. Formatting and file/function size are handled by hooks; do not spend a phase on them.
- Quality artifacts go to `.claude/quality/`, verification evidence to `.claude/verification/`.

## 3. Error recovery (know this before starting)

| Situation | Do |
|---|---|
| RED tests pass (exit 0) | STOP. They test nothing new. Rewrite them. |
| GREEN still failing after 3 attempts | STOP. Report the failure details to the user. |
| GREEN modified a test file | TDD violation. Revert the test change, return to RED. |
| Blocked by an unexpected dependency | Document it in the state file, ask the user. |
| Subagent produced broken code | Fix inline (max 2), then revert and do it yourself. |
| A fix makes the scan worse | REVERT it, flag for human review. |
| Browser verification failed | Return to the TDD phase, fix, re-run from inline gates. |
| User rejected at verification | Fix the issues, re-run from browser verification. |
| Context near ~70% | Finish the current phase (NEVER mid-phase), write state, compress. |

## 4. Execute the current phase

### RED
Confirm every task is a test or a stub. Write stubs with correct signatures that throw the language's not-implemented error. Write tests that import from stubs or existing modules, carry meaningful assertions (never `toBeDefined()` / `toBeTruthy()` / `not.toThrow()`), name their behavior ID, and include at least one error/edge case. Run `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/test-changed` (falls back to `$TEST_CMD`).
**HARD GATE**: exit non-zero → proceed. Exit zero → **STOP**; the tests are green-bar, testing pre-existing behavior, or the implementation already exists. Rewrite them; do not proceed to GREEN.
Commit `test(<scope>): add failing tests for <phase> [RED]` — tests and stubs only; verify with `git diff --name-only HEAD~1..HEAD`. Mark the sub-phase `[x]` with its commit hash.

### GREEN
Implementation files only. Write the **minimum** code that makes the failing tests pass — no behavior beyond what RED specifies. Do not modify any test file; if a test needs changing, STOP and return to RED. Run `test-changed`, falling back to `$TEST_CMD`.
**HARD GATE**: exit zero → proceed. Non-zero after 3 attempts → STOP and report. Confirm the diff shows no test files.
Commit `feat(<scope>): implement <phase>`. Update state.

### REFACTOR
Record the exact pass count from GREEN. Apply the `clean-code` skill to everything written in this phase's RED and GREEN: intention-revealing names, one job per function, self-documenting code over comments, Law of Demeter, no rigidity or needless complexity. Constraints: no new behavior, no test changes, **no public API surface change**. Run `$TEST_CMD` after each change, not only at the end.
**HARD GATE**: pass count drops at any point → REVERT that change immediately. Never fix a failing test during REFACTOR — a drop means the refactor changed behavior.
Commit `refactor(<scope>): clean <phase> implementation`. Update state.

### Inline Gates
Run `flow check --fix` (typecheck → lint → format → test; missing gates skip). Fix the code, not the test. Never silence a type error with `as any` or `@ts-expect-error`. Commit `chore: pass inline quality gates`.

### Quality / review, E2E, Browser Verification, User Verification, QA, PR
These gate phases belong to the calling skill, which owns their protocol and their reads — `${CLAUDE_PLUGIN_ROOT}/skills/feature/references/quality-gates.md` for the quality dimensions, `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` for E2E, `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` for browser work (start the server with `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/start-dev-server`, treat same-origin console errors as FAIL, write evidence to `.claude/verification/`, then strip every `[VERIFY]` string). **User Verification is a HARD GATE in the caller's main loop**: present the results and the plan's User Verification Steps, ask for explicit approval, and STOP. Silence, "hmm" and "maybe" are not approval. Never open a PR before it clears.

## 5. Completion check — whole-plan runs only

Every phase `[x]`; `$TEST_CMD`, `$LINT_CMD`, `$TYPECHECK_CMD` **run now** and exit 0; no `[VERIFY]` strings remain; `git log` shows Red → Green → Refactor; verification evidence exists with every assertion PASS; the user explicitly approved. Any failure → fix and re-run all checks; three failed attempts → STOP and report. There is no size-based exemption.

Completion is proven by the orchestrator re-running `TEST_CMD`, never asserted. Report the phases completed, the commit hashes, and the exit codes you observed.

## 6. Cleanup — whole-plan runs only, after the PR is open

Delete `.claude/workflow-state.local.md`, `.claude/feature-plan.local.md`, `.claude/pr-description.md`, `.claude/quality/`, `.claude/verification/`, `.qa-report/`.
