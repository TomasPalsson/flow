---
name: moonshot
description: "Proposes ONE moonshot for an existing repo: finds the constraint everyone accepts as just how it is (a heavy dependency, a layer months of tweaks never fixed, a ruling that made a limit policy), pitches a 12-month bet that removes it, priced for agent labour, writes MOONSHOT.md as 4-6 phases each with an oracle and a kill check, and seeds phase 1 into /flow:prep. Use when the user asks for a moonshot, 'what would you rebuild with unlimited resources', 'the 10x version', 'the ugliest part of this stack', 'we have tweaked X for months', or 'let it rip'; also when a MOONSHOT.md exists and its current phase shipped. Not for a list of ideas (flow-extras:brainstorm), growing the user's own idea (flow:develop-idea), judging an idea (flow-extras:scrutinize-idea), or a cleanup of one shipped spec (flow:flow-deepen)."
argument-hint: "[the part of the stack to rebuild, or a path]"
user-invocable: true
---

# Moonshot

**Go all out.** The size of the bet is the point of this skill; the user asked for the thing they would never have
dared to write down. Labour is free: agents can build the dependency yourself, a new engine, a new runtime, a
model trained on the project's own data, whatever the bet needs. The origin case: an app embedding CEF (all of
Chromium) spent months on small tweaks; the move was writing its own renderer. "The agent could always build
something like this. It just never suggested it, because in human time it looked too expensive."

Two failures to steer between. Left alone, a model bundles three or four projects (a knowledge graph, a digital
twin, a Bayesian engine, an agent loop, a platform for other users), prices them in squads and quarters, and opens
with plumbing. Told to be careful, it shrinks the bet into a cleanup it can prove. This skill wants **one bet, as big
as it goes**: one vision, one monkey, no cap on size. Feasibility is never a reason to shrink the bet; it is phase 1's
job. The only gate is that phase 1 has a cheap test that could kill the bet.

Five words carry the method; use them in everything you write:
- **accepted constraint**: the limit the repo treats as fixed. A heavy dependency, a layer every fix circles, or a
  ruling that turned a limitation into policy ("NO_DATA is a first-class outcome", "100 voice clips a day").
- **deletion list**: what stops being true when the bet lands: the constraint itself, and the workarounds, rulings,
  manual steps, waits and dependencies it forced. Empty = not a moonshot.
- **10x test**: if the bet works, the one-sentence description of the product changes, and the **north star** (the
  number the project exists to move: exams passed, leads won, readers who trust it) moves by 10x or more, or
  something the product cannot do becomes routine. 10x is the floor; aim for 100x or a new category. A subsystem metric (latency, image size, quota) does not count
  unless it is the north star's bottleneck. A bet that fits in one or two flow features is a task, not a moonshot.
  An idea already written in the owner's docs (IDEAS, PROGRESS Next, a proposal), or one some product already does,
  is a known direction: it can be a phase, never the bet. The target is the top of this scale: **10** = the project
  becomes a different, far bigger thing that nothing does today; 8 = a huge change in a known direction; 6 = a big
  upgrade of one part. Ship only 9-10.
- **the monkey**: the one assumption that, if false, kills the bet. Phase 1 tests it. Everything easy is **the pedestal**.
- **oracle**: the executable thing that proves the result (the old implementation in lockstep, a conformance
  suite, recorded inputs with golden outputs, or the success metric's baseline measured the same way). Code is
  cheap with agents; the oracle is where the cost and the safety live.

`${CLAUDE_PLUGIN_ROOT}` is the flow plugin root. Run scripts with `node`, all paths absolute.

## Steps

**0. Where you are.** Run `flow next --json` and note `state` and `stealth.active` (no `flow` on PATH: you can
still write MOONSHOT.md; skip Step 5). MOONSHOT.md sits at the repo root, or at `.specs/MOONSHOT.md` when stealth is
active. If one exists, go to Step 6. Done when you know the state and whether this is a first run or a re-entry.

**1. Find the accepted constraint.** Read [`references/recon.md`](references/recon.md) before this step; it holds
the signal families, the load-bearing test and how to read the output. Read the owner's docs (README, PROGRESS,
ADRs, rulings) and run `node ${CLAUDE_PLUGIN_ROOT}/skills/moonshot/scripts/recon.mjs --repo <root> [--focus <path>]`
(`--help` for the flags; do not read its source). When the user named the part, recon still runs, focused on it.
Write the **brief**: the project's reason to exist and its north star with today's number, the constraint at the
level of what the product can or cannot do, its receipts from at least 3
signal families (`path:line` or numbers), the stated reason it was accepted, what was tried, and today's baseline
numbers. Then zoom out once: what does the **whole category** accept as just how it is (every exam-prep app
assumes you study a fixed bank, every newsroom reports after the fact, every ads tool needs conversion volume)?
Add that category constraint to the brief; the 10 removes it, not only this repo's. Half a page, no solution in it.
Done when the brief names one repo constraint with 3+ families and the category constraint above it. Say "no
moonshot found" (the nearest candidate and the missing evidence, then stop) only when nothing clears the bar at any
level; a young repo is not a reason, because rulings, stated limits and dependency weight fire without history.

**2. Generate candidates cold.** Read [`references/candidates.md`](references/candidates.md); it holds the
generator and skeptic prompts, the card fields and the attractor list. Spawn one fresh subagent on the strongest
model with the brief only, no repo access, so it does not anchor on the current code. It returns 5 cards. No
subagent tool in this session: generate in a separate pass that works from the brief text alone, and say on the
cards that they are not cold. Done when 5 cards came back, each rated 9-10 on the ambition scale, passing the 10x
test, with a non-empty deletion list.

