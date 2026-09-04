# Portfolio Skill — DEPOSIT Mode Execution State Machine

You are executing the `portfolio` skill's DEPOSIT pipeline. Read this entire document before
starting. Assume you have NO context from `SKILL.md` — everything needed is here or in the
references this document tells you to load.

**What this mode is for**: new cash has arrived and the owner wants it deployed. Typically invoked
as "just deposited 7500, do what you need."

**The governing distinction, stated first because everything else depends on it:**

> A deposit authorizes **DEPLOYING** capital into the existing plan.
> It does **NOT** lower the underwriting bar for a name that has never been researched.

Collapsing those two turns a deposit into an impulse buy. New capital is a funding event, not a
research shortcut. A name that has not passed the full BUILD underwriting bar does not enter the
book because money showed up.

**MANDATORY — READ ENTIRE FILE** before any deployment decision:
[`references/10-cash-deployment.md`](references/10-cash-deployment.md).

---

## Prerequisites

1. `bash scripts/state.sh load` — **first, always**. Without restored state there is no prior
   snapshot to compare against, so a deposit cannot be distinguished from an FX move or a
   dividend, and the classification in Stage 1 is meaningless.
2. `node scripts/preflight.js` — must exit 0. A dead data source aborts the run.
3. Read `preferences.json` from the restored cache. **Do not re-ask anything it already answers**
   (autonomy level, jurisdiction, drawdown tolerance, exclusions, target name count, cash sleeve,
   deployment style). Load
   [`references/09-autonomy-and-communication.md`](references/09-autonomy-and-communication.md) for
   the staleness and contradiction rules.
4. If **no portfolio state exists at all**, this is not a deposit — it is an initial funding event.
   ABORT into BUILD mode at the new total NAV and say so plainly.

---

## Stage 1 — Classify the cash delta (~10s)

```bash
node scripts/classify-cash-delta.js --input=<snapshot.json>
```

Build the input from the restored `portfolio.json` snapshot plus a live read of
`get_account_balances` / `get_account_summary` / `get_account_positions`.

The script decomposes the total cash change into **FX revaluation**, **known events** (dividends,
sale proceeds, fees), **position changes**, and the **residual external-flow candidate**.

**Why this stage exists**: a cash balance moves for four different reasons and only one of them is
new capital. A EUR-base account holding USD cash sees its base-currency cash value move purely on
FX with nothing entering or leaving. A dividend increases cash without expanding the book's
funding. Sale proceeds are already accounted for in the existing plan — counting them as new
capital double-counts them and oversizes everything downstream.

Act on the classification:

| Classification | Action |
|---|---|
| `DEPOSIT`, confidence HIGH | Proceed to Stage 2 with the residual as the deployable amount |
| `WITHDRAWAL` | Do NOT deploy. Report the shortfall and whether any target is now unfundable. Route to REVIEW |
| `NO_EXTERNAL_FLOW` | No deposit occurred. Say so plainly and route to REVIEW — do not manufacture a deployment |
| `AMBIGUOUS` or `requires_user_confirmation: true` | **STOP and ask the owner to confirm the amount.** Never guess |

**If the owner stated an amount ("I put in 7500"), reconcile it against the computed residual.** A
material mismatch means either the transfer has not fully landed, fees were deducted, or an FX
conversion happened at the bank — surface the discrepancy with both figures rather than silently
preferring one. The owner's stated figure is a claim; the live balance is the fact.

**Any `unexplained_position_changes` must be surfaced loudly**, never absorbed into the residual —
that is a trade the skill did not record, and it means state and reality have diverged.

---

## Stage 2 — Expressibility check at the new NAV (~30s)

The book got bigger, so the set of reachable target weights changed. Recompute it.

Load [`references/08-multi-currency.md`](references/08-multi-currency.md) for the minimum-NAV
formula and lot-size constraints. For each existing and intended target:

- Is the target weight expressible at the new NAV given whole-share and lot-size constraints?
- Which previously-unreachable names are now reachable?
- Which are still not, and what NAV would they need?

**Report names that are still not expressible with the specific minimum NAV required.** Never
silently distort a weight to make it fit — that converts a sizing decision into an accident of
share price.

Consult `data/exchange-currency-map.json` for the suffix → currency → minor-unit divisor and
lot-size data. **Lot-constrained markets (Japanese round lots, Hong Kong board lots) are the most
common reason a target is unreachable at small NAV** — say so explicitly rather than quietly
dropping the name.

---

## Stage 3 — Route by deposit size (~instant)

| Deposit as % of pre-deposit NAV | Route | Why |
|---|---|---|
| Small (≲20-25%) | **Top-up path** — Stage 4 | The plan is still the plan; this is funding it further |
| Large (≳20-25%) | **Re-score path** — Stage 5 | The expressible universe genuinely changed; the old targets were shaped by a constraint that no longer binds |

The 20-25% threshold is a **reasoned default mirroring the per-name cap band, not an independently
sourced constant** — treat it as configurable and say so if it drives the routing.

Route on the honest reason, not on convenience. A deposit that materially changes what the book
*could* hold deserves a re-score; one that does not deserves a cheap top-up.

---

## Stage 4 — Top-up path (small deposit)

1. Compute current weights vs targets (`node scripts/compute-drift.js`).
2. Allocate the deployable cash to the **most underweight positions first**, moving them toward
   their **existing** targets. This is the mechanical, low-bar path — no thesis re-litigation.
3. **Do NOT initiate a new name on this path.** If the deposit seems to call for one, that is a
   Stage 5 decision at minimum and a full BUILD underwriting at maximum.
