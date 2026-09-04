---
name: portfolio-autonomy-communication
description: The autonomy ladder, standing-preferences schema that stops the skill re-asking settled questions, and the explanation standard for reporting to a financially literate owner. Load at the start of any run that will produce output or ask the user a question. Do NOT load for pure data-fetch stages.
---

# Autonomy and Communication

## Part 1 — The Autonomy Ladder

**The architectural ceiling is fixed.** `create_order_instruction` produces a reviewable IBKR
deep-link, never a live order — the human submits inside IBKR. No autonomy setting raises this
ceiling. This is a feature: it is the one control that cannot be configured away, escalated
past, or eroded by a self-tuning loop (06-agent-guardrails.md §7).

What varies is everything *before* that ceiling — how much the skill decides on its own versus
surfaces for a decision. Three levels, stored in `preferences.json` (Part 2):

| Level | Name | Model |
|---|---|---|
| 1 | Consult | Proposes, asks before each substantive step |
| 2 | **Draft** (recommended default) | Researches, decides, drafts autonomously; reports; asks only at a genuine fork |
| 3 | Standing mandate | As Level 2, plus acts on pre-agreed mechanical rules without asking |

### Level 1 — Consult

| May do without asking | Must always ask |
|---|---|
| Fetch data, compute scores, run the adversary pass, log | Which candidates to research further; how to size; whether to trim, add, exit, or draft an instruction — every substantive step |

### Level 2 — Draft (recommended default)

| May do without asking | Must always ask |
|---|---|
| Full research and scoring; hard-band mechanical trims (lowest evidence bar per 03-review-doctrine.md); drafting instructions for any action that already clears its evidence bar; watchlist/report generation | A genuine fork requiring owner judgment: a borderline reconciliation-gate delta, a finding that implies a new exclusion, a discretionary add/trim where the evidence bar is cleared but more than one reasonable response exists |

### Level 3 — Standing mandate

| May do without asking | Must always ask |
|---|---|
| Everything at Level 2, plus acting on pre-agreed mechanical rules with no per-instance confirmation: hard-band trims, cash deployment into existing targets per the stored deployment style (10-cash-deployment.md) | Initiating a name not previously underwritten; a full exit; breaching any hard-locked ceiling; anything the reconciliation gate failed on |

**These four always require the owner, at every level, with no exception a preference can
grant:**

| Always requires the owner | Why |
|---|---|
| A name not previously underwritten | Full BUILD underwriting bar — a review may only *flag* a candidate, never originate a buy |
| A full exit | The highest evidence bar in the review doctrine — a written, dated, durable pillar-break |
| Breaching any hard-locked ceiling | Hard-locked by design (06-agent-guardrails.md §7) — not tunable by any loop, including this one |
| Anything the reconciliation gate failed on | Hard stop by design (05-ibkr-handoff.md) — never averaged, never waved through |

Level 3 does not weaken these; it only removes asking for the mechanical middle where the
review doctrine already supplies the judgment (hard-band math, deployment-style math) instead
of the skill supplying it live.

### What actually reduces the owner's workload

It is **not** a higher autonomy number. Raising the level without the three items below just
moves the same volume of questions from "every run" to "every run that hits a fork" — real, but
marginal. The actual leverage is:

1. **Standing preferences persisted once** (Part 2) — the skill stops re-asking questions it
   already has dated answers to.
2. **A silent default** — most weekly runs should produce "no action, logged" and a few lines,
   not a decision request. This is the review doctrine's Prime Directive (03-review-doctrine.md)
   applied to the owner's inbox, not just the trade blotter.
3. **Scheduled invocation** — the owner should not have to remember to run this. A cron-style
   trigger firing the weekly hazard-scan removes the last manual step.

## Part 2 — Standing Preferences Schema

`preferences.json` lives in `~/.cache/portfolio-skill/` alongside `portfolio.json`,
`decision-log.jsonl`, `thesis-registry.json`, and `fx-cache.json`, and is persisted the same way
— via `scripts/state.sh load` / `save` to the `portfolio-state` branch, because the scheduled
routine runs in a fresh, wiped container every week.

```jsonc
{
  "autonomy_level": 2,                 // 1 | 2 | 3 — Part 1
  "base_currency": "EUR",
  "tax_jurisdiction": "IS",             // ISO country code — never assume US rules
  "drawdown_tolerance": "moderate",     // qualitative band, defined once with the owner
  "exclusions": { "sectors": [], "regions": [] },
  "target_name_count": 7,               // within the hard 5-10 band — a preference, not an override
  "cash_sleeve_target_pct": 5,
  "share_price_ceiling": null,          // max per-share price expressible at current NAV; null = no ceiling set
  "lot_constrained_markets_included": true,  // Japan/HK local board-lot lines in scope or not
  "deployment_style": {
    "mode": "staged",                   // "lump_sum" | "staged"
    "reason": "regret minimization — lump-sum has the better expected outcome; staged is the owner's explicit trade for lower realized regret on a bad first print"
  },
  "last_confirmed": "2026-01-15"
}
```

**The rule that makes this useful**: every run reads `preferences.json` first and does not
re-ask anything it already answers. Re-confirmation is triggered only by:

| State | Behavior |
|---|---|
| **Missing** (no file, first run) | Treat as BUILD-mode context elicitation — ask once, in full, then write the file with today's `last_confirmed`. This is the one allowed full questionnaire. |
| **Stale** (`last_confirmed` older than 12 months — reasoned default, expose as configurable) | Do not re-run the full elicitation. Ask one compact confirmation ("these are still your settings — unchanged?"); on silent confirmation, stamp today's date and continue. Only re-ask fields the owner actually changes. |
| **Contradicted** (this run's findings directly conflict with a stored preference — e.g. a candidate sits in an excluded sector, or NAV growth has structurally invalidated the share-price ceiling) | Never silently override and never silently keep the stale preference either. Surface the specific contradiction as a flagged item and ask about *only* that field — not a full re-elicitation. |

A preference that is merely old but unconfronted by anything the run found is not stale enough
to interrupt the owner — it is stale enough to passively re-confirm at the next natural
touchpoint (quarterly, per the staleness interval above).

## Part 3 — The Communication Standard

The owner is financially literate. Explaining basics to a competent reader is condescending and
spends attention that belongs on the actual decision.

**Assume the reader knows, and never explain**: P/E, free cash flow, ROIC, market cap, dividend
yield, a balance sheet, diversification, volatility, a limit order.

**Always explain**: the *reasoning* (why this name, why this weight, why now), the
*uncertainty* (what would make this wrong, how confident the skill actually is), and any
genuinely non-standard or skill-specific term the moment it is used — cluster cap, fade rate,
reverse-DCF as used here, conviction tier, binding constraint. These are defined in full in
01-horizon-signals.md and 02-construction-sizing.md; a report may use them but must gloss them
in one clause on first use per report, not assume the definition travels.

**Concrete rules:**

- **Lead with the decision, then the evidence.** Not a narrative building to a conclusion.
- **Every number carries its unit and currency.** A bare number in a multi-currency book is an
  error, not a style choice (see the GBp trap, 04-global-data.md).
- **State confidence explicitly**, and distinguish a computed figure from an estimate from a
  judgment call.
- **Never use false precision.** A weight to one decimal implies precision the inputs — tiered
  conviction, not optimization — do not have.
- **Name the binding constraint** when explaining a size: "this is 8% because the cluster cap
  bound, not because conviction was low."
- **Say what would change the answer.** A thesis without an invalidation condition is a story,
  not an analysis.
- **No hedging theater.** Do not bury a clear recommendation under qualifiers, and do not
  manufacture false balance where none exists. State the view, then its risks — in that order.
- **Report bad news first and plainly.** A drawdown, a failed gate, or a thesis break leads the
  report; it is never buried under what went well.

### Worked contrast

**Badly written:**
> ASML is looking strong right now — great momentum lately and sell-side sentiment is bullish.
> We're comfortable holding at the current size given the recent run; it could keep going from
> here, though of course there's always risk in individual names so it's worth keeping an eye
> on. The position is up about 40 points since initiation, which feels good, and weight has
> drifted to roughly 12%ish of the book — that seems about right for now, but we might trim if
> things get frothy.

Momentum used as *positive* evidence (wrong sign at this horizon — 01-horizon-signals.md); no
currency on "40 points"; no binding constraint for "12%ish"; no invalidation condition; "worth
keeping an eye on" and "might trim if things get frothy" are hedging theater, not a stated view.

**Well written:**
> Hold ASML at 12% (unchanged) — below the ~20-25% per-name cap, above the ~5% floor; no
> binding constraint moved this cycle, so no rebalancing action is warranted. Since initiation:
> +€340/share locally, EUR position value +9.4% (local price +11.2%, EUR/USD drag -1.8pp) — a
> fundamentals-driven gain, not an FX artifact. Confidence: Baseline tier, unchanged. Recent
> 12-month price strength is not treated as supporting evidence at this horizon. Thesis
> re-verified this quarter (FETCHED, filing dated 2026-04-22): EUV/DUV lithography position and
> semicap capex cyclicality both intact. Invalidation condition unchanged and not triggered:
> gross margin below 48% for two consecutive quarters, or a credible second-source EUV
> competitor announcement. This view would be wrong if China export-control easing accelerated a
> competitor's catch-up timeline — assessed Low probability within the hold horizon, not zero.

### Anti-patterns — communication specifically

| Anti-pattern | Mechanism |
|---|---|
| Explaining P/E, ROIC, or "what a limit order is" to the owner | Wastes a competent reader's attention; signals the skill doesn't know its audience |
| A weight reported to one decimal (e.g. 12.3%) | False precision — the sizing engine is tiered conviction, not continuous optimization; the decimal claims accuracy the inputs never had |
| A number with no currency in a multi-currency book | Silently conflates GBp/GBP/USD/EUR — the exact 100x trap this skill exists to prevent (04-global-data.md) |
| "Consider trimming" with no named constraint | Owner cannot tell whether a hard-band rule fired or the skill is guessing |
| A thesis with no invalidation condition | Unfalsifiable narrative — cannot be graded later against the accountability log (06-agent-guardrails.md §8) |
| Six qualifiers wrapped around a clear call | Hedging theater — forces the owner to reverse-engineer what the skill actually thinks |
| Good news first, bad news mentioned in passing | Reorders attention away from what the owner most needs to act on first |
