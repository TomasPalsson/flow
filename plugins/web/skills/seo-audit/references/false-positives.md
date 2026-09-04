---
name: false-positives
description: What NOT to report in an SEO audit — the tool false-positive catalog, myths with evidence against them, and recommendations that actively cause damage. Load before finalizing any audit findings, as a suppression pass over the draft.
---

# False Positives, Myths, and Harmful Recommendations

## 1. Why suppression matters

An audit's credibility is spent, not earned, by volume. Every finding a reader has to evaluate and
reject costs trust; a report that lists thirty non-issues alongside three real ones trains the reader
to skim past all thirty-three. Engineering time is the same currency: a ticket filed for a
self-referencing canonical or an intentional `noindex` is an hour a developer will not spend on the
thing that is actually costing traffic. The dominant way audits fail is not missing a real problem,
it is reporting too many fake ones and burying the real ones underneath. This document is the
suppression pass: read it after drafting findings, before shipping them, and cut or downgrade
anything that matches a row below unless the "when it IS real" condition is met and you have
evidence for it.

## 2. The false-positive catalog

| Tool flags this | Why it is usually fine | When it IS actually real |
|---|---|---|
| Duplicate meta descriptions on paginated or faceted URLs | Near-duplicate, template-generated pages are expected by Google, and the description is not a ranking lever there; search engines commonly rewrite the snippet anyway | Duplication across otherwise-unique landing or product pages meant to rank independently for distinct queries |
| Missing alt on decorative images | `alt=""` is the correct, deliberate markup for dividers, background flourishes, and icons paired with adjacent text; this is different from a missing attribute and should never be flagged the same way | The image is content-bearing (product photo, infographic, diagram) and carries no alt text at all, which is both an accessibility gap and a lost Image Search opportunity |
| `noindex` directive present | Frequently a deliberate directive on filtered/faceted URLs, internal search results, or utility pages doing exactly what it was set up to do | `noindex` on a page that should be earning organic traffic (a canonical category or product page), especially if it looks inherited from a shared template rather than set intentionally |
| Low Domain Authority (Moz) / Domain Rating (Ahrefs), "toxic" backlink score | Third-party, vendor-defined metrics Google does not consume; "toxic" is a heuristic invented by the tool, not a Google classification | Rarely real as stated; a persistently very low third-party score alongside genuinely manipulative or purchased link patterns can co-occur with real manual-action risk, but the score itself is never the mechanism, the link pattern is |
| Generic "SEO score /100" | Proprietary, non-standardized, and inconsistent between tools grading the same page, because each invents its own arbitrary weighting with no external validity against actual rankings | Useful only as an internal nudge for content editors ("did you forget a description"), never as a diagnostic or a prioritization input |
| Lighthouse / PageSpeed score below threshold | A synthetic lab test on a simulated device under worst-case conditions, not what Google's ranking signal (CrUX field data from real users) reflects | The lab score diverges sharply and consistently from field data, or the score reflects a genuinely broken pattern (render-blocking resources, unoptimized images) rather than a device-emulation artifact |
| Self-referencing canonical flagged as an issue | Standard, Google-recommended practice; CMSs that auto-apply these site-wide are behaving correctly | The self-reference coexists with parameter or duplicate URL variants that should instead canonicalize elsewhere, meaning the self-reference is masking a real duplication problem |
| "Missing canonical" on every URL | Not every URL needs an explicit canonical; absence is not a defect when there is no duplication risk | Genuine near-duplicate variants exist (tracking parameters, session IDs, sort orders) with no canonical resolution, causing index bloat or ranking dilution |
| Sitemap `priority` / `changefreq` missing or inconsistent | Google has said plainly it ignores both fields; flagging them has no basis for Google traffic | Essentially never for Google; a vanishingly rare concern for some non-Google crawlers only |
| URL length warnings | Google has stated URL length is not a ranking factor; the observed correlation (short URLs on high-ranking pages) reflects that established, authoritative pages tend to have simple URLs, not that length causes rank | Excessive length or parameter stacking hurts SERP snippet readability and click-through, or signals a deeper templating/parameter-duplication problem underneath |
| Multiple H1 tags | Legal in HTML5 sectioning content and explicitly confirmed by Google as a non-issue | The multiple H1s reflect genuinely broken document structure that harms screen-reader navigation, which is an accessibility finding, not an SEO one |
| Missing meta keywords | Unused by any major search engine for two decades; pure checklist residue | Never real for SEO purposes |
| Keyword density outside an arbitrary target | No such target exists; Google has explicitly denied any "optimal density" concept | The pattern is severe enough to read as spam to a human reader, which is a content-quality signal, not a density threshold |
| Missing or incomplete schema treated as a ranking gap | Schema is confirmed not a direct ranking factor; its value is eligibility for a rich result and downstream click-through, not position | Absence of schema is costing eligibility for a specific rich-result feature that competitors currently win (see §7), which is a visibility/CTR case, not a rankings case |
| "Alternate page with proper canonical tag" reported as an error | This is Search Console correctly describing expected behavior: a duplicate or variant URL is canonicalizing to the right target and is not indexed under its own URL on purpose | The canonical target is wrong, or the page carrying this status was meant to rank independently and should not have been canonicalized away |
| "Crawled - currently not indexed" reported as an error | A normal Search Console status, not a Google error state; Google crawled the URL and, for now, chose not to index it, often because it judged the content low-value or duplicative relative to what it already has | The share of the site in this state is large and growing, or it is happening to pages that clearly deserve indexing (unique, valuable, well-linked), which points to a site-wide quality or duplication problem worth investigating |

