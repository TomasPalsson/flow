---
name: alpha-hunt-risk-sizing
description: Position sizing, the composite score + veto gate, momentum-crash throttle, drawdown discipline, and stop philosophy for an aggressive concentrated book. Load at scoring + sizing stages.
---

# Risk, Sizing & the Composite Score

Aggressive that survives. An aggressive concentrated weekly book has three compounding failure
modes generic advice ignores: estimation-error over-betting, momentum-crash convexity, and false
diversification. Each has a specific fix below.

---

## §0. The thresholds here are UNVALIDATED PRIORS

No backtest exists and no live track record exists. Every threshold in this file and in `signals.md`
— the 0.50/0.25/0.15/0.10 composite weights, the 10-25% Kelly fraction, the 18-25% vol-target band,
the drawdown constant — is an unvalidated prior imported from published literature or judgment, not a
finding earned from this book's own results. The learning loop and calibration machinery (§14,
`learning-loop.md`) are mechanically INERT until resolved trades exist to feed them. The hard caps
(§5, §10, §13) are therefore the only thing bounding worst-case loss — do not relax them.

---

## The composite score with a DISQUALIFYING VETO GATE

Do NOT use a simple weighted average — it lets one strong factor mask a fatal flaw. Use a
weighted composite z-score (quality/value/momentum/catalyst) — assembled by the orchestrator from the
**momentum sub-score** (`compute-momentum.js`) + **value/quality** (`fetch-quote.js`: EBIT/EV, ROE,
margins) + **catalyst flags** (`fetch-catalysts.js`) — THEN apply hard veto gates that CAP the score
regardless of the other factors:

**Veto gates (any one → cap score at 0 / drop):**
- Beneish M-Score > -1.78, OR Sloan accruals > 20% of avg total assets, OR going-concern footnote
  (`compute-fraud-check.js`). Fraud kills returns — no exceptions.
- No dated, specific catalyst (catalyst sleeve) → drop.
- Short-interest-driven candidate with no other thesis → drop (bearish on average).
- Pure FDA/PDUFA binary held blind → drop (or route to the 2-5% binary treatment).

**Override asymmetry:** the bar for overriding UP (buy despite a red flag) must be MUCH higher than
overriding DOWN (skip despite a good score). False negatives from a screen are cheap; false
positives that bypass a red flag are expensive.

---

## 1. Fractional Kelly at 10-25% of full — and at the CLUSTER level

**f_full = (p·(b+1) − 1) / b**, p = calibrated win probability, b = upside_pct/downside_pct. **f =
f_full × kelly_fraction** (locked 0.10-0.25 of full). Full order: cluster budget → inverse-vol split
(§4) → vol-target scalar → regime dial (§4) → hard caps (§5, §10, §13).

- Textbook 25-50% Kelly assumes well-quantified edge error. LLM/backtest edges carry far fatter
  error; if true edge is 30-50% smaller than estimated, full Kelly overbets multiplicatively and
  multiplies risk-of-ruin. Use **10-25% of naive full Kelly.**
- **Size at the cluster level, then split within the cluster** — never independent per-ticker Kelly.
  Two correlated 15% positions are one 30% bet on the shared factor.
- **MANDATORY: Stage 6 calls `node scripts/compute-sizing.js <input.json>` — NEVER compute weights
  freehand in prose.** Fixes llm-guardrails.md §13 ("the LLM never does arithmetic"), which the old
  freehand approach violated.

## 2. Effective Number of Bets — "10 picks" is really 3-6 bets
One screen (momentum + catalyst + short interest) draws from a narrow factor lineage; in stress,
correlations →1 regardless of the calm-period matrix. Cluster by **rolling pairwise correlation
(§12) as the factor-clustering PROXY**, with **GICS sector** (`fetch-universe.js`) as a cruder second
axis — what the pipeline actually computes today. Adding more names from the same screen adds
correlated exposure, not diversification; control concentration with sizing + regime filters, not by
adding names. **Upgrade path**: an Effective-Number-of-Bets measure from the eigenvalues of the
holdings covariance matrix (Meucci) — tractable in plain JS on a ≤15×15 matrix — beats either proxy
above; not yet built.