**3. Ground, attack, let the user pick one.** For each card: open the code it names, check the deletion list, and
fetch the primary source of every outside component it leans on (does it exist, how mature, does it do the thing
the card needs) and whether the owner's docs already hold the idea. Mark anything unchecked UNVERIFIED. Then spawn
one skeptic subagent (`sonnet`) with the cards and your notes; it may only kill or amend, never add, and it amends
up whenever a bigger version can still be killed by a cheap phase 1. Rank survivors by ambition and recommend the
biggest. The one gate is a cheap phase-1 test that could kill the bet; an unverified component, an unproven
capability or a thing nobody has built yet becomes the monkey, never a reason to drop or shrink the card. Cards
rated below 9 go to Alternatives, never to the list. Then run the **make-it-a-10 pass** on the recommendation
(candidates.md): a fresh rater scores it cold on the scale and names what holds it below 10; rewrite the bet at
that size while a cheap phase-1 test can still kill it; at most 2 rounds. Self-ratings run about a point high, so
only the fresh rater's score counts. Show the survivors (at most
3) in one block: the bet in one sentence, what the product becomes, the deletion list, the north-star number, the
monkey, the strongest counterargument, and your recommendation.
End with "Which one should Mr Claude write to MOONSHOT.md?" and stop. Done when the user's reply names one.

**4. Write MOONSHOT.md.** Read [`references/moonshot-template.md`](references/moonshot-template.md); it holds the
template, the phase rules and the oracle-by-component table. Fill it for the one chosen bet. The other survivors go
under Alternatives, never into the phases. Check it against "Done when" below, then offer, in one line,
`/flow-extras:scrutinize-idea` on MOONSHOT.md as the attack pass (the proposer does not grade itself).

**5. Hand phase 1 to flow.** Only when `state` is `idle` or `no-project`: any other state means a feature or a
prep is already in flight; say so and leave the seed for re-entry. Read
[`references/handoff.md`](references/handoff.md), then the develop-idea seed contract it points to, before writing
anything. Seed phase 1 only, on the user's explicit yes. End the turn with the seed contract's `Next:` line.

**6. Re-entry at a phase boundary.** Read [`references/handoff.md`](references/handoff.md) (section Re-entry). Re-read
MOONSHOT.md from disk, find the phase marked in progress, and check what shipped against that phase's continue/kill
check. Then one of three: continue (append a status line, seed the next phase on a yes), amend (append a dated
Amendment, never rewrite the body), or stop (append the kill with its evidence; a kill is a result, not a failure).

## Never

- **Never bundle bets.** One MOONSHOT.md holds one bet. The default answer bundles about three; a bundle has no
  single monkey, so no phase 1 can kill it, and it grows until it cannot ship.

  | The excuse | Why it fails |
  |---|---|
  | "They reinforce each other" | Then one is the means of the other: keep the one whose deletion list matters, and the rest become its phases or go to Alternatives |
  | "The user said unlimited resources" | Labour is unlimited; review attention, the oracle and the user's own time are not |
  | "Leaving it out wastes the idea" | Alternatives keeps it, with the reason it lost |

- **Never shrink the bet, for evidence or for feasibility.** Evidence picks where; the 10x test sets the floor on
  how big; phase 1 settles whether it can be done. A fix recon can prove (a duplicate file, a slimmer image, a lazy
  import) goes under Alternatives as a quick win, never as the moonshot. If the only survivors are tasks, go back to
  Step 1 one level up: what the product cannot do, not what the code repeats.

  | The excuse | Why it fails |
  |---|---|
  | "That component does not exist yet" | Agents build it; it becomes the monkey and phase 1 tests it |
  | "Nobody has done this" | That is why the owner never wrote it down; phase 1 is the cheap test |
  | "A smaller version is more realistic" | Realism is phase 1's verdict, not the proposer's; the smaller version goes under Alternatives |

- **Never recommend the safest survivor.** Every survivor already passed the one gate; picking the most
  credible again trades away the reason the user asked. Recommend the one whose "the product becomes" sentence is
  furthest from today's, and name the phase-1 test that would kill it.
- **Never pitch a layer that removes no constraint.** A graph, twin, calibrated model, agent loop or platform turn
  is the attractor kit; it earns its place only as the means of deleting a named constraint, and the deletion list
  says what stops being true.
- **Never cost in people or calendar per task.** No squads, headcount, hires or "3 weeks for X". Size phases as flow
  features and oracle work; keep 12 months as the scope ceiling only. Human-time pricing is the bias that hid the
  moonshot in the first place.
- **Never start with the pedestal.** Phase 1 tests the monkey or builds the missing oracle; scaffolding, schema
  design and plumbing with no kill check prove nothing and make quitting expensive.
- **Never bolt on users as a side project.** Cohorts, public APIs, multi-tenant or open-sourcing added beside the bet
  are bundling. When reaching far more people IS the bet (the product becomes a different, far bigger thing), it is
  allowed and its phase 1 tests that those people want it.
- **Never seed more than the next phase, write a `D-NN`, or invoke `/flow:prep` yourself.** The router surfaces
  the newest unprepped seed, a decision needs the user's receipt, and prep is user-invoked; handoff.md has the detail.

## Done when

- MOONSHOT.md's first line after the title is the bet in one sentence, the next says what the product becomes, the
  deletion list is non-empty, the success metric is the north star with today's number and a target of 10x or more, and the
  file is at most about 150 lines.
- It has 4-6 phases; phase 1 tests the monkey or builds the oracle; every phase has a runnable check, a kill or
  continue condition with a number, and a "not this" fence; the last phase removes the old path or the old limit.
- Nothing in it prices work in people or per-task weeks.
- A seed, if written: `prep-lint` printed `OK` and the turn's last line is the seed contract's `Next:` line.
