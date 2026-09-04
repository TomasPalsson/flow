#!/usr/bin/env node
/**
 * fetch-regime.js
 * Timeout-guarded fetcher for the alpha-hunt regime gross-exposure dial.
 *
 * WHY THIS EXISTS: the reused investment/fetch-macro.js issued https.get calls
 * with NO timeout, and a proxied connection that completes the TLS handshake but
 * returns zero bytes stalls the whole weekly run forever. Every request here is
 * wrapped in the same 10s timeout guard preflight.js uses, so the regime dial —
 * alpha-hunt's headline risk control — can never hang the pipeline.
 *
 * Pulls the three directly-fetchable dial inputs (see references/regime-throttle.md):
 *   - Distribution days: Yahoo v8 chart on SPY (down >=0.2% on volume > prior day,
 *     trailing 25 sessions) + Follow-Through Day detection.
 *   - VIX term structure: ^VIX / ^VIX3M ratio (>1 = backwardation = stress).
 *   - Credit spread: FRED BAMLH0A0HYM2 via the keyless fredgraph.csv backend
 *     (no FRED_API_KEY dependency), latest level + ~4-week change.
 * Breadth (% of universe above 200DMA) is aggregated by the orchestrator from the
 * compute-momentum.js universe pull — not fetched here.
 *
 * Output: JSON {fetched_at, inputs:{...}, partial_regime_score, notes} to stdout;
 * warnings to stderr. A source that fails/times out is scored 0 (neutral) with a
 * note, never a hang. Also caches to ~/.cache/alpha-hunt/regime.json.
 *
 * Usage: node fetch-regime.js
 */

const https = require('node:https');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const TIMEOUT_MS = 10000;
const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const UA_YAHOO = 'Mozilla/5.0';

// Timeout-guarded GET — mirrors preflight.js::httpGet. Never rejects; resolves
// {status, body} on success or {status:null, error} on network/timeout failure.
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

