---
name: portfolio-review-doctrine
description: The separation-of-clocks architecture, asymmetric evidence bars, cooldowns, event-driven interrupts, and drift-response rules for the recurring portfolio review. MANDATORY load at the start of every REVIEW run, any cadence. Do NOT load during BUILD-mode research or scoring.
---

# Review Doctrine — Two Clocks, Never One

## The Prime Directive

A process invoked ~52 times a year and asked "does anything need to happen?" **will manufacture
reasons to act**, even when the correct evidence-based answer is no. Two independent lines of
evidence converge on this, from completely different disciplines:

- **Behavioral.** Gneezy & Potters (1997, QJE) is a genuine **controlled causal experiment**
  [VERIFIED] — identical underlying return distribution, only the feedback/evaluation frequency
  varied, and subjects who saw outcomes every period took on measurably less risk / behaved more
  reactively than subjects evaluated only every three periods. Benartzi & Thaler (1995) corroborates
  from simulation: the historical equity premium is consistent with investors whose *effective*
  decision horizon is ~1 year regardless of their stated goals. Honestly: effect **direction** is
  robust across replications; effect **magnitude** has replication caveats and should not be quoted
  as a calibrated dial. [High confidence: direction. Low-Medium confidence: magnitude.]
- **Portfolio math.** Higher-frequency calendar rebalancing produces no better risk-adjusted return
  than annual — only more turnover and cost (Vanguard, multiple studies, High confidence). The
  "rebalancing premium" itself is thin, roughly comparable in size to its own noise, and is
  substantially a **mean-reversion bet dressed as risk control** — a bad fit for single-stock
  theses that are *not* supposed to mean-revert to a policy weight the way an asset-class sleeve is.

**Resolution: the fix is not to monitor less — it is to structurally forbid frequent monitoring
from making frequent decisions.** Looking often is fine, even good. Deciding often is evidenced to
be actively harmful. Keep them mechanically separate.

## The Separation of Clocks

Collapsing "how often the agent looks" into "how often it may trade" is the single most important
anti-pattern this doctrine exists to prevent. Four clocks, each with a hard allow-list of outputs:

| Cadence | Runs | Allowed outputs | Forbidden |
|---|---|---|---|
| **Weekly** (hazard-scan) | Hard drift-band check, named event-trigger scan, idle-cash check, log | "No action, logged" (**the expected outcome**); mechanical hard-band trim; flag-for-review; idle-cash escalation | Originating a new position, a full exit, or a discretionary add — never, on its own authority |
| **Monthly** | Soft-band check (calendar side of hybrid rule); light thesis scan for anything material enough to not wait | Same menu as weekly, plus authority to schedule an early full review for one specific name | Formal rebalance decisions, full thesis re-scoring |
| **Quarterly** (aligned to earnings where possible) | Full thesis re-score per name; valuation refresh; tax-lot review; formal rebalance-to-band decision | Full menu: trim, add, exit, flag a new candidate for the next BUILD cycle | Originating a new position outright — flag only, never buy |
| **Annual** | Position-count and concentration check; process retrospective (realized turnover vs. budget, theses that played out vs. didn't) | Full menu plus structural changes (band widths, cadence itself) | — |
| **Event-driven** (always active, outside every cadence) | Named-trigger scan only | Flag-for-review for judgment-requiring triggers; mechanical action only for hard-band breaches or pre-committed stop rules | Treating every trigger as an automatic trade |

Quarterly is the **only routine trading window**. Everything faster is monitoring, not decision-making.

## "No Action" Is a Success

Encode "no action, logged" as the expected weekly outcome, not a null result to be explained away.
The weekly pass must never ask *"what should I do this week"* — that question always finds an
answer. It must ask only: **"has a pre-committed trigger fired?"** — a question that can honestly
be no. This mirrors the investment-committee governance finding [Medium confidence — institutional
best-practice consensus, not a controlled study]: committees that meet and decide frequently react
to noise; the fix is a written policy that specifies *in advance* what triggers action, so a
meeting can close with "nothing fired" instead of inventing a reason to have met.

## Asymmetric Evidence Bars by Action Type

Not all actions need the same proof. The bar rises with how expensive the action is to reverse:

1. **Hold** — default null hypothesis. Zero evidence required; the process must affirmatively
   reject it to do anything else.
2. **Mechanical trim on hard-band breach** — the lowest bar, no judgment call. This is precisely
   why it is the *only* category safe for a weekly-cadence process to execute unilaterally.
3. **Discretionary add** — requires a dated thesis re-affirmation from the last quarterly review.
   Never opportunistic off a weekly pass, no matter how good the price looks.
4. **New position** — the full BUILD-mode underwriting bar. A review may only **flag** a
   candidate for the next research cycle; it may never originate a buy.
5. **Full exit** — the highest bar. Requires a written, dated statement of *which specific thesis
   pillar broke* and *why the break is durable, not transient*. "Price is down" is never sufficient.

## Cooldowns and Minimum Holding Periods

- **Cooldown after a discretionary trade**: ~60–90 days before another discretionary trade in the
  same name is permitted. Blocks the "traded last week, price moved, correct by trading again"
  whipsaw a weekly cadence invites.
- **Minimum holding period before a discretionary full exit**: ~6–12 months from initiation,
  absent an event-driven interrupt. Operationalizes "give the thesis time to play out."
- **Design rationale**: borrowed from SEC Rule 10b5-1 cooling-off windows, which separate the
  *decision* to trade from its *execution* to prevent reactive, in-the-moment trading. Treat this
  as a **transferable design pattern, not literature evidence for this use case** [analogy, Medium
  confidence] — the regulation exists to stop insider-informed trading, not myopic churn, but the
  structural mechanism (mandatory minimum gap between decision and re-decision) generalizes cleanly.
- **Precedence when cooldown and hard-band conflict**: mechanical hard-band trims are **exempt**
  from cooldown (they carry no discretionary judgment). Discretionary trades remain subject to it.

## Event-Driven Interrupts

Always active, independent of every cadence above. Named triggers: going-concern qualification;
credible fraud discovery (investigation, restatement, corroborated whistleblower, auditor
resignation for cause); M&A affecting a held name as acquirer or target; dividend cut or
suspension; index deletion for cause (not routine reconstitution); catastrophic guidance revision
contradicting a stated thesis pillar; hard position-drift breach.

Two design points that keep this channel safe:

- **Most interrupts flag for review; they do not fire a trade.** Only mechanical hard-band
  breaches and pre-committed user stop rules justify near-automatic action. Fraud, going-concern,
  M&A, and guidance shocks require judgment about magnitude and durability that a weekly pass
  should surface, never resolve unilaterally.
- **The interrupt channel needs its own materiality filter**, or it becomes a second weekly-churn
  vector — e.g., a "dividend cut" that's actually a special-dividend base effect should be filtered
  before it escalates to a full flagged review.
- **Index-deletion note** [Medium confidence, Greenwood & Sammon/NBER]: the price impact of index
  deletion has weakened substantially over time (~-15% abnormal return in the 1990s vs. ~-2% by the
  2010s) — a much weaker *price* signal today, but deletion-for-cause (failing profitability or
  market-cap screens) can still be a meaningful *fundamental* signal. Treat cause, not the deletion
  event alone, as the actual trigger.

## Drift Response Is Asymmetric

Do not treat all drift alike — the correct response depends on *why* the weight moved:

- **Drift up from genuine outperformance** → **higher** bar to trim. A compounding winner
  re-rating upward is exactly the outcome the thesis wanted; mechanically trimming it cuts against
  the "let winners run" logic a concentrated book depends on. Widen the band or trim above a hard
  cap only.
- **Drift up from denominator shrinkage** (others fell, this one didn't) → mechanical trim-to-band
  is more defensible — this is closer to a genuine, name-agnostic concentration event.
- **Drift down from underperformance** → needs a **thesis check first**. Never let a weight
  trigger auto-add to a name whose fundamentals haven't been independently re-verified — that is a
  falling knife dressed as discipline, not opportunistic rebalancing.

Two more denominator traps: **cash must carry its own target weight and be included in drift**
(idle proceeds/dividends are a phantom weight shift, not a stock signal); and for a global book,
**decompose drift into local-price-driven vs. FX-driven** — currency drift is a hedging question,
not a stock-selection question, and conflating the two risks trimming a working thesis over an
unrelated FX move.

## Numeric Thresholds (reasoned defaults — expose as configurable)

- **Soft band** (triggers monthly-cadence attention, not a trade): ~20% relative to target weight
  — anchored to Daryanani (2007) [VERIFIED, but studied diversified multi-asset sleeves, not
  single stocks; treat as a **floor for looseness**, not a validated single-stock number].
- **Hard band** (triggers mechanical trim consideration): ~1.75–2x target weight above, ~0.3–0.4x
  below. **This document's own extrapolation, not literature-derived** — the closest study
  (Daryanani) never tested a 5–10 name concentrated book. Starting hypothesis, not settled fact.
- **Cash ceiling**: ~5% of portfolio value idle beyond one monthly cycle without explicit reason
  escalates to the next scheduled review as a required action item.
- **Turnover budget**: ~20–40% annual — materially above this is a process failure, not diligence.

## Cost and Tax Layer

Transaction costs (approximate, order-of-magnitude only): liquid large-cap ~5–15bps round-trip;
less-liquid mid/small-cap ~15–30bps plus 10–50bps market impact on size. **Tax drag frequently
exceeds trading-cost drag** — an illustrative estimate puts it near ~160bps/yr at only 25% turnover
[Medium confidence on the figure; High confidence on the qualitative point]. The US 1-year LTCG
cliff creates a mechanical incentive to defer a marginal, non-event-driven trade a few weeks rather
than realize short-term gains; wash-sale rules (US) block repurchasing a security sold at a loss,
or a substantially identical one, within a 30-day window either side of the sale.

**All tax content above is jurisdiction-dependent and NOT universal.** This account is EUR-base —
never assume US holding-period or wash-sale rules apply without first confirming the governing
jurisdiction; treat the 1-year cliff and wash-sale mechanics as illustrative of the *shape* of the
problem (realization timing matters), not as rules to enforce by default.

## Anti-Patterns

- **Collapsing review cadence and trading cadence.** If "run weekly" implicitly means the weekly
  output may be a trade, the agent will find one — a review starting from "what should I do"
  always finds an answer.
- **Mechanically trimming winners back to a fixed target weight** in a concentrated, thesis-driven
  book — importing asset-class rebalancing logic where it doesn't belong.
- **Auto-adding to a name whose weight fell** without first re-verifying the thesis.
- **Ignoring cash and FX in drift** — both create phantom drift that isn't a stock-selection signal.
- **Treating every event-driven trigger as requiring an automatic trade** — only hard-band
  breaches and pre-committed stops are safe to auto-execute.
- **No cooldown after a trade** — invites whipsaw churn with no informational gain, pure cost/tax
  destruction.
- **"I've been reviewing this for weeks and haven't done anything" becoming pressure to act.** This
  is the myopic-loss-aversion trap in its purest agentic form — the mere passage of review cycles
  is not evidence. Log the cycle count if useful for the retrospective; never let it argue for a
  trade.
- **Presenting Daryanani's multi-asset band, or this doctrine's own hard-band multiples, as
  precisely optimized for a single-stock book.** They are reasoned defaults and explicitly labeled
  as such above — do not launder that hedge away for readability.
