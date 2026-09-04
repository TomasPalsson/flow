#!/usr/bin/env node
/**
 * fetch-catalysts.js
 * The catalyst engine for alpha-hunt. Pulls dated catalysts from Finnhub
 * (earnings calendar, recommendation-trend revisions, company news) plus the
 * SEC market-wide Form-4 feed (fresh insider-activity NAME DISCOVERY only --
 * per-ticker Form-4 detail belongs to the investment skill's fetch-insider.js),
 * the SEC market-wide SC 13D activist feed, and (new) the SEC EDGAR full-text-
 * search 8-K feed for Item-code triage (signals.md "8-K Item-code triage").
 *
 * Every candidate in the output 'catalysts' array carries a 'date' field.
 * Candidates without a date are dropped.
 *
 * Requires: FINNHUB_API_KEY env var (exits 1 if absent).
 * Caching: writes ~/.cache/alpha-hunt/catalysts.json (always refreshed; no TTL
 * reuse, since catalysts are time-sensitive by design). Separately maintains
 * ~/.cache/alpha-hunt/news-seen.json -- a rolling 60-day cross-week memory of
 * seen headlines per ticker, used to flag REHASHED (stale, re-reported) news
 * as a FADE signal rather than a fresh catalyst. See fetchNews below. NOTE:
 * this file is NOT currently in scripts/state.sh's persisted set (only
 * picks-log.jsonl/holdings.json/signal-perf.json survive the routine's weekly
 * fresh container) -- until it is added there, cross-week rehash detection
 * only works within a single long-lived cache, not across the weekly reset.
 *
 * Usage: node fetch-catalysts.js [TICKER1 TICKER2 ...]
 *   No args -> deep-dive the top ~15 names from the earnings calendar.
 *   With args -> deep-dive the given watchlist tickers instead.
 */

const fs = require('fs');
const path = require('path');
const os = require('os');
const https = require('https');

const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const CACHE_FILE = path.join(CACHE_DIR, 'catalysts.json');
const USER_AGENT_SEC = 'alpha-hunt tomas@p5.is (research)';
const FINNHUB_BASE = 'https://finnhub.io/api/v1';
const FINNHUB_MIN_SPACING_MS = 1100; // stay under 60/min
const DEEP_DIVE_LIMIT = 15;

// --- SEC EDGAR full-text-search 8-K feed (Task: 8-K Item-code triage) -----
// Verified live (2026-07): https://efts.sec.gov/LATEST/search-index?forms=8-K
// &dateRange=custom&startdt=YYYY-MM-DD&enddt=YYYY-MM-DD&from=N (no 'q' param
// needed/used -- omitting 'q' returns ALL matching 8-Ks, newest-first, 100
// hits/page, paginated via 'from'). Each hit's _source already carries the
// parsed Item codes in an 'items' array plus ciks/display_names/file_date/
// adsh -- no need to fetch and regex individual filing bodies. Same UA/rate
// rules as the rest of SEC EDGAR (data-runbook.md).
const SEC_FTS_BASE = 'https://efts.sec.gov/LATEST/search-index';
const SEC_MIN_SPACING_MS = 120; // stay under the SEC's ~10 req/sec fair-access limit
const EIGHTK_LOOKBACK_DAYS = 7; // matches fetchNews's weekly window -- the weekly catalyst-intake cadence
const EIGHTK_PAGE_SIZE = 100; // fixed by the API
const EIGHTK_MAX_PAGES = 10; // safety cap (<=1,000 filings/week); a heavy week may not be fully covered -- see the WARN log

