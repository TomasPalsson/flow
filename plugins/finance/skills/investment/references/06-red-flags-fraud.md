---
name: red-flags-fraud
description: Fraud detection (Beneish M-Score, Sloan accruals, Dechow F-score), value-trap patterns, and growth-trap patterns. Beneish is a HARD VETO. Load in Stage 3 before scoring candidates.
---

# Red Flags, Fraud Detection, Value & Growth Traps

## Beneish M-Score (HARD VETO)

The Beneish M-Score (1999) is a logistic model predicting earnings manipulation likelihood. Compute for EVERY deep-fundamentals candidate. M-Score > **-1.78** → drop candidate, no exceptions, no second chance.

**Formula** (8 variables, exact coefficients from Beneish 1999):
```
M-Score = -4.84 + 0.92 × DSRI
              + 0.528 × GMI
              + 0.404 × AQI
              + 0.892 × SGI
              + 0.115 × DEPI
              - 0.172 × SGAI
              + 4.679 × Accruals
              - 0.327 × LVGI
```

| Variable | Definition | Threshold |
|----------|-----------|-----------|
| DSRI (Days Sales in Receivables Index) | (Receivables_t/Sales_t) / (Receivables_t-1/Sales_t-1) | > 1.465 elevated |
| GMI (Gross Margin Index) | GM_t-1 / GM_t | > 1.193 elevated (margins shrinking) |
| AQI (Asset Quality Index) | (1 - (CurAssets + Net PPE) / TotAssets)_t / (same)_t-1 | > 1.0 elevated (intangibles growing) |
| SGI (Sales Growth Index) | Sales_t / Sales_t-1 | > 1.4 elevated |
| DEPI (Depreciation Index) | DEPI_t-1 / DEPI_t | > 1.0 elevated (slowing depreciation = capex tricks) |
| SGAI (SG&A Index) | (SG&A/Sales)_t / (SG&A/Sales)_t-1 | > 1.054 elevated |
| Accruals | (Income from operations − cash from operations) / Total assets | > 0.10 elevated |
| LVGI (Leverage Index) | (LTD+CurLiab)/Total Assets ratio change | [SURPRISING] negative coefficient — higher leverage slightly REDUCES M-Score |

**Thresholds**:
- M-Score > -1.78: HIGH manipulation risk → VETO
- M-Score -2.22 to -1.78: ELEVATED (YELLOW) → see protocol below
- M-Score < -2.22: low risk → pass

**YELLOW band protocol** (M-Score between -2.22 and -1.78, OR Sloan accruals 10-20%):
1. Apply **-5 point penalty to the Quality bundle** (not just sector adjustment)
2. The thesis memo MUST include a specific pre-mortem item documenting WHY the elevated earnings-quality signal is non-material (industry seasonality? working capital build for known reason? recent acquisition?). If you cannot articulate a non-material reason → reject the candidate.
3. Cap position size at quarter-Kelly regardless of overall conviction score
4. Quarterly reassessment must re-check M-Score; if it moves above -1.78 → mandatory exit within 30 days

## Sloan Accruals (Secondary Veto)

Sloan 1996: Accrual reversal is forced by cash reality. High accruals predict poor future returns.

```
Total Accruals = (ΔCurrent Assets − ΔCash) − (ΔCurrent Liabilities − ΔShort-term Debt − ΔIncome Tax Payable) − Depreciation
Scaled Accruals = Total Accruals / Average Total Assets
```

Or the simpler CFO-based formula:
```
Scaled Accruals = (Net Income − CFO) / Average Total Assets
```

| Range | Action |
|-------|--------|
| Accruals > +0.20 | VETO — drop candidate |
| Accruals +0.10 to +0.20 | Yellow flag — proceed with skepticism |
| Accruals < +0.10 | Normal |

## Dechow F-Score (Tertiary)

Logistic regression predicting material misstatement.
```
Predicted Probability = 1 / (1 + exp(-(-7.893 + 0.79 × RSST Accruals + 2.518 × Δ Receivables + 1.191 × Δ Inventory + 1.979 × Soft Assets % + 0.171 × Δ Cash Sales − 0.932 × Δ ROA + 1.029 × Issuance Indicator)))

F-Score = Predicted Probability / Unconditional Probability (≈ 0.0037)
```

| F-Score | Risk Level |
|---------|-----------|
| > 10 | Extreme |
| > 2.0 | Elevated |
| 1.0-2.0 | Baseline |
| < 1.0 | Low |

[SURPRISING]: Soft assets (intangibles + goodwill as % of total assets) is the single strongest predictor.

## Going-Concern Veto

If the latest 10-K Item 8 "Going Concern" footnote raises substantial doubt about the company's ability to continue as a going concern → VETO immediately. No exceptions.

## Value Trap Patterns (7) — Detection Rules

