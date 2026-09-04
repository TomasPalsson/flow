---
name: diagnostic-playbooks
description: Ordered elimination sequences for Google Ads symptoms (CPA spike, conversion drop, flat revenue, serving stopped, ROAS decline, budget underspend), the volume thresholds that make a finding real, and the reasoning errors AI analysis characteristically makes. Load when the user reports any performance symptom.
---

# Diagnostic Playbooks

The order is the expertise, not the checklist. A broken conversion tag and a
genuine demand collapse produce an identical chart. One is a five-minute fix, the
other a strategy rebuild. So the sequence always runs cheap-and-deterministic
first, unfalsifiable-and-expensive last.

Every playbook below opens the same way, and that is the single most consistent
piece of practitioner knowledge in this domain.

---

## The universal opening

1. **Conversion tracking health.** Is the conversion action still recording? Was
   it edited — value, counting type, attribution setting, inclusion flag —
   shortly before the inflection? A duplicated or newly-added conversion action
   silently double-counts; a removed one silently halves.
2. **Change history.** Query `change_event` around the inflection date (needs
   `LIMIT <= 10000`, and a date bound). A change landing on or just before the
   inflection is the prime suspect. This is the fastest root-cause path in the
   entire domain because changes are logged and precisely dated.

Only after both: segment, then bid-strategy state, then auction pressure, then
the market.

---

## 1. CPA / CAC suddenly spiked

1. Conversion action status and edits (see universal opening).
2. Account-wide change history on the spike date — bid strategy changes, target
   changes, budget changes, new campaigns, **removed negative keywords**.
3. Segment by device, network (Search vs Search Partners), geo, time of day. An
   account-wide average routinely hides one broken segment.
4. Bid-strategy learning state — a recent qualifying change looks exactly like a
   cost spike while the algorithm recalibrates.
5. Auction pressure — new competitors or rising overlap raise CPCs with no
   account-side change. (Auction Insights fields are usually allowlist-gated via
   the API; treat their absence as an entitlement gap, not a finding.)
6. Search terms for query drift — broad match plus Smart Bidding pulling in
   low-intent, expensive queries.
7. Only now: treat it as a genuine cost increase.

## 2. Conversions dropped off a cliff

This is the highest-consequence misdiagnosis in PPC: optimizing against a
phantom drop that is actually a broken tag.

1. Conversion action diagnostics — tag firing, "detected" status, listed issues.
   Allow 24–48h for status to reflect a real site change.
2. Independent tag verification on the actual conversion page. A CMS deploy, a
   changed thank-you URL, or a consent-banner update breaks tracking without
   touching Google Ads.
3. **Is it a conversion-lag illusion?** Recent days are structurally
   undercounted. Check the account's lag distribution before concluding anything
   about the last week.
4. Consent-mode / cookie-consent changes suppressing measurable conversions.
5. Change history for the conversion action and bid strategy.
6. Segment by device/geo/network — universal points to tracking or consent,
   localized points to a real serving or demand issue.
7. Only now: treat as a genuine collapse.

## 3. Spend up, revenue flat

1. Compare growth *rates*: spend vs clicks vs conversions.
   Spend up + clicks flat → CPC inflation. Spend up + clicks up + conversions
   flat → conversion-rate problem on the new traffic, or a tracking gap.
2. Isolate **where** the incremental spend went, by campaign then ad group.
   Broad match and Smart Bidding are the usual leak paths.
3. Check whether a budget or target change preceded it — and whether the
   comparison window sits inside a learning period.
4. Check assisted conversions before calling the spend wasted; last-click flatness
   can hide upper-funnel contribution.
5. Segment by network. A growing Search Partners share moves blended metrics with
   no change in Google Search performance at all.

## 4. Impressions collapsed / stopped serving

A cliff to near-zero is almost always a break, not the algorithm.

1. Status and eligibility: paused, removed, budget exhausted, ad disapproved,
   policy review. **Check billing** — a failed payment or hit spending limit
   stops everything abruptly and is easy to overlook.
2. Change history on the drop date — status, budget, targeting, geo edits.
3. Policy disapprovals, including landing-page issues, which can zero serving
   without an obvious paused state.
4. Segment impressions by day to find the exact break date; a real break holds
   every day after, unlike a partial-data artifact.
5. Rank-lost vs budget-lost impression share to separate "we can't win auctions"
   from "we ran out of money."
6. Account-level issues — suspension, verification requirement, payment profile.

## 5. ROAS declining slowly over months

A slow decline is a trend, not a break. The task is isolating *which layer*
degraded.

1. Measurement drift first — attribution model change, conversion value change,
   rising share of modeled conversions, slow tag degradation. All produce gradual
   decline that is not a performance problem.
2. Auction Insights trended over the full window, not a snapshot.
3. Lost impression share, split rank vs budget, trended. Fix rank-driven loss
   before spending more.
