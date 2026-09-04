---
name: review
description: Shared PR review and quality gate workflow — tiered review (quick/standard/full), agent team orchestration with structured output contracts, PR creation with quality summary
---

# PR Review & Quality Gate

This workflow handles code review and PR creation for both feature development and bug fixes.

## NEVER Do

- **NEVER push to main directly** — always create a PR from the feature/fix branch
- **NEVER approve your own review when critical findings exist** — escalate to the user
- **NEVER let review agents modify code in the full review tier** — they advise, you decide and apply
- **NEVER skip CI checks even if the review passes** — lint/format/typecheck are non-negotiable gates
- **NEVER run the full review tier for small changes** — it wastes tokens and adds noise; match tier to scope

## Prerequisites

- Project detection has been run (need `TEST_CMD`, `LINT_CMD`, `FORMAT_CMD`, `TYPECHECK_CMD`)
- All implementation work is committed
- A feature branch exists with commits ahead of main

## Step 1: Determine Changed Files

```bash
git diff --name-only main...HEAD
git diff --name-only
git diff --name-only --cached
```

Combine and deduplicate. If no changed files, tell the user and stop.

## Step 2: Review Tiers

### Quick Review (small features / simple fixes)

Minimal gate — just ensure nothing is broken. No agents spawned — run checks inline:

1. Run `$TEST_CMD` — all tests must pass
2. Run `$LINT_CMD` — no lint errors
3. If either fails, fix and re-run
4. Proceed to PR creation

### Standard Review (medium features / moderate fixes)

Run improvement agents scoped to ONLY the changed files:

1. **Sequential pass** (both modify code structure — order matters):
   - Run `/simplify` (built into Claude Code, not a file in this repo) scoped to the changed files (dead code, unused imports, reuse and simplification; it applies its fixes)
   - `code-simplifier` agent (subagent_type: `code-simplifier:code-simplifier`, model: `sonnet`) only if that plugin is installed; otherwise skip — `/simplify` already covers it

2. **Parallel pass** (independent work — launch both with `run_in_background: true`):
   - Comments: a `general-purpose` agent (model: `sonnet`) adds comments only where the WHY is non-obvious in the changed files; no restating of code
   - Tests: a `general-purpose` agent (model: `sonnet`) writes or improves tests for the changed code, matching the project's framework; it must run `$TEST_CMD` and report the real count

3. Run all CI checks after agents complete:
   ```bash
   $TEST_CMD
   $LINT_CMD
   $FORMAT_CMD
   $TYPECHECK_CMD
   ```

4. Fix any failures, commit fixes
5. Proceed to PR creation

### Full Review (large features / complex fixes)

Spawn a **3-agent review team** in parallel. Each agent has a distinct role, clear input, and a structured output contract so results can be aggregated mechanically.

#### Agent Team — Launch ALL THREE in parallel with `run_in_background: true`

**Agent 1 — Code Reviewer** (subagent_type: `feature-dev:code-reviewer`, model: `sonnet`):
```
Review the diff for this branch against main.
Run: git diff main...HEAD

Focus areas (in priority order):
1. Security: injection, auth bypass, data exposure, secrets in code
2. Correctness: logic errors, off-by-one, null/undefined, race conditions
3. Design: does the approach fit existing architecture patterns?
4. Edge cases: empty states, error paths, boundary values, concurrent access
5. For bug fixes: does the fix address root cause or just mask symptoms?

Output EXACTLY this format:

## Code Review Findings
| # | Severity | File:Line | Finding | Suggestion |
|---|----------|-----------|---------|------------|

Severity levels: CRITICAL (must fix before merge), IMPORTANT (should fix), MINOR (nice to have)

## Summary
CRITICAL_COUNT=N IMPORTANT_COUNT=N MINOR_COUNT=N
VERDICT=PASS|FAIL (FAIL if any CRITICAL)
```

