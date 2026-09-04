---
name: sector-playbooks
description: Sector-specific valuation frameworks for sectors where standard P/E + ROIC + DCF break. MANDATORY load when candidate is in Financials, Real Estate, Biotech, SaaS, Cyclicals, Energy, or Consumer Brands.
---

# Sector-Specific Playbooks

Standard frameworks (Buffett quality, Lynch GARP, Greenblatt EBIT/EV, Piotroski) BREAK on the sectors below. Apply these sector-specific metrics INSTEAD. The CS100 formula for these sectors is computed differently.

## Banks (GICS Sub-Industry: Diversified Banks, Regional Banks)

**Why standard frameworks fail**: The balance sheet IS the business. Earnings are highly dependent on accounting choices (loan loss reserves). P/E is misleading mid-cycle. ROIC is undefined.

**Core metrics**:

| Metric | Target | Red Flag |
|--------|--------|----------|
| P/Tangible Book Value | 1.0-2.0x for quality | >2.5x (overvalued) or <0.8x (distress) |
| ROTCE (Return on Tangible Common Equity) | > 15% | < 10% |
| Efficiency Ratio | < 55% (excellent), 55-65% (good) | > 70% |
| Net Interest Margin (NIM) | 2.5-4.0% normalized | Sustained < 2.0% |
| CET1 (Common Equity Tier 1) | > 12% | < 10% |
| Loan loss reserves / NPLs | > 2.0x coverage | < 1.0x |
| Texas Ratio (NPL / (Equity + Reserves)) | < 50% | > 100% — failure risk |

**Bank-specific CS100**: Replace standard Quality bundle with:
- Quality: avg z-score of (ROTCE, −Efficiency Ratio, CET1, −Texas Ratio)
- Value: avg z-score of (−P/TBV, dividend + buyback yield)
- Momentum: standard 12-1

**Anti-pattern**: Sub-1.0x P/TBV is NOT automatically cheap. Could mean CECL reserves are inadequate, or hidden AOCI losses (SVB lesson — they had massive AFS losses below the line).

## Insurance (P&C, Life, Reinsurance)

| Metric | Target | Notes |
|--------|--------|-------|
| Combined Ratio | < 95% excellent; <100% profitable underwriting | Cost-of-float interpretation |
| Book Value per Share growth (5y CAGR) | > 8% for compounders | Berkshire's primary metric |
| Reserve development | Favorable (releases) | Adverse development = under-reserved, potential fraud |
| Float / Equity ratio | > 1.5x (leverage on float) | Lower for life ins. |

[SURPRISING]: Combined ratio > 100% is COMPATIBLE with a great business if cost-of-float (effective negative interest rate) is achieved via float deployment. Berkshire model.

## REITs (Real Estate Investment Trusts)

**Why standard fails**: REITs pay out 90% of taxable income → P/E is meaningless. Depreciation is a non-cash charge that dramatically understates earnings.

**Core metrics**:
- **FFO (Funds From Operations)** = Net Income + Depreciation + Amortization − Gains on property sales (NAREIT formula)
- **AFFO** = FFO − recurring capital expenditures − straight-line rent adjustments

| Sub-Sector | P/FFO Range | Notes |
|-----------|-------------|-------|
| Data Centers | 25-35x | Highest-quality REIT sub-sector |
| Industrial / Logistics | 20-25x | Amazon-era beneficiary |
| Apartments | 18-22x | Demand-stable |
| Healthcare | 16-20x | Demographic tailwind |
| Cell Towers | 25-30x | Quasi-monopoly |
| Retail | 10-16x | Disruption-exposed |
| Office | 6-12x | Post-COVID structural disruption |
| Mortgage REITs | 0.8-1.2x P/BV | Different beast — leverage-driven |

**Cap rate anchor**: Implied cap rate = NOI / EV. Compare to actual transactions in the sector.

**Debt maturity wall**: Critical for REITs (high leverage). Check next 24 months of debt maturity vs available liquidity.

**[SURPRISING]**: Office REIT multiples collapsed in 2023-24 but FFO won't reflect the decline for 2+ years due to lease durations. The MULTIPLE leads FFO.

## SaaS / Software

| Metric | Best-in-class | Acceptable | Red Flag |
|--------|---------------|-----------|----------|
| Rule of 40 (Growth% + FCF Margin%) | > 60 | > 40 | < 30 |
| Net Revenue Retention (NRR) | > 130% | > 110% | < 100% |
| Gross Margin | > 80% | > 70% | < 60% (not really software) |
| Magic Number ((New ARR × 4) / S&M Quarterly) | > 1.0 | > 0.7 | < 0.4 |
| CAC Payback | < 12 mo | < 24 mo | > 36 mo |
| SBC / Revenue | < 8% | < 15% | > 25% |

**EV / NTM Revenue cohorts** (rough 2026 mid-cycle):
- Hyper-growth + Rule of 40 > 60: 12-20x
- Solid growth + Rule of 40 40-60: 6-10x
- Mature + Rule of 40 20-40: 3-5x

**[SURPRISING] SBC double-count**: Don't add SBC back to FCF AND use diluted share count. That's double-counting. The correct approach: subtract SBC from FCF (treat it as a real cost paid in equity), THEN use diluted share count.

**Anti-pattern**: "Adjusted EBITDA" margins 10-20pp above EBITDA-minus-SBC margins = aggressive. Use EBITDA-minus-SBC as the true metric.

## Biotech / Pharma (with Pipeline)

**Why standard fails**: Most biotechs have no revenue. DCF on smooth cash flows is wrong for binary phase outcomes.

