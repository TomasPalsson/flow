---
name: evidence-gathering
description: How to acquire real evidence during an SEO audit — the seo-check script, CrUX/PSI APIs, schema detection, cloaking and bot-verification checks, and the browser-escalation rule. Load when actively running an audit and you need to collect data rather than interpret it.
---

# Evidence Gathering

This is the acquisition layer: what command produces what data, and what you are and are not
entitled to conclude from it. Every finding gets labeled with the tier it came from.

## 1. The evidence hierarchy

1. **Direct observation** — you fetched, parsed, or measured it yourself right now (raw HTTP
   response, `seo-check` output, a rendered-DOM snippet, a log line).
2. **First-party tool data** — Search Console, CrUX, PSI/Lighthouse: Google's own telemetry.
   Authoritative for what it covers, silent on everything it doesn't.
3. **Third-party tool inference** — Screaming Frog, Ahrefs, rank trackers: someone else's crawler
   or model, built on assumptions you can't inspect. Useful for scale, never ground truth alone.
4. **Assumption / training knowledge / vendor claim** — anything believed rather than checked.
   Never state this as a finding; verify it up a tier or label it unverified.

Higher tiers override lower ones on conflict. Write findings as "direct fetch showed...", "CrUX
has no data for this URL, so this is origin-level..." — a finding with no tier is a guess wearing
a report's clothes.

## 2. Running `scripts/seo-check.mjs`

The primary Tier-1 instrument: raw HTTP, robots, sitemap analysis plus Google's field and lab APIs,
with no browser. The CLI takes a single positional URL followed by flags. Always run `--help` first
to confirm the flags on the copy you actually have.

```bash
# Default pass: status and redirect chain, title/meta/canonical/hreflang/headings, JSON-LD parse
# (syntax only, not schema validity), OG/Twitter tags, alt coverage, links, approximate word count,
# and the jsDependency verdict.
node scripts/seo-check.mjs https://example.com/pricing

# robots.txt only: RFC 9309 allow/disallow verdict, parsed groups, Sitemap: lines, and access-error
# handling (4xx means allow-all, 5xx/timeout means strict disallow-all, which is stricter than
# Google's real retry-and-cache behavior that a script cannot replicate).
node scripts/seo-check.mjs https://example.com --robots

# Ask about a specific path and a specific bot token without fetching that path.
# --check-path changes which path the verdict is computed for.
# --as-ua changes which bot token the rules are matched against (distinct from --ua, which
# changes the user-agent actually sent on the wire).
node scripts/seo-check.mjs https://example.com --robots --check-path /admin --as-ua Googlebot

# Sitemap analysis: urlset vs sitemapindex, counts against the 50,000 URL / 50 MB limits, gzip
# handling, hreflang alternates. A 404 served as application/xml reports "not valid XML", never
# a silent "zero URLs".
node scripts/seo-check.mjs https://example.com --sitemap

# AI and search bot roster, grouped by role. Training bots, live-retrieval bots, and
# index/citation bots have different consequences when blocked, so never collapse them into one
# "AI bots" check. The roster is a dated snapshot: verify against each vendor's live bot docs.
node scripts/seo-check.mjs https://example.com --ai-bots

# Core Web Vitals. Keys are free from Google Cloud Console (enable "Chrome UX Report API" and
# "PageSpeed Insights API"; no billing account needed). A missing key degrades to a skip notice,
# it never crashes the run.
node scripts/seo-check.mjs https://example.com --crux "$CRUX_KEY" --psi "$PSI_KEY"

# Cloaking diff: fetches a second time with a Googlebot-like UA and compares. Diagnostic only.
node scripts/seo-check.mjs https://example.com --compare-googlebot

# Machine-readable output for bulk or programmatic work. Sub-check failures land in errors[]
# rather than aborting the run, and the limitations block is always present.
node scripts/seo-check.mjs https://example.com --json
```

Other flags: `--ua <string>` (wire user-agent), `--timeout <ms>`, `--max-redirects <n>`.
Exit codes: `0` completed, `1` target unreachable or fatal, `2` usage error.

**Worked example:**
```bash
$ node scripts/seo-check.mjs https://example.com/blog/post-1 --json | \
  jq '.jsDependency, .pageSignals.title, .pageSignals.canonical'
```
Suppose that returns a `jsDependency.verdict` of `"uncertain"`, a 6-character title, and a null
canonical. The raw HTML shows almost nothing, but the verdict is `uncertain`, not `likely-ssr`.
Per Section 3 you cannot report "missing canonical" from this alone. The correct finding is:
"raw HTML shows [X]; JS-dependency uncertain; escalate before treating this as a defect."

## 3. The browser-escalation rule

**The most important procedure in this document.** A raw HTTP fetch — including this agent's own
`WebFetch` — sees only what the server sent before any JavaScript ran. `WebFetch` additionally
strips `<script>` tags outright, so it can **never** see JSON-LD, on any page, rendered or not.

