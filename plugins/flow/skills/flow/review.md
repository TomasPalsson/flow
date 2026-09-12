---
name: flow-review
description: How flow reviews a slice diff and a whole-branch diff — the five adversary lenses with their self-commit protocol, severity buckets and verdict enum, the anchored 0–100 confidence re-score with the ≥80 keep rule, the bounded fix ladder, carried verdicts, and the stall rule. Loaded in steps 4 and 5.
---

# Flow Review

One protocol, two callers: step 4 reviews a single slice's diff, step 5 reviews the whole branch. The saved `review-diff` workflow implements this exactly; every other mode runs it inline. **The implementer never reviews its own work** — scanner ≠ fixer ≠ verifier is the whole point of this file.

## Lenses

Each reviewer gets the brief path and the diff path, and nothing else. It must **re-open the diff itself** — a finding built from another agent's summary is a rumor.

| Lens | Asks |
|---|---|
| **correctness** | Does this do what the brief says, on the error and edge paths too? Off-by-one, unhandled rejection, wrong default, lost await, broken invariant. |
| **gaming** | Was the gate satisfied rather than the problem? Skipped/xfail'd/deleted tests, assertions weakened to `toBeDefined()`, a threshold lowered, a stub left in the Green commit, behavior special-cased to the test's input. |
| **security** | Untrusted input reaching a sink, authz checked in the wrong layer, a secret in the diff, an injection or traversal path. |
| **cross-file** | Does this agree with the rest of the branch? Duplicated concept under a second name, a contract from `code-design.md` drifted, two slices owning one file. |
| **slop** | Is this generic, duplicated, or plausible-looking but unproven? See `skills/no-slop/references/adversary-lens.md` for the checklist and evidence rule. |

**Which lenses run where is fixed, never a per-run choice**: step 4 runs exactly **correctness + gaming + slop** on each slice diff — the trio the saved `build-slices` workflow is pinned to, so every mode reviews a slice identically. Step 5 runs **all five** on the branch diff, matching `review-diff`'s defaults. A slice-level security or cross-file worry is not dropped, it is caught at step 5 where the whole branch is visible.

**Self-commit protocol**: each reviewer states, before reporting, what it checked and what it deliberately did **not** check and why. A lens with no findings returns `verdict: CLEAN` and its `checked` list — **empty is a legitimate result**, and a reviewer that reads silence as failure manufactures the difference.

## Finding shape and severity

Every finding: `{ predicate, severity, file, line, scenario, receipt }` — `scenario` is concrete inputs → wrong output; `receipt` is the `file:line` that proves it. A finding with no receipt is an opinion and is dropped before scoring.

- **fatal** — wrong behavior, data loss, security. Blocks the slice.
- **significant** — a correctness risk or a missing test for a P0 behavior. Blocks the slice.
- **minor** — style or preference. Recorded, never blocking; at most 3 per review.

Reviewer `verdict` is one of `CLEAN` / `FINDINGS` / `BLOCKED` (could not read the diff).

## Confidence re-score (independent, anchored)

Every unique finding — deduped by `file + line + first 40 chars of predicate` — goes to a **different** agent than the one that raised it, with only the finding and the diff path. It re-opens the diff and scores 0–100 against fixed anchors:

- **0** — not a real issue. **25** — style or preference. **50** — plausible, unverified.
- **75** — verified real, low impact. **100** — verified real, correctness or security impact.

**Keep `score >= 80`; drop the rest** and report how many were dropped. The anchors are fixed text: never paraphrase them per run, or the threshold stops meaning the same thing between slices.

## Fix ladder (bounded)

Per surviving fatal or significant finding:

1. **Rounds 1–3** — the same implementer fixes it, with the finding text and its receipt. Re-run `TEST_CMD` after each round.
2. **Rounds 4–5** — a **fresh** implementer on a stronger model (`opus`), told what the first three attempts tried and why each failed.
3. **Then stop and record a ruling** in the plan's `## Progress` section: `Ruling: <finding> — parked — <why> — <cost if wrong>`. Continue to the next slice; the ruling surfaces again in the PR body.

Revert any fix that worsens the scan. Never delete, skip, or weaken a test to clear a finding — the Stop gate and the tamper notice put that on the record anyway.

**Carried verdicts**: a finding already scored and dropped is **never re-litigated** while the code it points at is unchanged. Re-score only findings whose `file:line` moved in the latest diff.

**Stall rule**: if the surviving finding count does not decrease between two consecutive fix rounds, stop laddering and escalate — the agent is churning, not converging. Say so plainly, park what remains with rulings, and let the human gate at step 5.5 decide.
