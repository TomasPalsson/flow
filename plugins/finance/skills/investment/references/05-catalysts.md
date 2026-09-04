---
name: catalysts
description: Catalyst taxonomy and 0-125 quality scoring rubric. Every recommended pick must have ≥1 identified catalyst. Load when running Stage 5 catalyst inventory.
---

# Catalysts — What Closes the Mispricing

Without a catalyst, value can stay cheap forever. Sears was "cheap" for 15 years before bankruptcy. The skill REQUIRES at least one identified catalyst per pick. No catalyst = no recommendation.

## Catalyst Taxonomy

| Category | Examples | Typical Magnitude | Typical Probability | Time-to-Event |
|----------|----------|-------------------|---------------------|---------------|
| Earnings | Margin expansion realized, segment break-out, guidance reset | 10-25% | 50-70% | 1-4 quarters |
| Capital allocation | Initiated buyback, special dividend, spinoff announcement | 5-15% | 30-60% | 6-18 months |
| Management change | New CEO with track record, CFO change | 10-30% | 40-60% | 12-24 months |
| Activist (13D filings) | Pershing/Elliott/Starboard/Trian/ValueAct campaigns | 7-15% (12mo drift) | 50-65% follow-through | 12-18 months |
| Regulatory/Legal | Drug approval, patent win, antitrust settlement | 20-100% | 20-60% (binary) | Event-specific |
| Operational | New product, capacity online, geographic expansion | 10-25% | 40-70% | 6-24 months |
| Strategic alternatives | Sale process, breakup, "exploring alternatives" language | 25-50% | 75-85% transaction completion | 6-12 months |
| Sentiment | Analyst upgrade cluster, institutional ownership shift | 5-15% | 30-50% | 1-6 months |
| Macro | Rate cut benefit, fiscal stimulus, commodity recovery | 10-30% | Regime-dependent | 6-24 months |
| Insider (cluster + opportunistic) | Cohen-Malloy-Pomorski filter, 3+ CEO/CFO buys | 5-12% (12mo) | 50-65% | 6-12 months |

## Catalyst Quality Scoring (0-125)

For each identified catalyst, score on 3 dimensions:

**Probability (0-50)**: How likely is the catalyst to actually occur?
- 5-15: Long shot
- 20-30: Plausible
- 35-45: Likely
- 50: Near-certain (announced, in-flight)

**Magnitude (0-50)**: If the catalyst occurs, how much does the stock re-rate?
- 5-15: Modest (5-10% upside)
- 20-30: Meaningful (10-20% upside)
- 35-45: Substantial (20-40% upside)
- 50: Transformational (>40% upside)

**Time (0-25)**: How soon will we know?
- 5-10: Long (18+ months)
- 12-18: Medium (6-18 months)
- 20-25: Near (< 6 months)

**Composite = Probability + Magnitude + Time (max 125)**

## Position Size Multiplier Mapping

| Composite Score | Multiplier | Interpretation |
|----------------|-----------|----------------|
| 100-125 | 2.0x | Strong, multi-catalyst, near-term |
| 80-99 | 1.5x | High-quality catalyst |
| 60-79 | 1.2x | Reasonable catalyst |
| 40-59 | 1.0x | Baseline catalyst (just qualifies) |
| 20-39 | 0.5x | Weak catalyst, reduce sizing |
| < 20 | DROP | Insufficient catalyst — reject pick |

Apply this multiplier to base Kelly sizing.

## Catalyst Quality Detection Rules (high-confidence patterns)

### 1. Activist 13D from Top Tier
- File a SEC EDGAR full-text search for "Schedule 13D" filings in last 90 days
- Filter to filers: Pershing Square, Elliott Management, Trian, Starboard Value, ValueAct, Engaged Capital, JANA Partners
- Read the 13D exhibit / public letter for thesis
- Score baseline: P=40, M=30, T=15. Composite = 85 → 1.5x multiplier
- Caveat: Average academic follow-through is ~7-10% over 12 months; not every activist campaign succeeds