**State plainly**: reporting "no schema found," "no title," "thin content," or "no canonical" from
raw HTML alone is a **false negative** on any client-rendered page. Google's indexer executes JS
before indexing; your raw fetch does not.

**Escalation ladder — stop at the first tier that resolves it:**

1. Check `jsDependency.verdict` from the default `seo-check` pass.
2. If it is anything other than `likely-ssr` (`likely-csr` or `uncertain`), escalate — do not
   report the raw-HTML absence yet.
3. Escalation options, cheapest first:
   - **Headless browser**, extract from the live DOM post-render (Playwright/Puppeteer
     `page.evaluate(...)` with `waitUntil: 'networkidle'`, or pasted into DevTools Console):
     ```js
     [...document.querySelectorAll('script[type="application/ld+json"]')]
       .map(s => { try { return JSON.parse(s.textContent); } catch { return { parseError: true }; } });
     document.title;
     document.querySelector('link[rel="canonical"]')?.href ?? null;
     document.querySelector('meta[name="robots"]')?.content ?? null;
     ```
   - **Google Rich Results Test** (`search.google.com/test/rich-results`) — reflects Google's
     actual Web Rendering Service; confirms extraction and current rich-result eligibility.
   - **GSC URL Inspection Live Test**, rendered-HTML/screenshot view — shows what Googlebot's
     renderer actually saw; requires verified property ownership (Section 5).
   - **Screaming Frog with JS rendering enabled** — bulk escalation once a spot-check confirms
     CSR; Tier 3, corroborate against a Tier-1 spot check before trusting at scale.
4. Only after confirmation do you report the absence as a defect. If escalation isn't possible,
   hedge explicitly: "not present in raw HTML; JS-dependency uncertain; not independently
   confirmed via rendered check."

## 4. Core Web Vitals: field vs. lab

**CrUX (field)** — real Chrome users, what Google's ranking systems actually consult. 75th
percentile, 28-day rolling window, ~2 days lag. Low-traffic URLs often have **no record**
(undisclosed minimum sample) — fall back to **origin-level** and label "site-wide average, not
page-specific," never treat "no data" as pass or fail.

**PSI/Lighthouse (lab)** — synthetic run on a simulated device, server-side (no local Chrome
needed). Fixed, reproducible conditions; not real-world conditions.

**When they disagree, and why that's not automatically a finding**: bad Lighthouse + good CrUX
means real users are fine despite one throttled synthetic run scoring poorly (Lighthouse
over-penalizes render-blocking patterns that resolve fine on fast connections; single-run variance
is high). **A bad Lighthouse score with good CrUX data is not a finding** — report both, note the
divergence, don't recommend "fix Lighthouse" on that basis alone. Good Lighthouse + bad CrUX is
more actionable — it usually means the synthetic condition doesn't match the real user mix.

**Thresholds** (verify at web.dev/vitals, they move):
- **LCP**: good ≤ 2.5s, poor > 4.0s
- **INP**: good ≤ 200ms, poor > 500ms — **replaced FID in March 2024**; don't request/report
  `first_input_delay`, it's deprecated from current responses
- **CLS**: good ≤ 0.1, poor > 0.25

```bash
# CrUX field data
curl -s -X POST 'https://chromeuxreport.googleapis.com/v1/records:queryRecord?key=API_KEY' \
  -H 'Content-Type: application/json' -d '{"origin":"https://example.com","formFactor":"PHONE"}'

# PSI lab data + CrUX passthrough for the same URL
curl -s "https://www.googleapis.com/pagespeedonline/v5/runPagespeed?url=https%3A%2F%2Fexample.com&strategy=mobile&category=performance&category=seo&key=API_KEY"
```
Free key: Cloud Console → enable "Chrome UX Report API" / "PageSpeed Insights API" → generate key,
no billing account required. CrUX: 150 queries/min/project. PSI: 25,000/day, 240/min. Verify
current quotas at `developer.chrome.com/docs/crux/api` and `developers.google.com/speed/docs/insights/rest`.

## 5. What you cannot determine, and the honest substitute

- **Confirmed indexation status.** URL Inspection API needs OAuth 2.0 and **verified ownership**
  of the property — unavailable for arbitrary third-party audits. Substitute: check
  *indexability* (robots.txt, meta-robots, `X-Robots-Tag`) as a proxy, explicitly labeled as a
  permission signal, not confirmed index state. A page can pass every indexability check and
  still not be indexed.
- **Do not scrape `site:` queries.** Against Google's ToS and actively rate-limited/CAPTCHA'd.
- **Rankings.** Require a rank tracker or the owner's own GSC data. Ad hoc SERP scraping is
  unreliable (personalization, geo, device variance) and ToS-violating at scale. Say so rather
  than approximate.
- **Competitor internal data** (their GSC, analytics, real conversion numbers). Unavailable by
  construction — say so, do not infer it from public tools and present it as measured.

## 6. Verifying a crawler is who it claims to be

