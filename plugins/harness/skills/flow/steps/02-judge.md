# Step 2 — Harsh judge (opt-in, exactly once, NO loop)

**This step is opt-in.** It runs only when the invocation carries `--judge` (or the user asks for a spec review by name). Default runs skip it and **say so in one line** — a silent skip reads as a pass that never happened.

Harsh means a low threshold: surface every plausible weakness, prefer false positives over silence. **One pass, then the user decides.** Re-judging is exactly the fatigue this pipeline removes.

**If `${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md` is absent**: say so, skip scoring, proceed. Do NOT self-score — that defeats the independent judge.

Run it through the chosen orchestration mode as a single agent (or a single stage). Substitute `<ABSOLUTE-SPEC-PATH>`, `<TIER>`, `<SPEC-DIR>`:

```
You are evaluating a spec for quality. Be MAXIMALLY HARSH — this is a single
pass with no refinement loop, so it is far better to over-report than to miss
anything. Surface every weakness you can find even at low confidence; flag
false-positives rather than stay silent. Mark each as SHIP-BLOCKER / SHOULD-FIX / NIT.

FIRST read the spec-judge skill at: ${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md
THEN read and evaluate the spec at: <ABSOLUTE-SPEC-PATH>

Follow the spec-judge protocol EXACTLY: buildability scan (B/D/U per requirement),
structure analysis, score all 8 dimensions out of 120 with quoted evidence,
total + grade. Apply <TIER> calibration. Write the report to:
<SPEC-DIR>/spec-judge-harsh.md

Top 3 Improvements must be specific and actionable. Score this spec cold.
```

## Decide, then move on

Parse the report. Present **score/120 + grade**, the **SHIP-BLOCKER list**, and the **top 3 improvements**. Then make the call for the user — always recommend:

> *"Harsh judge: 78/120 (B−). 2 ship-blockers, 5 should-fix, 9 nits. Mr Claude recommends fixing only the **2 ship-blockers** now (surgical edits) and carrying the rest as named assumptions in the spec — refining all 16 is not worth a second discovery round. Fix the blockers and proceed, or stop to address more?"*

Apply only the fixes the user agrees to, **surgically** — the smallest scope per cited piece of evidence, never a wholesale rewrite. Do **not** re-run the judge. Record every unaddressed should-fix and nit as `Assumption (confidence: Low)` in the spec so the builder sees them.

Under `--unattended`, flow applies its own recommendation without asking — ship-blockers only, surgically — and records the rest as `Assumption (confidence: Low)`.

Then read [`03-plan.md`](03-plan.md).

End the step with the line `Next: …` from `harness next`.