// MATERIAL (tier A) 8-K item codes -- real, dated, price-moving events.
// 4.02 (non-reliance / restatement) is included here for SALIENCE (it is a
// genuinely material dated event, not noise) but every 4.02 record is ALSO
// flagged negative_signal:true in fetchRecent8K -- a restatement is a red
// flag to AVOID, never a buy catalyst. Downstream scoring MUST check
// negative_signal before treating a tier-A 8-K as bullish.
const MATERIAL_8K_ITEMS = {
  '2.02': 'Results of Operations and Financial Condition',
  '1.01': 'Entry into a Material Definitive Agreement',
  '4.02': 'Non-Reliance on Previously Issued Financials (Restatement) -- NEGATIVE signal, see negative_signal',
  '2.06': 'Material Impairments',
  '3.01': 'Notice of Delisting / Failure to Satisfy a Listing Rule',
  '5.02': 'Departure/Appointment of Directors or Certain Officers',
  '2.04': 'Triggering Events That Accelerate a Direct Financial Obligation',
  '1.02': 'Termination of a Material Definitive Agreement',
};

// NOISE (tier C) 8-K item codes -- down-weighted per signals.md ("8-K
// Item-code triage": down-weight the 8.01 catch-all). A filing whose ONLY
// items fall in here (or in neither map) carries no evidenced edge, just a
// filing date.
const NOISE_8K_ITEMS = {
  '8.01': 'Other Events',
  '7.01': 'Regulation FD Disclosure',
  '9.01': 'Financial Statements and Exhibits',
};

// --- Cross-week news-rehash detection (Task: staleness) --------------------
// Tetlock (2011) "All the News That's Fit to Reprint": investors OVERREACT to
// STALE/reprinted information and those moves REVERSE, measured at a weekly
// horizon -- matches this skill's weekly cadence. A rehashed story is
// therefore a FADE/demerit, never a buy catalyst. fetchNews's existing 60-char
// headline-prefix dedup only catches repeats WITHIN one 7-day pull; this adds
// PERSISTENT memory across pulls so a story recycled the following week is
// visible too.
const NEWS_SEEN_FILE = path.join(CACHE_DIR, 'news-seen.json');
const NEWS_SEEN_TTL_DAYS = 60; // rolling prune window for the persistent store
const NEWS_LOOKBACK_DAYS = 7; // must match fetchNews's own pull window -- the "prior week" boundary
// Jaccard-similarity threshold for headline-token-set near-duplicates. 0.6 is
// a TUNABLE, UNVALIDATED default -- no backtest has confirmed this cutoff.
const JACCARD_THRESHOLD = 0.6;
const NEWS_STOPWORDS = new Set([
  'a', 'an', 'the', 'and', 'or', 'but', 'of', 'to', 'in', 'on', 'at', 'for', 'with', 'by',
  'is', 'are', 'was', 'were', 'be', 'been', 'being', 'it', 'its', 'this', 'that', 'as',
  'from', 'has', 'have', 'had', 'will', 'would', 'could', 'should', 'may', 'might',
  'not', 'no', 'than', 'then', 'into', 'over', 'after', 'before', 'about', 'up', 'down',
  'out', 'off', 'said', 'says', 'say', 'new',
]);

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function getJson(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT_SEC, Accept: 'application/json', ...headers } }, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        if (res.statusCode === 429) {
          const err = new Error('HTTP 429');
          err.statusCode = 429;
          return reject(err);
        }
        if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
        try {
          resolve(JSON.parse(body));
        } catch (e) {
          reject(new Error(`Bad JSON from ${url}: ${e.message}`));
        }
      });
    }).on('error', reject);
  });
}

function getText(url, headers) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT_SEC, ...headers } }, (res) => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });
}

// Finnhub GET with 429 backoff: wait 15s, retry once.
async function getFinnhub(pathAndQuery) {
  const key = process.env.FINNHUB_API_KEY;
  const sep = pathAndQuery.includes('?') ? '&' : '?';
  const url = `${FINNHUB_BASE}${pathAndQuery}${sep}token=${key}`;
  try {
    return await getJson(url);
  } catch (err) {
    if (err.statusCode === 429) {
      console.error(`WARN: Finnhub 429 rate-limited on ${pathAndQuery}, backing off 15s and retrying once`);
      await sleep(15000);
      return getJson(url);
    }
    throw err;
  }
}

