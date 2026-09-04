#!/usr/bin/env node
/**
 * compute-atr.js
 * Makes the Chandelier exit (risk-and-sizing.md §6) real. §6 previously marked this
 * NOT IMPLEMENTED because compute-momentum.js keeps only `adjclose` (discarding high/low) and
 * runs on WEEKLY bars, where ATR(22) would span ~5 months instead of the ~1 month LeBeau's
 * Chandelier intends. This script fixes both problems by fetching its own DAILY bars, but ONLY
 * for a SHORTLIST (~15-25 names — the shortlisted/held names at the point sizing happens),
 * NEVER the 1,500-name universe screen — see MAX_TICKERS below.
 *
 * Endpoint (keyless, UA 'Mozilla/5.0'):
 *   https://query1.finance.yahoo.com/v8/finance/chart/{TICKER}?range=6mo&interval=1d
 * Parses `indicators.quote[0].{high,low,close}` — NOT adjclose. True Range needs the RAW
 * high/low/close triple; adjclose retroactively rewrites historical prices for splits/
 * dividends, which would distort day-to-day True Range across such an event inside the window.
 * Accepted risk: a split or large dividend WITHIN the 6mo window itself still shows up as a
 * one-day discontinuity in raw prices and will distort that one day's True Range — but a 6mo
 * window on a liquid shortlisted name is short enough, and Wilder smoothing dilutes one bad
 * bar fast over the other ~120, that this is a minor, accepted risk, not a correctness gap.
 *
 * Per ticker:
 *   true_range (per day) = max(high-low, |high-prev_close|, |low-prev_close|)
 *   atr_22    = Wilder's smoothed ATR over 22 daily bars — this is WILDER'S METHOD, NOT a
 *               simple moving average of True Range. They differ (Wilder smoothing gives
 *               exponentially-decaying weight to all prior TRs, forever; an SMA truncates to
 *               a flat window) and the distinction matters for stop width. Seed: first ATR =
 *               simple mean of the first 22 TRs. Then ATR_t = (ATR_{t-1} * 21 + TR_t) / 22,
 *               carried forward through the rest of the series to the most recent bar.
 *   atr_pct   = atr_22 / last_close — makes stop width comparable across price levels.
 *   highest_close_60d, last_close — trailing 60-trading-day highest close and latest close.
 *   chandelier_stop = highest_close_since_entry - (ATR_MULT * atr_22). "Since entry" is
 *               anchored by an optional `--entry TICKER=YYYY-MM-DD` (repeatable). Without it,
 *               falls back to the trailing 60-day highest close and sets entry_anchored:false
 *               so the caller knows this is an approximation, not a true since-entry stop.
 *   stop_distance_pct = (last_close - chandelier_stop) / last_close.
 *
 * ATR_MULT = 3 (named constant below) is LeBeau's original Chandelier default — an
 * UNVALIDATED PRIOR for this book (no backtest, no resolved-trade history to tune it against;
 * see references/learning-loop.md §7). Do not present it as tuned.
 *
 * Usage: node compute-atr.js AAPL MSFT [--entry AAPL=2026-06-01] [--entry MSFT=2026-05-15]
 * JSON array to stdout (one record per ticker, per-ticker `error` field on failure — a bad
 * ticker never sinks the whole batch). Cached to ~/.cache/alpha-hunt/atr.json. Progress and
 * warnings go to stderr.
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');

const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const CACHE_FILE = path.join(CACHE_DIR, 'atr.json');
const USER_AGENT = 'Mozilla/5.0'; // Yahoo requirement
const ATR_PERIOD = 22; // Wilder ATR lookback, daily bars -- ~1 calendar month (risk-and-sizing.md §6)
const ATR_MULT = 3; // LeBeau's original Chandelier default -- UNVALIDATED PRIOR for this book, not tuned
const HIGHEST_CLOSE_LOOKBACK_DAYS = 60; // fallback anchor when no --entry date is supplied
const MIN_BARS = ATR_PERIOD + 1; // need >=22 True Range values, each of which needs a prior close
const MAX_TICKERS = 30; // hard ceiling -- this script is for a SHORTLIST only, never the universe screen

function fail(msg) {
  throw new Error(msg);
}

function round(x, d) {
  if (x === null || x === undefined || Number.isNaN(x)) return null;
  const m = 10 ** d;
  return Math.round(x * m) / m;
}

function meanOf(arr) {
  return arr.reduce((a, b) => a + b, 0) / arr.length;
}

function isoDate(ts) {
  return new Date(ts * 1000).toISOString().slice(0, 10);
}

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Parse a Yahoo v8 chart response into an ascending {ts, high, low, close} bar array, dropping
// any day where high/low/close isn't all present (holidays/gaps/pre-IPO padding).
function parseChartResponse(data) {
  const chartErr = data && data.chart && data.chart.error;
  if (chartErr) throw new Error(chartErr.description || 'Yahoo chart API error');
  const result = data && data.chart && data.chart.result && data.chart.result[0];
  if (!result) throw new Error('no chart result (invalid ticker?)');
  const timestamps = result.timestamp || [];
  const quote = (result.indicators && result.indicators.quote && result.indicators.quote[0]) || {};
  const highArr = quote.high || [];
  const lowArr = quote.low || [];
  const closeArr = quote.close || [];
  const bars = [];
  for (let i = 0; i < timestamps.length; i++) {
    const h = highArr[i];
    const l = lowArr[i];
    const c = closeArr[i];
    if (h === null || h === undefined || l === null || l === undefined || c === null || c === undefined) continue;
    bars.push({ ts: timestamps[i], high: h, low: l, close: c });
  }
  if (bars.length === 0) throw new Error('no usable high/low/close bars returned');
  return bars;
}

function fetchDailyBars(ticker) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?range=6mo&interval=1d`;
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { 'User-Agent': USER_AGENT }, timeout: 15000 }, (res) => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode}`)); }
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let data;
        try { data = JSON.parse(body); } catch (e) { return reject(new Error(`bad JSON response: ${e.message}`)); }
        try { resolve(parseChartResponse(data)); } catch (e) { reject(e); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', reject);
  });
}

// Wilder's smoothed ATR (NOT a simple moving average past the seed bar -- see the header
// comment). Returns the ATR as matured through to the LAST bar in `bars`, or null if there
// aren't enough True Range values to seed it.
function computeWilderATR(bars) {
  const trs = [];
  for (let i = 1; i < bars.length; i++) {
    const { high, low, close } = bars[i];
    const prevClose = bars[i - 1].close;
    trs.push(Math.max(high - low, Math.abs(high - prevClose), Math.abs(low - prevClose)));
  }
  if (trs.length < ATR_PERIOD) return null;
  let atr = meanOf(trs.slice(0, ATR_PERIOD)); // seed: simple mean of the first 22 TRs
  for (let i = ATR_PERIOD; i < trs.length; i++) {
    atr = (atr * (ATR_PERIOD - 1) + trs[i]) / ATR_PERIOD; // Wilder smoothing, carried to the latest bar
  }
  return atr;
}

function highestCloseOverLastN(bars, n) {
  const slice = bars.slice(Math.max(0, bars.length - n));
  return Math.max(...slice.map((b) => b.close));
}

// --entry TICKER=YYYY-MM-DD (repeatable), interleaved freely with ticker args.
function parseArgs(argv) {
  const tickers = [];
  const entries = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--entry') {
      const spec = argv[i + 1];
      i++;
      const eqIdx = spec ? spec.indexOf('=') : -1;
      if (eqIdx <= 0) fail(`--entry requires TICKER=YYYY-MM-DD, got ${JSON.stringify(spec)}`);
      const t = spec.slice(0, eqIdx).trim().toUpperCase();
      const d = spec.slice(eqIdx + 1).trim();
      if (!/^\d{4}-\d{2}-\d{2}$/.test(d)) fail(`--entry ${spec}: date must be YYYY-MM-DD, got ${JSON.stringify(d)}`);
      entries[t] = d;
    } else {
      tickers.push(a.toUpperCase());
    }
  }
  return { tickers: [...new Set(tickers)], entries };
}

async function processTicker(ticker, entryDateStr) {
  const bars = await fetchDailyBars(ticker);
  if (bars.length < MIN_BARS) fail(`insufficient daily history: need >=${MIN_BARS} bars, got ${bars.length}`);

  const atr22 = computeWilderATR(bars);
  if (atr22 === null || !Number.isFinite(atr22) || atr22 <= 0) fail('ATR computation failed (degenerate True Range series)');

  const lastBar = bars[bars.length - 1];
  const lastClose = lastBar.close;
  if (!Number.isFinite(lastClose) || lastClose <= 0) fail('invalid last close (zero/non-finite)');

  const highestClose60d = highestCloseOverLastN(bars, HIGHEST_CLOSE_LOOKBACK_DAYS);

  let entryAnchored = false;
  let entryWindowTruncated = false;
  let highestCloseSinceEntry = highestClose60d;

  if (entryDateStr) {
    const entryTs = Date.parse(`${entryDateStr}T00:00:00Z`) / 1000;
    if (!Number.isFinite(entryTs)) fail(`invalid --entry date "${entryDateStr}"`);
    if (entryTs > lastBar.ts) fail(`--entry date ${entryDateStr} is after the most recent fetched bar (${isoDate(lastBar.ts)}) -- refusing to anchor on a future entry`);
    if (bars[0].ts > entryTs) entryWindowTruncated = true; // entry predates the fetched 6mo window -- since-entry high may be understated
    const idx = bars.findIndex((b) => b.ts >= entryTs);
    const sinceEntryBars = bars.slice(idx === -1 ? bars.length - 1 : idx);
    highestCloseSinceEntry = Math.max(...sinceEntryBars.map((b) => b.close));
    entryAnchored = true;
  }

  const atrPct = atr22 / lastClose;
  const chandelierStop = highestCloseSinceEntry - ATR_MULT * atr22;
  const stopDistancePct = (lastClose - chandelierStop) / lastClose;

  return {
    ticker,
    as_of: isoDate(lastBar.ts),
    n_bars_used: bars.length,
    last_close: round(lastClose, 4),
    atr_22: round(atr22, 4),
    atr_pct: round(atrPct, 6),
    highest_close_60d: round(highestClose60d, 4),
    highest_close_since_entry: round(highestCloseSinceEntry, 4),
    entry_date: entryAnchored ? entryDateStr : null,
    entry_anchored: entryAnchored,
    entry_window_truncated: entryWindowTruncated,
    chandelier_stop: round(chandelierStop, 4),
    stop_distance_pct: round(stopDistancePct, 6),
    // A NEGATIVE stop_distance_pct means last_close is already BELOW the trailing stop — the name
    // has fallen more than ATR_MULT x ATR(22) off its high, so on this rule it is already stopped
    // out. Surfacing it explicitly matters: a caller that naively places `chandelier_stop` as a
    // stop order on a long would be placing it ABOVE the market, which triggers instantly or is
    // rejected outright. Treat true as an EXIT signal for a held name and a do-not-enter for a new
    // one — never as a stop level to submit.
    already_below_stop: stopDistancePct < 0,
    error: null,
  };
}

async function main() {
  let tickers;
  let entries;
  try {
    ({ tickers, entries } = parseArgs(process.argv.slice(2)));
  } catch (err) {
    console.error(`FATAL: ${err.message}`);
    process.exit(1);
  }

  if (tickers.length === 0) {
    console.error('Usage: node compute-atr.js TICKER1 [TICKER2 ...] [--entry TICKER=YYYY-MM-DD ...]');
    process.exit(1);
  }
  if (tickers.length > MAX_TICKERS) {
    console.error(`FATAL: ${tickers.length} tickers requested, max ${MAX_TICKERS} -- this script computes DAILY-bar ATR for a SHORTLIST only (risk-and-sizing.md §6), never the 1,500-name universe. Run compute-momentum.js for universe-wide screening.`);
    process.exit(1);
  }
  for (const t of Object.keys(entries)) {
    if (!tickers.includes(t)) console.error(`WARN: --entry ${t}=${entries[t]} given but ${t} is not in the ticker list -- ignored`);
  }

  ensureCacheDir();

  const results = [];
  for (let i = 0; i < tickers.length; i++) {
    const ticker = tickers[i];
    console.error(`Fetching daily bars for ${ticker} (${i + 1}/${tickers.length})...`);
    if (i > 0) await sleep(110 + Math.floor(Math.random() * 60)); // polite stagger, well under ~10 req/sec
    try {
      results.push(await processTicker(ticker, entries[ticker] || null));
    } catch (err) {
      console.error(`WARN: ${ticker}: ${err.message} -- skipping`);
      results.push({ ticker, error: err.message });
    }
  }

  const okCount = results.filter((r) => !r.error).length;
  console.error(`ATR/Chandelier: ${okCount}/${tickers.length} succeeded.`);

  const payload = {
    fetched_at: new Date().toISOString(),
    atr_period: ATR_PERIOD,
    atr_mult: ATR_MULT,
    highest_close_lookback_days: HIGHEST_CLOSE_LOOKBACK_DAYS,
    results,
  };
  fs.writeFileSync(CACHE_FILE, JSON.stringify(payload, null, 2));

  process.stdout.write(JSON.stringify(results, null, 2) + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
