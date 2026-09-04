---
name: alpha-hunt-execution
description: The weekly 8-stage state machine for the alpha-hunt pipeline. Loaded by SKILL.md before a run.
---

# Alpha-Hunt — Weekly Execution State Machine

You are executing one weekly `alpha-hunt` run. This file is self-contained: assume you have the
SKILL.md mindset but re-derive all state from disk. Skill root is the directory containing SKILL.md;
all script paths below are relative to it. Reuse the `investment` skill's scripts from
`../investment/scripts/` (see `references/data-runbook.md` for the exact reuse inventory).

## State restoration (do this before Stage 1)

0. **`bash scripts/state.sh load`** FIRST — the routine runs with `persist_session=false` in a fresh
   container, so `~/.cache/alpha-hunt/` is WIPED every week. This restores picks-log.jsonl,
   signal-perf.json, and holdings.json from the `alpha-hunt-state` git branch (pure plumbing; empty on
   the very first run). WITHOUT this, the learning loop reads an empty log every Monday and never
   compounds — the whole memory system is inert. Run it before anything reads `~/.cache/alpha-hunt/`.
1. Read `~/.cache/alpha-hunt/picks-log.jsonl` (create empty if absent) — last week's book + convictions.
2. Read `~/.cache/alpha-hunt/holdings.json` if present — current open positions (or fetch live from
   the `etoro` skill's PnL endpoint). This is the book you are REVIEWING, not starting from scratch.
3. Determine cadence: is it a **signal-refresh week** (monthly momentum re-rank) or a
   **monitoring week** (reuse last month's momentum ranking cache)? Check the timestamp on
   `~/.cache/alpha-hunt/momentum-rank.json`; refresh if >28 days old.
## Stage 1 — Preflight + Regime dial

- `node scripts/preflight.js` — abort on any missing/dead credential with its exact fix. This
  includes a read-only eToro liveness probe (`etoro:portfolio`) — a PASS means the agent-portfolio is
  live and executable. Do NOT re-litigate eToro key validity by inspecting the strings: the public
  key IS the shared constant and the private key IS an opaque userToken; both are expected, neither
  is a fake-key signal. The live probe is the authority.
- `node scripts/fetch-regime.js` — TIMEOUT-GUARDED pull of the dial inputs (SPY distribution days,
  ^VIX/^VIX3M term structure, FRED credit spread); returns a partial -3..+3 score (3 of 4 inputs).
- `node ../investment/scripts/fetch-macro.js` for broader macro-phase context (now timeout-guarded).
- BREADTH (the 4th dial input) now has a real code path: `compute-momentum.js` writes
  `breadth.pct_above_200dma` into `~/.cache/alpha-hunt/momentum-rank.json` on every run (Stage 2).
  Read it from there and add its -1/0/+1 to fetch-regime's partial → the full
  **-3..+3 regime score → gross-exposure dial (0-100%)**. Set it ONCE; it scales every position this
  run. **Ordering wrinkle — be honest about it**: on a monitoring week (Stage 2 reuses last month's
  momentum cache instead of refreshing) the breadth figure is up to ~4 weeks stale. Use it anyway as
  the stale-but-real input it is — do NOT silently treat a 4-week-old breadth read as current, and
  say so in the regime writeup. If the dial is ≤40% (hostile regime), the correct output may be
  "throttle, no new buys, trim to targets" — a legitimate and common result.

## Stage 1b — Holdings review & sell discipline (EVERY week, before deploying new capital)

You are NOT starting from cash — the book already holds positions (preflight's `etoro:portfolio` read
showed them). Manage the existing book with the same discipline as new entries, and do it BEFORE
hunting new adds: selling frees cash to redeploy and clears dead positions. The user's mandate is
explicit — **sell whenever you judge it right.** The triggers below are the discipline that informs
that judgment, not a mechanical must-sell.

1. Pull current positions from the eToro PnL (`GET /trading/info/real/pnl` — already fetched in
   preflight): per position, the instrument, size, `positionID`, unrealized PnL, and entry.
2. Match each to its thesis in `~/.cache/alpha-hunt/picks-log.jsonl` (if alpha-hunt opened it) or mark
   it inherited / unknown-origin.
3. Decide **SELL (full) / TRIM (partial) / HOLD** per position using the exit doctrine
   (`references/risk-and-sizing.md` §6-8, §11). Sell or trim when ANY fires — otherwise HOLD:
   - **Thesis broken / invalidated** — the reason logged at entry no longer holds (guidance cut,
     ROIC<WACC for 2 quarters, the setup structurally changed). A fundamental trigger, not a price %.
   - **Catalyst passed** — the dated catalyst came and went; the reason to hold is gone (drift already
     captured, or the thesis was wrong). Exit and redeploy.
   - **Momentum break — RETAIN BAND, not a rank tripwire**: enter only top-decile composite; do NOT
     sell on rank slippage until the name falls below the **top 30-40%** of the ranked universe (the
     quantitative form of the two-clock rule). **Guard**: this is a valid exit signal only if
     `n_scored` (`compute-momentum.js` cache) is materially unchanged from the prior snapshot —
     otherwise the rank drop is a universe-composition artifact, not a momentum break.
   - **Time stop — sleeve-specific**, since the three families decay on different clocks:
     **momentum ~4-6 months**, **PEAD ~6-9 weeks**, **insider cluster ~6-12 months**. Stagnant past
     its sleeve's horizon with no thesis progress; free the capital and attention.
   - **Overvaluation extreme** — top few % of its own historical valuation → TRIM (≈top 5%) or full
     exit (≈top 0.5%).
   - **Drawdown soft-trigger** — vol-scaled, not a fixed number: **0.15-0.20x trailing 4-week book
     vol**, floored at 2%, capped at 6%. Hit that level, or the position's pre-registered Chandelier
     stop → reduce now, don't wait for the hard kill.
   - **Out-of-mandate** — not a US large/mid-cap long (crypto like SOL, a leveraged product, a short).
     alpha-hunt cannot run its discipline on these, so default to exiting them to redeploy into the
     book — unless there is a clear, dated near-term reason to hold, in which case TRIM and flag it.
   - **Concentration** — any single position > ~20-25% of equity → TRIM back toward target.
4. Execute via the `etoro` skill's close mechanics: look up `positionID` from PnL, then
   `POST /trading/execution/market-close-orders/positions/{positionId}` with `UnitsToDeduct: null`
   (full close) or a units number (partial — prefer partial for trims). Space orders ≥3s (20/min
   limit); after closing, **WAIT 60s before re-reading PnL** (60s cache) so the freed cash is visible
   before Stage 6 sizing deploys it.
5. Log every SELL/TRIM decision + its trigger to `picks-log.jsonl`, and HOLD decisions with their
   reason too — so next week's review has continuity. Genuine winners with an intact thesis AND live
   momentum are HELD and allowed to run.

## Stage 2 — Universe + Momentum (signal-refresh weeks only; else load cache)

- `node ../investment/scripts/fetch-universe.js` → ~1,509 S&P 1500 tickers.
- `node scripts/compute-momentum.js <all tickers in ONE invocation>` → residual momentum + 52wk-high
  proximity + frog-in-the-pan discreteness → the MOMENTUM SUB-SCORE ranking (value/quality is blended
  in at Stage 4, not here). The script writes `~/.cache/alpha-hunt/momentum-rank.json`; the orchestrator
  then archives a dated copy `momentum-rank-YYYYMM.json` and KEEPS >=2 monthly snapshots so the
  consistency filter can confirm >=2 consecutive top-quintile appearances. NEVER shell out per-ticker.

## Stage 3 — Catalyst intake (every week)

- `node scripts/fetch-catalysts.js` → Finnhub earnings calendar (next 2 weeks) + company news +
  estimate revisions (upgrades AND downgrades) + earnings-surprise records + the 13D activist feed,
  the SEC market-wide same-day Form-4 feed (fresh opportunistic clusters), and the SEC EDGAR
  full-text-search **8-K item-code triage** feed with cross-week **news-rehash detection**.
  **Do NOT expect a usable SUE — verified live against the real API.** Finnhub's free
  `/stock/earnings` returns only 4 quarters and the time-series ratio needs ≥5, so `sue_timeseries`
  comes back null on every name; the analyst-based form's dispersion denominator is paywalled
  (`sue_analyst: null`). The usable free field is the single-quarter `surprise_pct` — an unscaled
  direction+magnitude flag, NOT a standardized surprise. Both nulls carry notes; never substitute a
  number for them, and never size a PEAD position as if the surprise had been standardized.
- **8-K item-code triage — two hard rules.** Every 8-K record carries `items[]` and a
  `negative_signal` flag; material codes (2.02/1.01/4.02/2.06/3.01/5.02/2.04/1.02) tier A, noise
  codes (8.01/7.01/9.01-only) tier C. **(1) A 4.02 non-reliance (restatement) filing is
  `negative_signal:true` — it is a thesis-broken/AVOID flag, NEVER a buy catalyst**, even though it
  tiers A for salience alone. **(2) News items carry `is_rehash` + `staleness_days`** (cross-week
  near-duplicate detection against prior weeks' first-seen headlines) — **an `is_rehash:true` item
  is a FADE (Tetlock 2011: stale-information reactions reverse at a weekly horizon), forced to tier
  C, and must never satisfy the dated-catalyst gate**, regardless of how fresh the underlying event
  once was.
- For each name the Form-4 feed surfaces, run `node ../investment/scripts/fetch-insider.js TICKER`.
  It now emits TWO cluster tests — do not conflate them. **LEGACY/LOOSE**
  (`summary.cluster_buy_max_unique_in_90d` / `cluster_buy_signal`): 3+ distinct buyers in a flat
  **90-day** window, no transaction-code or 10b5-1 filtering — a LEAD, not a confirmed signal.
  **STRICT/OPPORTUNISTIC** (`summary.cluster_buy_opportunistic_7d` / `_14d`, `has_c_suite_buyer`,
  `opportunistic_cluster_signal`): transaction code `'P'` only, 10b5-1-scheduled trades excluded
  where detectable, in a rolling 7d or 14d window — a 7d cluster of 3+ stands alone, a 14d cluster
  needs a C-suite participant. `is_10b5_1: null` means UNDETERMINED, not excluded — it still counts
  as opportunistic (best-effort filter, not airtight). Score off the strict fields; the legacy field
  is context only, not the scoring input.
- Every catalyst record carries a **tier**: A = earnings-surprise / activist-13d / insider-form4 /
  material-8-K (§ above), B = estimate-revision (up), C = a bare scheduled-earnings calendar entry,
  a non-material 8-K, or a rehashed news item. Drop any candidate without a **dated, specific
  catalyst** — and a tier-C record does NOT by itself satisfy that gate; a bare earnings date is a
  DATE, not an edge. De-dup news by first-mention timestamp.
- **Tier A from the Form-4 feed is PROVISIONAL.** `fetch-catalysts.js` assigns it at DISCOVERY time,
  before any cluster test has run. If `fetch-insider.js` then fails to confirm a real cluster,
  DEMOTE that record — nothing in the pipeline revises the stored tier for you, so an unconfirmed
  discovery will otherwise keep scoring as top-tier evidence for the rest of the run.

## Stage 4 — Two-sleeve shortlist + veto gate

- Build ~15-25 names: **momentum sleeve** (top momentum-sub-score steady grinders) + **catalyst sleeve**
  (dated-catalyst movers). Keep the sleeves separate — different sizing rules downstream.
- `node ../investment/scripts/fetch-quote.js <shortlist>` for value/quality fundamentals (EBIT/EV, ROE,
  margins). Assemble the MASTER composite = momentum sub-score + value/quality tilt + catalyst flags.
- **Options-signal confirm/demerit — `node scripts/compute-options-signals.js <shortlist>`.** Per-name
  CBOE fetch — pass the SHORTLIST only, never the full universe. It emits `iv_skew`, `vol_spread`,
  `os_ratio` (per ticker, `error:null` on success). Use it to **CONFIRM or DEMERIT an existing
  catalyst-sleeve thesis — never as a standalone trigger**: elevated put `iv_skew` demerits a long,
  a flat/low skew or positive `vol_spread` confirms it. **Gate the IV-skew read on the TOP QUINTILE of
  `os_ratio` across the shortlist** (Pan & Poteshman: the skew signal is only informative where option
  activity is unusually high) — outside that quintile, treat `iv_skew` as uninformative, not absent.
  The CBOE chain is 15-minute delayed: directional color only, never an intraday-timing input.
- **Sentiment veto — `node scripts/fetch-sentiment.js <shortlist>`.** Also per-name, shortlist only.
  Emits `mention_z` (ApeWisdom 30-day mention z-score) which is `null` until ≥10 historical
  observations have accumulated — **a null is UNKNOWN, not a pass; do not treat it as clean.** A high
  `mention_z` may only **VETO or TRIM** an otherwise-good candidate (already-crowded, "buy the rumor,
  sell the news") — it must **NEVER initiate or upgrade** a candidate that wasn't otherwise going to
  make the book.
- **Other confirmers/vetoes** (references/signals.md "RESEARCH UPGRADES"): 13D activist + sharpened
  insider (Stage 3's strict cluster fields) + index-reconstitution as catalyst candidates.
- **Reflection injection** (learning-loop.md §2): before scoring, `tail`/`grep` `picks-log.jsonl` and
  inject same-ticker history + regime-filtered recent lessons. Every single-agent signal output must
  carry a `strongest_counterargument` field (llm-guardrails §10) BEFORE the adversary fleet runs.
- **LLM-bias mitigations — STRUCTURAL, not advisory (llm-guardrails.md §14).** These change the
  pipeline shape so the bias has nothing to grab onto; "be careful about bias" wording alone is
  measured as no better than nothing:
  - **(a) Randomize candidate order before ANY qualitative scoring pass, every run** — position/
    recency bias in a long ranked list is well documented and, before this, unmitigated anywhere in
    the pipeline ahead of the adversary fleet. Never hand the model the same watchlist order twice.
  - **(b) Score qualitatively BEFORE revealing the quant composite.** Produce the bull/bear read from
    raw fetched data FIRST; only then show the composite score. Seeing "this scored 0.87" before
    forming an independent read collapses judgment into rubber-stamping the number.
  - **(c) Standing permission: fewer than 5 names, or zero, on candidate-quality grounds ALONE is a
    legitimate, expected result — independent of the regime dial.** The regime axis already grants
    this (Stage 1); the quality axis does not get a pass just because the output format expects
    5-15 names. An agent that always fills the book because the template expects one is completing a
    template, not making a decision. A thin week should look thin.
- Apply the composite score with its **disqualifying veto gate** (`references/risk-and-sizing.md`).
- **13F clone cross-check (low-weight confirming factor):** read `data/clone-funds.json`; for shortlist
  names run `node ../investment/scripts/fetch-13f.js TICKER`. If a HIGH/MEDIUM-`cloneability` fund holds
  it as a NEW ≥7.5%-of-portfolio position, add a small conviction bump — never a primary trigger
  (45-day-stale signal; see references/signals.md 13F section).
- `node ../investment/scripts/compute-fraud-check.js TICKER` on each survivor. `overall_verdict`
  VETO (Beneish M > -1.78 OR Sloan accruals > 20% OR going-concern) → **dropped, no exceptions.**
  `overall_verdict` UNKNOWN means the veto could NOT compute (missing SEC facts) — treat as UN-VETTED,
  not cleared: drop it or route to manual review, never size it as if fraud-checked.

## Stage 5 — Adversary fleet (KILL the thesis)

The fleet is the SECOND adversarial layer: each surviving candidate must already carry its analyst
`strongest_counterargument` (Stage 4 / llm-guardrails §10) before it gets here. For each surviving
candidate, spawn Sonnet `adversary` agents (agentType: 'adversary', model pinned sonnet). Give each ONLY the candidate's data + the bull thesis-to-be-tested, and assign a DISTINCT
lens: `thesis-break` / `crowding-correlation` / `catalyst-reality` / `data-integrity`. Each must
self-commit to the bear case BEFORE reading the bull case and return a verdict
{BLOCK | FIX-THEN-MERGE | PASS} with receipts (what it checked). See `references/llm-guardrails.md`
for the exact protocol. **A candidate advances only if it survives its adversaries.** Triage: only
Fatal/Significant findings block; cosmetic ones are logged.

Run this as a Workflow pipeline (candidates → adversary lenses in parallel) when >4 candidates
survive Stage 4 — it parallelizes cleanly and each candidate OWNS its own analysis (no shared state).

**Log every BLOCK verdict — nothing else records it, and it is the most expensive component in the
pipeline.** For every candidate any lens BLOCKs (whether or not it ever becomes a position), append
a picks-log line with the ticker, date, lens, and its one-line `reason` (the `adversary_verdicts`
field, learning-loop.md §1/§8). At a 4-8 week horizon this is graded against SPY (learning-loop.md
§8, Stage 8) to measure whether the fleet is actually earning its cost per lens, not just fleet-wide.

## Stage 6 — Sizing

**MANDATORY: `node scripts/compute-sizing.js <input.json>` computes every weight — never freehand
this arithmetic in prose.** This closes the gap between `references/llm-guardrails.md` §13 ("the LLM
never does arithmetic") and what this stage used to ask for. The LLM's job here is candidate
selection and judgment inputs only: group survivors into correlation clusters (factor exposure, not
calm-period pairwise corr) and, per candidate, supply a calibrated `confidence` (win probability) plus
`upside_pct`/`downside_pct` from the thesis. Everything downstream of those inputs is the script's job.

Build `input.json` with: `equity_usd`, `regime_dial` (Stage 1 output, 0-1), `book_vol_target` (0.18-
0.25), `book_realized_vol`, `kelly_fraction` (≤0.25), and `candidates[]` — each with `ticker`,
`sleeve` (`momentum`/`catalyst`), `cluster`,
`confidence`, `upside_pct`, `downside_pct`, `realized_vol_annual`, and optionally
`adv_usd`/`is_binary`. Run it; the output's `positions[]` (`weight_pct`, `weight_usd`,
`binding_constraint`) is **authoritative** — the script has already applied cluster budgeting,
inverse-vol split, the vol-target scalar, the regime dial, and every hard cap (binary 2-5%,
single-name 25%, top-5 60%, ADV capacity) in the locked
order. Report the `binding_constraint` the script names for each position; do not re-derive or
override its numbers.

## Stage 7 — Book + memos

Ranked book with target weights (% of equity). One memo per name:
thesis (1 sentence) / dated catalyst / **entry trigger** / **invalidation** / position size + Kelly
rationale / top 2-3 ways it's wrong + planned response. Pre-register all exits AT ENTRY, and the two
sleeves pre-register differently:
- **Momentum sleeve — a REAL pre-registered stop, not prose.** Run
  `node scripts/compute-atr.js <shortlist> [--entry TICKER=YYYY-MM-DD]` and use its
  `chandelier_stop` (highest close since entry − 3×ATR22) as the invalidation level. Check
  `entry_anchored`: `true` means the stop is anchored to the real entry date; `false` means no
  `--entry` was supplied yet and the script fell back to the trailing-60-day highest close — an
  APPROXIMATION, wider or narrower than the true Chandelier depending on where that 60-day high fell
  relative to the eventual entry. Carry `entry_anchored` in the memo; don't let it read as a firm
  number until it is one.
- **Catalyst sleeve — invalidation stays reason-based, not a price.** The exit is the thesis
  resolving or breaking (the dated catalyst passing, guidance cut, etc.), per `risk-and-sizing.md`
  §6 — a tight price stop here exits on noise, not on the thesis being wrong.

**Entry trigger must be an executable condition, not a restated screen.** "It scored top-decile
composite" is NOT an entry trigger — that's why it screened, not when to hit the buy button. Name a
concrete execution-level condition instead: a limit price (e.g. "limit ≤ $X, within 2% of last") or a
confirmation event (e.g. "on close above the breakout level" / "day 2-3 after a clean beat"). Default
to a **marketable limit order**, not a bare market order — a name that gapped past the trigger is a
reason to re-check the thesis, not to chase at any price.

Stagger entries into tranches — **prefer 5** (3 is the floor, not the target); ≤2-3 new positions/week;
keep dry powder. Tranching only **partially** mitigates rebalance-timing luck: it cuts the variance
roughly ~1/N, it does NOT eliminate it — Hoffstein, Faber & Braun (2020) document >100bp/yr dispersion
from reconstitution-timing alone. Say this plainly rather than treating tranching as a solved problem.

## Stage 8 — Output + calibration

- **Grade last week first** (before proposing changes) — run the LEARNING LOOP (learning-loop.md,
  load it): resolve each closed position into the rich picks-log schema (r_multiple, spy_alpha_pct,
  brier_component, thesis_correct_for_stated_reason, 2-4-sentence reflection). Grade PROCESS (entry-time
  info only) vs OUTCOME separately; grade against alpha-vs-SPY, not raw return. On monthly-refresh weeks,
  recompute the signal_family×regime performance table → it modulates next month's Kelly multipliers
  (±30% cap). Recalibrate stated_confidence via the trailing reliability diagram before it feeds Kelly.
  Down-weight any signal family whose rolling 6-13-week hit-rate decayed (decay clock). Once ≥30
  resolved trades exist for a signal family, compute a Deflated Sharpe before trusting a tuned
  threshold for it (learning-loop.md §7) — before that, treat the threshold as an unvalidated prior,
  not a finding. NEVER let the loop touch risk/personality params
  (Kelly ceiling, position caps, veto) — tactical params only.
- **Grade the adversary fleet** (learning-loop.md §8): for BLOCK verdicts logged at Stage 5, look up
  the blocked name's actual return vs SPY at its 4-8 week horizon, regardless of whether it ever
  became a position. Compute a hit-rate per lens (`thesis-break` / `crowding-correlation` /
  `catalyst-reality` / `data-integrity`) — a lens that blocks eventual winners is a false-positive
  tax on the book; one that blocks eventual losers is earning its keep. This calibration stream
  matures faster than trade-resolution grading since a blocked name only needs its price checked.
- Present the book, then hand target weights to the `etoro` skill for execution (% of equity → it
  opens by amount at Leverage 1, respects 20/min + 60s PnL cache).
- Append every pick + conviction + dated catalyst + pre-registered exits to
  `~/.cache/alpha-hunt/picks-log.jsonl`, using the rich schema (learning-loop.md §1): `trade_id`,
  `binding_constraint`, `composite_score_components`, `adversary_verdicts`, `overridden_flag`,
  alongside the existing fields. **APPEND-ONLY — MANDATORY**:
  resolving a position is a NEW JSONL line referencing the original entry's `trade_id`, NEVER an
  in-place edit of it — an editable entry lets a losing thesis be retroactively reworded once the
  outcome is known. Update `holdings.json`.
- **`bash scripts/state.sh save`** — persist picks-log.jsonl + signal-perf.json + holdings.json to the
  `alpha-hunt-state` branch so next week's run inherits them. This is what makes the learning loop
  actually COMPOUND rather than reset. Do this AFTER all logging is written. If the push fails (no
  creds), it warns loudly — surface that, because silent non-persistence = permanent amnesia.
- Footer: "not financial advice / risk pre-accepted." Schedule next weekly run.

## Error recovery

| Failure | Symptom | Recovery |
|---|---|---|
| Dead credential | preflight ping fails | Abort, print exact fix. Never run half-blind. |
| Yahoo crumb 401 | quoteSummary fails | Use `../investment/scripts/fetch-quote.js` (does crumb dance); or v8 chart for price. |
| SEC 403 | "Undeclared Automated Tool" | UA must be `AppName email`. Reuse investment scripts' UA. |
| Finnhub 429 | rate limited (60/min) | Space calls; the calendar+news for a 20-name shortlist fits easily. |
| Empty catalyst set | no dated catalysts this week | Momentum sleeve can still produce a book; note thin catalyst week. |
| Regime dial ≤40% | hostile regime | Legit "throttle/trim, no new buys" output — do not force picks. |
| Adversary connection drop | agent dies mid-run | Re-run that one candidate's adversary; others' verdicts are already on disk. |
| yfinance shift-bug | financials off by a year | fetch-financials.js already SEC-cross-checks; prefer SEC on divergence. |
| Dead/thin CBOE chain | `compute-options-signals.js` record has `error` set, no `iv_skew`/`vol_spread`/`os_ratio` | EXPECTED, especially for small-caps — the script already emits the record with `error` rather than dropping the name; degrade to no-options-read (skip the confirm/demerit) for that name, do not drop it from the shortlist over this alone. |
| ApeWisdom unavailable / `mention_z` still null | `fetch-sentiment.js` fails, or `mention_z:null` (<10 observations accumulated) | Treat as UNKNOWN, never as a pass — a null sentiment veto is not clearance to size the name at full conviction, it just means this run has no sentiment read on it. |
| EDGAR full-text search down | `efts.sec.gov` 8-K feed fetch fails | `fetch-catalysts.js` already warns and continues (other catalyst sources still populate). As a manual stopgap, the `getcurrent` atom feed (`type=8-K`, same pattern as Form-4/13D discovery) can surface bare 8-K filing dates — but it carries no item codes, so anything sourced that way is tier C (a date) only, never treat it as a material-item (tier-A) triage result. |
