# Portfolio REVIEW — Execution State Machine

You are executing the REVIEW pipeline of the `portfolio` skill: the recurring check-up run against a
concentrated 5-10 name global equity book held for **1-5 years**. The user runs this **weekly**. If
you have not already loaded [`references/03-review-doctrine.md`](references/03-review-doctrine.md),
load it now — it is the governing doctrine this state machine implements and every gate below cites.

## The governing constraint — read this twice

**The holding period is 1-5 years. The invocation cadence is weekly (~52 times/year). That mismatch
is the entire design problem.** A process asked "does anything need to happen?" 52 times a year
**will manufacture reasons to act**, even when the evidence-based answer is no — a controlled
experimental finding (Gneezy & Potters 1997), corroborated by the portfolio-math finding that
higher-frequency rebalancing beats nothing but cost. The fix is not to look less often. It is to
structurally forbid frequent looking from producing frequent deciding.

**The default and expected output of this pipeline is "no action, logged."** An empty weekly pass is
the pipeline functioning correctly, not a failure to find work. Every stage below asks one question
only: **"Has a pre-committed trigger fired?"** — never *"what should I do?"*, because that question
always finds an answer; there is always *some* number that moved or *some* headline that could be
read as significant. **An agent that finds something to do most weeks is malfunctioning, not
diligent.** Hold that standard through every stage below.

## Stage 0 — State restore and cadence routing

```bash
bash scripts/state.sh load
```

Run this **first, before anything else**. A scheduled weekly run starts in a fresh container with no
memory of prior runs — without a successful load there is no portfolio, no drift history, no
last-review-date, and the review has nothing to review. An IBKR positions fetch is not a substitute:
state carries the decision log and cadence clock positions alone cannot reconstruct.

Also load [`references/09-autonomy-and-communication.md`](references/09-autonomy-and-communication.md)
in full now, and read `preferences.json` from the state just restored. Every REVIEW run produces
output — at minimum the weekly "no action, logged" line — so Part 3's communication standard applies
to this run regardless of cadence, and Part 2's rule applies too: **do not re-ask anything
`preferences.json` already answers**; re-confirm only a field that is stale (`last_confirmed` >12
months) or that this run's findings directly contradict.

Determine cadence from days since the last **full re-score** (in state, not merely last run):

| Days since last full re-score | Cadence |
|---|---|
| < 28 | Weekly (hazard-scan only) |
| 28-88 | Monthly |
| 89-364 | Quarterly |
| ≥ 365 | Annual |

An explicit user argument (`--cadence=`) always overrides the detected value. **State the detected
cadence to the user before proceeding to Stage 1** — silent cadence selection is how a monthly
scope check quietly turns into an undisclosed trading window.

## Stage 1 — Position and price refresh (all cadences)

Read current IBKR positions, refresh prices with `node scripts/fetch-global-quote.js`.
**Currency-normalize before any arithmetic** — minor-unit and reporting-vs-trading-currency traps
are live money-losers, see `references/04-global-data.md` for non-US names. Only once normalized,
run `node scripts/compute-drift.js`, which **must decompose drift into local-price-driven and
FX-driven components** — never emit a single blended number; Stage 4 depends on this decomposition.

Reconcile the computed NAV against IBKR's own reported base-currency NAV. This is the **NAV**
reconciliation tolerance — a portfolio-level integrity check, distinct from the per-contract
**price** reconciliation tolerance in Stage 7 below (that one genuinely is a flat 2%). A mismatch
beyond the **~0.5% default tolerance** (configurable per-run, up to a hard 2% ceiling `compute-drift.js`
refuses to exceed — see `references/08-multi-currency.md` §4 and the script's
`nav_reconciliation_tolerance_pct` input) means stale FX, a missed position, or a bad price —
**fail loud and stop**, do not proceed to Stage 2 on an unreconciled book. A half-blind hazard scan
is worse than no scan.

## Stage 2 — Hazard scan (ALL cadences — this is the entire weekly pass)

Check **only** pre-committed triggers, nothing else: **hard drift bands** (~1.75-2x target weight
above, ~0.3-0.4x below — reasoned defaults, not literature-validated for single-stock books, state
them as such, configurable, not sacred); the **named event-interrupt list** (going-concern
qualification, credible fraud discovery, M&A affecting a held name, dividend cut/suspension, index
deletion **for cause** — not routine reconstitution — catastrophic guidance revision contradicting a
stated thesis pillar); **idle cash beyond ~5%** of portfolio value sustained past one monthly cycle;
and **cooldown / minimum-holding-period status** per name, so later stages never propose an action a
name is structurally ineligible for.

