---
name: moonshot-template
description: The MOONSHOT.md template, the phase rules (monkey first, seam, oracle, one flow feature per phase, retirement last), the oracle-by-component table with its freeze rules, and the agent-era re-pricing.
---

# MOONSHOT.md

Read at Step 4, and at Step 6 only when writing an Amendment.

## Template

Fill every slot; a slot you cannot fill is written `unknown: <what would tell us>`, never dropped. Detail is
proportional to risk: phases 1-2 near spec-ready, later phases outcome-level (they are written at maximum
ignorance and get re-shaped at each gate).

```markdown
# Moonshot: <name>

<The demo: the 30-second scene, present tense. What the owner sees, hears or touches.>

<The bet in one sentence.> Teaser: <path to the rough slice made before the pitch, or "none: <why>">.

| Phase | Status |
|---|---|
| 1 <name> | not started |
| ... | |

## Raw material
<What this uses that only this project has: archive, the owner's data, hardware, models, existing parts, with
paths and amounts. The delight signals it answers, quoted.>

## The accepted constraint
<Only when the bet removes one: what everyone works around, with receipts (path:line, numbers, rulings), and
what was tried. Otherwise delete this section.>

## Why it was never done, and why now
<What made it look too expensive (in human time, usually). What changed: the part that became available or
cheap, with its source and maturity. What still is not cheap (see Re-priced).>

## Deletion list
<What disappears when this lands, if anything. Names, not categories. A pure capability bet may write "nothing".>

## What stays
<Untouched parts, and the interface the new part must honour. Every ruling from the brief, one line each, marked
honoured; a ruling the owner agreed to change is quoted with their words and the date.>

## Oracle
<Only when the bet replaces a part; otherwise delete this section. What proves new == old: kind, input corpus, where it lives, what it does NOT pin (concurrency, performance,
security, environment), the accepted-divergence list (old bugs fixed on purpose).>

## How we know it worked
<The grin test, made checkable: what the owner does with it in an ordinary week (opens it daily, plays a round,
shows it to someone), plus one number that is cheap to read from the project's own logs. And the reason to come
back next week, not only on demo day.>

## Re-priced
| Cheap now (agents) | Not cheaper (owner) |
|---|---|
| ... | ... |

## Phases
### Phase 1: <name> (<prototype | tracer | oracle>; code kept: yes/no)
- Outcome: <what is true after it, user- or operator-visible>
- Check: <the command or observation that proves it>
- Continue if / kill if: <numbers, decided at this phase's gate>
- Not this: <what belongs to later phases>
- Door: <two-way | one-way>; scaffolding added: <...>, removed in phase <n>
### Phase 2 ...

## Not this
<Plausible goals declined, including any bigger version for other users, a public edition or a platform, with one
line on why it is not this bet.>

## Alternatives
<The boring incremental option and why it loses; the smallest version that still removes the constraint and what
the extra size buys; the other surviving candidates and why they lost; quick wins found on the way.>

## Status log
<Append-only: date, phase, what shipped, the check result, continue / amend / kill. Never edit old entries.>
```

## Phase rules

- **Phase 1 is the monkey, and it is already fun.** The smallest version the owner can play with on real data; it
  answers the killing question (is this actually fun, does the hard part work) with their reaction and one number.
  For a bet that replaces a part with no oracle, phase 1 is building the oracle. State which, and whether its code is kept
  (prototypes are thrown away). Schema design, scaffolding, "set up the project" are the pedestal: they fold into a
  later phase.
- **One phase = one flow feature**: one spec, one branch, one PR, a human `Verified:`. This binds phases 1-2, which
  are written near spec-ready. A later phase is an outcome; if at its gate it turns out to need several specs, the
  re-entry step splits it by Amendment. More than 6 phases at writing time means the bet is two bets.
- **Phase 1 starts from the teaser.** The teaser showed the moment; phase 1 makes it real and repeatable.
- **Every phase adds something visible.** A phase whose result the owner cannot see or hear is the pedestal: fold
  it into the phase that needs it.
