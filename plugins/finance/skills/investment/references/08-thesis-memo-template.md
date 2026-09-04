---
name: thesis-memo-template
description: Canonical thesis memo format for the final output. Fill in placeholders during Stage 6. Designed against best practices from Klarman, Ackman, Buffett, Greenlight, VIC, and Mauboussin.
---

# Thesis Memo Template

Use this exact structure when producing the final output. Replace `{...}` placeholders. Keep memo under 3 printed pages (~1,500 words) — Klarman/VIC style, not sell-side bloat.

---

# {COMPANY NAME} ({TICKER}) — Investment Thesis

**Date**: {YYYY-MM-DD}
**Conviction Score (CS100)**: {SCORE} ±{DISPERSION}  ({tier: Strong Buy / Buy / Hold / Pass})

> **One-line summary**: {15-25 word elevator pitch — what's this and why now?}

> **Disclaimer**: This is not financial advice. The frameworks below have historical academic backing but offer NO guarantee of forward performance. Markets are uncertain. Verify every number before acting. Past performance does not predict future results.

---

## Conviction Breakdown

| Component | Score | Weight | Contribution |
|-----------|-------|--------|--------------|
| Quality bundle | {0-100} | {%} | {pts} |
| Value bundle | {0-100} | {%} | {pts} |
| Momentum | {0-100} | {%} | {pts} |
| Sector adjustment | — | — | {±15} |
| Macro regime tilt | — | — | {±5} |
| Special-situation multiplier | — | — | {×1.x} |
| **CS100 Total** | | | **{SCORE} ±{DISPERSION}** |

**Stock-type classification**: {Compounder / GARP / Cyclical / Financial / Special-Situation / Deep Value Turnaround}

**Disagreement flag**: {Yes/No — if Yes, explain which bundle disagrees and what it might signal}

---

## Business (2-Minute Monologue)

{In ~150 words, plain English, describe:
- What the company does (revenue source, customer, unit economics)
- Why it's a good business (moat type, ROIC level, durability evidence)
- How it makes money (gross margin, operating margin, capital intensity)
- Key facts a 10-year-old could understand}

**Key metrics snapshot** (TTM):
- Market Cap: ${X}B
- Revenue: ${X}B (CAGR 5y: {X}%)
- Operating Margin: {X}% (5y trend: {improving/stable/declining})
- ROIC: {X}% (peers: {X}%)
- Net Debt / EBITDA: {X}x
- FCF Yield: {X}%

---

## Variant Perception — The Steinhardt Question

**What does the market currently believe about {COMPANY}?**
{Articulate the consensus in 1-2 sentences}

**Why is the market wrong (or what is being missed)?**
{The "variant perception" — the specific thing the framework analysis surfaces that consensus underweights. This is the alpha source. If you can't articulate it, the thesis is weak.}

**Mauboussin check**: Have I avoided the "outside view fallacy"? Base rate for {claimed outcome} is {X}% across {large-cap stocks / sector / size cohort}. My estimate of {X}% implies I believe this company is in the {top decile / median / bottom decile} of the reference class. Justified because: {non-trivial reasoning}.

---

## Valuation — 3 Scenarios

Fixed weighting: 20% bear / 60% base / 20% bull. Total expected value computed below.

| Scenario | Probability | 3-Year Target Price | Implied Return | Key Assumptions |
|----------|-------------|---------------------|----------------|-----------------|
| Bear (5-10th percentile) | 20% | ${X} | {±X%} | {Margin compression to X%, growth slows to Y%, multiple compresses to Z×} |
| Base (50th percentile) | 60% | ${X} | {+X%} | {Status quo + modest growth} |
| Bull (90-95th percentile) | 20% | ${X} | {+X%} | {Margin expansion, growth acceleration, multi-baggers from secular tailwind} |

**Expected Value = 0.2 × Bear + 0.6 × Base + 0.2 × Bull = ${X}**
**Current Price**: ${X}
**Upside / Downside Asymmetry**: {(Bull − Current) / (Current − Bear)} = {X:1}

**Reverse-DCF Cross-Check**: At current price ${X}, the market implies {X}% 10-year FCF CAGR.
- Historical 5y FCF CAGR: {X}% — {market expects acceleration / continuation / deceleration}
- Sector median 10y growth: {X}%
- Mauboussin base rate for {large-cap} {X}-year {X}% CAGR: {X}% probability
- Verdict: {Reasonable / Stretched / Priced for perfection}

---

## Catalyst Table

| # | Catalyst | Type | Probability | Magnitude | Time-to-Event | Evidence |
|---|----------|------|-------------|-----------|---------------|----------|
| 1 | {Primary catalyst} | {Earnings/Capital/Activist/etc.} | {%} | {% upside} | {months} | {source} |
| 2 | {Secondary} | | | | | |
| 3 | {Optional tertiary} | | | | | |

**Composite Catalyst Score (0-125)**: {SCORE} → Position Size Multiplier: {0.5x to 2.0x}

---

## Pre-Mortem — Three Things That Could Break This Thesis in 18 Months

### Risk 1: {Specific quantifiable trigger}
- **Trigger condition**: {exact metric and threshold}
- **Probability**: {%}
- **Impact if fires**: {% stock price decline}
- **We invest anyway because**: {non-trivial rebuttal — must be more than "we don't think it will happen"}

### Risk 2: {Specific quantifiable trigger}
{Same structure}

### Risk 3: {Specific quantifiable trigger}
{Same structure}

**ESG / Geopolitical overlay**: {1-2 sentences on material sustainability or supply-chain risks if applicable; "N/A" if not material}

---

## Position Size

**Recommended Position Size**: {X}% of equity portfolio (= ${X} of ${X} total portfolio)

Computation:
- Expected annual return (μ): {X}%
- Realized 3y volatility (σ): {X}%
- 10Y Treasury rate (r): {X}%
- Raw Kelly f* = (μ − r) / σ² = {X}%
- Half-Kelly applied: {X}%
- Catalyst multiplier ({Y}/125 → ×{Z}): {X}%
- Capital scale ({range}): ×{Z}
- Temperament ({user response}): ×{Z}
- **FINAL: {X}%** (capped at 25% single-position rule)

---

## Entry Zone

**Maximum Entry Price**: ${X} (= 1.{0X}× current price — discipline rule)

**Tranching plan** ({type tier}):
- **Tranche A (now, 50% of target)**: Buy at market or limit ${X}
- **Tranche B (-7% OR within 60 days, +25%)**: Trigger at ${X} OR after {date}
- **Tranche C (-15% OR after Q+1 confirms thesis, +25%)**: Trigger at ${X} OR after {next earnings date}

**Buying urgency**: {Low / Medium / High — based on catalyst timing}

---

## Sell Rules — Written At Entry

**Mandatory exit triggers** (any fires → exit within 30 days):
1. ROIC < WACC for 2 consecutive years
2. Gross margin trend -300bps over 4 rolling quarters
3. Customer concentration > 30% (new)
4. Insider cluster selling (3+ CEO/CFO outside historical pattern)
5. Dividend cut (if applicable — REIT/util/financial)
6. Pre-mortem trigger condition fires (then reassess within 72 hours)

**Valuation extreme**:
- Trim to half position at top 5% historical valuation
- Full exit at top 0.5% historical (Tesla 2021-level)

**Opportunity cost**: Switch only if alternative CS100 +15 points after risk adjustment.

**Concentration**: Trim back to 15% if position becomes >20% of portfolio.

**Time check**: This thesis assumes {X}-year payoff. If unrealized after {X×1.5} years, reassess from scratch.

---

## Tracking Plan

Monitor quarterly (and within 48 hours of any event below):

| Metric | Current | Target Range | Re-evaluate If |
|--------|---------|--------------|----------------|
| Revenue growth | {X}% | {X-Y}% | < {X}% for 2 quarters |
| Operating margin | {X}% | {X-Y}% | < {X}% for 2 quarters |
| Net debt / EBITDA | {X}x | < {X}x | > {X}x |
| ROIC | {X}% | > {X}% | < WACC for 1 year |
| Insider transactions | Baseline | Cluster buying = positive | 3+ insider sells outside pattern |

**Event triggers** (reassess within 48 hours):
- Quarterly earnings (always)
- 8-K filing
- Pre-mortem trigger fires
- Sector regime shift
- 13F filing (top holders changed)
- Index addition/deletion announcement

**Next scheduled reassessment**: {date — default 90 days; sooner if catalyst within that window}

---

## Sources & Data Verification

- Financial data: {Yahoo Finance + SEC EDGAR cross-check, dated {YYYY-MM-DD}}
- Last 10-K: {YYYY-MM-DD}
- Last 10-Q: {YYYY-MM-DD}
- Insider transactions: SEC Form 4 through {YYYY-MM-DD}
- 13F holdings: SEC Form 13F as of {YYYY-MM-DD}
- Macro data: FRED as of {YYYY-MM-DD}
- All numbers verified against SEC primary source where possible (yfinance data shift bug acknowledged)

---

## Footer

This is not financial advice. The frameworks applied have documented historical performance but offer no forward guarantee. Markets are uncertain. Verify all numbers independently. Consult a fiduciary advisor for advice tailored to your full financial situation. Past performance does not indicate future results. The user owns every decision made on the basis of this analysis.

**Pipeline version**: investment-skill v1.0
**Picks log entry**: appended to ~/.cache/investment-skill/picks-log.jsonl
**Next reassessment**: {date}
