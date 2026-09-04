---
name: diagnostics
description: Diagnostic procedures for SEO symptoms — the ordered traffic-drop decision tree, Search Console data traps, index-status decoding, migration forensics, cannibalization detection, and statistical honesty. Load whenever there is a symptom to explain (drop, lost rankings, page won't rank, post-migration damage) rather than a routine audit.
---

# Diagnostics

## The diagnostic stance

Form a hypothesis. Before looking for evidence that confirms it, name the evidence that would rule
it OUT, then go look for that evidence first. A hypothesis with no describable disproof is a
narrative, not a hypothesis, and a wrong narrative presented to stakeholders takes months to unwind.

Order checks cheapest-first. A binary 30-second check belongs before an hour of SERP analysis, not
because it's more likely to be the answer, but because ruling it out early prevents wasted
downstream work. Work the tree below in order; skip a node only once its evidence has actually
ruled it out, never because it matches a prior.

---

## The traffic-drop decision tree

Ordered cheapest-first; each node can eliminate a whole branch. Advance only once a node is
genuinely ruled out.

**Node 0 — Is the drop real?** Check the date-range shape (a 2-3 day dip vs. sustained multi-week
decline — the newest 1-3 days of GSC data are preliminary and revise), whether the window overlaps
a documented reporting anomaly (example: 2025-05-13 to ~2026-04-27, Google over-reported
impressions sitewide, distorting CTR and average position but not clicks, never backfilled —
verify against the live anomalies page rather than assuming this exact window still applies), and
WoW alongside YoY together. **Rule in:** decline holds 2-3+ consecutive weeks, consistent in both
views. **Rule out:** single-day blip, drop confined to the last 1-3 days, or a shift only in
impressions/CTR/position inside a confirmed anomaly window while clicks stay flat. If ruled out,
stop and report "not a real drop" rather than inventing a cause.

**Node 1 — Tracking or measurement breakage.** Check whether clicks AND impressions both
collapsed to near-zero simultaneously (a cliff, not a slope), and whether the property type
(domain vs. URL-prefix) changed around the same time. **Rule in:** a near-total, sudden collapse
across all queries and pages at once — real ranking losses are almost never instant and total.
**Rule out:** decline is gradual, partial, or concentrated in specific pages/queries.

**Node 2 — Manual action or security issue.** Check the Manual Actions and Security Issues
reports directly; both are binary. **Rule in:** any entry present. **Rule out:** both clean. This
is a 30-second, unambiguous check — run it every time, even when it feels unlikely, because
skipping it on a hunch is exactly how it gets missed when it's real.

**Node 3 — Seasonality and demand decline.** Overlay the affected query/category in Google Trends
against the same period last year; check whether visible competitor rankings/traffic move the
same direction. **Rule in:** Trends shows a matching seasonal shape and competitors trend the same
way. **Rule out:** Trends is flat or rising while your impressions fall — the problem is
site-specific.

**Node 4 — Indexation or technical failure.** Check the Page Indexing report for a drop in
Indexed count or a spike in a not-indexed status (noindex, robots.txt block, server error,
redirect error) on pages that used to rank; check Crawl Stats for a host-status flag or a 5xx
spike time-aligned with the decline; run URL Inspection Live Test on 3-5 previously-strong URLs.
**Rule in:** indexed-count drop, error-status spike, or crawl anomaly time-aligned with the
decline. **Rule out:** indexing and crawling are clean and stable.

**Node 5 — SERP-feature / CTR compression.** Pull impressions vs. CTR trend lines for the
affected queries — the signature is impressions flat-or-up, clicks down, CTR down, position
roughly stable. Manually check the live SERP for 5-10 representative queries for a new AI
Overview, expanded People Also Ask, a new carousel, or a competitor now above your result. **Rule
in:** impressions/position stable, CTR materially down, confirmed by a manual SERP check. **Rule
out:** impressions themselves are falling — this node is about clicks being intercepted, not
visibility lost.

**Node 6 — Algorithmic reranking.** Cross-reference the decline's start date against Google's
confirmed update rollout windows (fetch the current timeline; update schedules are volatile).
Segment by page type/template, content category, and query intent. **Rule in:** start date matches
a confirmed rollout, and losses concentrate in an identifiable pattern (a content type, a quality
tier, an intent category) rather than being random. **Rule out:** no rollout alignment and no
discernible pattern.

**Node 7 — Migration damage.** Only relevant if a migration/redesign shipped near the decline. If
so, run the full [Migration forensics](#migration-forensics) procedure below rather than
improvising. **Rule in:** timing lines up tightly with a launch date and the forensics checks
surface real anomalies. **Rule out:** no recent migration, or forensics come back clean.

**Node 8 — Cannibalization.** In the Pages report filtered to the specific query (or cluster),
look for multiple site URLs trading rank/impressions over time — one URL's impressions falling as
another's rise, net category clicks flat-to-down despite flat demand. This inverse "swap" pattern
is the signal, not mere co-occurrence. **Rule in:** a clear inverse relationship between two
internal URLs on the same query, with category clicks flat-to-declining despite flat Trends
demand. **Rule out:** no internal swap pattern.

**Node 9 — Brand vs. non-brand split and competitor displacement.** Regex-filter queries into
branded vs. non-branded buckets and compare trends separately; manually check SERPs for affected
non-brand queries for a new or strengthened competitor in your former positions. **Rule in:**
decline concentrated in non-brand with brand stable (competitive loss on generic terms), or
concentrated in brand specifically (reputation/demand/a competitor on brand terms) — plus, for the
non-brand case, a confirmed new competitor in the vacated positions. **Rule out:** decline is
proportional across brand and non-brand with no new competitor visible.

If every node is ruled out, don't stop at "unknown." Revisit Node 0's rigor (is the window
actually long enough?) and Node 6 with a wider update-date window — an under-the-radar or
unannounced ranking change is the most likely remaining explanation once everything else is
genuinely eliminated.

**Cross-cutting segmentation.** Wherever "the whole site is down" is the working claim, cut by:
brand vs. non-brand (regex filter, no native toggle); page type/directory (path-prefix filter,
separates a template-specific pattern from a true sitewide issue); query intent (informational vs.
transactional vs. navigational — core updates and SERP-feature impact skew informational); device
(isolates mobile-specific issues or device-skewed CTR compression); country (isolates rollout
timing, hreflang errors, or regional demand from a global issue). Filters stack with AND logic
(below), so validate any single-segment finding across two adjacent time windows before trusting it.

---

## Search Console data traps

| Trap | Why it misleads |
|---|---|
| **Average position is an average of averages** | An impression-weighted mean across every query, device, geography, and personalization state. "Avg position 8.2" can hide a #1 money query and fifty #45 long-tails at once. Filter to a single query or tight cluster before trusting any position number. |
| **Anonymized queries never reconcile with totals** | Low-volume/PII-risk queries are stripped from query rows but still count in page- and site-level totals. This is privacy filtering, not a bug — summing query rows to "check" a total is guaranteed to fall short. When query-level doesn't add up, pivot to page-level, which is complete. |
| **The ~1,000-row UI cap** | The Performance UI/export truncates per dimension combination. The Search Analytics API returns more (paginated); Bulk Data Export to BigQuery is the only unsampled, uncapped path (anonymized queries still excluded there too). Large sites relying on the UI alone silently miss the long tail — exactly where new cannibalization or migration stragglers show up first. |
| **Data freshness lag** | The newest 1-3 days are preliminary and still revise. Reacting to "yesterday's" dip is a classic false alarm — exclude or caveat the last 1-3 days in any drop analysis. |
| **16-month rolling retention** | History ages out permanently past ~16 months with no UI/API recovery unless previously exported. Enough for YoY, not enough for multi-year seasonal decomposition without an external export. |
| **Domain vs. URL-prefix property scope** | A Domain property rolls up all subdomains/protocols automatically; a URL-prefix property is scoped exactly to what was verified. Comparing history across a property-type change looks like a traffic event but is a measurement-scope change — confirm property type before trend-lining. |
| **Filters combine with AND logic** | Query AND page AND country AND device narrows multiplicatively. Stack enough filters (especially with the anonymized-query gap) and you can be looking at a near-empty, meaningless slice while believing it's comprehensive. |
| **GSC totals vs. analytics totals never match** | GSC counts impressions/clicks in Search results; analytics counts sessions that fired a tag, via its own attribution logic. Never designed to reconcile — see the reconciliation section below. |

**The impressions over-reporting anomaly (illustrative, re-verify before citing):** roughly
2025-05-13 to 2026-04-27, Google confirmed a logging bug that over-reported impressions sitewide,
distorting CTR and average position (impression-derived) but not clicks, with no historical
backfill. The durable lesson is not this specific window — it's that **a reporting anomaly of this
kind occurs periodically**, and any GSC trend analysis should check the current data-anomalies
page (`support.google.com/webmasters/answer/13112794`) before trend-lining impressions, CTR, or
position, because new anomalies get added over time and this one will eventually age out.

---

## Index-status decoder

| Status | What it means | Benign? | Action |
|---|---|---|---|
| **Crawled - currently not indexed** | Crawled and evaluated, then not indexed — a quality judgment, not a technical failure. | Often, at low volume. | Don't resubmit for crawling. Segment by template; a rising trend concentrated in one content type (thin, near-duplicate, low-value programmatic) is a real signal. |
| **Discovered - currently not indexed** | URL known but not yet crawled, often a deprioritized crawl. | Often, for large/new sites. | Check internal linking and Crawl Stats. Real signal only when a large volume of *important* URLs sits here for weeks. Not a noindex/robots issue. |
| **Duplicate without user-selected canonical** | Google picked a canonical because none was specified. | Usually — canonicalization working as designed. | Set an explicit canonical if you have a preference; otherwise confirm Google's choice is the one you'd want ranking. |
| **Duplicate, Google chose different canonical** | A canonical was specified but overridden. | Not by default. | Compare the two URLs. Near-identical: consolidate or strengthen signals toward your preferred URL. Genuinely different: may be cannibalizing. |
| **Alternate page with proper canonical tag** | Correctly points to an indexed canonical (pagination/params/hreflang). | Fully. | No action. Confirmation canonicalization works — over-reporting this as an "issue" erodes credibility. |
| **Page with redirect** | Non-canonical URL that redirects; never indexed itself. | Yes, expected. | Confirm the target is indexed and correct. Flag only if a batch is unintentional. |
| **Excluded by 'noindex' tag** | Directive found and honored. | If intentional. | Cross-check against pages meant to rank. A sitewide spike right after a deploy (e.g., a staging header shipped to prod) is high-priority breakage. |
| **Blocked by robots.txt** | Disallowed from crawling; may still be indexed via link signals with no snippet. | Depends. | Diff robots.txt against affected URLs. A newly broadened Disallow is a common self-inflicted drop cause. |
| **5xx / 404 / soft-404 / redirect error** | Genuine crawl/serving failures. | No. | Cross-reference Crawl Stats' response-code timeline and server logs for the triggering event. |
| **Page is indexed** | Eligible to appear. | N/A. | Not proof of ranking or visibility. Spot-check money pages with Live Test — "indexed" doesn't confirm the indexed content matches the live page. |

---

## GSC vs. analytics reconciliation

GSC counts impressions/clicks recorded in Search results, including clicks that never become a
full pageview (bounce before the tag fires, blocked tag/cookie). Analytics counts sessions that
fired the tag, attributed to organic by referrer/channel logic with its own edge cases
(self-referrals, cross-domain gaps, consent-mode gaps). These were never designed to match, and a
daily mismatch is not evidence of a tracking problem.

The right question is whether the **ratio** between the two has changed over time. A stable ratio,
even with numbers that never align, means both systems behave consistently. A sudden divergence in
the ratio is the real signal — it means something changed in how one system counts (a tag firing
later, a consent banner blocking more sessions, a property scope change), not that traffic moved.

---

## Migration forensics

A distinct, ordered procedure for a decline following a migration, replatform, or redesign. Run
this fully before returning to Node 7 above.

1. **Redirect-map completeness.** Audit the full pre-migration URL list (old sitemap, crawl
   archive, or pre-cutover GSC page list) against the new redirect map. Spot-check 20-30
   previously-ranking URLs individually: 404/soft-404 is a coverage gap; a redirect whose
   destination canonical points elsewhere is canonical drift; a chain (old → intermediate →
   final) is stacked migration tooling and should be collapsed to single-hop.
2. **URL structure diff.** Compare old vs. new URL patterns directly — added/removed path
   segments, changed slugs, a different pagination scheme multiply the redirect-mapping problem
   even when redirects appear to work.
3. **Internal-link preservation.** Did primary nav, footer, or related-content links change
   targets or drop during the redesign? Link-equity flow disruption is often underweighted — a
   redirect can work perfectly while the internal graph no longer reinforces the destination.
4. **Canonical and hreflang drift.** Check whether the new templating layer introduced
   self-referencing errors, cross-locale canonical pointers, or dropped hreflang alternates.
5. **Staging artifacts shipped to production.** Check production robots.txt right now for a
   blanket Disallow or leftover staging block, and check for a global noindex (meta or
   X-Robots-Tag) inherited from staging config — the single most common "traffic went to zero
   overnight" root cause, and should be checked immediately, not last.
6. **Hash-routing and client-side-only navigation.** Confirm new URLs are real, crawlable,
   bookmarkable paths, not fragment-identifier states invisible to crawlers.
7. **Discovery-crawl collapse.** Check Crawl Stats for a drop in discovery-purpose crawling
   post-launch — Google not finding new URLs fast enough, usually weak internal linking or a
   stale/missing sitemap.

**Realistic recovery:** months, not weeks, once real migration damage is confirmed. Don't promise a
fast reversal, and don't treat week-two flatness as evidence the fix failed.

**The attribution trap:** changing platform, URL structure, and design simultaneously makes it
statistically impossible to isolate which change caused a given loss. Say so explicitly rather than
picking whichever cause is easiest to explain — segment by what the evidence actually supports
(redirect gaps → URLs; thinner copy or removed internal links → design; canonical drift → platform).

---

## Cannibalization: detection and decision

The rigorous test is **measurable harm**, not overlapping strings. Two pages ranking for related
keywords with genuinely different intent is normal and healthy, not cannibalization.

**Detection:** filter the Pages report to the specific query (or a tight cluster) and look for the
"swap" pattern over time — one URL's impressions/position rising as another's fall, total clicks
flat-to-declining despite flat demand (confirm via Trends, don't assume). This sustained inverse
relationship is the harm signal: Google itself hasn't settled which page should own the query.
Co-occurrence on one snapshot day is not evidence.

| Diagnosis | Fix |
|---|---|
| Same query, same intent, one page clearly weaker/outdated | Consolidate: merge into the stronger URL, 301-redirect the weaker one, repoint internal links |
| Same query, same intent, both mediocre | Consolidate into one rewritten page, redirect both originals |
| Overlapping query, genuinely different intent/audience | Differentiate: sharpen titles/H1s/framing so the angle is unambiguous; do not merge |
| Near-duplicates for legitimate technical reasons (tracking params, print views, pagination) | Canonicalize — canonical is a duplicate-content tool, not a cannibalization fix; misapplying it to distinct-intent pages is a common error |
| Underperforming, no standalone value or backlinks | Prune (410/404) only after confirming zero independent value — deleting a page with real backlinks or traffic is worse than consolidating it |

Avoid de-optimizing a page (stripping keyword targeting to "cede" it to a sibling) — it affects
unintended keywords unpredictably. Avoid blanket noindexing one side — it removes the page from
all rankings instead of resolving which page should own the query.

---

## Content decay and refresh decisions

A genuine decay signature is a gradual, multi-month decline in average position and/or impressions
with no other explanation. Rule out first: **seasonal dip** (check YoY, not just MoM);
**SERP-feature displacement** (impressions flat/up, clicks down — a feature is absorbing the
click, not a quality problem, see Node 5); **cannibalization** (a sibling page is taking the
position); **algorithmic devaluation** (a step-change aligned to a confirmed update date, not
gradual decline).

```
Is the page decaying (data-confirmed, not seasonal/cannibalization/SERP-feature)?
├─ NO → Leave alone. Refreshing a page that isn't declining is a wasted cycle and a
│        "fake freshness" risk with no upside.
└─ YES
   ├─ Sibling URL already covers this topic well? → Consolidate (framework above)
   ├─ Is the topic still relevant/searched (query-volume trend, not just rank)?
   │  ├─ NO, zero demand, no backlink equity → Prune (410/404)
   │  ├─ NO, but meaningful backlinks/referral value remain → Redirect to the closest
   │  │        relevant current page
   │  └─ YES, demand persists
   │     ├─ Decay from outdated/thin content vs. current top-10, or missing what
   │     │  searchers now expect → Improve: substantive rewrite (updated data, expanded
   │     │  coverage, new analysis, removed stale claims), re-check against SERP intent.
   │     │  Update the dateline only as a byproduct of the real edit, never as the fix.
   │     └─ Decay from something outside content (technical regression, lost backlinks,
   │        internal-link changes, a stronger competitor, an update) → Diagnose and fix
   │        the actual cause; a rewrite will not fix a technical or off-page problem.
   └─ Uncertain which bucket → leave alone or a light fact-check pass; over-refreshing
      low-decay pages burns editorial budget on content that wasn't broken.
```

**Cosmetic freshness is a risk, not a tactic.** Changing a visible date or copyright year with no
substantive edit is the exact low-effort pattern Google's dateline guidance and quality-rating
criteria target. There's no guaranteed display benefit even when the date is technically accurate,
and a diffed history (via an archive) showing a date bump with no content change is a liability in
an audit. Never recommend a date change as the fix itself.

---

## Intent mismatch diagnosis

A page can be well-written, well-sourced, and technically clean and still fail to rank because
it's the wrong **type** of content for what the query wants — a common, frequently overlooked root
cause of "why won't this page rank," and no on-page optimization fixes it if the mismatch is
structural.

Pull the current live SERP for the target query (not cached or assumed — intent drifts) and
classify the top 5-10 results on three axes: **content type** (blog post, video, product/category
page, tool, comparison, forum thread, local pack), **content format** (listicle, tutorial,
comparison table, single deep review), **content angle** (e.g. recency-coded titles signal
searchers want current picks, not evergreen advice). Check whether the owned page matches on all
three. A page matching zero or one of three is a structural mismatch — the content type itself
needs to change, not the copy. If the SERP is entirely a different content type than what you have
(an editorial-listicle SERP against a manufacturer product page, a tool/calculator SERP against a
long essay), no amount of quality polish closes the gap; only a content-type change does.

---

## Statistical honesty

- **Day-to-day variance is largely noise.** Weekday/weekend cycles alone commonly produce swings
  wide enough to look alarming on a single day; never diagnose from one day's number.
- **Minimum window:** favor several consecutive weeks of a consistent directional trend over any
  single week-over-week comparison, which is among the least reliable inputs on its own.
- **WoW vs. YoY:** WoW is fast but exposed to weekday-mix and short-term noise. YoY controls for
  seasonality but is blind to *when* within the year something changed, and can straddle multiple
  algorithm updates, conflating causes. Use both together rather than either alone.
- **Small sites need wider windows.** Low absolute click/impression volume produces
  disproportionately large percentage swings from small-number variance (3 clicks to 7 reads as
  "+133%" and means almost nothing) — the lower the volume, the longer the window needed before
  treating a percentage change as signal.
- **Never lead a diagnosis with a single-day or single-week chart.** Present a rolling multi-week
  trend alongside a YoY comparison, and explicitly label the last 1-3 days as preliminary rather
  than silently cutting them off — silent omission invites the obvious question; labeling it
  builds trust in the rest of the analysis.
