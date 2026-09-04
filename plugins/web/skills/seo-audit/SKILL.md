---
name: seo-audit
description: When the user wants to audit, review, or diagnose SEO issues on their site, or wants to know why they are not visible in Google or in AI answers. Also use when the user mentions "SEO audit," "technical SEO," "why am I not ranking," "SEO issues," "on-page SEO," "meta tags review," "SEO health check," "my traffic dropped," "lost rankings," "not showing up in Google," "site isn't ranking," "Google update hit me," "page speed," "core web vitals," "crawl errors," "indexing issues," "why doesn't ChatGPT know about us," "AI Overviews," "AI search visibility," "AEO," "GEO," "LLM SEO," "answer engine optimization," "should I block AI crawlers," or "llms.txt." Use this even if the user just says something vague like "my SEO is bad" or "help with SEO" — start with an audit. Covers classic search and AI/LLM answer engines together, because the technical foundations overlap and the failure modes differ.
metadata:
  version: 2.0.0
---

# SEO Audit

You are diagnosing a system you cannot see directly, using evidence you must go and collect.

Two rules govern everything below.

**Rule 1 — Evidence before findings.** Never report an issue you have not observed. A crawler's
output is a hypothesis; your job is to confirm it, size it, and decide whether it matters. Audits
fail far more often from unfiltered tool output than from missed checks.

**Rule 2 — Verify, do not recall.** This field changes monthly. Rich-result types get retired,
crawler rosters gain user-agents, reporting tools develop bugs, CDN vendors change default policies.
Anything in this skill marked VOLATILE must be re-checked against its primary source at audit time.
Asserting a stale fact confidently is the most damaging thing you can do here.

---

## Route by symptom

Do not run a full audit by reflex. Match the request to the job:

| The user says | Start with | Load |
|---|---|---|
| "Traffic dropped" / "we lost rankings" | Diagnosis, not a checklist. Find the cause first. | [`references/diagnostics.md`](references/diagnostics.md) |
| "Why won't this page rank for X" | Single-query investigation: intent match, then cannibalization, then competitiveness | [`references/diagnostics.md`](references/diagnostics.md) |
| "We migrated and lost traffic" | Migration forensics — a distinct procedure | [`references/diagnostics.md`](references/diagnostics.md) |
| "Audit our site" / "SEO health check" | Full pass, Phases 0-3 below | this file, then suppress |
| "Are we visible in ChatGPT/AI Overviews" | AI visibility split: retrievability vs citability | [`references/ai-search.md`](references/ai-search.md) |
| "Should we block AI crawlers" | Bot-role analysis — the answer depends on which bot | [`references/ai-search.md`](references/ai-search.md) |
| Multi-language / multi-region site | Hreflang and locale integrity | [`references/international-seo.md`](references/international-seo.md) |

A drop investigation that turns into a generic checklist is the most common way this work goes
wrong. If there is a symptom, chase the symptom.

**Do NOT load** what the job does not need. Loading everything is not thoroughness, it is noise that
buries the relevant procedure:

- Skip `ai-search.md` unless AI/LLM visibility is actually in scope. A classic ranking problem does
  not become an AI problem because AI is topical.
- Skip `international-seo.md` for single-locale sites.
- Skip `ai-writing-detection.md` unless you are literally drafting or rewriting copy.
- Skip `diagnostics.md` for a greenfield site with no history and no symptom, since there is no
  change to explain.
- `false-positives.md` is the exception: load it before finalizing findings on **every** audit.

---

## The freshness protocol

Before asserting any of the following, fetch the primary source. These change on a timescale shorter
than this skill's revision cycle.

| VOLATILE claim | Fetch before asserting |
|---|---|
| Which rich results still produce a SERP feature | `developers.google.com/search/docs/appearance/structured-data/search-gallery` |
| Which AI/search crawler user-agents exist and what each does | `developers.openai.com/api/docs/bots`, `claude.com/crawling/bots.json`, `developers.google.com/search/docs/crawling-indexing/overview-google-crawlers` |
| Whether a Search Console report has a known data anomaly | `support.google.com/webmasters/answer/13112794` |
| Current core/spam update timeline | `status.search.google.com/products/rGHU1u87FJnkP6W2GwMi/history` and Search Central blog |
| Google's stated position on any AI-visibility control | `developers.google.com/search/docs/appearance/ai-features` |
| Robots.txt interpretation specifics | `developers.google.com/search/docs/crawling-indexing/robots/robots_txt` |
| Spam policy definitions (scaled content, site reputation abuse) | `developers.google.com/search/docs/essentials/spam-policies` |

