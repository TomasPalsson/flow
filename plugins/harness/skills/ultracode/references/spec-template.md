---
name: spec-template
description: Grill question bank + SPEC.md template for ultracode Phase 1. The spec is the only context fleet agents get — this template exists to make it misinterpretation-proof.
---

# SPEC.md — Template and Grill Bank

## Grill bank (pick the 3-5 load-bearing ones; batch them; skip any the request already answers)

1. **Oracle** — What command proves this worked? (test suite, compiler, typecheck, a script). If the answer is "nothing runs it", flag it: no oracle means Sonnet workers lose their safety net and that slice needs an Opus worker or a new test written FIRST.
2. **Done-boundary** — What is explicitly OUT of scope? (The #1 fleet failure is spec/design flaw, and the most common form is agents "helpfully" expanding scope.)
3. **Contracts** — Which interfaces/types/schemas do multiple units touch? These get frozen in the spec BEFORE fan-out; they cannot be decided by parallel agents independently.
4. **Behavior preservation** — Faithful port/refactor (same behavior, bug-for-bug) or improvement allowed? Fleets do mechanical-faithful well and creative-improvement inconsistently; mixing the two in one run produces both.
5. **Risk surfaces** — Auth, concurrency, money, data deletion? These route to structural-blind-spot handling (tool co-signers, human review) and may need network/git-history stripped from workers.
6. **Budget/priority** — If token budget bites, what's droppable? (Sets the workflow budget guard and what gets logged as dropped.)

## Template

```markdown
# SPEC: <task slug>

## Objective
<2-4 sentences. What exists after, that doesn't exist now.>

## Oracle (how every unit is judged)
- Command: `<test/build/typecheck command>` — run from <dir>
- Baseline: <N tests pass / build green as of <commit>> ← count, not just status
- A unit is DONE when: <oracle green + adversary Fatal/Significant findings resolved>

## Out of scope (hard boundaries)
- <thing agents will be tempted to touch — name it explicitly>

## Frozen contracts (decided here, not by agents)
<interfaces, types, schemas, naming — pasted verbatim. Anything two units share.>

## Unit map (ownership = files no other unit touches)
| Unit | Owns (files/dirs) | Depends on | Notes |
|---|---|---|---|

## Rules for every agent (paste into each prompt)
- Only touch files your unit owns. BLOCKED > improvised: if you cannot proceed
  without touching another unit's files or an unfrozen decision, stop and report BLOCKED.
- Never delete, skip, or weaken a test. Never stub "to make it pass/compile".
  If a workaround needs a paragraph to justify, the code is wrong — fix the code.
- Git: commit only your owned files. Banned: stash, reset, checkout, pull, merge.
  No repo-wide builds/greps mid-loop.
- Output: write artifacts to .ultracode/<slug>/<unit>/, return summary + paths +
  evidence (oracle command, its real output, test counts).

## Per-unit prompt packet (fill per unit)
- Objective: <unit-specific>
- Output format + path: <exact>
- Boundaries: <unit-specific "do NOT">
- Acceptance: <unit-specific oracle expectations>
```

## Before fan-out

Run one `adversary` (lens: spec) against this SPEC: unstated assumptions, contradictions between sections, units whose ownership overlaps, oracle gaps. Fix Fatal/Significant findings. Then — and only then — Phase 2.
