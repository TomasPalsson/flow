---
name: investment
description: Pick one US large/mid-cap stock for 1-5+ year holding using multi-framework analysis (Buffett quality, Lynch GARP, Greenblatt value, Piotroski, AQR QMJ, momentum) with Beneish fraud veto and Kelly-sized position. Use WHENEVER the user asks to find a stock to invest in, what to buy, pick a stock, when to sell, run a stock thesis, do intrinsic-value or reverse DCF, screen S&P 1500, or invokes /investment. Do NOT use for tax optimization, options, day trading, crypto, foreign markets, or short selling.
---

# Investment — Expert-Grade Stock Picker

## What This Skill Does

When invoked, this skill picks ONE US large/mid-cap stock (S&P 1500 universe) for a 1-5+ year hold, applying six expert frameworks in parallel and synthesizing them into a single conviction-scored thesis with entry zone, sell rules, and Kelly-sized position. It refuses to pick if no candidate is good enough.

**Hard guarantee**: The skill will produce no pick when the top-scoring candidate is below the conviction floor (CS100 < 55). "Patient cash" is a valid output. This models Klarman's discipline; in May 2026 with CAPE at 42, this matters.

**Hard veto**: Any candidate triggering Beneish M-Score > -1.78 OR Sloan accruals > 20% of avg total assets OR a 10-K "going concern" footnote is rejected without further consideration, regardless of other framework scores. Sloan accruals in the 10-20% range trigger the YELLOW protocol (-5 Quality bundle penalty + mandatory pre-mortem) — see [`references/06-red-flags-fraud.md`](references/06-red-flags-fraud.md).

## The Honest Framing — Read First, Every Time

This skill DOES NOT predict the future. It applies systematized expert frameworks to current public data to produce a conviction-scored thesis. Multi-framework signals have historical academic backing (Asness "Value and Momentum Everywhere" Sharpe 1.45 combined, post-publication decay applies). **This is not financial advice.** The user owns every decision.

Before any pick, the skill MUST elicit:
1. **Portfolio context**: total invested capital? existing concentration? this would be what % of total?
2. **Capital scale**: <$50K (Kelly math breaks, use simpler heuristics), $50K-$5M (standard), >$5M (liquidity and tax-lot considerations active)
3. **Temperament**: can the user tolerate a 35-50% drawdown without panic-selling? If no → recommend index funds instead, stop here.
4. **Horizon match**: confirms ≥1 year holding intent. If <1 year, this skill is wrong tool; redirect.
5. **Sector constraints**: any sector exclusions (ESG, geopolitical, personal)?

If any of these are unanswered when the skill starts work, ASK FIRST. Do not proceed assuming defaults.

## The Mindset Before Computing Anything

Before you fetch a single number, anchor yourself in three frames that separate this skill from generic "stock screener" output:

**1. The market is mostly right, mostly.** If a stock screens cheap, ask first: *what does the consensus know that I don't?* The variant perception (Steinhardt question) is the alpha; the framework numbers are how we test whether the variant perception survives scrutiny. A high CS100 score with no articulable variant perception is a coincidence, not a thesis.

**2. The strongest signal is what you choose NOT to pick.** Klarman: "Cash discipline is the foundation of opportunism." With CAPE at 42 in May 2026, "no qualifying pick — patient cash" is a higher-information output than a marginal pick. The CS100 < 55 refusal is a feature, not a bug. Resist the pressure to produce a recommendation.

**3. Position size matters more than ticker choice.** Even an outstanding pick can ruin a portfolio if oversized for the user's true temperament and capital scale. Half the work of this skill is sizing correctly. If the user has not articulated portfolio context, capital scale, drawdown tolerance, and horizon — that conversation comes first, before any data fetch.

## Execution Pipeline

The full state machine lives in [`execution-prompt.md`](execution-prompt.md). **MANDATORY — READ ENTIRE FILE** before running the pipeline. **Do NOT load** for simple questions like "explain CS100" or "what does the Beneish M-Score do?" — those don't require running the pipeline. Summary of the 7 stages:

1. **Universe Assembly** — `scripts/fetch-universe.js` + `scripts/fetch-macro.js` in parallel. Produces ~1,509 S&P 1500 tickers tagged by GICS sector, plus current macro regime signal from FRED.
2. **First-Cut Screen** — `scripts/fetch-quote.js` in batches of 20. Reduces to ~50 candidates via: market cap, liquidity (>$5M ADV), recent IPO exclusion (>2y public), sector exclusion (user-specified), distress filter (price/200DMA > 0.60 — keeps turnarounds), cheap quality proxy.
3. **Deep Fundamentals** — `scripts/fetch-financials.js` + `scripts/fetch-sec-facts.js` parallel batches of 10. Computes the 6 framework scores per candidate. Cross-section z-scoring with 1/99 winsorization. Bundle construction (Quality / Value / Momentum). Sector adjustments per [`references/03-sector-playbooks.md`](references/03-sector-playbooks.md). **Beneish M-Score VETO applied here** — fraud candidates dropped, no exceptions.
4. **Rank & Select Top 5** — Apply CS100 formula from [`references/01-conviction-scoring.md`](references/01-conviction-scoring.md) with macro regime tilt (±5 max). Hard refuse if top score < 55. Display top 5 to user with one-line summary each so they can OVERRIDE the #1 pick before deep-dive.
5. **Deep Dive on Top Candidate** — `scripts/fetch-insider.js` + `scripts/fetch-13f.js` parallel. Apply management quality scorecard, catalyst scoring (0-125), reverse DCF (what growth is priced in?), three-scenario IV with fixed 20/60/20 weights (prevents bull-case inflation), structured pre-mortem.
6. **Thesis Memo Generation** — Render canonical template from [`references/08-thesis-memo-template.md`](references/08-thesis-memo-template.md). Bull/base/bear scenarios, catalyst table, pre-mortem risks, entry zone (3-tranche plan), sell rules, position size with Kelly fraction.
7. **Output + Tracking** — Present memo. Append to `~/.cache/investment-skill/picks-log.jsonl` for accountability. Schedule quarterly reassessment reminder.

Expected runtime: 5-10 minutes cold, 1-3 minutes warm (caches under `~/.cache/investment-skill/` with 7-day TTL for fundamentals, 5-minute TTL for quotes).

## The Six Frameworks — Briefly

Each framework produces a percentile score within the deep-fundamentals universe (top decile = 90+). Bundle z-scores combine correlated frameworks.

| Framework | Bundle | Core Metric | Buy Threshold |
|-----------|--------|-------------|---------------|
| Buffett quality | Quality | ROIIC > 15% sustained 5y, owner earnings yield | Top 30% |
| Piotroski F-score | Quality | 9 binary financial-statement signals | ≥7/9 |
| AQR QMJ (or proxy) | Quality | Profitability + growth + safety + payout | Top 30% |
| Greenblatt EBIT/EV | Value | Sector-neutral percentile only (NOT absolute screen) | Top 30% in sector |
| Lynch GARP | Value | Value Ratio = (g% + div yield%) / P/E ≥ 2.0 | ≥ 2.0 |
| 12-1 Momentum | Momentum | Trailing 12-month return skipping last month | Top 30% |

**Magic Formula as a primary screen is dead post-2010** (Novy-Marx-Medhat 2025). EBIT/EV survives only as sector-neutral relative percentile. See [`references/02-frameworks.md`](references/02-frameworks.md) for full specifications.

## Conviction Scoring (CS100)

**MANDATORY — READ ENTIRE FILE** before computing CS100 (Stage 3-4): load [`references/01-conviction-scoring.md`](references/01-conviction-scoring.md). **Do NOT load** before reaching Stage 3 — earlier stages don't compute CS100. The formula has 5 stock-type buckets (compounder / cyclical / financial / special-situation / turnaround) each with different framework weights — equal 1/3 across the board fails on financials, cyclicals at peak, and quality-floor cases (proven in CS100 stress test against MSFT, INTC, NVDA, JPM, GEV).

Output is a confidence RANGE not a point: e.g., CS100 = 72 ±5 (high conviction), CS100 = 58 ±15 (uncertain, edge case).

Composite weights summarized below; full routing logic in the reference:

| Stock Type | Quality | Value | Momentum | Notes |
|-----------|---------|-------|----------|-------|
| Wide-moat compounder | 60% | 20% | 20% | Buffett-archetype |
| GARP / Lynch fast grower | 35% | 35% | 30% | Standard balanced |
| Deep value / turnaround | 20% | 60% | 20% | Quality floor still applies |
| Cyclical | 30% | 40% (cycle-normalized) | 30% | EBIT must be normalized to mid-cycle |
| Financial | Custom — see sector playbook | — | — | ROE / P/TBV / CET1 / combined ratio replace standard metrics |

Special-situation conviction multipliers (apply AFTER CS100):
- Greenblatt-quality spinoff (5 criteria met): ×1.15
- Activist 13D from top-tier fund + thesis confirmed: ×1.15
- S&P 500 DELETION with fundamentals intact (NOT inclusion): ×1.15
- Cluster + opportunistic insider buy (Cohen-Malloy-Pomorski filter): ×1.15
- Cap: cumulative multiplier ≤ ×1.50

## Sell Rules — Built Into the Thesis Memo

Every pick comes with EXPLICIT sell rules written down at entry (pre-mortem at purchase). **MANDATORY — READ ENTIRE FILE**: Load [`references/04-sell-rules.md`](references/04-sell-rules.md) when generating the thesis memo's sell-rules section. **Do NOT load** when only computing CS100 or doing first-cut screening — the sell rules apply at thesis-memo time, not screen time. Summary of the 9 rules:

1. **Thesis broken** (5 sub-triggers, mandatory exit within 30 days)
2. **Opportunity cost** — only if new opportunity is ≥15-20% better risk-adjusted, all conditions simultaneously met
3. **Overvaluation extreme** — top 5% historical = trim; top 0.5% = full exit
4. **Pre-mortem trigger fires** — reassess within 72 hours
5. **Insider cluster selling** — graduated 3-tier response
6. **Dividend cut** (especially for REITs / utilities / financials)
7. **Tax-aware** — long vs short term, wash sale, IRA mechanics
8. **Quarterly reassessment cadence** — 3-question protocol
9. **Concentration rebalancing** — trim if >20% of portfolio

**Sell rules are written in FUNDAMENTAL terms (ROIC < WACC for 2 years), not price-percentage terms (down 20%)** — this is deliberate. Price-based stops induce momentum-trading behavior; fundamental triggers preserve thesis discipline.

## Catalysts

Without a catalyst, value can stay cheap forever (Sears 15 years). Every pick must have ≥1 identified catalyst. **MANDATORY — READ ENTIRE FILE** when running Stage 5 catalyst inventory: load [`references/05-catalysts.md`](references/05-catalysts.md). **Do NOT load** during CS100 computation or first-cut screening — catalyst scoring is a Stage 5 step. Catalyst quality scored 0-125 on (probability × magnitude × time), maps to position-size multiplier 0.5x to 2.0x.

## Position Sizing

Half-Kelly default; quarter-Kelly for uncertain or edge-case cases. Hard caps: 25% single position, 40% sector. Capital-scale adjustments:
- <$50K: skip Kelly entirely, use 5-10% sizing (psychological + commission tolerances)
- $50K-$5M: standard half-Kelly
- >$5M: half-Kelly but liquidity-clamped to <5% of stock's 30-day ADV
- Temperament factor: if user said "high drawdown tolerance" use half-Kelly; if "moderate" use third-Kelly; if "low" stop and recommend ETF.

**MANDATORY — READ ENTIRE FILE** when computing final position size in the thesis memo: load [`references/07-position-sizing.md`](references/07-position-sizing.md). **Do NOT load** during screening — position sizing is the last Stage 6 step.

## Sector-Specific Playbooks

Standard frameworks BREAK for several sectors. **MANDATORY — READ ENTIRE FILE** when ANY candidate in the deep-fundamentals universe (Stage 3) is in any of these sectors: load [`references/03-sector-playbooks.md`](references/03-sector-playbooks.md). **Do NOT load** if the universe contains zero candidates in the sectors listed below — that's wasted tokens.