function toISODate(d) {
  return d.toISOString().slice(0, 10);
}

async function fetchEarningsCalendar() {
  const today = new Date();
  const to = new Date(today.getTime() + 14 * 24 * 3600 * 1000);
  const data = await getFinnhub(`/calendar/earnings?from=${toISODate(today)}&to=${toISODate(to)}`);
  return data.earningsCalendar || [];
}

async function fetchEstimateRevision(ticker) {
  const trend = await getFinnhub(`/stock/recommendation?symbol=${encodeURIComponent(ticker)}`);
  if (!Array.isArray(trend) || trend.length < 2) return null;
  // Finnhub returns most-recent period first.
  const current = trend[0];
  const prior = trend[1];
  const curBull = (current.buy || 0) + (current.strongBuy || 0);
  const priorBull = (prior.buy || 0) + (prior.strongBuy || 0);
  if (curBull !== priorBull) {
    // Revision BREADTH: net shift in analyst buy/strong-buy counts vs the prior
    // period. The magnitude of the shift (net_upgrade_delta), not merely its
    // direction, is the signal. Price-target MAGNITUDE (the ideal refinement)
    // needs Finnhub's premium /stock/price-target endpoint; recommendation-trend
    // breadth is the free-tier proxy.
    // NEVER drop the down case: a NEGATIVE net_upgrade_delta ('down') is a
    // DEMERIT on a deteriorating name, not a catalyst -- it must stay visible
    // to downstream scoring, not be silently swallowed by a > 0 check.
    return {
      ticker,
      type: 'estimate-revision',
      date: current.period,
      net_upgrade_delta: curBull - priorBull,
      direction: curBull > priorBull ? 'up' : 'down',
      buy_strongbuy_current: curBull,
      buy_strongbuy_prior: priorBull,
    };
  }
  return null;
}

// Time-series SUE = (actual_latest - actual_4_quarters_ago) / stdev(last up to
// 8 quarterly YoY EPS changes). Analyst-based SUE ((actual - consensus) /
// estimate dispersion) is NOT computed here -- see fetchEarningsSurprise.
function computeSueTimeseries(quarters) {
  const usable = quarters.filter((q) => typeof q.actual === 'number');
  if (usable.length < 5) {
    return {
      sue_timeseries: null,
      sue_note: `only ${usable.length} usable quarter(s) with reported actual EPS -- need >=5 to form a 4-quarter-back time-series SUE`,
      n_quarters: usable.length,
    };
  }
  // YoY EPS change_i = actual[i] - actual[i+4], most recent first, capped at
  // the last 8 such pairs per spec.
  const yoyChanges = [];
  for (let i = 0; i + 4 < usable.length && i < 8; i++) {
    yoyChanges.push(usable[i].actual - usable[i + 4].actual);
  }
  if (yoyChanges.length === 0) {
    return { sue_timeseries: null, sue_note: 'no quarter pairs 4 apart available', n_quarters: usable.length };
  }
  const mean = yoyChanges.reduce((a, b) => a + b, 0) / yoyChanges.length;
  const variance = yoyChanges.reduce((a, b) => a + (b - mean) ** 2, 0) / yoyChanges.length;
  const stdev = Math.sqrt(variance);
  if (!stdev) {
    return { sue_timeseries: null, sue_note: 'stdev of YoY EPS changes is 0 -- cannot form a ratio', n_quarters: usable.length };
  }
  // yoyChanges[0] === actual_latest - actual_4_quarters_ago by construction.
  return { sue_timeseries: yoyChanges[0] / stdev, sue_note: null, n_quarters: usable.length };
}

