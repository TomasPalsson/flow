---
name: feature-planning
description: TDD-first plan templates for feature development — Behavior Inventory, Red/Green/Refactor phase triplets, verification steps, and quality gates for small/medium/large features
---

# TDD Feature Plan Templates

Use the template matching the feature's size classification. Create the plan at `.claude/feature-plan.local.md`.

**If the spec directory contains a `code-design.md`**, every template's title line gains a design segment — `# Feature: [name]  (design: .specs/<NNN>-<slug>/code-design.md)` — and every phase gains a `- **Design trace**: <the code-design sections and contract types this phase implements>` line beneath its behavior list. Omit both entirely when there is no `code-design.md`. This is not decoration: `execution-prompt.md`'s design instruction fires on the plan header naming a design file, so a plan that omits the segment silently drops the design before Red, and every phase then re-invents the names, error shape and module placement the design fixed.

All templates use placeholder commands from project detection. Replace `[TEST_CMD]`, `[LINT_CMD]`, etc. with actual detected commands.

---

## Behavior Inventory (REQUIRED — ALL SIZES)

Before writing any plan phases, enumerate every behavior the feature must exhibit:

```markdown
## Behavior Inventory

| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| B1 | [precondition] | [action] | [expected outcome] | P0 |
| B2 | [precondition] | [action] | [expected outcome] | P0 |
| B3 | [precondition] | [action] | [expected outcome] | P1 |
| B4 | [error condition] | [action] | [error outcome] | P0 |
```

**Rules:**
- Every P0 behavior MUST have a corresponding test in a Red phase
- P1 behaviors are tested if time permits
- Behavior IDs appear in test names: `test("B1: returns user on valid credentials")`
- Include at least one error/edge case behavior per implementation phase
- If you cannot describe the behavior as Given/When/Then, the requirement is underspecified — ask the user

---

## Small Feature Template

For simple changes: 1-3 files, single concern.

```markdown
# Feature: [name]

## Description
[What the feature does and why]

## Behavior Inventory
| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| B1 | ... | ... | ... | P0 |
| B2 | ... | ... | ... | P0 |

## Phases

### Phase 1: [name] — RED
**Mandate**: Write failing tests. No implementation code beyond stubs.
- Create stub file(s) with correct signatures, all throwing NotImplementedError
- Write tests for behaviors B1, B2 (import from stubs)
- Run `[TEST_CMD]` — **MUST exit non-zero**
- If tests pass: STOP. Tests are not testing new behavior. Rewrite.

**Files**: [test files only]
**Commit**: `test(<scope>): add failing tests for [name] [RED]`

### Phase 1: [name] — GREEN
**Mandate**: Make Red tests pass. No new tests. No new behaviors.
- Replace stubs with real implementation
- Run `[TEST_CMD]` — **MUST exit zero**
- Confirm no test files modified (`git diff --name-only` shows only implementation files)

**Files**: [implementation files only — NO test files]
**Commit**: `feat(<scope>): implement [name]`

### Phase 1: [name] — REFACTOR
**Mandate**: Improve structure. No new behavior. No new tests.
- Review for clarity, duplication, naming
- Run `[TEST_CMD]` after each change — same pass count as Green
- If tests fail: REVERT last change immediately

**Commit**: `refactor(<scope>): clean [name] implementation`

### Phase 2: Inline Gates (MANDATORY)
- Run typecheck: `[TYPECHECK_CMD]`
- Run lint with auto-fix: `[LINT_CMD] --fix`
- Run format: `[FORMAT_CMD] --write`
- Run ALL tests: `[TEST_CMD]`
- Fix any failures

### Phase 3: Quality Pipeline (MANDATORY)
- Launch parallel quality agents (security, performance, accessibility, type-safety)
- Aggregate results
- Auto-fix high-confidence CRITICAL findings (max 2 attempts)
- Document remaining findings

### Phase 4: Browser Verification (MANDATORY — NON-SKIPPABLE)
- Execute Browser Verification Steps below
- Write results to `.claude/verification/browser-results.md`
- ALL assertions must PASS

### Phase 5: User Verification (MANDATORY — HARD GATE)
- Present verification results + screenshots to user
- Present User Verification Steps below
- **STOP and wait for explicit user approval**
- Do NOT proceed until user approves

### Phase 6: QA Pass (MANDATORY)
- Invoke `/qa` skill against current branch
- QA swarm deploys: code analysis, browser testing, accessibility, security, edge cases
- Fix ship-blockers if verdict is FAIL, re-run inline gates, then re-run `/qa`
- Fix quick-win "should fix" items if verdict is PASS WITH NOTES

### Phase 7: PR Creation
- Push branch
- Create draft PR with quality badge + TDD evidence + QA results
- Promote to ready after all gates pass + user approval + QA pass

## Browser Verification Steps
1. [Navigate to URL / run command]
2. [Interact with feature]
3. Expected: [specific, observable outcome]

## User Verification Steps
1. [Specific thing for human to verify]
2. [UX or behavior judgment call]

## Done When
- All behaviors in inventory are tested and passing
- All quality gates PASS
- Browser verification PASS
- User has approved
```

