---
name: portfolio-cash-deployment
description: Doctrine for deploying new cash — lump-sum vs staged entry evidence, deposit classification, top-up vs new-name decisions, and expressibility gating. MANDATORY load in DEPOSIT mode and whenever idle cash is being deployed. Do NOT load for the weekly hazard-scan or for scoring stages.
---

# Cash Deployment Doctrine

## 1. Lump-sum vs staged entry — the central question

**Finding, direction confident, magnitude approximate**: Vanguard's oft-cited research
("Dollar-cost averaging just means taking risk later," 2012, covering US/UK/Australia
market history) found lump-sum investing beat a 12-month DCA schedule roughly **two-thirds
of the time** — commonly reported as ~67% for a 12-month stagger, with the lump-sum edge
*rising* for shorter stagger windows and *falling* for longer ones. Average outperformance
where lump-sum won was on the order of low-single-digit percentage points over the
deployment year for a 60/40-style portfolio — **treat that magnitude as approximate,
sourced from secondary summaries, not re-derived here.** *(High confidence on direction and
rough magnitude; do not quote the 67% or the point-estimate outperformance as precise —
re-verify if a number this specific must be shown to the user.)*

**Why**: equity markets rise more often than they fall — the S&P 500 has posted a positive
calendar year roughly 70-75% of the time historically. Staging cash into the market means
spending part of the staging period in cash, which is a bet against that base rate. Every
week spent out of the market widens the exposure gap that drives lump-sum's edge.

**The load-bearing reframe**: DCA is a **regret-minimization / behavioral tool, not a
return-maximizing one.** It exists to reduce the expected pain and expected bad decision
that follow an immediate drawdown right after full deployment — not to improve expected
return, which it does not do on average. Presenting DCA to the user as if it were a
risk-adjusted-return optimization is a category error this skill must not make.

**Honest conditions under which staging IS defensible** — none of these are "the market
looks expensive," all are structural or behavioral:

- A single position would be large relative to the book (the deposit, deployed at once,
  would push one name past the per-name cap at initiation — see `SKILL.md` locked
  ceilings) — stage that name's fill, not the whole deposit.
- The name is illiquid enough that a single order would move the price against the user —
  stage for execution-quality reasons, not market-timing reasons.
- A genuine near-term binary event is disclosed and pending for a candidate name
  (litigation ruling, regulatory decision, pivotal trial readout) — this is an event-risk
  reason, not a "wait for a better price" reason.
- The user has stated, or has a demonstrated history of, panicking and selling after an
  immediate post-deployment drawdown — staging here is buying insurance against a
  behavioral failure mode the user actually has, not a forecast.

If none of these four apply, **default to lump-sum deployment of whatever passes the
top-up/new-name and expressibility gates below.** Do not stage by default and do not let
"markets feel high" count as a fifth reason — that is market timing wearing a DCA costume,
and this skill forbids market timing (see `SKILL.md`, `06-agent-guardrails.md`).

## 2. Deposit classification — what actually counts as new capital

A rise in cash balance is **not automatically a deposit.** Classify every delta between the
live balance and the last-known state snapshot (from `state.sh load`) before treating any
of it as deployable new capital:

| Source of the cash delta | Book size effect | Handling |
|---|---|---|
| **External deposit** (wire/transfer into the account) | Genuinely expands NAV | The only category this doctrine's deployment logic applies to |
| **Dividend accrual / cash dividend received** | Already inside NAV | Small, routine — folds into ordinary sleeve/drift math, not a deployment event on its own unless it pushes cash meaningfully over the sleeve ceiling |
| **Sale proceeds** (a name was trimmed or exited) | Already accounted for in the plan | The plan that generated the sale already decided where that capital goes (reinvest, raise sleeve, fund a different name) — re-treating it as "new" capital double-counts it |
| **FX revaluation** of a non-base cash balance (e.g. USD cash appreciating in EUR terms) | Not new capital at all | A valuation change, not a cash flow — never deployable as if it were fresh money |