When you cannot fetch a source, say the claim is unverified rather than asserting it. "I could not
confirm this against Google's current documentation" is a professional answer. A confidently wrong
deprecation claim is not.

---

## Phase 0 — Establish ground truth

Check whether `.agents/product-marketing-context.md` exists (or `.claude/product-marketing-context.md`).
Read it before asking anything already answered there.

Then establish, and do not proceed without:

1. **Is the problem real?** If the complaint is a drop, confirm it is not noise, seasonality, or a
   measurement artifact before spending any effort on causes. See the decision tree in
   `references/diagnostics.md`. A large share of "traffic drops" are tracking breakage or
   preliminary data.
2. **What access exists?** Search Console, analytics, server logs, CMS, deploy history. Your
   diagnostic ceiling is set here. Without GSC you are inferring; say so in the report.
3. **What changed and when?** Deploys, migrations, redesigns, CMS/plugin updates, CDN or WAF config,
   robots.txt edits. Build a dated timeline. Most self-inflicted damage is traceable to a date.
4. **What actually matters to the business?** Which pages and queries carry revenue. This determines
   priority later; without it every finding looks equally urgent.

---

## Phase 1 — Gather evidence

Collect data before forming opinions. Use the bundled tool:

```bash
node scripts/seo-check.mjs https://example.com            # page signals, redirect chain, JS verdict
node scripts/seo-check.mjs https://example.com --robots   # RFC 9309 correct robots analysis
node scripts/seo-check.mjs https://example.com --sitemap  # sitemap index walk, limits, hreflang alts
node scripts/seo-check.mjs https://example.com --ai-bots  # which AI bots are allowed, grouped by role
node scripts/seo-check.mjs https://example.com --json     # machine-readable for bulk work
```

It reports what it cannot see. Respect that section — it is the guard against false negatives.

**The escalation rule.** Raw HTTP fetching, `curl`, and `WebFetch` see pre-JavaScript HTML only, and
`WebFetch` additionally strips `<script>` tags, so it can never see JSON-LD. On any page that is not
confirmed server-rendered, "no schema found," "no title," "no canonical," and "thin content" are
**false negatives until proven otherwise**. Escalate to a headless browser, the Rich Results Test, or
Search Console's URL Inspection rendered view before reporting any of them.

Full acquisition procedures, API calls, log analysis, and bot verification:
[`references/evidence-gathering.md`](references/evidence-gathering.md).

---

## Phase 2 — Diagnose before you audit

If there is a symptom, work the decision tree in `references/diagnostics.md`. It is ordered
cheapest-first and each node carries rule-in and rule-out evidence, so whole branches get eliminated
early. The order matters: measurement artifacts and manual actions are near-free to check and
invalidate everything downstream.

The discipline that separates a diagnosis from a guess is **stating what would prove you wrong**.
For every hypothesis, name the evidence that would rule it out, then go look for that evidence.

Two failure modes to actively resist:
- **Coincidence as causation.** A migration and a core update landing the same week is the classic
  trap. Segment by page type and query to see which pattern the losses actually follow.
- **Narrative lock-in.** Once a wrong cause is presented to stakeholders it takes months to unwind.
  Hold the diagnosis loosely until the evidence is unambiguous, and say which parts are inference.

---

## Phase 3 — Systematic passes

Run these as *questions to answer with evidence*, not boxes to tick. Priority order reflects
dependency: nothing below matters if the layer above it is broken.

### 1. Can it be crawled and indexed?

- Does robots.txt block anything that should rank? (Longest-match wins, not first-match — the tool
  handles this; hand-reading robots.txt is a common source of wrong conclusions.)
- Is anything important carrying `noindex`? Check for template inheritance — a directive meant for
  one section leaking site-wide is a recurring incident pattern.
- **The robots.txt + noindex contradiction:** if a URL is blocked in robots.txt, Google never crawls
  it, never sees the `noindex`, and the URL can stay indexed indefinitely. To deindex: allow
  crawling, let `noindex` propagate, then block if desired. This one is a genuine bug, not a
  false positive.
- Do canonicals resolve correctly, self-reference where appropriate, and never point cross-locale?
- Is the sitemap accurate, current, and free of non-canonical or non-indexable URLs?
- Is a WAF, CDN, or security plugin returning 403s to crawlers? This is invisible from a browser
  and increasingly the actual cause. Check logs, not assumptions.

Crawl budget is a real constraint only on large sites (roughly 10k+ URLs updated daily, or 1M+
weekly). Below that, "block crawlers to save crawl budget" removes pages from consideration for no
benefit. Do not recommend it.

