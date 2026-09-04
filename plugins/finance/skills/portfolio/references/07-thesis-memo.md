---
name: portfolio-output-templates
description: Canonical templates for the per-name thesis memo, the portfolio construction report, and the recurring review report (including the quiet no-action weekly log). Load when rendering output at the end of BUILD or REVIEW. Do NOT load during research, scoring, or sizing.
---

# Output Templates: Thesis Memo, Construction Report, Review Report

## A. Per-name thesis memo

```
# {TICKER} ({Company Name}) — Investment Thesis

**One-line summary**: {15-25 words — what this is, why now}

**Conviction tier**: {Highest / Baseline / Lower} — {1-2 sentences: the
qualitative factors that placed it here — thesis strength, payoff
asymmetry, valuation cushion, business resilience. No numeric
expected-return input.}

## Business
{~100 words plain English: revenue source, customer, unit economics,
moat type and mechanism, margin structure, capital intensity.}

## Variant Perception
**Consensus believes**: {1-2 sentences — what the market currently
prices in}
**This thesis says that's wrong because**: {the specific, falsifiable
gap between consensus and this view — the alpha source. If this can't
be articulated, the thesis is not ready.}

## Return Decomposition (expected, 1-5yr)
| Component | Contribution | Basis |
|---|---|---|
| Dividend yield | {X%} | {payout policy, observable} |
| Per-share FCF/EPS growth (dilution-adjusted) | {X%} | {unit economics, forecastable} |
| Multiple change | {±X%} | {re-rating case, if any} |
| **Total expected return** | **{X%}** | |

**Multiple-expansion flag**: {if multiple change is >~1/3 of total —
STATE EXPLICITLY: "this thesis requires re-rating to work, the
structurally weakest and least persistent component." Otherwise: "works
at flat-or-lower exit multiple."}

## ROIC Fade Assumption
**Current ROIC**: {X%} vs. **sector norm fade rate**: {qualitative:
roughly a fifth to a third of excess ROIC erodes per year, sector-
dependent — illustrative magnitude, not a computed constant}
**This thesis assumes**: {X%/yr fade, or "reverts to cost of capital by
year N"}
**If below sector-norm fade** (i.e. assumes ROIC persists longer than
typical): {mandatory justification — named mechanism: switching costs,
network effects, regulatory barrier, structural scale advantage. Never
"management is good" or brand strength alone.}

## Reverse-DCF Cross-Check
At current price, market implies: {X%/yr growth or margin path over N
years}
**Defensible?**: {Yes/No/Stretched} — against company's own historical
range, sector growth rates, TAM ceiling. {1-2 sentences.}

## Cluster Membership
**Cluster**: {name} — shared driver: {end-market / customer-supplier
node / macro sensitivity / regulatory-geopolitical single point of
failure}. Co-members: {other tickers in this cluster, if any}.

## Target Weight
**Weight**: {X%} — **binding constraint**: {per-name floor (~5%) /
per-name cap (~20-25%) / aggregate cluster cap (~50-60%) / conviction
tier tilt / lot-size non-expressibility (see 08-multi-currency §2) —
name exactly which one set the final number, not just the tier}

## Pre-Registered Invalidation Condition
**Written in FUNDAMENTAL terms — never a price-percentage.** A price
stop induces momentum-trading behavior; this book does not do that.
{e.g. "Gross margin below X% for 2 consecutive quarters" / "Customer
concentration exceeds X%" / "ROIC below WACC for 2 consecutive years" —
must be a specific, checkable metric and threshold, not "if it goes
down a lot."}

## Top Ways This Thesis Is Wrong
1. **{Risk}** — trigger: {specific metric/event}. Response: {planned
   action, not "we'll reassess"}.
2. **{Risk}** — {same structure}.
3. **{Risk, optional}** — {same structure}.

## Why the Bessembinder Right Tail
{Only ~4% of stocks historically drove all net market wealth creation;
most stock-picking, applied without edge, lands on the majority that
lags cash over long horizons. State explicitly why THIS name —
specific mechanism, not "good business" — belongs in that minority
rather than the majority. If this can't be stated concretely, that is
itself a signal to lower conviction tier.}
```

## B. Portfolio construction report