### 2. Spinoff (Greenblatt-Quality Filter)
ALL of the following must be true:
- Form 10 filed (not S-1 — this is a spin, not an IPO)
- Management equity alignment (CEO of spin has equity grant aligned with new entity)
- Spin is SMALL relative to parent (< 30% of parent market cap)
- Clean balance sheet (no liabilities dumped from parent)
- Sector orphan (institutional holders won't keep it — forced selling creates value)

[SURPRISING]: Indiscriminate spinoff basket UNDERPERFORMED by ~2.7%/yr in last decade (SPUN ETF terminated 2020). Only Greenblatt-quality filtered spins retain edge.

Score: P=35, M=35, T=15. Composite = 85 → 1.5x multiplier. Apply ×1.15 special-situation conviction multiplier on top.

### 3. PEAD (Post-Earnings Announcement Drift)
**[SURPRISING]**: Strongest after the FIRST beat following multiple misses (turnaround signal), NOT after continuation beats. The 2nd beat-and-raise from a credibility nadir produces larger gains than the 1st.

Detection: Stock beats EPS by >10% AND beats revenue AND raises guidance, AFTER 2+ consecutive misses. Magnitude tends to be 5-12% over 60 days.

Score: P=40, M=25, T=20. Composite = 85.

### 4. "Exploring Strategic Alternatives" Announcement
SEC 8-K Item 7.01 (Regulation FD Disclosure) or Item 2.02 — exact language: "exploring strategic alternatives" or "review of strategic alternatives." Historical 75-85% completion rate.

Score: P=45, M=35, T=15. Composite = 95 → 1.5x to 2.0x multiplier depending on certainty.

### 5. Insider Cluster (Cohen-Malloy-Pomorski Opportunistic Filter)
- 3+ distinct insiders
- Form 4 Code P only (open-market purchase, not option exercise)
- Outside historical Form 4 pattern (must check insider's history)
- Rolling 90-day window
- CFO and CEO purchases weighted highest

Annualized alpha when filter met: ~8.8% (vs ~2-3% unfiltered insider buying). Score: P=35, M=20, T=15. Composite = 70 → 1.2x multiplier.

### 6. S&P 500 Deletion Opportunity
**[SURPRISING]**: Index DELETION creates a temporary asymmetric opportunity (5-day forced selling). Index INCLUSION does NOT — that alpha is dead (Greenwood-Sammon-Thesmar 2022).

Requirements for buy:
- Recent S&P 500 deletion (1-30 days post-effective date)
- Business fundamentals remain intact (vs. genuinely deteriorating, the usual reason for deletion)
- Liquidity hasn't permanently impaired

Score: P=40, M=25, T=22. Composite = 87 → 1.5x multiplier.

### 7. CFO Succession (Material 8-K)
[SURPRISING]: Often underappreciated. CFO is most knowledgeable about financials. New CFO from a higher-quality company = upgrade. New CFO from outside the industry = sometimes turnaround playbook.

Score: P=25, M=15, T=18. Composite = 58 → 1.0x multiplier.

## Catalyst Hopium (Anti-Patterns)

- **"The story is going to play out"** — without a specific named event with date range, this is hopium. Reject.
- **"It's so cheap something has to happen"** — Sears was cheap for 15 years.
- **"The new CEO will turn it around"** — wait for the operational evidence, not the announcement.
- **"Reggie Middleton said..." / Twitter hype** — not a catalyst.
- **"Analysts will eventually realize..."** — analysts already know. The information edge requires variant perception, not waiting for consensus to catch up.
- **Double-counting catalysts** — buyback + dividend increase + earnings beat from same earnings report = ONE catalyst, not three.

## Catalyst Inventory Requirements (Stage 5)

For each pick, document:
- **Catalyst 1 (primary)**: Name, type, score, evidence
- **Catalyst 2 (secondary, if exists)**: Same
- **Tertiary catalysts (optional)**

The thesis memo's "Catalyst Table" includes all of these with magnitude / probability / time / evidence columns.

If NO catalyst with score ≥ 20 exists, the candidate is DROPPED and pipeline returns to next candidate.
