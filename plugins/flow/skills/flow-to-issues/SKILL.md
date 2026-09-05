---
name: flow-to-issues
description: Turn a forged spec into a dependency-ordered set of tracer-bullet vertical-slice issues, each tagged AFK (agent can ship it solo) or HITL (needs a human decision). Use WHENEVER the user says /flow-to-issues, /spec-to-issues (legacy alias), "break this spec into issues", "slice this spec", "turn the spec/PRD into tickets", "create issues from the spec", "what should I build first", or after flow-spec produces a spec and the next step is planning the build. This is STEP 2 of the build flow (flow-spec → flow-to-issues → flow-feature) — it produces the issue plan; the flow-feature skill then implements each issue. Writes issues as local markdown and OPTIONALLY creates real GitHub issues with `gh`. Slices VERTICALLY (each issue cuts the full stack end-to-end), never horizontally (no "build the schema / build the API / build the UI" layer tickets). Triggers also on - slice the spec, tracer bullet, vertical slices, AFK issues, plan the build, spec to tickets, break down the PRD.
---

# Spec → Issues

Convert a buildability-contract spec into the smallest set of **independently shippable, vertically-sliced** issues, ordered so an agent (or human) can build them one at a time and keep a demoable system the whole way.

This is the bridge between `flow-spec` (which produced the spec) and `flow-feature` (which implements each issue). It does NOT write code. It produces a plan and, with approval, the issues.

```
flow-spec ──► .specs/NNN/spec.md ──► [flow-to-issues] ──► issues + gh ──► flow-feature (per issue)
```

---

## The One Idea: Tracer-Bullet Vertical Slices

A **tracer bullet** is the thinnest possible cut through *every layer* that produces observable end-to-end behavior. The system stays alive and demoable after every slice; each slice makes it one capability richer.

**Vertical (do this):**
- "User can create the simplest possible record and see it persist"
- "User can edit one field and see it saved"
- "User submits an empty form and sees a validation error"

**Horizontal (NEVER do this):**
- "Create the database schema" · "Build the API endpoints" · "Wire up the UI" · "Add tests"

Horizontal tickets create handoff hell and can't be demoed alone. The litmus test for **every** issue you propose:

> *"If we merged ONLY this issue and stopped, could a QA engineer write a test that passes?"*

If no → it is a layer, not a slice. Re-slice it. See the horizontal-masquerade detector in spec-judge's Issue-Breakdown Mode — the same detector grades your output, so apply it before you ship the plan.

---

## AFK vs HITL — tag every issue

| Tag | Meaning | Assign when |
|---|---|---|
| **AFK** | Agent-friendly — an agent can implement it solo, no human checkpoint | Requirements fully specified, acceptance criteria deterministic, no new product/UX/architecture decision required |
| **HITL** | Human-in-the-loop — needs a human checkpoint | The issue hides an unmade decision: visual/UX design, an architectural fork, external credentials/policy, an irreversible/destructive action, or an unresolved `[NEEDS CLARIFICATION]` |

Maximize AFK — that is the point. But NEVER mark an issue AFK to inflate the count: if it needs judgment, it is HITL, and you must name the *specific* decision the human must make. A plan where everything is AFK is lying; a plan where everything is HITL is useless.

---

## Phase 1 — Resolve the spec

1. If the user passed a path, use it. Otherwise default to the **highest-numbered** `.specs/<NNN>-*/spec.md` in the repo (the freshest flow-spec output). If `specs/` or `.specify/` is the project convention, use that instead.
2. If no spec is found: tell the user *"No spec found in `.specs/`. Run flow-spec first, or pass a spec path."* and stop.
3. Read the **entire** spec. Note the size tier (Small/Medium/Large) stated in it — it sets your slice count expectation: Small ≈ 2–4 slices, Medium ≈ 4–8, Large ≈ 8–15. More than that for the tier means the slices are too thin; fewer means they are too fat.
4. Extract the raw material for slicing: the user **journeys** (flow-spec enforces happy/error/edge paths — these are your natural slices), the measurable **requirements**, and any `[NEEDS CLARIFICATION]` markers (each one forces HITL on the issues it touches).

## Phase 2 — Slice vertically

Walk the journeys, not the architecture. For each end-to-end capability, draft one issue:

- **Start with the walking skeleton**: the very first slice should be the thinnest possible end-to-end path (create-the-simplest-thing). Everything else depends on it.
- **One capability per slice**: add one field, one validation, one error path per subsequent issue. If an issue's title needs an "and", it is probably two slices.
- **Each slice must change observable behavior.** If you can't write its acceptance criteria as Given/When/Then on observable output, it is horizontal — merge it into the slice it actually serves.
- Pull acceptance criteria **verbatim from the spec's measurable requirements** — do not invent new ones, and do not soften quantified ones into adjectives.
- **Slice along deep-module seams.** Prefer cuts where the slice sits behind a small, stable interface that hides complexity. A slice with a clean seam gives the downstream `flow-feature` TDD step a *durable test target* — the test won't churn as internals change. This is an issue-ordering hint, NOT a place to specify implementation: name the behavioral seam ("entry persistence", "validation gate"), never the technology behind it.

Then for each draft issue assign: **AFK/HITL** (+ the blocking decision if HITL), and **`depends-on`** (other slice IDs). Keep the dependency graph acyclic and as flat as possible — a single straight line of dependencies is a smell that you sliced horizontally.

**Revalidate `code-design.md` against these real slices, if one exists.** flow-spec's design pass has no build plan yet, so it counts each structure's consuming slices against a provisional list derived from the spec's journeys and marks every count provisional — the slice list you just drafted is the real one, and this is the first point it exists.

If `<SPEC-DIR>/code-design.md` is present, re-run its Decisions-section counts against this real list. Any structure whose consuming-slice count now falls below 2 is a local implementation detail, not cross-slice structure — drop it from `code-design.md` and let the one slice that needs it specify it inline instead.

Record what you dropped (structure name + which slice absorbed it) so the provisional-to-real handoff stays honest rather than silent.

Then, still gated on `<SPEC-DIR>/code-design.md` being present: now that the real slice list exists, cut one `## Contract for this slice` block per surviving slice, replacing whatever flow-spec's design pass cut against its provisional list. The block's shape and field-by-field meaning are defined in `code-design-doctrine.md`'s per-slice contract block — load it there and follow it exactly; do not restate its shape here.

## Phase 3 — Self-check against the anti-patterns (before judging)

Apply these structurally — fix in place, don't just note:

| Anti-pattern | Defense |
|---|---|
| Horizontal masquerade | Run the litmus test on every issue; re-slice any that fail |
| Acceptance-criteria fog | Every issue cites a quantified requirement from the spec |
| Orphan dependency | Every `depends-on` resolves to a real issue ID |
| Mega-issue | Any issue with >~7 acceptance criteria → split it |
| Coverage gap | Every spec journey/requirement maps to ≥1 issue |
| AFK inflation | Every AFK issue genuinely needs zero human decisions |

## Phase 4 — Validate with spec-judge (capped at 2 sessions)

Write the draft plan to `<SPEC-DIR>/plan.md` (format below), then have spec-judge grade it in **issue-breakdown mode**.

**If spec-judge is not installed** at `${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md`: tell the user it's skipped and proceed straight to the approval gate with your self-check only. Do not self-score.

**Spawn a Task agent** (`subagent_type: general-purpose`, `model: sonnet`, `mode: bypassPermissions`). Substitute `<ABSOLUTE-PLAN-PATH>`, `<SPEC-DIR>`, `<N>` (iteration, 1 or 2):

```
You are evaluating an issue breakdown for build-readiness.

FIRST: Read the spec-judge skill at:
${CLAUDE_PLUGIN_ROOT}/skills/spec-judge/SKILL.md

THEN evaluate the breakdown at:
<ABSOLUTE-PLAN-PATH>

MODE: issue-breakdown

Follow spec-judge's Issue-Breakdown Mode rubric EXACTLY. Apply the
horizontal-masquerade detector to every issue and NAME every horizontal
issue verbatim. Score all 5 dimensions out of 100 with quoted evidence.

Write the report to:
<SPEC-DIR>/issue-plan-judge-iteration-<N>.md

Be ruthless. Top 3 Improvements must be specific and actionable.
Do NOT mention any prior iteration's score — score cold.
```

**Refinement loop — HARD CAP 2 iterations.** Parse the report. Loop until ONE of:

| Condition | Action |
|---|---|
| Score ≥ 85/100 AND D-Slice not capped | **Ship it** — go to the gate. |
| 2 iterations completed | **Hard cap.** Go to the gate with caveats stated. |
| Score delta < 5 between the two | **Diminishing returns.** Go to the gate. |

When refining, fix the **named horizontal issues first** — D-Slice is worth 35 and caps the total at 50 if any slice is horizontal. Re-slice them vertically, don't just reword titles.

