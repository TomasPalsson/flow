---
name: ai-search
description: AI and LLM answer-engine visibility playbook — crawler roles and the training vs retrieval vs index split, JavaScript rendering limits, platform-by-platform retrieval differences, what the evidence actually supports about citation, and how to measure AI visibility honestly. Load when auditing visibility in ChatGPT, AI Overviews, Perplexity, Copilot, or Claude, or when advising on blocking AI crawlers.
---

# AI Search Visibility

This is the depth layer behind SKILL.md's AI section. Read that first for the two-question frame
and the top-level rules; this file carries the bot roster, the platform mechanics, and the evidence
review needed to back a specific finding with something better than a vendor blog post.

## 1. Two separate questions, two different evidence qualities

**Retrievability**: can the machine physically fetch and parse your content? This is engineering
fact: HTTP status codes, robots.txt tokens, whether HTML contains the text before JavaScript runs.
Near-certain once observed. An audit can state retrievability findings with high confidence.

**Citability**: once retrievable, will a given passage be selected and quoted in an answer? This is
a retrieval-and-reranking problem inside someone else's black-box pipeline, studied mostly by
vendors who sell AI-visibility dashboards. Evidence here ranges from one large rigorous study down to
undisclosed-methodology marketing content. An audit must grade its confidence explicitly, every time.

Do not let a retrievability finding (verified, binary, yours to fix) get diluted by a citability
claim (contested, probabilistic, largely outside your control) in the same breath. Report them
separately, and say which kind of claim you are making.

---

## 2. The bot role table

**Dated snapshot: verify before shipping any of this to a client.** Bot rosters gain new
user-agents, IP ranges rotate, and compliance behavior changes. This table reflects research current
to 2026-08-15. Re-fetch the primary URLs below before treating any row as current:

- `https://developers.openai.com/api/docs/bots`
- `https://support.claude.com` (search "crawling" / bots.json)
- `https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers`
- `https://developer.amazon.com/amazonbot`
- Cloudflare's community-maintained `ai.robots.txt` list on GitHub, for the long tail

**The single most important teaching point in this document:** blocking a TRAINING bot does not
affect citations. Blocking the INDEX/SEARCH bot removes you from that platform's answers entirely.
These are separate user-agent strings by design, precisely so a publisher can choose one without the
other. Confusing them is the most common and most consequential AI-crawler audit mistake.