**Allowed outputs at weekly cadence, and only these**: "no action, logged"; a mechanical hard-band
trim; flag-for-review; idle-cash escalation.

**Hard gate — check before emitting any recommendation, every run**: originating a new position,
executing a full exit, or making a discretionary add is **explicitly forbidden** at weekly cadence,
on the pipeline's own authority, no exception. If the scan surfaces something that looks like it
warrants one of those three, the correct output is a **flag**, not the action — carry it to the
cadence that has authority (quarterly, for anything short of a mechanical hard-band trim).

## Stage 3 — Materiality filter on any fired interrupt

An interrupt firing is not the same as an interrupt being material. Every fired trigger from Stage 2
must clear a materiality check before it escalates, or the interrupt channel becomes a second
weekly-churn vector alongside the drift channel — defeating the point of separating clocks.

**Most interrupts flag for review; they do not fire a trade.** Only a mechanical hard-band breach or
a pre-committed user stop rule justifies near-automatic action. Fraud, going-concern, M&A, and
guidance shocks require a judgment call about magnitude and durability that this pass should
**surface**, never **resolve unilaterally**.

Worked example — dividend cut: a headline "dividend cut" fires the named-event list. Before
escalating, distinguish a genuine cut to the ongoing regular dividend (material — flag, do not
auto-act) from a **special-dividend base effect**: last year's payout included a one-off special
dividend, this year's regular dividend is flat or higher, and the trailing comparison is
arithmetically manufacturing a "cut" that never happened. The second case is filtered here and never
reaches the user.

## Stage 4 — FX vs. thesis discrimination (before any reaction is formed)

Using the Stage 1 local/FX decomposition, before any recommendation is formed: an **FX-driven
drawdown is not a thesis break** and must never trigger a sell; an **FX-driven gain is not a win**
and must never be cited as thesis validation; **same-currency co-movement across several held names
is one macro event, not N independent signals** — five names moving together on a shared currency
move is one data point, not five confirmations of a pattern. If Stage 2 or 3 surfaced something this
gate reclassifies as FX noise, downgrade it to "no action, logged" and note the reclassification.

## Stage 5 — Cadence-specific work (skip entirely at weekly)

**MONTHLY**: soft-band check, ~20% relative to target weight — anchored to a study of diversified
multi-asset sleeves, not single stocks, so treat it as a floor for looseness that keeps watching,
never a trade trigger on its own. Light thesis scan for anything too material to wait for the
quarterly cycle. May schedule an **early full review for exactly one specific name**; may not
rebalance, add, exit, or re-score the whole book.

**QUARTERLY** (align to earnings where possible) — **the only routine trading window**: full thesis
re-score per name (load [`references/01-horizon-signals.md`](references/01-horizon-signals.md)
first — never re-derive signal direction from memory); valuation refresh and reverse-DCF re-run;
tax-lot review; formal rebalance-to-band decision. Load
[`references/02-construction-sizing.md`](references/02-construction-sizing.md) before resizing any
position — sizing is a deterministic script call (`compute-weights.js`), never prose arithmetic.
Full menu available here: trim, add, exit, flag a new candidate for the next BUILD cycle.
Originating a brand-new position outright stays out of scope even here — flag only, hand to BUILD.

**ANNUAL**: position count and concentration check, plus a **process retrospective** — realized
turnover vs. the ~20-40%/yr budget, which theses played out and which didn't, **process graded
separately from outcome**. A disciplined loser (thesis correctly falsified, exited on the
pre-registered condition) and a sloppy winner (right for the wrong reason, no falsifiable thesis
ever written) are not the same trade and must not be scored the same.

## Stage 6 — Asymmetric evidence bar enforcement

Before emitting **any** action — from any stage above — check it against the ladder. The bar rises
with how expensive the action is to reverse:

| Action | Bar |
|---|---|
| Hold | Zero evidence — the default null hypothesis the process must affirmatively reject |
| Mechanical trim, hard-band breach | Lowest — no judgment call, the only category safe for weekly-cadence unilateral execution |
| Discretionary add | Requires a **dated** thesis re-affirmation from the last quarterly review |
| New position | Full BUILD-mode underwriting bar — a review may only **flag**, never originate |
| Full exit | Highest — a written, dated statement of *which specific thesis pillar broke* and *why the break is durable, not transient*. "Price is down" is never sufficient on its own |