// Real SUE, both forms from signals.md -- MANDATORY, this is the headline gap
// this fix exists to close. net_upgrade_delta (fetchEstimateRevision, above)
// is analyst-COUNT breadth, NOT an earnings-surprise signal; do not conflate
// the two upstream.
async function fetchEarningsSurprise(ticker) {
  const data = await getFinnhub(`/stock/earnings?symbol=${encodeURIComponent(ticker)}`);
  if (!Array.isArray(data) || data.length === 0) return null;
  const latest = data[0]; // Finnhub returns most-recent quarter first.
  if (latest.actual == null || latest.estimate == null) return null; // no reported print yet
  const { sue_timeseries, sue_note, n_quarters } = computeSueTimeseries(data);
  return {
    ticker,
    type: 'earnings-surprise',
    date: latest.period,
    actual: latest.actual,
    estimate: latest.estimate,
    surprise_pct: latest.surprisePercent ?? null,
    sue_timeseries,
    sue_note,
    n_quarters,
    // Analyst-based SUE needs estimate DISPERSION across analysts -- paywalled
    // on the Finnhub free tier. NEVER fabricate or substitute a different
    // signal here; be explicit that it is unavailable instead.
    sue_analyst: null,
    sue_analyst_note: 'estimate dispersion is paywalled on the Finnhub free tier',
  };
}

// Lowercase, strip punctuation, drop stopwords -> token set for Jaccard.
function tokenizeHeadline(text) {
  return new Set(
    String(text || '')
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .filter((w) => w && !NEWS_STOPWORDS.has(w))
  );
}