| User-agent | Operator | Role | Honors robots.txt | What blocking it actually costs you |
|---|---|---|---|---|
| GPTBot | OpenAI | Train | Yes | Nothing for ChatGPT Search or citations: only future model-training inclusion |
| OAI-SearchBot | OpenAI | Index-citations (builds ChatGPT Search corpus) | Yes | Removed from ChatGPT Search answers/citations |
| ChatGPT-User | OpenAI | Live-retrieve (user- or agent-triggered fetch) | **No**: OpenAI states robots.txt rules may not apply | ChatGPT can't fetch a page a user pastes or an agent action requests live |
| OAI-AdsBot | OpenAI | Narrow: validates submitted ad landing pages | Not documented | Ad-safety checks fail for that landing page only |
| ClaudeBot | Anthropic | Train | Yes | Nothing for Claude's search/citations: only future training inclusion |
| Claude-SearchBot | Anthropic | Index-citations (Claude's search/answer corpus) | Yes | Removed from Claude's web-search-grounded answers |
| Claude-User | Anthropic | Live-retrieve (user-question-triggered fetch) | **Yes**: Anthropic honors robots.txt here too, unlike OpenAI's and Perplexity's equivalents | Claude can't fetch a page a user is actively asking about |
| Googlebot | Google | Index (Search, and the shared base AI Overviews/AI Mode draw from) | Yes | Removed from Google Search entirely, and from AI Overviews/AI Mode since they draw on the same index |
| Google-Extended | Google | Train (control token, not a separate fetcher; piggybacks on Googlebot's crawl) | Yes | Opts out of the training/grounding use Google names; **its exact reach into AI Overviews is not clearly settled: see §3** |
| Google-CloudVertexBot | Google | Live-retrieve (site owner's own Vertex AI Agent workflows) | Yes | Breaks the site owner's *own* Vertex AI Agent workflow: not a third-party visibility issue |
| PerplexityBot | Perplexity | Index | Yes, per Perplexity's own docs | Not indexed/citable in Perplexity answers |
| Perplexity-User | Perplexity | Live-retrieve | **Disputed**: Perplexity argues it is "an agent, not a bot"; Cloudflare's Aug 2025 investigation found stealth UA/ASN rotation evading declared blocks, and formally delisted Perplexity as a Verified Bot on Aug 4 2025 over it | Little reliable control via robots.txt alone; treat as edge/WAF-level enforcement only |
| Bingbot | Microsoft | Index (Bing Search; the same crawl grounds Copilot) | Yes | Removed from Bing Search **and** Copilot, since Copilot is grounded on the Bing index |
| BingPreview / AdIdxBot | Microsoft | Preview render / ad validation | Yes | Narrow: link previews or ad checks fail |
| Applebot | Apple | Index (Siri, Spotlight, on-device search) | Yes | Removed from Siri/Spotlight web results |
| Applebot-Extended | Apple | Train (Apple Intelligence), independent token | Yes | Only opts out of Apple's AI training corpus; Applebot indexing continues regardless |
| Meta-ExternalAgent | Meta | Train (Llama/Meta AI corpus) | Yes, documented | Opts out of Meta AI training corpus only |
| Meta-ExternalFetcher | Meta | Live-retrieve (user-triggered link fetch in Meta AI) | May bypass robots.txt for user-provided URLs, per Meta's own docs | Little reliable robots.txt control; server-level blocking needed |
| Meta-WebIndexer | Meta | Index (citations/links in Meta AI) | Documented as robots.txt-governed | Removed from Meta AI's cited/linked responses |
| Amazonbot | Amazon | Train + general crawl | Yes (no Crawl-delay support) | Opts out of Amazon AI training use |
| Amzn-SearchBot | Amazon | Index (Alexa/Amazon search experience): Amazon states this bot does not train generative models | Yes | Removed from Alexa/Amazon search-experience surfaces |
| Amzn-User | Amazon | Live-retrieve (Alexa live queries) | Yes | Alexa can't answer a live query needing current page content |
| Bytespider | ByteDance | Train + broad crawling | **Documented as ignoring robots.txt** | Robots.txt gives little control; needs server/WAF-level blocking |
| CCBot | Common Crawl | Index/train-source (feeds the open corpus many labs draw from) | Yes | Excludes future crawls; does **not** retroactively remove archived data (archives run back to 2007) |

One structural note that recurs across every operator with a search product: the split exists
because publishers asked for it. Treat "block training, allow search/retrieval" as the default
sensible position for a site that wants citation traffic without contributing to model training,
feasible for OpenAI, Anthropic, Amazon, Google, and Apple, all of which expose the split cleanly.
Meta and Perplexity are the exceptions: their live-retrieval fetchers are documented or disputed as
not honoring robots.txt, so the clean split doesn't fully hold for those two.

---

## 3. The audit procedure for "should we block AI crawlers"

Do not answer this with an opinion. Run the procedure.

**Step 1: establish what the business actually wants.** These are three different asks, and they
map to different tokens:
- *Opt out of AI training* → block the training bots (GPTBot, ClaudeBot, Google-Extended,
  Applebot-Extended, Amazonbot, Meta-ExternalAgent, CCBot). No effect on citations.
- *Control citation/answer visibility* → the lever is the index/search bots (OAI-SearchBot,
  Claude-SearchBot, PerplexityBot, Bingbot, Amzn-SearchBot). Blocking these removes you from that
  platform's answers; this is rarely what a business actually wants, but it's what accidental
  blanket blocks produce.
- *Control scraping cost / server load* → this is an infrastructure question, not a visibility one,
  and the right tool is rate-limiting or WAF rules keyed to verified IP ranges, not a blunt
  robots.txt disallow that also forfeits citation eligibility.

Naming which of these three the stakeholder actually wants is the step audits skip, and it's the
step that determines every downstream recommendation.

**Step 2: map the want to the specific token.** Use the table in §2. Confirm the exact user-agent
string, not the vendor name: "block OpenAI" is not a robots.txt instruction, "block GPTBot but
allow OAI-SearchBot" is.

**Step 3: verify what robots.txt actually does.** Matching is longest-match-wins, not first-match,
and `Allow` wins ties at equal specificity (RFC 9309). A blanket `Disallow: /` written years before
any AI bot existed will silently catch every one of them unless a more specific `Allow` rule for the
wanted bot sits below it. Hand-reading a robots.txt file for this is unreliable; use the bundled
`--ai-bots` check (see SKILL.md Phase 1) to see what is actually allowed, grouped by role, rather
than assuming intent matches implementation.

**Step 4: check the edge, because that's where silent blocks happen.** CDN bot-management defaults,
WAF rules keyed on raw user-agent string matching, and CMS security plugins (Wordfence, Sucuri-class
tools) commonly block AI crawlers with no site-owner decision behind it and no visibility from
robots.txt alone. CDN/WAF bot-management postures and defaults change on their own schedule and
without the site owner's involvement: do not assume last year's configuration, or a blog post's
description of a vendor's default, still holds. Pull the actual current dashboard configuration and
the vendor's current published policy before concluding anything about what's blocked at the edge.

**Step 5: check logs to confirm what bots really received.** The edge configuration is a stated
policy; server/CDN access logs are what actually happened. Grep for the user-agent strings from §2
and check response codes: a 403 in the logs for a bot that robots.txt and the dashboard both claim
to allow means something else in the stack (a plugin, a rate limiter, a stale cache rule) is doing
the blocking.

**A caveat that changes what "verify" means for some operators:** Perplexity-User is disputed and
ChatGPT-User and Meta-ExternalFetcher are documented as potentially bypassing robots.txt outright,
and Bytespider is documented as ignoring it. For these, robots.txt is a courtesy signal at best:
real enforcement requires server-side 403s or rate-limiting keyed to verified IP ranges, not a
disallow rule. Say this explicitly in any finding that recommends "add a robots.txt rule" for one of
these operators; the recommendation may not actually work.

---

## 4. JavaScript is the hard floor

Non-Google AI crawlers fetch raw HTML. They do not execute JavaScript. This is confirmed directly
against Vercel's "Rise of the AI Crawler" data: GPTBot fetches JS files on roughly 11.5% of requests
and ClaudeBot on roughly 23.8%, but neither one *runs* what it fetches. PerplexityBot and Amazonbot
are documented the same way. Google is the outlier, and only because its AI surfaces (AI Overviews,
AI Mode, Gemini grounding) ride on the same Googlebot index and Web Rendering Service that classic
Search already uses: Google is not doing anything special for AI, it's reusing infrastructure that
already renders JS.

**Consequence:** content that only exists after client-side hydration (a React/Vue/Angular SPA with
no server rendering) is invisible to ChatGPT, Claude, Perplexity, and most others, regardless of
what robots.txt says. This is binary, not a gradient: robots.txt controls whether the bot is allowed
to fetch a URL; it says nothing about whether the bot can read what's inside the response body once
it does.

**Diagnostic.** View the raw HTML the server actually returns: `curl`, `WebFetch`, or the tool's
`--ai-bots`/render check, not a browser DevTools view, which shows the post-hydration DOM and will
mislead you. Look for:
- Real content in the initial response, or an empty (or near-empty) root `<div id="root">` /
  `<div id="app">` with everything else in a JS bundle
- Presence of SSR/SSG markers: pre-rendered text matching what a user sees, meta tags and JSON-LD
  present in the raw response rather than injected post-load
- Whether the framework in use (Next.js, Nuxt, SvelteKit, Remix, plain CRA) is configured for
  server rendering or is shipping a client-only build

Any "no schema found," "no title," or "thin content" conclusion drawn from a raw-HTML fetch on a
page that isn't confirmed server-rendered is a false negative until proven otherwise: escalate to a
headless browser before reporting it (see SKILL.md's escalation rule).

**Fix hierarchy, in order of preference:** SSR or SSG (content is genuinely in the initial response)
> prerendering (a rendering service snapshots the post-JS DOM and serves that to bots) > nothing
(accept that CSR content is invisible to every non-Google AI surface). This is usually the
highest-leverage single finding in an AI-visibility audit, because it is binary, verifiable in
minutes, and often affects the entire site rather than one template.

---

## 5. Platform differences

Backing index, how citations get selected, and the mechanics that make "optimizing for AI search" a
different exercise per platform.

| Platform | Backing index/retrieval | Citation selection | Notable mechanics |
|---|---|---|---|
| **Google AI Overviews** | Google's own Search index (Googlebot) | Drawn from content already retrieved/ranked by classic Search; "grounded by design," no separate fan-out layer | Snippet-eligibility controls (`nosnippet`, `max-snippet`, `data-nosnippet`) gate inclusion the same way they gate classic snippets |
| **Google AI Mode** | Same underlying index, plus live signals (Shopping Graph, Knowledge Graph, live data) | A dedicated Gemini instance decomposes the query into parallel sub-queries ("fan-out"), each retrieved and ranked separately, then synthesized | The fan-out step is the structural difference from AI Overviews: a query can retrieve dozens of sub-results even though the user sees one answer |
| **ChatGPT Search** | Routes through Bing's index for the default browsing path, plus OpenAI's own OAI-SearchBot-built corpus and direct publisher-licensing content | Non-browsing (default/parametric) mode has **no live citations at all**: anything citation-shaped is pattern completion, not retrieval | **Critical testing caveat:** testing "does ChatGPT cite us" without confirming the query actually triggered browsing produces a meaningless result. Publisher partnerships (AP, Reuters, and others per OpenAI's own announcements) grant paid preferential citation placement, a channel outside organic optimization entirely |
| **Perplexity** | Own hybrid retrieval, not disclosed in detail; heavy live web fetch | Practitioner-described as gated pass/fail stages (relevance, authority, freshness, corroboration, structure) rather than a single graduated score | Has a formal Publishers' Program (revenue share); least robots.txt-reliable major operator (see §2/§3) |
| **Microsoft Copilot** | Bing index/live web | Same crawl and ranking signals that power Bing Search itself | Optimizing for Bing Search **is** optimizing for Copilot: there is no Bing-Extended-style split the way OpenAI/Anthropic separate train from search |
| **Claude** | Web search is an explicit, model-decided tool call, not default-on | Model issues a search, can iterate with refined follow-up queries if initial results are insufficient | Tends to answer from parametric knowledge first; treat "is Claude citing us" tests the same way as ChatGPT: confirm the tool call actually fired before concluding anything from a non-search answer |
| **Grok (xAI)** | Own web index plus a live X/Twitter post stream | DeepSearch mode does multi-pass cross-referencing | Only major platform that cites live social-media posts as first-class sources alongside web content: a brand's on-site optimization has limited reach here if the query space is dominated by real-time social discourse |

The Google AI Overviews / AI Mode split and the ChatGPT-Search-routes-through-Bing mechanic are the
best-corroborated facts in this table: each has a primary or near-primary source behind it. The
per-platform citation-count and dominant-source-domain figures that circulate in vendor content
(e.g., "ChatGPT cites 15 sources per answer") are single-vendor-sourced and should be treated as
approximate at best; do not repeat them as precise counts in a client-facing finding.

---

## 6. Citability: what the evidence actually supports

This area is dominated by vendor marketing selling AI-visibility-tracking subscriptions. The anchor
for this section is the highest-rigor study located: **arXiv:2605.25517, "What Gets Cited:
Competitive GEO in AI Answer Engines."** It ran 252,000 paired-comparison trials across six LLMs
testing 18 content factors: a scale and design that outclasses everything else in this literature.
Its finding: topical relevance and list position were the strongest drivers; formatting-only edits
(headers, tables, structure added without new information) had little impact.

**What has decent support:**
- Topical relevance and being genuinely retrievable at all: the dominant factors in the
  highest-rigor study available (arXiv:2605.25517).
- Passage-level self-containment: a mechanism-level implication of how retrieval actually works;
  see §7.
- Off-site corroboration across independent sources: multiple 2026 sources converge qualitatively
  on generative engines rewarding claims repeated across independent third parties over a single
  well-optimized owned page, though the strongest quantified version of this comes from a vendor
  (see below).
- Recency, where the underlying query is genuinely time-sensitive: plausible mechanistically and
  consistent with dynamic-retrieval behavior (§3, Gemini grounding), though exact recency-weighting
  figures are vendor-sourced and not independently audited.

**What is contested:**
- Schema's effect on citation. Google's own spokespeople have hedged or dismissed schema as a
  citation lever historically (schema is not a Google ranking factor, and no independent
  methodologically-sound study was found tying it to AI citation specifically). Bing's own guidance
  is more positive about structured-data signals. No independent, disclosed-methodology study
  resolves this either way: treat "schema drives AI citations" as unproven, not disproven.

**What the evidence contradicts:**
- Formatting-only edits producing large citation lifts. This is the headline finding of
  arXiv:2605.25517 and it directly contradicts the "add tables/headers for 2-3x citations" claims
  that circulate across SEO-vendor content. Structure aids extractability once content is being
  retrieved; it does not manufacture selection on its own.

**What is cargo cult:**
- llms.txt for search citation. Google has publicly stated it does not use it, and independent
  log-based studies (using different methodologies) widely report near-zero crawler fetches of
  the file in practice. This is corroborated across more than one independent measurement approach,
  though it was not re-verified against primary sources in this pass, so it is reported here as
  "widely reported" rather than independently confirmed. Its one genuine, confirmed use is unrelated
  to search: developer tools (Cursor, Windsurf, Claude Code and similar) use it as a
  manually-supplied context-loading convenience for API/reference docs: a different audience
  entirely from AI search crawlers. Do not put llms.txt creation high in a priority list; it is
  defensible only as a near-zero-cost hedge, never as a visibility lever.

**Ranking is no longer a reliable proxy for citation.** The overlap between classic top-10 rankings
and what gets cited in AI answers has fallen substantially over the past year: this direction is
well-corroborated across independent trackers (Ahrefs, seoClarity-adjacent sources, Originality.AI).
The exact percentages diverge meaningfully by methodology and study, so report the direction ("a
site can rank #1 and go uncited, and a growing share of citations come from pages that don't rank
top-10 at all") without repeating any single tracker's specific percentage as if it were a settled
figure.

**Foundational but historical: the original GEO paper.** arXiv:2311.09735 (Aggarwal et al., KDD'24)
is the paper the entire GEO/AEO industry cites for percentage-lift numbers on citing sources,
quotations, and statistics. It is a real, peer-reviewed paper: but its design optimized multiple
competing sources per query simultaneously, a disclosed confound that makes its individual-technique
effect sizes unreliable as clean causal estimates. Cite it, if at all, as the field's foundational
and historical reference point, not as current evidence for a specific percentage lift.

**Vendor research, named and hedged: Semrush's AI Visibility Index.** Built from 126 million AI
search prompts, Semrush's research found off-site brand mentions correlate more strongly with
citation than backlinks, Domain Authority, or schema markup, and reported per-platform average
source counts per response. This is vendor research from a company that sells AI-visibility tracking
tools: the finding directionally reframes GEO toward earned-media/PR-style presence and away from
on-page tactics, which is useful, but the exact numbers were not independently audited and should
not be quoted as precise measurements.

**Query fan-out sub-query counts** ("~16 typical, 50+ for complex queries" for Google AI Mode) trace
to press coverage of a single conference talk (Google I/O 2025), with no primary Google document
located confirming the figures. Use the mechanism (AI Mode decomposes a query into parallel
sub-queries; AI Overviews does not) with confidence; hedge the specific counts as press-relayed.

---

## 7. Passage-level retrieval and what it implies for content structure

Retrieval operates on chunks, not whole documents. A page gets pulled because one passage inside it
answers a specific sub-question well: via embedding similarity or a reranker's judgment on that
passage, not a holistic assessment of the page. The rest of the page can be entirely irrelevant to
why that one chunk was retrieved.

**Practical implication, stated as mechanism-derived and plausible rather than as a measured lift:**
a section that fully and self-containedly answers one question, with the answer positioned near the
top of that section, is more retrievable than the same facts distributed across a narrative that
requires reading several paragraphs to assemble the answer. This follows directly from how chunk-based
retrieval works: a chunking pipeline is more likely to produce a clean, complete, useful chunk from
a self-contained section than from prose that spreads one fact across multiple paragraphs and
sentences. Treat this as a structural recommendation grounded in mechanism, not as a claim backed by
a measured citation-rate improvement: no rigorous study in this evidence base isolates the effect of
content structure this way independent of topical relevance and list position (the two factors
arXiv:2605.25517 actually found to dominate).

---

## 8. Measurement honesty

Every method available for measuring AI visibility has a real, structural weakness. State the method
used with every number, and report ranges rather than point estimates.

- **A large share of AI referral traffic arrives with no referrer** and gets misattributed to
  "Direct" in standard analytics: mobile in-app browsers and copy-paste usage patterns strip
  referrer headers. Any AI-referral count pulled straight from GA4/analytics "Source/Medium" is an
  undercount, and the true undercount rate is itself only estimated, not precisely known.
- **Search Console does not separately break out AI Overviews or AI Mode as of this writing.** There
  is no native filter for AI-surface impressions or clicks. Any AI-visibility read from GSC is
  inference from indirect signals (e.g., changes in impressions for queries known to trigger AI
  Overviews), not a direct measurement. **VOLATILE: verify against
  `https://developers.google.com/search/docs/appearance/ai-features` and the Search Console
  Performance report's own "Search type" filter options before telling a client whether this exists**,
  since Google could ship a dedicated surface at any time, and conflicting claims about whether one
  already exists have circulated.
- **Vendor AI-visibility trackers disagree with each other substantially.** Different commercial
  tools measuring the same platform for the same brand report materially different citation counts,
  and run-to-run variance for the same tool can be high. Do not present a month-over-month trend from
  a single vendor dashboard as a stable signal without a second, independently-sourced check.
- **Citations shown to a user are not a reliable record of what a model actually retrieved and used.**
  Generative engines sometimes fail to cite sources they actually used in producing an answer: this
  undermines any citation-counting methodology as a complete measure of influence, including most
  vendor tools.

**Practical approach:**
1. Triangulate more than one method: analytics referrer patterns, a vendor tracker (labeled as
   such), and manual spot-checks (actually running representative queries against each platform with
   browsing/search confirmed active): rather than trusting any single source.
2. Report uncertainty bands ("roughly X-Y, based on referrer-pattern estimation") rather than a
   single confident number.
3. State the method used alongside every figure in a finding: a reader should be able to tell
   whether a number came from GSC, a named vendor tool, or a manual test.
4. Never present a vendor dashboard number as ground truth, even when it's the only number available;
   say so, and say what it doesn't capture.

**Approximating an AI-traffic segment in analytics:** build a referrer-pattern segment matching known
AI domains (`chat.openai.com`, `chatgpt.com`, `perplexity.ai`, `copilot.microsoft.com`,
`gemini.google.com`, and similar) in the analytics platform's referrer/source field. This captures
AI-driven sessions that *did* carry a referrer. What it misses: the no-referrer share discussed above
(likely the larger portion, direction-only estimate, not a precise fraction), any AI surface that
answers in place without ever sending a click (ChatGPT non-browsing answers, most AI Overview
impressions), and app-embedded AI experiences that don't pass a web referrer at all. State this gap
explicitly whenever this segment is used: it is a floor on AI-driven traffic, not a total.

---

## 9. Volatile facts: verify before shipping

Every claim in this document that moves on a timescale shorter than an audit cycle, paired with the
primary URL to re-fetch. Do not carry forward a number or a status from this document without
re-checking it live.

| Volatile fact | Why it moves | Verify against |
|---|---|---|
| Whether a dedicated Search Console AI-features reporting/opt-out surface exists | Contested even across the underlying research for this document; Google could ship this at any time | `https://developers.google.com/search/docs/appearance/ai-features`, and Search Console's own Performance report "Search type" filter |
| Google-Extended's precise scope (training only, vs. training + grounding + AI Overviews) | Google's own current wording ("training and grounding in some of Google's other systems") is already ambiguous and could be clarified or changed at any time | `https://developers.google.com/search/docs/appearance/ai-features` (search "Google-Extended") |
| AI crawler user-agent roster and robots.txt behavior, every operator | New bots ship, IP ranges rotate, compliance behavior (especially Perplexity, Meta, Bytespider) is actively disputed and evolving | `https://developers.openai.com/api/docs/bots`, `https://support.claude.com`, `https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers`, `https://developer.amazon.com/amazonbot`, the `ai.robots.txt` community list on GitHub |
| CDN/WAF bot-management defaults and posture toward AI crawlers (Cloudflare and others) | Postures and defaults change on the vendor's own schedule; do not assume last-known behavior still holds | The vendor's current bot-management dashboard configuration for the specific site, plus the vendor's current published policy page (e.g., Cloudflare's Content Signals Policy blog post and current bot-management docs) |
| Crawl-to-referral ratios per AI platform | Reported as moving fast month to month even in the underlying research; secondary-sourced, not a direct analytics-provider pull | A first-party crawler-analytics dashboard (e.g., Cloudflare Radar's AI crawler/referrer sections), pulled directly rather than via a blog aggregator |
| IETF AIPREF draft status (`Content-Usage` header / robots.txt extension) | Draft was already expired relative to the underlying research date; a newer revision almost certainly exists | `https://datatracker.ietf.org/doc/draft-ietf-aipref-attach/` |
| Query fan-out sub-query counts for Google AI Mode | No stable Google-published number located; existing figures are press-relayed from a single conference talk | Search `blog.google` and `developers.google.com` directly for current AI Mode / query fan-out documentation |
| Which structured-data/rich-result types are currently active vs. deprecated | Google has already reversed one deprecation after announcing it, and holds at least one type in an announced-but-not-executed "phasing out" state | `https://developers.google.com/search/docs/appearance/structured-data/search-gallery` and `https://developers.google.com/search/updates` |
| Any vendor AI-visibility statistic (Semrush, Ahrefs, or similar) | Recurring vendor research products, typically re-run and republished every few months with updated numbers | The vendor's own current report page, not a cached or previously-cited figure |
| Cloudflare's Perplexity Verified Bot delisting status | Confirmed as of Aug 4, 2025 in the underlying research; whether Perplexity's actual crawling behavior or Cloudflare's status decision has since changed is not confirmed | `https://blog.cloudflare.com` (search "Perplexity") and Cloudflare's current Verified Bots list |