## 3. The one that IS real and gets mis-filed as noise

Robots.txt blocking a URL that also carries `noindex` looks, at a glance, like harmless redundancy:
two different mechanisms both saying "don't index this." It is the opposite. The mechanism: a URL
blocked in robots.txt is never crawled at all, so Google never has the opportunity to read the page
and see the `noindex` tag on it. If the URL was already indexed before the block went up, it can
remain indexed indefinitely, because the only way Google learns to remove it is by crawling it again
and finding the directive. The fix is sequential, not simultaneous: allow crawling, let the `noindex`
propagate and the URL drop out of the index, then block in robots.txt afterward if you still want to
stop crawling it. Flag this prominently in any audit and do not fold it into the false-positive
catalog above. It is the one place in this document where a tool correctly surfacing "noindex present
but blocked" deserves to be treated as a real, often urgent, finding rather than suppressed.

## 4. Myths with the evidence against them

- **Keyword density has an optimal percentage.** Google (Mueller) has stated no such concept exists
  at Google; the metric persists because it is easy to quantify, not because it predicts rankings.
- **The meta keywords tag matters.** Confirmed dead as a ranking input for well over a decade; still
  on checklists out of institutional inertia only.
- **One H1 per page is required.** True under old HTML4 assumptions, false under HTML5 sectioning
  content; Google has stated multiple H1s cause no ranking problem.
- **Shorter URLs rank better.** Google has said URL length is not a ranking factor; the correlation
  reflects that established, authoritative pages tend to have simple URLs, not that shortening a URL
  helps it rank. The one narrow exception: Google may prefer the shorter of two near-duplicate URLs
  when picking which to treat as canonical, which is not a general ranking boost.
- **Sitemap `priority`/`changefreq` influence crawling or ranking.** Google has said it ignores both;
  only `lastmod`, when it is reliably accurate, gets any real use.
- **Alt text is a general web-search ranking lever.** Google treats alt text like ordinary page text
  and does not weight it separately for standard web search. It genuinely does matter for two
  independent reasons that should not be conflated with a web-search ranking claim: it is meaningfully
  used for Image Search specifically, and it is an accessibility requirement on its own merits.
- **Word count is a ranking factor, longer always wins.** Both Mueller and Danny Sullivan have stated
  there is no target word count; the historical correlation between length and rankings reflected
  comprehensiveness, not word count itself, and helped produce a wave of artificially padded content.