## Phase 5 — Approval gate (HARD)

Nothing is created until the user approves. Show a single table:

```
#  Issue title                                   Tag    depends-on   Notes
01 User can create a draft entry end-to-end      AFK    —            walking skeleton
02 User can add a title and see it persist       AFK    01
03 Choose the dashboard layout                    HITL   01           decision: visual design
...
Judge: 88/100 (D-Slice 31/35, no horizontal slices)  •  N AFK / M HITL
```

Then ask exactly: *"Create these as local markdown only, or also open GitHub issues with `gh`? Reply 'local', 'github', or edits."* Wait. Do not proceed on silence.

## Phase 6 — Emit

**Always** write local markdown: one file per issue at `<SPEC-DIR>/issues/<NN>-<slug>.md` using the issue template in `references/issue-template.md` (read it once). Each file links back to the spec and its source journey/requirements. If `<SPEC-DIR>/code-design.md` is present, also carry the issue's Design trace: its slice's `## Contract for this slice` block, or at minimum the code-design.md sections and contract types the issue implements — the template's `## Design trace` field. If code-design.md is absent, omit that field entirely (see the template).

**If the user chose GitHub** (`gh` available + inside a repo): create issues in **dependency order** (topological — a depended-on issue exists before its dependents) so `depends-on` can reference real issue numbers:
```
gh issue create --title "<title>" --body-file <path> --label afk   # or hitl
```
Capture each returned URL and write it back into `<SPEC-DIR>/issues.md` (an index table: # · title · tag · depends-on · URL). If `gh` is missing or not authed, fall back to local-only and tell the user the exact `gh` commands to run later.

## Phase 7 — Hand off to `feature`

This skill stops at the plan. Each issue should be built in its OWN fresh session — implementing the whole list in one context bloats it past the smart zone and the agent goes dumb by issue #4. So bridge each issue with `flow-handoff`.

**ALWAYS end with the next step (so the user doesn't have to remember the flow):**

> *"Plan is ready (N AFK, M HITL). **Next in the flow:** build one issue at a time, each in a fresh session. Mr Claude can run **`/flow-handoff`** to write a per-issue bridge, then **`/flow-feature`** implements it via TDD. Start with #01 (the walking skeleton)? AFK issues run unattended; HITL issues need your decision first. (Flow: `flow-spec → flow-to-issues → flow-handoff → flow-feature`.)"*

When the user agrees: for each **AFK** issue in dependency order, run `/flow-handoff` (purpose = implement this issue; references = spec + issue file + the deep-module seam; skill-to-run = `/flow-feature`), then implement it in a fresh session via `flow-feature`. Pause before each **HITL** issue and surface its blocking decision to the user first. Do not auto-run the whole list without the user's go-ahead.

---

## plan.md format

```markdown
# Build Plan — <feature> (from .specs/<NNN>-<slug>/spec.md · design: .specs/<NNN>-<slug>/code-design.md — DELETE the "· design: …" segment if code-design.md does not exist)

Size tier: <Small|Medium|Large> · Slices: <count> · <N> AFK / <M> HITL

## Issues
### 01 — <user-capability title>
- **Tag**: AFK
- **depends-on**: —
- **Spec trace**: Journey 1 (happy path), FR-3, FR-4
- **Design trace**: <the code-design.md sections and contract types this slice implements> — DELETE this bullet entirely if code-design.md does not exist
- **Acceptance criteria** (from spec):
  - Given … When … Then …
- **Demoable result**: <the observable behavior after this merges>

### 02 — <title>
- **Tag**: HITL — decision: <the specific unmade decision>
- ...
```

---

## NEVER

- **NEVER emit a horizontal slice.** "Build the API", "create the schema", "add tests" are layers. If it can't be demoed alone, it isn't an issue here. This is the #1 failure and spec-judge will cap your score for it.
- **NEVER invent acceptance criteria.** Pull them from the spec. If the spec lacks them, that's a `[NEEDS CLARIFICATION]` → HITL, not a place to improvise.
- **NEVER mark an issue AFK to look productive.** Judgment required → HITL with the decision named.
- **NEVER create GitHub issues before the approval gate.** Local markdown is always safe; `gh issue create` is outward-facing and irreversible-ish — it needs explicit consent.
- **NEVER exceed 2 spec-judge iterations.** Past that, ship with caveats; refinement churn isn't worth the tokens.
- **NEVER reimplement TDD here.** Implementation is the `flow-feature` skill's job. This skill plans; it does not code.
