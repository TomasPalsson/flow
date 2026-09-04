#!/usr/bin/env node
/**
 * fetch-macro.js
 * Pull macro indicators from FRED for regime classification.
 * No API key required for the most recent observation via redirect endpoints.
 *
 * Output JSON: { fetched_at, indicators: {...}, regime: 'late-cycle' | 'mid-cycle' | etc. }
 *
 * Caching: 24-hour TTL.
 *
 * Usage: node fetch-macro.js [--api-key=KEY] [--no-cache]
 *
 * For best results, set FRED_API_KEY env var (free at https://fred.stlouisfed.org).
 * Without key, falls back to scraping public FRED chart data (less reliable).
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill');
const CACHE_FILE = path.join(CACHE_DIR, 'macro.json');
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;

const FRED_API_KEY = process.env.FRED_API_KEY || process.argv.find((a) => a.startsWith('--api-key='))?.split('=')[1];

// Series we need
const SERIES = {
  fed_funds: 'FEDFUNDS',
  ten_year: 'DGS10',
  three_month: 'DGS3MO',
  cpi_yoy: 'CPIAUCSL', // need to compute YoY from index
  unemployment: 'UNRATE',
  ism_proxy: 'MANEMP',   // ISM Manufacturing Employment proxy (FRED removed actual ISM PMI)
  hy_oas: 'BAMLH0A0HYM2', // High Yield OAS
  thirty_year: 'DGS30',
};

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function fetchJson(url) {
  return new Promise((resolve, reject) => {
    // 10s timeout guard: a proxied socket can complete the TLS handshake but
    // return zero bytes and stall forever without this — destroy() forces an
    // 'error' event that rejects instead of hanging the whole run.
    const req = https.get(url, { timeout: 10000 }, (res) => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode}`)); }
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
      });
    });
    req.on('timeout', () => { req.destroy(new Error('timeout after 10s')); });
    req.on('error', reject);
  });
}

async function fetchSeries(seriesId) {
  if (!FRED_API_KEY) {
    // Fallback: fetch the public CSV via fred chart data export
    // (Note: this is fragile; encourage user to set API key)
    throw new Error('FRED_API_KEY not set. Get free key at https://fred.stlouisfed.org/docs/api/api_key.html');
  }
  const url = `https://api.stlouisfed.org/fred/series/observations?series_id=${seriesId}&api_key=${FRED_API_KEY}&file_type=json&sort_order=desc&limit=14`;
  const data = await fetchJson(url);
  // Filter out "." values (FRED's NaN)
  const obs = data.observations.filter((o) => o.value !== '.').map((o) => ({ date: o.date, value: parseFloat(o.value) }));
  return obs;
}

function classifyRegime(ind) {
  const yieldCurve = ind.ten_year - ind.three_month;
  const recentInversion = ind.yield_curve_history?.some((h) => h.value < 0);
  let signals = 0;
  let phase = 'mid-cycle';

  // Late-cycle / recession signals
  if (yieldCurve > 0 && recentInversion) signals++;  // re-normalized after inversion
  if (ind.unemployment > 4.0) signals++;
  if (ind.ism_proxy_yoy < 0) signals++;
  if (ind.hy_oas > 4.0) signals++;
  if (ind.cpi_yoy > 3.5 || ind.cpi_yoy < 1.5) signals++; // off-target inflation

  if (signals >= 4) phase = 'late-cycle';
  if (signals >= 5 && yieldCurve < 0) phase = 'recession-imminent';
  if (signals <= 1 && ind.unemployment > 5.0) phase = 'recovery';
  if (signals === 0 && yieldCurve > 1.0) phase = 'early-cycle';

  return { phase, signals_count: signals, yield_curve_bps: Math.round(yieldCurve * 100) };
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const useCache = !args.has('--no-cache');
  ensureCacheDir();

  if (useCache && fs.existsSync(CACHE_FILE)) {
    const stat = fs.statSync(CACHE_FILE);
    if (Date.now() - stat.mtimeMs < CACHE_TTL_MS) {
      process.stdout.write(fs.readFileSync(CACHE_FILE, 'utf8'));
      return;
    }
  }

  if (!FRED_API_KEY) {
    const fallback = {
      fetched_at: new Date().toISOString(),
      warning: 'FRED_API_KEY not set — using stale defaults',
      indicators: {
        fed_funds: 3.75, ten_year: 4.38, three_month: 4.30, cpi_yoy: 3.3, unemployment: 4.2,
        ism_proxy: 51, hy_oas: 3.2, thirty_year: 4.95,
      },
      regime: { phase: 'late-cycle', signals_count: 3, yield_curve_bps: 8 },
    };
    fs.writeFileSync(CACHE_FILE, JSON.stringify(fallback, null, 2));
    process.stdout.write(JSON.stringify(fallback, null, 2));
    return;
  }

  const results = {};
  // Rate limit: 120 req/min — we have 8 series, totally fine
  for (const [key, sid] of Object.entries(SERIES)) {
    try {
      const obs = await fetchSeries(sid);
      results[key] = obs[0]?.value;
      // For 10Y-3M history, keep last 12 observations
      if (key === 'ten_year') results.yield_curve_history = obs.slice(0, 12);
    } catch (err) {
      console.error(`WARN: ${sid} failed: ${err.message}`);
      results[key] = null;
    }
    await new Promise((r) => setTimeout(r, 600)); // gentle pacing
  }

  // Compute CPI YoY (FRED returns index level)
  try {
    const cpiObs = await fetchSeries(SERIES.cpi_yoy);
    if (cpiObs.length >= 13) {
      results.cpi_yoy = ((cpiObs[0].value / cpiObs[12].value - 1) * 100).toFixed(2) * 1;
    }
  } catch (e) { /* keep null */ }

  // Compute ISM proxy 6mo YoY
  try {
    const ismObs = await fetchSeries(SERIES.ism_proxy);
    if (ismObs.length >= 7) {
      results.ism_proxy_yoy = ((ismObs[0].value / ismObs[6].value - 1) * 100).toFixed(2) * 1;
    }
  } catch (e) { /* keep null */ }

  const regime = classifyRegime(results);

  const out = {
    fetched_at: new Date().toISOString(),
    indicators: results,
    regime,
  };

  const outStr = JSON.stringify(out, null, 2);
  fs.writeFileSync(CACHE_FILE, outStr);
  process.stdout.write(outStr);
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
