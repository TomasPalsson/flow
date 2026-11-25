---
name: candidates
description: The generator, skeptic and paired-comparison prompts for moonshot Steps 3-4, the candidate card fields, the probe rules, the attractor motifs that need an override, and how to present survivors for the user's pick.
---

# Candidates: generate cold, ground, probe, attack

Read at Steps 3-4; skip on re-entry (Step 7).

Why this shape: one model asked for "the" moonshot returns its modal answer, bundled. Several candidates from a brief
give it room to reach a tail idea. Nothing is ranked by a score out of 10: the best LLM judge ranked research ideas
at 53.3% against 56.1% agreement between human reviewers (https://arxiv.org/abs/2409.04109), and when 43 experts
went on to build ideas, the LLM-written ones lost more on every measure than the human ones and the ranking
flipped (https://arxiv.org/abs/2506.20803). An earlier version of this skill tuned itself on a judged ambition
score and ended up proposing other products (docs/research/29-moonshot-usefulness-2026-11-25.md in the flow repo).
So: a measured probe where one is possible, a pass that can only kill or amend, a paired comparison on what this
owner would build, and the owner picks.

## Generator prompt (Step 3)

Spawn with `model: opus` (or the strongest available), no repo path, no tools needed. Paste the brief and the
owner's chosen constraint and appetite where marked.

```
You are proposing moonshots for a software project you cannot see. Below is a brief: what the project is for and
who uses it, the owner's rulings, and constraints everyone there has accepted as "just how it is". The owner chose
one constraint to remove. A moonshot here is the thing the owner wanted and never asked for because in human time
it looked too expensive. Labour is unlimited: a fleet of AI agents writes the code, so building your own engine,
runtime, renderer, index, compiler, model or protocol is on the table. Outside cooperation, money, and the owner's
own review time are not unlimited.

BRIEF:
<brief>

CHOSEN CONSTRAINT AND APPETITE:
<constraint, and what the owner said it is worth>

Rules:
- Same product, same people, same purpose. Every ruling in the brief holds. The bet removes a limit the owner
  suffers; it does not change who the project is for or give the owner a new job.
- Each card removes the chosen constraint entirely, not shrinks it, and not by adding a layer beside it.
- One bet per card: one assumption that could kill it.

Work in this order, writing each step down:
1. Say in one sentence what the project is for and who uses it, quoting the brief.
2. Say what holds the constraint in place: the structural cause that small fixes cannot reach.
3. List what a team would have said this costs in human time, and why that price no longer applies.
4. List what changed recently that might make removal possible (a library or project reaching usability, a cost
   collapse, a capability), and say how sure you are it exists.
5. Write 5 cards that remove the constraint by different means, not five sizes of one idea. First write down the
   most likely answer and set it aside as card 1; the other four must each differ from it in the means. One of the
   five is the smallest version that still removes the constraint. A tuned or 10% better version of the current
   design is out of scope.
6. For each card write the ordinary day, today and after. If the two read the same, replace the card. If the
   person in "after" is not the person in the brief, or the owner now runs something for strangers, replace it.
7. If you believe the best bet needs one ruling changed, you may write it as a sixth card marked NEEDS RULING,
   naming the ruling. At most one.

Card fields:
- bet: one sentence, the constraint it removes first, then the means
- ordinary day, today / after: two or three sentences each, the person from the brief on a normal day
- deletion list: what stops being true: the constraint, and the workarounds, manual steps, waits, caps or
  dependencies it forced (names from the brief, not categories)
- measure: the measure the brief says the owner tracks, today's value and the value this bet reaches; or, when the
  brief says none is tracked, the one sentence the owner could check
- build vs reuse: what gets built from scratch (fine: agents are cheap) and what existing parts it reuses
- why now: what changed that makes it newly feasible; mark "unverified" if you are not sure it exists
- what stays: the parts left untouched, and each ruling the card leans on
- the monkey: the single assumption that kills it if false
- first kill test: the cheapest experiment that could kill it, and its pass/fail number
- probe: the slice of that test that could run in 20 minutes on the repo's own data, reading only
- oracle: what proves the new thing behaves like the old one, and whether the brief says it already exists
- strongest counterargument
- prior art: who does anything like this today, and what can be reused from them
```

## Attractor motifs (check every card)

Current models' default moonshot for a codebase comes from one kit: a knowledge/claim **graph**, a **digital
twin** or simulator, a **calibrated / hierarchical Bayesian / causal** model, a **self-improving agent loop**, and a
**platform turn** (public API or MCP, cohorts, multi-client, open-sourcing, "for anyone"). In nine cold runs on six
repos all nine built from this kit and bundled about three bets each (docs/research/27-moonshot-forge-2026-10-27.md
in the flow repo). A motif is fine when it is the means of removing the named constraint ("give the blind loop a
sensor" removes NO_DATA); it fails when it sits beside the constraint and leaves it in place. The platform turn is
the one that also breaks the owner's ordinary day, so it needs both tests. A motif in new words is still that
motif: the test is the deletion list, not the vocabulary.

## Grounding (Step 4, you)

Per card, before the probe and the skeptic:
- Open every path or component in the card's deletion list; strike items that do not exist or that other code still
  needs.
- Fetch the primary source (repo README, docs, release notes) for every outside part in "build vs reuse" and "why
  now": does it exist, what maturity does it claim, does it do the specific thing the card needs. Quote the line.
  A part that is missing or immature is not a reason to drop the card: the card builds it, and the monkey names it.
  The failure to catch is a card that assumes a fact about the repo or the world that is false.
- Oracle: does a runnable old implementation, a test suite, a labelled set or recorded input exist? If none, the
  card's phase 1 is building one; say so on the card. A card whose oracle already exists says where.
- Owner's docs: grep them (IDEAS, PROGRESS Next, plans, specs, notes) for the card's core move. Written down and
  deferred for cost: the strongest sign the owner wants it; cite the line. Already scheduled or in progress (an
  open spec, a branch): it is the plan, not a moonshot; drop the card or move past what is planned.
- Rulings: check the card against every ruling in the brief. A conflict the generator missed makes it a NEEDS
  RULING card (at most one may be shown) or kills it.

## Probe (Step 4, you)

The probe turns the monkey from an argument into a number before the owner is asked to choose.
- Limits: about 20 minutes, read-only on the repo and its data, no money spent, nothing sent outward (no posts,
  mail, deploys, paid APIs), nothing written outside a scratch directory.
- Good probes: replay a day or a week of recorded input through a rough version of the new part; time the slow
  path with the old part stubbed out; count in the repo's own data how often the case the bet depends on occurs;
  run the candidate library on ten real inputs and diff against the current output.
- Record on the card: the command, the number, and the pass/fail line it was measured against (written before
  running). A failed probe kills the card. An inconclusive one says so; do not round it up.
- No probe possible (the test needs weeks, a human's marks, hardware that is not here): write "untested" and why.
  Such a card can still be shown; it ranks below any card whose probe passed.

## Skeptic prompt (Step 4)

Spawn with `model: sonnet`, with the cards, your grounding and probe notes, and the brief. No subagent tool: run
it yourself as a separate pass, cards and notes only, and say on the output that the skeptic was not independent.

```
Each card below proposes removing one accepted constraint from a codebase, for the owner described in the brief.
You may only KILL a card or AMEND it; you may not add new cards or merge cards. For each card answer:
1. Is the deletion list real after grounding? (If it is empty or struck, kill.)
2. Does the constraint survive it, with a new layer sitting beside it? (kill, or amend to the version that removes it)
3. Does it rest on a false fact about the repo or the world, per the grounding notes? (kill, or amend the fact) A part
   that does not exist yet is not false: the card builds it; amend the monkey to name it.
4. Did its probe fail? (kill) Is there a cheap first test that could kill it, and an oracle or a phase 1 that builds
   one? (no -> amend until there is; kill only if none can exist)
5. Is it really two or more bets? (amend to the one whose deletion list matters most)
6. Read the two ordinary-day paragraphs. Is the person in "after" still the person in the brief, doing what the
   project is for? If it adds an audience, goes public, or gives the owner a service to run that the brief does not
   ask for, AMEND it down to the version for the brief's owner. If it breaks a ruling and is not the one NEEDS
   RULING card, amend it to honour the ruling or kill it.
7. Do the two paragraphs read the same? Does it fit in one or two specs? Then KILL it as "a task, not a moonshot"
   and name it as a quick win.
8. Does it stop short: part of the constraint, or one of its workarounds, would still be there? AMEND up to the
   version that removes it.
9. Is it already scheduled in the owner's docs (see the grounding notes)? KILL it as "already planned".
Never kill a card for being unproven, unprecedented, or expensive in human time. Never amend a card upward for
ambition alone: up only to finish removing the constraint, down only to stay inside the owner's ordinary day.
Return per card: KILL with one-line reason, or KEEP/AMEND with the amended bet, both ordinary-day paragraphs,
deletion list, monkey and counterargument.
```

## Paired comparison (Step 4, after the skeptic)

Two or more survivors: spawn a fresh subagent (`model: opus`) with the brief and the surviving cards, labelled A,
B, C with probe results attached and no recommendation. No subagent tool: skip this pass and say so; do not
replace it with your own scores.

```
You are choosing for the owner described in the brief. For every pair of cards, answer twice, once in each order:
which of these two would this owner start on Monday and still be glad of in six months? Decide from the brief: what
the project is for, what the constraint costs them, their rulings, what they said it is worth. A measured probe
result outweighs any argument. Do not score cards; give the winner of each pair and one sentence of why. Then list
the cards in order of pairs won, and say where the two orders disagreed.
```

A pair that flips with the order is a tie; say so when presenting.

## Presenting survivors

At most 3, each as these lines: bet; the ordinary day today and after (one or two sentences each); deletion
list; the measure or check; the monkey with its first kill test; the probe (command, number, pass or fail, or
"untested" and why); what is reused and from whom; strongest counterargument; rulings (all honoured, or NEEDS
RULING and which). One of the three is the smallest version that still removes the constraint, labelled so. Put
the recommendation first with one sentence of why: a passed probe first, then the longer deletion list, then the
paired comparison. A NEEDS RULING card goes last and is never the recommendation. Every survivor a task: do not
present tasks as moonshots; go back to Step 1 for the next constraint, and list the tasks as quick wins. Ask the
user which to write and stop. If they want several: one MOONSHOT.md per bet, and the order matters (the one whose
phase 1 is cheapest to kill goes first). All killed: say so, show the best near-miss and its fatal flaw, stop.
