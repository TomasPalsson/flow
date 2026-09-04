---
name: alpha-hunt-signals
description: Full signal library for alpha-hunt — momentum variants, catalyst/event strategies, exact thresholds, and the composite scoring formula. Load at screening/scoring stages.
---

# Signal Library — Specs & Thresholds

Two sleeves, kept separate because they select different populations and size differently.

---

## MOMENTUM SLEEVE (steady quality grinders)

### Residual / idiosyncratic momentum — PREFER over raw 12-1
Textbook Blitz-Huij-Martens (2011) regresses monthly returns on a 3-factor model (market/size/value)
over a trailing 36-month window and cumulates the residuals. **That is NOT what runs.**
`compute-momentum.js` is an intentional simplification: it regresses WEEKLY returns on **SPY only**
(single-factor/CAPM) over a ~2-year window, then sums the residuals over the 12-1 window. What is lost
vs the textbook version: no size/value residualization, so the "residual" here is only market-neutral,
not size/value-neutral — some size and value tilt leaks back into the signal. Reported (NOT
independently verified) gross monthly Sharpe is roughly ~0.48 vs ~0.25 for raw 12-1, at ~half the vol.
Take that pair as a directional prior, not a fact.

**MANDATORY fix that just landed: the signal is standardized by the residual standard deviation**
(sum(residuals) / std(residuals) — an information-ratio form, Σε/σ_ε), not a raw sum. The
un-standardized raw-sum version tilts the ranking toward high-idiosyncratic-vol names — which carry
documented POOR forward returns (Ang, Hodrick, Xing & Zhang) — meaning it inverts the signal's intent
(rewards exactly the noisy names the residual construction was supposed to filter out). If you can
carry only one momentum signal, this is it. Residual-momentum holdings can be held more patiently than
raw-momentum (their reversal clock starts later).

### Frog-in-the-pan (information discreteness) — the path filter
Two stocks with IDENTICAL 12-month return can have opposite forward returns (+5.94% vs -2.07%)
depending on HOW the return arrived. Steady grinders >> gap-and-flat. The real Da, Gurun & Warachka
(2014) measure is a SIGN-COUNT statistic, NOT a magnitude ratio: `ID = sign(PRET) × (%neg − %pos)`
over the formation window — LOWER is better (more continuous, "frog-in-the-pan" information).
`compute-momentum.js` now computes the faithful form on weekly bars:
`info_discreteness = sign(mom_12_1) × (1 − 2 × up_ratio)`, since `%neg − %pos = (1 − up_ratio) −
up_ratio`. Weekly bars are coarser than the paper's daily bars — faithful-in-form, coarser-in-resolution.
The old magnitude-ratio field (`discreteness = |return from single largest up-day| / |total trailing
return|`) is retained but ONLY as a reported diagnostic — it is not the weighted signal and is not the
Da-Gurun-Warachka measure. Penalize high-`info_discreteness` names in the momentum sleeve. (Note:
explosive one-jump names belong in the CATALYST sleeve, sized small — not the momentum sleeve.)

### 52-week-high proximity — behavioral, decays slowly
`proximity = current_price / 52wk_high`. Names within ~5-10% of their 52wk high, driven by anchoring
underreaction. Distinct from return momentum; robust because behavioral not mechanical.

### Consistency filter
Require top-quintile trailing return for **≥2 consecutive monthly snapshots**, not a single recent
spike. Cheap, discriminates against one-pop names.

### Skip-month is CONDITIONAL
For liquid, high-turnover names, 12-0 (no skip) can beat 12-1 — the reversal the skip avoids is
concentrated in illiquid names. `compute-momentum.js` uses a uniform ~4-week skip as the safe default;
treating skip-0 for the most liquid mega-caps is an optional refinement the orchestrator can overlay.

