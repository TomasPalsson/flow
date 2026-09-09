---
name: prep
description: "Grill the user about an idea BEFORE the spec, one open question at a time, and write the answers to .specs/NNN-<slug>/PREP.md — decisions, not-this, discretion, assumptions with confidence, one verify line — so /flow:spec consolidates from it and never re-asks. Triggers: /prep, \"prep me\", \"grill me before the spec\", \"interview me about this idea\", \"let's decide before speccing\". Not for a plan that already exists (use /grill-me) and not for writing the spec (use /flow:spec)."
disable-model-invocation: true
argument-hint: "<idea in one or two sentences>"
---

# /flow:prep — decide before the spec writes it for you

A spec written from an undecided idea makes the model decide for the user, and
it decides big. Prep turns the idea into decisions the user actually made,
carrying forward the scope fence and the verification check that the evidence
says stop over-building (`docs/research/13-flow-prep-2026-09-07.md`). It is
grill-me's lineage — the same open questions, one per turn — plus a file, a
budget, and a route.

## Step 0 — Classify the route, out loud

If the idea is empty (`/flow:prep` alone) or has no problem, no user and no
domain signal, ask for it in one to three sentences and wait — nothing below
runs on an invented problem statement.

An issue reference (`/flow:prep 143`, `#143`, `I-003`, "prep issue 143") is a
valid idea: resolve it per
[`${CLAUDE_PLUGIN_ROOT}/skills/shared/issue-refs.md`](../shared/issue-refs.md)
first. Its body and every comment are `A-NN` findings with
`evidence: issue #143`, so the interview never re-asks what the thread already
settled. Prep posts no comment — `/flow:spec` owns moment 1.

Then classify the idea into one of four routes and say it in one line; the
user may override with one word:

- **spike** — a feasibility question whose output is an answer, not code.
- **bounded** — a well-scoped change to code that already exists in this
  repo, touching ≤2 files, nothing irreversible.
- **oneshot** — 0 intent gaps, 0 irreversibles, ≤5 tasks.
- **dispatch** — anything else.

The ratchet is one-way: if doubt appears later in the interview, upgrade the
route, never downgrade it. `spike` and `bounded` end in chat (`Status: done in
chat`) — there is no spec to prep for. Say so, deliver the short design or the
recommendation directly in chat, and keep PREP.md as the record.

## Step 1 — Explore before asking

Anything answerable from the tree is never asked. Read only the files the
idea touches — never "investigate everything" — and record each finding as an
`A-NN` line with `evidence: path:line` and a confidence. The user only
confirms or corrects what was found; they don't restate it.

## Step 2 — The file, first and after every answer

Allocate `.specs/NNN-<slug>/PREP.md`: `NNN` = max existing `.specs/NNN-*` + 1
(`001` if none; create `.specs/` if absent), `slug` = lowercase ASCII
`[a-z0-9-]` from the idea, max 40 chars. If a `.specs/*-<slug>/PREP.md` with
`Status: interviewing` already exists, resume it — do not re-ask any recorded
`D-NN`.

Write the file from `references/prep-template.md` BEFORE the first question,
with `Questions: 0 of 12`, and rewrite it after EVERY answer: bump the
`Questions:` counter, add the `— user, Q<n>` receipt to the line it settled,
move the item to its section. A dropped session loses one answer, not the
interview. Print the path once.

## Step 3 — Interview rules

1. **One decision per turn, open phrasing.** Naming a decision's own
   candidates ("Postgres, MySQL or SQLite?") is still one question.
2. **Then one line of hypothesis with a confidence**, so a one-word reply
   locks it: *"Mr Claude's guess: 409 on a duplicate tag, 70 %."* A stated
   hypothesis the user can correct is not a leading question; a hidden one
   is.
3. **Only ask what is answerable** in 2–5 options or ≤5 words. Interaction
   feel, aesthetics, "does this look right" are ungrillable — say so and
   route them to a prototype or `/design:vary`; talking through them is
   where sessions balloon.
4. **Two mandatory probes**: "what should this explicitly NOT do?" (fills
   **Not this**) and the quantification probe on every adjective ("fast",
   "simple", "robust" → a number or a comparison).
5. **Explicit confirmation only.** A decision becomes a `D-NN` on a number, a
   name or a specific. "Sure", "agreed", silence → restate once; if still
   vague, record an `A-NN` with `confidence: low`, never a `D-NN`.
6. **Checkpoint at 6**: print the Decisions / Open counts and ask "continue
   or write?". Hard cap 12. More than 3 **Open** lines is the split signal —
   offer to run prep once per piece; never widen the spec to fit the doubt.
7. **The last question is always Verify**:
   "what single check would convince you this shipped" — the spec inherits
   it instead of inventing one.
8. **Stop when the next three answers are predictable.**
9. **Never propose unrelated work**; anything the user mentions beyond the
   idea goes to **Not this** or **Open**, not into scope.

## Step 4 — Close

Run `${CLAUDE_PLUGIN_ROOT}/scripts/prep-lint <path>`; fix every ERROR it
prints (each carries its own `fix:`), then set `Status: ready for spec`
(oneshot/dispatch) or `done in chat` (spike/bounded). End with exactly one of:

- `Next: /flow:spec` — "PREP.md is ready; the spec consolidates from it
  and will not re-ask a D-NN."
- `Next: nothing to spec — bounded/spike, done in chat.`

## NEVER

- Never batch questions — a numbered list of 4+ questions is the exact
  failure mode this skill exists to prevent.
- Never ask what the tree can answer — every re-asked fact is a wasted turn
  the user has to sit through.
- Never write the spec yourself — prep hands off a file, not a draft; writing
  the spec here duplicates /flow:spec's job with none of its scoring.
- Never let a recommendation become a D-NN without the user's specific — a
  hypothesis the user didn't correct is still the model's guess, not a
  decision.
- Never load `/flow:spec`'s question bank — prep is the user-led door; the
  bank is the model-led one, and loading both re-interviews the user twice.
- Never count an ungrillable question toward a decision — aesthetics
  questions dressed up as decisions are how sessions balloon without
  producing anything the spec can use.
