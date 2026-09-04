---
name: alpha-hunt-learning-loop
description: The compounding-edge memory system — a rich picks-log schema, weekly reflection injection, monthly signal×regime performance table, confidence recalibration, and per-sleeve decay/Brier throttles. Load at Stage 8 (calibration) and whenever sizing multipliers or signal weights are set.
---

# Learning Loop — Compound Edge From Your Own Track Record

The biggest gap in a naive weekly agent: it starts FRESH every run and never learns from its own
results. Research on trading-agent memory (FinMem/FinAgent layered memory, FinCon conceptual verbal
reinforcement, Reflexion) shows the durable wins come from a feedback loop, not a smarter one-shot
prompt. This is zero-infra: a JSONL log + tail/grep + a small monthly table. No vector DB.

**Governance — locked vs mutable (do this or the loop is dangerous).** The loop may self-tune only
TACTICAL parameters within a bounded range: catalyst weights, signal sub-weights, sizing multipliers
(±30% drift cap). It may NEVER modify RISK/PERSONALITY parameters — Kelly ceiling (25%), position
caps, the fraud veto, the regime dial thresholds, long-only/unleveraged. Those are hard-locked
against agent self-modification. An agent that can rewrite its own risk limits will, eventually,
rewrite them to zero.

## 1. The rich picks-log schema (the keystone — makes everything else computable)
Every entry (BUY / TRIM / SELL / HOLD) appends one JSONL line to `~/.cache/alpha-hunt/picks-log.jsonl`.
At ENTRY, log the pre-registered plan; at RESOLUTION (exit or review), append the outcome fields.

```
{ "ts": "...", "ticker": "...", "action": "BUY|TRIM|SELL|HOLD",
  "trade_id": "...",                     // stable unique id (e.g. ticker+entry_ts) — the join key every
                                          // append-only resolution line references (see §1a)
  "signal_family": "residual-momentum|frog-in-pan|pead|insider-cluster|activist-13d|options-skew|...",
  "sleeve": "momentum|catalyst",
  "composite_score_components": { "...": "..." },  // the SUB-scores that fed the composite (momentum
                                          // z, value tilt, catalyst tier, options confirm/demerit,
                                          // sentiment veto, ...), not just the total — a losing quarter
                                          // needs to know WHICH sub-score misfired, not just that it did
  "adversary_verdicts": [ { "lens": "thesis-break|crowding-correlation|catalyst-reality|data-integrity",
    "verdict": "BLOCK|FIX-THEN-MERGE|PASS", "reason": "<=1 sentence" } ],  // what the fleet actually
                                          // said, per lens — feeds §3a's adversary-fleet grading
  "overridden_flag": { "overridden": true|false, "what": "veto|score|...", "why": "<=1 sentence>" },
                                          // was a veto or score overridden by a human/agent, and why —
                                          // the accountability trail against the sycophancy-toward-
                                          // your-own-picks failure (llm-guardrails.md §4)
  "binding_constraint": "...",           // compute-sizing.js's name for whichever step (kelly|cluster-
                                          // budget|vol-target|regime-dial|binary-
                                          // cap|single-name-cap|top5-cap|adv-cap) actually set the
                                          // final weight — the single most useful field for diagnosing
                                          // "why was this sized the way it was" six months later
  "stated_confidence": 0.0-1.0,          // the number that fed Kelly — grade it later
  "regime_dial_at_entry": -3..3,
  "entry_price": <fetched>, "weight_pct": <of equity>,
  "dated_catalyst": "...", "catalyst_date": "YYYY-MM-DD",
  // pre_registered exits are SLEEVE-CONDITIONAL — see the note below the schema.
  "pre_registered": {
    "trailing_stop_spec": "<momentum sleeve: a RULE not a price, e.g. Chandelier - highest close since entry minus 3xATR22>",
    "thesis_completion_exit": "<catalyst sleeve: a REASON not a price - the catalyst resolving>",
    "time_barrier_weeks": N
  },
  // --- appended at resolution ---
  "exit_ts": "...", "exit_price": <fetched>, "exit_reason": "target|stop|time|thesis-broken|...",
  "r_multiple": <realized R>, "spy_alpha_pct": <return minus SPY over the hold>,
  "brier_component": <(stated_confidence - outcome_1_or_0)^2>,
  "thesis_correct_for_stated_reason": true|false,   // right for the RIGHT reason?
  "lesson": "<=1 sentence, concrete" }
```
**No fixed `profit_target` field, and this is deliberate, not an omission.** Momentum's expectancy is
right-tail driven — a handful of monster winners carry the sleeve — and a fixed profit target truncates
precisely the returns the strategy depends on; a `trailing_stop_spec` (e.g. Chandelier: highest close
since entry − 3×ATR22) plus a time-barrier let winners run instead. Catalyst-sleeve entries may still
exit on `thesis_completion_exit` (the catalyst resolving), which is a REASON, not a price target. A
future editor who "helpfully" restores a fixed `profit_target` on the momentum sleeve is reintroducing
the exact truncation this schema exists to prevent — don't.