---

## Medium Feature Template

For moderate changes: 4-15 files, 1-2 areas.

```markdown
# Feature: [name]

## Description
[What the feature does and why]

## Options
- max_iterations: [N]

## Behavior Inventory
| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| B1 | ... | ... | ... | P0 |
| B2 | ... | ... | ... | P0 |
| B3 | ... | ... | ... | P0 |
| B4 | ... | ... | ... | P1 |

## Phases

### Phase 1: [name] — RED
**Mandate**: Write failing tests ONLY.

#### Tasks
| ID | Task | Files | Depends On |
|----|------|-------|------------|
| T1.1 | Create stubs for [component] | [stub files] | — |
| T1.2 | Write tests for B1, B2 | [test files] | T1.1 |
| T1.3 | Write tests for B3 | [test files] | T1.1 |

**Red Gate**: Run `[TEST_CMD]` — MUST exit non-zero. All T1.2/T1.3 tests must fail meaningfully (not import errors).
**Commit**: `test(<scope>): add failing tests for [name] [RED]`

### Phase 1: [name] — GREEN
**Mandate**: Make Red tests pass. No new tests.

#### Tasks
| ID | Task | Files | Depends On | Parallelizable |
|----|------|-------|------------|----------------|
| T1.4 | Implement [component A] | [impl files] | T1.2 | Yes |
| T1.5 | Implement [component B] | [impl files] | T1.3 | Yes |

#### Execution Waves
- **Wave 1** [parallel]: T1.4, T1.5

**Green Gate**: Run `[TEST_CMD]` — ALL phase tests must pass. No test files modified.
**Commit**: `feat(<scope>): implement [name]`

### Phase 1: [name] — REFACTOR
**Mandate**: Clean structure, no new behavior.
- Review for duplication, naming, clarity
- Run `[TEST_CMD]` after each change
**Commit**: `refactor(<scope>): clean [name]`

### Phase 2: [name] — RED
... (repeat TDD triplet for next implementation phase)

### Phase 2: [name] — GREEN
...

### Phase 2: [name] — REFACTOR
...

### Phase [N]: Inline Gates (MANDATORY)
- Run typecheck: `[TYPECHECK_CMD]`
- Run lint with auto-fix: `[LINT_CMD] --fix`
- Run format: `[FORMAT_CMD] --write`
- Run ALL tests: `[TEST_CMD]`

### Phase [N+1]: Quality Pipeline (MANDATORY)
- Launch ALL 4 parallel quality agents
- Aggregate results
- Auto-fix CRITICAL and high-confidence IMPORTANT (max 2 attempts)
- Document remaining findings

### Phase [N+2]: Browser Verification (MANDATORY — NON-SKIPPABLE)
- Execute Browser Verification Steps
- Write results to `.claude/verification/browser-results.md`
- ALL assertions must PASS

### Phase [N+3]: User Verification (MANDATORY — HARD GATE)
- Present results + screenshots + dev server URL
- Present User Verification Steps
- **STOP and wait for explicit user approval**

### Phase [N+4]: QA Pass (MANDATORY)
- Invoke `/qa` skill against current branch
- QA swarm deploys: code analysis, browser testing, accessibility, security, edge cases
- Fix ship-blockers if verdict is FAIL, re-run inline gates, then re-run `/qa`
- Fix quick-win "should fix" items if verdict is PASS WITH NOTES

### Phase [LAST]: PR Creation
- Push branch
- Create draft PR with quality badge + TDD evidence + QA results
- Promote to ready after all gates pass + user approval + QA pass

## Browser Verification Steps
1. [Navigate to URL]
2. [Interact]
3. Expected: [specific outcome]

## User Verification Steps
1. [Specific criterion for human to check]
2. [UX judgment call]
3. [Acceptance criterion from feature request]

## Done When
- All P0 behaviors tested and passing
- All quality gates PASS
- Browser verification PASS
- User approved
```