**rNPV (risk-adjusted NPV)** by program:
```
rNPV = Σ over phases [P(phase_n+1 | phase_n) × discounted future cash flows | success]
     − development costs to reach success
```

**Phase transition probabilities (BIO data, generic)**:
| Phase | Probability of Advancing |
|-------|------------------------|
| Phase I → II | 63% |
| Phase II → III | 31% |
| Phase III → Approval | 58% |
| Overall Phase I → Approval | ~12% |

**Adjust by therapeutic area**:
- Oncology: lower (overall ~5-7% Phase I → approval)
- Rare disease: higher (overall ~17%)
- CNS: lower (overall ~6%)
- Infectious disease: moderate (~10%)

**Cash runway** = (Cash − Annual burn) / Annual burn = years to next milestone. Must exceed time-to-Phase-III readout for the lead program.

**Patent cliff erosion** (branded → generic):
- Year 1 post-genericization: -30 to -50% revenue
- Year 2: -65 to -75%
- Year 3+: -85 to -95%

## Cyclicals (Materials, Industrials, Energy E&P, Autos)

**The P/E inversion** [SURPRISING and critical]:
- High P/E + trough earnings = potentially attractive
- Low P/E + peak earnings = dangerous

**Use normalized earnings** = average EBIT over 5-7 years through cycle.

**Mid-cycle margin** anchor: compute average operating margin over a full cycle, use that as the long-run anchor.

**Capacity utilization**:
- > 85% — late cycle, peak earnings, sell
- 75-85% — mid cycle, normal
- < 70% — early cycle / trough, potentially attractive

**Commodity-linked**: Compute FCF at strip prices (futures curve) AND at long-run average prices. The gap = optionality.

**US Steel example** [SURPRISING]: 2002 trough P/E ~50 (correct buy signal); 2006 peak P/E ~7 (correct sell signal). Standard screens flagged it backwards.

## Energy (E&P specifically)

| Metric | Definition | Target |
|--------|-----------|--------|
| AISC (All-In Sustaining Cost) | Total cost per barrel/MCF/oz including overhead | Bottom quartile cost curve |
| Reserve Life Index (RLI) | Proved reserves / annual production | > 8 years |
| F&D Costs (Finding & Development) | Capex / barrels added | < $15/boe (oil) |
| Net Debt / EBITDAX | At strip prices | < 1.5x |
| FCF Breakeven price | Oil price at which FCF = 0 | < 60% of current strip |

**Strip pricing** (futures curve) is the correct base case, NOT spot price. Spot is too noisy.

## Consumer Brands (Staples + Discretionary apparel/luxury)

**Gross margin stability** = brand-equity proxy. Coefficient of variation of gross margin over 8 quarters; < 3pp = strong brand pricing power.

**Volume vs price decomposition**: Pull from MD&A. Sustained price-positive / volume-negative is BRAND EROSION, not premium strategy. (Tide raising prices while losing share to private label = warning.)

**DTC vs wholesale margin difference**: DTC typically 10-15pp higher gross margin. The trend matters.

**Declining brand warning signals**: Promotional intensity rising, gross margin trend negative, market share losses to private label.

## Sector-to-Framework Routing Table (used by Stage 4)

| GICS Sector | Sub-Industry | Framework Set | Notes |
|-------------|--------------|---------------|-------|
| Financials | Banks | Bank playbook (P/TBV + ROTCE + CET1) | |
| Financials | Insurance | Insurance playbook (combined ratio + BV growth) | |
| Financials | Capital Markets / Asset Managers | Standard with AUM × take-rate adjustment | |
| Financials | Consumer Finance | Hybrid bank/standard | Higher loan loss volatility |
| Real Estate | REITs | REIT playbook (FFO/AFFO + cap rates) | |
| Real Estate | Real Estate Mgt & Dev | Standard, asset-heavy adjustment | |
| Healthcare | Biotechnology | Biotech rNPV playbook | |
| Healthcare | Pharmaceuticals | Standard + patent-cliff overlay | |
| Healthcare | Healthcare Equipment / Services | Standard | |
| IT | Software | SaaS playbook (Rule of 40 + NRR) | |
| IT | Semiconductors | Cyclical playbook (book-to-bill leading indicator) | |
| IT | Tech Hardware | Standard, cyclical-tilt | |
| Industrials | Capital Goods | Cyclical playbook | |
| Industrials | Transportation | Standard with operating leverage focus | |
| Industrials | Aerospace & Defense | Standard, contract-visibility premium | |
| Materials | All | Cyclical playbook + commodity overlay | |
| Energy | Oil/Gas E&P | Energy E&P playbook (AISC + reserve life) | |
| Energy | Refining/Marketing | Cyclical playbook | |
| Consumer Discretionary | Auto | Cyclical playbook | |
| Consumer Discretionary | Apparel / Specialty Retail | Consumer brand playbook | |
| Consumer Discretionary | Hotels/Restaurants | Standard with unit economics focus | |
| Consumer Staples | Beverages / Food | Consumer brand playbook | |
| Consumer Staples | Household Products | Consumer brand playbook | |
| Communication Services | Telecom | Cap-intensive standard + dividend focus | |
| Communication Services | Media / Interactive Media | Standard, growth-tilt | |
| Utilities | Electric / Gas / Water | Regulated utility playbook (Allowed ROE + Rate Base) | |

[SURPRISING] **GICS 2023 Reclassification**: Visa and Mastercard moved to Financials but require hybrid payment-network framework (volume growth, net revenue margin) — NOT standard bank metrics. Hard-code this exception.
