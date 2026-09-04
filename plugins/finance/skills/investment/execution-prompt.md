# Investment Skill — 7-Stage Execution State Machine

You are executing the investment skill pipeline. Read this entire document before starting. The pipeline picks ONE US large/mid-cap stock for 1-5+ year holding using six expert frameworks synthesized into the CS100 conviction score.

## Prerequisites (check first)

1. **User context elicited?** If the user has not stated portfolio context, capital scale, temperament (drawdown tolerance), horizon, and sector constraints — STOP and ask. Do not proceed.
2. **Working directory?** Cache at `~/.cache/investment-skill/`. Create if missing.
3. **Scripts executable?** Run `chmod +x scripts/*.js` if first run. Verify Node.js ≥ 18.
4. **Internet?** Confirm SEC EDGAR (data.sec.gov), Wikipedia, FRED, and yahoo-finance reachable.

## Stage 1 — Universe Assembly (~30s)

Run in parallel:
```bash
node scripts/fetch-universe.js --output=cache > ~/.cache/investment-skill/universe.json
node scripts/fetch-macro.js > ~/.cache/investment-skill/macro.json
```

Output: `universe.json` with ~1,509 S&P 1500 tickers tagged by GICS sector + sub-industry; `macro.json` with current yield curve, ISM proxy, unemployment, CPI, classifying regime as one of: `early-cycle`, `mid-cycle`, `late-cycle`, `recession`, `recovery`.

If macro regime is `late-cycle` or shows CAPE > 38, apply a -3 to -5 tilt to ALL CS100 scores (Klarman discipline in expensive markets). In May 2026 with CAPE at 42, apply the -5 tilt.

## Stage 2 — First-Cut Screen (~110s)

For each ticker in universe, fetch quote in parallel batches of 20:
```bash
node scripts/fetch-quote.js TICKER1 TICKER2 ... > batch.json
```

Apply filters in order (drop on first fail):
1. Market cap ≥ $700M (S&P 600 floor; included anyway by index)
2. 30-day avg daily $ volume ≥ $5M (liquidity)
3. Sector in user's allowed list (apply exclusions)
4. Public for ≥ 2 years (need history)
5. Price/200-DMA > 0.60 (avoid catastrophic distress, but KEEP turnarounds)
6. Cheap quality proxy: (ROE TTM > 8%) OR (P/E < sector median × 0.7) OR (price/book < sector median)

Expected output: ~50 candidates. If <30 or >80, log warning but proceed.

## Stage 3 — Deep Fundamentals (~110s)

For each top-50 candidate, fetch in parallel batches of 10 using `Promise.allSettled()`:
```bash
node scripts/fetch-financials.js TICKER > financials/TICKER.json
node scripts/fetch-sec-facts.js TICKER > facts/TICKER.json
```

For each candidate, compute 6 framework scores per [`references/02-frameworks.md`](references/02-frameworks.md):
- F1: Buffett quality (ROIIC, owner earnings yield, $1-retained test)
- F2: Lynch GARP Value Ratio
- F3: Greenblatt EBIT/EV percentile (sector-neutral)
- F4: Piotroski F-score 0-9
- F5: AQR QMJ proxy (gross profitability + ROE + earnings stability + payout)
- F6: 12-1 momentum percentile

**Apply Beneish M-Score VETO**: Run `compute-fraud-check.js TICKER` for every candidate. M-Score > -1.78 → drop candidate, no score computed. Sloan accruals > 10% of avg assets → drop. Going-concern flagged in 10-K → drop.

Cross-section z-scoring with 1st/99th percentile winsorization. Then bundle:
- Quality bundle = avg(z(F1), z(F4), z(F5)) → 0-100 percentile
- Value bundle = avg(z(F2), z(F3)) → 0-100 percentile
- Momentum = F6 percentile → 0-100

## Stage 4 — Rank & Select Top 5 (~instant)

Apply CS100 formula per [`references/01-conviction-scoring.md`](references/01-conviction-scoring.md):
1. Classify each candidate into one of 5 stock-type buckets (compounder / GARP / value-turnaround / cyclical / financial). Use sector + ROIC + revenue-growth heuristics.
2. Apply the bucket's weight vector to (Quality, Value, Momentum).
3. Apply sector adjustment (±15) and macro regime tilt (±5).
4. Apply special-situation multipliers (×1.15 each, cap at ×1.50) if Greenblatt-quality spinoff / activist 13D / S&P 500 deletion / Cohen-Malloy-Pomorski insider cluster.
5. Output CS100 as range: point estimate ± dispersion.

**HARD REFUSAL**: If top CS100 < 55, OUTPUT "no qualifying pick — patient cash recommended" with the top 5 list for transparency. Do not proceed to Stage 5. End cleanly.

**Otherwise**: Display top 5 to user with one-line thesis each, ask: "Pick #1 unless you'd like to override." Wait for user confirmation OR override.

## Stage 5 — Deep Dive on Top Candidate (~55s)

