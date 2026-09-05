# Step 1 — Spec (adaptive discovery)

Produce a **buildability contract** before any code: a spec a builder with no access to the author could implement and a QA engineer could test from. Depth scales to the size tier.

## Discovery rules (non-negotiable at every size)

Run discovery **serially** — one question per turn, Anchor → Boundaries → Depth order.

1. **Always recommend an answer with visible reasoning**, then "confirm or correct?" — never a bare question.
2. **Quantify every adjective.** "fast" / "secure" / "scalable" become a number with a unit and a measurement point.
3. **Always ask the negative-scope question**: "what should this explicitly NOT do?"
4. **Medium/Large only**: always ask "who maintains this after launch, and what do they know?" The answer changes the architecture and is structurally orphaned in every other tool.

`${CLAUDE_PLUGIN_ROOT}/skills/flow-spec/references/question-bank.md` holds the 8-category taxonomy, the quantification probes and the "I don't know" fallback — **consult it when a line of questioning stalls**, not as a preamble.

**Consolidate-mode**: when rich context already exists (a long design conversation this session, or an explored codebase), do not re-interview — synthesize draft answers, show a "here's what I already know" summary, and ask only the genuine gaps. Rules 2 and 3 still fire. `--unattended` forces consolidate-mode regardless of context depth: synthesize, make the single batched offer, then proceed on recommendations; rules 2 and 3 are answered by flow's own recommendation and recorded as `Assumption (confidence: <level>)`.

Stop asking when the next answer would not change what you build or test (convergence, not budget exhaustion), at the hard cap (S: 4, M: 7, L: 10), or when the user says "just write it."

## Codebase research is the first fan-out

The discovery dialogue stays in the main loop — the orchestrator asks. Codebase research does not: **launch these in one message, in parallel** — up to 3 read-only `haiku` explorers through the chosen mode, each carrying a distinct question (existing patterns, conventions, reusable code), **never sequentially**. Their receipts ground every recommendation in what is already there; asking one reader at a time buys nothing but wall clock, and a model reading this step on its own will serialise them unless it launches them together.

## Write the spec

**MANDATORY — READ ENTIRE FILE (the only mandatory read in this step)**: `${CLAUDE_PLUGIN_ROOT}/skills/flow-spec/references/spec-template.md`.

Write the spec to `<spec_dir>/spec.md`, where `spec_dir` comes from `.claude/flow.json` (step 0.5 already created it — do not recompute a number). Tell the user the path before writing. Fill every placeholder the size variant includes. Cap unresolved `[NEEDS CLARIFICATION]` markers at 3; anything above that is a discovery gap, not a drafting gap.

Record every auto-resolved or inferred answer as `Assumption (confidence: <level>)` so the builder — and the PR reader — sees what was decided without the user.

## Next

- Run carries `--judge` → read [`02-judge.md`](02-judge.md).
- Otherwise → say in one line *"Skipping the harsh judge (not requested; pass `--judge` to run it)"* and read [`03-plan.md`](03-plan.md).

End the step with the line `Next: …` from `flow next`.
