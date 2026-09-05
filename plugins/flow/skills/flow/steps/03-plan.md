# Step 3 — Build plan (this REPLACES issue slicing)

Decompose the spec into an **internal, ordered, vertical-slice build plan** the pipeline builds straight through. No `gh issue create`, no AFK/HITL labels, no per-issue files.

**MANDATORY — READ ENTIRE FILE**: [`../planning.md`](../planning.md) — decomposition rules, the Behavior Inventory, the plan template in the grammar `plan-lint` enforces, and the gate phases block.

1. **Slice vertically, never horizontally.** Litmus on every slice: *"If we built only this and stopped, could a QA engineer write a passing test?"* No → it is a layer; re-slice. "Build the schema" / "wire the API" / "add tests" are banned as slices.
2. **Walking skeleton first**, then one capability per slice. If a slice title needs "and", split it.
3. **Pull acceptance criteria verbatim** from the spec's measurable requirements as Given/When/Then — never invented, never softened — sorting each into the Behavior Inventory (P0/P1) as you go.
4. **Order by dependency.** A single straight chain across all slices is a smell that you sliced horizontally; prefer a flat graph.
5. **Code design pass — trigger test first.** It is **required** when **two or more slices share a name, id type, error shape, module boundary, or shared resource** — the trigger is cross-agent surface, never file count and never the size tier — and **skipped entirely** otherwise, including on every one-slice build. If it does not fire, go to step 6 and do not load the doctrine. If it fires: **MANDATORY (conditional) — READ ENTIRE FILE**: `${CLAUDE_PLUGIN_ROOT}/skills/flow-spec/references/code-design-doctrine.md` and, in the same pass, `${CLAUDE_PLUGIN_ROOT}/skills/flow-spec/references/pattern-forces.md`. Read them once, here; never in step 4, and never pasted into a slice prompt — and where the doctrine says `flow/orchestration.md` pastes the cut block into the subagent prompt at RED, that is v1: in v2 nothing is pasted, `slice-brief --design` appends the block to `.claude/slices/<N>-brief.md` and the subagent reads that file. Write `<spec_dir>/code-design.md` beside `spec.md` (Medium: sections 1–7; Large: 1–11) and, in the same pass, cut the per-slice `## Contract for this slice — Slice <N>` blocks — `${CLAUDE_PLUGIN_ROOT}/scripts/slice-brief --design` appends them from that file, so they must exist before step 4. Then run the **adversary lens** by a DIFFERENT agent than the design's author, over the design doc, contract file, cut contract blocks and slice descriptions. It emits numbers against thresholds, never "improve the architecture"; it does not re-open step 2.
6. **Write** `.claude/feature-plan.local.md` in `planning.md`'s grammar, carrying `code-design.md`'s path in the header and a Design trace per slice when step 5 produced one.

## Validate before the plan is ever shown

Run both from the repo root, in the same turn — two Bash calls in one message, never chained:

- `${CLAUDE_PLUGIN_ROOT}/scripts/plan-lint .claude/feature-plan.local.md` → must print `OK`.
- `${CLAUDE_PLUGIN_ROOT}/scripts/slice-overlap .claude/feature-plan.local.md` → must exit 0 with no output.

**Refuse to present a plan that fails either.** A grammar failure means step 4's `slice-brief` will hand an agent the wrong section; an overlap means two slices own one file and will collide. Fix and re-run until both are clean, then walk `planning.md`'s checklist.

## UI direction

If the feature has UI and the user has not given a design direction, invoke `showcase` first and stop for them to pick one — it becomes the build's design anchor, and browser verification checks against it. Skip for backend, CLI and config work. Under `--unattended`, showcase still runs but flow takes the recommended direction and records it as an Assumption.

## Plan approval — HARD GATE

Present the full plan — slices, Behavior Inventory, verification steps, gates, orchestration mode — together with `code-design.md` when step 5 produced one. `code-design.md` is approved **with** the plan: no new stop is added and the gate manifest still says two stops.

**Preferred rendering**: if `command -v better-plan` succeeds, write the plan as MDX (`<PlanHeader>` + a `##` section per slice, `<Steps>`, `<Comparison>`, `<Diagram>` for the slice graph, `<Checklist>` for the gates — see the `better-plan` skill), run `better-plan ./.claude/plan.mdx`, and gate on the in-UI decision: poll `GET /__bp/status` (or `--wait-approval`), proceed only on `approved`, revise and re-render on `changes-requested`. If it is not on PATH, present the plan inline.

**Do NOT start building until the user explicitly approves** — the Approve button, or "looks good" / "go" / "approved". Ambiguity is not approval; ask once more.

**On explicit approval, and never before**, add `Approved: <YYYY-MM-DD> by user` as the first line of `.claude/feature-plan.local.md` — the spec gate hook denies source edits until this line is present and `plan-lint` passes.

Under `--unattended` the plan is still written, validated and rendered, the batched offer still goes out, and the plan is auto-approved when it expires — for that auto-approval, add `Approved: <YYYY-MM-DD> auto (--unattended)` instead, never the plain `by user` form; with `better-plan`, render but do NOT poll and do NOT pass `--wait-approval`.

Then read [`04-build.md`](04-build.md).

End the step with the line `Next: …` from `flow next`.
