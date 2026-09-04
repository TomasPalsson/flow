---
name: flow-planning
description: How flow turns a spec into an internal vertical-slice build plan — decomposition rules, the Behavior Inventory, the plan template in the grammar plan-lint enforces, the gate phases block, and the validation rule. No GitHub issues, no AFK/HITL tags. Loaded in step 3.
---

# Flow Build Plan

The output is an **internal plan the pipeline builds straight through** — written once to `.claude/feature-plan.local.md`. A "slice" here is a build phase, not a ticket. The grammar below is not cosmetic: `slice-brief`, `slice-overlap` and `plan-lint` all parse this file, so a plan that drifts from it hands the wrong section to a build agent.

## Step 1 — Decompose into vertical slices

1. **Walk the spec's journeys, not its architecture** — happy, error and edge paths are your natural slices. Slice 1 is the **walking skeleton**: the thinnest end-to-end path producing observable behavior. Everything depends on it.
2. **One capability per later slice** — one field, one validation, one error path. If a slice title needs "and", it is two slices.
3. **Each slice changes observable behavior.** Litmus: *"If we built ONLY this slice and stopped, could a QA engineer write a test that passes?"* No → it is a horizontal layer ("build the schema", "wire the API", "add tests"), which is **banned as a slice**. Fold it into the vertical slice it serves.
4. **Acceptance criteria come verbatim from the spec** as Given/When/Then. Never invent one; never soften a quantified one into an adjective. A behavior with no spec AC is a gap to flag back to the spec, not a place to improvise — `code-design.md` supplies name, location and signature, never acceptance criteria.
5. **Slice along deep-module seams.** Prefer cuts behind a small, stable interface: it gives TDD a durable test target. Name the behavioral seam ("entry persistence", "validation gate"), never the technology.
6. **Order by dependency, skeleton first.** Keep the graph acyclic and flat. A single straight chain across every slice is a smell that you sliced horizontally.
7. **One file has one owning slice.** `slice-overlap` fails the plan otherwise, because two agents editing one file in the same build collide.

Slice-count sanity: Small ≈ 1–3, Medium ≈ 3–6, Large ≈ 6–12. Many more → too thin; many fewer → too fat.

## Step 2 — Behavior Inventory (REQUIRED, all sizes)

Enumerate every behavior before writing slices, each mapped to the slice that delivers it and the test that proves it. The header row is fixed — `plan-lint` matches it literally. Phrase the behavior as Given/When/Then with its priority; if you cannot, the requirement is underspecified, so resolve it before planning the slice.

Rules: every P0 behavior gets a test in a Red phase; behavior IDs appear in test names (`test("B1: persists a draft entry")`); every slice carries at least one error or edge behavior.

## Step 2.5 — Code design pass (conditional)

Runs after Step 1's slice list and Step 2's inventory both exist and before Step 3 writes the plan — the design gate counts consuming slices, and the header's `· design:` segment and each slice's Design trace must be fillable when Step 3 commits them to paper. The trigger, depth and mechanics are the doctrine's, not this file's: test the trigger first (step 3 of `steps/03-plan.md` states it), and only if it fires load `${CLAUDE_PLUGIN_ROOT}/skills/flow-spec/references/code-design-doctrine.md` in full. When it runs it writes `<spec_dir>/code-design.md` **and** cuts the per-slice `## Contract for this slice — Slice <N>` blocks that `slice-brief --design` later appends. The blocks are never re-cut in step 4.

## Step 3 — Write the plan