- **Seam before swap.** If the old part is not behind an interface, an early phase puts it behind one and ships with
  zero behaviour change; later phases build the new part behind the same seam, behind a flag, old path still the
  default.
- **Every phase leaves main shippable.** If the program stopped after this phase, the product would still work and
  be no worse off. A phase that only pays when the last one lands makes the plan a big-bang cutover in disguise.
- **Port faithfully, clean up later.** No behaviour changes or redesign in the same phase as a port; cleanup comes
  after the old path is gone. Do not combine the replacement with a user-visible redesign.
- **Stateful paths**: shadow-compare only side-effect-free reads; for writes use dual-write then compare reads.
- **Hardening is a phase** for anything exposed to a network or untrusted input: a reimplementation that passes the
  old tests can still lose invariants the tests never held (vinext passed its ported Next.js tests; a security scan
  then validated 24 findings, among them cross-request state leaks and auth-blind cache keys;
  https://www.hacktron.ai/blog/hacking-cloudflare-vinext).
- **Retirement is last** and the only one-way door: delete the old path (or the ruling, workaround or manual step
  the old limit forced) after parity reaches a stated threshold and a fallback window has passed. Done means the
  old path is gone and the success metric measured, not "new code merged".
- **A capability bet** (the product gains what it could not do, rather than swapping a part) still has an oracle:
  the success metric's baseline measured the same way before and after, plus a regression check that existing
  behaviour holds. Port rules apply to whatever it replaces on the way.
- **A miss is a re-shape, not an extension.** A phase that fails its check goes back to the user as an Amendment or a
  kill; it does not get "a bit more time".

## Oracle by component

| Component | Build first | Add second | Not pinned |
|---|---|---|---|
| Pure function / library | Differential harness old vs new over generated inputs | Golden snapshots of edge cases; round-trip and idempotence properties | performance |
| CLI | Golden stdout, stderr, exit code and files written over 50-300 invocations (scrubbed) | Differential old vs new on the same corpus | env, locale, TTY, signals |
| HTTP service | Replay recorded requests against old, outbound calls cassetted in replay-only mode | Live read-only shadow comparison | writes, auth state, concurrency, security |
| UI / renderer | Screenshot or reftest baselines of old rendering, fixed viewport, fonts and container, dynamic parts masked | DOM or accessibility-tree snapshots | animation and interaction timing |
| Data pipeline | Row-level diff old vs new on frozen input snapshots | Row counts, nulls, uniqueness, idempotent rerun | late data, scale |
| Stateful store | Random operation sequences against old and new, agreement on every read, seeded | Recorded production traces; crash/restart sequences | interleavings, durability |

No runnable old implementation and no derivable properties: the component is not a candidate. Say so.

**Freeze the oracle** before any replacement phase, because agents game weak ones (special-casing test inputs,
editing tests, re-recording snapshots, raising diff thresholds, calling out to the old component):
- control-vs-control runs of the old implementation are clean (any diff is noise to normalise first);
- corpus, normalisers and thresholds sit in one manifest the implementer may not edit; corpus size never shrinks;
- a holdout slice (default 10-20%) runs only at the phase gate;
- the new code must not import, spawn or link the old one: test it where the old one is absent;
- the author of the oracle is not the agent making the new code pass it;
- no test is skipped, deleted or weakened to proceed, and a stub defended by a paragraph-long comment is wrong code.

## Re-priced

Cheap with agents: mechanical ports and rewrites against an oracle, boilerplate, test and corpus generation, faithful
translation. Not cheaper: the oracle's design, review attention, live-data cutover, operations, the owner's
retraining and docs, security of a reimplementation, and the long tail. Bun's agent port of 535k lines merged in
11 days and reached a stable release about 14 weeks later with 19 known regressions found on the way; treat the
merge date as the demo, not the finish (one data point, so a ratio is a guess; https://bun.com/blog/bun-in-rust,
https://bun.com/blog/bun-v1.4).
