# Step 4 — TDD build (one slice, one fresh context)

Build each slice through **Red → Green → Refactor**, gated on real exit codes. This is the main fan-out and it runs through the mode chosen in step 0. Each slice executes in its **own fresh context** — a long context goes dumb by the fourth slice.

**MANDATORY — READ ENTIRE FILE (the only mandatory read in this step)**: `${CLAUDE_PLUGIN_ROOT}/skills/feature/execution-prompt.md` — the canonical TDD state machine. `flow` reuses it unchanged; do not duplicate it.

## Invariants, identical in every mode

- **Red** commits contain ONLY tests + stubs; `TEST_CMD` MUST exit non-zero.
- **Green** commits contain ONLY implementation; MUST exit zero. **Never edit a test to go green** — that is a return to Red.
- **Red exits non-zero and Green exits zero, verified by you and not an agent's word.** Re-run `TEST_CMD` in the main loop after every slice. An agent reporting an exit code it did not observe is fabrication, and it is indistinguishable from success until the PR breaks.
- **Refactor** applies `clean-code`, adds no behavior, keeps the same pass count, changes no public API surface; revert on any drop.
- One behavior's full triplet at a time. Tests assert real values, never `toBeDefined()` / `not.toThrow()`.
- When step 3's design pass ran, the slice inherits its `## Contract for this slice` block **at Red** — Red writes the stubs and signatures that fix the public API, and Refactor may not change it, so a design arriving later cannot bind.
- **Out-of-plan work an agent notices belongs in the plan's `## Discovered` section, not in the diff.** Add `- <what> — discovered in Slice <N> — <defer|fold into Slice M>` and move on; a slice agent that does the extra work instead ships scope no one approved.

## Workflow mode

One call builds every slice in waves, reviews each diff, and runs the bounded fix ladder:

```
Workflow({ name: 'harness:build-slices', args: {
  plan: '.claude/feature-plan.local.md',
  design: '<spec_dir>/code-design.md',   // omit when the design pass was skipped
  base: '<base sha from step 0.5>',
  slices: [1, 2, 3],                     // every slice id; order is not load-bearing
  testCmd: '<TEST_CMD>'
} })
```

`deps` and `files` MAY be omitted — `build-slices` computes them itself in stage 0 (one `haiku` agent reads the plan and returns `{ deps, files }` per the `- **Depends-on**:` and `- **Files**:` lines) when the caller does not pass them, and it `log()`s the waves it computed either way. Passing them yourself (transcribed from the plan) skips that stage 0 read. The workflow then schedules **waves** (a slice starts when its dependencies are done and its files overlap nothing running), briefs each slice with `slice-brief`, implements it with a `developer` agent, packages the diff with `review-package`, runs the two `adversary` lenses `correctness` and `gaming` in parallel, and applies the fix ladder — returning `{ slices, waves, parked, clean }`. **Re-run `TEST_CMD` yourself** on return, and check the logged waves match the dependency order you expected; the workflow's own report is a claim, not the gate. Record every `parked` ruling in the plan's Progress section, and any Discovered bullet the slice agents recorded instead of acting on.

## Subagent and agent-team modes

**Build in waves, never one slice at a time.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/slice-overlap --waves` first and launch the waves it prints. Launch every ready slice's subagent in ONE message with `run_in_background: true`, at most 4 at a time; do not start the next wave until the current one reports. Three independent slices are one wave, not three turns. State each wave's slice ids before launching it. In agent-team mode the same readiness rule becomes the `addBlockedBy` edges, and teammates claim every unblocked slice concurrently.

Per slice inside the wave:

1. `${CLAUDE_PLUGIN_ROOT}/scripts/slice-brief .claude/feature-plan.local.md <N> [--design <spec_dir>/code-design.md]` → prints a brief path. The agent reads **only that brief and the files it names** — never the whole plan, never the doctrine.
2. Launch **one fresh** agent (subagent, or the team task for that slice) with the brief path and `execution-prompt.md` **scoped to §2–§4** — a slice agent stops after its own REFACTOR; §5 completion and §6 cleanup are the orchestrator's, and a slice agent running them deletes state steps 5–6 still need. Every launch in the wave goes out in that one message, in parallel. Mode mechanics — wave caps, `addBlockedBy` ordering, shutdown — are in `../orchestration/subagents.md` and `../orchestration/team.md`.
3. **As each slice reports, the orchestrator re-runs `TEST_CMD`** and confirms the Red and Green exit codes before accepting that slice.
4. `${CLAUDE_PLUGIN_ROOT}/scripts/review-package <base> HEAD --out .claude/review/slice-<N>.diff` → prints the path and line count. It never prints the diff itself.
5. Launch **two adversary agents — the `correctness` and `gaming` lenses** from [`../review.md`](../review.md), never a different pair; that is the pair `build-slices` runs, so a slice gets the same review in every mode (`security` and `cross-file` run over the whole branch at step 5). **Launch both in one message, in parallel.** Each gets only the brief path and the diff path. Scanner ≠ fixer ≠ verifier: the implementer never reviews its own slice.
6. Apply `review.md`'s fix ladder to fatal and significant findings. The ladder is per slice and never blocks another slice; the wave ends when every slice in it has reported, and only then does the next wave start.

Commit after every sub-phase; update `.claude/workflow-state.local.md` after every sub-phase. When all slices are done, read [`05-verify.md`](05-verify.md).