function jaccardSimilarity(setA, setB) {
  if (setA.size === 0 || setB.size === 0) return 0;
  let intersection = 0;
  for (const t of setA) if (setB.has(t)) intersection++;
  const union = setA.size + setB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

function loadNewsSeenStore() {
  try {
    const parsed = JSON.parse(fs.readFileSync(NEWS_SEEN_FILE, 'utf8'));
    if (parsed && Array.isArray(parsed.entries)) return parsed;
  } catch (err) {
    if (err.code !== 'ENOENT') console.error(`WARN: could not read news-seen store (${NEWS_SEEN_FILE}), starting fresh: ${err.message}`);
  }
  return { updated_at: null, entries: [] };
}

// Rolling ~60-day prune, keyed off each entry's first_seen date.
function pruneNewsSeenStore(store, now) {
  const cutoff = now.getTime() - NEWS_SEEN_TTL_DAYS * 24 * 3600 * 1000;
  const before = store.entries.length;
  store.entries = store.entries.filter((e) => {
    const t = Date.parse(e.first_seen);
    return !Number.isNaN(t) && t >= cutoff;
  });
  const dropped = before - store.entries.length;
  if (dropped > 0) console.error(`Pruned ${dropped} news-seen entr${dropped === 1 ? 'y' : 'ies'} older than ${NEWS_SEEN_TTL_DAYS}d.`);
  return store;
}

function saveNewsSeenStore(store) {
  store.updated_at = new Date().toISOString();
  fs.writeFileSync(NEWS_SEEN_FILE, JSON.stringify(store, null, 2));
}

// 'store' is the persistent cross-week news-seen memory (see NEWS_SEEN_FILE
// above): loaded once in main(), mutated here, saved once at the end of main().
async function fetchNews(ticker, store) {
  const today = new Date();
  const from = new Date(today.getTime() - 7 * 24 * 3600 * 1000);
  const items = await getFinnhub(`/company-news?symbol=${encodeURIComponent(ticker)}&from=${toISODate(from)}&to=${toISODate(today)}`);
  if (!Array.isArray(items)) return [];
  const seen = new Map(); // key: headline prefix (60 chars) -> earliest datetime item (WITHIN this single 7-day pull)
  for (const item of items) {
    if (!item.datetime) continue; // require a concrete datetime
    const key = String(item.headline || '').slice(0, 60);
    const existing = seen.get(key);
    if (!existing || item.datetime < existing.datetime) seen.set(key, item);
  }
  const out = [];
  for (const item of seen.values()) {
    const headline = item.headline || '';
    const tokens = tokenizeHeadline(headline);
    // Cross-WEEK check (this is on top of, not instead of, the within-run
    // dedup above): does this headline near-match a same-ticker entry
    // already in the persistent store, first seen in a PRIOR week's run?
    let bestMatch = null;
    let bestSim = 0;
    for (const entry of store.entries) {
      if (entry.ticker !== ticker) continue;
      const sim = jaccardSimilarity(tokens, tokenizeHeadline(entry.headline));
      if (sim >= JACCARD_THRESHOLD && sim > bestSim) {
        bestSim = sim;
        bestMatch = entry;
      }
    }
    const stalenessDays = bestMatch ? Math.floor((today.getTime() - Date.parse(bestMatch.first_seen)) / (24 * 3600 * 1000)) : null;
    const isRehash = !!bestMatch && stalenessDays >= NEWS_LOOKBACK_DAYS; // "prior week", not this run's own first-seen
    const record = {
      ticker,
      type: 'news',
      date: new Date(item.datetime * 1000).toISOString().slice(0, 10),
      headline,
      url: item.url,
      is_rehash: isRehash,
      first_seen: bestMatch ? bestMatch.first_seen : toISODate(today),
      staleness_days: isRehash ? stalenessDays : 0,
    };
    if (isRehash) {
      // FADE signal (Tetlock 2011), not a catalyst -- see tierFor.
      record.note = 'REHASH -- near-duplicate of a story first seen in a prior week; stale-information reactions REVERSE at a weekly horizon (Tetlock 2011), so this is a FADE, never a fresh buy catalyst.';
    } else if (!bestMatch) {
      // Genuinely new: append so a future week's run can detect a rehash of THIS story.
      store.entries.push({ key: `${ticker}|${headline.slice(0, 80)}`, ticker, first_seen: toISODate(today), headline });
    }
    out.push(record);
  }
  return out;
}

function parseForm4Atom(xml) {
  // SEC's getcurrent "type=4" query param does PREFIX matching, not exact --
  // the raw feed also contains 425 / 424B2 / 424B3 / 497AD etc. Titles look
  // like "<FORM_TYPE> - <ISSUER/PERSON> (<CIK>) (<ROLE>)"; keep only the
  // exact Form 4 family (4, 4/A).
  const entries = [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)];
  const out = [];
  for (const m of entries) {
    const block = m[1];
    const title = block.match(/<title>([^<]*)<\/title>/)?.[1]?.trim();
    const updated = block.match(/<updated>([^<]+)<\/updated>/)?.[1];
    const link = block.match(/<link[^>]*href="([^"]+)"/)?.[1];
    if (!title || !updated) continue;
    if (!/^4(\/A)? -/.test(title)) continue; // drop 425/424B2/... false-prefix matches
    out.push({ type: 'insider-form4', date: updated.slice(0, 10), entity: title, url: link || null });
  }
  return out;
}

// SEC market-wide Form-4 atom feed: discovery of NEW names filing insider
// transactions right now. Per-ticker Form-4 detail/cluster analysis is the
// investment skill's job (fetch-insider.js) -- this is a fresh-name radar.
async function fetchForm4Discovery() {
  const url = 'https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&type=4&company=&dateb=&owner=include&count=100&output=atom';
  const xml = await getText(url);
  return parseForm4Atom(xml);
}