UA strings are the **weakest** signal — trivially spoofed by any client at zero cost. Never
conclude "this is Googlebot" from a UA string alone, useful only as a first-pass filter for which
requests are worth DNS-verifying.

**Forward-confirmed reverse DNS** (Google's own documented method, strongest signal):
```bash
dig -x 66.249.66.1 +short                    # 1. reverse-resolve -> crawl-66-249-66-1.googlebot.com.
                                              # 2. confirm hostname is in the expected crawler
                                              #    domain (googlebot.com/google.com; bing.com for Bingbot)
dig crawl-66-249-66-1.googlebot.com +short   # 3. forward-resolve that hostname back
                                              # 4. confirm round-trip matches the original IP
```
`host` works equivalently if `dig` is unavailable. A PTR outside the expected domain, or a
round-trip mismatch, means the request did not come from that crawler regardless of UA.

**Published IP-range JSON files** — second method, good for bulk log analysis without per-row DNS:
Google/Bing publish machine-readable IP-range lists; load into a CIDR matcher and check request
IPs against it. Refetch periodically — ranges change — and verify the current URL at each vendor's
crawler docs before hardcoding it.

## 7. Reading server logs

Logs reveal what crawlers actually *did*. Cross-reference GSC Crawl Stats — a mismatch between
GSC's reported crawl volume and what logs show for verified bot IPs is itself a signal (often a
robots.txt failure or a WAF silently 403-ing the crawler while GSC still records an attempt).
Adapt field indices below to the actual log format in use (nginx/Apache/CDN JSON differ); inspect
a sample line first.

```bash
# Requests by user-agent
awk -F'"' '{print $6}' access.log | sort | uniq -c | sort -rn | head -30

# Status-code distribution for one bot — compare against what a normal browser UA gets on the same
# paths; bot-only 403s/429s while browsers get 200 is a strong cloaking/WAF signal (Section 8)
grep -i 'Googlebot' access.log | awk '{print $9}' | sort | uniq -c | sort -rn

# Most-crawled paths — surfaces crawl budget wasted on low-value paths (faceted-nav, infinite
# pagination), finer-grained than GSC's own aggregate-by-bot-type view
grep -i 'Googlebot' access.log | awk '{print $7}' | sort | uniq -c | sort -rn | head -30
```

## 8. Detecting cloaking and edge weirdness

```bash
# Diff by user-agent
curl -s -A "seo-check/1.0 (+contact)" https://example.com/page -o /tmp/plain.html
curl -s -A "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)" \
  https://example.com/page -o /tmp/googlebot-ua.html
diff /tmp/plain.html /tmp/googlebot-ua.html

# Vary header — Vary: User-Agent/Accept-Encoding with a CDN in front can be legitimate
# device-adaptation, not cloaking; distinguish before flagging
curl -sI https://example.com/page | grep -i vary
```
- **Geo-redirect detection**: fetch through different-country egress points, diff for unexpected
  redirect-target or content changes. Language localization is expected; silently swapped
  canonical content or region-blocked indexable content is not.
- **CDN variant serving**: compare `curl` with/without cache-busting headers to check for a stale
  or A/B-test variant served specifically to crawlers.

A meaningful diff is worth investigating but is a **diagnostic diff, never the primary basis of an
audit**: Google authenticates its real crawler by reverse DNS (Section 6), not UA string, so a
UA-based diff only reveals whether *the site's own logic* branches on the header. Never write "the
site cloaks for Googlebot" based solely on a spoofed-UA curl diff.

## 9. Establishing "what changed and when"

A finding that says "X broke on this date, correlating with this event" beats "X is broken."
Build a timeline before attributing cause.

- **Deploy history**: `git log --since="60 days ago" --oneline` against the repo backing the
  site, if accessible — align commit dates with the change's onset.
- **CMS revision history**: WordPress revisions / headless CMS version history log content and
  template changes independently of git — check both, they can diverge.
- **CDN/WAF config change dates**: Cloudflare/Fastly/Akamai keep an audit log of rule changes — a
  new WAF rule is one of the most common causes of a sudden crawler-only status-code change.
- **GSC Crawl Stats anomalies**: host-status flips, response-code spikes, discovery/refresh
  collapse — each has a chart date to correlate against the sources above.
- **Wayback Machine before/after**: fetch a specific dated snapshot, or pull the capture list via
  the CDX API, then diff archived raw HTML against a current fetch for title/meta/canonical/
  content changes. The archived copy is itself raw-HTML-at-crawl-time — the Section 3 JS-rendering
  caveat still applies to what it captured.
  ```bash
  # Specific dated snapshot
  https://web.archive.org/web/YYYYMMDDhhmmss/https://example.com/page
  # Full capture list
  curl -s "http://web.archive.org/cdx/search/cdx?url=example.com/page&output=json&limit=50"
  ```

Combine the timeline with the traffic-drop decision tree (`references/diagnostics.md`): the node
that "rules in" is the one whose event date lines up tightly with the decline's onset, not the one
that merely sounds plausible.