### Composite: how the master score is assembled
`compute-momentum.js` emits ONLY the **momentum sub-score** (z-composite of the momentum-family
fields). The orchestrator forms the **master composite** by blending in the **value/quality tilt**
from `fetch-quote.js` fundamentals (EBIT/EV sector-neutral percentile, ROE, margins) and the
**catalyst flags** from `fetch-catalysts.js`. No single script emits the full composite — that
assembly happens in the pipeline (execution-prompt Stage 4). Combine the sub-scores as a
**weighted z-score (rank-and-sum)**, NEVER an AND-intersection. Value and momentum are
negatively correlated BY DESIGN — that offset is the diversification benefit. An intersection filter
discards it and selects a narrow weird population. Add a light value tilt (EBIT/EV sector-neutral
percentile) to the momentum z-score; do not require both to agree.

---

## CATALYST SLEEVE (explosive dated-catalyst names, sized SMALL)

Every candidate here needs a **dated, specific catalyst** and min **3:1 upside/downside**, or it is
disqualified. "A thesis without a catalyst is hope, not a trade."

### Catalyst tiering — a date is not an edge
Catalyst records now carry a tier: **A** = earnings-surprise / activist-13d / insider-form4. **B** =
estimate-revision. **C** = a bare scheduled-earnings calendar entry or a news item. A tier-C entry is a
DATE, not an edge, and MUST NEVER on its own satisfy the "every pick needs a dated catalyst" gate —
otherwise the gate is trivially passed by any company reporting within two weeks, which is what was
happening before tiering existed.

### Earnings-announcement premium (PRE-print) — the counterintuitive one
**72% of the total earnings premium is realized BEFORE the print** via uncertainty resolution — a
distinct mechanism from PEAD. Higher pre-event uncertainty → higher pre-announcement return. Entering
pre-print captures this but takes full binary miss/beat risk → cap at binary size (2-5%).

### PEAD (post-print drift)
- SUE two ways: **time-series** `(EPS_q − EPS_q-4)/σ` and **analyst-based** `(actual − consensus)/
  dispersion`. **NEITHER is computable on the free data tier — verified live, not assumed.**
  `fetch-catalysts.js` implements the time-series form against Finnhub `/stock/earnings`, but that
  endpoint returns only **4 quarters** on the free tier and the ratio needs ≥5, so it emits
  `sue_timeseries: null` with a `sue_note` on every name. The analyst-based denominator (estimate
  DISPERSION across analysts) is outright paywalled → `sue_analyst: null`. **What you actually get is
  the single-quarter `surprise_pct`** (actual vs consensus, both free) — a real but weaker PEAD input:
  it is one unscaled observation, so it cannot separate a big surprise on a noisy earnings history
  from a small one on a smooth history, which is the whole point of standardizing. Use it as a
  direction+magnitude flag, never as if it were SUE. Both nulls carry explicit notes rather than a
  substituted number — treat SUE as specified-but-unavailable, not silently missing.
- Mostly dead for large-caps on naive last-quarter SUE; survives in **small/mid-caps** and (2025 ML
  work) large-caps conditioned on FULL surprise history. ~25-30% of drift concentrates around the
  NEXT print (hold through it). Beats extend more than misses revert (asymmetric).
- Post-print entry (day 2-3 after a clean beat) captures drift with a CONFIRMED direction, no binary.