**Method**: compare the live `get_account_balances`/`get_account_summary` cash figure
against the cash figure in the last saved state. Attribute the delta by checking, in order:
(a) does the trade log show a recent sale for roughly this amount? → sale proceeds; (b) does
a dividend/income entry explain it? → accrual; (c) is the balance in a non-EUR currency and
did only its EUR-converted value move, not its native-currency quantity? → FX revaluation;
(d) none of the above → candidate external deposit.

**When classification is ambiguous, ask — do not guess.** This determines whether the book
is judged to have grown, which flows directly into the top-up-vs-new-name threshold in §3.
Silently treating ambiguous cash as a deposit can trigger an unwarranted re-score; silently
treating a real deposit as something else leaves the user's capital idle indefinitely.

## 3. Top-up vs new-name — the load-bearing rule

**A deposit authorizes deploying capital. It never lowers the underwriting bar for adding a
name that has not been researched.** These are separate questions and this skill must never
let answering "yes" to the first stand in for the second.

- **Small deposit relative to NAV → top up existing underweight positions toward their
  existing targets.** Low bar, mechanical: the names are already underwritten, already
  hold a thesis and a target weight, and the deposit just closes the gap between held and
  target weight. No new research is required because no new claim is being made.

- **Large deposit — propose >20-25% of pre-deposit NAV as the threshold** — warrants a
  full re-score of targets, not a proportional top-up. Reasoning: at meaningfully larger
  NAV the *expressible* universe genuinely changes. Names that were previously unsizeable
  at a reasonable weight (lot-constrained Asian names, high-priced single shares — see
  `08-multi-currency.md` §2) may now clear the minimum-NAV bar. A proportional top-up at
  the old target weights ignores that the efficient frontier of what this book *can* hold
  has moved. The 20-25% figure mirrors the per-name cap-at-initiation band already locked
  in `SKILL.md` — *(Medium confidence: reasoned from the existing ceiling table, not a
  separately sourced constant; treat as a starting default, adjustable if the user's
  deposit cadence makes it impractical.)*

- **A brand-new name always requires the full BUILD underwriting bar** — universe screen,
  deep fundamentals, thesis, scoring, adversary pass — **regardless of deposit size.** A
  deposit is a capital event, not a research event. Reasoning: the two questions "do I have
  more cash to invest" and "is this specific company worth owning for 1-5 years" are
  independent, and conflating them is exactly how a book quietly drifts from "concentrated
  conviction" to "whatever was cheap to buy when cash arrived."

## 4. Expressibility gating at the new NAV

Before drafting any order, re-check which target weights are actually expressible at the
**post-deposit** NAV given whole-share and lot-size constraints. Use the minimum-NAV formula
in `08-multi-currency.md` §2 (`NAV_eur >= (L * price_major * fx_rate) / (w * epsilon)`) —
do not re-derive or duplicate it here; that file is the single source of truth for the
mechanics.

**Rule**: if a target weight is not expressible at the new NAV, say so explicitly and state
the minimum NAV that *would* express it. **Never silently distort the weight to fit** — not
by rounding to a lot that overshoots the tolerance band, not by dropping the name without
saying why, not by quietly picking a nearby weight. The user decides whether to add more
capital later, accept the distortion, or drop the name; the skill's job is to surface the
constraint, not resolve it silently.

## 5. The cash sleeve applies to the new total

A deposit is not 100% deployable. The policy cash sleeve (~2-10% of NAV, per `SKILL.md`'s
locked ceilings) is recomputed against the **new, post-deposit NAV** — not held constant in
EUR terms and not skipped because "it's just a top-up."

**The sleeve is a policy parameter, never a market-timing view.** A deposit arriving during
a market the agent "feels" is expensive does **not** justify holding back more than the
policy sleeve — reasoning that way is exactly the market-timing this skill forbids
elsewhere (`SKILL.md`, `06-agent-guardrails.md`). If the sleeve is currently above its
policy band for unrelated reasons (e.g. a recent large sale not yet redeployed), fix that
through the ordinary REVIEW-mode process, not by quietly widening the sleeve on a deposit.

## 6. Cost efficiency of deployment at small account sizes

