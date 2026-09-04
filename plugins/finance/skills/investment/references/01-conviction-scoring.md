---
name: conviction-scoring
description: CS100 conviction-score formula with 5 stock-type weight buckets, sector and regime adjustments, and special-situation multipliers. Load before any conviction computation.
---

# CS100 — The Conviction Score

CS100 is a 0-100 conviction score for a stock-pick. It synthesizes three orthogonal bundles (Quality, Value, Momentum), routed by stock-type bucket because equal weights fail on financials, cyclicals at peak, and stocks with no quality floor (verified in Wave 3 stress test against MSFT, INTC, NVDA, JPM, GEV).

**Output as a range, not a point.** Standard dispersion ±5; for edge cases (financials, recent IPOs, structural changes) ±15.

## The Three Bundles

Frameworks are reducible to 3 independent signals (Asness; QMJ-style decomposition):

**Quality bundle** = z-score average of:
- Buffett ROIIC (5-yr ΔNOPAT / 5-yr ΔInvested Capital, threshold > 15%)
- Piotroski F-score (≥ 7 of 9)
- AQR QMJ proxy: avg z-score of (Gross Profit / Total Assets, ROE, earnings stability over 8 quarters, net payout yield)

Map to percentile 0-100.

**Value bundle** = z-score average of:
- Lynch Value Ratio = (forward 5y growth% + dividend yield%) / P/E. Threshold ≥ 2.0.
- Greenblatt EBIT/EV — SECTOR-NEUTRAL percentile only (not absolute screen; Magic Formula post-2010 underperformed).

Map to percentile 0-100.

**Momentum bundle** = 12-1 percentile (price return over months t-12 to t-1, skipping the latest month per Jegadeesh-Titman).

Map to percentile 0-100.

## Stock-Type Routing (5 buckets)

Classification heuristic (apply in order, first match wins):

1. **Financial** if GICS Sector ∈ {Financials, Real Estate} → see sector playbook
2. **Cyclical** if GICS Industry Group ∈ {Materials, Energy, Industrials Capital Goods, Auto, Semis at certain points}, OR if 5-year sales coefficient of variation > 0.25
3. **Special-Situation** if recent (<24mo) spinoff, OR has active 13D filer from top activist (Pershing/Elliott/Trian/Starboard/ValueAct), OR recent S&P 500 deletion
4. **Wide-Moat Compounder** if ROIIC > 15% for 5 consecutive years AND gross margin stability std < 3pp over 5y AND debt/EBITDA < 3
5. **GARP / Growth** if revenue 3y CAGR > 12% AND not classified above
6. **Deep Value / Turnaround** if P/Sales < 1.0 AND ROIC < 6% AND not classified above (the "everything else looking cheap" bucket)

Default if unclassified: GARP.

## Weight Vectors by Bucket

| Bucket | Quality | Value | Momentum | Notes |
|--------|---------|-------|----------|-------|
| Wide-Moat Compounder | 60% | 20% | 20% | Quality dominates; value modest because compounders rarely trade cheap |
| GARP / Growth | 35% | 35% | 30% | The balanced Asness "value + momentum + quality" weighting |
| Deep Value / Turnaround | 20% | 60% | 20% | Value-driven, but Quality FLOOR still applies (see below) |
| Cyclical | 30% | 40% (cycle-normalized) | 30% | EBIT/EV must use 5-7y avg EBIT, not trailing |
| Financial | See sector playbook — frameworks replaced by ROE, P/TBV, CET1, combined ratio, FFO | | | |
| Special-Situation | Base weights from underlying business archetype, then apply ×1.15 multiplier | | | |

## The Quality Floor (mandatory)

**Regardless of bucket**, if a candidate scores < 30 on the Quality bundle (bottom tercile), the maximum CS100 it can achieve is 55. This prevents momentum-driven inflation of fundamentally broken businesses (INTC stress-test failure: ROIC 1.47% but +400% momentum could otherwise score 64).

## Sector Adjustment (±15)

Apply per sector based on macro regime and current sector relative strength:

| Sector State | Adjustment |
|--------------|-----------|
| Strong tailwind + early-cycle | +10 to +15 |
| Tailwind | +5 to +10 |
| Neutral | 0 |
| Headwind | -5 to -10 |
| Strong headwind + late-cycle | -10 to -15 |

In May 2026: Energy +10, Materials +10, Industrials +5, Healthcare 0, Staples 0, Financials -5, Real Estate -10, IT (Mag-7-heavy) -10, Communication Services -10.

## Macro Regime Tilt (±5)