## 3. Momentum crash is a REBOUND phenomenon (the most important risk fact)
Worst losses hit when the market turns back UP after a decline while the book is still tilted. A
"cut exposure when the market falls" rule fires on the WRONG event. Fix:
- Scale position size inversely to the **strategy's OWN trailing 6-month realized volatility**
  (Barroso-Santa-Clara), targeting the 18-25% band (§4) — reported to be roughly a doubled Sharpe
  (~0.53→0.97), crash depth cut roughly -78.96%→-28.40% in dynamic variants. Those figures are for a
  long-SHORT WML portfolio whose crash is driven mostly by the SHORT leg (Daniel & Moskowitz: the
  loser portfolio's up-market beta sits far above its down-market beta) — a long-only book has no
  short leg and can't hit that specific tail, so vol-scaling is still right but this citation
  oversells the protection it buys THIS book.
- Own vol, NOT market VIX, NOT the underlying stocks' vol. **Bootstrap**: a brand-new book has no
  6-month own history — until ≥6 months of picks-log history exists, proxy with **MTUM's trailing
  realized vol** (same Yahoo v8 chart path already used elsewhere) instead of skipping the throttle.

## 4. Vol-target sizing (the default, beats equal-weight)
Target book realized vol in the **18-25% band** — a 5-15 name concentrated single-stock book has
natural annualized vol around 25-35%; targeting 12% would require holding ~60% cash permanently,
which contradicts the concentration mandate. Size each position so its dollar-vol contribution
Inverse-vol vs equal-weight reported to lift Sharpe roughly 0.99→1.54 and cut max DD roughly
-31%→-14% in one cited study.
**How the tilt is applied (`compute-sizing.js`, step 2b — BEFORE cluster budgeting, so cluster caps
bind on vol-adjusted numbers).** Kelly sizes on EDGE and is blind to volatility, so each `f` is
scaled by **(book median vol / own vol)**, clamped to **[0.5x, 2.0x]**:
- Anchoring on the MEDIAN makes this a relative tilt — the typical position is untouched and weight is
  redistributed, not inflated. (It is not strictly gross-neutral: a right-skewed vol distribution
  lifts gross modestly. The hard caps and the regime dial still bound it.)
- The clamp is deliberate. Unclamped `1/vol` levers a very low-vol name up several-fold on the
  strength of a vol *estimate*; a conviction book should tilt, not lever.
- **Why this exists**: without it, a name that is the sole member of its cluster never had its vol
  considered at all — a 5-name book of uncorrelated names got IDENTICAL weights at equal conviction
  whether a name ran 18% or 33% vol, leaving the riskiest names to quietly dominate realized vol.
  A self-test assertion (`--self-test`) locks the behaviour in.
- The within-cluster split (confidence/vol) still applies on top for multi-name clusters.

Per-name `realized_vol_annual` and the MTUM `vol_proxy` bootstrap both come from
`compute-momentum.js`; neither is ever an LLM estimate.
**Order (`compute-sizing.js`), each applied ONCE — no other mechanism may re-apply either:**
(1) vol-target scalar `s = min(1, book_vol_target / book_realized_vol)`; (2) regime dial (Stage 1
output), applied LAST, never stacked with #1.

## 5. Binary-catalyst hard cap (2-5%), overriding vol-target
Gaps jump through stops (planned 2% loss → realized 10-15%). Worse: a binary shows LOW pre-event
vol, so naive vol-target OVERSIZES it — exactly backwards. **Flat 2-5% cap on any binary-catalyst
position regardless of conviction, as a hard override on top of vol-target.**

**Options-implied signals and the sentiment veto are NOT sizing inputs.** `compute-options-signals.js`
(IV skew / vol spread / O-S ratio) is a **conviction confirmer-or-demerit on the catalyst sleeve
only** — it can raise or lower confidence going INTO Kelly, never touch a weight directly.
`fetch-sentiment.js` (ApeWisdom mention z-score) is **VETO/TRIM only** — a high mention_z drops or
trims an otherwise-good candidate, it never sources or sizes one. Sizing (§1-§4 above, §13 below)
depends ONLY on the inputs `compute-sizing.js` accepts (confidence, upside_pct, downside_pct,
realized_vol_annual, regime_dial) — neither script's output is a field
in that input schema, and neither should ever be smuggled in as one.

## 6. Stop philosophy — horizon-dependent
- **Technical / momentum trades** → trailing price stops earn their keep (cut DD 50%+ in trending
  regimes) but multiply small whipsaw losses. Use them; expect whipsaw. **Default width: a
  Chandelier exit** — stop = (highest close since entry) − 3 × ATR(22 DAILY bars). A stop rule with
  no width is not actionable. **This is now REAL, not aspirational**: run
  `node scripts/compute-atr.js <shortlist> [--entry TICKER=YYYY-MM-DD]` at the point sizing
  happens, for the ~15-25 shortlisted/held names only — NEVER the 1,500-name weekly universe
  screen (see the trap below). It fetches its own **daily** bars (keyless Yahoo endpoint) and
  computes Wilder ATR(22), independent of `compute-momentum.js`'s weekly-cadence `adjclose`-only
  series.
  **The trap that made this NOT-IMPLEMENTED for so long stays documented on purpose**: the
  universe screen pulls **weekly** bars, and ATR(22) computed on weekly bars spans ~5 months, not
  the ~1 month LeBeau's Chandelier intends — reusing that data silently produces a far-too-wide
  stop rather than an obviously missing one. Never retrofit ATR onto the weekly universe series;
  `compute-atr.js` fetches its own daily series specifically to avoid this.
  **`--entry TICKER=YYYY-MM-DD` is optional.** Supply it once a position is actually entered, and
  the stop anchors to the highest close SINCE that entry date (`entry_anchored: true`). Without
  it, the script falls back to the trailing 60-day highest close (`entry_anchored: false`) — that
  is an APPROXIMATION, not a true since-entry stop, and reads wider or narrower than the real
  Chandelier depending on where the 60-day high fell relative to entry. Treat `entry_anchored`
  as a first-class field, not metadata to ignore.
- **Catalyst / fundamental trades** → thesis-invalidation exit + a hard size cap, NOT a tight price
  stop (which exits on noise). The stop is at a logical invalidation point, defined by the REASON,
  not a price %.
- Stops COST expected return; they buy lower tail risk (Calmar), not free safety. **Caveat**: Han,
  Zhou & Zhu (2014) and Kaminski & Lo (2014) measure diversified portfolios / asset-class trend
  strategies, NOT single names in a concentrated 5-15 name book — don't cite a "Sharpe roughly
  doubles" result as proven here; treat it as directionally supportive only.
- **Book-level regime de-gross trigger > per-stock stops** for crash protection (per-stock stops on
  losers can force selling into the trough right before the rebound that defines a momentum crash).

## 7. Track Calmar, not just Sharpe
Two strategies with identical Sharpe can have wildly different max DD. High-Sharpe/low-Calmar =
hidden crash risk. Calmar = CAGR / max DD. Screen candidate strategies on Calmar too.

## 8. Drawdown discipline — soft trigger BEFORE hard kill (pod-shop pattern)
A fixed **2.5-3% from book peak** is a multi-manager pod-risk number calibrated for ~10% vol books —
this book runs 25-35% vol, where 2.5-3% is ordinary weekly noise and a fixed trigger would fire
almost continuously. (That 2.5-3% figure traces to practitioner-blog sources, not a primary risk
manual — treat it as directional color, not a hard-sourced fact.) Use a **vol-scaled soft trigger**
instead: **0.15-0.20 × trailing 4-week realized book vol**, floored at 2% and capped at 6%. The
published/hard threshold is a backstop; the soft number is the real control point where you actually
start reducing. Build the soft trigger deliberately — don't only define the kill switch.

## 9. Cadence-aware conviction threshold
Every week of turnover taxes the edge — but NOT via market impact (an institutional-size effect,
~zero at retail order size; Frazzini, Israel & Moskowitz measured median institutional costs ~6.2bp
for context, well above this book's scale). The real cost is the platform's **flat fee + spread**,
REGRESSIVE with position size — it hurts SMALL positions hardest, the opposite of an impact model.
Practical implication: a **minimum sensible position size**, not a penalty on large ones. Require a
BIGGER expected edge to justify replacing a held small/mid-cap name than a liquid large-cap. ≤2-3 new
positions/week; stagger into 3-5 tranches; keep dry powder.

## 10. eToro execution envelope
Long-only, `Leverage: 1`. Present target weights as % of equity to the `etoro` skill. No CFDs, no
leveraged ETFs for multi-day holds. Concentration cap: top 5 positions ≤ ~55-60% of book; single
position soft-cap ~20-25% (a genuinely aggressive ceiling), binary positions 2-5%.

## 11. Managing the existing book — sell / trim / hold (Stage 1b)
The book is never cash-flat; each weekly run inherits open positions and MUST manage them, not just
hunt new adds. The exit doctrine (§6-8) applied to *held* positions. Sell or trim on ANY trigger,
else hold — the user's mandate is to sell whenever it's judged right, so these are the discipline
behind the judgment, not a checklist to satisfy mechanically:
- **Thesis broken** — the entry reason no longer holds (fundamental, not a price %). Full exit. A
  **rehashed/recycled news story** driving the move is a FADE, not confirmation — never average
  down into it. A **4.02 non-reliance/restatement 8-K** is a thesis-broken trigger in its own
  right — the market has priced the wrong numbers; it is never a dip to buy.
- **Catalyst passed** — the dated catalyst resolved (drift captured or thesis wrong). Exit, redeploy.
- **Momentum break** — RETAIN BAND (quantitative form of the two-clock rule): enter only top-decile
  composite; do NOT sell on rank slippage until the name falls below the **top 30-40%** of the ranked
  universe (mirrors MSCI's 50% semi-annual turnover buffer; Novy-Marx & Velikov 2016 find buy/hold
  bands the single most effective turnover-cost mitigation). **Guard**: valid only if `n_scored` is
  materially unchanged vs the prior snapshot (`compute-momentum.js` emits `n_input_tickers`/`n_scored`)
  — a drop from fewer names scored is an artifact, not a momentum break.
- **Time stop** — sleeve-specific, since the three signal families decay on measurably different
  curves: **momentum ~4-6 months** (Jegadeesh & Titman), **PEAD ~6-9 weeks / 30-60 trading days**
  (Bernard & Thomas), **insider cluster ~6-12 months** (Cohen, Malloy & Pomorski). Stagnant past its
  sleeve's horizon with no thesis progress → free capital + attention.
- **Overvaluation extreme** — top ~5% of its own history → TRIM; top ~0.5% → full exit.
- **Drawdown soft-trigger** — the vol-scaled soft-review level (§8) or the position's pre-registered
  stop (§6 Chandelier exit) → reduce now, ahead of the hard kill.
- **Out-of-mandate** — not a US large/mid-cap long (crypto, leveraged products, shorts). alpha-hunt
  can't run its discipline on these → default to exiting to redeploy, unless a clear dated near-term
  reason to hold (then TRIM + flag). Judgment, not a reflexive dump.
- **Concentration** — single position > ~20-25% of equity → TRIM to target.
Every qualitative exit reason logged MUST carry its numeric cross-check alongside it (the band
position, the weeks held, the stop level) — a tripwire against post-hoc rationalization on the sell
side.
Execution: partial close (`UnitsToDeduct` = units) for trims, full close (`UnitsToDeduct: null`)
for exits, via the `etoro` skill; space ≥3s, wait 60s for the PnL cache before re-reading freed cash.
Log every decision + trigger to `picks-log.jsonl` (HOLDs too) for weekly continuity and calibration.

## 12. Correlation-of-holdings throttle (make ENB real — from persisted OHLC returns)
The "10 picks = 3 bets" warning (§2) becomes operational: compute the **rolling 60-day pairwise
correlation** across current + proposed holdings from `~/.cache/alpha-hunt/returns-series.json` —
`compute-momentum.js` now persists this on every run; it previously wasn't persisted anywhere,
despite this section claiming the data was "already in the pipeline." When 3+ positions show rising
co-movement (or rising correlation to MTUM / the momentum factor), you're building one leveraged
factor bet — **soft-de-gross** just as the VIX/regime dial would. This is a distinct throttle from
the market-regime dial: it fires on book-internal crowding, not market state.

## 13. Capacity / ADV ceiling — the small-account edge, enforced
Cap every position at **min(cluster-Kelly $, ~1-2% of the name's 20-day ADV)**, using
`avg_daily_dollar_volume_10d` (fall back to `avg_daily_dollar_volume_3mo`) from `fetch-quote.js`.
This is why Medallion self-caps: it structurally keeps the book in the illiquid small-cap lane where
retail has a real capacity edge (§ "stay small" in signals.md), stops slippage from eating the edge,
and prevents future account growth from silently drifting into mega-caps with zero retail edge.
**At small retail account size this cap will rarely bind** — LOG it as a monitoring number, not an
active constraint, until account growth makes it load-bearing; from then it IS the moat, not a
constraint to route around.

## 14. Anti-overfitting: Deflated Sharpe — once there's a track record big enough to deflate
The DSR mandate is asserted in three separate files for a live track record that will carry
single-digit N per signal family for months; a DSR on N≈6 is theater, not rigor. **Conditional
trigger, not an unconditional mandate**: compute a Deflated Sharpe Ratio (López de Prado) before
trusting a backtested/tuned number (a new signal weight, a regime threshold, a Kelly multiplier) only
once **≥30 resolved trades exist for the signal family in question**. Until then, say it plainly:
every threshold in this skill is an **unvalidated prior**, not a finding. The full rationale + the
per-sleeve performance throttle live in [`learning-loop.md`](learning-loop.md) §7 — **load it when
tuning weights or sizing multipliers.**
