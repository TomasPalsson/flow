---
name: alpha-hunt
description: "Aggressive weekly stock-hunting engine: a concentrated 5-15 name conviction book from momentum, catalyst and event-driven signals for a long-only eToro agent-portfolio, every thesis attacked by an adversary fleet before sizing. Triggers: /alpha-hunt, what should I buy this week, aggressive or high-conviction ideas, catalyst trade, momentum book, weekly stock review, find me alpha. Not for patient single picks (/investment), eToro balances (/etoro), screener code, or market commentary."
user-invocable: true
argument-hint: "[optional: focus, e.g. 'earnings movers' or a ticker to pressure-test — omit for full weekly hunt]"
---

# Alpha-Hunt — Aggressive Weekly Conviction Hunter

You are running an aggressive, concentrated, weekly-cadence hunt for the best risk-adjusted BUY
candidates, producing a ranked book (5-15 names + target weights + dated catalysts + exit rules)
that the `etoro` agent-portfolio skill executes. This skill is the offensive counterpart to
`/investment`. It is built on the same house infrastructure (the 8 `investment` data scripts) and
borrows the `ultracode` spine: fan out Sonnet agents, and make an **adversary fleet try to kill
every thesis before capital touches it.**

**This is not financial advice. The user pre-accepted the risk. Aggression here means concentration
+ conviction sizing + catalyst selection — NOT leverage.** The book is long-only and unleveraged
(eToro forbids CFD algo-trading via API; positions open at `Leverage: 1`). The edge and the danger
both live in *what you concentrate into*, not in borrowed money.

---

## The Prime Directive: two clocks, never one

**The single most important rule in this skill.** The academic momentum/quality/catalyst edge is
built on monthly-or-slower holding periods. Re-picking the whole book every week pays 3-5x turnover
to re-rank noise and bleeds the entire edge to cost. So run **two separate clocks**:

| Clock | Cadence | What it does |
|---|---|---|
| **Signal-refresh** | Monthly | Re-rank momentum, recompute composite scores, rebuild the shortlist |
| **Weekly loop** | Every run | Monitor holds, check exits, intake FRESH dated catalysts, deploy dry powder |