| Regime | Tilt | Reasoning |
|--------|------|-----------|
| Recession (Sahm Rule fired, ISM < 45) | +5 | Best long-term entries are in fear |
| Recovery (ISM crossed 50 upward) | +3 | Early cycle is highest-return phase |
| Mid-cycle | 0 | Standard |
| Late-cycle (CAPE > 30 OR yield curve recently re-normalized after inversion) | -3 | Be more selective |
| Extreme overvaluation (CAPE > 38) | -5 | Klarman discipline — May 2026 territory |

## Special-Situation Multipliers (apply AFTER CS100, cap at ×1.50)

These are EARNED, not granted:

| Trigger | Multiplier | Requirements |
|---------|-----------|--------------|
| Greenblatt-quality spinoff | ×1.15 | All 5 of: management equity alignment, small relative to parent, clean balance sheet, sector-orphan, Days 10-45 entry. Indiscriminate spinoffs do NOT qualify (SPUN ETF lesson). |
| Activist 13D + thesis confirmed | ×1.15 | Filer in top tier (Pershing/Elliott/Trian/Starboard/ValueAct/Engaged/JANA). Thesis-confirmed = our independent analysis arrives at same conclusion as activist letter. |
| S&P 500 DELETION with fundamentals intact | ×1.15 | Index removal causes forced selling; if business is durable, this is an asymmetric opportunity. (Index INCLUSION as buy signal is DEAD per Greenwood 2022.) |
| Cohen-Malloy-Pomorski opportunistic insider cluster | ×1.15 | 3+ insiders, Form 4 Code P only, outside historical pattern, rolling 90-day window. CFO buys weighted highest. |
| Multiple of the above simultaneously | Stack to cap | Hard cap at ×1.50 cumulative. |

## Disagreement Flag

When one of (Quality, Value, Momentum) is in top 30% but another is in bottom 30%, set `DISAGREE_MAX = True`. The thesis memo MUST explicitly address: which bundle is right? What does this disagreement signal? Examples:
- High Quality, low Value, high Momentum = expensive compounder; thesis must justify pay-up
- Low Quality, high Value, low Momentum = value trap risk; thesis must specify catalyst
- High Quality, high Value, low Momentum = forgotten compounder (rare and valuable); thesis can lean confident
- Low Quality, low Value, high Momentum = momentum-only; usually reject

## Worked Examples (from CS100 Stress Test)

**MSFT (Wide-Moat Compounder):** Q=85, V=25, M=55 → 0.60(85) + 0.20(25) + 0.20(55) = 67. Sector IT -10. Regime -5. CS100 = 52 ±5. Verdict: high quality but premium-priced; on the watch list but not a buy at current valuation. Matches expert view.

**INTC (Deep Value / Turnaround):** Q=8, V=65, M=20 → 0.20(8) + 0.60(65) + 0.20(20) = 44.6. **Quality Floor applies** (Q < 30) → ceiling at 55, so CS100 = 44.6 (below ceiling). Verdict: cheap-looking but quality floor binds; reject. Matches expert "value trap" reading.

**JPM (Financial):** Standard weights DO NOT APPLY. Route to sector playbook: ROTCE 18%, P/TBV 1.8x, CET1 15%, efficiency ratio 56% — all strong. Bank-specific CS100 = 72. Sector Financials -5. Regime -5. Bank-CS100 = 62 ±10. Verdict: good business, fair price, would buy in a -10% pullback.

**NVDA (Cyclical):** Q=88 (peak earnings), V=15 (using trailing EBIT), M=92 → standard would give CS100 = 65. But cycle-normalized using 7-year avg EBIT: V drops to 8. Cyclical-adjusted CS100 = 0.30(88) + 0.40(8) + 0.30(92) = 57. Regime -5. CS100 = 52 ±15. Verdict: cyclical at peak, high uncertainty; reduce position size multiplier to 0.5x. Matches expert wariness.

**GEV (Special Situation — Spinoff):** Base archetype = compounder (utility/AI infra). Q=70, V=40, M=N/A (use 50 — Wave 3 rule: <15mo trading history → momentum defaults to neutral). CS100 = 0.60(70) + 0.20(40) + 0.20(50) = 60. Sector Industrials +5. Greenblatt-quality spinoff filter check → all 5 criteria met → ×1.15 multiplier. Final: 65 × 1.15 = 75 ±10. Verdict: strong conviction spinoff pick.

## Anti-Patterns

- **Do not use absolute Magic Formula rank for screening.** It's dead post-2010 for large/midcap. Use only as sector-neutral relative percentile.
- **Do not skip the Quality Floor.** A stock with broken quality is a value trap even if it's cheap and has momentum.
- **Do not apply equal weights to all stocks.** Stock-type routing is mandatory.
- **Do not stack multipliers above ×1.50.** Concentration of false-positive multipliers is dangerous.
- **Do not report CS100 as a point estimate.** Always include the dispersion.
- **Do not hide the bundle scores in the output.** The thesis memo must show Quality / Value / Momentum separately so the user sees the source of conviction.