```
# Portfolio Construction — {YYYY-MM-DD}

## Weights
| Ticker | Weight | Cluster | Conviction Tier | Currency | Shares | Binding Constraint |
|---|---|---|---|---|---|---|
| {TICKER} | {X%} | {cluster} | {tier} | {ccy} | {N} | {constraint from memo §Target Weight} |
{... one row per name, 5-10 total}

## Cluster Map
| Cluster | Members | Aggregate Weight | Shared Driver |
|---|---|---|---|
| {name} | {tickers} | {X%} | {driver} |

Aggregate cluster cap: ~50-60%. {Confirm no cluster breaches this
independently of per-name caps.}

## Cash Sleeve
**Size**: {X%} — **policy**: {liquidity need / drawdown tolerance / add
capacity — state which}. **This is NOT a market-timing view** — dry
powder for a "better entry" lacks reliable empirical support and is
explicitly disclaimed as a forecasting bet. Kept separate from any
rounding-residual cash (§ below).

## Concentration Disclosure
A {N}-name book deliberately forgoes idiosyncratic diversification that
a 20-30+ name portfolio would carry. **Trade-off stated explicitly**:
concentration is the mechanism by which conviction can matter at all;
its cost is that a single wrong thesis moves the whole book materially
more than in a diversified sleeve. This is a deliberate design choice,
not an oversight.

## Reconciliation Gate Results
| Ticker | Yahoo Price (major units) | IBKR Price | Delta | Gate |
|---|---|---|---|---|
| {TICKER} | {price} | {price} | {X%} | {PASS / HARD STOP} |

Any HARD STOP blocks that name's draft instruction until resolved —
never averaged or waved through (see 05-ibkr-handoff.md §3).

## Draft Instructions
| Ticker | Side | Quantity | Order Type | Limit Price | Deep-Link |
|---|---|---|---|---|---|
| {TICKER} | {BUY/SELL} | {N} | {LIMIT/MARKET} | {price} | {URL} |

**These are DRAFT instructions, not live orders.** Each requires the
user's own review and submission inside IBKR before any trade executes.
This report's authority ends at drafting.
```

## C. Review report

Cadence-aware — pick the block matching the run.

### Weekly — deliberately minimal ("no action" is the expected outcome)

A quiet weekly pass is success, not a null result to explain away.
Padding it to look busy manufactures pressure to find something on the
next pass. Keep this to a few lines:

```
# Weekly Review — {YYYY-MM-DD}

Scanned: {N} positions, hard drift bands, named event triggers, idle
cash check.
Fired: {None / list any hard-band breach or named trigger}.
Action: {No action, logged. / Mechanical trim on hard-band breach:
{ticker}, {detail}.}
Next scheduled action: {date — next weekly, or escalation if flagged}.
```

If something fired, expand only that item using the Monthly/Quarterly
structure below — do not inflate the rest of the log to match.

### Monthly / Quarterly — fuller

```
# {Monthly/Quarterly} Review — {YYYY-MM-DD}

## Drift
| Ticker | Target Wt | Actual Wt | Drift | Local Return | FX Return | Band |
|---|---|---|---|---|---|---|
| {TICKER} | {X%} | {X%} | {±X pp} | {r_local} | {r_fx} | {within / soft / hard} |

NAV reconciliation vs. IBKR reported NAV: {PASS / FLAG, delta X%}.
Cash weight: {X%} ({policy sleeve} + {rounding residual}).
FX concentration by currency: {ccy: X%, ...} — {flag if one currency
>60-70% of NAV with no conviction driving it}.

## Thesis Re-affirmations (quarterly only, or monthly if material)
| Ticker | Last Reviewed | Verdict | Notes |
|---|---|---|---|
| {TICKER} | {date} | {Affirmed / Watch / Invalidation pillar broke} | {1-2 sentences, tie back to the memo's pre-registered condition} |

## Flagged Items
{List anything requiring judgment: soft-band breach, event-driven
interrupt, cooldown status, candidate flagged for next BUILD cycle. "No
items flagged" is a valid, complete entry.}

## Actions Taken This Cycle
{Trim / add / exit, each with the fundamental (not price-%) reason and
which evidence bar it cleared. "None" is valid for monthly.}

Next scheduled action: {date}.
```
