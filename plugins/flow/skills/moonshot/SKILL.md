---
name: moonshot
description: "Proposes ONE moonshot for an existing repo: finds the constraint everyone accepts as just how it is (a heavy dependency, a layer months of tweaks never fixed, a ruling that made a limit policy, a wish the owner wrote down and priced out), lets the owner say which one hurts, pitches the bet that removes it for the same product and the same people, priced for agent labour, tests the riskiest assumption before pitching where it can, writes MOONSHOT.md as 4-6 phases each with an oracle and a kill check, and seeds phase 1 into /flow:prep. Use when the user asks for a moonshot, 'what would you rebuild with unlimited resources', 'the 10x version', 'the ugliest part of this stack', 'we have tweaked X for months', or 'let it rip'; also when a MOONSHOT.md exists and its current phase shipped. Not for a list of ideas (flow-extras:brainstorm), growing the user's own idea (flow:develop-idea), judging an idea (flow-extras:scrutinize-idea), or a cleanup of one shipped spec (flow:flow-deepen)."
argument-hint: "[the part of the stack to rebuild, or a path]"
user-invocable: true
---

# Moonshot

A moonshot is **the thing the owner wanted and never asked for, because in human time it looked too expensive.**
The origin case: an app embedding CEF (all of Chromium) spent months on small tweaks; the move was writing its own
renderer. Same app, same users, same purpose; one structural limit gone. "The agent could always build something
like this. It just never suggested it, because in human time it looked too expensive." Labour is free now: agents
can build the dependency, the engine, the runtime, the index, a model trained on the project's own data.

Three failures to steer between:
- **The cleanup.** Told to be careful, a model shrinks the bet into something it can prove today (a duplicate file,
  a slimmer image). The structural limit stays.
- **The bundle.** Left alone, it stacks three or four projects (a graph, a twin, an agent loop, a platform) and
  opens with plumbing.