| Pattern | Detection | Action |
|---------|-----------|--------|
| Declining business no catalyst | Revenue CAGR (3y) < -3% AND no announced strategic action | Reject |
| Hidden liabilities | Pension underfunded > 20% of market cap, OR operating lease commitments > 50% of LT debt, OR environmental liability disclosed | Reject or massively haircut |
| One-time earnings | EPS_TTM / EPS_5y_avg > 1.5x AND no durable cause | Use normalized earnings; reject if multiple expansion is the only driver |
| Cyclical at peak | Capacity utilization > 88% AND industry-wide capex up > 15% YoY | Reject |
| Capital structure trap | Debt/EBITDA > 5x AND operating margin trend negative | Reject |
| Foreign fraud risk | Domicile = China/Hong Kong, with US listing, with auditor not Big 4 | Avoid entire category |
| Melting ice cube | 5y revenue declining, 5y operating margin declining, no announced transformation | Reject |

**Specific examples to recognize**:
- Sears (declining business, no catalyst, 15-year value trap)
- Gap (declining brand, attempted turnarounds repeatedly failed)
- J.Crew (PE-owned, structural decline, levered)
- Bed Bath & Beyond (peak-earnings illusion masking decay)

## Growth Trap Patterns (6) — Detection Rules

| Pattern | Detection | Action |
|---------|-----------|--------|
| Growth at any price | P/Sales > 15x AND not Rule-of-40 > 60 | Reject |
| Growth slowing, multiple stays high | Revenue YoY growth decelerated > 30% (e.g. 40% → 25%) AND P/Sales > 8x | Reject |
| SBC dilution masking growth | SBC/Revenue > 15% AND diluted share count growing > 3%/yr | Drop SBC add-back; recompute |
| Customer concentration | Top 1 customer > 20% of revenue, OR top 3 > 40% | Apply 30-50% IV haircut |
| TAM overstatement | Company claims TAM > 10x current revenue with no clear path | Skepticism overlay; require independent TAM check |
| Land-grab with no profitability path | Operating margin trend -, revenue trend +, no announced margin inflection | Reject |

**Specific examples**:
- Peloton (growth crashed, multiple stayed high too long)
- Zoom (post-COVID growth deceleration, valuation overshoot)
- Snap (engagement growing, monetization failing)
- Many 2021-2022 "Rule of 0" SaaS — growing but burning, no path to profit

## SBC Trap Specifically

[SURPRISING] but critical: Stock-Based Compensation is a real cost paid in equity. Tech "Adjusted EBITDA" margins are typically 10-20pp higher than EBITDA-minus-SBC margins.

**The correct adjustment**:
- DON'T add SBC back to FCF AND use diluted share count (double-count)
- DO subtract SBC from FCF (treat as real cost) AND use diluted share count

[SURPRISING] data point: ~40% of S&P 500 tech buybacks from 2019-2024 merely offset SBC issuance (Wave 1 insider research). Net buyback yield = Gross Buybacks − SBC − new issuance / Market Cap.

## Auditor Red Flags

Pull from 10-K and proxy:
- Auditor change in last 5 years without clean reason
- Late filings (10-K filed past 60-day deadline = NT 10-K)
- Material weakness in internal controls disclosed
- Audit committee turnover
- Non-Big-4 auditor for company > $5B market cap
- Audit fees declining despite company growing

Any 2+ of these = elevated fraud risk.

## SBC and Goodwill Detection

- SBC/Revenue > 12% sustained = high dilution risk (impacts long-term IRR significantly)
- Goodwill/Total Assets > 40% = serial acquirer; check impairment history
- Goodwill impairments in 3 of last 5 years = serial overpayer; reject

## Soft Asset Quality

Soft Assets = Intangibles + Goodwill / Total Assets.
- > 70% soft = highly impairment-prone
- 30-70% = standard
- < 30% = asset-rich (industrial / utility / financial)

Rising soft asset ratio + falling tangible book = serial acquirer concern.

## Forensic Accounting Case Studies (lessons for the skill)

| Case | Signal that would have caught it |
|------|----------------------------------|
| Enron | Off-balance-sheet entities (SPEs) disclosed in footnotes; soft asset %; auditor conflict (Andersen 27% of revenue) |
| Worldcom | Capex/D&A divergence; DEPI Beneish variable |
| Luckin Coffee | DSRI spike + same-store-sales statistical impossibility |
| Wirecard | Opaque receivables from "Asian trustees"; EY audit failure; index inclusion blinded scrutiny |
| Theranos (private) | Auditor changes, related-party, charismatic-CEO red flag |

## Final Veto Stack Order

When evaluating a candidate, apply vetoes in this order (first hit = drop):
1. Going concern flag in 10-K → VETO
2. Beneish M-Score > -1.78 → VETO
3. Sloan Accruals > +0.20 → VETO
4. Foreign fraud profile (China-domiciled, non-Big-4 auditor) → VETO
5. Restatement in last 12 months → REVIEW (lean veto)
6. Goodwill impairments 3 of 5 last years → REJECT
7. Sustained SBC/Revenue > 25% → REJECT

Only candidates surviving the veto stack proceed to CS100 scoring.
