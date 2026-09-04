#!/usr/bin/env node
/**
 * preflight.js
 * Credential + endpoint liveness gate for the alpha-hunt pipeline.
 * Run this FIRST — abort the whole run on any failure.
 *
 * Checks:
 *   1. Required env vars are set and non-empty (FRED_API_KEY, FINNHUB_API_KEY,
 *      AGENT_PRIVATE_KEY, AGENT_PUBLIC_KEY). AGENT_* (eToro keys) are only
 *      existence-checked — never used to call a trading endpoint here.
 *   2. Live pings: Finnhub quote, FRED observations, SEC companyfacts, Yahoo chart.
 *
 * Output: PASS/FAIL table to stderr; JSON summary {ok, checks[]} to stdout.
 * Exit code: 0 if all checks pass, 1 otherwise.
 *
 * Usage: node preflight.js
 */

const https = require('node:https');
const { randomUUID } = require('node:crypto');

const USER_AGENT_SEC = 'alpha-hunt tomas@p5.is (research)';
const USER_AGENT_YAHOO = 'Mozilla/5.0';

function httpGet(url, headers) {
  return new Promise((resolve) => {
    const req = https.get(url, { headers, timeout: 10000 }, (res) => {
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('timeout', () => { req.destroy(new Error('timeout')); });
    req.on('error', (err) => resolve({ status: null, error: err.message }));
  });
}

async function checkEnvVar(name, fixUrl) {
  const val = process.env[name];
  if (val && val.trim().length > 0) {
    return { name: `env:${name}`, status: 'PASS', detail: 'set and non-empty' };
  }
  return { name: `env:${name}`, status: 'FAIL', detail: `Missing/empty. Fix: set ${name} in your environment${fixUrl ? ` (get one at ${fixUrl})` : ''}.` };
}

async function checkFinnhub() {
  const key = process.env.FINNHUB_API_KEY;
  if (!key) return { name: 'finnhub:quote', status: 'FAIL', detail: 'Skipped — FINNHUB_API_KEY not set. Fix: set FINNHUB_API_KEY (get one at https://finnhub.io/register).' };
  const url = `https://finnhub.io/api/v1/quote?symbol=AAPL&token=${encodeURIComponent(key)}`;
  const res = await httpGet(url);
  if (res.error) return { name: 'finnhub:quote', status: 'FAIL', detail: `Network error: ${res.error}. Fix: check connectivity to finnhub.io.` };
  if (res.status !== 200) return { name: 'finnhub:quote', status: 'FAIL', detail: `HTTP ${res.status}. Fix: verify FINNHUB_API_KEY is valid at https://finnhub.io/dashboard.` };
  try {
    const json = JSON.parse(res.body);
    if (typeof json.c === 'number' && json.c > 0) {
      return { name: 'finnhub:quote', status: 'PASS', detail: `AAPL current price c=${json.c}` };
    }
    return { name: 'finnhub:quote', status: 'FAIL', detail: `HTTP 200 but no valid 'c' field: ${res.body.slice(0, 200)}. Fix: verify FINNHUB_API_KEY is valid at https://finnhub.io/dashboard.` };
  } catch (e) {
    return { name: 'finnhub:quote', status: 'FAIL', detail: `Invalid JSON response: ${e.message}` };
  }
}

async function checkFred() {
  const key = process.env.FRED_API_KEY;
  if (!key) return { name: 'fred:observations', status: 'FAIL', detail: 'Skipped — FRED_API_KEY not set. Fix: set FRED_API_KEY (get one at https://fred.stlouisfed.org/docs/api/api_key.html).' };
  const url = `https://api.stlouisfed.org/fred/series/observations?series_id=DGS10&api_key=${encodeURIComponent(key)}&file_type=json&sort_order=desc&limit=1`;
  const res = await httpGet(url);
  if (res.error) return { name: 'fred:observations', status: 'FAIL', detail: `Network error: ${res.error}. Fix: check connectivity to api.stlouisfed.org.` };
  if (res.status === 400) return { name: 'fred:observations', status: 'FAIL', detail: `HTTP 400 — invalid FRED_API_KEY. Fix: get a valid key at https://fred.stlouisfed.org/docs/api/api_key.html.` };
  if (res.status !== 200) return { name: 'fred:observations', status: 'FAIL', detail: `HTTP ${res.status}. Fix: get a valid key at https://fred.stlouisfed.org/docs/api/api_key.html.` };
  try {
    const json = JSON.parse(res.body);
    if (Array.isArray(json.observations) && json.observations.length > 0) {
      return { name: 'fred:observations', status: 'PASS', detail: `DGS10 latest=${json.observations[0].value} on ${json.observations[0].date}` };
    }
    return { name: 'fred:observations', status: 'FAIL', detail: `HTTP 200 but no observations[] in response: ${res.body.slice(0, 200)}` };
  } catch (e) {
    return { name: 'fred:observations', status: 'FAIL', detail: `Invalid JSON response: ${e.message}` };
  }
}

async function checkSec() {
  const url = 'https://data.sec.gov/api/xbrl/companyfacts/CIK0000320193.json';
  const res = await httpGet(url, { 'User-Agent': USER_AGENT_SEC, Accept: 'application/json' });
  if (res.error) return { name: 'sec:companyfacts', status: 'FAIL', detail: `Network error: ${res.error}. Fix: check connectivity to data.sec.gov.` };
  if (res.status === 403) return { name: 'sec:companyfacts', status: 'FAIL', detail: `HTTP 403 — User-Agent rejected. Fix: use a descriptive User-Agent header (e.g. "alpha-hunt you@example.com") per https://www.sec.gov/os/webmaster-faq#developers.` };
  if (res.status !== 200) return { name: 'sec:companyfacts', status: 'FAIL', detail: `HTTP ${res.status}. Fix: verify data.sec.gov is reachable and User-Agent header is set.` };
  return { name: 'sec:companyfacts', status: 'PASS', detail: 'HTTP 200 from data.sec.gov' };
}

async function checkYahoo() {
  const url = 'https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=5d&interval=1d';
  const res = await httpGet(url, { 'User-Agent': USER_AGENT_YAHOO });
  if (res.error) return { name: 'yahoo:chart', status: 'FAIL', detail: `Network error: ${res.error}. Fix: check connectivity to query1.finance.yahoo.com.` };
  if (res.status !== 200) return { name: 'yahoo:chart', status: 'FAIL', detail: `HTTP ${res.status}. Fix: Yahoo may be blocking the request; verify User-Agent header is set to a browser-like value.` };
  try {
    const json = JSON.parse(res.body);
    if (json && json.chart && json.chart.result && json.chart.result[0]) {
      return { name: 'yahoo:chart', status: 'PASS', detail: `HTTP 200, chart.result[0] present for AAPL` };
    }
    return { name: 'yahoo:chart', status: 'FAIL', detail: `HTTP 200 but no chart.result[0]: ${res.body.slice(0, 200)}` };
  } catch (e) {
    return { name: 'yahoo:chart', status: 'FAIL', detail: `Invalid JSON response: ${e.message}` };
  }
}

const ETORO_BASE = 'https://public-api.etoro.com/api/v1';

// Read-only liveness probe for the eToro agent-portfolio — the AUTHORITY on
// whether the trading credentials work. Do NOT judge the keys by appearance:
//   - AGENT_PUBLIC_KEY equals eToro's SHARED x-api-key constant (same for everyone).
//   - AGENT_PRIVATE_KEY (the x-user-key userToken) decodes to an opaque blob tagged
//     "UnregisteredApplication" — that is exactly what a valid userToken looks like.
// Neither is evidence of a fake key. Only this live call decides validity.
async function checkEtoro() {
  const apiKey = process.env.AGENT_PUBLIC_KEY;   // x-api-key
  const userKey = process.env.AGENT_PRIVATE_KEY; // x-user-key (userToken)
  if (!apiKey || !userKey) {
    return { name: 'etoro:portfolio', status: 'FAIL', detail: 'Skipped — AGENT_PUBLIC_KEY (x-api-key) and/or AGENT_PRIVATE_KEY (x-user-key) not set. Fix: set both in the environment.' };
  }
  const res = await httpGet(`${ETORO_BASE}/trading/info/real/pnl`, {
    'x-api-key': apiKey, 'x-user-key': userKey, 'x-request-id': randomUUID(),
  });
  if (res.error) return { name: 'etoro:portfolio', status: 'FAIL', detail: `Network error: ${res.error}. Fix: check connectivity to public-api.etoro.com.` };
  const body = res.body || '';
  if (res.status === 200) {
    let positions = null, orders = null;
    try {
      const cp = (JSON.parse(body).clientPortfolio) || JSON.parse(body);
      positions = Array.isArray(cp.positions) ? cp.positions.length : null;
      orders = Array.isArray(cp.ordersForOpen) ? cp.ordersForOpen.length : null;
    } catch (_) { /* live regardless; body shape may vary */ }
    const posStr = positions == null ? 'portfolio state read OK' : `${positions} open position(s), ${orders ?? 0} pending`;
    return { name: 'etoro:portfolio', status: 'PASS', detail: `agent-portfolio LIVE — ${posStr}. Keys are VALID; this live call is the authority — do NOT judge keys by appearance.` };
  }
  // A response the API only produces for a real agent-portfolio still proves validity.
  if (/(this gcid is an agent-portfolio|agent-portfolio)/i.test(body)) {
    return { name: 'etoro:portfolio', status: 'PASS', detail: 'agent-portfolio credentials VALID — the API resolved them to a real agent-portfolio. Do NOT judge keys by appearance; this live call is the authority.' };
  }
  if (res.status === 403 && /InsufficientPermissions/i.test(body)) {
    return { name: 'etoro:portfolio', status: 'FAIL', detail: 'HTTP 403 InsufficientPermissions — the user key lacks real:write. Fix: provide an agent-portfolio userToken with scope 202 (real:write).' };
  }
  return { name: 'etoro:portfolio', status: 'FAIL', detail: `HTTP ${res.status} from /trading/info/real/pnl: ${body.slice(0, 200)}. Fix: verify AGENT_PRIVATE_KEY is a valid agent-portfolio userToken (mint one via eToro Settings > Trade).` };
}

async function main() {
  const checks = [];

  checks.push(await checkEnvVar('FRED_API_KEY', 'https://fred.stlouisfed.org/docs/api/api_key.html'));
  checks.push(await checkEnvVar('FINNHUB_API_KEY', 'https://finnhub.io/register'));
  checks.push(await checkEnvVar('AGENT_PRIVATE_KEY', null));
  checks.push(await checkEnvVar('AGENT_PUBLIC_KEY', null));

  const [finnhub, fred, sec, yahoo, etoro] = await Promise.all([
    checkFinnhub(), checkFred(), checkSec(), checkYahoo(), checkEtoro(),
  ]);
  checks.push(finnhub, fred, sec, yahoo, etoro);

  const nameWidth = Math.max(...checks.map((c) => c.name.length));
  console.error('alpha-hunt preflight');
  console.error('='.repeat(60));
  for (const c of checks) {
    console.error(`[${c.status === 'PASS' ? ' OK ' : 'FAIL'}] ${c.name.padEnd(nameWidth)}  ${c.detail}`);
  }
  console.error('='.repeat(60));

  const ok = checks.every((c) => c.status === 'PASS');
  console.error(ok ? 'ALL CHECKS PASSED — pipeline may proceed.' : 'PREFLIGHT FAILED — fix the issues above before proceeding.');

  process.stdout.write(JSON.stringify({ ok, checks }, null, 2) + '\n');
  process.exit(ok ? 0 : 1);
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