**A proposed action that fails its bar is downgraded to a flag, not emitted.** This is the mechanism
that makes the rest of the doctrine enforceable, not aspirational — apply it as the last check
before output, every time, even to actions that survived every earlier stage.

## Stage 7 — Execution (only if an action cleared its bar in Stage 6)

Load [`references/05-ibkr-handoff.md`](references/05-ibkr-handoff.md) before touching IBKR.

The reconciliation gate applies to **every** contract before any draft instruction — match by
company name and exchange, never bare ticker; reject the match on >2% price divergence against an
independent source. On failure: hard stop, surface both prices, require a corrected match or human
confirmation. Never pick the closer line, never average.

**Before drafting, check for an existing DRAFT on the same contract.** Call
`get_order_instructions` and filter to the contract being resized; skip (delta unchanged) or
`delete_order_instruction` and redraft (delta changed) rather than creating a second instruction —
never blind-create. A quarterly REVIEW that re-drafts the same delta without this check silently
stacks duplicate drafts across review cycles; the user reviewing IBKR's draft list has no signal
it isn't the first copy and could submit the same trade twice.

Draft **deltas against current IBKR positions**, never absolute targets — read existing positions
first, or the pipeline double-buys holdings already owned. **Drafts only** — nothing here submits a
live order.

## Stage 8 — Output, log, persist

Render output via [`references/07-thesis-memo.md`](references/07-thesis-memo.md). For a quiet
weekly pass — the expected case — use the **minimal no-action template**. Do not pad a null result
with restated theses or manufactured color to look busy: padding creates pressure to eventually
justify itself with an action, exactly the failure mode this pipeline exists to prevent.

Follow the communication standard in
[`references/09-autonomy-and-communication.md`](references/09-autonomy-and-communication.md) Part 3
for every output this stage renders, **including the terse weekly no-action report** — terse and
unexplained are different things. Any figure still carries its unit and currency, a fired-but-immaterial
trigger still gets its binding constraint named, and a failed gate or flagged item leads the report,
never buried under what went well.

Then, in order: (1) append the run to the **append-only** decision log — cadence, inputs checked,
triggers fired, materiality outcome, action taken or "no action, logged"; (2) `bash scripts/state.sh
save` — **required**, or next week starts blind, with no memory this week happened; (3) state the
next scheduled review date to the user.

## Sycophancy guard

This mode reads the user's actual holdings **before** analyzing them — the implicit-context form of
bias most likely to skew analysis toward validating what is already owned. Counter it explicitly:
score each thesis, at every cadence that re-scores one, **as if the position were not already
held**. Ask "would this pass the BUILD-mode bar today, from zero?" — not "has anything gotten bad
enough to abandon a position I already committed to?" Only the first question is unbiased.

## Failure-mode table

| Failure | Detection | Response |
|---|---|---|
| `state.sh load` fails | First run (no state expected) vs. real failure (state existed last week) — distinguish | First run: route to BUILD. Real failure: **hard stop**, surface the error, never fabricate a baseline |
| NAV reconciliation mismatch | Computed NAV vs. IBKR-reported NAV diverge beyond tolerance | Hard stop before Stage 2 — never hazard-scan an unreconciled book |
| Position in IBKR, absent from state | Cross-check on load | Flag as out-of-band (manual trade / corporate action); never silently absorb into targets |
| Position in state, absent from IBKR | Cross-check on load | Flag as an outside-pipeline exit; never assume intent, surface for confirmation |
| Reconciliation gate failure (Stage 7) | >2% price divergence on contract match | Hard stop, surface both listings, require human confirmation. Never draft |
| Stale FX | FX timestamp older than price timestamp, or a silently cached fetch | Fail loud rather than compute drift on mismatched-vintage prices |
| Name delisted or acquired | Price fetch returns no data / a corporate-action flag for a held ticker | Route through Stage 3 as an automatic event-interrupt; never silently drop from state |
| Empty API response | Fetch returns empty/null where a value was expected | **UNKNOWN is not PASS** — flag the data gap itself, never read it as "no red flags" |

**Close every run, every cadence, with the same discipline**: state what was checked, what fired,
what cleared its evidence bar — and if nothing did, say so plainly, log it, save state, and give the
next review date. That is a complete and successful weekly pass.
