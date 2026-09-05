# Mode C — Workflow (ultracode)

Call the **saved workflows** `build-slices` and `review-diff` by name. There is no inline script to write and no API to re-derive: `build-slices` and `review-diff` already encode this pipeline's fan-out, and an ad-hoc script drifts from them silently.

**In the workflow** (autonomous): per-slice TDD build, the diff packaging, the review lenses, the anchored re-score, the bounded fix ladder.
**Out of it** (main loop, before and after): spec discovery, plan approval, browser verification, **user verification**, `gh pr ready`.

## Step 4 — build

```
Workflow({ name: 'flow:build-slices', args: {
  plan: '.claude/feature-plan.local.md',
  design: '<spec_dir>/code-design.md',   // omit when the design pass was skipped
  base: '<base sha>',
  slices: [1, 2, 3],                     // every slice id; order is not load-bearing
  testCmd: '<TEST_CMD>'
} })
```

`deps` and `files` MAY be omitted: `build-slices` computes them itself in stage 0 (one `haiku` agent reads `plan` and returns `{ deps, files }` per the `- **Depends-on**:` and `- **Files**:` lines) whenever the caller does not pass them, and logs the waves either way. Passing them yourself skips that stage 0 read. The workflow then runs **waves**: a slice starts once its dependencies are done and its files overlap nothing still running, so independent slices build concurrently. Per slice it runs `slice-brief` → a `developer` agent that reads only the brief → `review-package` → the two `adversary` lenses `correctness` and `gaming` in parallel → the fix ladder, and returns `{ slices, waves, parked, clean }`.

## Step 5 — review

```
Workflow({ name: 'flow:review-diff', args: { base: '<base sha>' } })
```

Lenses default to correctness, security, gaming and cross-file and run in parallel, as do the scorers; the keep threshold defaults to 80. Returns `{ verified, dropped, diffPath }`. Launch this call, the inline gates and the E2E step (when it applies) **together in one message** — they share no data — then browser verification, then the user gate.

## Guardrails

- **Never put a user gate inside a workflow.** There is no way to prompt the user mid-workflow — the run pauses by *returning*, not by waiting.
- **Re-verify in the main loop.** A workflow agent reporting `greenExit: 0` is a claim; run `TEST_CMD`, `LINT_CMD` and `TYPECHECK_CMD` yourself before the PR. Red exits non-zero and Green exits zero, verified by you and not an agent's word.
- **The plan is the schedule.** `build-slices` is wave-scheduled, not a pipeline, and the graph it schedules on comes from the plan's `- **Depends-on**:` and `- **Files**:` lines — whether you transcribe them into `deps`/`files` or leave stage 0 to read them, a missing `- **Depends-on**:` line in the plan is what builds a slice against a seam that does not exist yet, not a wrong `slices` order. Ship a plan that `plan-lint` and `slice-overlap` both pass, and check the logged waves match what you expected.
- **Never pass the doctrine.** Only the `## Contract for this slice` block belongs near a builder, and `slice-brief --design` appends it — `code-design-doctrine.md` and `pattern-forces.md` are designer-only, and putting either in a build prompt causes the exact pattern-name emission the design exists to prevent.
- **Record every parked ruling** the workflow returns into the plan's `## Progress` section, and surface it in the PR body. A parked finding that only ever lived in a workflow result is a finding nobody sees.
- Between the two calls the orchestrator commits nothing on the agents' behalf and skips no gate: `flow check`, browser verification and the human gates run exactly as in every other mode.