- **Schema markup directly boosts rankings.** Google has repeatedly denied this (Mueller, Sullivan:
  "no impact on ranking in web search"), and that denial is the load-bearing evidence here. A
  controlled matched-pages study reporting no ranking uplift from adding schema was also referenced
  during this skill's research, but it was not traced to a named author, publication, or URL, so do
  not cite it to a client as though it were a specific paper. Rest the argument on Google's own
  stated position plus the confound described in the correlation section, and if a client wants
  study-grade evidence, go find and read the primary source first.
- **Domain Authority / Domain Rating are Google ranking signals.** This is the one myth that needs a
  precise, two-part statement, because getting either half wrong is a credibility failure. Moz's
  Domain Authority and Ahrefs' Domain Rating are third-party products built from each vendor's own
  link graph and its own arbitrary scoring formula; Google does not consume either score, and Google
  spokespeople have repeatedly denied using Moz's specific metric by name. That is not the same claim
  as "site-level authority does not exist inside Google." Google's own 2024 Content Warehouse API leak
  and 2023-24 DOJ antitrust testimony confirmed a real, internal, largely query-independent
  site-level authority signal (the `siteAuthority` field, referenced in testimony as "Q*") that
  functions as an input across a domain's pages. Both statements are true at once: "Google does not
  use Moz's DA" and "Google computes its own site-level authority score." The myth to correct is that
  Google reads a vendor's number, not that site-level authority is meaningless. DA/DR correlate with
  rankings because they proxy for the kind of link-based trust signals Google's own internal score
  does reward, not because Google reads the vendor's output.
- **"Toxic backlinks" require routine disavow.** Mueller has called "toxic links" a term "made up by
  certain SEO tools." Google's own systems already discount the overwhelming majority of
  spammy/low-quality links algorithmically; disavowing based on a vendor toxicity score risks removing
  links that were quietly passing value. Disavow remains genuinely useful only for cleanup after
  deliberate, large-scale manipulative link building, such as a past negative-SEO attack or an old
  black-hat campaign, not as routine hygiene.
- **A high Lighthouse/PageSpeed score is required for rankings.** Lighthouse is a lab/synthetic
  diagnostic; Google ranks using field data (CrUX) from real users. A low lab score alongside strong
  field data is not an SEO problem.
- **Crawl budget optimization matters for every site.** Google has stated crawling is independent of
  site size for the vast majority of sites; crawl budget is a real constraint only above roughly 1M
  pages updated weekly (or 10k+ daily), or where "Discovered, currently not indexed" is a large share
  of the site. Below that threshold, blocking crawlers to save crawl budget mostly removes pages from
  consideration for no offsetting benefit.
- **Bounce rate is a ranking factor.** Google cannot see a site's analytics account. The one real
  signal in this family is NavBoost's capture of pogo-sticking (quick return-to-SERP behavior) from
  Google's own click logs, which is not the same thing as a GA4 bounce-rate metric and should not be
  presented as one.
- **LSI keywords are a real SEO concept.** "Latent Semantic Indexing" keywords are a term invented by
  SEO tools and content marketers; the underlying academic technique (LSI) is not part of Google's
  ranking systems, and Google has never endorsed the practice of inserting "semantically related"
  synonyms as a distinct optimization tactic. Topical coverage matters; the LSI-keyword framing of it
  does not correspond to anything Google has confirmed using.

## 5. Correlation-versus-causation traps

Three patterns recur across the research, and all three share the same underlying confound: sites
that do one thing well tend to do everything well, so almost any quality-correlated metric will show
a positive relationship with rankings whether or not it causes anything.

- **Core Web Vitals correlate with rankings.** Every major controlled study (2021-2022, using the
  now-retired FID metric) found CWV correlated with rankings but was "not a large ranking factor,"
  with content, links, and intent dominating. The confound: sites with the engineering investment to
  hit good CWV scores also tend to have better content, better technical hygiene, and stronger link
  profiles across the board. No published study has cleanly re-isolated the correlation using INP.
  Report CWV findings as "this correlates; the causal ranking claim is not established at meaningful
  magnitude," not as a rankings fix.
