---
name: macro-regime-2026
description: Current macro regime read (as of May 2026) and adjustment rules. Reload at start of each pipeline run since regime can shift.
---

# Macro Regime — May 2026 Read

This document captures the macro regime at pipeline-build time. The skill MUST re-read FRED at runtime to verify, but this provides the baseline interpretation.

## Current Regime Snapshot (May 2026)

| Indicator | Value | Interpretation |
|-----------|-------|----------------|
| S&P 500 level | ~7,400 | 4th consecutive year of gains |
| Shiller CAPE | 42 | [SURPRISING] Only 2nd time in history above 40 (prior: Dec 1999). Dot-com territory. |
| Fed Funds Rate | 3.5-3.75% | Rate cuts paused/delayed |
| 10Y Treasury | 4.38% | Re-normalized from inverted |
| 30Y Treasury | 4.95% | |
| Yield Curve (10Y-3M) | Positive ~50bps | RE-NORMALIZED after 26-month inversion. **Historically this PRECEDES recession**, doesn't signal all-clear. |
| CPI YoY | 3.3% (rising again March 2026) | Soft-landing narrative stressed |
| Unemployment | 4.2% | Slight rise from 3.5% trough |
| ISM Manufacturing | ~51 | Marginally expansionary |
| AAII Sentiment Bull/Bear | Bullish ~45% (rich-but-not-extreme) | Sentiment indicators don't yet signal capitulation |
| VIX | ~16 | Complacent given fundamentals |

**Sector YTD performance**:
- Energy: +23%
- Materials: +18%
- Industrials: +14%
- Utilities: +12%
- Financials: +6%
- S&P 500 overall: +4%
- Healthcare: -2%
- IT: -3%
- Consumer Discretionary: -4%
- Communication Services: -7%
- Mag 7 basket: -4.9% (every member underperforming S&P 500)

## Cycle Phase Classification

Using Fidelity/Hudson criteria:
- Inverted yield curve recently re-normalized ✓
- Industrial production decelerating ✓
- Energy/Materials leading (defensive late-cycle behavior — sector rotation has rotated) ✓
- Mag 7 (growth) breaking down ✓
- Credit spreads still tight (HY OAS ~3.0-3.2%) but inflecting wider
- Unemployment ticking up but still low
- ISM around 50

**Regime classification**: **LATE-CYCLE with rising recession probability**.

This is NOT clearly "early-cycle" or "mid-cycle." It is the late phase where multiple expansion is over and earnings need to do the heavy lifting just as growth slows.

## Implications for the Skill

### 1. Apply -5 macro regime tilt to ALL CS100 scores
The "default macro regime tilt" in this build is **-5**, not 0. CAPE > 38 forces this.

### 2. Sector adjustment recalibration
Per [`03-sector-playbooks.md`](03-sector-playbooks.md):

| Sector | Adjustment Now |
|--------|---------------|
| Energy | +10 |
| Materials | +10 |
| Industrials | +5 |
| Utilities | +5 |
| Healthcare | 0 |
| Staples | 0 |
| Financials | -5 |
| Real Estate | -10 |
| IT (especially Mag-7-adjacent) | -10 |
| Communication Services | -10 |
| Consumer Discretionary | -5 |

### 3. Quality > Value > Momentum bias
In late cycle with rate uncertainty, quality compounders survive. Cyclicals look optically cheap but are at peak earnings. Boost Quality bundle weight by +5 percentage points in default weights (60→65 for compounders, 35→40 for GARP).

### 4. Patient Cash is MORE likely
With CAPE 42, expect the pipeline to refuse picks more often than baseline. This is correct behavior. Klarman cash discipline.

### 5. Duration sensitivity warning
Long-duration cash flow stocks (biotech with no revenue, hyper-growth SaaS, REITs, utilities) are MORE rate-sensitive in re-normalized curve environment. Apply additional -3 tilt to candidates with >70% of DCF value in terminal value.

### 6. Recession overlay
If user's horizon < 3 years AND we're in late-cycle: warn that a -25 to -40% drawdown in next 12-24 months is plausible. Adjust position sizing toward quarter-Kelly.

### 7. Mag 7 specific
Mag 7 stocks are individually high-CS100 candidates by quality (MSFT, GOOGL, AAPL) but the cohort is at sector-headwind point. Apply -10 sector adjustment to all of them as of May 2026. The "concentration unwind" risk is the regime story.

### 8. AI capex cycle
Capex on AI infrastructure remains massive (NVDA, TSM, vlsi, etc.) but **ROIC on AI capex is unprovable yet**. Apply skeptical lens: companies SPENDING on AI ≠ companies BENEFITING from AI. Most beneficiaries are upstream (chips, power, data centers).

### 9. Vistra-like AI-data-center demand
[SURPRISING] AI is a cross-sector demand driver. Vistra (VST), Constellation (CEG), Talen (TLN), and utilities serving AI campuses outperformed sharply in 2024-2025. This is durable through 2027+. Sector classification (Utilities = late-cycle defensive) may understate these names — apply +5 override for AI-data-center exposed utilities.

### 10. Private equity comparison
PE underperformed S&P 500 by ~17%/year in 2023 and 2024. The "PE always outperforms" narrative is empirically dead. This is bullish for public-equity attention.

## Indicators to Watch for Regime Shift

Re-classify regime if any 3 of these flip:
- Yield curve re-inverts → recession warning back on
- ISM PMI drops below 47 → recession imminent
- Credit spreads widen >150bps from current ~300bps → stress
- VIX > 25 sustained — sentiment regime shift
- AAII Bull-Bear becomes capitulation-bearish (>45% bearish) — contrarian buy signal
- Sahm Rule fires (3mo avg unemployment > 12mo low + 50bps) — recession started
- S&P 500 EPS guidance for 2026 revised down >5% in aggregate
- Sector leadership rotates back to defensives (Staples, Healthcare leading)

## Runtime Recomputation

`scripts/fetch-macro.js` recomputes these indicators at runtime. The skill should compare to this baseline document and warn if regime has shifted. The thesis memo's "Macro Regime" section uses the runtime value, not this document.

## Operating Principle Across Regimes

[SURPRISING — Marks "Calibrating"]: Cycle awareness works by TILTING between more/less risky assets, not by RAISING CASH. The skill's exception (patient-cash output when CS100 < 55) is specifically for retail context where the user isn't mandated to be 100% deployed. Institutional investors should not literally hold cash; they should rotate to defensives.