A held winner is **NOT sold because it slipped a rank this week.** Screening cadence (weekly) and
holding cadence (the anomaly's natural 4+ week horizon) are different variables. Collapsing them
into one weekly reconstitution is the fastest way an on-paper-good screen dies in live trading.

## Mindset before you fetch a single number

1. **The market is mostly right.** If a name screens cheap-and-moving, ask *what does consensus
   know that I don't?* The variant perception is the alpha; the scores test whether it survives.
2. **LLMs get regime backwards** — timid in bull markets, reckless in bear. You must EXPLICITLY
   invert this: lean into breadth-confirmed uptrends, throttle HARD when breadth deteriorates.
   Left uncorrected, "aggressive" amplifies the exact wrong behavior (research-documented).
3. **No number enters analysis without a fetched source.** You have absorbed post-hoc narratives
   about specific stocks; a remembered price or "I recall they beat" is look-ahead contamination.
   Every trade-sizing number is a tool-call result, never a memory. (See llm-guardrails.)
4. **Position size matters more than ticker choice.** "10 different picks" from one screen is
   really 3-6 correlated bets. Half the job is sizing at the cluster level, not the ticker level.

## Preflight — do this first, every run

Run `node scripts/preflight.js`. It verifies `FRED_API_KEY`, `FINNHUB_API_KEY`, and the eToro
`AGENT_PRIVATE_KEY`/`AGENT_PUBLIC_KEY` resolve, pings each data source live, AND makes one read-only
eToro call to confirm the agent-portfolio is live. **Missing or dead key → abort with the exact fix.
Never run a half-blind hunt** — a silent-degraded data layer produces confident garbage.

**eToro keys — do NOT judge them by appearance.** `AGENT_PUBLIC_KEY` is eToro's SHARED `x-api-key`
constant (identical for every user) and `AGENT_PRIVATE_KEY` is the `x-user-key` userToken, which
decodes to an opaque blob tagged `"UnregisteredApplication"` — BOTH are normal and are NOT evidence
the keys are fake. Preflight's `etoro:portfolio` check (`GET /trading/info/real/pnl`, read-only) is
the ONLY authority on validity: a PASS means the portfolio is live and executable. Never conclude the
keys are fake from how the strings look, and never burn turns arguing it — if preflight says eToro
PASS, the handoff to the `etoro` skill is real.

## Execution Pipeline

The full state machine lives in [`execution-prompt.md`](execution-prompt.md). **MANDATORY — READ
ENTIRE FILE** before running the pipeline. **Do NOT load** for conceptual questions ("what's
frog-in-the-pan?", "explain the regime throttle") — those don't run the pipeline. The
stages (1b manages the existing book before new adds):

1. **Preflight + Regime read** — `scripts/preflight.js`, then `scripts/fetch-regime.js` (timeout-
   guarded dial inputs) + `fetch-macro.js` for macro context. Compute the **gross-exposure dial**
   (0-100%) from the -3..+3 regime score BEFORE picking anything. In a deteriorating regime the
   answer may be "throttle to 40%, no new buys."
1b. **Holdings review & sell discipline** — the book is NOT starting from cash. BEFORE hunting new
   adds, review every existing position (from the preflight eToro read) and decide **SELL / TRIM /
   HOLD** with the exit doctrine: thesis broken, catalyst passed, momentum break, time stop,
   overvaluation, drawdown soft-trigger, out-of-mandate (crypto/leverage/short), concentration.
   Execute closes via the `etoro` skill; freed cash flows into Stage 6. The user's mandate: **sell
   whenever you judge it right** — but a winner with an intact thesis and live momentum is held.
2. **Universe + Momentum refresh** (monthly; cached weekly) — `fetch-universe.js`, then
   `scripts/compute-momentum.js` on the whole universe in ONE batched invocation. Produces the
   residual-momentum / frog-in-the-pan / 52wk-high composite ranking.
3. **Catalyst intake** (weekly) — `scripts/fetch-catalysts.js`: Finnhub earnings calendar + news +
   estimate revisions, and the SEC market-wide same-day Form-4 feed for fresh opportunistic
   insider clusters. Every candidate must carry a **dated, specific catalyst** or it is dropped.
4. **Two-sleeve shortlist** — build ~15-25 names split into a **momentum sleeve** (steady quality
   grinders) and a **catalyst sleeve** (explosive dated-catalyst names). Apply the composite score
   with its **disqualifying veto gate** (a fatal single-factor flag caps the score — not a soft
   average). Run the **Beneish/Sloan fraud veto** (`compute-fraud-check.js`) — fraud is dropped.
5. **Adversary fleet (the ultracode spine)** — for each surviving candidate, spawn Sonnet
   `adversary` agents whose mandate is to **KILL the thesis**: each self-commits to the bear case
   BEFORE seeing the bull case, with distinct lenses (thesis-break / crowding / catalyst-reality /
   data-integrity). A hard devil's-advocate role produces real dissent; a soft "consider the other
   side" produces none. Only theses that survive get sized.
6. **Sizing** — `node scripts/compute-sizing.js` computes every weight deterministically: cluster-Kelly
   at **10-25% of full**, vol-targeted, with the **momentum-crash throttle**, **binary-catalyst
   2-5% caps**, and the hard caps LAST. Real stop
   widths come from `node scripts/compute-atr.js <shortlist>` — Wilder ATR(22) on daily bars, the
   Chandelier stop. The LLM supplies candidates + confidence/upside/downside; the scripts' output is
   authoritative, never freehand-composed in prose.
7. **Book assembly + memos** — ranked book with target weights (scaled by the gross-exposure dial),
   one memo per name (thesis / dated catalyst / entry trigger / invalidation level / size / the top
   2-3 ways it's wrong + planned response). Pre-register exits AT ENTRY.
8. **Output + LEARNING LOOP** — present the book, hand weights to the `etoro` skill for execution,
   and run the compounding-edge loop (`references/learning-loop.md`): resolve closed picks into the
   rich `picks-log.jsonl` schema, grade process vs outcome (alpha-vs-SPY), and — monthly — recompute
   the signal×regime performance table that modulates next month's sizing. The agent gets smarter
   every month from its own track record; risk/personality params stay hard-locked. **Memory is
   persisted with `bash scripts/state.sh save`** (and restored with `load` before Stage 1) to the
   `alpha-hunt-state` git branch — REQUIRED because the routine's fresh container wipes the cache
   weekly; without it the learning loop resets every run. Filings/statements prefer the connected
   **FinancialFilings** MCP (SEC EDGAR is the fallback) — see data-runbook.

## The signal library — briefly

**MANDATORY — READ ENTIRE FILE** at Stage 2-4: load [`references/signals.md`](references/signals.md)
for the full specs + thresholds. **Do NOT load** for preflight/regime/sizing stages. Summary:

| Sleeve | Signal | Why it survives 2026 | Key rule |
|---|---|---|---|
| Momentum | Residual momentum, std. by residual σ (composite weight **0.50**) | Harder to crowd than raw 12-1 (reported to be roughly Sharpe ~0.48 vs ~0.25 — unverified) | Info-ratio form (Σε/σ_ε); carry more patiently than raw momentum |
| Momentum | 52-week-high proximity (weight **0.25**) | Behavioral anchor, decays slowly | Distinct from return momentum |
| Momentum | Information discreteness, sign-count (weight **0.15**) | Path matters: grinders beat gap-and-flat (reported +5.94% vs -2.07% — unverified) | LOWER is better; penalize high-discreteness names |
| Momentum | Up-ratio (weight **0.10**) | Feeds the sign-count discreteness form | Fraction of up-weeks in the formation window |
| Momentum | Raw 12-1 momentum (reported, **0 weight**) | Double-counts residual momentum if scored | Diagnostic only — never re-add to the composite |
| Momentum | Value+momentum tilt | Negative correlation is the point | **Weighted z-score, NEVER AND-filter** |
| Catalyst | Earnings-announcement premium | 72% of premium is realized PRE-print | Pre vs post entry is a deliberate choice |
| Catalyst | Insider opportunistic cluster | ~82bp/mo; routine = zero | Spec: 3+ buyers/7-14d, exclude 10b5-1. CODE ships 90d, NO 10b5-1 filter → weak lead only |
| Catalyst | Estimate-revision breadth | Net analyst-upgrade shift (magnitude, not just direction) | "Beat and raise" > either alone |
| Catalyst | 13F new high-conviction | Clone BORING low-turnover funds | ≥7.5% positions; NOT Tiger Cubs |
| Catalyst | 8-K Item-code triage (`fetch-catalysts.js`) | Material (2.02/1.01/2.06/3.01…) vs noise, market-wide | **4.02 restatement is ALWAYS `negative_signal:true`** — never a buy |
| Confirmer | Options-implied skew/vol-spread/O-S ratio (`compute-options-signals.js`) | Informed flow shows in options before the print | Catalyst-sleeve confirmer/demerit ONLY — never a sizing input, never a standalone trigger |
| Veto | Social-sentiment mention z-score (`fetch-sentiment.js`, ApeWisdom) | A spike in retail attention is LATE, not a lead | VETO/TRIM only — never sources or sizes a buy |

**Every pick needs a dated, specific catalyst (min 3:1 upside/downside) or it is disqualified.**
Short interest is BEARISH on average — use it to AVOID longs, never to hunt squeezes. AVOID pure
FDA/PDUFA binaries; if engaging, trade the run-up and exit, or enter only post a clean AdCom vote.

## Risk, sizing & the composite score

**MANDATORY — READ ENTIRE FILE** at Stage 1b (holdings review), Stage 4 (scoring), and Stage 6
(sizing): load [`references/risk-and-sizing.md`](references/risk-and-sizing.md). **Do NOT load** during regime or
catalyst-intake stages. Non-negotiables:

- **Cluster-Kelly at 10-25% of full**, never per-ticker. ENB: 10 picks ≈ 3-6 bets.
- **Momentum crashes are a REBOUND phenomenon** — de-risk on the strategy's OWN trailing vol, not
  on market declines (a decline-trigger fires on the wrong event). Vol-target **18-25% band** (12%
  would need ~60% cash on a 5-15 name concentrated book, which breaks the concentration mandate).
- **Binary-catalyst positions hard-capped 2-5%** regardless of conviction (gaps jump stops).
- **Track Calmar, not just Sharpe** (high-Sharpe/low-Calmar = hidden crash risk).
- **Composite score has a disqualifying VETO gate** — one fatal factor caps the whole score.
  Override-UP bar (act despite a red flag) >> override-DOWN bar (skip despite a good score).
- **Sizing is a deterministic script call, not prose arithmetic** — `scripts/compute-sizing.js` takes
  the LLM's candidates + confidence/upside/downside and computes every weight (Kelly → cluster budget
  → vol-target → regime dial → hard caps); its output is authoritative.

**HARD-LOCKED CEILINGS — inlined here on purpose.** These are the numbers that bound worst-case loss,
so they must survive even if the reference file above never gets loaded under context pressure. They
are enforced in `compute-sizing.js` and are NOT tunable by the learning loop:

| Locked parameter | Value |
|---|---|
| Kelly fraction of full | ≤ **0.25** (script errors above it) |
| Book vol target | **0.18-0.25** band (script errors outside it) |
| Binary-catalyst position | **2-5%** hard cap |
| Single position | ≤ **25%** of equity |
| Top-5 positions combined | ≤ **60%** of equity |
| Capacity cap | ≤ **1%** of the name's ADV |
| Fraud veto | Beneish M > −1.78 **OR** Sloan accruals > 20% **OR** going-concern → DROP |
| Mandate | long-only, `Leverage: 1`, no CFDs, no leveraged ETFs for multi-day holds |

## Regime throttle — the gross-exposure dial

**MANDATORY — READ ENTIRE FILE** at Stage 1: load
[`references/regime-throttle.md`](references/regime-throttle.md). **Do NOT re-load** later — the
dial is set once per run. It converts a few robust inputs (distribution-day count, breadth
divergence, VIX term-structure SHAPE not level, HY-IG credit spreads) into a -3..+3 score → a
gross-exposure % that scales every position. This is the mechanical throttle that fires before a
human "feels" the regime shift — 2025-26 unwinds resolved in days via forced deleveraging.

## LLM guardrails — the anti-hallucination spine

**MANDATORY — READ ENTIRE FILE** before Stage 5 (adversary fleet) and any numeric work: load
[`references/llm-guardrails.md`](references/llm-guardrails.md). Covers: no-number-without-source,
the deterministic fact-ledger, the hard devil's-advocate protocol (99.2% vs 48.3% dissent),
look-ahead contamination, the calibration log, and treating ingested news/filings as an untrusted
prompt-injection surface.

## Data runbook

**MANDATORY — READ ENTIRE FILE** before writing or invoking any data call: load
[`references/data-runbook.md`](references/data-runbook.md) — the reuse inventory of the 8 investment
scripts, the new endpoints (market-wide Form-4 feed, free CBOE options, keyless FRED, Finnhub,
Nasdaq calendar), exact invocations, batching rules, and the dead-source traps (stooq, Finviz, FMP
demo key). **Do NOT load** for conceptual questions.

## Critical Anti-Patterns (this skill MUST NOT do these)

- **Never re-pick the whole book weekly.** Refresh signals monthly; the weekly loop is monitor /
  exit / fresh-catalyst / deploy only. Weekly reformation is a cost-suicide anti-pattern.
- **Never leave the existing book unmanaged, and never over-churn it either.** Stage 1b reviews every
  held position each week and sells/trims on a real exit trigger (thesis broken, catalyst passed,
  momentum break, drawdown, out-of-mandate) — but a winner with an intact thesis and live momentum is
  HELD. Selling on discipline, yes; dumping good positions for activity's sake, no.
- **Never blend the two sleeves' contradictory filters.** Momentum sleeve favors steady grinders;
  catalyst sleeve holds explosive dated-catalyst names sized smaller. Different populations,
  different sizing — never one screen trying to satisfy both.
- **Never let a number enter from memory.** Look-ahead contamination. Fetch or don't use it.
- **Never combine value+momentum as an AND-intersection.** Weighted composite only.
- **Never size per-ticker Kelly, or above 25% of full.** Cluster-level, fractional.
- **Never hold a pure binary (FDA/earnings) as a normal position.** Cap 2-5% or trade around it.
- **Never treat high short interest as a bullish squeeze setup.** It's bearish on average.
- **Never de-risk on market declines alone.** Momentum crashes hit on the rebound; use own-vol.
- **Never mistake a favourable regime dial for evidence the strategy works.** The dial answers "is
  the market hospitable" — it says nothing about whether this book has any demonstrated edge, and no
  threshold in this skill has been validated against its own results yet (risk-and-sizing.md §0).
- **Never treat a recycled/rehashed story as a fresh catalyst, and never build a position on news or
  social sentiment.** The exploitable effect is next-day and reverts inside this skill's own weekly
  cadence — by the time a weekly run could act on it, the edge is gone and what's left is late risk.
  `fetch-sentiment.js` is VETO/TRIM only for this reason; see risk-and-sizing.md §11.
- **Never accept an adversary's "looks fine" without receipts** (what it checked + the bear case
  it self-committed to). Silence without receipts is a stall, not a pass.
- **Never skip the calibration log or let outcome overwrite the process grade.** A disciplined
  loser and a sloppy winner are not the same trade; conflating them trains the wrong behavior.
- **Deflated Sharpe before trusting a tuned number — conditional, not unconditional.** DSR on a
  single-digit-N track record is theater, not rigor; the trigger is **≥30 resolved trades** for that
  signal family. Full rationale + threshold: `references/learning-loop.md` §7.
- **Never let the learning loop touch risk/personality params.** It self-tunes tactical weights/
  multipliers within ±30% only; the Kelly ceiling, position caps, fraud veto, and long-only/unleveraged
  are hard-locked. An agent that can lower its own risk limits eventually lowers them to ruin.
- **Never chase the hype-graveyard signals** (signals.md): named-investor persona "voice", time-series
  foundation models on stocks, congressional-trade copying, self-reported "my bot returned X%", or
  0DTE/options strategies. All are grift or decayed; the evidence bar rejected them.
- **Never let the book drift out of its small-cap tilt.** The achievable edge, honestly scoped, is a
  tilt toward the **smaller end of the S&P 600 leg** — thinner analyst coverage, harder institutional
  position-building — real but modest, NOT a structural moat (the universe is the S&P 1500, so every
  name here is already 13F-held at scale; there is no sub-institutional-threshold edge to claim).
  Drifting into mega-caps as the account grows still throws away even that modest edge (capacity
  ceiling §13; signals.md "stay small, honestly scoped").
- **Never let a signal's SPEC drift from what the code computes.** A reference file claiming a
  stronger construction than the script implements — a "3-factor regression" that the code actually
  runs as CAPM-only, a "sign-count discreteness" that the code actually computes as a magnitude ratio —
  produces false confidence in a LIVE book: the doc reads like a stronger edge than what's sizing real
  money. Whenever doc and code diverge, correct the doc to match the code or fix the code to match the
  doc — never leave them silently divergent.
- **Never claim certainty.** Output conviction as a range; say "the framework ranks this highest and
  here's what kills it," not "this will go up."

## End-of-run discipline

Always end with: the ranked book (or "throttle to cash — regime hostile"), the per-name memos with
pre-registered exits, the picks-log confirmation, the "not financial advice / risk pre-accepted"
footer, and the hand-off note to the `etoro` skill (target weights as % of equity). Then schedule
the next weekly run.

## References

| File | Load when | Do NOT load |
|---|---|---|
| [`execution-prompt.md`](execution-prompt.md) | Running the pipeline | Conceptual questions |
| [`references/signals.md`](references/signals.md) | Stage 2-4 (screening/scoring) | Preflight/regime/sizing |
| [`references/risk-and-sizing.md`](references/risk-and-sizing.md) | Stage 4 + Stage 6 | Regime/catalyst stages |
| [`references/regime-throttle.md`](references/regime-throttle.md) | Stage 1 (set the dial) | After Stage 1 |
| [`references/llm-guardrails.md`](references/llm-guardrails.md) | Stage 5 + numeric work | Pure data plumbing |
| [`references/data-runbook.md`](references/data-runbook.md) | Any data call | Conceptual questions |
| [`references/learning-loop.md`](references/learning-loop.md) | Stage 8 + setting sizing/weights | One-off runs w/ empty log |