async function fetchYahooDaily(symbol, range) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(symbol)}?range=${range}&interval=1d`;
  const res = await httpGet(url, { 'User-Agent': UA_YAHOO });
  if (res.error) throw new Error(`${symbol}: ${res.error}`);
  if (res.status !== 200) throw new Error(`${symbol}: HTTP ${res.status}`);
  const json = JSON.parse(res.body);
  const r = json.chart && json.chart.result && json.chart.result[0];
  if (!r) throw new Error(`${symbol}: no chart.result`);
  const ts = r.timestamp || [];
  const q = (r.indicators && r.indicators.quote && r.indicators.quote[0]) || {};
  const closes = q.close || [];
  const volumes = q.volume || [];
  // Keep only bars where close is present (drop holiday/null rows), aligned.
  const bars = [];
  for (let i = 0; i < ts.length; i++) {
    if (typeof closes[i] === 'number') {
      bars.push({ t: ts[i], close: closes[i], volume: typeof volumes[i] === 'number' ? volumes[i] : null });
    }
  }
  return bars;
}

// Distribution-day count over the trailing `window` sessions.
function computeDistributionDays(bars, window = 25) {
  const start = Math.max(1, bars.length - window);
  let distDays = 0;
  let followThrough = null;
  for (let i = start; i < bars.length; i++) {
    const prev = bars[i - 1];
    const cur = bars[i];
    if (!prev || cur.volume == null || prev.volume == null) continue;
    const pct = (cur.close - prev.close) / prev.close;
    if (pct <= -0.002 && cur.volume > prev.volume) distDays++;
    // Follow-Through Day: index up >=1.25% on higher volume (keep the most recent)
    if (pct >= 0.0125 && cur.volume > prev.volume) {
      followThrough = new Date(cur.t * 1000).toISOString().slice(0, 10);
    }
  }
  return { count: distDays, follow_through_day: followThrough };
}

function csvLatestAndChange(csvText, lookbackRows = 20) {
  const lines = csvText.trim().split('\n');
  // Drop header; rows are "date,value"; skip missing "." values.
  const rows = [];
  for (let i = 1; i < lines.length; i++) {
    const parts = lines[i].split(',');
    if (parts.length < 2) continue;
    const v = parseFloat(parts[1]);
    if (Number.isFinite(v)) rows.push({ date: parts[0], value: v });
  }
  if (rows.length === 0) return null;
  const latest = rows[rows.length - 1];
  const priorIdx = Math.max(0, rows.length - 1 - lookbackRows);
  const prior = rows[priorIdx];
  return { value: latest.value, date: latest.date, change_4w: +(latest.value - prior.value).toFixed(2) };
}

async function fetchCreditSpread() {
  // Keyless "Download Data" backend — no FRED_API_KEY dependency.
  const url = 'https://fred.stlouisfed.org/graph/fredgraph.csv?id=BAMLH0A0HYM2';
  const res = await httpGet(url, {});
  if (res.error) throw new Error(`credit: ${res.error}`);
  if (res.status !== 200) throw new Error(`credit: HTTP ${res.status}`);
  const parsed = csvLatestAndChange(res.body);
  if (!parsed) throw new Error('credit: no parseable observations');
  return parsed;
}

async function main() {
  const inputs = {};
  const notes = [];

  // --- Distribution days (SPY) ---
  let distScore = 0;
  try {
    const spy = await fetchYahooDaily('SPY', '3mo');
    const dd = computeDistributionDays(spy);
    if (dd.count <= 3) distScore = 1;
    else if (dd.count <= 5) distScore = 0;
    else distScore = -1;
    inputs.distribution_days = { ...dd, score: distScore };
  } catch (e) {
    console.error(`WARN: distribution days unavailable (${e.message}) — scored 0`);
    inputs.distribution_days = { count: null, follow_through_day: null, score: 0, error: e.message };
    notes.push('distribution_days unavailable — scored neutral');
  }

  // --- VIX term structure (^VIX / ^VIX3M) ---
  let vixScore = 0;
  try {
    const [vix, vix3m] = await Promise.all([
      fetchYahooDaily('^VIX', '5d'),
      fetchYahooDaily('^VIX3M', '5d'),
    ]);
    const v = vix[vix.length - 1].close;
    const v3 = vix3m[vix3m.length - 1].close;
    const ratio = +(v / v3).toFixed(4);
    let shape;
    if (ratio > 1.05) { shape = 'backwardation'; vixScore = -1; }
    else if (ratio < 0.95) { shape = 'contango'; vixScore = 1; }
    else { shape = 'flat'; vixScore = 0; }
    inputs.vix_term_structure = { vix: v, vix3m: v3, ratio, shape, score: vixScore };
  } catch (e) {
    console.error(`WARN: VIX term structure unavailable (${e.message}) — scored 0`);
    inputs.vix_term_structure = { ratio: null, shape: null, score: 0, error: e.message };
    notes.push('vix_term_structure unavailable — scored neutral');
  }

  // --- Credit spread (FRED BAMLH0A0HYM2, keyless) ---
  let creditScore = 0;
  try {
    const c = await fetchCreditSpread();
    if (c.change_4w < -0.1) creditScore = 1;        // tightening
    else if (c.change_4w > 0.3) creditScore = -1;   // sharp widening
    else creditScore = 0;
    inputs.credit_spread = { hy_oas: c.value, as_of: c.date, change_4w: c.change_4w, score: creditScore };
  } catch (e) {
    console.error(`WARN: credit spread unavailable (${e.message}) — scored 0`);
    inputs.credit_spread = { hy_oas: null, change_4w: null, score: 0, error: e.message };
    notes.push('credit_spread unavailable — scored neutral');
  }

  const partial = distScore + vixScore + creditScore;
  notes.push('Breadth (% above 200DMA) is orchestrator-aggregated from the compute-momentum universe pull — add its -1/0/+1 to partial_regime_score for the full -3..+3 dial. VIX>1.05 ratio = backwardation = stress.');

  const out = {
    fetched_at: new Date().toISOString(),
    inputs,
    partial_regime_score: partial,
    partial_range: '-3..+3 (this covers 3 of 4 inputs; breadth added by orchestrator)',
    notes,
  };
  const outStr = JSON.stringify(out, null, 2);

  try {
    if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.writeFileSync(path.join(CACHE_DIR, 'regime.json'), outStr);
  } catch (e) { console.error(`WARN: could not write cache: ${e.message}`); }

  process.stdout.write(outStr + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
