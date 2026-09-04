---
name: alpha-hunt-data-runbook
description: Data plumbing — reuse inventory of the 8 investment scripts, new endpoints (market-wide Form-4, SEC 8-K item-code triage, CBOE options, keyless FRED, Finnhub, Nasdaq calendar), exact invocations, batching rules, dead-source traps. Load before any data call.
---

# Data Runbook

All endpoints below were live-verified (2026-07). Reuse the `investment` skill's scripts; add the
new capabilities. SEC requires a `User-Agent: AppName email` — reuse the investment scripts' UA.
SEC rate limit ~10 req/sec (punitive ~10-min block on violation). Never shell out per-ticker to
Yahoo (crumb cost ~1s/cold process) — batch into ONE invocation.

## Reuse inventory (`../investment/scripts/`) — do NOT rebuild these

| Script | Source | Invocation | Output |
|---|---|---|---|
| `fetch-universe.js` | Wikipedia S&P 500/400/600 | `node fetch-universe.js` | ~1,509 tickers + sector/CIK |
| `fetch-quote.js` | Yahoo via yahoo-finance2 | `node fetch-quote.js T1 T2 …` | price/mcap/PE/beta/margins/… (batches internally) |
| `fetch-financials.js` | Yahoo + SEC cross-check | `node fetch-financials.js T` | financials + shift-bug flag |
| `fetch-sec-facts.js` | SEC XBRL companyfacts | `node fetch-sec-facts.js T` | ~25 GAAP tags + 7yr series |
| `fetch-insider.js` | SEC Form 4 (per-ticker) | `node fetch-insider.js T` | txns + 90d cluster signal |
| `fetch-13f.js` | SEC 13F (curated CIKs) | `node fetch-13f.js T` | superinvestor holdings |
| `fetch-macro.js` | FRED (needs FRED_API_KEY) | `node fetch-macro.js` | 8 series + regime phase |
| `compute-fraud-check.js` | derived + SEC FTS | `node compute-fraud-check.js T` | Beneish/Sloan/going-concern → PASS/YELLOW/VETO |

**13F clone list**: `fetch-13f.js` checks the investment skill's superinvestor CIKs; alpha-hunt's
`data/clone-funds.json` narrows these to LOW-turnover funds worth cloning (each tagged `cloneability`
HIGH/MEDIUM/LOW). Stage 4 reads it to weight a 13F confirmation — clone only NEW ≥7.5% positions of
HIGH/MEDIUM funds (the 45-day lag is fatal for fast-turnover funds; see signals.md).

Only npm dep is `yahoo-finance2` (already installed in the investment dir). New alpha-hunt scripts
must be self-contained (Node stdlib + https only) so they run without extra installs.

## New endpoints (alpha-hunt adds these)

### Yahoo v8 chart — keyless OHLCV at scale (for compute-momentum.js)
```
https://query1.finance.yahoo.com/v8/finance/chart/{TICKER}?range=2y&interval=1wk&events=div,splits
```
Header `User-Agent: Mozilla/5.0` REQUIRED (no UA → 429). Returns `timestamp[]`,
`indicators.quote`, `indicators.adjclose`, `events`. Weekend/holiday days are simply omitted — count
returned timestamps, not calendar days. v10 quoteSummary / v7 options are crumb-gated (use
`fetch-quote.js` for those). Batch all tickers in ONE process.
Same endpoint serves the regime inputs: `SPY`/`^GSPC` (`interval=1d` for distribution-day counts),
and `^VIX` + `^VIX3M` (term-structure ratio = VIX/VIX3M; scored with a dead band — >1.05 backwardation
→ −1, <0.95 contango → +1, else 0; see regime-throttle.md). Breadth (% above 200DMA)
is aggregated by the orchestrator from the universe's weekly pull — no separate endpoint needed.