4. **Do NOT trigger a full rebalance.** Positions that did not need trading before the deposit do
   not need trading now — deploying new cash is not a reason to churn the rest of the book.
5. Proceed to Stage 6.

---

## Stage 5 — Re-score path (large deposit)

1. Load [`references/01-horizon-signals.md`](references/01-horizon-signals.md) and
   [`references/02-construction-sizing.md`](references/02-construction-sizing.md).
2. Re-score existing holdings' theses against current data — conviction tiers may have moved.
3. Re-run the cluster map. A bigger book can hold more names, which changes cluster concentration.
4. If a **new name** is warranted, it goes through the **full BUILD underwriting bar**: deep
   fundamentals, thesis with return decomposition and explicit ROIC fade, reverse-DCF
   falsification, and the adversary pass. Load
   [`references/06-agent-guardrails.md`](references/06-agent-guardrails.md) for the hard adversary
   protocol. **No shortcuts because the money is already sitting there.**
5. Recompute weights via `node scripts/compute-weights.js` — authoritative, never prose arithmetic.

---

## Stage 6 — Cash sleeve and deployment style

**Cash sleeve is recomputed against the NEW total NAV**, at the policy percentage from
`preferences.json`. The sleeve is a **policy parameter, never a market view**.

**Deployment style — default is LUMP-SUM.** Staged entry spends time out of the market and is a
regret-minimization tool, not a return-maximizing one. Stage ONLY for a stated reason from
`references/10-cash-deployment.md`: an oversized single position, genuine illiquidity, a disclosed
binary event, or the owner's own recorded preference.

**"The market feels expensive" is NOT a valid reason to stage.** That is market timing wearing a
prudent-looking coat, and this skill forbids it. If you find yourself reaching for it, the honest
statement is "no view on timing; deploying per policy."

Check order economics before drafting: an order small enough that commission is a large percentage
of the position is uneconomic — batch or skip it rather than place it. Convert FX **once per
currency**, not once per order.

---

## Stage 7 — IBKR handoff

**MANDATORY — READ ENTIRE FILE**:
[`references/05-ibkr-handoff.md`](references/05-ibkr-handoff.md).

1. Call `get_order_instructions` **before drafting anything** — skip or supersede any existing
   draft for the same contract. Blind-creating stacks duplicates the owner could submit twice.
2. Read existing positions and draft **deltas**, never absolute targets.
3. Run the **reconciliation gate** per contract: currency-normalized price cross-check, 2%
   tolerance. **HARD STOP on failure** — no averaging, no "closest line", no draft.
4. Create or update the watchlist, then draft one instruction per delta position.
5. Present the deep-links. **These are drafts. The owner reviews and submits in IBKR.** Never
   describe a drafted instruction as an executed trade.

---

## Stage 8 — Report, log, persist

Render via [`references/07-thesis-memo.md`](references/07-thesis-memo.md). Follow the communication
standard in `references/09-autonomy-and-communication.md`:

- **Lead with what was done and why**, then the evidence.
- Every figure carries its **unit and currency**.
- **Name the binding constraint** for each size ("8% because the cluster cap bound, not because
  conviction was low").
- **Report anything that failed or was skipped first** — an unfundable target, a failed
  reconciliation, an uneconomic order — before what went well.

Then:
1. Append to `decision-log.jsonl` — **append-only**; a resolution is a NEW entry referencing the
   original, never an edit.
2. Update `portfolio.json` with the new snapshot (this becomes the next run's prior snapshot — if
   you skip it, the next deposit cannot be classified).
3. `bash scripts/state.sh save` — **REQUIRED**, or the next run starts blind.
4. State the next scheduled review date.

---

## Failure-Mode Table

| Failure | Detection | Response |
|---|---|---|
| No prior state to compare | `state.sh load` found no branch | If no book exists → BUILD. If book exists but state lost → STOP; reconstructing a snapshot from memory is look-ahead contamination |
| Classification `AMBIGUOUS` | Script output | STOP and ask. This decides whether the book grows — a guess mis-sizes everything |
| Owner's stated amount ≠ computed residual | Stage 1 reconcile | Surface BOTH figures. Do not silently prefer either. Likely partial settlement, bank FX, or fees |
| Unexplained position change | Script `unexplained_position_changes` | Surface loudly. State and reality have diverged; do not deploy until reconciled |
| Missing FX rate for a held currency | Script errors | Fix the input — a missing rate silently treated as 1.0 is a known real-bug class here |
| Target still unexpressible at new NAV | Stage 2 | Report the specific minimum NAV needed. Never distort the weight to fit |
| Deposit would breach a cluster or per-name cap | `compute-weights.js` errors | The script errors rather than clamping. Re-allocate to other targets or hold in the sleeve |
| Reconciliation gate fails | Stage 7 | HARD STOP for that name. Surface both prices, both currencies, both identifiers |
| Order too small to be economic | Stage 6 | Batch or skip; report which and why |
| `state.sh save` push fails | Save reports failure | Surface loudly — the next run will start blind and the deposit will look like it never happened |

---

## What this mode must NEVER do

- **Never initiate an unresearched name** because cash arrived.
- **Never treat dividends, sale proceeds, or FX revaluation as new capital.**
- **Never deploy on an AMBIGUOUS classification.**
- **Never stage deployment because the market "feels expensive."**
- **Never trigger a full rebalance** of positions that did not need trading.
- **Never silently distort a target weight** to make it expressible.
- **Never draft when the reconciliation gate failed.**
- **Never skip the state save** — an unrecorded deposit corrupts every future classification.