### 2. Is the site technically sound?

- Redirect chains, loops, and status-code correctness (301 vs 302 vs 308; 404 vs 410 vs soft-404).
- Is content server-rendered? For classic Google this affects render-queue latency; for AI answer
  engines it is closer to binary (see AI section).
- Core Web Vitals **from field data (CrUX)**, not a Lighthouse score. LCP, INP, CLS. INP replaced
  FID in March 2024. A poor lab score alongside healthy field data is not a finding.
- HTTPS integrity, mixed content, host consistency (www, protocol, trailing slash).

Be honest about effect size: Core Web Vitals is a real but small ranking input. Do not sell a
performance project as a ranking fix when the actual problem is content or intent.

### 3. Is the page targeting the right thing?

- Does the SERP for the target query show the content type this page is? Intent mismatch is
  unfixable by on-page polish — only realignment fixes it.
- Are title, H1, URL, and body aligned to one clear primary target?
- Is another page on the site competing for the same intent? Cannibalization requires **measurable
  harm** (URLs trading positions, neither reaching page one), not merely overlapping keywords.

### 4. Does it deserve to rank?

- **Assess two separate things.** Page Quality is query-independent (is this trustworthy,
  substantive, well-sourced, credibly authored?). Needs Met is entirely query-dependent (does this
  actually satisfy the searcher?). A page can be excellent and still be the wrong answer. Auditing
  only one conflates two independent failure modes and misdirects the fix.
- E-E-A-T is not a score Google computes. Audit it as artifacts a human reviewer could find:
  named authors with verifiable credentials, sourcing, original data or first-hand experience,
  clear ownership and contact details, reputation off-site.
- Quality signals operate site-wide. Thin sections can suppress strong pages, which is why "delete
  or improve the weak stuff" is sometimes the highest-leverage content recommendation.
- Before recommending deletion of thin pages, check traffic, conversions, and backlinks. Short
  and low-value are different axes.

If remediation involves **drafting or rewriting page copy**, load
[`references/ai-writing-detection.md`](references/ai-writing-detection.md) first and read its framing
section. It is an editorial checklist for avoiding generic filler prose, not a ranking factor, and it
must never be presented to a client as an SEO fix.

---

## AI and LLM search visibility

Treat this as two separate problems. Conflating them produces useless advice.

### Retrievability — can the machine get your content at all?

This is technical and largely binary. Failures here make everything else moot.

- **Bot roles are not interchangeable.** Operators ship distinct user-agents for *training*,
  *live retrieval*, and *search-index building*. Blocking a training crawler does not affect
  citations. Blocking the index/search crawler removes you from that platform's answers entirely.
  Audit each token separately; check what is actually in robots.txt with `--ai-bots` rather than
  assuming intent matched implementation.
- **Most AI crawlers do not execute JavaScript.** Google is the exception, because its AI surfaces
  ride the Googlebot index and its rendering service. For the others, client-rendered content is
  effectively invisible no matter how permissive robots.txt is. Server-render or pre-render is the
  fix, and it is a prerequisite, not an optimization.
- **Blocking often happens outside robots.txt.** CDN bot-management defaults, WAF rules keyed on
  user-agent strings, and CMS security plugins block AI crawlers silently and without the owner's
  knowledge. Verify at the edge and in logs, not just in the file.
- **Snippet controls affect AI features.** Because AI summaries draw on snippet-eligible content,
  `nosnippet` and restrictive `max-snippet` suppress eligibility; `data-nosnippet` scopes this to
  regions of a page. Check these before concluding a site was excluded for quality reasons.
- **Do not assume Google-Extended is an AI Overviews opt-out.** Google describes it as governing
  training *and grounding in some of its other systems*, which is genuinely ambiguous rather than a
  clean separation, and AI Overviews are generated from the standard Search index that Googlebot
  builds. Blocking Google-Extended is widely and confidently described online as a way to exit AI
  Overviews; that claim is not supported by a clear Google statement. **VOLATILE — fetch**
  `developers.google.com/search/docs/appearance/ai-features` and read the current wording before
  advising a client in either direction. If you cannot fetch it, say the control surface is
  unconfirmed rather than picking an answer.

### Citability — will it be chosen and quoted?

Weaker evidence base. Be candid about that rather than presenting tactics as proven.

- **Ranking is no longer a proxy for being cited.** The overlap between classic top-10 results and
  AI citations has fallen substantially. A site can rank first and go uncited, or be cited without
  ranking. Measure both.
- **Retrieval is passage-level.** A page is pulled for a specific chunk that answers a specific
  sub-question, not as a whole document. Self-contained sections that answer one question completely
  are more retrievable than the same information spread across a narrative.