function parseActivist13DAtom(xml) {
  // Same PREFIX-matching caution as Form 4: SEC's getcurrent "type=SC 13D"
  // query also pollutes with SC 13G, SC 13E3, and amendment variants. Titles
  // look like "<FORM_TYPE> - <ISSUER/PERSON> (<CIK>) (<ROLE>)"; keep only the
  // exact SC 13D family (SC 13D, SC 13D/A).
  const entries = [...xml.matchAll(/<entry>([\s\S]*?)<\/entry>/g)];
  const out = [];
  for (const m of entries) {
    const block = m[1];
    const title = block.match(/<title>([^<]*)<\/title>/)?.[1]?.trim();
    const updated = block.match(/<updated>([^<]+)<\/updated>/)?.[1];
    const link = block.match(/<link[^>]*href="([^"]+)"/)?.[1];
    if (!title || !updated) continue;
    if (!/^SC 13D(\/A)? -/.test(title)) continue; // drop SC 13G/SC 13E3/... false-prefix matches
    // Name-discovery only, exactly like fetchForm4Discovery -- the per-ticker
    // confirmation (and 13D vs 13D/A escalation-language scoring) is a
    // separate stage, not this feed's job.
    out.push({ ticker: null, type: 'activist-13d', date: updated.slice(0, 10), entity: title, url: link || null });
  }
  return out;
}

// SEC market-wide SC 13D/13D-A atom feed: discovery of fresh activist stakes
// right now. HIGH-value catalyst per signals.md; mirrors fetchForm4Discovery
// exactly (same SEC UA, same atom parsing, same defensive title filter).
async function fetchActivist13D() {
  const url = 'https://www.sec.gov/cgi-bin/browse-edgar?action=getcurrent&type=SC+13D&company=&dateb=&owner=include&count=100&output=atom';
  const xml = await getText(url);
  return parseActivist13DAtom(xml);
}

