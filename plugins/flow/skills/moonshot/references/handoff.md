---
name: handoff
description: How a moonshot phase becomes a flow seed PREP.md - what differs from develop-idea's flow-seed contract, why only the next phase is seeded, and how re-entry at a phase boundary works.
---

# Handoff: one phase at a time into flow

Read at Step 5 (before any seed) and Step 6 (Re-entry); skip while still choosing the bet.

Read [`../../develop-idea/references/flow-seed.md`](../../develop-idea/references/flow-seed.md) in full first. Its
yes gate, allocation, A-NN grammar, header, lint check and close line apply unchanged. This file lists only what a
moonshot changes.

## Why only the next phase

- With no feature holding a spec.md or TASKS.md, `flow next` shows the **newest** PREP-only directory and ignores
  `.specs/.current` (`router.js`, `findPrepWithoutSpec`), so seeding phases 1-5 at once surfaces phase 5 first.
- A bare `/flow:prep` with two or more unfinished interviews asks which, every run.
- Phase K+1's monkey is only knowable after K ships; an early seed is an unconfirmed guess that ages.

So MOONSHOT.md holds the plan, and flow holds one phase at a time. A moonshot phase is a flow **feature** (own
spec.md, TASKS.md, branch, PR), never a `## Phase` inside one TASKS.md.

## What the seed holds (deltas from flow-seed.md)

- `Seed:` line with true provenance: `Seed: "<what the user pointed at, their words>" — user, via /flow:moonshot
  (phase proposed by Mr Claude)`. The moonshot is the model's idea; the seed must not claim the user said it.
- A-01 is the cost of the status quo for this phase, never the replacement ("the app ships 350 MB of Chromium to
  render 12 screens", not "replace CEF with Blitz"). The replacement lives in MOONSHOT.md.
- A-04 (desired outcome) is the phase's Outcome; A-05 (riskiest assumption) is the phase's kill condition, `confidence: low`.
- A-07: `moonshot: MOONSHOT.md phase <K> of <N>; prerequisite proven: <what phase K-1 showed, or none>`.
- `## Not this`: the later phases' scope, one bullet each, plus MOONSHOT.md's Not this. This is what stops phase K
  from absorbing K+1 (prep carries it into the spec's Non-goals).
- `## Open` at most 3; surplus unknowns become `confidence: low` A-NN lines.
- Slug: `<moonshot-slug>-p<K>-<verb>`, max 40 chars, so no two phases collide.
- Under stealth, MOONSHOT.md never cites `.specs` paths or spec numbers; name phases by name.

After `prep-lint` prints `OK`, set the phase's row in MOONSHOT.md's table to `seeded`, append a status-log line, and
end with flow-seed.md's `Next:` line.

## Re-entry

Triggered when MOONSHOT.md exists (Step 6). Position comes from disk, never from a remembered transcript.
1. `flow next --json`. Only `idle` or `no-project` means the last phase is merged and archived; anything else, report
   the state and the router's command, and stop.
2. Find the phase marked `seeded` or `in progress`. Look for its evidence: the archived feature's PR, its check's
   output, the success-metric number.
3. Compare against the phase's continue/kill condition and say the result in one line, with the number.
4. Then ask which: **continue** (mark the phase `done`, append the log line, seed phase K+1 on a yes), **amend**
   (append a dated `## Amendment <date>` block that supersedes named lines; never rewrite the body), or **stop**
   (append the kill and its evidence; the plan stays as the record).
5. A user's hand edit of MOONSHOT.md is a decision: keep it.