---

## Large Feature Template

For complex changes: 15+ files, cross-cutting.

```markdown
# Feature: [name]

## Description
[What the feature does and why]

## Options
- max_iterations: [N]

## Behavior Inventory
| ID | Given | When | Then | Priority |
|----|-------|------|------|----------|
| B1-B[N] | ... | ... | ... | P0/P1 |

## Phases

### Phase 1: [name] — RED
**Mandate**: Write failing tests ONLY.

#### Tasks
| ID | Task | Files | Depends On | Parallelizable |
|----|------|-------|------------|----------------|
| T1.1 | Create stubs | [stubs] | — | Yes |
| T1.2 | Tests for B1-B3 | [tests] | T1.1 | Yes |
| T1.3 | Tests for B4-B6 | [tests] | T1.1 | Yes |

**Red Gate**: `[TEST_CMD]` MUST exit non-zero
**Commit**: `test(<scope>): add failing tests for [name] [RED]`

### Phase 1: [name] — GREEN
... (implementation waves, max 4 parallel subagents)

### Phase 1: [name] — REFACTOR
...

### Phase 2-N: [Implementation phases...]
... (each as Red/Green/Refactor triplet)

### Phase [N]: Inline Gates (MANDATORY)
- `[TEST_CMD]`, `[TYPECHECK_CMD]`, `[LINT_CMD] --fix`, `[FORMAT_CMD] --write`

### Phase [N+1]: E2E Tests (MANDATORY for UI features)
- Create E2E tests following project conventions
- Run: `[E2E_CMD]`

### Phase [N+2]: Quality Pipeline (MANDATORY)
- ALL 4 parallel quality agents
- Auto-fix ALL confidence levels (max 2 attempts)
- Re-run inline gates after fixes

### Phase [N+3]: Browser Verification (MANDATORY — NON-SKIPPABLE)
- Full verification tier: all viewports, all routes
- Execute ALL Browser Verification Steps
- Write results to `.claude/verification/browser-results.md`

### Phase [N+4]: User Verification (MANDATORY — HARD GATE)
- Present comprehensive verification report
- Present User Verification Steps
- **STOP and wait for explicit user approval**

### Phase [N+5]: QA Pass (MANDATORY)
- Invoke `/qa` skill against current branch
- QA swarm deploys: code analysis, browser testing, accessibility, security, edge cases
- Fix ship-blockers if verdict is FAIL, re-run inline gates, then re-run `/qa`
- Fix quick-win "should fix" items if verdict is PASS WITH NOTES

### Phase [LAST]: PR Creation
- Push, draft PR with full quality badge + TDD evidence + QA results + Known Issues
- Promote to ready after all gates pass + user approval + QA pass

## Dependency Graph (Mermaid)
[Graph showing TDD phases, gates, verification, PR]

## E2E Test Scenarios
1. [User flow with expected outcome]
2. [Another flow]

## Browser Verification Steps
1. [Navigate]
2. [Interact at desktop viewport]
3. Expected: [outcome]
4. [Interact at mobile viewport]
5. Expected: [outcome]

## User Verification Steps
1. [Feature works as described]
2. [Responsive behavior is correct]
3. [Accessibility check]
4. [Domain-specific correctness]

## Rollback Plan (MANDATORY for large)
- **Starting commit**: [hash]
- **Revert sequence**: `git revert --no-commit <first>..<last>`
- **Migrations to undo**: [list or "none"]
```