**APPEND-ONLY — MANDATORY.** Resolution is a NEW JSONL line referencing the entry's `trade_id`, NEVER
an in-place edit of the entry line. An editable entry lets a losing thesis be retroactively reworded
after the fact — exactly the sycophancy-toward-your-own-picks failure llm-guardrails.md §4 warns about.
Append-only makes the original claim (signal, confidence, catalyst, invalidation condition) immutable
evidence that cannot be quietly softened once the outcome is known.

Grade against **alpha vs SPY**, not raw return (a +8% hold in a +12% tape is a LOSS). "Right for the
wrong reason" (thesis wrong but made money) is logged as a process FAIL — it trains the wrong behavior
otherwise (see the process-vs-outcome rule in llm-guardrails).

## 2. Weekly reflection injection (before Stage 4 scoring)
`tail`/`grep` the picks-log — no retrieval model needed:
- **Same-ticker history**: for any candidate you held before, inject its prior realized alpha + its
  `lesson` verbatim into the analysis. ("You bought SNDK on a momentum signal 8 weeks ago; it was a
  spinoff data artifact, −1.2R. The momentum score on it is untrustworthy.")
- **Regime-filtered recent lessons digest**: the last ~10 resolved `lesson` lines whose
  `regime_dial_at_entry` is within ±1 of the current dial. Same regime → relevant lessons.
- **Critical-event pin**: any resolution with `|r_multiple| > 3` (a blowup or a monster) is pinned
  into the digest PERMANENTLY regardless of age (FinMem's promotion rule) — the rare events teach most.

## 3. Monthly experience-compression pass (runs on the monthly signal-refresh week)
Raw retrieval gets NOISIER as the log grows; compress instead. Recompute from full history a small
**signal_family × regime** table:

| signal_family | regime bucket | N | hit_rate | mean_R | mean_alpha | Brier |
|---|---|---|---|---|---|---|

This table — not raw log lines — modulates the **cluster-Kelly sizing multiplier** per signal family.
A family with a strong realized hit-rate/Brier in the current regime gets a higher multiplier (bounded
by the ±30% tactical cap); a degraded one gets cut. Cache to `~/.cache/alpha-hunt/signal-perf.json`.

## 4. Confidence recalibration (before any confidence touches Kelly)
LLM conviction scores are systematically miscalibrated (overconfident on high-probability calls). Build
a trailing **reliability diagram**: bucket resolved picks by stated_confidence decile, compute realized
hit-rate per bucket, fit an isotonic (monotone) correction. Pass every new stated_confidence through
that correction BEFORE it enters **the Kelly-fraction formula** — `f_full = (p·(b+1) − 1)/b`, defined
in [`risk-and-sizing.md`](risk-and-sizing.md) §1 and implemented in `scripts/compute-sizing.js`. Track
rolling **Brier score** as the single calibration health metric — improving Brier = the loop is working.

The ±30% tactical drift cap on self-tuned weights/multipliers (Governance, above) is not merely
cautious, it is evidenced: DeMiguel, Garlappi & Uppal (2009, RFS) show mean-variance-optimized weights
need implausibly long samples (~3000 months for 25 assets) to beat naive fixed weighting out-of-sample
— this loop's history will never be that long, so aggressive self-tuning of weights is EXPECTED to lose
to leaving them alone, and the cap is sized accordingly.

## 5. Per-sleeve performance throttle (independent of the macro regime dial)
Separate from the market-regime dial: cut a SLEEVE's Kelly fraction when its OWN trailing stats
degrade. If the momentum sleeve's trailing-13-week Brier or SQN100 drops past a threshold vs its
baseline, throttle that sleeve down until it recovers — the agent self-adapts from its own track
record, not just from the market. (FinMem's character shifts on its own trailing return; same idea.)

## 6. Signal decay clock (every signal, every week)
Alpha decays and crowds — treat it as a certainty, not a risk. Maintain each signal family's rolling
6-12mo hit-rate; **downweight any signal whose recent hit-rate has dropped materially vs its
full-history baseline.** The template to watch for: congressional-trading copy decayed 42.5%→32.2% as
it crowded. Distinguish genuine decay from a single forced-deleveraging week (one liquidity event
breaks every signal temporarily — don't bench a good signal for one bad week; see regime-throttle).

## 7. Anti-overfitting gate — Deflated Sharpe / PBO (the canonical copy — other files point here)
You iterate on this skill's thresholds against the SAME history repeatedly. That is textbook multiple-
testing. **This is a conditional trigger, not an unconditional mandate**: it applies once **≥30
resolved trades exist for the signal family in question** — a DSR computed on N≈6 is theater, not
rigor. Once that threshold is met, before trusting ANY tuned threshold or new signal weight, compute a
**Deflated Sharpe Ratio** (López de Prado) that discounts the raw Sharpe for the number of variants
already tried, and prefer **purged, embargoed walk-forward** validation over a single in-sample fit.

**The honest interim position, below N=30:** a tuned threshold or signal weight is an **unvalidated
prior**, not a finding, and must be labelled as such — not defended with a statistic (DSR) that cannot
yet be computed on too few resolved trades. Say the limitation out loud rather than borrow the
authority of a rigorous-sounding statistic you haven't actually run. Almost no retail effort does
this; it is the cheapest protection against fooling yourself. A backtested Sharpe with no DSR is noise.

## 8. Grade the adversary fleet
Nothing currently records whether an adversary that returned `BLOCK` was RIGHT. The adversary fleet
(llm-guardrails.md §3) is the single most expensive component in the pipeline — a Sonnet agent per
lens, per candidate — and it is entirely unmeasured. Close that gap:
- Log every `BLOCK` verdict with its ticker, date, lens, and `reason` (the `adversary_verdicts` field
  in the picks-log schema, §1, carries this even for candidates that never became a position).
- At a **4-8 week horizon**, look up the blocked name's actual return vs SPY over that window,
  regardless of whether it was ever traded.
- Compute a **fleet hit-rate**: a lens that blocks eventual winners is COSTING money (a false-positive
  veto tax on the book); a lens that blocks eventual losers is EARNING its keep. Track this per lens
  (`thesis-break` / `crowding-correlation` / `catalyst-reality` / `data-integrity`), not just fleet-wide
  — one lens can be worth its cost while another is dead weight.
- This calibration stream accrues FASTER than trade-resolution-based calibration (§4): a blocked name
  never needs to be held to be graded, it just needs its price checked later — so the fleet's own
  track record becomes statistically meaningful well before the picks-log does.

## What this buys you
A book that is quietly smarter every month: sizing bends toward what has actually worked for THIS
agent in THIS regime, confidence is calibrated to realized outcomes, decayed signals fade before they
cost real money, and the rare blowups are never forgotten. That compounding is a bigger edge than any
single new signal — and it's free.
