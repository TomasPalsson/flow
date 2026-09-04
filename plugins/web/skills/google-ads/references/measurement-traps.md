---
name: measurement-traps
description: Why a Google Ads number means something other than it looks like — micros scaling, conversion semantics, impression-share clamping, attribution rewrites, and the structural reasons totals never reconcile. Load before quoting conversion, value, or share numbers, or comparing periods.
---

# Measurement Traps

Every trap here shares one shape: the API returns a correctly-typed, plausible
number, no error is raised, and the number answers a different question than the
one asked. None of this is discoverable from a field name or a metadata call.

Confidence is marked where it matters. Where a claim is unresolved, it says so —
do not upgrade it in your own writing.

---

## 1. Micros scaling

**The rule that is airtight:** an `int64` field whose name ends in `_micros` is
scaled by 1,000,000. Divide it. No exceptions exist in the schema.
(High — proto-verifiable.)

**Where the rule breaks:** `double` fields with no suffix split into two families
that scale in *opposite* directions.

| Family | Fields | Scaling |
|---|---|---|
| Cost-family | `average_cpc`, `average_cpm`, `average_cpe`, `average_cost`, `trueview_average_cpv`, `cost_per_conversion`, `cost_per_all_conversions` | **Micros** — divide by 1e6 |
| Value-family | `conversions_value`, `all_conversions_value`, `cross_device_conversions_value` | **Not micros** — already currency |
| Ratios | `ctr`, `*_rate`, `*_share`, `*_percentage`, `conversions_value_per_cost` | Dimensionless — never divide |

Cost-family micros scaling rests on a Google Ads API team member's statement on
the official developer forum plus an arithmetic argument (a micros numerator
divided by a plain count stays micros). It is **not** stated in the proto or the
field-reference page. Confidence: Medium-High.

Value-family rests on structural proto evidence: Google ships *both*
`cross_device_conversions_value` (`double`) and
`cross_device_conversions_value_micros` (`int64`, documented "in micros") as
separate fields — which only makes sense if the plain one is not micros.
Confidence: Medium-High.

**`value_per_conversion` is unresolved.** It is `conversions_value ÷ conversions`
— an unscaled numerator over a plain count, which argues *not* micros, the
opposite of its look-alike `cost_per_conversion`. No source settles it. Do not
assert its units; verify or say it is unverified.

**The runtime check that settles any of these** — one query, no guessing:

> Select the ambiguous field together with its components on a row with nonzero
> volume, e.g. `metrics.cost_micros`, `metrics.clicks`, `metrics.average_cpc`
> from `campaign`. Compute `cost_micros / 1e6 / clicks` by hand and compare to
> the returned `average_cpc`. If they match, your scaling assumption is right;
> if they differ by 1e6, it is inverted. Same method for `value_per_conversion`
> against `conversions_value / conversions`.

Prefer this over trusting any table, including this one.

---

## 2. Rates and ratios must be recomputed, not averaged

CTR, CPC, CPA, conversion rate and ROAS are ratios of two counters. Averaging
them across rows or days weights a 10-impression day equally with a
100,000-impression day — a textbook Simpson's-paradox setup where the direction
of the computed change can reverse relative to the truth.

Always recompute from summed numerators and denominators:
`sum(clicks) / sum(impressions)`, never `mean(daily_ctr)`.

---

## 3. Impression share: clamped, non-additive, sometimes absent

Proto-verbatim clamping (High confidence):

- Share metrics reported in `[0.1, 1]` — any true value **below 10%** is returned
  as **`0.0999`**: `search_impression_share`, `search_absolute_top_impression_share`,
  `search_top_impression_share`, `search_click_share`,
  `search_exact_match_impression_share`, `content_impression_share`.
- "Lost" metrics reported in `[0, 0.9]` — any true value **above 90%** is
  returned as **`0.9001`**: `search_budget_lost_impression_share`,
  `search_rank_lost_impression_share`, their absolute-top/top variants, and the
  content equivalents.

So `0.0999` is a sentinel meaning "below 10%, exact value withheld." A quarter
of `0.0999` readings is *not* "flat at ~10%" — the truth may have swung between
1% and 9%.

**Non-additive.** The denominator is a Google-estimated eligible-impression pool
that the API never exposes. Summing or simple-averaging across campaigns or days
produces a number corresponding to no real quantity. Either report at the grain
Google provides, or state explicitly that you impression-weighted as an
approximation.

**Absent ≠ zero.** At low volume these fields come back missing rather than `0`.
Missing means "not enough data to estimate," which is a different finding from
"you have no impression share."

**Two families with near-identical names.** `absolute_top_impression_percentage`
and `top_impression_percentage` are unclamped ratios of *your own* impressions.
`search_absolute_top_impression_share` / `search_top_impression_share` are
clamped, modeled shares of an *eligible* pool. Both are valid `[0,1]` doubles, so
nothing errors when you grab the wrong one.

---

## 4. Conversions are not a straightforward count

