---
name: alpha-hunt-regime-throttle
description: The gross-exposure dial — a few robust regime inputs (distribution days, breadth divergence, VIX term structure, credit spreads) into a -3..+3 score that scales the whole book. Load at Stage 1.
---

# Regime Throttle — The Gross-Exposure Dial

Set ONCE per run, before picking anything. An aggressive book MUST throttle gross exposure DOWN
mechanically before a human "feels" the shift — the 2025-26 unwinds resolved in DAYS via forced
deleveraging, not slow rotation. Keep it a **few robust, independently-sourced inputs**, not one
over-fit composite. Score each input −1 / 0 / +1, sum to a −3..+3 score, map to a gross-exposure %.

## Inputs (each scored −1 / 0 / +1)

### 1. Distribution-day count (the trend-pressure gauge)
A distribution day = a major index down **≥0.2% on volume higher than the PRIOR day** (not
necessarily above average — common misunderstanding). Count only within the **trailing 25 sessions**.
- ≤3 in 3-4 weeks → +1 (healthy)
- 4-5 → 0 (under pressure)
- ≥6 → −1 (correction likely: cut exposure to 20-40%, halt new buys)
Recovery is confirmed ONLY by a **Follow-Through Day**: a major index up **≥1.25% on higher volume
than the prior day, on day 4-10 of a rally attempt** (a thrust on days 1-3 is discounted as noise).

### 2. Breadth + divergence (% of S&P 500 above 200-day MA)
- >70% → +1 (broad participation)
- 30-70% → 0
- <30% → −1 (oversold — but often precedes recovery; pair with trend)
**Divergence overrides level**: index making new highs WHILE this % falls = trend exhaustion → force
this input to −1 regardless of the absolute level. Diff breadth vs the index's new-high status.

### 3. VIX TERM STRUCTURE — shape, not level
Same VIX print means different things by curve shape. Check contango vs backwardation:
- Contango (normal), any level ≤25 → +1
- Contango but VIX elevated (25-30) → 0
- **Backwardation / flattening curve, especially VIX 25-30 → −1 (de-risk aggressively)**
A level-only rule both over- and under-reacts. If you can only get VIX level (no term structure),
treat >30 as −1 and <20 as +1, but prefer the shape.

### 4. Credit spreads (HY-IG) — the LEADING signal
The earliest warning is **HY-IG spread WIDENING while equity implied vol stays calm** (credit
stressed, equity complacent) — credit leads equity at turning points. From FRED `BAMLH0A0HYM2`:
- Spread stable/tightening → +1
- Widening modestly → 0
- Widening sharply while VIX calm → −1 (earliest warning class; omitting credit misses it)

## Fetching the inputs (runtime data paths — no input left unsourced)
`node scripts/fetch-regime.js` fetches the first three inputs below with a 10s-per-request TIMEOUT
guard (a stalled proxied socket must never hang the run) and emits a partial -3..+3 score; breadth
is aggregated by the orchestrator. Manual/underlying paths:
- **Distribution days**: Yahoo v8 chart on `SPY` (or `^GSPC`), `range=3mo&interval=1d`. Count days in
  the trailing 25 sessions with close down ≥0.2% AND volume > the prior session's. Follow-Through Day
  = a day up ≥1.25% on higher volume, on day 4-10 of a rally attempt.
- **Breadth (% above 200DMA)**: aggregate from the SAME universe pull `compute-momentum.js` already
  fetches (2y weekly per name) — fraction of the universe whose last close exceeds its own ~40-week
  (200-day) average. Lighter proxy: RSP/SPY (equal- vs cap-weighted) ratio trend via Yahoo v8 chart.
- **VIX term structure**: Yahoo v8 chart on `^VIX` and `^VIX3M`; ratio = VIX / VIX3M. `fetch-regime.js`
  scores this with a **DEAD BAND, not a 1.0 crossover**: ratio **>1.05** = backwardation (stress) → −1;
  **<0.95** = contango (calm) → +1; **0.95-1.05 → 0** (neutral). The band is deliberate — a bare >1/<1
  rule flip-flops the whole dial on noise while the curve sits flat near parity. This gives the SHAPE
  the level alone can't.
- **Credit spreads**: FRED `BAMLH0A0HYM2` (keyed API or keyless fredgraph.csv) — level + 4-week change.
- **Zweig thrust** (optional re-entry override): needs NYSE advance/decline breadth; if unavailable,
  treat as a manual override the user can supply, not a blocking input.

## Score → gross-exposure dial

| Regime score | Gross exposure | Posture |
|---|---|---|
| +2 to +3 | 90-100% | Full aggression; lean into breadth-confirmed uptrend |
| 0 to +1 | 60-85% | Normal; selective new entries |
| −1 | 40-55% | Defensive; trim to targets, few/no new buys |
| −2 to −3 | 0-40% | Hostile; throttle hard, no new buys, "cash is a position" |

Multiply every position's target weight by the dial. A hostile-regime run legitimately outputs
"throttle/trim, no new buys" — that is a high-information result, not a failure to find picks.

## Zweig Breadth Thrust — the rare re-entry override
10-day EMA of advancing / (advancing+declining) issues moving **from <40% to >61.5% within 10
trading days** = a rare, high-conviction "the correction is over" signal. Treat as a special-case
override that can lift the dial faster than the slow inputs would — not a routine weekly input.

## THE LLM CORRECTION (do not skip)
LLM traders are documented to get regime backwards — **timid in bull markets, reckless in bear.**
An "aggressive" skill left uncorrected AMPLIFIES this. So the dial must be obeyed mechanically:
lean INTO +2/+3 regimes (this is where aggression pays), and throttle HARD in −2/−3 regimes even
when individual names look exciting. Aggression is regime-conditional, not constant.

## Signal decay tracking
Momentum-family half-lives are now ~12 months — quarterly recalibration is already too slow.
Track each signal family's **rolling 13-week** realized hit-rate/slugging; down-weight or bench a
family whose realized stats decayed vs its own trailing baseline. Distinguish genuine decay from a
one-off forced-deleveraging week (a single liquidity event breaks every signal temporarily — don't
bench a good signal because of one March-2025-style week).
