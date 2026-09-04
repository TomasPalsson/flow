#!/usr/bin/env node
/**
 * fetch-sentiment.js
 * Social-sentiment VETO signal for alpha-hunt (references/signals.md "Social sentiment").
 * Source: apewisdom.io (free, keyless, Reddit + StockTwits mention counts), paginated via
 * /page/N. Live-verified shape (2026-07):
 *   { count, pages, current_page, results: [ { rank, ticker, name, mentions, upvotes,
 *     rank_24h_ago, mentions_24h_ago }, ... ] }  -- ~100 results per page.
 *
 * *** VETO / TRIM ONLY -- THIS SIGNAL MUST NEVER INITIATE A POSITION. ***
 * A name already spiking in retail attention is LATE (operationalizes "buy the rumor, sell
 * the news"). Use a high mention_z to veto or trim an otherwise-good long candidate. Never
 * use it to source or justify a buy.
 *
 * ApeWisdom's endpoint is a POINT-IN-TIME snapshot, not a history series -- there is no way
 * to ask it for "30 days ago". So this script builds its own series: every run appends the
 * FULL current snapshot to ~/.cache/alpha-hunt/sentiment-history.json, pruned to a rolling
 * 60-day retention window. A per-ticker z-score is computed against the trailing 30-day slice
 * of THAT history (signals.md specifies a 30-day mention z-score), and ONLY once >=10
 * historical observations exist in that window (prior runs -- the current run is never counted
 * against itself). Below that threshold every record emits `mention_z: null` with a `note`
 * explaining history is still accumulating. NEVER fabricate a z-score from a single snapshot.
 * A ticker absent from a historical day's snapshot is zero-filled (ApeWisdom's "all-stocks"
 * filter only lists names with >=1 mention that day, so absence reads as zero mentions, not a
 * missing observation) -- this assumption is stated here, not silently baked in.
 *
 * Also emits the raw `mentions`, `rank`, and the 24h change ApeWisdom already provides
 * directly (mentions_24h_ago / rank_24h_ago) -- those are usable from day one, no history
 * required.
 *
 * Output: JSON array to stdout. Progress/warnings to stderr.
 *
 * Usage: node fetch-sentiment.js [TICKER1 TICKER2 ...]
 *   No args   -> top DEFAULT_TOP_N tickers by current mentions (the full snapshot commonly
 *                covers 600-800 names; most of that is irrelevant to any one shortlist).
 *   With args -> exactly those tickers (mentions:0 if absent from today's snapshot -- a real
 *                "not currently trending" data point, not a failure).
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');

const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const HISTORY_FILE = path.join(CACHE_DIR, 'sentiment-history.json');
const USER_AGENT = 'alpha-hunt tomas@p5.is (research)';
const BASE_URL = 'https://apewisdom.io/api/v1.0/filter/all-stocks';
const TIMEOUT_MS = 15000;
const PAGE_SPACING_MS = 300; // no documented rate limit on this free endpoint; polite spacing anyway
const MAX_PAGES = 20; // defensive cap in case the API ever misreports `pages`
const HISTORY_RETENTION_DAYS = 60;
const ZSCORE_WINDOW_DAYS = 30; // signals.md specifies a 30-day mention z-score
const MIN_OBSERVATIONS_FOR_ZSCORE = 10;
const DEFAULT_TOP_N = 50;

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}
function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }
function round(x, d) {
  if (x === null || x === undefined || !Number.isFinite(x)) return null;
  const m = 10 ** d;
  return Math.round(x * m) / m;
}

// Timeout-guarded GET, mirrors fetch-regime.js/preflight.js -- never rejects,
// resolves {status, body} on success or {status: null, error} on failure.
function httpGet(url, headers) {
  return new Promise((resolve) => {
    const req = https.get(url, { headers, timeout: TIMEOUT_MS }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('timeout', () => { req.destroy(new Error('timeout')); });
    req.on('error', (err) => resolve({ status: null, error: err.message }));
  });
}

async function fetchPage(pageNum) {
  const url = pageNum <= 1 ? BASE_URL : `${BASE_URL}/page/${pageNum}`;
  const res = await httpGet(url, { 'User-Agent': USER_AGENT, Accept: 'application/json' });
  if (res.error) throw new Error(`network error: ${res.error}`);
  if (res.status !== 200) throw new Error(`HTTP ${res.status}`);
  let json;
  try { json = JSON.parse(res.body); } catch (e) { throw new Error(`bad JSON: ${e.message}`); }
  if (!Array.isArray(json.results)) throw new Error('response missing results[]');
  return json;
}

async function fetchFullSnapshot() {
  const first = await fetchPage(1);
  const byTicker = new Map();
  for (const r of first.results) {
    if (r.ticker) byTicker.set(r.ticker.toUpperCase(), r);
  }
  const totalPages = Math.min(Number(first.pages) || 1, MAX_PAGES);
  for (let p = 2; p <= totalPages; p++) {
    await sleep(PAGE_SPACING_MS);
    try {
      const page = await fetchPage(p);
      for (const r of page.results) {
        if (r.ticker) byTicker.set(r.ticker.toUpperCase(), r);
      }
    } catch (err) {
      console.error(`WARN: page ${p}/${totalPages} failed (${err.message}) -- snapshot may be partial`);
    }
  }
  return { byTicker, count: first.count, pages: first.pages, pagesFetched: totalPages };
}

function loadHistory() {
  if (!fs.existsSync(HISTORY_FILE)) return [];
  try {
    const parsed = JSON.parse(fs.readFileSync(HISTORY_FILE, 'utf8'));
    return Array.isArray(parsed) ? parsed : [];
  } catch (err) {
    console.error(`WARN: could not parse existing history file (${err.message}) -- starting fresh`);
    return [];
  }
}

function meanOf(arr) { return arr.reduce((a, b) => a + b, 0) / arr.length; }
function stdOf(arr, mean) { return Math.sqrt(arr.reduce((a, b) => a + (b - mean) ** 2, 0) / arr.length); }

async function main() {
  ensureCacheDir();
  const argTickers = process.argv.slice(2).map((t) => t.toUpperCase()).filter(Boolean);

  console.error('Fetching ApeWisdom all-stocks snapshot (paginated)...');
  const { byTicker, count, pages, pagesFetched } = await fetchFullSnapshot();
  console.error(`Snapshot: ${byTicker.size} tickers across ${pagesFetched}/${pages} page(s) (API reports count=${count}).`);

  const nowIso = new Date().toISOString();
  const currentMentions = {};
  for (const [ticker, r] of byTicker) currentMentions[ticker] = r.mentions;

  // Load prior history BEFORE appending this run, so the baseline never
  // includes the observation it's being compared against.
  const history = loadHistory();
  const nowMs = Date.now();
  const windowMs = ZSCORE_WINDOW_DAYS * 24 * 3600 * 1000;
  const baseline = history.filter((h) => nowMs - new Date(h.fetched_at).getTime() <= windowMs);
  const nBaseline = baseline.length;

  // Gate on DISTINCT DAYS, not raw snapshot count. Ten runs in one afternoon satisfies a
  // count-of-observations threshold while carrying zero information about a 30-day distribution —
  // and because those near-identical snapshots have ~zero variance, the naive path then returns
  // z=0, which reads as "perfectly average attention" (a PASS) when the truth is "no idea yet".
  // A veto signal that silently defaults to passing is worse than no signal at all.
  const distinctDays = new Set(baseline.map((h) => String(h.fetched_at).slice(0, 10))).size;

  function computeZ(ticker, currentValue) {
    if (distinctDays < MIN_OBSERVATIONS_FOR_ZSCORE) {
      return { mention_z: null, note: `history accumulating: ${distinctDays}/${MIN_OBSERVATIONS_FOR_ZSCORE} distinct DAYS in the trailing ${ZSCORE_WINDOW_DAYS}d window (${nBaseline} raw snapshots — repeated same-day runs do not count toward the baseline)` };
    }
    // Zero-fill: a ticker absent from a historical snapshot had 0 mentions
    // that day (see header comment on ApeWisdom's "all-stocks" semantics).
    const series = baseline.map((h) => h.mentions[ticker] || 0);
    const mean = meanOf(series);
    const std = stdOf(series, mean);
    if (std === 0) {
      // NEVER return 0 here. A flat baseline means the z-score is undefined, not that attention is
      // average — and 0 would be read downstream as a benign, measured value that clears the veto.
      return { mention_z: null, note: `zero-variance ${ZSCORE_WINDOW_DAYS}d baseline (constant mention count) -- z-score undefined; treat as UNKNOWN, never as a pass` };
    }
    return { mention_z: round((currentValue - mean) / std, 3), note: null };
  }

  // Append this run's FULL snapshot to history (not filtered by argv), so
  // the baseline stays comprehensive regardless of what this run's caller
  // asked to see. Then prune to the 60-day retention window.
  history.push({ fetched_at: nowIso, mentions: currentMentions });
  const retentionMs = HISTORY_RETENTION_DAYS * 24 * 3600 * 1000;
  const pruned = history.filter((h) => nowMs - new Date(h.fetched_at).getTime() <= retentionMs);
  fs.writeFileSync(HISTORY_FILE, JSON.stringify(pruned, null, 2));
  console.error(`History: ${pruned.length} run(s) retained (rolling ${HISTORY_RETENTION_DAYS}d), ${nBaseline} in the ${ZSCORE_WINDOW_DAYS}d z-score baseline for this run.`);

  // Build output records.
  let tickers;
  if (argTickers.length > 0) {
    tickers = [...new Set(argTickers)];
  } else {
    tickers = [...byTicker.keys()]
      .sort((a, b) => (byTicker.get(b).mentions || 0) - (byTicker.get(a).mentions || 0))
      .slice(0, DEFAULT_TOP_N);
  }

  const results = tickers.map((ticker) => {
    const r = byTicker.get(ticker);
    const mentions = r ? r.mentions : 0;
    const { mention_z, note: zNote } = computeZ(ticker, mentions);
    const notes = [];
    if (!r) notes.push("not present in today's ApeWisdom snapshot (treated as 0 mentions)");
    if (zNote) notes.push(zNote);
    return {
      ticker,
      found_in_snapshot: !!r,
      mentions,
      rank: r ? r.rank : null,
      mentions_24h_ago: r ? r.mentions_24h_ago : null,
      mentions_24h_change: r && typeof r.mentions_24h_ago === 'number' ? mentions - r.mentions_24h_ago : null,
      rank_24h_ago: r ? r.rank_24h_ago : null,
      upvotes: r ? r.upvotes : null,
      mention_z,
      note: notes.length > 0 ? notes.join('; ') : null,
    };
  });

  console.error(`Sentiment: ${results.length} ticker record(s) emitted; VETO/TRIM signal only, never a buy trigger.`);

  process.stdout.write(JSON.stringify(results, null, 2) + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
