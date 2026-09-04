---
name: sell-rules
description: The 9 explicit sell rules with quantifiable triggers. Used by the thesis memo to spell out exit conditions at entry. Load when generating the sell-rules section of the thesis memo.
---

# Sell Rules — The 9-Rule Discipline

Most retail (and many professional) investors have zero codified sell discipline. They sell winners too early and losers too late (disposition effect — Shefrin-Statman 1.5-2x empirically demonstrated).

**Core principle**: Sell rules are written in FUNDAMENTAL terms (ROIC < WACC for 2 consecutive years), not price-percentage terms (down 20%). Price-based stops induce momentum-trading behavior; fundamental triggers preserve thesis discipline.

**The three valid reasons to sell** (Mauboussin / Marks):
1. **Thesis broken** — durable operating change
2. **Opportunity cost** — better risk-adjusted return available elsewhere
3. **Overvaluation extreme** — top 0.5% historical outcomes priced in

## Rule 1 — Thesis Break (5 sub-triggers, MANDATORY exit within 30 days)

Mark any of the following:
1. **ROIC drops below WACC for 2 consecutive years**, indicating value destruction.
2. **Gross margin trend** declines >300bps over rolling 4 quarters (signals lost pricing power).
3. **Market share loss** in core segment (vs sector growth) for 3+ consecutive quarters.
4. **Customer concentration** rises (top 1-3 customers > 30% of revenue if not previously the case).
5. **Capital allocation reversal**: company starts large M&A spree below historical ROIIC standard.

If ≥1 fires AND the operating change appears durable (not a 1-quarter blip), mandatory exit within 30 days. No exceptions, no "let me give it one more quarter."

## Rule 2 — Opportunity Cost

Sell ONLY if ALL of the following simultaneously:
- A new opportunity has CS100 score ≥ 15 points higher than current holding (risk-adjusted)
- The new opportunity passes all framework hurdles
- Tax cost of exit < expected outperformance × time-to-thesis-completion
- The new opportunity has sufficient liquidity for the position size

[SURPRISING] This is RARE. Marks "Selling Out": "Most opportunity-cost sells are made up by an outperforming hold."

## Rule 3 — Overvaluation Extreme (two-tier)

Compute reverse-DCF: given current price, what implied 10-year FCF CAGR does the market need?

| Tier | Implied CAGR vs Base Case | Action |
|------|--------------------------|--------|
| Stretched | +50% vs reasonable base case | Trim to half position |
| Top 5% historical | Implied CAGR exceeds 95th percentile of large-cap 10y CAGRs (Mauboussin base rate) | Trim to 1/3 position |
| Top 0.5% historical | Implied CAGR exceeds 99.5th percentile (Tesla 2021 territory) | Full exit |

Reverse-DCF cross-check: if implied CAGR is structurally impossible (>30% for non-tech, >40% for tech-with-revenue, >50% for any biotech), full exit regardless of momentum.

## Rule 4 — Pre-Mortem Trigger Fires

At entry, write 3 specific things that could break the thesis in 18 months. Examples:
- "AI-disruption thesis breaks if competitor X reaches 50% of customers within 12 months"
- "Margin expansion thesis breaks if input cost X rises >25%"
- "Network effect thesis breaks if engagement metric Y declines for 3 consecutive quarters"

If a pre-mortem trigger fires, **mandatory reassessment within 72 hours**. Not automatic exit — but explicit reassessment, documented decision (continue / trim / exit).

## Rule 5 — Insider Cluster Selling (3-tier)

Per Wave 1 Insider research, MOST insider selling is noise (10b5-1 plans, taxes, diversification). The exceptions:

| Pattern | Signal | Action |
|---------|--------|--------|
| Routine 10b5-1 plan execution | Noise | No action |
| 1-2 insiders selling on schedule | Yellow flag | Note and monitor |
| 3+ insiders selling, especially CEO+CFO, outside historical pattern, multi-month cluster at multi-year highs | RED FLAG | Trim 25-50% |
| Founder-CEO unloading material % of holdings | RED FLAG | Reassess thesis from scratch within 7 days |

Use Cohen-Malloy-Pomorski "opportunistic" filter (Code S transactions outside historical Form 4 pattern) — this is the high-signal subset.

## Rule 6 — Dividend Cut (especially REITs / utilities / financials)

Dividend cut is one of the strongest leading indicators of underlying business deterioration. Empirical: REITs/utilities that cut dividends underperform for 2+ years even after the cut.