### SEC market-wide same-day Form-4 feed (for fetch-catalysts.js)
```
https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&type=4&company=&dateb=&owner=include&count=100&output=atom
```
Atom XML of the most recent Form-4s across ALL issuers — discover NEW opportunistic clusters, not
just confirm known tickers. Cross-reference with `fetch-insider.js` for the per-ticker detail.
Form-4s are ≤2 business days late.

### SEC EDGAR full-text-search 8-K feed (for fetch-catalysts.js `fetchRecent8K()`) — Item-code triage
```
https://efts.sec.gov/LATEST/search-index?forms=8-K&dateRange=custom&startdt=YYYY-MM-DD&enddt=YYYY-MM-DD&from=N
```
Live-verified 2026-07 via curl. **Omit the `q` (query) param entirely** — with no `q`, this returns
ALL matching 8-Ks (not a text-search subset), sorted **newest-first**, 100 hits/page, paginated with
`from=` (0, 100, 200, …). `fetchRecent8K()` pulls a trailing 7-day window (matches `fetchNews`'s
weekly cadence), capped at 10 pages (≤1,000 filings) as a safety limit on a heavy filing week — a
`WARN` is logged to stderr if the cap truncates real results (observed: ~1,280 8-Ks market-wide over
7 days, so the cap does bite; the truncation drops the OLDEST end of the window, not the newest).
Response shape — each hit's `_source` already carries the parsed data, no need to fetch/regex the
filing body:
```json
{"hits":{"total":{"value":1280},"hits":[{"_id":"<adsh>:<filename>","_source":{
  "ciks":["0001077183"],"display_names":["NEOGENOMICS INC  (NEO)  (CIK 0001077183)"],
  "file_date":"2026-07-22","form":"8-K","adsh":"0001077183-26-000049","items":["7.01","8.01","9.01"]
}}]}}
```
- `items` = the filing's 8-K Item codes (this is the field the triage runs on).
- `display_names[0]` — ticker is the parenthesized group right before `(CIK …)`, e.g. `(NEO)`; funds/
  trusts with no ticker have no such group (`extractTickerFromDisplayName()` returns `null` for those
  — correct, not a bug).
- Filing URL is NOT returned directly — build it: `https://www.sec.gov/Archives/edgar/data/<cik, no
  leading zeros>/<adsh, dashes stripped>/<filename from _id after the colon>` (verified live).
- Same **UA requirement** as the rest of SEC EDGAR (`alpha-hunt tomas@p5.is (research)`) and the same
  **~10 req/sec fair-access limit** — `fetchRecent8K()` sleeps 120ms between paginated pages.
- `efts.sec.gov` is a **different subdomain** from `www.sec.gov` (used by the Form-4/13D getcurrent
  feeds and Archives) but is the same SEC EDGAR service and subject to the same fair-access policy.

### Finnhub (keyed — FINNHUB_API_KEY, guaranteed present) — the catalyst engine
Free tier 60 calls/min. Base `https://finnhub.io/api/v1`. Key endpoints:
- Earnings calendar: `/calendar/earnings?from=YYYY-MM-DD&to=YYYY-MM-DD&token=KEY`
- Company news: `/company-news?symbol=T&from=…&to=…&token=KEY`
- Recommendation/estimate trends: `/stock/recommendation?symbol=T&token=KEY`
- Insider transactions: `/stock/insider-transactions?symbol=T&token=KEY`
Space calls to stay under 60/min (a 20-name shortlist fits easily).

### Free CBOE delayed options (no key) — conviction proxy
```
https://cdn.cboe.com/api/global/delayed_quotes/options/{TICKER}.json
```
Full chain incl. IV / OI / greeks (15-min delayed, treat as directional not tradeable-precision).
Use for put/call OI skew and IV-rank proxies. Optional enrichment, not core.

