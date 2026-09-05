---
name: fleet-economics
description: Claude API pricing (snapshot 2026-07-21) and the fleet arithmetic — tier staircase, cache break-evens, worked fan-out costings. Load before sizing a fleet or choosing non-default tiers.
---

# Fleet Economics (pricing snapshot 2026-07-21)

Source: platform.claude.com/docs/en/about-claude/pricing — re-check if quoting to the user after **Sep 1, 2026** (see cliff below).

## Base rates, $/MTok

| Model | Input | Output | 5m cache write | 1h cache write | Cache read |
|---|---|---|---|---|---|
| Haiku 4.5 | $1 | $5 | $1.25 | $2 | $0.10 |
| **Sonnet 5 (intro, thru Aug 31 2026)** | **$2** | **$10** | $2.50 | $4 | $0.20 |
| Sonnet 5 (from Sep 1 2026) / 4.6 | $3 | $15 | $3.75 | $6 | $0.30 |
| Opus 4.8 | $5 | $25 | $6.25 | $10 | $0.50 |
| Fable 5 / Mythos 5 | $10 | $50 | $12.50 | $20 | $1 |

Universal multipliers: 5m cache write = 1.25x input, 1h write = 2x, cache read = 0.1x. Batch API = 50% off both directions (not available for interactive sessions). Data residency `inference_geo:"us"` adds a flat 1.1x. No long-context surcharge on current-gen models — 1M-token context is linear pricing.

**The three numbers to keep in your head:**
1. **Output = 5x input at every tier.** This is *why* the orchestrator (read-heavy: specs in, verdicts out) can run on an expensive model while workers (write-heavy: code out) must not — the fleet's dollars go where the output tokens are.
2. **Tier staircase: Haiku ×2→ Sonnet ×2.5→ Opus ×2→ Fable.** Clean multipliers on both axes; a tier choice multiplies the *whole fleet's* bill with no volume discount.
3. **Sonnet price cliff Sep 1, 2026:** $2/$10 → $3/$15. Any budget quoted today is 50% stale on that date.

## Worked examples

**A. Implementer writing ~2k lines** (~25k output tokens, 15k input):

| Tier | Cost | vs Sonnet |
|---|---|---|
| Haiku | $0.14 | 0.5x |
| Sonnet 5 | $0.28 | 1x |
| Opus 4.8 | $0.70 | 2.5x |
| Fable 5 | $1.40 | 5x — one Fable diff ≈ 4-5 whole Sonnet implementer calls |

Output is ~89% of tokens but ~94% of dollars here — implementer tier choice is where fleet money actually moves. Orchestrator verdicts (400k read, 3k written ≈ $0.83 on Sonnet rates) are noise by comparison even on expensive tiers.

**B. 20-adversary review fan-out** (30k in / 1.5k out each): Haiku $0.75 · Sonnet $1.50 · Opus $3.75 · Fable $7.50. At 20-wide, per-agent premiums are never worth it — run Sonnet lenses and reserve Opus for ONE adjudication call over disagreements.

**C. Caching honesty.** Break-even: 1 reuse (5m cache) or 2 reuses (1h). Always cache the shared prefix (agent system prompt, rubric, SPEC) in fan-outs ≥2. But savings are bounded by the shared fraction: if each agent's unique payload (its diff/files) dominates input, caching the prefix saves ~20%, not 5x. Cache pays hugely only when the shared block dominates.

## Escalation economics

- **Sonnet → Opus for one worker** is justified when the expected cost of a Sonnet mistake on *that call* exceeds 2.5x — realistically: no oracle to catch it cheaply, or blast radius spans many files before any gate fires.
- **Effort inflection:** a Sonnet worker pushed to max thinking effort can out-spend Opus at normal effort for similar quality — if a unit needs that much reasoning, move the unit to Opus rather than inflating Sonnet's thinking budget.
- **Fable/Mythos:** priced for rare single high-stakes calls. As a fan-out tier it is a 5-10x multiplier with zero fan-out discount. The orchestrator seat (this conversation) is the only place it belongs in a fleet.
- **Tokenizer note:** Sonnet 5 / Opus 4.7+ / Fable use a tokenizer yielding ~30% more tokens per unit of text than Sonnet-4.6-era models — compare cost per task, not per MTok, across generations.