- **Word count correlates with rankings.** Older studies found longer content ranking higher on
  average. The confound: comprehensive, well-researched content is naturally longer, and
  comprehensiveness is what Google's systems actually reward. Padding a page to hit a word count
  target adds length without adding the comprehensiveness that produced the original correlation.
- **"Pages with schema rank better."** Sites sophisticated enough to implement schema correctly also
  tend to have better information architecture, more engineering investment, and more mature content
  operations generally. Schema correlating with better rankings is therefore expected even if schema
  does nothing causally. Google's own repeated statement that schema does not affect web-search
  ranking is the evidence that settles this; the correlation never could.

The house style for all three: say "this correlates, the causal claim is not established," name the
plausible confound, and do not let a correlation stand in for a mechanism in a finding you ship.

## 6. Recommendations that cause damage

- **Mass or blanket noindex.** A documented incident: a developer accidentally pushed `noindex` to
  every page in a deploy, costing roughly a third of organic traffic; recovery required detecting the
  error, reverting the tag, and waiting for re-crawl and re-indexation. The recurring root cause is
  template inheritance: a directive intended for one section (a staging path, an internal search
  results template) leaks to child or category pages that share the same template, silently
  deindexing revenue pages nobody meant to touch. Any recommendation to noindex a URL pattern needs
  page-by-page verification of what actually inherits that template before it ships.
- **Reflexive disavow based on vendor toxicity scores.** Removing links because a tool assigned them a
  "toxic" score, without manual review, can strip links that were passing real value; the net effect
  is usually neutral at best and can be negative, and is essentially never clearly positive outside a
  genuine manipulative-link cleanup scenario.
- **Deleting "thin" pages without checking traffic, conversions, and backlinks first.** Word count and
  business value are different axes. A short page that converts, or that carries inbound links, is a
  candidate for improvement or merging with a stronger page, not deletion. Bulk deletion driven purely
  by a word-count threshold is one of the most commonly cited audit-driven mistakes, because it
  destroys assets (rankings, link equity, conversion paths) that a five-minute data check would have
  flagged as valuable.
- **Redirecting all removed URLs to the homepage.** This produces a soft-404 pattern: Google devalues
  the redirect because the destination is topically unrelated to the original URL, any inbound link
  equity the removed page held is effectively wasted rather than transferred, and the user lands
  somewhere irrelevant to what they clicked. The correct pattern is per-URL: a real 404/410 if the
  content is genuinely gone, a specific redirect to the actual replacement if the content moved, or
  restoration if it should still exist.
- **Blocking crawlers to "save crawl budget" on sites below the size where budget binds.** For the
  large majority of sites, well under the roughly 10k-pages-updated-daily or 1M-pages-updated-weekly
  thresholds Google has named, this recommendation removes pages from the index with no offsetting
  benefit, because crawl budget was never the binding constraint to begin with.
- **Panic-pruning during an algorithm update, before diagnosis.** Reactive content removal driven by
  update-week anxiety, done before establishing what actually changed, risks deleting pages that were
  not the actual cause while destroying backlinks, rankings, and historical signal that might have
  recovered on their own. Diagnose first; prune only what the evidence implicates.

## 7. Structured data specifics

Rich-result types get retired on a rolling basis, and Google has already shown it will reverse a
deprecation (a retired type un-retired months later). Do not hardcode a list of which types are
currently live or dead in an audit; it will be wrong within a quarter. Before recommending any
schema type, verify its current status against Google's search-gallery documentation at
`developers.google.com/search/docs/appearance/structured-data/search-gallery`. If a type has no live
entry there, implementing it produces zero SERP payoff no matter how correctly it validates.

The anti-patterns below are durable, unlike the type list, because they are about how markup is
built rather than which types Google currently rewards:

- **Markup that does not match visible content.** This is a manual-action risk under Google's
  structured-data policy, not merely a warning. Examples include marking up reviews, events, or
  ratings that are not genuinely present on the page. A manual action removes rich-result eligibility
  for the affected section or the whole site until a reconsideration request is filed and approved,
  which makes this a materially higher-severity finding than a validation warning.