**Agent 2 — Simplicity Auditor** (subagent_type: `code-simplifier:code-simplifier`, model: `sonnet`):
```
Audit ONLY these changed files for unnecessary complexity:
[list changed files here]

Check for:
1. Over-engineering: abstractions with only one consumer, premature generalization
2. Dead code: unused variables, unreachable branches, commented-out code
3. Missed simplifications: verbose patterns with concise equivalents in this language
4. Naming: unclear or misleading names that will confuse future readers
5. Duplication: repeated logic across the changed files that should be extracted

Output EXACTLY this format:

## Simplicity Audit Findings
| # | Severity | File:Line | Finding | Suggestion |
|---|----------|-----------|---------|------------|

Severity levels: CRITICAL (actively harmful complexity), IMPORTANT (should simplify), MINOR (style preference)

## Summary
CRITICAL_COUNT=N IMPORTANT_COUNT=N MINOR_COUNT=N
VERDICT=PASS|FAIL (FAIL if any CRITICAL)
```

**Agent 3 — CI Runner** (subagent_type: `general-purpose`, model: `haiku`):
```
Run the full CI check suite and report results. Run each check independently — do not stop on first failure.

Checks to run:
1. Unit tests: [TEST_CMD]
2. E2E tests (if command exists): [E2E_CMD]
3. Linting: [LINT_CMD]
4. Formatting: [FORMAT_CMD]
5. Type checking: [TYPECHECK_CMD]

Output EXACTLY this format:

## CI Results
| Check | Status | Details |
|-------|--------|---------|
| Unit Tests | PASS/FAIL | N passed, N failed, N skipped |
| E2E Tests | PASS/FAIL/SKIP | N passed, N failed |
| Lint | PASS/FAIL | N errors, N warnings |
| Format | PASS/FAIL | N files need formatting |
| Typecheck | PASS/FAIL | N errors |

For any FAIL: include the full error output below the table under a ### Failures section.

## Summary
VERDICT=PASS|FAIL
```

#### Aggregation Protocol

After all three agents complete:

1. **Parse** each agent's `VERDICT` and finding counts from their structured output
2. **Build the quality gate table**:

| Reviewer | Verdict | Critical | Important | Minor |
|----------|---------|----------|-----------|-------|
| Code Review | PASS/FAIL | N | N | N |
| Simplicity | PASS/FAIL | N | N | N |
| CI Suite | PASS/FAIL | — | — | — |

3. **Apply gate rules**:
   - Any `VERDICT=FAIL` → **GATE FAILED** → must fix before PR
   - Fix all CRITICAL findings first, re-run only the affected agent's checks
   - IMPORTANT findings → fix if straightforward (<5 min each), otherwise document as "Known Issues" in the PR description
   - MINOR findings → note in PR description only, do not fix now

4. **Re-verify** after fixes: re-run CI Runner agent only (don't re-run full review team unless critical findings required architectural changes)

#### Fallback

If specialized agent types (`feature-dev:code-reviewer`, `code-simplifier:code-simplifier`) are not available, use `general-purpose` agents (model: `sonnet`) with the same prompts. The prompts are self-contained — the agent type adds domain context but is not required.

## Step 3: PR Creation

```bash
git push -u origin $(git branch --show-current)
```

Create PR with `gh pr create`:

**Quick tier:**
```
Title: <type>(<scope>): <description>  (under 70 chars)
Body:
  ## Summary
  - <1-3 bullet points of what changed>

  ## Test Plan
  - [ ] All tests pass
```

**Standard tier:**
```
Title: <type>(<scope>): <description>  (under 70 chars)
Body:
  ## Summary
  - <what was done and why>

  ## Changes
  - <file-by-file or area-by-area breakdown>

  ## Test Plan
  - [ ] Unit tests pass
  - [ ] Lint/format/typecheck clean
  - [ ] <manual verification steps if applicable>
```

**Full tier:**
```
Title: <type>(<scope>): <description>  (under 70 chars)
Body:
  ## Summary
  - <what was done and why>

  ## Changes
  - <detailed breakdown>

  ## Quality Gate
  | Reviewer | Verdict | Findings |
  |----------|---------|----------|
  | Code Review | PASS | N critical, N important, N minor |
  | Simplicity | PASS | N critical, N important, N minor |
  | CI Suite | PASS | All checks green |

  ## Known Issues
  - <any IMPORTANT/MINOR findings deferred from review>

  ## Test Plan
  - [ ] Unit tests pass
  - [ ] E2E tests pass (if applicable)
  - [ ] Lint/format/typecheck clean
  - [ ] Browser verification complete (if UI changes)
  - [ ] <manual verification steps>
```

## Step 4: Report

Output the PR URL so the user can review it. If the PR was created successfully, this phase is complete.
