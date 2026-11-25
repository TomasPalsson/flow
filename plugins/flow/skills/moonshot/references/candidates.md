---
name: candidates
description: The generator, skeptic and paired-comparison prompts for moonshot Steps 2-3, the card fields, the lame list, the teaser rules, and how to present survivors for the user's pick.
---

# Candidates: pitch cold, ground, attack, tease

Read at Steps 2-3; skip on re-entry (Step 6).

Why this shape: one model asked for "the" moonshot returns its modal answer, and the modal answer is worthy and
dull. Twelve one-line demos across different lenses give it room to reach a tail idea; asking for the likely
answers first and setting them aside pushes it further (asking for several answers with their likelihood widened
the range 1.6-2.1x in creative tasks, https://arxiv.org/abs/2510.01171; LLM idea pools are less varied than a group
of people's unless pushed, https://arxiv.org/abs/2402.01727). Nothing is ranked by a score out of 10: LLM judges
rank ideas near chance (https://arxiv.org/abs/2409.04109) and idea-stage ratings fall once the idea is built
(https://arxiv.org/abs/2506.20803). An earlier version of this skill tuned itself on a judged ambition score and
produced grand, earnest plans the owner called lame (docs/research/29-moonshot-usefulness-2026-11-25.md in the flow
repo). So: demo first, a pass that can only kill or amend, a paired comparison on one question, teasers the owner
can look at, and the owner picks.

## Generator prompt (Step 2)

Spawn with `model: opus` (or the strongest available), no repo path, no tools needed. Paste the brief where marked.

```
You are pitching moonshots for a software project you cannot see. The brief below says what it is, who uses it,
what the owner has built for fun, the raw material it has, and the owner's rulings. The owner wants something COOL
AND FUN: the version of this project they would be dying to show a friend, and never asked for because in human
time it looked too expensive. Labour is unlimited: a fleet of AI agents writes the code, so a custom engine, a
game, an instrument, a model trained on the owner's own data, or software for hardware in the owner's home are all
on the table. Money, outside cooperation and the owner's own attention are not unlimited.

BRIEF:
<brief>

What the owner does NOT want (they have seen these and called them lame): complete coverage of something;
verification, auditing, fact-checking, trust or provenance layers; knowledge graphs; dashboards and analytics;
anything "calibrated"; self-improving agent loops; public APIs and platforms; a bigger audience; better accuracy,
reliability, speed or cost; summaries of summaries. If a pitch's best moment is a number going up, drop it.

Rules:
- For this owner. Same person, their rulings hold. Fun for them, not a launch.
- Built from this project's raw material: every pitch names at least two things from the brief's list and could
  not be made the same way for another project.
- One bet per card.

Work in this order, writing each step down:
1. Say in one sentence what the project is and what the owner seems to enjoy about it, quoting the brief's
   delight signals.
2. Write the three pitches a typical assistant would give for this project. Set them aside; nothing below may be
   one of them or a variant.
3. Write 12 demos, one or two sentences each: what the owner sees, hears or touches in the first 30 seconds. Use
   each of these lenses at least once: alive (moves and reacts while you watch); physical (a screen on the wall, a
   printer, a speaker, a light, the machine itself); toy or game; a voice or a character; absurd scale (all of it
   at once); time machine (replay or run forward); the invisible made visible; the flex (our own engine, model,
   renderer or format, from scratch because we can); only here (the owner's own taste, voice or history).
4. For each of the 12 answer honestly: would the owner show this to a friend tonight, and would the friend ask
   how it works? Keep the 5 with the strongest yes, from at least 4 different lenses.
5. For each of the 5, make it more fun once: what would make the owner laugh, or come back tomorrow? Rewrite.
   Then write the card.

Card fields:
- the demo: the 30-second scene, present tense, concrete (what is on screen, what sound, what the owner does)
- bet: one sentence
- lens: which of the lenses it came from
- raw material: what it uses from the brief, by name and amount
- the price that hid it: what this would have cost a person or team, and why agents change that
- build vs reuse: what gets built from scratch (fine: agents are cheap) and what existing parts it reuses
- coming back: why the owner uses it again next week, not only on demo day
- the monkey: the single assumption that kills it if false
- phase 1: the smallest version that is already fun, and the reaction or number that would kill the bet
- teaser: a rough slice that could be made in 20 minutes from the brief's raw material (a page, a clip, an image)
- rulings: which rulings it touches and how it honours them
- strongest counterargument
- prior art: who does anything like this, and what makes this one the owner's
```

## The lame list (check every card)

Kill on sight unless the demo passes the grin test without the label: complete coverage of X; verify / audit /
fact-check / provenance / trust; knowledge or claim graph; digital twin or simulator of the project itself;
calibrated, Bayesian or causal anything; self-improving agent loop; dashboard, analytics, observability; public
API, MCP server, platform, multi-user, open-sourcing; "for anyone"; faster, cheaper, more accurate, more reliable;
a rewrite whose only visible result is that nothing changed. In nine cold runs on six repos all nine default
moonshots came from this kit (docs/research/27-moonshot-forge-2026-10-27.md in the flow repo). A motif in new words
is still that motif: the test is the demo. If the scene is someone reading a table, it is lame.

A rewrite or own-engine bet (the origin case) is welcome when its demo is visible: it starts instantly, it does a
thing the old part could not, it is small enough to read. "Same behaviour, fewer megabytes" alone is a cleanup.

## Grounding (Step 3, you)

Per card, before the skeptic:
- Raw material: open the paths. Is the archive that big, do the marks exist, is the hardware or model really on
  hand per the owner's docs? Correct the amounts; strike what is not there.
- Outside parts: fetch the primary source for each (repo README, docs, release notes): does it exist, how mature,
  does it do the specific thing. Quote the line. Missing or immature is not a reason to drop the card: the card
  builds it, and the monkey names it.
- Owner's docs: grep for the card's core move. Written down as a wish and deferred: a strong sign; cite the line.
  Already scheduled or built: drop the card or go past it.
- Rulings: check each. A conflict makes it the one NEEDS RULING card or kills it.
- For a card that replaces a part: is there an oracle (old implementation, tests, recorded inputs)? Note it; the
  template's oracle table applies to that card.

## Skeptic prompt (Step 3)

Spawn with `model: sonnet`, with the cards, your grounding notes and the brief. No subagent tool: run it yourself
as a separate pass and say on the output that the skeptic was not independent.

```
Each card pitches a moonshot for the owner described in the brief, who asked for something cool and fun and has
called earlier, worthier proposals lame. You may only KILL a card or AMEND it; you may not add or merge cards.
For each card answer:
1. Read only the demo. Would this owner show it to a friend tonight, and would the friend ask how it works? If
   the honest answer is "it is sensible", KILL it as worthy.
2. Is it on the lame list in other words (coverage, verification, graph, dashboard, platform, a number going up)?
   KILL, or amend to the version whose demo stands on its own.
3. Does it rest on a false fact about the repo or the world, per the grounding notes? (kill, or amend the fact)
   A part that does not exist yet is not false: the card builds it.
4. Could it be made the same way for any other project? Then it does not use the raw material: amend it until it
   could only be this one, or kill it.
5. Is it two or more bets? (amend to the one with the better demo)
6. Is it for someone other than the owner, or does it give the owner a service to run for strangers? Amend it
   back to the owner. Does it break a ruling? Amend to honour it, or kill.
7. Would a person have built it in an afternoon? KILL as a task and name it as a quick win.
8. Is it a one-day novelty: fun once, never opened again? Amend "coming back" until it has a reason, or say so
   plainly as its counterargument.
9. Is there a more fun version of this same card? AMEND toward it. Never amend toward safer, smaller or more
   sensible.
Never kill a card for being unproven, unprecedented, frivolous, or expensive in human time.
Return per card: KILL with one-line reason, or KEEP/AMEND with the amended demo, bet, monkey, phase 1 and
counterargument.
```

## Paired comparison (Step 3, after the skeptic)

Two or more survivors: spawn a fresh subagent (`model: opus`) with the brief and the surviving cards, labelled A,
B, C, no recommendation attached. No subagent tool: skip this pass and say so; do not replace it with scores.

```
You are choosing for the owner described in the brief, who wants something cool and fun. For every pair of cards,
answer twice, once in each order: which of these two would this owner rather show a friend tonight, and still be
playing with in a month? Decide from the brief's delight signals and what they said they like and hate. Do not
score cards; give the winner of each pair and one sentence of why. Then list the cards in order of pairs won, and
say where the two orders disagreed.
```

A pair that flips with the order is a tie; say so when presenting.

## Teasers (Step 3, you)

For the top 2 or 3 after the comparison. The teaser is the reason the owner can choose with their eyes.
- Limits: about 20 minutes each, real data from the repo (never invented content), written only to a scratch
  directory, no money spent, nothing sent outward (no posts, mail, deploys, paid APIs).
- Forms: one self-contained HTML page; an audio file; an image or short screen recording; a terminal session.
  Follow the project's own look where it has one (its design notes, its palette).
- It shows the core moment of the demo, not the whole product: one day replayed, one story as the new thing, one
  round of the game.
- Open it yourself before showing it (screenshot the page, play the first seconds). A teaser that is broken or
  dull is information: say so, and let it move the card down.
- Cannot be made here (needs the owner's hardware, a model not on this machine): say what is missing and give the
  command that would make it there.

## Presenting survivors

At most 3. Each: the teaser path (or why none); the demo scene; the bet in one sentence; the raw material it
uses; the price that hid it; the monkey and phase 1; coming back; strongest counterargument; rulings (all
honoured, or NEEDS RULING and which). Recommendation first, one sentence of why. A NEEDS RULING card goes last and
is never the recommendation. Keep the whole block short enough to read in two minutes; the teasers carry the
weight. Below it, one line each: the cards that were killed and why, and any quick wins found. Ask the user which
to write and stop. All killed: say so, show the nearest miss, and go back to Step 2 with the lenses not yet used.