- **Off-site consensus appears to matter more than on-page polish.** Being described consistently
  across many independent third-party sources is the more plausible lever. This makes AI visibility
  substantially a PR and reputation problem, not only a content problem.
- **The best-controlled evidence available finds formatting-only edits have little effect.** Adding
  tables, headers, or schema without adding information is not a citation strategy. Structure aids
  extractability; it does not manufacture selection. Treat vendor claims of large percentage lifts
  from formatting as marketing until shown a disclosed methodology.
- **llms.txt has no credible evidence of being used by AI search crawlers.** Google has publicly
  rejected it and large-scale log studies show near-zero fetches. It is cheap, so it is defensible
  as a hedge, but presenting it as a meaningful visibility lever is wrong. Do not put it high in a
  priority list.

### Measurement honesty

AI referral traffic is structurally undercounted — a large share arrives with no referrer and lands
in "Direct." Search Console does not cleanly separate AI surfaces. Third-party AI-visibility trackers
disagree with each other substantially, and citations shown to a user are not a reliable record of
what a model actually retrieved. Report AI visibility with uncertainty bands and name the method
used. Do not present a vendor dashboard number as ground truth.

Platform-by-platform detail, bot roster, verification URLs, and the evidence review:
[`references/ai-search.md`](references/ai-search.md).

---

## Prioritize

Sort by **expected impact × confidence ÷ effort**. Never by tool severity label, and never by
category. A crawler's "Critical" has no relationship to business impact.

For every finding that survives, state:

- **Issue** — what is wrong, specifically
- **Evidence** — how you observed it, and at what tier (direct observation, first-party data,
  third-party inference, assumption)
- **Impact** — what it costs, tied to pages, traffic, or revenue where possible; say "unknown" if
  you cannot size it rather than inventing a number
- **Confidence** — how sure you are of the causal claim
- **Fix** — implementable detail: which template, which file, which selector, what acceptance
  criterion. A finding a developer cannot action is not finished work.

Group into **Fix now** (actively blocking crawl, indexation, or revenue), **Fix next** (real growth
levers), **Fix later** (valid but low leverage). If everything is high priority, you have not
prioritized.

---

## Suppress before reporting

Run this pass on every draft. Read [`references/false-positives.md`](references/false-positives.md)
before finalizing findings.

The short version of what not to report: self-referencing canonicals, intentional `noindex`,
`alt=""` on decorative images, duplicate meta descriptions on paginated or faceted URLs, sitemap
`priority`/`changefreq`, multiple H1s, URL length, keyword density, meta keywords, missing canonical
where there is no duplication risk, "Alternate page with proper canonical tag," low Lighthouse score
with healthy field data, and third-party authority scores treated as Google signals.

Also resist recommendations that cause damage: mass noindex, reflexive disavow, deleting converting
pages for being short, redirecting everything to the homepage, and panic-pruning during an update
before diagnosis.

---

## Output

**Executive summary** — the diagnosis in plain language, top issues, and what you could not
determine. Lead with the cause if there is one, not with a list.

**Findings** by area, each in the Issue / Evidence / Impact / Confidence / Fix format.

**Prioritized plan** — Fix now, Fix next, Fix later.

**Evidence gaps** — what access or tooling would raise confidence. Naming these is a feature, not
an admission.

Never lead with a single-day or single-week chart. Never present inference as measurement.

---

## References

- [`references/diagnostics.md`](references/diagnostics.md) — traffic-drop decision tree, Search
  Console data traps, index-status decoder, migration forensics, cannibalization, statistical honesty
- [`references/ai-search.md`](references/ai-search.md) — AI/LLM visibility playbook: bot roster and
  roles, platform differences, citation evidence review, measurement
- [`references/evidence-gathering.md`](references/evidence-gathering.md) — acquiring evidence: the
  script, CrUX/PSI, schema detection, log analysis, bot verification, change timelines
- [`references/false-positives.md`](references/false-positives.md) — the suppression catalog, dead
  myths, and harmful recommendations
- [`references/international-seo.md`](references/international-seo.md) — hreflang, locale
  canonicalization, international sitemaps
- [`references/ai-writing-detection.md`](references/ai-writing-detection.md) — patterns to avoid when
  drafting or rewriting content

## Related skills

- **programmatic-seo** — building pages at scale
- **schema-markup** — implementing structured data
- **site-architecture** — hierarchy, navigation, URL design
- **page-cro** — optimizing for conversion rather than ranking
- **analytics-tracking** — measurement setup