### Keyless FRED CSV fallback (no key)
```
https://fred.stlouisfed.org/graph/fredgraph.csv?id={SERIES}
```
e.g. `BAMLH0A0HYM2` (HY-IG spread — regime), `DGS10`, `T10Y3M`, `VIXCLS`. Stable "Download Data"
backend; no key needed. Use if FRED_API_KEY is absent (but preflight requires it, so this is backup).

### Nasdaq earnings calendar (unofficial, browser-UA, no key)
```
https://api.nasdaq.com/api/calendar/earnings?date=YYYY-MM-DD
```
JSON `{data:{rows:[{symbol,name,marketCap,epsForecast,…}]}}`. Single-date; 5-7 calls for a week.
Fragile/unofficial — keep Finnhub calendar as the primary, this as a cross-check.

## Dead sources / traps — do NOT use
- **stooq.com** — JS proof-of-work challenge, not curl-able. Use Yahoo v8 chart instead.
- **Finviz export.ashx** — Elite paywall now. Screener HTML is scrape-only/brittle.
- **FMP `apikey=demo`** — dead (401). Real key required; free tier is EOD-only.
- **Alpha Vantage free tier** — 25 calls/day, unusable for batch screening.
- **yfinance financials shift-bug (#2584)** — keep the SEC cross-check in fetch-financials.js.
- **SEC submissions `filings.recent`** — capped at 1,000 rows across all form types; serial small-cap
  filers can push Form-4s out of the window. Fine for a 1-yr lookback on most names.

## Preflight (scripts/preflight.js)
Verify FRED_API_KEY, FINNHUB_API_KEY, AGENT_PRIVATE_KEY, AGENT_PUBLIC_KEY all resolve, then one live
ping each (Finnhub `/quote?symbol=AAPL`, FRED series, SEC companyfacts w/ UA, Yahoo v8 chart).
Missing or dead → exit non-zero with the exact fix. Run FIRST, every pipeline.

## Regime fetcher (scripts/fetch-regime.js)
TIMEOUT-guarded (10s/request) pull of the dial inputs: SPY distribution days, ^VIX/^VIX3M term
structure, and FRED credit spread (BAMLH0A0HYM2 via keyless fredgraph.csv — no key dependency).
Emits a partial -3..+3 score (breadth added by the orchestrator). It exists because the reused
`fetch-macro.js` originally issued https.get with NO request timeout and could hang forever on a
proxied socket that stalls after the TLS handshake; `fetch-macro.js` is now also timeout-guarded,
but the regime dial uses this dedicated, key-independent fetcher.

## FinancialFilings MCP — ⚠️ NOT WORKING, and its fit is unproven. SEC EDGAR is the real path.
The `FinancialFilings` connector (`mcp.financialfilings.com`, free OAuth) is attached, but **every
data-bearing tool returns 403 — tested live 2026-07**: `companies_list`, `filing_types_list`,
`isins_retrieve`, `companies_financials_retrieve`, `filings_markdown_retrieve` all fail with *"Your
FinancialReports account isn't linked to the identity you signed in with."* Only the three static
reference tools (`get_fr_markdown_fetch_strategy`, `get_fr_filing_type_taxonomy`,
`get_fr_industry_classification_isic`) respond. This is an ACCOUNT-LINKING prerequisite, not a code
problem: a human must register at `financialreports.eu/signup` with the same email as the connector
identity. Until then the connector cannot serve a single number.

**Second, independent concern — do not skip this even after linking.** The vendor's own live tool
description for `companies_financials_retrieve` states that structured financials are *"currently
ESEF/EU-derived and being expanded"* and that empty results are *"common for US/SEC issuers."*
alpha-hunt screens the S&P 400/600 — an entirely US universe. So the previous instruction to PREFER
this over SEC-XBRL for the value/quality tilt and the Beneish/Sloan inputs was never validated and
may be backwards for this book's actual coverage.

**Therefore: SEC EDGAR (`fetch-sec-facts.js` / `compute-fraud-check.js`) is the PRIMARY and only
proven path.** Treat FinancialFilings as an unproven optional enrichment. Before routing anything
real through it, verify on a US small/mid-cap that `period_count > 0` — a non-empty response for one
mega-cap proves nothing about this universe. Never hang waiting on it.

## Persistent memory (scripts/state.sh — survives the weekly fresh container)
`persist_session=false` wipes `~/.cache/alpha-hunt/` each run. `scripts/state.sh load|save` syncs the
persistent state (picks-log.jsonl, signal-perf.json, holdings.json) to a dedicated `alpha-hunt-state`
git branch via pure plumbing — never touches the code working tree or history. `load` runs at State
Restoration (before Stage 1), `save` runs at the end of Stage 8. This is what makes the learning loop
compound across weeks instead of resetting.

## Caching
Cache under `~/.cache/alpha-hunt/`. TTLs: momentum-rank 28 days (monthly refresh), quotes 5 min,
catalysts 1 day, macro/regime 1 day, **news-seen.json rolling 60-day prune** (not a reuse-TTL like the
others — it's read-merge-write every run: cross-week news-headline memory for the rehash/staleness
detector in `fetchNews()`, entries older than 60 days are dropped on load). picks-log.jsonl +
holdings.json + signal-perf.json persist via state.sh to the alpha-hunt-state branch (never TTL'd; the
durable memory across runs). **`news-seen.json` and `sentiment-history.json` are ALSO in state.sh's
persisted set** — both are history-ACCUMULATING caches that compare against prior WEEKS (cross-week
rehash detection; the sentiment z-score baseline), so a weekly wipe would make every story look fresh
forever and leave the z-score permanently "history accumulating". Both would then silently no-op
rather than fail loudly — the worst failure mode. Anything that compares across runs MUST go in
state.sh; anything derivable from a single run must NOT (it just bloats the state branch).

## New data sources (2026 research upgrades — all free/keyless)
- **Options-implied signals from the CBOE chain ALREADY fetched** (`cdn.cboe.com/.../options/{T}.json`):
  derive IV skew (25Δ put IV − ATM IV), volatility spread (ATM call − put IV), and O/S ratio in code —
  no new source, no key. See signals.md "Options-implied informed-trading."
- **FINRA daily short-volume** — single keyless file, whole market:
  `cdn.finra.org/equity/regsho/daily/CNMSshvol{YYYYMMDD}.txt` (consolidated). Short-volume ratio as a
  MINOR demerit/tiebreaker only (weak academic backing).
- **EDGAR 13D activist feed** — extend the existing getcurrent atom used for Form 4:
  `browse-edgar?action=getcurrent&type=SC%2013D&output=atom` (and `SC 13D/A`). Same UA rule.
- **Social sentiment (veto only)**: ApeWisdom (`apewisdom.io/api/v1.0/filter/all-stocks`, free JSON,
  Reddit/StockTwits mention counts) + Google Trends via the `pytrends` idea (SVI). Compute 30-day
  z-scores. Use to VETO/trim crowded names, never to buy (signals.md).
- **Dealer GEX — NOT a dial input, NOT implemented.** The regime dial is fixed at exactly FOUR inputs
  summing to −3..+3 (regime-throttle.md); there is no fifth vote and no code computes one. Recorded
  here only as a research note: SPX/SPY gamma exposure from the CBOE index-options chain is orthogonal
  to the VIX-term-structure vote (calm contango + structurally negative dealer gamma is a distinct
  fragile setup). Legit mechanism, oversold by retail. Adding it would mean re-deriving the whole
  score range — do not wire it in as a bonus input.
- Reference build (do NOT depend on, study only): `jsconiers/traders-edge-mcp` (free CBOE+FRED GEX/
  flip/walls/max-pain/vanna/charm) for formulas if implementing alpha-hunt's own version.
- **Blacklist naive close-price execution on monthly OPEX Fridays + quarterly triple-witching** —
  known mechanical vanna/charm-unwind flow distorts those sessions.