- **Multiple plugins emitting conflicting duplicate `@graph` blocks.** Common on WordPress stacks
  running more than one SEO plugin (Yoast, RankMath, AIOSEO) alongside a theme's own JSON-LD, each
  outputting its own `Organization` or `Article` node with different property values. This does not
  itself trigger a manual action, but it dilutes signal quality and leaves it unclear which values
  Google actually trusts. The fix is deconfliction: disable schema output in all but one source.
- **Article schema on non-article pages.** The most common real-world misapplication: category pages,
  product listings, or plain marketing landing pages tagged `Article` because a CMS or plugin defaults
  to it regardless of actual content type. Google's guidance is explicit that markup must represent
  the page's actual primary content; a divergence between the JSON-LD `headline` and the visible `H1`
  is flagged as a signal-inconsistency issue, not just a stylistic slip.
- **Marking up content that is not on the page.** Distinct from the mismatch case above in that this
  is often deliberate: adding ingredient lists, FAQ pairs, or ratings purely to chase rich-result
  eligibility, with no corresponding visible text on the page. This is explicitly named in Google's
  spam-policy guidance as "spammy structured data" and carries the same manual-action exposure as
  markup/content mismatch generally.

## 8. Vendor statistics hygiene

Marketing-adjacent SEO content circulates a large volume of precise-sounding statistics with no
disclosed methodology behind them. Before citing any such number in a finding, check:

- **Who published it, and do they sell a product that benefits from the conclusion.** A tool vendor
  publishing a study that validates its own scoring methodology, or an agency publishing a case study
  that recommends the service it sells, is not disqualifying on its own but raises the bar for
  independent corroboration before the number goes in a client-facing report.
- **Is the methodology disclosed.** Sample size, control group, date range, and how the effect was
  isolated from confounds. A number with none of these is not verifiable and should not be treated as
  fact.
- **Has anyone independently replicated it.** A single vendor blog post citing "our data" is a
  different evidentiary tier than a finding corroborated across multiple independent sources, or one
  confirmed directly by a Google spokesperson or primary documentation.
- **Is the precision itself a red flag.** A marketing claim citing a correlation coefficient to two
  decimal places, or a specific percentage lift ("schema increases citations by 40%"), with no
  methodology attached, is a stronger signal of unearned confidence than of a real measurement.
  Treat suspiciously precise numbers in vendor content as a reason for more scrutiny, not less.

The governing rule: prefer mechanism over effect size whenever the effect size is not independently
verified. "AI crawlers do not execute JavaScript, so client-rendered content is invisible to them" is
a claim you can ship with confidence because it describes a mechanism. "Schema lifts AI citations by
40%" is not, because it is an unverified number standing in for a mechanism nobody has demonstrated.
Where the underlying research explicitly flagged a statistic as anecdotal or unverified, either drop
it from the audit entirely or label it plainly as an industry talking point, never as a citable fact.

## 9. The triage discipline

Experts do not prioritize by what the tool calls severe. The discipline that separates a useful audit
from a dumped findings list:

- **Score by impact times confidence, divided by effort**, not by a tool-assigned Critical/Warning/
  Notice label. A crawler's severity tag reflects how the tool's author categorized the check, not
  what the finding costs the business.
- **Tie every retained finding to a business number**, traffic at risk, a revenue-bearing template
  affected, or a conversion path implicated, or mark impact honestly as unknown. "Unknown" is a valid
  and professional answer; a fabricated number is not.
- **Ship engineering-ready detail.** A finding without a template, file path, selector, or acceptance
  criterion is not a finished finding, it is a wish. The gap between "audit shipped" and "fix shipped"
  is where most audits actually die, and specificity is what closes it.
- **Verify after shipping.** Re-crawl and re-measure once a fix is live. An audit is not complete at
  delivery, it is complete when the fix is confirmed live and its effect has been measured.

If everything in the report is high priority, nothing has been prioritized. A report that cannot say
which three things to fix first has not done the job an audit exists to do.
