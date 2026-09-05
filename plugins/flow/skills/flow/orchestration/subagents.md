# Mode A — Subagents (default)

Use the **Agent** tool; parallelize within a phase, serialize across phases. Pin `model` on every call — never let a worker inherit the session model.

| Phase | Fan-out | Model |
|---|---|---|
| Codebase research (step 1) | up to 3 read-only explorers in ONE message | `haiku` |
| TDD build (step 4) | **one subagent owns one slice**; every ready slice launches together | `sonnet` |
| Green sub-tasks inside a slice | a wave of **≤ 4** background agents | `sonnet` |
| Slice review (step 4) / diff review (step 5) | one agent per lens, all launched in one message | `sonnet` |
| Gates + review (step 5) | 5.1, 5.2 and 5.3 launched in one message | — |
| Fixer | a **separate** call from the scanner | `sonnet` |

Never exceed 4 agents per wave — beyond that, parallel-reasoning degradation produces worse output than running them in sequence.

## Wave scheduling (step 4)

Do **not** loop slice-by-slice. Keep a `done` set and repeat until no slice is left:

1. Run `${CLAUDE_PLUGIN_ROOT}/scripts/slice-overlap` once, before the first wave — an overlap here means the plan, not the schedule, is wrong.
2. `ready` = every pending slice whose `Depends-on` slices are all in `done` **and** whose `- **Files**:` paths overlap no slice still running.
3. Launch every `ready` slice's subagent in ONE message with `run_in_background: true`, **≤ 4 at a time**; log the wave's slice ids.
4. Wait for the whole wave to report before computing the next one. A slice's own review lenses and fix ladder run inside its wave and never block another slice.

Three mutually independent slices are one wave. Building them in three turns is the failure this section exists to prevent.

## Per-slice build call

The brief is the contract. `slice-brief` has already cut the slice section and appended its `## Contract for this slice` block when a design exists, so the prompt names a path instead of pasting a plan — and **never** pastes `code-design-doctrine.md` or `pattern-forces.md`, which are designer-only. Naming the pattern behind a design decision moves output further from a correct implementation, not closer.

```
Agent(subagent_type: general-purpose, model: sonnet, run_in_background: true,
      description: "Build slice 2: persist title",
      prompt: "Read ${CLAUDE_PLUGIN_ROOT}/skills/feature/execution-prompt.md and follow SECTIONS
               2-4 ONLY. Read .claude/slices/2-brief.md — it is the whole
               assignment; read only the files it names. Execute the Red -> Green
               -> Refactor triplet for slice 2 ONLY, then STOP and report: do not
               run its section 5 completion check and do not run its section 6
               cleanup. Return: red_exit_code, green_exit_code, commits, files,
               notes. Do NOT touch any other slice's files.")
```

Scope the prompt to §2–§4 in every mode. Handed the whole file unscoped, an agent finishing the last pending slice can read §1's "all phases checked → go to §5", walk into the completion check and then §6, and delete `.claude/workflow-state.local.md` and `.claude/feature-plan.local.md` — which the remaining slices and steps 5–6 still read. Completion and cleanup are the orchestrator's alone.

One such call per ready slice, all of them in the same message. **As each reports, the orchestrator independently runs `TEST_CMD`** and confirms the Red and Green exit codes before accepting that slice. An agent's self-report is a claim; the exit code you observed is the gate.

## Per-slice review call

```
Agent(subagent_type: general-purpose, model: sonnet,
      description: "Review slice 2 — correctness lens",
      prompt: "Read ${CLAUDE_PLUGIN_ROOT}/skills/flow/review.md and apply its CORRECTNESS lens
               to the diff at .claude/review/slice-2.diff against the brief at
               .claude/slices/2-brief.md. Re-open the diff yourself. Return the
               finding shape from review.md, with a receipt for every finding.")
```

Exactly two lenses per slice in step 4 — **`correctness` and `gaming`**, the pair `build-slices` is pinned to — and all four (adding `security` and `cross-file`) in step 5. The pair is fixed, not chosen per run; the second call above is the same prompt with `GAMING` substituted for `CORRECTNESS`, launched in the same parallel wave. The implementer never reviews its own slice, and the scorer that re-scores a finding is never the agent that raised it — scanner ≠ fixer ≠ verifier.

## Gates

The orchestrator runs `flow check`, the browser steps and the user gate inline. At step 5 the inline gates, the E2E step (when it applies) and the diff-review lenses go out in **one** message and are waited on together; browser verification and the user gate follow, in that order. Commit after every sub-phase; update `.claude/workflow-state.local.md` after every sub-phase.
