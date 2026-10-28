---
name: candidates
description: The generator and skeptic prompts for moonshot Steps 2-3, the candidate card fields, the attractor motifs that need an override, and how to present survivors for the user's pick.
---

# Candidates: generate cold, ground, attack

Read at Steps 2-3; skip on re-entry (Step 6).

Why this shape: one model asked for "the" moonshot returns its modal answer, bundled. Several candidates from a brief
give it room to reach a tail idea; a separate pass that can only kill or amend stops it blessing its own text (the
best LLM judge ranked research ideas at 53.3% against 56.1% agreement between human reviewers;
https://arxiv.org/abs/2409.04109). The user picks, because the pick is a judgment about their product.

## Generator prompt (Step 2)

Spawn with `model: opus` (or the strongest available), no repo path, no tools needed. Paste the brief where marked.

```
You are proposing moonshots for a software project you cannot see. Below is a brief about one part of it that
everyone has accepted as "just how it is". Go all out: the owner wants the idea they would never have dared to
write down. Labour is unlimited: a fleet of AI agents writes the code for twelve months, so building your own engine,
runtime, renderer, compiler, model or protocol is on the table, and so is anything nobody has built yet. Feasibility
is not your job: each card gets a cheap first test that can kill it, and that test decides. Outside cooperation and
the owner's own review time are the only things that are not unlimited.

BRIEF:
<brief>

Work in this order, writing each step down:
0. Say in one sentence what the project is for, and its north star (the number it exists to move) with today's
   value from the brief.
1. List the accepted constraints in the brief, one line each, the category constraint (what every product of this
   kind accepts) first. The owner's scope rulings (who it is for, what it is for, "X first") count as constraints
   you may remove; rulings that protect safety, money or data do not. At least three cards must remove the category constraint, not only this project's.
2. For each, ask what would make it disappear entirely, not shrink.
3. List what changed recently that might make that possible (a library or project reaching usability, a cost
   collapse, a capability), and say how sure you are it exists.
4. Write 5 candidate cards. A tuned or 10% better version of the current design is out of scope, and so is a
   cleanup: each card must move the NORTH STAR (not a subsystem number) by 10x or more, or make something the
   product cannot do routine, and must need at least four buildable steps. Each card must also remove the
   constraint; a layer added on top that leaves the constraint in place is not a moonshot.
5. Push every card further, three times: "what if this went all the way?"; "and if that worked, what would be
   absurd not to do next?"; "who else does something like this today, and what would make this unlike anything
   that exists?" The product may outgrow its current audience or scope if that is the bet. Rewrite the card at the
   biggest size a cheap first test can still kill. Aim for 100x on the north star or a new category of product.
   Then rate each card on this scale and replace any below 9: 10 = the project becomes a different, far bigger thing
   that nothing does today; 8 = a huge change in a known direction; 6 = a big upgrade of one part.
6. For each card, estimate the probability that a typical coding agent would propose it unprompted. Prefer cards
   under 0.1 and drop any above 0.3, replacing them.

Card fields:
- bet: one sentence, the constraint it removes first, then the means
- the product becomes: the new one-sentence description of the project if the bet works (it must differ from
  today's sentence in what the product is, not only in how fast or cheap)
- deletion list: what stops being true: the constraint, and the workarounds, rulings, manual steps, waits or
  dependencies it forced (names, not categories)
- 10x: the north star, today's number, and the number this bet reaches
- build vs reuse: what gets built from scratch (fine: agents are cheap) and what existing parts it reuses
- why now: what changed that makes it newly feasible; mark "unverified" if you are not sure it exists
- what stays: the parts left untouched
- the monkey: the single assumption that kills it if false
- first kill test: the cheapest experiment that could kill it, and its pass/fail number
- oracle: what would prove the new thing behaves like the old one
- strongest counterargument
- typicality: your probability from step 6
- prior art: who does anything like this today, and what this does that they do not
- ambition: your 1-10 rating from step 5
```

## Attractor motifs (check every card)

Current models' default moonshot for a codebase comes from one kit: a knowledge/claim **graph**, a **digital
twin** or simulator, a **calibrated / hierarchical Bayesian / causal** model, a **self-improving agent loop**, and a
**platform turn** (public API or MCP, cohorts, multi-client, open-sourcing). In nine cold runs on six repos all nine
built from this kit and bundled about three bets each (docs/research/27-moonshot-forge-2026-10-27.md in the flow
repo). A motif is fine when it is the means of removing the named constraint ("give the blind loop a sensor" removes
NO_DATA); it fails when it sits beside the constraint and leaves it in place. A motif in new words is still that
motif: the test is the deletion list, not the vocabulary.

## Grounding (Step 3, you)

Per card, before the skeptic sees it:
- Open every path or component in the card's deletion list; strike items that do not exist or that other code still
  needs.
- Fetch the primary source (repo README, docs, release notes) for every outside part in "build vs reuse" and "why
  now": does it exist, what maturity does it claim, does it do the specific thing the card needs. Quote the line.
  A part that is missing or immature is not a reason to drop the card: the card builds it, and the monkey names it.
  The failure to catch is a card that assumes a fact about the repo or the world that is false.
- Oracle: does a runnable old implementation, a test suite or recorded input exist? If none, the card's phase 1 is
  building one; say so on the card.
- Already thought of: grep the owner's docs (IDEAS, PROGRESS Next, proposals, open specs) for the card's core move,
  and search the web for products or projects already doing it. A hit is a known direction (an 8 at best); note it,
  and the skeptic must push the card past it.

## Skeptic prompt (Step 3)

Spawn with `model: sonnet`, with the cards and your grounding notes.

```
Each card below proposes replacing part of a codebase. You may only KILL a card or AMEND it; you may not add new
cards or merge cards. For each card answer:
1. Is the deletion list real after grounding? (If it is empty or struck, kill.)
2. Does the constraint survive it, with a new layer sitting beside it? (kill, or amend to the version that removes it)
3. Does it rest on a false fact about the repo or the world, per the grounding notes? (kill, or amend the fact) A part
   that does not exist yet is not false: the card builds it; amend the monkey to name it.
4. Is there a cheap first test that could kill it, and an oracle or a phase 1 that builds one? (no -> amend until
   there is; kill only if none can exist)
5. Is it really two or more bets? (amend to the one whose deletion list matters most)
6. Does it bolt on users, tenants or a public product beside the bet? (amend it out; when reaching them IS the bet, keep it)
7. Is it still a moonshot? If it fits in one or two specs, or its north star moves less than about 3x, KILL it
   as "a task, not a moonshot" and name it as a quick win. An amendment may narrow a card to one bet; it may not
   shrink its 10x target.
8. Is it already in the owner's docs, or does some product already do it (see the grounding notes)? Then AMEND it
   up past the known direction, or KILL it as "already planned".
9. Is there a bigger version that a cheap first test could still kill? AMEND up to it.
10. Rate it 1-10 (10 = the project becomes a different, far bigger thing nothing does today; 8 = a huge change in a
   known direction; 6 = a big upgrade of one part). Below 9: AMEND up or KILL.
Never kill or shrink a card for being too ambitious, unproven or unprecedented; kill only on false facts, no
possible kill test, bundling or task size.
Return per card: KILL with one-line reason, or KEEP/AMEND with the amended bet, "the product becomes" sentence,
north-star number, monkey, counterargument and ambition rating.
```

## Make-it-a-10 pass (Step 3, after the skeptic)

Spawn a fresh subagent (`model: opus`) with only the recommended card, the brief and this prompt; it has not seen
the other cards or any self-rating. No subagent tool: run it as a separate pass and discount your own score by one.

```
Rate this moonshot 1-10 on this fixed scale: 10 = if it works the project becomes a different, far bigger thing
that nothing does today; 8 = a huge change in a known direction; 6 = a big upgrade of one part; 4 = a solid feature.
Then, if it is below 10, name exactly what holds it there (it stays the same product for the same people; a known
product already does this; it moves a part, not what the project exists for; it stops short of the obvious next
step; it obeys an owner ruling about scope, such as who the project is for or "X first"), and write the version of
this bet that would be a 10. Scope rulings may be broken; rulings that protect safety, money or data may not. Keep
one bet and one monkey. Return: score, what holds it back, the 10 version in one sentence, and the cheapest first
test that could kill the 10 version.
```

If the 10 version has a cheap first kill test, it becomes the recommendation and the card it grew from becomes a
runner-up. Re-rate it with a fresh rater each round; stop at 10 or after three rounds.

## Presenting survivors

At most 3, ranked by ambition, each as eight lines: bet, the product becomes, deletion list, north-star number,
the monkey with its first kill test, prior art and what is new, strongest counterargument, ambition rating. Recommend the biggest. Every survivor a
task: do not present tasks as moonshots; go back to Step 1 one level
up (what the product cannot do), and list the tasks as quick wins. Put the recommendation first with one sentence of why. Ask the user which to write and
stop. If they want several: one MOONSHOT.md per bet, and the order matters (the one whose phase 1 is cheapest to
kill goes first). All killed: say so, show the best near-miss and its fatal flaw, stop.
