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
everyone has accepted as "just how it is". Labour is unlimited: AI agents write the code. Twelve months is the
ceiling on scope, not a schedule. Review attention, outside cooperation and the owner's own time are NOT unlimited.

BRIEF:
<brief>

Work in this order, writing each step down:
1. List the accepted constraints in the brief, one line each.
2. For each, ask what would make it disappear entirely, not shrink.
3. List what changed recently that might make that possible (a library or project reaching usability, a cost
   collapse, a capability), and say how sure you are it exists.
4. Write 5 candidate cards. A tuned or 10% better version of the current design is out of scope, and so is a
   cleanup: each card must move its success metric by about 10x, or make something the product cannot do routine,
   and must need at least four buildable steps. Each card must also remove the constraint; a layer added on top
   that leaves the constraint in place is not a moonshot.
5. For each card, estimate the probability that a typical coding agent would propose it unprompted. Prefer cards
   under 0.1 and drop any above 0.3, replacing them.

Card fields:
- bet: one sentence, the constraint it removes first, then the means
- deletion list: what stops being true: the constraint, and the workarounds, rulings, manual steps, waits or
  dependencies it forced (names, not categories)
- 10x: the success metric, today's number, and the number this bet reaches
- composed from: the existing mature parts it would reuse, and what would be built new
- why now: what changed that makes it newly feasible; mark "unverified" if you are not sure it exists
- what stays: the parts left untouched
- the monkey: the single assumption that kills it if false
- first kill test: the cheapest experiment that could kill it, and its pass/fail number
- oracle: what would prove the new thing behaves like the old one
- strongest counterargument
- typicality: your probability from step 5
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
- Fetch the primary source (repo README, docs, release notes) for every outside part in "composed from" and "why
  now": does it exist, what maturity does it claim, does it do the specific thing the card needs, what does it say
  it does not do. Quote the line. A moonshot that hinges on a capability nobody checked is the fantasy case.
- Oracle: does a runnable old implementation, a test suite or recorded input exist? If none, the card's phase 1 is
  building one; say so on the card.

## Skeptic prompt (Step 3)

Spawn with `model: sonnet`, with the cards and your grounding notes.

```
Each card below proposes replacing part of a codebase. You may only KILL a card or AMEND it; you may not add new
cards or merge cards. For each card answer:
1. Is the deletion list real after grounding? (If it is empty or struck, kill.)
2. Does the constraint survive it, with a new layer sitting beside it? (kill, or amend to the version that removes it)
3. Does every outside part it depends on exist and do what the card needs, per the quoted sources? (unverified -> amend
   the monkey to that dependency)
4. Is there an oracle, or a believable phase 1 that builds one? (no -> kill)
5. Is it really two or more bets? (amend to the one whose deletion list matters most)
6. Does it add users, tenants or a public product the brief never mentions? (amend it out)
7. Is it still a moonshot? If it fits in one or two specs, or its success metric moves less than about 3x, KILL it
   as "a task, not a moonshot" and name it as a quick win. An amendment may narrow a card to one bet; it may not
   shrink its 10x target.
Return per card: KILL with one-line reason, or KEEP/AMEND with the amended bet, 10x number, monkey and counterargument.
```

## Presenting survivors

At most 3, ranked by your recommendation, each as six lines: bet, deletion list, 10x number, the monkey, strongest
counterargument, typicality. Every survivor a task: do not present tasks as moonshots; go back to Step 1 one level
up (what the product cannot do), and list the tasks as quick wins. Put the recommendation first with one sentence of why. Ask the user which to write and
stop. If they want several: one MOONSHOT.md per bet, and the order matters (the one whose phase 1 is cheapest to
kill goes first). All killed: say so, show the best near-miss and its fatal flaw, stop.