---

## TDD Plan Validation Checklist

### All Sizes (MANDATORY)
- [ ] Has Behavior Inventory with at least one P0 behavior
- [ ] Every implementation phase has Red/Green/Refactor sub-phases
- [ ] Red phases list ONLY test files
- [ ] Green phases list ONLY implementation files
- [ ] Each Red phase has a "Red Gate" exit-code check
- [ ] Each Green phase has a "Green Gate" pass check
- [ ] Inline Gates phase present
- [ ] Quality Pipeline phase present
- [ ] Browser Verification phase present with "NON-SKIPPABLE" label
- [ ] User Verification phase present with "HARD GATE" label
- [ ] QA Pass phase present
- [ ] PR Creation phase present
- [ ] Browser Verification Steps section is non-empty
- [ ] User Verification Steps section is non-empty
- [ ] Done When criteria reference behavior inventory

### Medium (additional)
- [ ] Task tables with IDs, files, dependencies
- [ ] Execution waves for parallelizable Green tasks

### Large (additional)
- [ ] E2E Tests phase (UI features)
- [ ] Mermaid dependency graph
- [ ] E2E Test Scenarios (at least 2)
- [ ] Rollback Plan

**A plan that fails validation MUST be fixed before presenting to the user.**

---

## Progress Section Template

Populate `## Progress` in `.claude/workflow-state.local.md`:

```markdown
## Progress
- [ ] Phase 1: [name] — RED
  - [ ] Stubs created
  - [ ] Tests written
  - [ ] Red Gate: tests fail (exit non-zero)
- [ ] Phase 1: [name] — GREEN
  - [ ] Implementation complete
  - [ ] Green Gate: tests pass (exit zero)
  - [ ] No test files modified
- [ ] Phase 1: [name] — REFACTOR
  - [ ] Refactoring complete
  - [ ] Tests still pass (same count)
- [ ] Phase 2: [name] — RED
  ...
- [ ] Inline Gates
  - [ ] Typecheck passes
  - [ ] Lint clean
  - [ ] Format clean
  - [ ] All tests pass
- [ ] Quality Pipeline
  - [ ] Security: .claude/quality/security.md
  - [ ] Performance: .claude/quality/performance.md
  - [ ] Accessibility: .claude/quality/accessibility.md
  - [ ] Type-safety: .claude/quality/type-safety.md
  - [ ] All gates PASS
- [ ] Browser Verification
  - [ ] All assertions PASS
  - [ ] Results written to .claude/verification/
- [ ] User Verification
  - [ ] Results presented to user
  - [ ] User approved: [yes/no — record response]
- [ ] QA Pass
  - [ ] /qa skill invoked
  - [ ] QA verdict: [PASS/PASS WITH NOTES/FAIL]
  - [ ] Ship-blockers resolved (if any)
  - [ ] Results at .qa-report/QA-REPORT.md
- [ ] PR Creation
  - [ ] Draft PR created
  - [ ] Quality badge in description
  - [ ] Promoted to ready
```

Mark each `[x]` with commit hash as it completes: `(commit: abc1234)`.
