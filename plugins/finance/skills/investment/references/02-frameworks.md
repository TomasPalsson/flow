---
name: frameworks
description: Specifications for all 6 investment frameworks plus the management quality scorecard. Use these formulas exactly when computing per-candidate scores.
---

# The Six Frameworks — Exact Specifications

Each framework outputs a 0-100 percentile within the deep-fundamentals universe (~50 candidates). Bundle z-scores in CS100 derive from these.

## F1 — Buffett Quality (Owner Earnings + ROIIC)

**Owner Earnings** (Buffett 1986 letter):
```
Owner Earnings = Net Income
               + Depreciation & Amortization
               + Non-cash charges (other)
               - Maintenance Capex
               - Working capital reinvestment needs
```

**Maintenance Capex** (Greenwald method — most rigorous practitioner technique):
```
Maintenance Capex = Total Capex − (5y-7y avg Gross PP&E / Revenue × ΔRevenue)
```
**Must use Gross PP&E, not Net PP&E.** Most practitioners get this wrong.

**ROIIC (5-year)**:
```
ROIIC = (NOPAT_t - NOPAT_t-5) / (Invested Capital_t - Invested Capital_t-5)
```
Where NOPAT = EBIT × (1 - effective tax rate), Invested Capital = Total Assets − Excess Cash − Non-interest-bearing current liabilities.

For high-R&D companies (pharma, big tech), capitalize R&D into Invested Capital (amortize over 5-7 years) — otherwise ROIC is overstated by 200-500 bps.

**$1-Retained Test**: Over 5-year rolling windows, $1 of retained earnings should produce ≥ $1 of market value created. Compute: ΔMarket Cap / Σ Retained Earnings ≥ 1.0.

**Scoring (percentile within deep-fundamentals universe):**
- ROIIC > 20% AND ROIC > 18% AND $1-retained ≥ 1.5 → Top decile
- ROIIC > 15% AND ROIC > 13% → Top tercile
- ROIIC < 8% OR ROIC < 6% → Bottom quartile

**Anti-patterns:** Don't compute ROIIC over <3 years (too noisy). Don't include goodwill in invested capital denominator (it normalizes acquirer-vs-organic comparison). Don't trust Net PP&E for the Greenwald capex split.

## F2 — Lynch GARP (Value Ratio)