- **Banks** → P/TBV, ROTCE, efficiency ratio, NIM, CET1 (not P/E + ROIC)
- **Insurance** → combined ratio, float economics, reserve adequacy
- **REITs** → FFO/AFFO, cap rates, NAV (not earnings)
- **SaaS** → Rule of 40, NRR, magic number, EV/NTM Revenue cohorts
- **Biotech** → rNPV with phase probabilities, cash runway (not DCF)
- **Cyclicals** → normalized earnings 5-7y avg, mid-cycle margin, capacity utilization (P/E lies; high P/E at trough = good, low at peak = bad)
- **Energy** → reserve life, AISC, strip vs spot
- **Consumer brands** → gross margin stability as brand-equity proxy

## Red Flags & Fraud Veto

**MANDATORY — READ ENTIRE FILE** before Stage 3 scoring: load [`references/06-red-flags-fraud.md`](references/06-red-flags-fraud.md) — value-trap catalog (7 patterns), growth-trap catalog (6 patterns), and fraud detection layer (Beneish M-Score, Sloan accruals, Dechow F-score). **The Beneish M-Score check is a HARD VETO, not a score component** — any candidate above -1.78 is dropped from consideration even if every other signal is strong. Use `scripts/compute-fraud-check.js TICKER` at runtime. An `overall_verdict` of `UNKNOWN` means the veto could NOT compute (missing SEC facts) — treat it as UN-VETTED (manual review), never as a clean PASS.

## Macro Regime Adjustment

**MANDATORY — READ ENTIRE FILE** at pipeline start (Stage 1 macro fetch + interpretation): load [`references/09-macro-regime-2026.md`](references/09-macro-regime-2026.md) — current (May 2026) regime read. **Do NOT re-load** after Stage 1 since the regime tilt is computed once per pipeline run. **Critical 2026 context**: CAPE at 42 (only second time in history above 40 — the prior was Dec 1999), Mag 7 -4.9% YTD, yield curve re-normalized after 26-month inversion (historically a recession precursor), Energy/Materials leading. The skill MUST inject this regime read as a ±5 tilt to CS100 and warn the user explicitly that we are in extreme overvaluation territory. The "patient cash" outcome is more likely than usual in this regime.

## Second-Level Questions (Marks)

Before finalizing the pick, run the 20 second-level questions. **MANDATORY — READ ENTIRE FILE** when entering Stage 5 deep-dive: load [`references/10-second-level-questions.md`](references/10-second-level-questions.md). **Do NOT load** during earlier screening stages. At minimum, the thesis memo must answer: "What does the market believe about this stock that I think is wrong, and why is my view variant?"

## Thesis Memo Output

The final output uses the canonical template. **MANDATORY — READ ENTIRE FILE** when entering Stage 6 thesis-memo generation: load [`references/08-thesis-memo-template.md`](references/08-thesis-memo-template.md). **Do NOT load** earlier in the pipeline. Required sections: one-line summary, conviction score with bundle breakdown, business description (2-minute monologue), variant perception (Steinhardt test), 3-scenario valuation, catalyst table, pre-mortem with "why we invest anyway" per risk, position size with Kelly rationale, entry zone with tranches, exit rules, tracking plan.

## Critical Anti-Patterns (Things This Skill MUST NOT Do)

- **Never proceed without portfolio/temperament/horizon elicitation.** A pick without context can ruin a user.
- **Never override the CS100 < 55 refusal.** "Patient cash" is a valid output, especially in May 2026.
- **Never bypass the Beneish M-Score veto.** Fraud kills returns.
- **Never use price-based stop-losses in sell rules.** Use fundamental triggers.
- **Never claim certainty.** Output CS100 as a RANGE. Use language like "the framework suggests" not "this will."
- **Never recommend without a catalyst.** Value-traps live in the no-catalyst zone.
- **Never apply equal framework weights to financials.** They are structurally different. Route to sector playbook.
- **Never add SBC back without diluted share count adjustment.** This is the classic adjusted-EBITDA fraud.
- **Never claim "I'm confident in this pick" — instead say "this scored highest in the framework; here's why and here's what could go wrong."**

## End-of-Run Discipline

Always end with: the thesis memo (or "no pick — patient cash"), the picks-log entry confirmation, the "not financial advice" footer, and the next reassessment date. Full operational details (parallelization, rate limits, caching) live in [`execution-prompt.md`](execution-prompt.md) — they are pipeline mechanics, not skill-body content.