Per-order minimum commissions and FX conversion spreads are close to fixed costs — they do
not scale down with order size, so they are proportionally brutal on small orders. *(All
fee figures below: verify at runtime via account settings / IBKR docs — never hardcode a
commission as fact; IBKR's fee schedule varies by tier, venue, and changes over time.)*

**Arithmetic for "is this order too small to place"**: if `commission_and_spread_cost /
order_value` exceeds a small threshold (order-of-magnitude: low-single-digit percent — this
is a sanity check, not a hardcoded limit), the order is uneconomic. A EUR 150 top-up
incurring a EUR 5-10 flat commission plus an FX spread is paying several percent in friction
before the position has moved at all — that is a worse cost drag than almost any drift
tolerance would justify walking past.

**Rule**: batch or skip rather than place an uneconomic order. If a deposit is small enough
that per-name top-ups would each be tiny, either accumulate it in the sleeve until the next
deposit or review cycle makes a batched order worthwhile, or concentrate it into the single
most-underweight name rather than splitting it thin across several.

**FX conversion should generally happen once per currency, not per order.** Convert EUR to
the needed foreign currency in one transaction sized for all orders in that currency this
session, then place the individual orders — this avoids paying the spread N times for N
orders that could have shared one conversion.

## 7. Anti-patterns

- **Treating a deposit as license to add an unresearched name.** Mechanism: the deposit
  answers "do I have capital," not "is this company worth owning" — skipping the BUILD
  underwriting bar (§3) lets capital availability substitute for conviction.
- **Deploying 100% of a deposit and ignoring the sleeve.** Mechanism: the sleeve is a
  standing policy against the *new* NAV (§5); deploying past it turns a policy buffer into
  a number that only ever shrinks, never resets.
- **Staging deployment out of a market view rather than a stated behavioral or structural
  reason.** Mechanism: DCA is a regret-minimization tool (§1); using it because "prices look
  high" launders a forecast as a process choice, and this skill forbids market-timing
  forecasts.
- **Letting a deposit trigger a full rebalance of positions that did not need trading.**
  Mechanism: a deposit funds top-ups toward *existing* targets or, above the large-deposit
  threshold, a re-score of targets (§3) — it is not a license to re-trade names that are
  already within tolerance of their current target, which would burn the turnover budget
  and transaction costs for no risk-adjusted benefit.
- **Classifying sale proceeds as new capital and double-counting them.** Mechanism: the
  plan that generated a sale already allocated its proceeds (§2); treating the resulting
  cash balance as a fresh deposit re-decides an allocation that was already made, and can
  inflate the apparent size of the book's deployable capital.

## 8. Concrete rules + confidence ratings

| Rule | Confidence |
|---|---|
| Lump-sum beats staged entry on expected return more often than not, historically | High — well-established direction |
| ~67% / 12-month-stagger figure, or any specific outperformance percentage | Medium — reported by secondary sources summarizing Vanguard's 2012 study; re-verify before quoting precisely to the user |
| DCA is a behavioral/regret-minimization tool, not a return-maximizing one | High — this is the correct framing, not a numeric claim |
| Default to lump-sum absent one of the four stated exceptions (§1) | High — directly follows from the above |
| External deposit vs accrual vs sale proceeds vs FX revaluation must be classified before deployment | High — structural, not probabilistic |
| Ambiguous classification → ask, don't guess | High — policy choice, not an empirical claim |
| Small deposit → mechanical top-up to existing targets | High — follows from existing underwriting already having been done |
| >20-25% of NAV → treat as large, re-score expressible universe | Medium — reasoned default anchored to the existing per-name cap band, not independently sourced |
| New name always needs full BUILD bar regardless of deposit size | High — structural firewall between capital and conviction |
| Expressibility must be re-checked at new NAV; never silently distort a weight | High — directly inherits `08-multi-currency.md`'s existing, sourced rule |
| Cash sleeve recomputes against new NAV; never a market-timing lever | High — directly inherits `SKILL.md`'s locked ceiling |
| Specific commission/FX fee figures | Not stated as fact — verify at runtime, every time |
| FX conversion once per currency, not per order | High — arithmetic identity (fewer conversions, less spread paid), not an empirical claim |