**Action**: On dividend cut announcement, full exit within 5 trading days unless there's compelling evidence the cut is one-time (e.g., regulatory + recovery clearly visible). Default action = sell.

Pre-cut warning signs (sell BEFORE the cut):
- Payout ratio > 80% AND FCF coverage < 1.1x
- Management language shifts from "we are committed to the dividend" to "we will evaluate the dividend"
- Credit downgrade
- Bond yield > dividend yield × 1.5

## Rule 7 — Tax-Aware Selling

- **Long-term vs short-term**: Wait for 366-day holding period IF possible without violating other rules. The 20pp+ tax delta is large.
- **Wash sale rule**: Cannot deduct loss if substantially identical security is repurchased within 30 days before or after. Plan accordingly.
- **IRA trap** [SURPRISING]: Wash sale rules apply across taxable AND IRA accounts. A sale in taxable + repurchase in IRA within 30 days disallows the taxable loss permanently. Most retail investors don't know this.
- **Tax-loss harvesting**: At year-end, sell losers for tax benefit IF you can replace with non-substantially-identical exposure (sector ETF substitute) for 31 days.

## Rule 8 — Quarterly Reassessment Cadence

Every 90 days (or sooner on event triggers — see below), run 3-question protocol:
1. Has any fundamental input to the thesis changed materially?
2. Has the implied-CAGR (reverse DCF) moved into a less attractive zone?
3. Are there better opportunities right now?

Event triggers that ACCELERATE the cadence (reassess within 48 hours):
- Earnings report (especially if guide cut)
- 8-K filing (material events)
- Pre-mortem trigger fires
- Sector-wide regime shift (rate move, war, regulatory)
- 13F filing showing major holder exit

## Rule 9 — Concentration Rebalancing

If a winner becomes > 20% of total portfolio, trim back to 15% (re-anchor) regardless of thesis quality.

Reasoning: ALL fundamentals can be wrong. Concentration risk compounds asymmetrically. Even Buffett trims concentration over time (e.g., Apple from 50% to 30%+ over 2023-2024).

**Tax-lot selection**: When trimming, sell the highest-cost-basis lots first (minimize taxable gain).

## What is NOT a sell rule

- "Stock down 10%" — not a reason to sell. Could be the best buying opportunity.
- "It's been a long time" — time alone is not a thesis change.
- "I need the cash" — not a thesis sell; that's a portfolio sell, different category.
- "My friend told me X" — not a thesis input.
- "The market is overvalued" — could affect new buys, doesn't force exits of existing holdings.
- "I want to lock in gains" — disposition effect; let winners run unless rule 3 fires.

## Pre-Mortem Worksheet (write at entry, store with thesis memo)

```
PRE-MORTEM — 3 things that could break this thesis in 18 months:

1. [Specific quantifiable trigger]
   Trigger fires when: [exact condition]
   Action if fires: [reassess / trim / exit]
   We invest anyway because: [non-trivial rebuttal]

2. [Specific quantifiable trigger]
   ...

3. [Specific quantifiable trigger]
   ...

EXIT CHECKLIST — fundamental triggers that mandate exit:
- ROIC < WACC for 2 consecutive years: EXIT WITHIN 30 DAYS
- Gross margin trend -300bps in 4 rolling quarters: REASSESS
- Customer concentration > 30% (new): REASSESS
- Insider cluster selling 3+ CEO/CFO outside pattern: TRIM 25-50%
- Dividend cut (REITs/utilities/financials): EXIT WITHIN 5 DAYS
- Implied CAGR reaches top 0.5% historical: EXIT
- Better opportunity with CS100 +15: CONSIDER SWITCH

TIME CHECK: This thesis assumes [X years to play out]. If unrealized in [X+50% years], reassess from scratch.
```

## Anti-Patterns

- **"I'll sell when it gets back to even"** — Odean's data: stocks that fall and you hold "to get back to even" underperform by 3.4%/yr. Decision should be: would I buy at the current price? If no, sell.
- **"Just one more quarter"** — Especially dangerous when thesis is clearly breaking. Set the exit trigger, honor it.
- **Stop-losses on quality compounders** — Marks's explicit skepticism. Whipsaws cost more than they save for genuinely durable businesses.
- **Pyramiding into losers** — Adding to a position on the way down without RESET of thesis is "averaging into a thesis break." Different from rational tranching at entry.
