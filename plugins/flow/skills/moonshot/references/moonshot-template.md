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

<The bet in one sentence: the constraint removed, then the means.>
If it works, <project> becomes: <the new one-sentence description of what the product is>.

| Phase | Status |
|---|---|
| 1 <name> | not started |
| ... | |

## The accepted constraint
<What everyone works around, with receipts (path:line, numbers, rulings). The structural cause incremental
work cannot reach. What was tried and stalled.>

## Why it was never done, and why now
<What made it look too expensive (in human time, usually). What changed: the part that became available or
cheap, with its source and maturity. What still is not cheap (see Re-priced).>

## Deletion list
<What disappears when this lands. Names, not categories.>

## What stays
<Untouched parts, and the interface the new part must honour.>

## Oracle
<What proves new == old: kind, input corpus, where it lives, what it does NOT pin (concurrency, performance,
security, environment), the accepted-divergence list (old bugs fixed on purpose).>

## Success metric
<The north star (the number the project exists to move): today's baseline and the 10x target, measured the same
way before and after, plus one sentence a user could check.>

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
<Plausible goals declined, including anything that came up about other users or a platform.>

## Alternatives
<The boring incremental option and why it loses; the other surviving candidates and why they lost.>

## Status log
<Append-only: date, phase, what shipped, the check result, continue / amend / kill. Never edit old entries.>
```

## Phase rules

- **Phase 1 is the monkey.** A prototype that answers the killing question with a pass/fail number on a real
  workload, or, when there is no oracle, building the oracle. State which, and whether its code is kept
  (prototypes are thrown away). Schema design, scaffolding, "set up the project" are the pedestal: they fold into a
  later phase.
- **One phase = one flow feature**: one spec, one branch, one PR, a human `Verified:`. A phase that would need two
  specs is two phases; more than 6 phases means the bet is two bets.
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
