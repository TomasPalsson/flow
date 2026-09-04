---
name: google-ads
description: "Use when working with Google Ads data through the official Google Ads MCP server (googleads/google-ads-mcp — see developers.google.com/google-ads/api/docs/developer-toolkit/mcp-server), whose tools are `search_search`, `customers_list_accessible_customers`, and `metadata_get_resource_metadata`. Use for: building a GAQL query or a `search_search` call; pulling campaign, ad group, keyword, search-term or Performance Max performance; reading Google Ads spend, conversion, or impression-share numbers; MCC/manager-account rollups; and diagnosing a Google Ads CPA spike, conversion drop, ROAS decline, stalled serving, or budget underspend. Also use when a Google Ads query returns nothing, returns an absurd-looking number, when Google Ads totals don't reconcile between levels, or on any Google Ads API error. Trigger phrases: 'google ads', 'GAQL', 'google ads mcp', 'google ads api', 'PMax', 'performance max', 'search terms report', 'impression share', 'customer id', 'adwords'. Requires Google Ads MCP tools to be connected — if no such tools are present, this skill does not apply and cannot substitute for them."
metadata:
  version: 1.0.0
---

# Google Ads via MCP

Target: the **official** Google Ads MCP server, `googleads/google-ads-mcp` —
Google's first-party server, documented at
[developers.google.com/google-ads/api/docs/developer-toolkit/mcp-server](https://developers.google.com/google-ads/api/docs/developer-toolkit/mcp-server).
Read-only by design in its current release, Python, stdio by default. Everything
about tool shape below describes that server specifically.

You are querying a **read-only** server over a live advertising account where the
numbers are easy to fetch and easy to misread. Two failure modes dominate: asking
the server for something in the wrong shape, and believing a number that means
something other than what it looks like.

This skill is a method for the first and a set of interpretation rules for the
second. It deliberately carries no schema snapshot — the server is authoritative
about its own schema and stays fresher than any list written here.

---

## Orientation — what this server actually is

Three tools, namespace-prefixed (this trips people up — the README calls them
`search`, `get_resource_metadata`, `list_accessible_customers`):

| Tool | Purpose |
|---|---|
| `customers_list_accessible_customers` | Directly accessible customer IDs. Effectively free. Call it first. |
| `search_search` | Fetch rows. **Does not take a GAQL string.** |
| `metadata_get_resource_metadata` | Selectable/filterable/sortable fields for one resource. Expensive. Cache it. |

**`search_search` takes structured parameters, not a query string:**

```
customer_id: str          # digits only — strip hyphens from 123-456-7890
fields:      list[str]    # fully-qualified: "campaign.name", not "name". No wildcards.
resource:    str          # the FROM resource — one only
conditions:  list[str]    # AND-joined for you. Do not write "AND" yourself.
orderings:   list[str]
limit:       int | None   # no server-side default. See narrowing discipline.
```

The server assembles the GAQL and always appends
`PARAMETERS omit_unselected_resource_names=true`. If you catch yourself composing
`SELECT ... FROM ... WHERE ...` as a string, stop — that is the API of the
*community* Google Ads MCP servers, not this one.

**Worked example** — "how did my campaigns do last month?", the whole call:

```json
{
  "customer_id": "1234567890",
  "resource":    "campaign",
  "fields":      ["campaign.id", "campaign.name", "campaign.status",
                  "metrics.impressions", "metrics.clicks",
                  "metrics.cost_micros", "metrics.conversions"],
  "conditions":  ["segments.date DURING LAST_MONTH",
                  "campaign.status = 'ENABLED'"],
  "orderings":   ["metrics.cost_micros DESC"],
  "limit":       50
}
```

Note the shapes, which are easy to get wrong:
- Each **condition is one complete GAQL predicate as a string** — field, operator,
  value. Never write `AND` yourself; the server joins with ` AND `. Never pass an
  operator or value as a separate key.
- String literals inside a condition are **single-quoted** (`'ENABLED'`); numbers
  and date literals are not.
- Each **ordering carries its own direction** (`"metrics.cost_micros DESC"`), and
  they are comma-joined.
- `segments.date` appears in `conditions` but **not** in `fields` — that is what
  makes this one aggregated row per campaign instead of ~30 daily rows.

**Read-only is enforced by the tool surface, not by the credential.** The token
carries full `adwords` scope; Google publishes no read-only scope. So the safety
property is "no write tool exists here," not "this session cannot write." Never
imply to the user that the credential is incapable of mutation.

---

## Step 0 — Confirm your surface before trusting it

Do this once per session, before assuming anything about what you were given.

1. **Look at the tool names you actually have.**
   - **No Google Ads MCP tools at all?** Then you cannot query this account. Say
     so plainly and stop — do not answer performance questions from memory, and
     do not invent numbers. You can still help the user set the server up
     (see `references/failure-recovery.md`) or reason about method in the
     abstract, but say explicitly that you have no access to their data.
   - **Unprefixed names, or `run_gaql` / `execute_gaql_query` / anything that
     mutates?** You are on a *different* Google Ads MCP server — several
     community ones exist, some with write access. The tool-shape guidance below
     stops applying; re-read the descriptions you were actually given. The
     interpretation rules in `references/measurement-traps.md` still apply in
     full, since those are properties of the Google Ads data, not of the server.
2. **Look at how much `search_search`'s description gave you.** On the official
   server it may arrive as a long text carrying usage hints and the full list of
   valid resources — or as a one-line summary, depending on which `fastmcp`
   version the deployment resolved (it is unpinned, and the behavior has been
   observed both ways). Whatever arrived is your live resource list. Do not
   assume it is there, and do not assume it is missing — read it.
3. **Assume the per-parameter hints may be empty**, so the operational details
   in this skill (hyphen stripping, `YYYY-MM-DD` dates, the `change_event` limit)
   are load-bearing rather than redundant.

---

## The discovery loop

**Never guess a field name into a query. Never dump the schema either.** Both are
failures; the path between them is a probe.

```
identify grain + window  →  get customer_id  →  pick resource
        →  fields you're confident in?  ──yes──►  query coarse
                    │no
                    ▼
        metadata_get_resource_metadata(resource)  →  cache  →  query coarse
        →  interpret (see "Reading the numbers")  →  narrow only if asked
```

**Getting a customer ID.** Call `customers_list_accessible_customers`. One ID
back does not mean one account — a manager (MCC) ID is indistinguishable from a
serving account in that response. Carry "this might be a manager" as an open
hypothesis; if a normal query returns zero rows, resolve it by querying
`customer_client` for `id`, `descriptive_name`, `manager`, `level`.

**Choosing a resource.** Query `FROM` the resource at the grain you want rows at.
One row per campaign → `campaign`. Per keyword → `keyword_view`. Per search term
→ `search_term_view`. You cannot get search-term grain from `campaign` — GAQL has
no JOIN. Related fields come free via attributed resources (`campaign.name` while
`FROM ad_group` works), but the attribution graph is not guessable from naming.

Useful entry points to probe from — a doorway, not a catalogue:
`customer_client`, `campaign`, `ad_group`, `ad_group_ad`, `keyword_view`,
`search_term_view`, `campaign_search_term_view` (Performance Max),
`change_event`.

**When the grain you need isn't one of those, and the live tool description
didn't hand you a resource list, guess by convention and validate cheaply.**
Report-style resources follow visible patterns — `<dimension>_view`
(`geographic_view`, `age_range_view`, `gender_view`, `landing_page_view`),
`<entity>_criterion`, `<entity>_asset`. Form the most plausible name and probe it
with `metadata_get_resource_metadata`.

The probe is asymmetric, and that is what makes this affordable: **a wrong
resource name comes back with empty `selectable`/`filterable`/`sortable` lists —
a near-free response.** Only a *correct* name returns the large, expensive
payload. So guessing costs almost nothing when you are wrong, and when you are
right you were going to pay for the metadata anyway. Two or three probes are
cheaper than one `discovery-document` read by four orders of magnitude.

If several probes come back empty, ask the user what they're trying to see rather
than burning calls — and never invent a resource name into a query.

**When to spend a `metadata_get_resource_metadata` call.** It costs tens of
thousands of tokens. Its own docstring says to call it before every query; that
instruction is not affordable literally, and following it mechanically will
exhaust your context before you answer anything. Spend it when: the resource is
unfamiliar, a field name just failed, or you are pairing an uncommon
metric/segment whose compatibility you genuinely cannot predict. Skip it for
`campaign.id` + `metrics.clicks`-tier queries you are already confident about.
**Cache every response for the session, keyed by resource.**

**Never read `resource://metrics`, `resource://segments`, or
`resource://discovery-document` inside an agent loop.** Measured live: ~1.25M,
~1.39M, and ~662k tokens. Two of them exceed a 1M-token context window by
themselves. They are not "expensive," they are unusable. `resource://release-notes`
(~96k) is justifiable only for a targeted deprecation question.

---

## Query construction and narrowing discipline

GAQL has **no aggregate functions, no `GROUP BY`, no `JOIN`, no subqueries, no
wildcards, no arithmetic in `SELECT`**. Aggregation happens two ways only:
pick a coarser resource (server-side, free), or sum rows yourself (costs context).
Always prefer the coarser resource.

**The technique worth knowing:** a date segment can *filter* without being
*selected*. `conditions: ["segments.date DURING LAST_MONTH"]` with
`segments.date` absent from `fields` returns **one pre-aggregated row per
campaign for the whole month** — not 31 rows to sum. Adding `segments.date` to
`fields` is what multiplies rows. Every segment you select multiplies grain;
add one only when the question needs that breakdown.

- **Aggregate first, drill down second.** Get headline numbers at `campaign`
  grain, find the interesting slice, *then* re-query narrowly scoped with
  `campaign.id = ...`. Never open at the finest grain "to be thorough."
- **`limit` has no server-side default.** Treat it as mandatory below campaign
  grain and as a defensive ceiling above it — account size is not knowable in
  advance. `change_event` requires `LIMIT <= 10000`.
- Dates are `YYYY-MM-DD` with dashes, in the **account's** timezone, never UTC.
  Ranges must be closed on both ends.
- The complete `DURING` set is: `TODAY`, `YESTERDAY`, `LAST_7_DAYS`,
  `LAST_14_DAYS`, `LAST_30_DAYS`, `LAST_BUSINESS_WEEK`, `THIS_MONTH`,
  `LAST_MONTH`, `THIS_WEEK_SUN_TODAY`, `THIS_WEEK_MON_TODAY`,
  `LAST_WEEK_SUN_SAT`, `LAST_WEEK_MON_SUN`. There is **no** `THIS_YEAR`,
  `LAST_YEAR`, or `ALL_TIME` — use an explicit `BETWEEN`.
- `=`, `IN` and `CONTAINS` are case-**sensitive**; `LIKE` is case-insensitive.
- Granular (daily/weekly/hourly) data is retained **37 months**; monthly and
  coarser, 11 years. A day-segmented query further back fails with
  `REQUESTED_DATE_GRANULARITY_NOT_SUPPORTED` — that is a granularity error, not
  "no data." Re-ask it unsegmented.

---

## Reading the numbers — the part no tool call will tell you

The API returns a correctly-typed number and never warns you that it means
something else. This is where confident, wrong analysis comes from.

**Money is not uniformly scaled.**
- `int64` ending in `_micros` → divide by 1,000,000. Airtight.
- Cost-family `double`s with **no** suffix — `average_cpc`, `average_cpm`,
  `average_cost`, `cost_per_conversion`, `cost_per_all_conversions` — are
  *also* micros (legacy convention). Miss this and you report "$2.19 million
  average CPC."
- Value-family — `conversions_value`, `all_conversions_value` — are **not**
  micros. Divide these and a real campaign reads as earning $0.0000004.
- `value_per_conversion` is **genuinely unresolved**. Do not assert its units.
- Ratios (`ctr`, `*_rate`, `*_share`, `*_percentage`) are never a micros question.

**When unsure, do not guess — verify arithmetically in one query.** Select the
ambiguous field alongside its components and check by hand: does
`cost_micros / 1e6 / clicks` equal the returned `average_cpc`, or 1e6× it? The
answer is unambiguous and costs one row.

**Rates must be recomputed, never averaged.** Mean-of-daily-CTR weights a
low-traffic day equally with a high-traffic one; the resulting "CTR improved 15%"
can point the opposite way from pooled `sum(clicks)/sum(impressions)`. Always
re-derive from summed numerators and denominators.

**Impression share is clamped and non-additive.** Below 10% is reported as
`0.0999`; above 90% as `0.9001`. So `0.0999` means "under 10%, withheld" — a
quarter that looks "flat at ~10%" may have swung between 1% and 9%. It cannot be
summed or simple-averaged across campaigns or days; the denominator is a
per-auction estimated pool Google does not expose. Report it at the grain Google
provides, or state the approximation you made.

**Conversions are not a count you can take at face value.** They are fractional
(attribution splits credit), attributed to **click date** by default so today's
conversions may belong to a click 90 days ago, partly **modeled** rather than
observed, and **retroactively rewritten** when the attribution model updates — so
re-pulling the same past dates can legitimately return different numbers.
`conversions` and `all_conversions` count different populations; picking whichever
is larger is not "more complete," it is a different question.

**Recent days are provisional.** They rise on re-pull with no underlying change.
There is no official fixed exclusion window — Google's own pages say 14 days,
"at least 30 days," and "the most recent few weeks" in different places. The
defensible rule is the account's own: wait until its **Avg. days to conversion**
(or the conversion action's configured lookback window, whichever is longer) has
elapsed. Derive it; don't assume a constant.

**Totals structurally will not reconcile, and that is not a bug.** Search-term
and demographic rows are privacy-suppressed while their spend still counts in the
parent. Performance Max has no ad-group grain at all. Asset metrics are shared,
not exclusively attributed. Never "fix" a gap by rescaling child rows.

**Currency is per-account with no API conversion.** Summing `cost_micros` across
`customer_client` rows in a multi-currency MCC adds USD to GBP silently and
returns a plausible large number that is not any real total. Check
`customer.currency_code` before any cross-account sum; report per currency or
apply an explicit external rate and say so.

**MANDATORY — READ ENTIRE FILE** before writing any analysis that quotes
conversion, value, or impression-share numbers, or that compares periods:
[`references/measurement-traps.md`](references/measurement-traps.md).

---

## Diagnosing — elimination in a fixed order

The order is the expertise. A broken conversion tag and a genuine demand collapse
produce an identical chart; one takes five minutes to fix and the other takes a
strategy rebuild. So cheap deterministic causes get ruled out first, always.

**Whatever the symptom, the first two checks are the same:**
1. **Conversion tracking health** — is the conversion action still recording,
   and was it edited (value, counting, attribution) just before the inflection?
2. **Change history** — query `change_event` around the inflection date. A change
   landing on that date is the prime suspect.

Only after those: segment (device, network, geo, time), then check bid-strategy
learning state, then auction pressure, then — last, because it is unfalsifiable
and easy to reach for — the market.

**Before calling any movement real**, check it clears the volume bar: Google's
own floors are 30 conversions/30 days for Target CPA evaluation, and for Target
ROAS **15**/30 days on Search & Shopping (the widely repeated "50" is the Demand
Gen and Hotel figure, not a universal minimum). Under those volumes, week-to-week
swings are mostly noise. Bid strategies take up to 3 weeks or 1–2 conversion
cycles to calibrate after a change.

Prefer week-over-week to day-over-day; align day-of-week and moving holidays for
year-over-year. Scanning many keywords for "the underperformer" will always find
one by chance — require persistence across periods before acting.

**MANDATORY — READ ENTIRE FILE** when the user reports any symptom (CPA spike,
conversion drop, flat revenue, serving stopped, ROAS decline, budget underspend):
[`references/diagnostic-playbooks.md`](references/diagnostic-playbooks.md).

---

## When a call fails

The server flattens every Google Ads error into one `ToolError` string:
`Request ID: {id}` then `Google Ads API Error: {message}` per error. **The
structured error code does not survive the wrapping** — you must classify by
reading the message text. Retry transient failures (`INTERNAL`, `UNAVAILABLE`,
`DEADLINE_EXCEEDED`, short-term throttling) with backoff; never retry a malformed
query, a permission error, or an exhausted daily quota.

Some failures **bypass that wrapper entirely** and surface as an opaque internal
error instead: an API version that Google has sunset, and a response exceeding
the 64MB gRPC cap. If a tool call fails with no `Request ID:` line at all, suspect
one of those two — not a bad query.

**Empty results are the most misread outcome.** Never report "no data" without
ruling out: the ID was a manager account, it is a test account (which have no
real data by design), the filter over-constrained, the window predates the
37-month granular retention limit, or the rows were privacy-suppressed. Drop one
condition at a time to find which.

**Schema-selectable does not mean account-entitled.** Some fields — Auction
Insights especially — are real, appear in `get_resource_metadata`, and still
return a permission error because of a closed allowlist. Nothing predicts this in
advance; a repeated permission error on one field family is an entitlement gap to
report, not a query bug to fix.

**MANDATORY — READ ENTIRE FILE** on any authentication, permission, quota, or
setup error, or when the user is configuring the server:
[`references/failure-recovery.md`](references/failure-recovery.md).

---

## Anti-patterns

- **NEVER compose a raw GAQL string for `search_search`.** It takes structured
  parameters and builds the query itself.
- **NEVER guess a field name into a query** — probe with
  `metadata_get_resource_metadata` and cache the answer.
- **NEVER read the `metrics`, `segments`, or `discovery-document` resources in a
  loop.** They are 662k–1.39M tokens.
- **NEVER divide by 1,000,000 because a field looks like money.** Classify it,
  or verify arithmetically. Two families scale opposite ways.
- **NEVER sum or average impression share**, and never read `0.0999`/`0.9001` as
  precise values.
- **NEVER judge recent days as final.** Conversion data is still arriving.
- **NEVER treat a coarse-vs-fine total mismatch as a data bug**, and never
  rescale child rows to close it.
- **NEVER sum cost across accounts in an MCC** without checking currency per
  account.
- **NEVER cite "a >20% budget or target change resets learning."** It is
  practitioner folklore, absent from Google's documentation, and Google's own FAQ
  states Smart Bidding reacts to target changes in real time regardless of size.
- **NEVER present Google's Recommendations or Optimization Score as neutral
  advice** — the score measures adoption of Google's suggestions, not account
  health.
- **NEVER recommend pausing an "expensive" keyword from last-click cost alone**
  without checking whether it assists conversions credited elsewhere.
- **NEVER state a change as made.** This server cannot write. Frame every
  suggestion as a recommendation for a human to apply, with the spend at risk and
  whether it is reversible.