4. Creative fatigue — declining CTR with flat or rising CPC over weeks.
5. Segment the decline: a mix shift in one segment usually explains what looks
   like uniform decay.
6. Query drift accumulating over months — trend the search terms, don't snapshot.
7. Market and seasonality **last** — unfalsifiable and easy to reach for early.

## 6. New campaign won't spend its budget

1. Separate zero impressions from some-impressions-low-spend. They have different
   causes; zero impressions is a settings problem that will not resolve with time.
2. Bid strategy status reason — "limited by bid strategy" usually means the
   target is too aggressive (tCPA too low, tROAS too high) to win auctions.
3. Smart Bidding optimizes toward the goal, not toward spend. Deliberate
   underdelivery against an unrealistic target is by design.
4. Give a genuinely new campaign its learning period — but keep checking for
   zero-impression conditions daily, which are not a learning issue.
5. Check compounding narrow targeting and shared/portfolio budget caps elsewhere.
6. If targets are the constraint, establishing a real baseline before layering a
   target on is sounder than guessing a target with no history.

---

## Volume thresholds — what makes a finding real

Google's stated minimums, verified against
`support.google.com/google-ads/answer/6268637` and `.../answer/6268632`:

| Strategy / campaign type | Google's stated minimum |
|---|---|
| Target CPA (evaluation, general) | 30 conversions in the last 30 days |
| Target ROAS — Search & Shopping | **15** conversions / 30 days |
| Target ROAS — Display | 15 conversions (with values) / 30 days |
| Target ROAS — App | 10/day, or 300 / 30 days |
| Target ROAS — Demand Gen | 50 / 35 days (10 in last 7), or 100 across campaigns |
| Target ROAS — Video Action | 30 / 30 days |
| Target ROAS — Hotel | 50 per week |
| Target ROAS — Travel | 50 / 7 days |

**The widely repeated "50 conversions for tROAS" is a conflation.** It is the
Demand Gen and Hotel figure. For standard Search and Shopping the official floor
is 15. Do not quote 50 as universal.

**Learning period**: "up to 3 weeks or 1–2 conversion cycles" to calibrate after
a change (`support.google.com/google-ads/answer/13020501`).

**Do NOT cite "a >20% budget or target change resets learning."** Three official
Google pages were checked directly and none states it. Google's own FAQ says the
opposite framing — that Smart Bidding "reacts to target changes in real time,
whether they are large or small." The 20% figure traces to third-party agency
content. If it comes up, label it as unverified community folklore.

These are floors for *eligibility*, not confidence. Practitioners work to higher
bars (roughly 50–80 for tCPA, 100+ for tROAS) before trusting steady-state
behavior — a heuristic, not a Google number.

---

## Comparison discipline

- **Week-over-week beats day-over-day** for judging performance. PPC metrics are
  strongly day-of-week cyclical; DoD bakes in a confound. Reserve DoD for
  detecting a break, not for judging performance.
- **Year-over-year needs day-of-week and holiday alignment.** Comparing literal
  calendar dates lands on different weekdays and different offsets from moving
  holidays, manufacturing trends that are pure calendar artifact.
- **Scanning many keywords will always surface an outlier by chance.** Require
  persistence across multiple periods before acting, and be aware that a metric
  reverting to its mean after you pause something is not evidence the pause
  worked.
- **One significant change at a time.** Batched changes make attribution
  impossible and compound learning resets.

---

## Where AI analysis characteristically fails

Guard against these deliberately — they are the failure modes of fluent
pattern-matching, which is exactly what an LLM does well and dangerously here.

- **Confident causal narrative without running the elimination sequence.** The
  documented case: an AI tool attributed a conversion drop to "limited budget"
  from surface-level visibility gaps when the real cause was a bidding
  constraint. Fluency outran evidence. (One documented incident, reported by
  Frederick Vallaeys of Optmyzr via Search Engine Journal — treat it as an
  illustrative case, not a general law.)
- Treating modeled conversions as observed ground truth.
- Aggregating non-additive ratios (impression share above all).
- Ignoring conversion lag and declaring a recent period a failure.
- Recommending pausing "expensive" keywords from last-click cost alone.
- Confusing correlation with causation on budget changes, which are never
  randomly assigned — budgets get raised on campaigns already trending.
- Over-trusting Google's Recommendations and Optimization Score. The score
  measures adoption of Google's suggestions, not account health, and several
  recommendation types are better aligned with Google's revenue than the
  advertiser's ROI.
- Presenting a finding from a handful of conversions with the same confidence as
  one backed by thousands.

---

## Operating posture

This server is read-only, and that is the right posture regardless. Never phrase
a suggestion as a change already made. Frame recommendations with the spend at
risk, over what period, and whether they are reversible — and leave the decision
with the human.
