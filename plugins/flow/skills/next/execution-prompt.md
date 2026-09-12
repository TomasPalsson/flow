---
name: next-execution-prompt
description: The per-task TDD loop a fresh developer subagent runs from one brief — Red/Green/Refactor with exit-code gates, commit discipline, and error recovery.
---

# Per-task execution prompt

You were handed **one brief path** and nothing else. That brief is the whole assignment.

## 1. Read the brief

`${brief}` carries `Base:` (the sha measured before you were dispatched), `Feature:` (the feature directory under `.specs/`), the TASKS.md header, your phase's `Goal:` and `Independent test:` lines, and your own task line with its `files:` and `verify:`.

Read only the files the brief names. There is no plan file and no state file to restore: your position is the brief plus `git log Base..HEAD`.

If the brief carries a `## Contract` block, it is **binding for RED**, where stubs and signatures are written — REFACTOR may not change public API surface, so a contract that arrives later cannot bind. Never edit the design file it came from: import from it. A type you need that is not there is an escalation, not a local declaration.

**Scope check.** You own §3 for this task only: finish REFACTOR, report, and STOP. The wave barrier, the re-run of your `verify:`, `flow tick`, the gates and the PR belong to the orchestrator that dispatched you.

## 2. Rules

- Follow CLAUDE.md. Use the `Test:` command from the brief header, never a hardcoded one.
- **Touch only the paths in `files:`.** Anything else you find goes in your report, not in a commit.
- Commit after each sub-phase with a conventional message.
- **Never** tick your own box. `flow tick` is the only writer of `[x]`, and the orchestrator runs it.
- **Never** edit a test to go green, skip it, xfail it, or lower a threshold to pass a gate. The Stop gate blocks the turn while gates are red and the tamper notice puts any weakening on the record — satisfy the check, do not suppress it. Formatting and file/function size are handled by hooks; do not spend a phase on them.
- Browser or screenshot evidence goes into `<Feature>/verify/`. A verification claim with no file there does not count.

## 3. Execute

### RED
Write stubs with correct signatures that throw the language's not-implemented error. Write tests that import from those stubs or existing modules, carry meaningful assertions (never `toBeDefined()` / `toBeTruthy()` / `not.toThrow()`), name their behavior ID, and include at least one error/edge case. Run `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/test-changed` (falls back to the brief's `Test:` command).
**HARD GATE**: exit non-zero → proceed. Exit zero → **STOP**; the tests are green-bar, testing pre-existing behavior, or the implementation already exists. Rewrite them; do not proceed to GREEN.
Commit `test(<scope>): add failing tests for <ID> [RED]` — tests and stubs only; verify with `git diff --name-only HEAD~1..HEAD`.

### GREEN
Before your first edit, state the search receipt: `searched: <terms>; found: <path:line | nothing>`. Implementation files only. Write the **minimum** code that makes the failing tests pass — no behavior beyond what RED specifies. Do not modify any test file; if a test needs changing, STOP and return to RED. Run `test-changed`, falling back to the brief's `Test:` command.
**HARD GATE**: exit zero → proceed. Non-zero after 3 attempts → STOP and report. Confirm the diff shows no test files.
Commit `feat(<scope>): implement <ID>`.

### REFACTOR
Record the exact pass count from GREEN. Apply the `clean-code` skill to everything written in this task's RED and GREEN: intention-revealing names, one job per function, self-documenting code over comments, Law of Demeter, no rigidity or needless complexity. Constraints: no new behavior, no test changes, **no public API surface change**. Run the test command after each change, not only at the end.
**HARD GATE**: pass count drops at any point → REVERT that change immediately. Never fix a failing test during REFACTOR — a drop means the refactor changed behavior.
Before reporting done, run `${CLAUDE_PLUGIN_ROOT}/skills/no-slop/scripts/slop-check --base <base>` and fix or justify each finding.
Commit `refactor(<scope>): clean <ID> implementation`.

### Inline gates
Run `flow check --fix` (typecheck → lint → format → test; missing gates skip). Fix the code, not the test. Never silence a type error with `as any` or `@ts-expect-error`. Commit `chore: pass inline quality gates`.

## 4. Error recovery

| Situation | Do |
|---|---|
| RED tests pass (exit 0) | STOP. They test nothing new. Rewrite them. |
| GREEN still failing after 3 attempts | STOP. Report the failure details. |
| GREEN modified a test file | TDD violation. Revert the test change, return to RED. |
| The task needs a file not in `files:` | STOP and report it. Widening the task in flight is what the wave barrier exists to prevent. |
| Blocked by an unexpected dependency | STOP and report it; the orchestrator records it as a `Discovered:` line. |
| Browser verification failed | Return to RED, fix, re-run the inline gates. |
| Context near ~70% | Finish the current sub-phase (NEVER mid-phase), commit, and report. |

For browser work: `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md`, start the server with `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/start-dev-server`, treat same-origin console errors as FAIL, write evidence to `<Feature>/verify/`, then strip every `[VERIFY]` string.

## 5. Report

Report the commits you made (sha + message), the exit codes you observed for RED, GREEN and the inline gates, and anything you found that is not in your brief. Do not claim `verify:` passed — the orchestrator re-runs it, and its exit code is the only ground truth.