### Insider opportunistic cluster buying — the 82bp/mo signal
- **Opportunistic** (breaks the insider's own historical pattern) = ~82bp/mo abnormal return.
  **Routine** = zero. Filtering only on "insider bought" is near-noise.
- Cluster definition (the IDEAL): **3+ distinct insiders, open-market cash buys, within a 7-14 day
  window** (60-day backdrop for slower clusters), EXCLUDING 10b5-1 scheduled trades, option exercises
  and RSU vesting.
- **WHAT THE CODE NOW DOES — the strict test exists alongside the legacy loose one.**
  `../investment/scripts/fetch-insider.js` emits BOTH. The **legacy/loose** field
  (`cluster_buy_max_unique_in_90d` / `cluster_buy_signal`) is unchanged: 3+ distinct buyers in a flat
  90-day window, no transaction-code filter beyond direction, no 10b5-1 exclusion — keep treating it as
  a WEAK lead only. The **strict/opportunistic** fields
  (`cluster_buy_opportunistic_7d` / `_14d`, `has_c_suite_buyer`, `opportunistic_cluster_signal`) are
  new and finally resemble the construction the ~82bp/mo figure came from: transaction-code **'P'**
  (open-market buy) only, a rolling **7-day or 14-day** window, and **10b5-1 scheduled trades excluded**
  — a 7d cluster of 3+ opportunistic buyers stands alone; a 14d cluster only counts if a C-suite buyer
  participated. **Caveat — read this before trusting the exclusion:** per-transaction `is_10b5_1` is
  `true | false | null`, and `null` means **UNDETERMINED** (the filing carried no structured
  per-transaction plan tag and no document-level checkbox ruled it out) — those transactions are kept
  in the opportunistic pool (`is_10b5_1 !== true`), not dropped. So the 10b5-1 filter is
  **best-effort, not airtight**: some scheduled trades that never got a clean structured marker will
  still pass through and dilute the signal. Treat `opportunistic_cluster_signal` as materially stronger
  evidence than the legacy `cluster_buy_signal`, but not as a guaranteed-clean opportunistic cluster.
  Weight C-suite (CEO/CFO/COO) above directors. Small-cap officer clusters ~7.4%/12mo.
- Discover market-wide via the SEC `getcurrent` Form-4 feed (see data-runbook), not just per-ticker.
- Form-4s are ≤2 business days late — the edge is the multi-week hold, NOT the filing-day pop.

### Estimate-revision momentum — this is analyst COUNT breadth, not EPS revisions
Unambiguous statement: the runtime signal is **analyst buy/strongBuy COUNT breadth**, NOT EPS estimate
revisions. `fetch-catalysts.js` computes `net_upgrade_delta` — the net shift in analyst buy/strong-buy
counts vs the prior period via Finnhub recommendation trends — and that count-breadth shift, not any
EPS number, is what feeds the composite. **Downgrades are now captured too**: the code previously
returned a signal only when counts ROSE, so deterioration could never demerit a name; it now emits a
`direction: 'down'` record with a negative `net_upgrade_delta` as an explicit demerit, not silently
dropped. Ideal refinement (premium data, not implemented): price-target **magnitude** ($100→$160 >>
$100→$105) and **clustered multi-firm** hikes >> single analyst. "Beat and raise" is a distinct,
stronger category than beat or raise alone. Valuation-only downgrades (no fundamental deterioration)
often mark short-term bottoms.

### 13F cloning — clone the BORING funds
- 45-day filing lag → clone LOW-turnover concentrated long-horizon funds; a 45-day-old snapshot of a
  3-year holding is barely stale. Tiger Cubs (fast turnover) are the WORST to clone despite the fame.
- Keep only positions ≥7.5% of the fund's disclosed 13F portfolio (career-risk bets). Slow/confirming
  signal, low weight. 13Fs hide shorts/options/hedges — a "conviction" long may be delta-hedged.

### Other events — low-weight confirming color, none implemented in code
- **Spinoffs**: wait out the forced-selling air-pocket, don't buy day 1.
- **Index recon**: add>delete but arbitraged away — low weight.
- **Buybacks**: prefer disclosed actual repurchase over headline authorization.
- **Lockup expiry**: only fires if the stock is above IPO cost basis.

### News triage
- Residual "pure news" (strip what's predictable from price/fundamentals) predicts 18+ months.
- Markets UNDERreact to numeric negative disclosure, OVERREACT to splashy ambiguous stories.
- Article volume ≠ information (republication). De-dup by first-mention; require a new quantifiable claim.
- **8-K Item-code triage — IMPLEMENTED** (`fetch-catalysts.js`, market-wide SEC EDGAR full-text-search
  8-K feed). **Material** (tier A — real, dated, price-moving): **2.02** earnings, **1.01** M&A/
  financing, **4.02** non-reliance/restatement, **2.06** material impairment, **3.01** delisting/
  transfer-agreement non-compliance, **5.02** exec departures/appointments, **2.04** credit-agreement
  acceleration, **1.02** termination of a material agreement. **Noise** (tier C — down-weighted,
  a date not an edge): **8.01** catch-all, **7.01** Reg FD, **9.01** exhibits-only. **4.02 is a
  restatement RED FLAG — always a negative/avoid flag, NEVER a buy**, even when it lands alongside
  otherwise-bullish items; management or the auditor disowning prior financials is a reason to leave,
  not enter.
- **Rehash detection — IMPLEMENTED** (`fetch-catalysts.js`): cross-week Jaccard similarity over
  headline token sets flags a story as a near-duplicate of one already scored in a prior week. A
  detected rehash is forced to tier C and treated as a **FADE, never a catalyst.** Evidence: Tetlock
  (2011), "All the News That's Fit to Reprint: Testing Media Bias," finds investors OVERREACT to STALE
  (already-known) information and that those moves systematically REVERSE at roughly a **weekly**
  horizon — matching this skill's cadence. A republished story is stale by construction; score it as a
  reversal candidate, not fresh signal.
- Source-credibility first (filing > wire > outlet > social).

### Generic news SENTIMENT scoring — REJECTED
Blunt: do not bolt a generic positive/negative sentiment score onto news text. Tetlock (2007) measures a
**next-day** effect that reverts within days — shorter than this skill's weekly cadence, so by the time
this skill would act on it the effect is already gone. Garcia (2013) finds the effect concentrated in
**recessions** and weak-to-absent otherwise — regime-dependent, not a standing edge. Loughran & McDonald
(2011) show generic (non-financial) sentiment dictionaries systematically **misclassify** financial text
(words like "liability," "tax," "cost" score negative in general dictionaries but are neutral accounting
terms in a filing). For a weekly, long-only book, hard event classification (8-K item-code triage above)
and staleness detection (rehash, above) dominate generic sentiment on every axis that matters here —
don't build it.

---

## HARD AVOIDS
- **Pure FDA/PDUFA binaries** (40-200% single-day). If engaging: trade the pre-date run-up and exit,
  or enter only AFTER a clean AdCom vote (unanimous → ~99% approval; close 5-4 → only 60-70%). Never
  hold a blind binary as a normal position.
- **Short interest as a bullish squeeze setup** — it's BEARISH on average (short sellers are usually
  right). Use elevated short interest to AVOID longs. A squeeze sleeve, if any, is a tiny labeled bet.
- **Leveraged/3x ETFs for multi-day holds** — daily-reset decay loses even on a flat round-trip.

---

## RESEARCH UPGRADES (2026 swarm — evidence-backed, free-data, mandate-fitting)

### Options-implied informed-trading — IMPLEMENTED (`compute-options-signals.js`)
Five independent peer-reviewed confirmations that informed traders leave footprints in options BEFORE
the stock moves. `compute-options-signals.js` computes all three from `cdn.cboe.com/.../options/{T}.json`
(already in data-runbook), against the delayed free chain for a ~15-25 name shortlist:
- **IV skew** = 25-delta put IV − ATM IV. Elevated put skew = informed downside pricing → demerit /
  avoid a long. Flattening/low skew on a momentum name = clean.
- **Volatility spread** = ATM call IV − ATM put IV. Positive (calls bid over puts) leans bullish.
- **O/S ratio** = option volume / stock volume. Gate the put/call OI skew signal to the TOP QUINTILE
  of O/S (Pan-Poteshman) — the skew signal is only informative where options activity is unusually high.
The CBOE chain is **15-minute delayed** — directional-only, never an intraday-timing input. Use as a
**conviction confirmer/demerit on the catalyst sleeve**, never a standalone trigger. (HIGH.)

### Activist 13D tracking — IMPLEMENTED (`fetch-catalysts.js`)
`fetch-catalysts.js` now pulls the market-wide `type=SC 13D` / `SC 13D/A` EDGAR getcurrent feed
alongside Form-4. Still prose-only: scoring the **amendment (13D/A) with escalation language** (proxy
fight, board demand, "explore strategic alternatives") HIGHER than the initial 13D (already priced) —
the feed only does name-discovery, not escalation-language scoring. A fresh activist stake + catalyst
is a real, dated event. (HIGH.)

### Sharpened insider cluster — PARTIALLY IMPLEMENTED (refine the existing signal)
- Filter on the Form-4 **10b5-1 checkbox/plan tag** directly (exclude scheduled plans — the
  routine/opportunistic split, mechanized) — **IMPLEMENTED**, see "Insider opportunistic cluster
  buying" above: `../investment/scripts/fetch-insider.js` now emits `is_10b5_1` per transaction and a
  strict 7d/14d opportunistic cluster test built on it. Best-effort, not airtight — `null` (undetermined)
  still counts as opportunistic; see the caveat above.
- Weight by **buy_value / trailing-12mo insider comp** (from DEF 14A XBRL), so a proportionally-LARGE
  director buy isn't drowned out by a proportionally-trivial CEO buy — **NOT IMPLEMENTED.**
- **Double-signal upweight**: an insider cluster AND a buyback signal (esp. a tagged ASR — accelerated
  share repurchase, a distinct 8-K sub-category) landing in the same window = confirmed conviction —
  **NOT IMPLEMENTED.** (HIGH.)

### Index reconstitution — NOT IMPLEMENTED (new catalyst category — long-only compatible)
Forced index-fund flow. Long-only so trade the **deletions** (post-drop technical air-pocket), not
additions (can't short). Run a **Russell 1000/2000 cutoff-proximity screen each April-May** off
market-cap ranks to flag likely June reconstitution moves ahead of the rank date. Prose-only — no
script fetches Russell membership/rank data. (MED-HIGH.)

### Social sentiment — IMPLEMENTED (`fetch-sentiment.js`, a de-risking VETO, never a buy trigger)
`fetch-sentiment.js` pulls ApeWisdom mention counts, free. ApeWisdom is a **point-in-time snapshot API**
with no history endpoint, so the script builds its own series — every run appends to a rolling local
history — and computes the 30-day mention z-score **only once ≥10 historical observations have
accumulated**; below that it emits `mention_z: null` rather than fabricate a z-score from too few
points. A name already spiking in retail attention is LATE — use a high z-score to **veto or trim an
otherwise-good long** (operationalizes "buy the rumor, sell the news"); the code **never** turns a high
z-score into an initiation signal. The Google-Trends/pytrends half of this item is DELETED: pytrends is
an unofficial Python scraper of an undocumented endpoint with no stable keyless Node-callable
equivalent, so it cannot be implemented under this skill's Node-stdlib-only constraint. (MED-HIGH as a
veto.)

### The "stay small" edge, honestly scoped
Prior text claimed the edge is up-weighting names "below the ADV threshold where 13F-reporting
institutions structurally cannot build positions" and called that the skill's only durable advantage.
**That edge cannot exist inside this skill's universe.** `fetch-universe.js` screens the S&P 1500 —
every constituent is, by construction, an index name held at scale by 13F filers. Claiming a
sub-institutional-threshold edge while screening the S&P 1500 is self-deception; a genuine micro-cap
edge would require a different universe source (below S&P 600 floor), which this skill does not fetch.
The achievable version, inside the actual universe: tilt selection toward the **SMALLER end of the
S&P 600 small-cap leg**, where analyst coverage is thinner and institutional position-building is
harder than at S&P 500 scale — real, but much weaker, than "below the institutional threshold." The
capacity-discipline point still stands and is sound: never let account growth drift the book into
mega-caps, where retail has zero edge even under the honest framing. (MED — a real but modest tilt,
not a structural moat.)

### Hype graveyard — do NOT chase these (the swarm's rejects)
- **Named-investor persona prompting** (Buffett/Burry "voice") — cosmetic, no proven alpha over a neutral analyst.
- **Time-series foundation models** (Chronos/TimesFM) on stocks — zero published financial validation.
- **Congressional-trading copy** (Pelosi/QuiverQuant) — decayed 42.5%→32.2%, 45-90-day disclosure lag. Skip.
- **Any self-reported "my bot returned X%" / retail AI-trading product** — survivorship bias, no live audit.
- **0DTE / options-trading strategies** — out of mandate and grift-saturated.
