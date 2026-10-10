# Borrow rubric: scoring an outside skill set against flow

Written 2026-10-09 for the cursor/pstack review (`23-pstack-borrow-2026-10-09.md`). Reusable for the next outside set: the aihero (22) and ECC (spec 009) reviews asked the same questions without writing them down.

skill-judge answers one question: is this SKILL.md well made? A borrow review needs four more: is the idea worth having, do we already have it, would it survive the move into Claude Code and flow, and what does the set teach about how to work. So there are four layers. Layer A is per skill and reuses skill-judge. Layers B and D are per skill or per trick. Layer C is for the whole set.

## Layer A: craft (per skill, from skill-judge)

Score the eight skill-judge dimensions as written in `plugins/flow-extras/skills/skill-judge/SKILL.md` (D1 knowledge delta 20, D2 mindset and procedure 15, D3 anti-patterns 15, D4 description 15, D5 progressive disclosure 15, D6 freedom calibration 15, D7 pattern 10, D8 usability 15; total 120). Two adjustments for outside sets:

- D4: a description written for another host (Cursor modes, `@`-rules) is judged on whether its trigger words would still work in Claude Code, not on its own host's rules.
- Tiny principle skills (under 30 lines) are scored on D1, D3 and D6 only and reported as `/50`. The full 120 rewards scaffolding that a one-rule file should not have.

Craft tells you how much rewriting a borrow needs. It does not tell you whether to borrow.

## Layer B: idea value (per skill), 0-5 each, 35 total

| Code | Question | 0 | 5 |
|---|---|---|---|
| B1 Gap | Does flow already do this? Name the flow file that covers it, or say none. | flow covers it fully | nothing in flow comes close |
| B2 Leverage | If flow had it, how much better would a typical build, fix or review turn out? | cosmetic | changes outcomes on most runs |
| B3 Mechanism | Is the idea carried by something that runs (script, schema, gate, hook, test), or only by prose that asks the model to behave? | prose only | a check that fails loudly |
| B4 Evidence | Does it produce something a reviewer can re-run or read later (a log, a test, a report with commands)? | self-report | re-runnable artifact |
| B5 Portability | Does it survive the move to Claude Code and flow? Minus points for Cursor modes, a model panel of non-Anthropic models, MCPs we do not have, or a team process. | host-locked | drops in unchanged |
| B6 Cost | Tokens, wall clock, and how much it adds to flow's surface. Higher is cheaper. Watch the user's rule: no per-turn output noise. Feeds ranking, never SKIP. | big, always on | free or on demand |
| B7 Fit | Does the user's own work ever hit this situation? Score it from the evidence profile (their repos: CI, PR habits, reviewers and bots, stacks, team size, UI vs agents vs infra, perf work), never from what a generic team would need. | never happens in their work | happens most weeks |

B7 gates everything else. A clever idea for a situation the user never meets is still a SKIP. Write the profile fact that sets the score (for example "no repo has a review bot", "most repos have no CI") next to it.

Verdict from Layer B:

- **SKIP first if B7 <= 1.** Otherwise:
- **ADOPT** (copy close to as-is): B1 >= 4, B2 >= 3, B5 >= 4.
- **ADAPT** (take the idea, rewrite it in flow's shape): B1 >= 3 and B2 >= 3, but B5 or B3 is low, or the craft score says it needs a rewrite.
- **MERGE** (fold a piece into an existing flow skill): B1 is 2-3 and the piece that is new is small.
- **SKIP**: B1 <= 1, or B2 <= 1. A SKIP reason must be durable (fit, gap, leverage). Cost, "later" and "not now" are deferrals: score them, never skip on them. Always give the one-line reason and the flow file that already covers it.

A skill can be SKIP while one of its tricks is ADOPT (Layer D). Score the trick, not just the file.

## Layer C: ways of working (whole set), 0-5 each, 50 total

Score pstack and flow side by side on each row, with one line of evidence for each score. A row where pstack beats flow by 2 or more is a candidate change to flow.

| Code | Question |
|---|---|
| C1 Entry and routing | How does a request find the right procedure? One router, many slash commands, or the model's own guess? Can a newcomer find it? |
| C2 Composition | Are shared rules written once and pointed to by name (principles, shared references), or copied into each skill? |
| C3 Verification culture | Is "done" proven against the real artifact? Who checks: the author, a fresh agent, a different model, a script? |
| C4 Delegation and context | How is work handed to subagents? Are briefs complete? Is raw output kept out of the main thread? |
| C5 Learning loop | When something goes wrong, does the set turn it into structure (lint, test, skill edit) or into more prose? Can it mine past sessions? |
| C6 Human contact | When does it stop and ask, and when does it proceed and report? Is that rule explicit and does it match risk? |
| C7 Long runs | Can it run unattended for hours (overnight, stacks of PRs) and resume after a crash or a pause? |
| C8 Writing quality | Does it control the prose it produces: replies, PR bodies, docs, comments? |
| C9 Personalisation | Can a user make it theirs (their models, their style) without forking? |
| C10 Maintenance | Does the set police itself: tests on its own scripts, drift checks, versioning, a way to retire skills? |

## Layer D: clever-tricks log

A trick is a small, nameable move, often one paragraph, that would make a flow skill better even if the rest of its file is skipped. Record each as:

| Field | Content |
|---|---|
| Name | two to five words |
| Where | pstack path:line |
| What | one sentence |
| Why it works | the failure it prevents |
| Steal score | 0-5, using B2 x B5 / 5, rounded |
| Lands in | the flow file it would change, or "new" |

## Layer E: the whole set as a product

Three questions, answered in prose, with a verdict each:

1. **Thesis.** What is the set's one belief about how agents should build software? Is it right?
2. **Overlap.** Draw the map: which pstack pieces line up with which flow pieces, and where each side has nothing.
3. **Should flow be doing this?** For each gap where pstack has something and flow has nothing, say whether flow should fill it, and whether the right home is flow, flow-extras or tooling.

## Rules for the reviewer

- Read every file you score in full. Quote `path:line` for every claim.
- Score against flow as it is on `main` today. Open the flow file before saying "flow already covers it".
- A score of 4 or 5 needs a quote. A score of 0 or 1 needs the reason.
- Do not reward length. A 15-line principle that changes behaviour beats a 150-line playbook that restates defaults.
- For each attribution line in flow, run `git -C <upstream> diff <sha>..HEAD -- <cited path>`; each upstream fix to a borrowed file becomes an item. Every new credit line records the upstream short SHA it was taken from (`@ <sha>`).
- The user's standing rules apply to anything borrowed: no per-turn output noise, surface on demand only; no speculative features; mechanism over prose.