- **Fractional by design.** Attribution splits credit, so one purchase can appear
  as `0.4` on one keyword and `0.6` on another. `conversions` is a `double`.
- **Click-date attributed by default.** A conversion counted "today" may belong
  to a click up to 90 days ago. Day-level cost-vs-conversion correlation from raw
  `metrics.conversions` + `segments.date` is not causally clean. The
  `*_by_conversion_date` variants report on the conversion's own date instead.
- **`conversions` vs `all_conversions` count different populations.**
  `conversions` includes only actions with
  `conversion_action.include_in_conversions_metric = true`; `all_conversions` is
  the superset. Picking the bigger number is not "more complete," it is a
  different question. Use `conversions` for "what is Smart Bidding optimizing,"
  `all_conversions` for "full measured business impact,"
  `*_by_conversion_date` for reconciling against an order system.
- **Reporting inclusion and biddability are separate switches.**
  `include_in_conversions_metric` governs the reporting column;
  `primary_for_goal` governs whether Smart Bidding optimizes for it — and custom
  conversion goals override `primary_for_goal`. An action excluded from the
  reporting column can still be driving bidding.
- **Counting type changes the meaning.** `MANY_PER_CLICK` actions can report more
  conversions than clicks. That is expected for lead-gen actions, not a data bug.
- **Partly modeled.** Google models conversions it cannot observe (consent gaps,
  ITP, cross-device) — and *only* where volume clears a threshold, so a small
  account may show lower conversions simply because it did not qualify for
  modeling. Do not present modeled figures as observed ground truth.
- **Do not add the subsets.** `cross_device_conversions` and
  `view_through_conversions` are already folded into `all_conversions`. Adding
  them double-counts.

---

## 5. History is not stable

Attribution model changes — including Google's automatic migration to
data-driven attribution — **retroactively recalculate historical conversion
credit**. Re-pulling the same past date range weeks apart can legitimately return
different numbers with no account change, no budget change, and no seasonality.

The data-driven model itself drifts: a conversion action's
`data_driven_model_status` can go `STALE` (not updated 7+ days) or `EXPIRED`
(30+ days, usually because volume fell), silently changing credit distribution.

Before diagnosing "our historical numbers changed, tracking must be broken,"
rule out attribution recalculation first.

---

## 6. Recent data is provisional — and there is no official constant

Conversions keep arriving for days or weeks. Recent-day CPA and ROAS will improve
on re-pull with no underlying change. An agent that flags "CPA doubled yesterday"
is usually reading in-flight data.

Google publishes **no single exclusion window**. Its own pages say, variously:
"exclude the most recent few weeks," a worked example using 14 days, and
"at least 30 days." Its strongest statement is account-specific:

> Wait until the account's own **Avg. days to conversion** — or the conversion
> action's configured lookback window, whichever is longer — has elapsed.

Derive it from the account (`segments.conversion_lag_bucket`, the conversion
action's `click_through_lookback_window_days`, up to 90). Do not quote a flat
"exclude 2 weeks" as a Google rule; it is not one.

---

## 7. Totals structurally will not reconcile

Each of these is expected behavior, not a defect:

- **Privacy thresholding.** Low-volume search terms and demographic/geo rows are
  omitted from the breakdown while their clicks and cost still count in the
  parent total. Suppression is based on query volume across all of Google, so a
  term meaningful to one advertiser can still be hidden. The gap grows with how
  long-tail the account is.
- **Performance Max has no ad-group or ad-level reporting at all.** Any
  ad-group-level rollup claiming to explain 100% of account spend silently omits
  100% of PMax spend. PMax search terms live in `campaign_search_term_view`;
  `search_term_view` excludes PMax by its own proto definition.
- **Asset-level metrics are shared, not exclusively attributed** across assets in
  an ad or ad group. Summing asset rows over- or under-counts by design.
- **Some segments do not simply partition.** `segments.conversion_adjustment`
  splits into an "original" row and a "delta" row that must be summed *together*.
  `segments.conversion_action` can multiply-count clicks and impressions across
  rows tied to the same click.

**Never rescale child rows to force a match with a parent total.** That corrupts
correct data to close a gap that was never meant to close.

---

## 8. Currency

`customer.currency_code` is per-account and immutable. Every cost value is in
that account's own currency and the API provides **no** conversion — the "Converted
currency" rollup in the Google Ads UI is UI-only and not exposed through the API.

Summing `cost_micros` across `customer_client` rows in a multi-currency MCC adds
USD cents to GBP pence and returns a large, plausible, meaningless number with no
error. Check currency per account first; then either report per currency group or
apply an explicit external FX rate and disclose it.

---

## 9. Budgets

`campaign_budget.amount_micros` is a **daily** amount. Google's own cap is
`30.4 ×` the daily amount per month, and daily spend can run up to 2× the daily
budget on any given day. Multiplying daily budget by 30 or 31 will not match
Google's monthly cap arithmetic.
