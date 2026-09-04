#!/usr/bin/env node
/**
 * compute-options-signals.js
 * Options-implied informed-trading signals (references/signals.md "Options-implied
 * informed-trading" -- "the strongest new signal", five independent peer-reviewed
 * confirmations that informed traders leave footprints in options BEFORE the stock moves).
 *
 * *** CONVICTION CONFIRMER / DEMERIT ON THE CATALYST SLEEVE ONLY. ***
 * *** NEVER a standalone buy trigger. ***
 * Source is CBOE's free delayed quote feed -- 15-MINUTE DELAYED, so this is directional
 * color, not tradeable-precision execution data.
 *
 * Source (free, keyless): https://cdn.cboe.com/api/global/delayed_quotes/options/{TICKER}.json
 * Live-verified shape (2026-07): {timestamp, symbol, data:{current_price, options:[...]}}.
 * Each data.options[] entry is {option, bid, ask, iv, open_interest, volume, delta, gamma,
 * vega, theta, rho, theo, ...}. `option` is an OCC-style symbol, e.g. "AAPL260727C00205000"
 * = root "AAPL" + expiry YYMMDD "260727" + type "C" + strike*1000 zero-padded to 8 digits
 * "00205000" ($205.00 strike). Put deltas come back NEGATIVE (e.g. -0.25 for a 25-delta put).
 *
 * EXPIRY RULE (per spec): use the NEAREST expiry that is AT LEAST 7 CALENDAR DAYS OUT --
 * never the literal nearest listed expiry, which is frequently <7d out and too close to
 * expiration for a stable IV read (gamma/theta noise dominates near-dated legs).
 *
 * Per ticker at that expiry:
 *   iv_skew    = IV of the ~25-delta PUT minus a blended ATM IV (avg of ATM call/put IV).
 *                ELEVATED (positive) put skew = informed downside positioning = a DEMERIT
 *                for a long. Flattening/low skew on a momentum name reads clean.
 *   vol_spread = ATM call IV minus ATM put IV. Positive (calls bid over puts) leans bullish.
 *   os_ratio   = TOTAL option volume (summed across the WHOLE chain, all expiries) / stock
 *                volume (most recent session, Yahoo v8 chart range=1mo&interval=1d, UA
 *                'Mozilla/5.0'; null if unavailable -- NEVER guessed). Pan & Poteshman: the
 *                skew signal is only informative where options activity is unusually high --
 *                this script does NOT gate on that itself, it just emits the raw ratio so the
 *                orchestrator can gate on the TOP QUINTILE of os_ratio across the shortlist.
 *
 * CONTRACT SELECTION: prefer delta (ATM = call delta nearest 0.5 / put delta nearest -0.5;
 * 25-delta put = put delta nearest -0.25). If there isn't enough usable (iv>0, correctly
 * signed, non-zero) delta data at the target expiry -- which happens on thin/illiquid
 * chains where CBOE's delta field is present but degenerate (0.0) -- fall back to: ATM =
 * strike nearest current_price, 25-delta put APPROXIMATED as the put ~10% out-of-the-money
 * (a standard rule-of-thumb stand-in, NOT a real delta calc). Every record's `skew_method`
 * field says which method was actually used ('delta' or 'strike_approx') -- NEVER silently
 * substitute one for the other.
 *
 * Many small-caps have thin or absent options chains -- that is EXPECTED, not a failure.
 * Every ticker record carries an explicit `error` field (null on success) rather than being
 * dropped, so the orchestrator can see who was skipped and why.
 *
 * Output: JSON array to stdout (one record per input ticker, in input order). Cached (wrapped
 * with fetched_at + a repeat of the conviction-confirmer/15min-delay warning) to
 * ~/.cache/alpha-hunt/options-signals.json. Progress/warnings to stderr.
 *
 * Usage: node compute-options-signals.js TICKER1 TICKER2 ...
 *   Pass a SHORTLIST (~15-25 names), never the full universe -- space requests politely.
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');

const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const CACHE_FILE = path.join(CACHE_DIR, 'options-signals.json');
const USER_AGENT = 'alpha-hunt tomas@p5.is (research)';
const USER_AGENT_YAHOO = 'Mozilla/5.0';
const CBOE_BASE = 'https://cdn.cboe.com/api/global/delayed_quotes/options';
const TIMEOUT_MS = 15000;
const REQUEST_SPACING_MS = 150; // polite spacing across the shortlist batch (CBOE + Yahoo per ticker)
const MIN_DAYS_TO_EXPIRY = 7;
const SUGGESTED_MAX_SHORTLIST = 25;

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

// Parse a CBOE/OCC option symbol into {expiry, type, strike}. The suffix is a
// FIXED 15 chars (YYMMDD + C/P + 8-digit strike*1000) regardless of root
// length, so parse from the END of the string -- this is what makes it work
// for both short and long ticker roots without a lookup table.
function parseOccSymbol(symbol) {
  if (typeof symbol !== 'string' || symbol.length < 16) return null;
  const suffix = symbol.slice(-15);
  const m = suffix.match(/^(\d{2})(\d{2})(\d{2})([CP])(\d{8})$/);
  if (!m) return null;
  const [, yy, mm, dd, type, strikeStr] = m;
  return { expiry: `20${yy}-${mm}-${dd}`, type, strike: parseInt(strikeStr, 10) / 1000 };
}

function daysFromToday(expiryISO) {
  const now = new Date();
  const todayUTC = Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate());
  const [y, mo, d] = expiryISO.split('-').map(Number);
  const expiryUTC = Date.UTC(y, mo - 1, d);
  return Math.round((expiryUTC - todayUTC) / 86400000);
}

async function fetchCboeChain(ticker) {
  const url = `${CBOE_BASE}/${encodeURIComponent(ticker)}.json`;
  const res = await httpGet(url, { 'User-Agent': USER_AGENT, Accept: 'application/json' });
  if (res.error) throw new Error(`CBOE network error: ${res.error}`);
  if (res.status === 404) throw new Error('CBOE HTTP 404 -- no listed options chain for this ticker');
  if (res.status !== 200) throw new Error(`CBOE HTTP ${res.status}`);
  let json;
  try { json = JSON.parse(res.body); } catch (e) { throw new Error(`CBOE bad JSON: ${e.message}`); }
  const data = json && json.data;
  if (!data || !Array.isArray(data.options)) throw new Error('CBOE response missing data.options[]');
  if (typeof data.current_price !== 'number') throw new Error('CBOE response missing data.current_price');
  return data;
}

// Most recent session's stock volume (Yahoo v8 chart, range=1mo&interval=1d
// per spec). Walks backward past any trailing null (in-progress/holiday) bar
// rather than assuming the very last array element is populated.
async function fetchStockVolume(ticker) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?range=1mo&interval=1d`;
  const res = await httpGet(url, { 'User-Agent': USER_AGENT_YAHOO });
  if (res.error) throw new Error(`Yahoo network error: ${res.error}`);
  if (res.status !== 200) throw new Error(`Yahoo HTTP ${res.status}`);
  let json;
  try { json = JSON.parse(res.body); } catch (e) { throw new Error(`Yahoo bad JSON: ${e.message}`); }
  const result = json && json.chart && json.chart.result && json.chart.result[0];
  if (!result) throw new Error('Yahoo response missing chart.result[0]');
  const volumes = (result.indicators && result.indicators.quote && result.indicators.quote[0] && result.indicators.quote[0].volume) || [];
  for (let i = volumes.length - 1; i >= 0; i--) {
    if (typeof volumes[i] === 'number' && Number.isFinite(volumes[i])) return volumes[i];
  }
  throw new Error('Yahoo response has no populated volume bar');
}

function usableIv(o) { return o && Number.isFinite(o.iv) && o.iv > 0; }

// Preferred selection: by delta. Returns null if there isn't enough usable
// (iv>0, correctly-signed nonzero delta) data to do this -- caller falls
// back to pickByStrike and MUST record which method actually ran.
function pickByDelta(calls, puts) {
  const c = calls.filter((o) => usableIv(o) && Number.isFinite(o.delta) && o.delta > 0);
  const p = puts.filter((o) => usableIv(o) && Number.isFinite(o.delta) && o.delta < 0);
  if (c.length === 0 || p.length === 0) return null;
  const atmCall = c.reduce((best, o) => (Math.abs(o.delta - 0.5) < Math.abs(best.delta - 0.5) ? o : best));
  const atmPut = p.reduce((best, o) => (Math.abs(Math.abs(o.delta) - 0.5) < Math.abs(Math.abs(best.delta) - 0.5) ? o : best));
  const put25 = p.reduce((best, o) => (Math.abs(Math.abs(o.delta) - 0.25) < Math.abs(Math.abs(best.delta) - 0.25) ? o : best));
  return { atmCall, atmPut, put25 };
}

// Fallback when delta is missing/unusable: ATM = strike nearest current
// price; 25-delta put APPROXIMATED as the put ~10% out-of-the-money (a
// standard rule-of-thumb, NOT a real delta calc -- hence skew_method).
function pickByStrike(calls, puts, currentPrice) {
  const c = calls.filter(usableIv);
  const p = puts.filter(usableIv);
  if (c.length === 0 || p.length === 0) return null;
  const atmCall = c.reduce((best, o) => (Math.abs(o.strike - currentPrice) < Math.abs(best.strike - currentPrice) ? o : best));
  const atmPut = p.reduce((best, o) => (Math.abs(o.strike - currentPrice) < Math.abs(best.strike - currentPrice) ? o : best));
  const targetPutStrike = currentPrice * 0.90; // ~10% OTM approximates a 25-delta put
  const put25 = p.reduce((best, o) => (Math.abs(o.strike - targetPutStrike) < Math.abs(best.strike - targetPutStrike) ? o : best));
  return { atmCall, atmPut, put25 };
}

async function computeSignalsForTicker(ticker) {
  const data = await fetchCboeChain(ticker);
  const currentPrice = data.current_price;

  // Group by expiry (parsed from the OCC symbol) and accumulate TOTAL chain
  // volume across ALL expiries for os_ratio -- Pan & Poteshman's O/S ratio is
  // a whole-chain-vs-stock measure, not scoped to the single expiry used for
  // the skew legs below.
  const byExpiry = new Map();
  let optionVolumeTotal = 0;
  for (const o of data.options) {
    if (typeof o.volume === 'number' && Number.isFinite(o.volume)) optionVolumeTotal += o.volume;
    const parsed = parseOccSymbol(o.option);
    if (!parsed) continue;
    if (!byExpiry.has(parsed.expiry)) byExpiry.set(parsed.expiry, { calls: [], puts: [] });
    const bucket = byExpiry.get(parsed.expiry);
    const rec = { strike: parsed.strike, iv: o.iv, delta: o.delta };
    (parsed.type === 'C' ? bucket.calls : bucket.puts).push(rec);
  }
  if (byExpiry.size === 0) throw new Error('no parseable option contracts in CBOE response');

  // NEAREST expiry that is >= MIN_DAYS_TO_EXPIRY days out.
  const candidates = [...byExpiry.keys()]
    .map((expiry) => ({ expiry, daysOut: daysFromToday(expiry) }))
    .filter((e) => e.daysOut >= MIN_DAYS_TO_EXPIRY)
    .sort((a, b) => a.daysOut - b.daysOut);
  if (candidates.length === 0) throw new Error(`no expiry >=${MIN_DAYS_TO_EXPIRY}d out found in chain`);
  const { expiry: targetExpiry, daysOut } = candidates[0];
  const { calls, puts } = byExpiry.get(targetExpiry);

  let picks = pickByDelta(calls, puts);
  let skewMethod = 'delta';
  if (!picks) {
    picks = pickByStrike(calls, puts, currentPrice);
    skewMethod = 'strike_approx';
  }
  if (!picks) throw new Error(`no usable (iv>0) call+put contracts at expiry ${targetExpiry}`);

  const { atmCall, atmPut, put25 } = picks;
  // Blended ATM IV = average of the ATM call and ATM put IV. Kept distinct
  // from vol_spread's two legs (call-only, put-only) so iv_skew and
  // vol_spread measure different things instead of being algebraic
  // restatements of each other.
  const atmIv = (atmCall.iv + atmPut.iv) / 2;
  const ivSkew = put25.iv - atmIv;
  const volSpread = atmCall.iv - atmPut.iv;

  let stockVolume = null;
  let osRatio = null;
  let osRatioNote = null;
  try {
    stockVolume = await fetchStockVolume(ticker);
    osRatio = stockVolume > 0 ? optionVolumeTotal / stockVolume : null;
    if (stockVolume <= 0) osRatioNote = 'Yahoo stock volume was 0 -- os_ratio emitted null, not divided by zero';
  } catch (e) {
    osRatioNote = `stock volume unavailable (${e.message}) -- os_ratio emitted null, not guessed`;
  }

  return {
    ticker,
    error: null,
    fetched_at: new Date().toISOString(),
    current_price: currentPrice,
    expiry_used: targetExpiry,
    days_to_expiry: daysOut,
    skew_method: skewMethod,
    atm_call_strike: round(atmCall.strike, 2),
    atm_call_iv: round(atmCall.iv, 4),
    atm_put_strike: round(atmPut.strike, 2),
    atm_put_iv: round(atmPut.iv, 4),
    atm_iv: round(atmIv, 4),
    put25_strike: round(put25.strike, 2),
    put25_delta: skewMethod === 'delta' ? round(put25.delta, 4) : null,
    put25_iv: round(put25.iv, 4),
    iv_skew: round(ivSkew, 4),
    vol_spread: round(volSpread, 4),
    option_volume_total: optionVolumeTotal,
    stock_volume: stockVolume,
    os_ratio: osRatio !== null ? round(osRatio, 6) : null,
    os_ratio_note: osRatioNote,
  };
}

async function main() {
  const tickers = [...new Set(process.argv.slice(2).map((t) => t.toUpperCase()).filter(Boolean))];
  if (tickers.length === 0) {
    console.error('Usage: node compute-options-signals.js TICKER1 [TICKER2 ...]');
    console.error('Pass a SHORTLIST (~15-25 names), never the full universe.');
    process.exit(1);
  }
  if (tickers.length > SUGGESTED_MAX_SHORTLIST) {
    console.error(`WARN: ${tickers.length} tickers requested -- this script is meant for a ~${SUGGESTED_MAX_SHORTLIST}-name shortlist, not the full universe. Proceeding, but please narrow next time.`);
  }

  ensureCacheDir();

  const results = [];
  let okCount = 0;
  for (let i = 0; i < tickers.length; i++) {
    const ticker = tickers[i];
    if (i > 0) await sleep(REQUEST_SPACING_MS);
    try {
      const record = await computeSignalsForTicker(ticker);
      results.push(record);
      okCount++;
    } catch (err) {
      console.error(`WARN: ${ticker}: ${err.message} -- skipping (thin/absent chain is expected for small-caps)`);
      results.push({ ticker, error: err.message });
    }
  }

  console.error(`Options signals: ${okCount}/${tickers.length} tickers produced a usable signal, ${tickers.length - okCount} failed/absent chain.`);

  const cachePayload = {
    fetched_at: new Date().toISOString(),
    note: 'CONVICTION CONFIRMER/DEMERIT on the catalyst sleeve only -- NEVER a standalone buy trigger. Data is 15-minute delayed (directional, not tradeable-precision).',
    results,
  };
  fs.writeFileSync(CACHE_FILE, JSON.stringify(cachePayload, null, 2));

  process.stdout.write(JSON.stringify(results, null, 2) + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