- **The other product.** Told to be ambitious, it turns the project into something bigger for people the owner
  never mentioned (a private reader becomes a public newsroom). It scores high with a judge and the owner never
  builds it. Ideas rated at the idea stage lose most of their lead once someone executes them
  (https://arxiv.org/abs/2506.20803), so this skill ranks by evidence and the owner's pick, never by an ambition score.

So: **one bet, for this product and these people, as big as removing the constraint takes, and no bigger.**

Six words carry the method; use them in everything you write:
- **accepted constraint**: the limit the repo treats as fixed. A heavy dependency, a layer every fix circles, a
  ruling that turned a limitation into policy ("NO_DATA is a first-class outcome", "100 voice clips a day"), or a
  wish the owner wrote down and priced out ("for now", "would need", "too slow", "by hand").
- **deletion list**: what stops being true when the bet lands: the constraint itself, and the workarounds, manual
  steps, waits, caps and dependencies it forced. Names, not categories. Empty = not a moonshot.
- **the ordinary day**: two short paragraphs, the owner (or their user) using the product on a normal day, today and
  after the bet. It replaces any score. If the two read the same, the bet is a cleanup. If the person in the second
  one is someone else, or the owner has a new job (running a service, moderating, selling), it is another product.
- **the monkey**: the one assumption that, if false, kills the bet. Phase 1 tests it. Everything easy is **the pedestal**.
- **probe**: a slice of the monkey's test small enough to run now, in this session, before the pitch. A measured
  number on the card is worth more than any argument for it.
- **oracle**: the executable thing that proves the result (the old implementation in lockstep, a conformance
  suite, recorded inputs with golden outputs, or the owner's own measure taken the same way before and after). Code
  is cheap with agents; the oracle is where the cost and the safety live. Every agent-built rewrite that worked had
  one before it started, so a bet with an oracle already in the repo outranks one that must build it.

**The owner's rulings are inputs.** Who the project is for, what it is for, what is private, what must not be
spent: read them all and honour them all. The constraint to remove is one the owner suffers, not one they chose. If
the best bet really needs a ruling changed, say so on that one card, show it last, and do not recommend it.

**Size.** The floor: the constraint has a structural cause incremental work cannot reach, the deletion list reaches
three or more places, and the bet needs at least three phases; less is a task, and it goes under Alternatives as a
quick win. The ceiling: the ordinary day is still the owner's. There is no number to hit. Use the measure the owner
already tracks when there is one, with today's value; never invent a metric whose baseline is 0.

`${CLAUDE_PLUGIN_ROOT}` is the flow plugin root. Run scripts with `node`, all paths absolute.

## Steps

**0. Where you are.** Run `flow next --json` and note `state` and `stealth.active` (no `flow` on PATH: you can
still write MOONSHOT.md; skip Step 5). MOONSHOT.md sits at the repo root, or at `.specs/MOONSHOT.md` when stealth is
active. If one exists, go to Step 6. Done when you know the state and whether this is a first run or a re-entry.

**1. Find the accepted constraints.** Read [`references/recon.md`](references/recon.md) before this step; it holds
the signal families, the load-bearing test and how to read the output. Read the owner's docs (README, PROGRESS,
plans, ADRs, rulings, specs, IDEAS) and run [`scripts/recon.mjs`](scripts/recon.mjs) as
`node ${CLAUDE_PLUGIN_ROOT}/skills/moonshot/scripts/recon.mjs --repo <root> [--focus <path>]`
(`--help` for the flags; do not read its source). When the user named the part, recon still runs, focused on it.
Write the **brief**, half a page, no solution in it:
- what the project is for and who uses it, in the owner's words, with the quote;
- the rulings, as a list, each marked scope or protective (all are honoured; the mark is for the reader);
- the measure the owner tracks, with today's value, or "none tracked";
- 3 to 5 accepted constraints, each named at the level of what the product can or cannot do, with receipts from
  at least 2 signal families (`path:line` or numbers), what it costs the owner (time, waits, failures, things done
  by hand), what was tried, and whether an oracle already exists for it.
Done when the brief holds 3+ constraints that pass the load-bearing test. Say "no moonshot found" (the nearest
candidate and the missing evidence, then stop) only when nothing passes; a young repo is not a reason, because
rulings, stated limits, priced-out wishes and dependency weight fire without history.

**2. Ask which one hurts.** Skip this step when the user named the part, or nobody is there to answer (then take
the constraint with the highest stated cost and say you chose it). Otherwise show the constraints, one or two
lines each (what the product cannot do, what it costs, the receipt), and ask two things: which of these costs the
most, or is it one not listed; and how much it is worth (a few phases, or months of agent work). Stop. The owner
has stopped seeing most of these, which is why you show the list and do not ask an open question; the owner still
knows which one they would pay to lose, which is why you ask. Done when one constraint and an appetite are named.

**3. Generate candidates cold.** Read [`references/candidates.md`](references/candidates.md); it holds the
generator, skeptic and comparison prompts, the card fields and the attractor list. Spawn one fresh subagent on the
strongest model with the brief only, no repo access, so it does not anchor on the current code. It returns 5 cards,
all removing the chosen constraint by different means, one of them the smallest version that still removes it. No
subagent tool in this session: generate in a separate pass that works from the brief text alone, and say on the
cards that they are not cold. Done when 5 cards came back, each with a non-empty deletion list and both
ordinary-day paragraphs.

**4. Ground, probe, attack, let the user pick one.** For each card: open the code it names, check the deletion
list, and fetch the primary source of every outside component it leans on (does it exist, how mature, does it do
the thing the card needs). Mark anything unchecked UNVERIFIED. An idea the owner wrote down and deferred is the
best lead there is: cite where. A product that already does it is evidence it works and a part to reuse, not a
reason to drop the card. Then:
- **Probe.** For each card still standing, run its probe when it fits in about 20 minutes, reads only, spends no
  money and sends nothing outward (replay a day of recorded input through a rough version, time the slow path with
  the part stubbed, count how often the case the bet depends on occurs in the repo's own data). Write the number
  and the command on the card. A failed probe kills the card, and that is a result. No probe possible: say why,
  and the card says "untested".
- **Skeptic.** One subagent (`sonnet`) with the cards, your notes and the brief; it may only kill or amend, in
  either direction: up when the card stops short of removing the constraint, down when it reaches past the owner's
  ordinary day. No subagent tool: run it as a separate pass and say so.
- **Compare.** A fresh subagent compares the survivors in pairs, both orders, on one question: which would this
  owner start on Monday and still be glad of in six months. No scores out of 10 anywhere.
Show at most 3 survivors in one block, each as the lines in candidates.md (Presenting survivors). Recommend one:
a passed probe first, then the longer deletion list, then the comparison. Always include the smallest version
that still removes the constraint, so the owner can see what the extra size buys.
End with "Which one should Mr Claude write to MOONSHOT.md?" and stop. Done when the user's reply names one.

**5. Write MOONSHOT.md.** Read [`references/moonshot-template.md`](references/moonshot-template.md); it holds the
template, the phase rules and the oracle-by-component table. Fill it for the one chosen bet. The other survivors go
under Alternatives, never into the phases. Check it against "Done when" below, then offer, in one line,
`/flow-extras:scrutinize-idea` on MOONSHOT.md as the attack pass (the proposer does not grade itself).

**6. Hand phase 1 to flow.** Only when `state` is `idle` or `no-project`: any other state means a feature or a
prep is already in flight; say so and leave the seed for re-entry. Read
[`references/handoff.md`](references/handoff.md), then the develop-idea seed contract it points to, before writing
anything. Seed phase 1 only, on the user's explicit yes. End the turn with the seed contract's `Next:` line.

**7. Re-entry at a phase boundary.** Read [`references/handoff.md`](references/handoff.md) (section Re-entry). Re-read
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

- **Never shrink the bet into a cleanup.** Evidence picks where; the structural cause sets how big; phase 1 settles
  whether it can be done. A fix recon can prove today goes under Alternatives as a quick win.

  | The excuse | Why it fails |
  |---|---|
  | "That component does not exist yet" | Agents build it; it becomes the monkey and phase 1 tests it |
  | "A smaller version is more realistic" | Keep it as the smallest-version card and let the owner see both |
  | "It would take a team a year" | That price is the reason nobody wrote it down; re-price it in phases and oracle work |

- **Never grow the bet into another product.** No new audience, no going public, no service to run, no change to
  what the project is for, unless the owner's docs already ask for it.

  | The excuse | Why it fails |
  |---|---|
  | "It is more ambitious" | Ambition is not the measure; the owner's ordinary day is |
  | "Nothing like it exists" | Nothing like the owner's wish, built, exists either, and that one gets used |
  | "The ruling is only about scope" | The owner made it on purpose; one flagged card may question it, the recommendation may not |

- **Never rank by a score out of 10, yours or a judge's.** Probe results, deletion lists and a paired comparison
  rank the cards; the owner picks.
- **Never pitch a layer that removes no constraint.** A graph, twin, calibrated model, agent loop or platform turn
  is the attractor kit; it earns its place only as the means of deleting a named constraint.
- **Never cost in people or calendar per task.** No squads, headcount, hires or "3 weeks for X". Size phases as flow
  features and oracle work. Human-time pricing is the bias that hid the moonshot in the first place.
- **Never start with the pedestal.** Phase 1 tests the monkey or builds the missing oracle; scaffolding, schema
  design and plumbing with no kill check prove nothing and make quitting expensive.
- **Never seed more than the next phase, write a `D-NN`, or invoke `/flow:prep` yourself.** The router surfaces
  the newest unprepped seed, a decision needs the user's receipt, and prep is user-invoked; handoff.md has the detail.

## Done when

- MOONSHOT.md's first line after the title is the bet in one sentence, the next two paragraphs are the ordinary
  day today and after, the deletion list is non-empty, every ruling in the brief is listed as honoured (or the one
  the owner agreed to change, with their words), and the file is at most about 150 lines.
- The success measure is one the owner already tracks, or the ordinary-day sentence a user could check; the probe's
  number and command are recorded, or "untested" with the reason.
- It has 4-6 phases; phase 1 tests the monkey or builds the oracle; every phase has a runnable check, a kill or
  continue condition with a number, and a "not this" fence; the last phase removes the old path or the old limit.
- Nothing in it prices work in people or per-task weeks.
- A seed, if written: `prep-lint` printed `OK` and the turn's last line is the seed contract's `Next:` line.