```markdown
# Flow Build Plan — <feature>  (spec: .specs/<NNN>-<slug>/spec.md · design: .specs/<NNN>-<slug>/code-design.md)

Size: <S/M/L> · Slices: <n> · Orchestration: <Subagents | Agent team | Workflow> · Base: <sha>

## Behavior Inventory
| Behavior | Slice | Verified by |
|---|---|---|
| B1 (P0): Given <precondition>, when <action>, then <observable outcome> | 1 | <test name / command> |
| B2 (P0): Given <error condition>, when <action>, then <error outcome> | 1 | <test name / command> |
| B3 (P1): Given <precondition>, when <action>, then <observable outcome> | 2 | <test name / command> |

## Slice 1 — <walking-skeleton capability>
- **Files**: <path>, <path>
- **Spec trace**: Journey 1 (happy + error), FR-3, FR-4
- **Design trace**: <sections and contract types this slice implements — DELETE this bullet if the design pass was skipped>
- **Seam**: <named behavioral seam to test at>
- **Demoable result**: <observable behavior once this slice lands>
### Slice 1 — RED
Tests + stubs only for B1, B2. TEST_CMD MUST exit non-zero.
### Slice 1 — GREEN
Implementation only. TEST_CMD MUST exit zero. No test edits.
### Slice 1 — REFACTOR
clean-code pass. No new behavior, same pass count, no public API change.
#### Automated verification
- `<TEST_CMD> <path>` exits 0
- `<LINT_CMD>` exits 0
#### Manual verification
- <a specific observable a human checks — never "does this look right?">

## Slice 2 — <next capability>
- **Files**: <path>
- **Depends-on**: Slice 1
- **Spec trace**: FR-5
- **Seam**: <named behavioral seam>
- **Demoable result**: <observable behavior once this slice lands>
### Slice 2 — RED
Tests + stubs only for B3. TEST_CMD MUST exit non-zero.
### Slice 2 — GREEN
Implementation only. TEST_CMD MUST exit zero.
### Slice 2 — REFACTOR
clean-code pass. No new behavior, same pass count.
#### Automated verification
- `<TEST_CMD> <path>` exits 0
#### Manual verification
- <specific observable>

## Discovered
- <what noticed out of plan> — discovered in Slice <N> — <defer|fold into Slice M>
## Gate Phases
### Inline Gates — `harness check --fix` (typecheck → lint → format → test)
### E2E Tests (Large UI only) — `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md` → `$E2E_CMD`
### Diff Review — lenses + anchored re-score, keep ≥80 (`flow/review.md`)
### Browser Verification (NON-SKIPPABLE) — steps below → `.claude/verification/`
### User Verification (HARD GATE) — present results, STOP for explicit approval
### QA Pass — `/qa` on the branch → `.qa-report/QA-REPORT.md`
### PR Creation — draft → re-verify all gates → ready

## Browser Verification Steps
1. <navigate / run> → Expected: <specific observable outcome>

## User Verification Steps
1. <specific criterion a human checks>
```

Delete the `· design:` header segment and every Design trace bullet when the design pass was skipped. `## Discovered` is optional and, when present, sits after the last `## Slice <N>` and before `## Gate Phases`, fence-aware — it terminates the last slice's section, so `slice-brief` must not leak it; each bullet reads `- <what noticed> — discovered in Slice <N> — <defer|fold into Slice M>`, where `defer` feeds `/wrap`'s `## Next` and `fold into Slice M` sends the item back into an existing slice; `plan-lint` checks placement and that every bullet names an existing slice. After approval (`steps/03-plan.md`), the plan file's first line becomes `Approved: <YYYY-MM-DD> by user`, or `Approved: <YYYY-MM-DD> auto (--unattended)` for an unattended auto-approval — never written before approval; the spec gate hook requires it, and `/wrap` never removes or edits it.

## Step 4 — Validate before approval

**Run `${CLAUDE_PLUGIN_ROOT}/scripts/plan-lint .claude/feature-plan.local.md` and fix until it prints `OK`**, then `${CLAUDE_PLUGIN_ROOT}/scripts/slice-overlap` until it exits 0. Both run before the plan is ever shown. Then check by eye what the linters cannot:

- [ ] Every behavior maps to a slice; at least one P0; every slice has an error/edge behavior; every slice passes the QA-engineer litmus (no horizontal slices)
- [ ] Every slice cites a spec requirement as its acceptance criteria (none invented)
- [ ] If the design pass ran: every slice touching a shared name, type, error shape, module boundary or resource has a non-empty Design trace. If it was skipped: no Design trace, no `· design:` segment
- [ ] Dependency graph is acyclic and not a single straight chain; Browser and User Verification Steps are non-empty; orchestration mode and base sha are in the header

The plan is the contract — silent scope drift is the top cause of wasted build work. Mirror each slice's sub-phases into `## Progress` in `.claude/workflow-state.local.md`, marking each `[x]` with its commit hash as it lands; that is what step 0's resume check reads.
