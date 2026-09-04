# Step 5 — Gates and verification

Runs after every slice's triplet lands. **Launch 5.1 inline gates, 5.2 E2E (if applicable) and 5.3 review-diff together in one message; wait for all three; then browser verification; then the user gate.** Those three read the same tree and feed nothing to each other, so running them across three turns buys nothing but wall clock — and a model reading this step one file at a time will serialise them unless it launches them together. Inline gates, browser verification for any UI, and user verification are invariants; E2E, review breadth and the QA pass scale to the work.

**MANDATORY — READ ENTIRE FILE (the only mandatory read in this step)**: [`../review.md`](../review.md) — lenses, severities, the confidence re-score, and the fix ladder.

## 5.1 Inline gates

Run `harness check --fix` (typecheck → lint → format → test; missing gates auto-skip; it execs `check-all` with `CI=true`) as a background Bash call (`run_in_background: true`) in the same message that launches 5.2 and 5.3. Fix inline, commit, re-run until green. Cheapest gate — never skip it. **Escape hatch**: if it exits non-zero on the *same* error set twice in a row, stop and surface those errors — a formatter and a linter with conflicting rules flip-flop forever.

## 5.2 E2E tests — Large UI only

For Large features with UI, launched alongside the inline gates: **MANDATORY (conditional) — READ FIRST** `${CLAUDE_PLUGIN_ROOT}/skills/shared/e2e-testing.md`; write E2E tests for the plan's scenarios and run `$E2E_CMD`. Skip for Small/Medium and for non-UI work, and say you skipped it.

## 5.3 Diff review

Launched in the same message as 5.1 and 5.2, never after them.

**Workflow mode**: `Workflow({ name: 'harness:review-diff', args: { base: '<base sha>' } })`. It packages the diff with `review-package`, runs the lenses in parallel, and re-scores each finding 0–100 against the anchors in `review.md`, keeping only `>= 80`. It returns `{ verified, dropped, diffPath }`.

**Every other mode**: the inline equivalent — `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <base> HEAD`, then one adversary agent per lens over the diff path, then a **separate** scorer per unique finding applying the same anchors and the same ≥80 keep rule.

Either way: **scanner ≠ fixer ≠ verifier.** A fixer that saw its own finding rationalizes it, and access-control findings carry 78%+ false-positive rates, so a self-confirmed auto-fix ships a real vulnerability behind a false-clean gate. Empty is a legitimate result — a lens that finds nothing says so rather than padding. Apply `review.md`'s fix ladder to what survives; revert any fix that worsens the scan.

## 5.4 Browser verification — NON-SKIPPABLE

Starts only once 5.1–5.3 have all reported. No flag, size, or time pressure exempts it: **any feature with UI gets browser-verified.** Read `${CLAUDE_PLUGIN_ROOT}/skills/shared/claude-in-chrome-reference.md` (UI) or `${CLAUDE_PLUGIN_ROOT}/skills/shared/verification.md` (non-UI) before the first step — whichever branch applies, not both. Start the dev server with `${CLAUDE_PLUGIN_ROOT}/skills/shared/scripts/start-dev-server`, execute each Browser Verification Step from the plan, treat same-origin console errors as FAIL, capture evidence to `.claude/verification/`, then strip every `[VERIFY]` debug string. **Evidence is the deliverable** — a verification claim with no artifact in `.claude/verification/` does not count as verified, in either mode.

## 5.5 User verification — HARD GATE

This **cannot be automated, delegated to a teammate, or run inside a workflow.** It always returns to the main loop. Present results, screenshots and the plan's User Verification Steps, then ask: **"Verify using the steps above — reply 'approved' to proceed, or describe issues to fix."** STOP.

**Silence ≠ approval**; "hmm" / "maybe" ≠ approval. On rejection, fix and re-run from 5.4.

Under `--unattended` this gate is **deferred, not skipped**: capture all evidence, carry the User Verification Steps into the PR body as a checklist, and leave the PR a draft. The user's judgment still gates the ship — it moves to PR review, where the user actually is.

## 5.6 QA pass — scaled by value

Invoke the `qa` skill against the branch when the work is large or user-facing enough that an independent sweep could plausibly catch something this pipeline missed; skip it on a Small change and say so. Read `.qa-report/QA-REPORT.md`: PASS → proceed; PASS WITH NOTES → fix quick wins; FAIL → fix ship-blockers, re-run inline gates, re-run `/qa`.

Then read [`06-pr.md`](06-pr.md).

End the step with the line `Next: …` from `harness next`.