**Lynch's actual formula** (not the textbook PEG):
```
Value Ratio = (Forward 5y EPS growth %  +  Dividend Yield %) / P/E
```
Thresholds (Lynch's own):
- < 1.0 → poor
- 1.0-1.5 → fair
- ≥ 2.0 → buy

**Growth ceiling**: Lynch's [SURPRISING] rule — 50%+ projected annual growth is a RED FLAG, not enthusiasm. Hot industries attract competition. Sweet spot is 20-25%.

**Category routing** (Lynch's 6 categories):
- Slow growers (< 4% rev CAGR) — dividend plays only
- Stalwarts (4-12% rev CAGR) — sell at 30-50% gains, rotate
- Fast growers (15-25% rev CAGR) — Lynch's favorite, multi-baggers
- Cyclicals — apply cycle-normalization (see sector playbook)
- Turnarounds — debt declining 5+ quarters then rising = sell trigger
- Asset plays — break-up value > market cap

**Anti-patterns:** Don't use trailing P/E for cyclicals (peak-earnings illusion). Don't apply Value Ratio to growth >40% (mean-reversion math breaks).

## F3 — Greenblatt EBIT/EV (sector-neutral relative percentile)

**Magic Formula is dead post-2010 for large/midcap** (Novy-Marx-Medhat 2025; AlphaArchitect live tracking). Do not use as primary screen.

Use EBIT/EV as a SECTOR-NEUTRAL relative percentile only:

```
EBIT/EV = EBIT (TTM) / Enterprise Value
Enterprise Value = Market Cap + Total Debt + Preferred + Minority Interest − Excess Cash
```

"Excess cash" = cash beyond what's needed for operations (~2-5% of revenue depending on industry). Not all cash.

**Sector neutralization**: Compute EBIT/EV percentile within the candidate's GICS sector, NOT vs. universe.

**Cyclical adjustment**: For cyclicals, use 5-7y average EBIT, NOT trailing EBIT. Otherwise high P/E at trough looks bad and low P/E at peak looks good — the inversion.

**Acquirer's Multiple** = EV / EBIT (the inverse). Wesley Gray and Tobias Carlisle research: in pure backtests pre-2010, single-factor EBIT/EV BEAT the two-factor Magic Formula. Post-2010, both struggle.

## F4 — Piotroski F-Score (9-point binary checklist)

All signals as defined in Piotroski 2000. Use beginning-of-year assets in denominators (NOT average) — as the original paper specifies.

| # | Signal | Definition |
|---|--------|------------|
| 1 | ROA > 0 | Net income / beginning total assets > 0 |
| 2 | CFO > 0 | Cash flow from operations > 0 |
| 3 | ΔROA > 0 | Current ROA > prior year ROA |
| 4 | Accrual quality | CFO > Net Income |
| 5 | ΔLeverage < 0 | Long-term debt / avg assets decreased YoY |
| 6 | ΔLiquidity > 0 | Current ratio increased YoY |
| 7 | No equity issuance | Diluted shares didn't increase (excluding SBC vesting routine) |
| 8 | ΔGross Margin > 0 | Gross margin improved YoY |
| 9 | ΔAsset Turnover > 0 | Revenue / avg assets improved YoY |

**Scoring**: F-score 8-9 = high quality; 0-2 = junk. **Apply only to non-financials** — banks have undefined current ratio. For financials, use the sector playbook instead.

**Universe caveat**: Piotroski's original was a HIGH BOOK-TO-MARKET (deep value) screen. Large-cap F-score alpha is statistically insignificant (only 1.7%/yr). Use as a quality FLOOR check across the universe, not as primary alpha source for large/mid.

## F5 — AQR QMJ Proxy (Quality Minus Junk)

True QMJ requires licensed Compustat data (Asness-Frazzini-Pedersen 2014). Approximate with public data:

**Profitability sub-score** = avg z-score of:
- Gross Profitability = Gross Profit / Total Assets (Novy-Marx 2013 — empirically the strongest single quality measure)
- ROA = Net Income / Total Assets
- ROE = Net Income / Stockholders Equity (cap at 50% to avoid leverage artifacts)
- CFO / Total Assets

**Safety sub-score** = avg z-score of:
- −Beta (lower beta = safer)
- −Debt/Equity
- 8-quarter earnings standard deviation / mean (lower = safer, "Earnings volatility")
- Altman Z-score (higher = safer)

**Payout sub-score** = avg z-score of:
- −Net equity issuance (negative issuance = buybacks, good)
- Dividend yield + buyback yield − SBC dilution

**Growth sub-score** = z-score of 5-year per-share growth in profitability metrics.

**Combine**: QMJ z = avg of 4 sub-scores. Map to 0-100 percentile.

## F6 — 12-1 Momentum

```
Momentum = Price(t-1 month) / Price(t-12 months) − 1
```
Skip the most recent month (Jegadeesh-Titman; reduces 1-month reversal contamination — roughly doubles Sharpe vs naive 12-month return).

Map to 0-100 percentile across universe.

**Caveats**:
- For spinoffs / IPOs with <15 months trading history → default to 50 (neutral). Trading mechanics dominate fundamentals in early months.
- Momentum has option-like payoff — short a call on the market in bear regimes. Apply −3 regime tilt if VIX > 30 AND market drawdown > 15%.

## Management Quality Scorecard (100 points)

Used in Stage 5 deep-dive, NOT in CS100. Decomposes into 5 weighted categories:

| Category | Weight | Key Signals |
|----------|--------|------------|
| Capital Allocation | 30 | $1-retained test, goodwill impairment history, buyback price vs IV, dividend stability, ROIIC trend |
| Compensation Alignment | 25 | Long-term grants (multi-year vest), TSR/ROIC-based bonuses (NOT revenue-based), no option repricing, CEO/median pay ratio, "say on pay" votes |
| Communication Quality | 20 | 10-K MD&A clarity, shareholder letter style (Buffett-clear vs corporate-boilerplate), segment reporting trend (consolidating segments = red flag), non-GAAP vs GAAP gap stable |
| Governance | 15 | Independent chair, board industry expertise, related-party transactions, auditor stability, restatement history |
| Track Record | 10 | CEO tenure 5+ years, CFO turnover frequency, capital allocation outcomes over tenure |

**Hard ceiling 70** if any "red flag override" present:
- Option repricing in last 5 years
- Restatement in last 3 years
- CEO turnover < 3 years
- Material related-party transactions in 10-K
- Auditor change with no clean reason

**Empirical anchor** (Outsiders study, Thorndike): The 8 CEOs who created exceptional shareholder value averaged 22-year tenure. S&P 500 median CEO tenure is now 5.1 years. This structural mismatch is the most underappreciated governance problem in public markets.

## Source Locations in Filings

| Signal | 10-K Section / Filing |
|--------|---------------------|
| Owner earnings inputs | Cash Flow Statement |
| ROIC components | Income Statement + Balance Sheet |
| Buybacks | Statement of Equity OR Cash Flow Financing |
| SBC | Cash Flow Statement (often a line item) |
| Compensation details | DEF 14A proxy — Summary Compensation Table + CD&A |
| Related-party | 10-K Item 13 |
| Auditor info | 10-K Item 9A + Audit Committee Report in proxy |
| Restatements | 10-K Item 9B + 8-K Item 4.02 history |
| Goodwill impairments | 10-K Item 7 MD&A + Note on Goodwill |
| Segment reporting | 10-K Item 8 Notes |
| Insider transactions | SEC Form 4 (real-time) |
| Major holders | 13D/13G + 13F filings |
