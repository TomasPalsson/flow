---
name: flow-seed
description: >-
  How to hand a developed idea to /flow:prep as a seed PREP.md instead of a
  transcript: the yes gate, when it applies, readiness, the restatement, where the file
  goes, the eight-field mapping, the lint check, the close line.
---

# Flow seed — handing a developed idea to /flow:prep

## The yes gate — check this first, every time

Write nothing until the user's latest reply contains an explicit yes to writing it: "yes", "write it", "do it", "go ahead". "Sounds good", "sure", "ok", "agreed", "makes sense" or silence agree with the summary, not with writing a file — answer with one line, "Write it to `.specs/` for /flow:prep — yes?", and stop. Asked once already and still no yes → leave it; the idea stays in chat. The user ends the divergent stage, never the model: when BMAD's brainstorm agents lost that rule, a user wrote "I thought the agents were bullying me to wrap it up" (BMAD issue #1249), and a nodded-through summary is the model's idea, not theirs.

## When

Both, else fall back to the other hand-off bullets: `git rev-parse --is-inside-work-tree` succeeds; the idea is software to build in this repo — not an essay, a strategy, a personal decision, or another codebase.

## Readiness

State the problem and whose situation it is WITHOUT naming the solution. If nobody can name a real person with a real pain, there is no seed yet: keep developing, or offer scrutinize-idea. Never run a checklist interview to fill fields — that turns the Expand stage into a form. An unreached field is written as unknown; prep asks it.

## Restate, then ask for the yes

One short block, the eight fields in plain words, then: "Reply **yes** and Mr Claude writes this to `.specs/` for /flow:prep — or say what's off."

## Where

Allocate exactly as [prep's Step 2 — The file](../../prep/SKILL.md) does: `NNN` = max existing `.specs/NNN-*` + 1 (`001` if none), `slug` = lowercase ASCII `[a-z0-9-]`, max 40 chars; create `.specs/` if absent. A `.specs/*-<slug>/PREP.md` already there → stop and ask, never overwrite. A stealth `.specs` link is written through like a folder; add nothing else.

## What

Map the eight fields plus the user's own words onto the [PREP.md template](../../prep/references/prep-template.md):

| Field | PREP.md slot |
|---|---|
| The user's sliver, verbatim (first message) | `Seed: "<words>" — user, via /flow:develop-idea` under the Gathered header |
| Problem, stated without the solution | A-01 |
| Whose problem, as a situation ("When <situation>, <who> …") | A-02 |
| What they do today instead (the current alternative) | A-03 |
| Desired outcome / success signal | A-04 — prep's Verify hypothesis |
| Riskiest assumption (the one that, if wrong, kills it) | A-05, `confidence: low` unless evidence exists |
| Appetite (time it's worth, not an estimate) | A-06 — prep's route classifier |
| No-gos — what the user dropped at Focus, in their words | `## Not this` bullets |
| Rabbit holes / open unknowns | `## Open` as `- Q: <q> → deferred to spec`, max 3 — more than 3 is the split signal: say so, write nothing, offer one seed per piece |

A-NN grammar: `- A-NN <text> — evidence: <path:line|none> — confidence: high|medium|low — unconfirmed`. An unreached field is still written, as `<Field>: unknown — prep asks` with `confidence: low`. Header exactly: `Gathered: <YYYY-MM-DD> · Questions: 0 of 12 · Route: dispatch · Status: interviewing` — provisional; prep classifies a `Questions: 0` file fresh. `## Decisions`, `## Discretion`, `## Verify` stay empty: never a D-NN, never a guessed Verify — prep locks decisions with the user's receipt.

## Check

Run `${CLAUDE_PLUGIN_ROOT}/scripts/prep-lint <path>` and fix every ERROR it prints before handing off.

## Close

Print the path once, then end with exactly: `Next: /flow:prep — it resumes this seed, confirms these lines instead of re-asking them, and picks the route.`

## Never

- Never a D-NN — decisions are locked by prep with the user's receipt.
- Never a seed without the explicit yes — the user ends divergence, not the model.
- Never fill an unreached field with the model's own guess — write `unknown — prep asks`; Anderson et al. 2024 found ChatGPT-assisted ideas less distinct across users and less owned by them.
- Never overwrite an existing PREP.md — stop and ask instead.
