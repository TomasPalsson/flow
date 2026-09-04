---
name: portfolio-multi-currency
description: The weight-to-shares algorithm for non-base-currency positions, minor-unit (GBp) normalization ordering, lot-size constraints, local-vs-FX return attribution, and drift with mixed-currency cash. MANDATORY load when computing share quantities or attributing returns. Do NOT load for scoring or thesis stages.
---

# Multi-Currency Mechanics (EUR-Base Account)

## 1. The weight → shares algorithm

**Inputs**: target weight `w`; `NAV_eur`; `quote.currency` (the
**trading** currency — never `financialData.financialCurrency`, which
describes the company's reporting currency, not what the position
trades/settles in); `price_native`; a freshly fetched
`fx_rate(EUR -> major_local)`; venue lot size (§2).

1. `target_value_eur = w * NAV_eur`.
2. Read `quote.currency`; discard `financialCurrency` for sizing.
3. **Normalize minor-unit currencies before any FX step.** GBp/GBX
   (pence) and ZAc (SA cents) are the two realistically encountered:
   divide `price_native` by 100, relabel to the major ISO code
   (GBp→GBP, ZAc→ZAR) → `price_major`. Already-major codes pass
   through unchanged.
4. Fetch `fx_rate(EUR -> major_local)` using the **post-normalization**
   code — FX providers quote major-unit-to-major-unit only; no
   provider publishes a "pence exchange rate."
5. `target_value_local = target_value_eur * fx_rate(EUR -> major_local)`.
6. `raw_shares = target_value_local / price_major`.
7. Apply rounding + lot constraints (§2) → integer quantity `N`.
8. **Before sending the order**, re-derive the limit price in whatever
   unit IBKR itself expects — not guaranteed to equal `price_major`
   (§1.3).

**Why /100 must precede FX**: fetching the FX rate first forces a
choice between mislabeling pence as pounds (100x too large) or
inventing a rate no provider publishes. Normalizing first puts price,
FX rate, and target value in the one space FX rates exist in.

**The silent-failure shape**: both the mislabeled and correctly
normalized paths yield a plausible positive share count — no exception
fires, the order places at ~100x the wrong size. Treat "is this a
minor-unit code?" as a mandatory branch checked *before* any FX math.

**Worked — GBp (Shell, SHEL.L)**: `price_native = 3383.5` GBp →
`price_major = 33.835` GBP. `w=12%`, `NAV_eur=50,000` →
`target_value_eur=6,000`. `fx_rate(EUR→GBP)=0.8600` *(illustrative —
verify at runtime)* → `target_value_local=5,160` GBP →
`raw_shares=152.5` → floor, no lot constraint → **N=152**.
*Counterfactual (skip step 3)*: 3383.5 treated as GBP →
`raw_shares=1.5` → 1-2 shares, ~100x undersized, executes cleanly,
nothing flags it.

**Worked — JPY (Toyota, 7203.T)**: `price_native=2,950` JPY (no minor
unit, `price_major=2,950`). `w=10%`, `NAV_eur=50,000` →
`target_value_eur=5,000`. `fx_rate(EUR→JPY)=163.50` *(illustrative)* →
`target_value_local=817,500` → `raw_shares=277.1`. TSE round lot=100
(§2) → floor to lot → **N=200**, not 277 — a ~28% cut, far larger than
ordinary rounding.

### 1.3 Unresolved: IBKR's GBp order-price convention

IBKR's MCP exposes no currency field, so it is **not verified** whether
`get_price_snapshot`/`limit_price` for LSE contracts match Yahoo's
pence convention or use pounds. Do not guess. **Runtime cross-check,
every GBp-class order**: pull `get_price_snapshot`, compare to Yahoo's
`price_native`. Within ~1-2% → IBKR quotes in pence, pass `limit_price`
in pence. ~100x smaller → IBKR is already in pounds, pass
`price_major`. Share-count math (steps 1-7) is always in major units
regardless; only the order's `limit_price` unit is in question.

## 2. Rounding and minimum expressible position

Flooring `raw_shares` (never ceiling) makes achieved weight
systematically `<=` target. Across a 5-10 name book this compounds
into a growing unintended cash residual, quietly cutting equity beta
below what target weights imply across successive rebalances.