Run in parallel for the chosen winner:
```bash
node scripts/fetch-insider.js TICKER > insider.json
node scripts/fetch-13f.js TICKER > 13f.json
```

Plus extract latest 10-K, 10-Q, and DEF 14A proxy text from EDGAR (already fetched in Stage 3 if cached).

Compute:
1. **Management quality scorecard (100 points)** per [`references/02-frameworks.md`](references/02-frameworks.md) — Capital Allocation 30, Compensation Alignment 25, Communication 20, Governance 15, Track Record 10. Hard ceiling at 70 if any "red flag override" present (option repricing, restatement history, CEO turnover <3y, related-party transactions).
2. **Catalyst inventory** per [`references/05-catalysts.md`](references/05-catalysts.md) — ≥1 catalyst required, scored 0-125 on probability × magnitude × time-to-event. Map to position size multiplier 0.5x to 2.0x.
3. **Reverse DCF** — given current price, solve for implied 10-year FCF CAGR. Compare to historical CAGR, sector growth, GDP. If implied > 15% for non-tech / > 25% for tech → flag as priced-for-perfection.
4. **3-scenario intrinsic value** — bear (5-10th percentile), base (50th), bull (90-95th). **FIXED weighting 20/60/20** (NOT user-tunable — prevents bull-case inflation). Expected value = 0.2 × bear + 0.6 × base + 0.2 × bull. Asymmetry ratio = (bull − current) / (current − bear). Require ≥ 2:1.
5. **Pre-mortem** — write down 3 specific things that could break the thesis in 18 months. For each, articulate "we invest anyway because…"
6. **Second-level check** — answer the variant-perception question explicitly: what does consensus believe; why is my view different; why is consensus wrong?

## Stage 6 — Thesis Memo Generation

Render memo using canonical template at [`references/08-thesis-memo-template.md`](references/08-thesis-memo-template.md). Required sections:
- One-line summary
- Conviction score with bundle breakdown (Quality / Value / Momentum + adjustments)
- Business description ("2-minute monologue" — Lynch test)
- Variant perception (the Steinhardt question)
- Valuation: 3 scenarios + reverse DCF cross-check
- Catalyst table
- Pre-mortem risks with "invest anyway" rationale
- Position size (Kelly-fractional, capital-scale-adjusted, temperament-adjusted)
- Entry zone (3-tranche plan from [`references/07-position-sizing.md`](references/07-position-sizing.md))
- Sell rules (9 rules from [`references/04-sell-rules.md`](references/04-sell-rules.md))
- Tracking plan (what to monitor, quarterly cadence)

## Stage 7 — Output + Picks Log

1. Display memo to user.
2. Append to `~/.cache/investment-skill/picks-log.jsonl`: timestamp, ticker, CS100, entry price, target tranches, sell rule triggers, next-reassessment date. This is an APPEND-ONLY accountability trail.
3. Footer: "Not financial advice. Verify all numbers. Markets are uncertain. Next reassessment: <date>."
4. If a catalyst with time-to-event < 90 days exists, schedule reassessment for that event date instead of default 90 days.

## Failure-Mode Table

| Failure | Detection | Response |
|---------|-----------|----------|
| SEC EDGAR rate-limited | 429 status | Back off 5s, retry. If 3 failures, fail loudly. |
| yfinance returns stale shares-outstanding | Data shift bug #2584 — compute from EDGAR XBRL CommonStockSharesOutstanding instead | Cross-check vs EDGAR; if >5% delta, prefer EDGAR. |
| Universe scrape fails | Wikipedia HTML change | Use cached universe (7-day TTL), warn user. |
| No candidate scores ≥ 55 | Stage 4 check | OUTPUT "patient cash" message + top 5 for transparency. End cleanly. |
| Top candidate triggers Beneish veto | Stage 3 fraud check | Drop, move to next candidate. Re-rank. |
| Catalyst inventory empty | Stage 5 step 2 | Drop candidate, return to Stage 4 with #2 pick. |
| Asymmetry ratio < 2:1 | Stage 5 step 4 | Flag as low-conviction but continue; reduce position size multiplier to 0.5x. |
| User overrides #1 pick at Stage 4 | User input | Proceed with override; record in picks log as user-driven not framework-driven. |

## State Restoration (if Resumed Mid-Pipeline)

If pipeline was interrupted, look at `~/.cache/investment-skill/state.json` for the last completed stage. Resume from there. Cache TTLs:
- universe.json: 7 days
- macro.json: 24 hours
- quote/*.json: 5 minutes
- financials/*.json: 7 days
- facts/*.json: 30 days
- insider/*.json: 24 hours
- 13f/*.json: 7 days

If TTL expired, re-fetch.

## Caveats This Pipeline Cannot Cover

- Foreign-domiciled with US ADRs: index already excludes these. Don't add back.
- Pre-IPO or recent SPAC: filtered in Stage 2.
- Special situations not in S&P 1500 universe: skill is scope-bounded. Acknowledge and stop.
- Tax-loss harvesting timing: defer to user's CPA.
- Margin/leverage: never recommended.
- Options strategies: out of scope.
