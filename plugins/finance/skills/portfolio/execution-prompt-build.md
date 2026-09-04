# Portfolio Skill — BUILD-Mode Execution State Machine

You are executing the `portfolio` skill's BUILD pipeline: constructing a concentrated 5-10 name
global equity portfolio (US + EU/UK/APAC) for a 1-5 year hold, ending in a watchlist and draft
order instructions for Interactive Brokers. Read this entire document before starting — it is
written to be followed with no other context loaded. Where it says "load `references/0N-*.md`",
that file carries the reasoning; load it, don't proceed on a guess at its content.

BUILD runs rarely: first construction, or a deliberate, user-confirmed rebuild. Any other
invocation should have routed to REVIEW. If you are not certain you're in BUILD mode, re-run mode
detection before touching Stage 1.

## Prerequisites — verify before Stage 1

1. **Load `references/09-autonomy-and-communication.md` and read `preferences.json`** from the
   state already restored by `state.sh load` (Prerequisite #3). Apply Part 2's rules before doing
   anything else: **missing** → this is the one full elicitation this skill ever runs unprompted;
   **stale** (`last_confirmed` >12 months) → one compact re-confirmation, not a full re-ask;
   **contradicted** by anything this run finds → surface just that field. **Do not re-ask anything
   `preferences.json` already answers.**
2. **User context elicited, deferring to `preferences.json` first.** The user must have, on record
   this run — either freshly stated or already answered in `preferences.json` per Prerequisite #1 —
   capital scale, base currency, drawdown tolerance, horizon confirmation (1-5yr, not a trading
   system), jurisdiction (tax rules are NOT universal), and sector/region exclusions. **If any of
   these six is still missing after checking `preferences.json`, STOP and ask for exactly that
   item — never the full six-item battery when preferences already answers some of them.** A
   guessed jurisdiction or capital scale silently corrupts every downstream weight.
3. **State restored** — `bash scripts/state.sh load` has run this session before anything else.
4. **Preflight passed** — `node scripts/preflight.js` reported Node ≥18, `yahoo-finance2`
   resolvable, IBKR reachable. A dead data source aborts with the exact fix printed; never run
   half-blind — a silently degraded data layer produces confident garbage.
5. **FinancialFilings is opportunistic, never required.** It has 403'd on every data endpoint in
   every session observed (account-linkage issue). On any 403, fall through silently to Yahoo-only
   — never surface it as a blocker.
6. **Live capital cross-check, before the stated capital scale becomes `nav_base`.** Call
   `get_account_balances` and/or `get_account_summary` and compare the live reported NAV against
   the capital figure the user stated in Prerequisites #2. Read the account's **base currency**
   from this same call too — never assume it matches what the user stated. **On a discrepancy
   beyond ~5%, STOP and reconcile with the user before proceeding to Stage 1.** Every downstream
   weight, floor, cap, and share count is sized off `nav_base` — a silently wrong NAV silently
   mis-sizes every position in the book.

## Stage 0 — Mode guard (~instant)

Before any research call, check for existing portfolio state (already surfaced by `state.sh load`
in Prerequisites #3 — read that output, don't re-fetch).

- **State present** → **ABORT into REVIEW mode.** Do not continue this document. Silently
  rebuilding an existing book is the most destructive failure this skill can commit.
- **State present AND the user has explicitly asked to rebuild** (not "run the portfolio skill" or
  "check on my portfolio" — an unambiguous rebuild request) → restate in plain language what gets
  discarded ("this replaces the current N-name book and its decision log — confirm?") and require
  an explicit affirmative before continuing.
- **No state file** → proceed to Stage 1. The only silent path.

## Stage 1 — Context and universe (~60-90s)

Elicit-and-confirm first (Prerequisites #2) — no fetch before all six context items are on record.
Restate them in one line; get an explicit go / correct-me.

Then assemble the candidate universe. **It is global by construction** — US and EU/UK together, not
US-plus-afterthought — so region and the Yahoo suffix convention (`.L`, `.DE`, `.PA`, `.AS`, `.MC`,
`.SW`, `.ST`, `.OL`, `.CO`, …) matter from the first fetch. **Do not hand-assemble this list from
memory or recall** — a remembered set of "the well-known names" is exactly the unmeasured selection
bias this stage exists to avoid. Fetch it instead:

```bash
node scripts/fetch-universe.js --region=us,eu
```

This scrapes S&P 500 (US) plus FTSE 100, DAX, CAC 40, AEX, IBEX 35, SMI, OMX Stockholm 30, OMX
Copenhagen 25, and OBX Index (Europe) constituent lists, resolves every ticker to a Yahoo-suffixed
symbol via `data/exchange-currency-map.json`, and reports per-source counts against a sanity floor —
a source that scraped near-empty is a named `ERROR` in the output, never a silently short list.
**APAC is deliberately not covered** (see the script's header — Japanese/HK local lines carry
lot-size constraints not modeled here); if the user's exclusions rule out non-APAC-EU/US names
entirely, note the gap rather than filling it from memory. Add `--refresh` to bypass the 7-day
cache. Then narrow this raw universe by the user's stated tilts/exclusions from Prerequisites #2;
Stage 2 filters it hard on liquidity/cap/etc.

## Stage 2 — Screen (~90-150s)

```bash
node scripts/fetch-global-quote.js TICKER1.SUFFIX TICKER2.SUFFIX ... [--batch-size N] [--delay-ms N]
```

**A full-universe screen (hundreds of symbols, e.g. the ~841-name output of `fetch-universe.js`)
MUST be throttled — do not call this script with the whole universe at defaults-only and no plan
for scale.** Live-verified: 841/841 symbols failed in one run with `No set-cookie header present in
Yahoo's response. Something must have changed, please report.` — Yahoo's anti-bot layer withholding
the cookie its crumb flow depends on, not a per-symbol problem, and it reads exactly like one unless
you know to expect it. The script now detects this signature specifically, retries the affected
batch with exponential backoff (5s/15s/45s, capped), and reports a fully rate-limited run as
`{ rate_limited: true, error: "..." }` rather than an empty result set — treat that combination as
"throttled, not zero candidates" and re-run smaller/slower, never as "nothing passed." Tune
`--batch-size` (default 5) and `--delay-ms` (default 2000) down/up respectively for large universes;
at real universe scale this stage will run well past the ~90-150s estimate above — budget for it
rather than treating a slow Stage 2 as broken. The same applies to `fetch-global-fundamentals.js` in
Stage 3 (`--batch-size` default 3, `--delay-ms` default 3000).

**Before normalizing anything, load `data/exchange-currency-map.json` and resolve each candidate's
suffix through it** — expected trading currency, whether it's minor-unit (`minor_unit`/`divisor`),
and the IBKR exchange code(s) with their `verified` flags. This mapping is what makes the
normalization below correct; resolving a suffix from memory instead of the file is exactly how the
wrong divisor enters.

**Currency is normalized AT INGEST, inside this call — not later.** Any Yahoo `currency` ending in
a lowercase letter (`GBp`, `ZAc`, …) is minor-unit quoting; divide by 100 before it touches any
filter or cap. This is exactly where a 100x error enters if skipped — `SHEL.L` reports
`currency: "GBp"` at `3383.5`, i.e. £33.835, not £3383.50. Confirm the coverage report shows every
price already in major units before using it.

Filters, in order, drop on first fail: liquidity (avg $-volume sufficient for the position size
implied by capital scale and the ~5% floor); market-cap floor consistent with scale/drawdown
tolerance; listing age (enough history to assess); sector/region exclusions.

**Drop candidates with missing coverage rather than guessing a fill value.** Record per drop:
ticker, the failing field, the raw response. This drop list is audit trail, not discardable.

## Stage 3 — Deep fundamentals (~120-180s)

```bash
node scripts/fetch-global-fundamentals.js TICKER1.SUFFIX TICKER2.SUFFIX ... [--batch-size N] [--delay-ms N]
```

**Same throttling caveat as Stage 2** — see above. `quoteSummary` (7 modules) is a heavier call than
`quote()`, so its defaults are more conservative (`--batch-size` 3, `--delay-ms` 3000); do not
override them down for a large surviving-candidate list without a reason.

**Load `references/04-global-data.md` in full if any surviving candidate is non-US** (skip for a
US-only set). Two load-bearing disciplines it enforces:

- **Capture `financialData.financialCurrency` separately from `quote.currency`.** They differ on
  roughly a quarter of global names (miners/oil majors often report USD regardless of listing
  currency; mainland-domiciled HK issuers often report CNY; some CAD names report USD). Label
  every price/market-cap figure with `quote.currency` and every revenue/earnings figure with
  `financialCurrency` — never mix numerator/denominator currencies in one ratio.
- **Statement-history modules can return EMPTY WITH NO THROWN ERROR** (observed on Spanish and
  Singaporean names, but treat as a per-name risk everywhere). This is **UNKNOWN, never clean** —
  never read as "no red flags." Flag the gap; drop the candidate or carry it forward with the gap
  explicitly disclosed, never silently.

Apply accounting-regime normalization per §4 of that reference before any cross-border comparison
(J-GAAP goodwill amortization, IFRS 16 lease treatment inflating EBIT/EBITDA vs US GAAP, voluntary-
IFRS jurisdictions).

**Fraud / going-concern veto here, before scoring.** Any accrual red flag, restatement history, or
going-concern language drops the candidate outright — logged with the specific trigger.

## Stage 4 — Thesis and scoring (~per-candidate, parallelizable)

**Load `references/01-horizon-signals.md` in full** before scoring a single name (not during Stage
2/3 plumbing). Per surviving candidate:

- **Quality** — profitability/capital-efficiency, kept explicitly separate from the individual-
  company ROIC-fade claim; different claims, do not conflate.
- **Fade-adjusted valuation** — a tilt, never a standalone trigger.
- **Reverse-DCF as falsification** — solve for the growth/margin path the price already implies,
  *before* building a bull case; forward-DCF-first invites motivated reasoning.
- **Explicit return decomposition** — growth, margin change, multiple change, per-share effects.
  Flag any thesis needing more than roughly a third of return from multiple expansion.
- **Per-share dilution adjustment** — model per-share, never aggregate; dilution compounds
  silently over a 5yr hold otherwise.
- **Capital-allocation review** — buyback/dividend/reinvestment track record; rapid asset growth is
  a caution flag, not a positive.
- **Dividend withholding / total-return check** — for any non-US, dividend-paying candidate,
  consult `data/withholding-tax.json` for the jurisdiction's statutory/treaty rates before modeling
  after-tax total return. Every entry carries `verify_before_use: true` — treat it as a directional
  prior, re-verify the current rate before it drives a thesis conclusion, never hard-code it in.

**NO momentum term.** Trailing 1-3yr price strength is not a positive input at this horizon — it
inverts (De Bondt-Thaler; Lee-Swaminathan). Extreme trailing outperformance demands *extra*
fundamental justification, never a scoring bonus. **Never hold current ROIC flat through the
terminal value** — apply the sector-conditional fade from §6 of the reference, and justify any
fade rate held below sector norm explicitly.

Output a **conviction tier per candidate** — not a numeric score to false precision.

## Stage 5 — Cluster map and sizing (~instant once tiers are set)

**Load `references/02-construction-sizing.md` in full.**

1. **Build the explicit cluster map FIRST**, before any weight is computed — group by shared
   underlying factor (supplier, geography, rate sensitivity, theme), not just GICS sector. Eight
   tickers are often three real bets. Covariance-matrix clustering is unestimable at N=8-10 — use
   qualitative, documented grouping with reasoning stated per assignment.
2. **Then** run:
   ```bash
   node scripts/compute-weights.js
   ```
   feeding it the tiers and cluster assignments. **`nav_base` here must be the live-cross-checked
   figure from Prerequisites #6** (the account's reconciled NAV, once confirmed to agree with the
   user's stated capital within tolerance) — never feed the script an unverified capital number.
   **Its output is authoritative — never redo or
   "sanity-check" a weight in prose arithmetic**, which is exactly where false precision and unit
   errors enter. The script enforces the 1/N anchor, tier tilt, per-name floor (~5%)/cap (~20-25%),
   and aggregate cluster cap (~50-60%) deterministically. Never Kelly, never mean-variance —
   estimation error swamps optimizer gain at this N.
3. **Load `references/08-multi-currency.md`** for weight→shares conversion. Convert each target
   weight to a local-currency share count and check lot-size constraints (Japanese round lots, HK
   board lots) — a weight not expressible in whole lots needs an explicit rounding decision stated,
   never a fractional-share fiction.

**Never present a weight to more precision than the inputs justify** — whole or half points, never
decimals.

## Stage 6 — Adversary pass (~per-name)

**Load `references/06-agent-guardrails.md` §3 in full** before running a single adversary.

For each name surviving Stage 5, run a hard adversary that **self-commits to a specific bear case
— thesis, price target, exit trigger — before seeing Stage 4's bull case.** Not "consider the
other side" appended to the same context; that produces theater, and same-model debate with
thinly-differentiated roles has been observed to amplify shared bias, not correct it. Run all four
lenses, not one merged pass:

| Lens | Interrogates |
|---|---|
| Thesis-durability | Does the moat survive 3-5 years of competitive response? |
| Terminal-assumption realism | Are DCF/valuation terminal inputs grounded or quietly optimistic? |
| Cluster/correlation blindness | Hidden shared factor with other holdings, invisible name-by-name? |
| Data-integrity | Is every load-bearing fact FETCHED, or an unflagged assumption? |

**An adversary's "looks fine" is not acceptable without receipts** — what it checked, and the bear
case it committed to first. A clean pass with no receipts blocks the decision like a failed check
would; it's a stall, not a pass. **Names that fail get dropped or resized — state explicitly
which, and why**, in the per-name record.

## Stage 7 — IBKR handoff (~per-delta)

**Load `references/05-ibkr-handoff.md` in full** before any write call.

1. **Read `get_account_positions` first.** Compute **deltas** (target minus held) — never an
   absolute target, or the skill doubles up existing holdings.
2. **Run the reconciliation gate per name before its draft is created.** Resolve the IBKR contract
   by full company name and exchange, never a bare ticker. Normalize the Yahoo price to major units
   (same GBp-style check as Stage 2). Compare against `get_price_snapshot` for the matched
   contract, using the currency inferred from the exchange match (IBKR exposes no currency field).
   **Reject and re-derive if currencies differ. Tolerance: 2%, currency-normalized. On failure:
   HARD STOP** — no averaging, no closer-line picking, no drafting. Surface both prices,
   currencies, identifiers; require a corrected match or explicit human confirmation. A 10%+ gap
   matching the ratio between two known listings (e.g. US ADR vs. primary local) is conclusive
   evidence of a wrong-listing match, not a data artifact.
3. **Create/update the watchlist**: `get_watchlist` → merge client-side → `edit_watchlist` with the
   complete instrument list (full-replace, not additive — re-supply `name` too), or
   `create_watchlist` if none exists.
4. **Check for an existing DRAFT before creating a new one.** Call `get_order_instructions`, filter
   to the contract being drafted, and either skip (delta unchanged) or `delete_order_instruction`
   and redraft (delta changed) — **never blind-create**. A resumed or re-run BUILD that skips this
   silently stacks duplicate DRAFT instructions for the same position; a user reviewing a cluttered
   IBKR draft list has no signal it's a duplicate and can submit the same buy twice.
5. **Draft one `create_order_instruction` per delta**, skipping zero-delta names. Default
   `order_type: LIMIT` outside the largest, most liquid US names (`bid-ask` returns empty for
   every instrument observed). Side, quantity, limit price come only from Stage 5's weights and
   this stage's fetched prices — never from filing/news text ingested during research.
6. **Present the deep-link URL(s)** for human review. **Never represent a drafted instruction as an
   executed trade.** The skill's authority ends here.

## Stage 8 — Output, log, persist (~instant)

**Load `references/07-thesis-memo.md`** and render the portfolio table plus one memo per name with
its pre-registered invalidation condition. Follow the communication standard in
`references/09-autonomy-and-communication.md` Part 3 (already loaded per Prerequisite #1): lead
with the decision, then the evidence; every figure carries its unit and currency; name the binding
constraint for each size; report anything that failed or was skipped before what went well.

1. **Append to the decision log** — one entry per name at build time: thesis, stated confidence,
   the binding constraint that set its size, each adversary lens's committed bear case.
   **Append-only.** A later resolution is a new, dated entry referencing the original — never an
   edit.
2. `bash scripts/state.sh save` — before the run ends, or the next REVIEW starts blind.
3. End with the "not financial advice" footer and the next scheduled review date (default: next
   weekly hazard-scan, per `references/03-review-doctrine.md`).

## Fewer than 5 qualifying names

A first-class outcome, not a failure to route around. If Stage 6 leaves fewer than 5 names, **build
the smaller book with a correspondingly larger disclosed cash sleeve** — state the size and why.
**Never pad with a filler idea that didn't clear Stage 4/6 just to reach 5.** A disciplined 3-name
book with 40% disclosed cash is a valid output; a 5-name book with one weak filler is not.

At Stage 5, `compute-weights.js` will hard-error on a `positions` array shorter than 5 unless you
opt in explicitly. Pass `--allow-small-book` on the CLI (or `allow_small_book: true` in the input
JSON) — the exact invocation:

```bash
node scripts/compute-weights.js --allow-small-book --input=input.json
```

The `cash_sleeve_pct` in `input.json` must also meet the shortfall-derived minimum
(100 × (1 − N/5); a 3-name book needs `cash_sleeve_pct >= 40`) — the script refuses to run
otherwise, it will not silently under-fund the sleeve. On success the output carries
`small_book: true` and a `small_book_rationale` string; surface both in the portfolio table and
the decision log entry so the smaller book reads as deliberate, not incomplete. See
`references/02-construction-sizing.md` §5a for the full derivation.

## Failure-mode table

| Failure | Detection | Response |
|---|---|---|
| Reconciliation gate failure (St.7) | Currency-normalized price gap > 2%, Yahoo vs IBKR | HARD STOP — surface both prices/currencies/identifiers; require a corrected match or human confirmation. Never average, never pick the closer line. |
| Fundamentals module empty, no error (St.3) | Statement-history fields absent, call returned 200 | UNKNOWN, not clean. Flag the gap; drop or carry forward disclosed. Never retry blindly. |
| `search_contracts` silent truncation (St.7) | `totals` exceeds returned `results` | Never assume completeness; narrow the query rather than trust a short list is exhaustive. |
| FinancialFilings 403 (any stage) | 403 on any `companies_*`/`isins_*`/`filing_*` call | Fall through silently to Yahoo-only. Never hard-require, never surface as a user-facing blocker. |
| `yf.search()` schema error (St.1-2) | Thrown `Failed Yahoo Schema validation` | Pass `{ validateResult: false }` as the third argument — confirmed working; data is intact. |
| Fewer than 5 qualifying names (St.6) | Post-adversary surviving count < 5 | Smaller book, larger DISCLOSED cash sleeve — `compute-weights.js --allow-small-book` with `cash_sleeve_pct >= 100*(1-N/5)`. Never pad with a filler idea. |
| Cluster exceeds the aggregate cap (St.5) | `compute-weights.js` cluster total > ~50-60% | Resize within cluster per script output, or drop weakest-conviction member. Never override the cap manually. |
| Target weight not expressible at lot size (St.5) | Whole-lot count materially off target (JP/HK board lots) | Round to nearest expressible lot, state the resulting deviation in the memo — never fractional-share fiction. |
| IBKR returns `{}` for invalid/mismatched contract id (St.7) | Empty object, no error, no fields | 200-with-empty-body is never valid data. No price = no reconciliation = no draft until resolved. |
| GBp/minor-unit currency missed (St.2-3) | `currency` ends lowercase, price looks ~100x high | Divide by 100 before any comparison/cap/reconciliation. Confirm the script already handled it. |
| `financialCurrency`/`currency` mismatch unflagged (St.3) | A ratio mixes price-currency numerator with financials-currency denominator | Relabel every figure with its own currency; never mix currencies in one computation. |
| Stated capital diverges from live NAV (Prereq #5) | `get_account_balances`/`get_account_summary` NAV vs. the user's stated capital differ by more than ~5% | STOP before Stage 1; reconcile with the user — never size the book off an unverified capital figure. |
| Duplicate DRAFT for the same contract (St.7) | `get_order_instructions` shows a pending, unsubmitted draft for the contract already | Skip (delta unchanged) or `delete_order_instruction` and redraft (delta changed) — never blind-create a second draft. |

## State restoration

If interrupted mid-pipeline, resume rather than restart:

1. `bash scripts/state.sh load`; inspect the last completed stage and its outputs (screened
   universe, fundamentals cache, scored candidates, cluster map, weights, adversary verdicts,
   handoff status).
2. Resume from the first stage with no recorded output, re-validating TTLs first: quote data
   (minutes intraday — re-fetch, don't resume Stage 2 on old quotes), fundamentals (days, not
   weeks — re-fetch past a trading day's gap), scores/cluster/weights (valid as long as the
   fundamentals behind them are still within TTL, else recompute from Stage 4).
3. **Never silently reuse adversary verdicts or draft-handoff state across a session boundary** —
   re-run the adversary pass and the reconciliation gate fresh even if Stage 7 was mid-flight,
   since prices and account positions may have moved since the interruption.