// Extract "(TICKER)" (or the first of several comma-separated tickers) from
// an EDGAR full-text-search display_name, e.g.
// "NEOGENOMICS INC  (NEO)  (CIK 0001077183)" -> "NEO", or
// "Ramaco Resources, Inc.  (METC, METCB, METCI, METCZ)  (CIK 0001687187)" -> "METC".
// Funds/trusts with no ticker (e.g. "Golub Capital Private Income Fund I
// (CIK 0002082559)") have no such group and correctly resolve to null.
function extractTickerFromDisplayName(name) {
  const m = /\(([A-Z][A-Z0-9.\-]*(?:,\s*[A-Z0-9.\-]+)*)\)\s*\(CIK/.exec(name || '');
  if (!m) return null;
  return m[1].split(',')[0].trim();
}

// Build the filing document URL from an EDGAR full-text-search hit, e.g.
// ciks:["0001077183"], adsh:"0001077183-26-000049", _id:"...:neo-20260720.htm"
// -> https://www.sec.gov/Archives/edgar/data/1077183/000107718326000049/neo-20260720.htm
// (verified live, 2026-07).
function filingUrlFromHit(hit) {
  const cik = String((hit.ciks && hit.ciks[0]) || '').replace(/^0+/, '');
  const adshNoDashes = String(hit.adsh || '').replace(/-/g, '');
  const filename = String(hit._id || '').split(':')[1];
  if (!cik || !adshNoDashes || !filename) return null;
  return `https://www.sec.gov/Archives/edgar/data/${cik}/${adshNoDashes}/${filename}`;
}

function labelFor8KItem(code) {
  return MATERIAL_8K_ITEMS[code] || NOISE_8K_ITEMS[code] || null;
}

// SEC EDGAR full-text-search 8-K feed: pulls the trailing EIGHTK_LOOKBACK_DAYS
// window of ALL 8-Ks market-wide (name discovery, like fetchForm4Discovery /
// fetchActivist13D), reading each hit's already-parsed 'items' array for
// Item-code triage -- no per-filing fetch/regex needed. Paginated (100/page)
// newest-first via 'from='; capped at EIGHTK_MAX_PAGES as a safety limit on a
// heavy filing week (a WARN is logged if the cap truncates real results).
async function fetchRecent8K() {
  const today = new Date();
  const from = new Date(today.getTime() - EIGHTK_LOOKBACK_DAYS * 24 * 3600 * 1000);
  const startdt = toISODate(from);
  const enddt = toISODate(today);
  const out = [];
  let page = 0;
  let total = Infinity;
  while (page * EIGHTK_PAGE_SIZE < total && page < EIGHTK_MAX_PAGES) {
    if (page > 0) await sleep(SEC_MIN_SPACING_MS);
    const url = `${SEC_FTS_BASE}?forms=8-K&dateRange=custom&startdt=${startdt}&enddt=${enddt}&from=${page * EIGHTK_PAGE_SIZE}`;
    const data = await getJson(url);
    total = (data && data.hits && data.hits.total && data.hits.total.value) || 0;
    const hits = (data && data.hits && data.hits.hits) || [];
    if (hits.length === 0) break; // defensive: stop on an empty page even if 'total' claimed more
    for (const hit of hits) {
      const src = hit._source || {};
      const items = Array.isArray(src.items) ? src.items : [];
      out.push({
        ticker: extractTickerFromDisplayName((src.display_names || [])[0]),
        type: '8-K',
        date: src.file_date || null,
        items,
        item_labels: items.map(labelFor8KItem).filter(Boolean),
        entity: (src.display_names || [])[0] || null,
        url: filingUrlFromHit({ ciks: src.ciks, adsh: src.adsh, _id: hit._id }),
        // 4.02 (non-reliance / restatement) is a restatement red flag -- NEVER
        // a buy catalyst. See MATERIAL_8K_ITEMS comment and tierFor.
        negative_signal: items.includes('4.02'),
      });
    }
    page++;
  }
  if (total > page * EIGHTK_PAGE_SIZE) {
    console.error(`WARN: SEC 8-K feed truncated at ${EIGHTK_MAX_PAGES} pages (${out.length} of ${total} filings in the ${EIGHTK_LOOKBACK_DAYS}-day window) -- oldest end of the window may be missing.`);
  }
  return out;
}

// --- Catalyst tiering ------------------------------------------------------
// A tier tells downstream scoring whether a catalyst is real, evidenced signal
// or merely a scheduled DATE. It labels only -- it does not filter anything
// here. Tier C (a bare scheduled 'earnings' calendar entry, or generic 'news')
// is a DATE, not an edge: a name printing within 14 days is not automatically
// a real catalyst just because it has one on the calendar. Downstream scoring
// MUST NOT let a tier-C entry alone satisfy the "every pick needs a dated
// catalyst" gate.
function tierFor(c) {
  if (c.type === 'earnings-surprise' || c.type === 'activist-13d' || c.type === 'insider-form4') return 'A';
  if (c.type === 'estimate-revision') return c.direction === 'up' ? 'B' : null; // 'down' is a demerit, not a gate-qualifying catalyst
  if (c.type === '8-K') {
    // A MATERIAL item code (see MATERIAL_8K_ITEMS) makes this tier A; an
    // 8.01/7.01/9.01-only filing (or any other non-material item) is tier C --
    // a bare filing date, not an edge. NOTE: 4.02 (restatement) is tier A for
    // SALIENCE but is ALSO negative_signal:true (set in fetchRecent8K) --
    // downstream scoring MUST check negative_signal before treating a
    // tier-A 8-K as a bullish catalyst; a restatement is an AVOID, not a buy.
    return (c.items || []).some((code) => MATERIAL_8K_ITEMS[code]) ? 'A' : 'C';
  }
  if (c.type === 'news' && c.is_rehash) return 'C'; // FADE signal (Tetlock 2011), forced tier C even though 'news' is already always C below
  if (c.type === 'earnings' || c.type === 'news') return 'C';
  return null;
}

async function main() {
  const apiKey = process.env.FINNHUB_API_KEY;
  if (!apiKey) {
    console.error('FATAL: FINNHUB_API_KEY is not set. Export it and retry.');
    process.exit(1);
  }

  ensureCacheDir();
  const argTickers = process.argv.slice(2).map((t) => t.toUpperCase()).filter(Boolean);
  const catalysts = [];
  const newsSeenStore = pruneNewsSeenStore(loadNewsSeenStore(), new Date());

  console.error('Fetching Finnhub earnings calendar (next 14 days)...');
  let earningsCalendar = [];
  try {
    earningsCalendar = await fetchEarningsCalendar();
    for (const e of earningsCalendar) {
      if (!e.date || !e.symbol) continue;
      catalysts.push({ ticker: e.symbol, type: 'earnings', date: e.date, epsEstimate: e.epsEstimate ?? null });
    }
  } catch (err) {
    console.error(`WARN: earnings calendar fetch failed: ${err.message}`);
  }

  const deepDiveTickers = argTickers.length > 0
    ? argTickers
    : [...new Set(earningsCalendar.map((e) => e.symbol).filter(Boolean))].slice(0, DEEP_DIVE_LIMIT);

  console.error(`Deep-diving ${deepDiveTickers.length} ticker(s): ${deepDiveTickers.join(', ') || '(none)'}`);

  for (const ticker of deepDiveTickers) {
    await sleep(FINNHUB_MIN_SPACING_MS);
    try {
      const revision = await fetchEstimateRevision(ticker);
      if (revision) catalysts.push(revision);
    } catch (err) {
      console.error(`WARN: recommendation trend fetch failed for ${ticker}: ${err.message}`);
    }

    await sleep(FINNHUB_MIN_SPACING_MS);
    try {
      catalysts.push(...(await fetchNews(ticker, newsSeenStore)));
    } catch (err) {
      console.error(`WARN: company news fetch failed for ${ticker}: ${err.message}`);
    }

    await sleep(FINNHUB_MIN_SPACING_MS);
    try {
      const surprise = await fetchEarningsSurprise(ticker);
      if (surprise) catalysts.push(surprise);
    } catch (err) {
      console.error(`WARN: earnings surprise fetch failed for ${ticker}: ${err.message}`);
    }
  }

  console.error('Fetching SEC market-wide Form-4 feed (name discovery)...');
  try {
    catalysts.push(...(await fetchForm4Discovery()));
  } catch (err) {
    console.error(`WARN: SEC Form-4 feed fetch failed: ${err.message}`);
  }

  console.error('Fetching SEC market-wide SC 13D activist feed (name discovery)...');
  try {
    catalysts.push(...(await fetchActivist13D()));
  } catch (err) {
    console.error(`WARN: SEC SC 13D feed fetch failed: ${err.message}`);
  }

  console.error(`Fetching SEC EDGAR full-text-search 8-K feed (item-code triage, last ${EIGHTK_LOOKBACK_DAYS}d, name discovery)...`);
  try {
    catalysts.push(...(await fetchRecent8K()));
  } catch (err) {
    console.error(`WARN: SEC 8-K feed fetch failed: ${err.message}`);
  }

  try {
    saveNewsSeenStore(newsSeenStore);
    console.error(`News-seen store: ${newsSeenStore.entries.length} entr${newsSeenStore.entries.length === 1 ? 'y' : 'ies'} persisted to ${NEWS_SEEN_FILE} (synced across weeks by scripts/state.sh -- required, since cross-week rehash detection compares against prior weeks).`);
  } catch (err) {
    console.error(`WARN: failed to persist news-seen store: ${err.message}`);
  }

  for (const c of catalysts) c.tier = tierFor(c);

  const datedCatalysts = catalysts.filter((c) => !!c.date);
  const dropped = catalysts.length - datedCatalysts.length;
  if (dropped > 0) console.error(`Dropped ${dropped} candidate(s) missing a 'date' field.`);

  const result = {
    fetched_at: new Date().toISOString(),
    earnings_calendar: earningsCalendar,
    catalysts: datedCatalysts,
  };

  const out = JSON.stringify(result, null, 2);
  fs.writeFileSync(CACHE_FILE, out);
  process.stdout.write(out + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