**Max single-name distortion**: `max_weight_error = V_eur / NAV_eur`
(`V_eur` = one share's EUR value). A ~1,700 EUR single-share name
(Booking, NVR, Berkshire A) in a 20,000 EUR account is 8.5% of NAV —
0% or 8.5%, no 6% in between.

**Minimum account size** for weight `w` within tolerance `epsilon`:
`NAV_eur >= V_eur / (w * epsilon)`. Lot-constrained market: `V_eur`
becomes one lot's value — `NAV_eur >= (L * price_major * fx_rate) /
(w * epsilon)`. Lot size multiplies directly into the required minimum
account size.

**Lot sizes**: Japan (TSE) — typically **100 shares** *(Medium
confidence, verify at runtime)*. Hong Kong (HKEX) — set **per stock**,
100 to several thousand; **not hard-codable even approximately** — look
up per contract at runtime. US/EU/UK and most developed markets —
effectively lot size 1 for liquid large/mid-caps; do not generalize
this to Asian exchanges.

**When a target weight isn't expressible** (`L * V_eur / NAV_eur >
w * (1+tolerance)`):

1. **Default: drop the name** — a lumpy oversized lot distorts the
   book's risk budget more than its diversification benefit is worth.
2. **Exception**: round up to one lot if overshoot is modest (~20-25%
   relative) — accept, flag explicitly as *rounding-driven overweight*,
   never conviction-driven.
3. **Escape hatch**: check for a US ADR (single share, no board-lot)
   before dropping — same exposure, expressible sizing.
4. **Never silently ceiling** — an unflagged lot-driven overweight is
   indistinguishable from a real active bet on the next review.

## 3. Local vs FX return attribution

`r_local = P1/P0 - 1` (major-unit prices; /100 cancels in a ratio —
irrelevant here, matters only for sizing). `r_fx = FX1/FX0 - 1`. Exact:
`r_eur = (1+r_local)(1+r_fx) - 1`. Weekly-window additive approximation
`r_eur ≈ r_local + r_fx` is fine for commentary (error = `r_local *
r_fx`, sub-bps weekly); use the exact form for anything summed across
periods, since the additive error compounds. Compute both legs from
`quote.currency` prices; `financialCurrency` is irrelevant here too.

**Weekly-review rules — load-bearing:**

1. **An FX-driven drawdown is not a thesis break.** `r_eur<0` with
   `r_local>=0` (or mildly negative), `r_fx` explaining most of the
   loss → log, do not trim/stop/re-underwrite. Escalate only if it
   persists several consecutive windows (rule 4).
2. **An FX-driven gain is not a win.** `r_eur>0` with `r_local` flat or
   negative → does not build conviction, is not a profit-taking signal.
3. Only `r_local` drives thesis-linked decisions. Only aggregate `r_fx`
   drives currency-exposure/hedging review (§5) — never a single-name
   verdict.
4. **Several same-currency names moving together in one window is ONE
   macro event, not N signals.** Attribute once, portfolio-level.
   Persisting 4+ consecutive weekly windows with no reversion →
   escalate to §5.
5. Report both legs always — suppressing FX invites misreading `r_eur`
   as pure thesis performance next week too.

### 3.1 Drift-cause classifier thresholds (`compute-drift.js`)

The script implementing the decomposition above also assigns each name one of four mutually
exclusive **drift-cause** labels (`fx-driven` / `winner-appreciation` / `underperformance` /
`denominator-shrinkage`) so a reviewer never has to eyeball raw numbers to answer "why did this
drift." The four category names are this package's own (§3 rules 1-4 above;
`references/03-review-doctrine.md`), but the exact numeric boundary between them is set by four
constants defined in the script:

| Constant | Default | What it gates |
|---|---|---|
| `MEANINGFUL_LOCAL_RETURN_PCT` | 5% | `r_local` must exceed this to count as a genuine winner-appreciation/underperformance signal rather than noise |
| `FX_DOMINANCE_RATIO` | 1.5x | `\|r_fx\|` must exceed this multiple of `\|r_local\|` ... |
| `FX_MATERIALITY_PCT` | 2% | ... AND itself clear this floor, before a move is labeled `fx-driven` |
| `COMOVEMENT_MIN_FX_RETURN_PCT` | 1% | floor for a name's FX leg to count toward the same-currency co-movement detector (rule 4 above) |

**This package's own extrapolation, not literature-derived.** No study or source cited anywhere
in this skill specifies where "meaningfully local" or "FX-dominant" begins numerically — only
that the four categories themselves are a useful distinction. These thresholds were synthesized
to make that distinction computable, not measured from realized return data or drawn from any
external source. Treat them as reasoned, tunable defaults — override via the script's input JSON
if a name's volatility profile makes 5% / 1.5x / 2% / 1% obviously wrong for it — never as
calibrated constants with the standing of the reconciliation tolerance or the hard drift bands,
which do trace to an explicit source. *[Low confidence — internally reasoned default, not
empirically validated]*

## 4. Drift with mixed currencies and cash

1. **Fix one snapshot time `T`** for the whole run — every price and FX
   rate pulled in the same pass.
2. Per equity `i`: `value_eur_i = N_i * price_major_i *
   fx_rate(local_i -> EUR)`, all as of `T`.
3. Per cash sleeve currency `j` (incl. un-swept dividends, floor-round
   residue): `value_eur_j` as of `T` (rate trivially 1 for EUR).
4. `NAV_eur_computed = sum(value_eur_i) + sum(value_eur_j)`.
5. **Reconcile against IBKR's own reported base-currency NAV**
   (`NetLiquidation` via `get_account_summary`/`get_account_balances`)
   — IBKR reports this correctly at account level despite no
   per-contract currency field. Divergence beyond ~0.5% is a
   **data-quality flag** — don't trust this run's drift until resolved.
   The single most reliable integrity check available, since it doesn't
   depend on the per-contract currency inference this file otherwise
   relies on.
6. `weight_i = value_eur_i / NAV_eur_reported`; `drift_i = weight_i -
   target_weight_i`; `cash_weight = sum(value_eur_j) /
   NAV_eur_reported`, tracked as its own line, never folded into
   residual.

**Stale-FX-vs-fresh-price trap**: refreshing prices every review but
caching FX mixes a real market move with a stale conversion factor —
produces apparent drift indistinguishable from genuine drift, no
automatic flag. Mitigate by fetching price and FX together per
position per run, logging each rate's timestamp.

**Non-base cash drifts purely on FX**: floor-rounded residue, un-swept
dividends, partial fills are themselves unhedged exposure — EUR value
moves daily with no trade occurring. Track each currency sleeve
separately (can move opposite directions); never read a moving
`cash_weight` as a deliberate cash call without checking FX-translation
vs. actual buy/sell. An un-swept USD dividend sitting three weeks is a
live FX bet the review should surface, not a risk-free "cash" line.

## 5. FX hedging recommendation

Equity FX exposure is **partly self-hedging**: a weaker local currency
often makes an exporter more competitive, offsetting translation loss
— directionally well-documented (Vanguard, MSCI), magnitude
period-dependent *[Medium confidence]*. **Listing currency is a poor
proxy for true economic exposure** — `quote.currency` says where a
stock trades, not where the business earns/spends. Canonical case: a
CHF-listed multinational (Nestlé/Roche/Novartis profile) earning mostly
USD/EUR; hedging "the CHF exposure" hedges a currency the business
barely touches while leaving real exposure untouched, and could add a
net-new uncompensated CHF bet. True economic exposure needs
revenue-geography data this skill doesn't have *[High confidence,
qualitative]*.

Hedge cost/benefit is set by covered interest rate parity — the
short-rate differential between the two currencies, paid or earned as
carry, not a flat fee — direction and magnitude **verify at runtime**,
never hard-coded. Rolling forwards also carry real operational burden
(periodic rolls, spread cost each time) heavier than this skill's
weekly cadence.

**Default: no mechanical FX hedging overlay.** Manage currency risk
through position construction — track concentration by `quote.currency`
alongside by-name weights every review; if one currency exceeds ~60-70%
of NAV with no conviction driving it, treat as a diversification gap to
close via name selection, not a signal to hedge. Matters more here than
in standard advice: an 8-of-10-USD book hides a large single-factor
currency bet inside what looks like name diversification (§3 rule 4).
Reconsider hedging only with a shortening horizon, a EUR liability to
match, or an explicit high-conviction currency view independent of the
equity thesis (then size/review it as a deliberate macro trade, not
hygiene) *[Medium confidence — mainstream practitioner consensus for
equities generally]*.

## 6. Cost and dividend layer

**Three funding mechanisms**: (1) **Auto-conversion** — IBKR converts
EUR to local currency during order execution; least effort, but the
effective rate is opaque unless surfaced and typically embeds a spread
— *mechanics/spread: verify at runtime*. (2) **Explicit FX order** —
convert EUR→local first, confirm fill/rate, fund the equity order from
the resulting balance; full visibility, feeds §3 accurately, costs
two-leg sequencing (confirm FX filled before the equity leg).
(3) **Margin borrow of the foreign currency** — defers, doesn't
eliminate, FX exposure (the negative balance moves with FX) and adds
borrow interest plus margin-call risk; avoid by default.

**Recommended default: explicit, controlled FX conversion immediately
ahead of the equity order** — rate known, logged, feeds §3 accurately,
never silently introduces margin leverage. *Order types/parameters
against IBKR MCP tools: verify at runtime.*

Dividends pay in local trading currency, net of source-country
withholding deducted before credit. **Withholding rate depends on the
treaty between the dividend's source country and the investor's tax
residency** (not broker domicile, not account base currency) — varies
by pair, changes with treaty updates. **Never hard-code a withholding
rate — verify at runtime / confirm investor residency every time it
matters.** Unless auto-swept, net dividends sit as local-currency cash
(§4's trap): received today, converted three weeks later, carries its
own FX leg on top of the withholding haircut. Track dividend cash by
currency from receipt, not folded into aggregate cash until converted.

Commission schedules, FX spreads, and margin borrow rates are all
**broker pricing conventions that change over time** — none stated as
fact anywhere in this file. Resolve each via the relevant IBKR tool (or
current published rates) at the moment it's needed, never from training
data or this document.

## 7. Concrete rules + confidence

**Certain — arithmetic/definitional:**

| Rule | Confidence |
|---|---|
| Weight→shares algorithm structure (§1) is internally consistent | High |
| GBp/ZAc normalization must precede FX conversion | High |
| `r_eur = (1+r_local)(1+r_fx)-1` is exact by construction | High |
| Whole-share flooring is a systematic negative bias vs. target | High |
| `max_weight_error` and min-account-size formulas (§2) | High |
| Reconciling computed vs. IBKR-reported NAV is a valid integrity check | High |

**Market convention — verify before relying on the exact figure:**

| Rule | Confidence |
|---|---|
| GBp/pence London convention; trading≠reporting currency on ~24% of tested names | High (per verified context) |
| Japanese round lot typically 100 shares | Medium — verify at runtime |
| Hong Kong board lots per-stock, 100-5,000+ | Medium-High on pattern; Low on any figure — look up per contract |
| IBKR's GBp price/order convention matching Yahoo's | **Low — explicitly unverified**; §1.3's cross-check exists because of this gap |
| Auto-conversion spread, commissions, margin borrow rate | Low / unverified by design |
| Dividend withholding by country pair | Low / investor-specific |

**Judgment / practitioner consensus:**

| Rule | Confidence |
|---|---|
| Equity FX exposure is partly self-hedging | Medium |
| Listing currency is a poor proxy for true economic exposure | High qualitative; quantifying needs data this skill lacks |
| Default to no mechanical hedge, manage via diversification | Medium — this book's concentration is a reason to revisit if currency concentration proves high |
| Explicit FX conversion preferred over auto-conversion/margin | Medium — reasoned, not a measured cost comparison |

**Hard rules to encode**: never read `financialCurrency` for sizing;
always floor `raw_shares`; fetch price+FX together at one snapshot;
convert `target_value_eur` to local once, not price-per-share
back-and-forth; cross-check IBKR vs. Yahoo before every GBp-class
order; drop a name by default when unexpressible, flag any accepted
lumpy overweight as rounding-driven; report `r_local`/`r_fx` separately
every review; reconcile NAV every review and block on mismatch; track
non-EUR cash sleeves separately; default to no hedge, surface
concentration instead; default to explicit logged FX conversion, never
silent margin borrowing.
