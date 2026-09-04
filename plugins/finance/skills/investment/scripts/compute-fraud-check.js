#!/usr/bin/env node
/**
 * compute-fraud-check.js
 * Compute Beneish M-Score + Sloan Accruals + going-concern check for a ticker.
 *
 * This is the HARD VETO gate (Stage 3 of the investment pipeline). If a candidate
 * triggers any veto, drop it from consideration regardless of other scores.
 *
 * Reads cached financials from fetch-sec-facts.js + fetch-financials.js output.
 * If cache misses, instructs caller to fetch first.
 *
 * Output JSON:
 * {
 *   ticker, beneish_m_score, sloan_accruals_pct, going_concern_flag,
 *   verdict: "PASS" | "VETO",
 *   reason: "..." (only when VETO),
 *   diagnostics: {...}
 * }
 *
 * Reference: references/06-red-flags-fraud.md
 *
 * Usage: node compute-fraud-check.js TICKER
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';
import { spawnSync } from 'node:child_process';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill');

function loadJsonCache(subdir, file) {
  const p = path.join(CACHE_DIR, subdir, `${file}.json`);
  if (!fs.existsSync(p)) return null;
  try { return JSON.parse(fs.readFileSync(p, 'utf8')); } catch { return null; }
}

function ensureFinancials(ticker) {
  const scriptDir = path.dirname(new URL(import.meta.url).pathname);

  // fetch-sec-facts.js caches RAW companyfacts by CIK but only emits the processed
  // { facts, series } shape (which pickFromSeries needs) on STDOUT — so capture that,
  // never a ticker-named cache file. The original code read sec-facts/<ticker>.json,
  // which was never written (the writer keys by CIK), so it silently fed null facts
  // to the Beneish/Sloan veto and it PASSed everything without vetting. The script's
  // own 30-day raw cache keeps this cheap on repeat runs.
  const rf = spawnSync('node', [path.join(scriptDir, 'fetch-sec-facts.js'), ticker], { encoding: 'utf8' });
  if (rf.status !== 0) throw new Error(`fetch-sec-facts failed: ${rf.stderr}`);
  let facts;
  try { facts = JSON.parse(rf.stdout); } catch (e) { throw new Error(`fetch-sec-facts returned unparseable output: ${e.message}`); }

  // fin is a secondary yf fallback; best-effort, never fatal to the veto.
  let fin = loadJsonCache('financials', ticker);
  if (!fin) {
    const r = spawnSync('node', [path.join(scriptDir, 'fetch-financials.js'), ticker], { encoding: 'utf8' });
    if (r.status === 0) fin = loadJsonCache('financials', ticker);
  }

  return { facts, fin };
}

function pickFromSeries(secFacts, key, yearOffset = 0) {
  // Returns the value from SEC facts series at the given year offset (0 = latest, 1 = prior, ...)
  const variants = [key];
  if (key === 'Revenues') variants.push('RevenueFromContractWithCustomerExcludingAssessedTax', 'SalesRevenueNet');
  for (const v of variants) {
    const series = secFacts?.series?.[v];
    if (series && series[yearOffset]) return series[yearOffset].val;
  }
  return null;
}

function pickFromYf(yfData, field, yearOffset = 0) {
  if (!yfData) return null;
  const items = yfData.filter((row) => row[field]?.raw !== undefined);
  return items[yearOffset]?.[field]?.raw || null;
}

function safeDivide(num, denom) {
  if (denom === null || denom === undefined || denom === 0) return null;
  if (num === null || num === undefined) return null;
  return num / denom;
}

function computeBeneishMScore(data) {
  const { facts, fin } = data;
  const sec = facts;
  const yf = fin?.yf_financials || [];

  // Pull both years (t and t-1) for each variable
  // Prefer SEC EDGAR (more reliable per Wave 1/3 research)
  const revenue_t = pickFromSeries(sec, 'Revenues', 0);
  const revenue_t1 = pickFromSeries(sec, 'Revenues', 1);
  const receivables_t = pickFromSeries(sec, 'AccountsReceivableNetCurrent', 0);
  const receivables_t1 = pickFromSeries(sec, 'AccountsReceivableNetCurrent', 1);
  const cogs_t = pickFromSeries(sec, 'CostOfRevenue', 0) || pickFromSeries(sec, 'CostOfGoodsAndServicesSold', 0);
  const cogs_t1 = pickFromSeries(sec, 'CostOfRevenue', 1) || pickFromSeries(sec, 'CostOfGoodsAndServicesSold', 1);
  const totAssets_t = pickFromSeries(sec, 'Assets', 0);
  const totAssets_t1 = pickFromSeries(sec, 'Assets', 1);
  const curAssets_t = pickFromSeries(sec, 'AssetsCurrent', 0);
  const curAssets_t1 = pickFromSeries(sec, 'AssetsCurrent', 1);
  const ppe_t = pickFromSeries(sec, 'PropertyPlantAndEquipmentNet', 0);
  const ppe_t1 = pickFromSeries(sec, 'PropertyPlantAndEquipmentNet', 1);
  const depr_t = pickFromSeries(sec, 'DepreciationAndAmortization', 0) || pickFromSeries(sec, 'DepreciationDepletionAndAmortization', 0);
  const depr_t1 = pickFromSeries(sec, 'DepreciationAndAmortization', 1) || pickFromSeries(sec, 'DepreciationDepletionAndAmortization', 1);
  const sga_t = pickFromSeries(sec, 'SellingGeneralAndAdministrativeExpense', 0);
  const sga_t1 = pickFromSeries(sec, 'SellingGeneralAndAdministrativeExpense', 1);
  const longTermDebt_t = pickFromSeries(sec, 'LongTermDebtNoncurrent', 0) || pickFromSeries(sec, 'LongTermDebt', 0);
  const longTermDebt_t1 = pickFromSeries(sec, 'LongTermDebtNoncurrent', 1) || pickFromSeries(sec, 'LongTermDebt', 1);
  const curLiab_t = pickFromSeries(sec, 'LiabilitiesCurrent', 0);
  const curLiab_t1 = pickFromSeries(sec, 'LiabilitiesCurrent', 1);
  const income_ops_t = pickFromSeries(sec, 'OperatingIncomeLoss', 0);
  const cfo_t = pickFromSeries(sec, 'NetCashProvidedByUsedInOperatingActivities', 0);

  const required = [revenue_t, revenue_t1, totAssets_t, totAssets_t1, cogs_t, cogs_t1];
  if (required.some((v) => v === null)) {
    return { computable: false, reason: 'Insufficient data — missing key fields' };
  }

  // DSRI = (Receivables_t / Sales_t) / (Receivables_t-1 / Sales_t-1)
  const dsri = safeDivide(safeDivide(receivables_t, revenue_t), safeDivide(receivables_t1, revenue_t1)) ?? 1.0;

  // GMI = (GM_t-1) / (GM_t) where GM = (Sales - COGS) / Sales
  const gm_t = (revenue_t - cogs_t) / revenue_t;
  const gm_t1 = (revenue_t1 - cogs_t1) / revenue_t1;
  const gmi = safeDivide(gm_t1, gm_t) ?? 1.0;

  // AQI = (1 - (CurAssets + Net PPE) / TotAssets)_t / same_t-1
  const aqi_num = 1 - safeDivide((curAssets_t || 0) + (ppe_t || 0), totAssets_t);
  const aqi_den = 1 - safeDivide((curAssets_t1 || 0) + (ppe_t1 || 0), totAssets_t1);
  const aqi = safeDivide(aqi_num, aqi_den) ?? 1.0;

  // SGI = Sales_t / Sales_t-1
  const sgi = safeDivide(revenue_t, revenue_t1) ?? 1.0;

  // DEPI = (Depr_t-1 / (Depr_t-1 + Net PPE_t-1)) / (Depr_t / (Depr_t + Net PPE_t))
  let depi = 1.0;
  if (depr_t && depr_t1 && ppe_t && ppe_t1) {
    const depi_t = depr_t / (depr_t + ppe_t);
    const depi_t1 = depr_t1 / (depr_t1 + ppe_t1);
    depi = depi_t1 / depi_t;
  }

  // SGAI = (SG&A/Sales)_t / (SG&A/Sales)_t-1
  let sgai = 1.0;
  if (sga_t && sga_t1) {
    sgai = (sga_t / revenue_t) / (sga_t1 / revenue_t1);
  }

  // Accruals = (Income from Ops - CFO) / Total Assets
  const avgAssets = (totAssets_t + totAssets_t1) / 2;
  const accruals = safeDivide((income_ops_t || 0) - (cfo_t || 0), avgAssets) ?? 0;

  // LVGI = ((LTD_t + CurLiab_t) / Assets_t) / ((LTD_t-1 + CurLiab_t-1) / Assets_t-1)
  let lvgi = 1.0;
  if (longTermDebt_t && longTermDebt_t1) {
    const lvgi_t = (longTermDebt_t + (curLiab_t || 0)) / totAssets_t;
    const lvgi_t1 = (longTermDebt_t1 + (curLiab_t1 || 0)) / totAssets_t1;
    lvgi = lvgi_t / lvgi_t1;
  }

  // M-Score = -4.84 + 0.92*DSRI + 0.528*GMI + 0.404*AQI + 0.892*SGI + 0.115*DEPI - 0.172*SGAI + 4.679*Accruals - 0.327*LVGI
  const mScore = -4.84 + 0.92 * dsri + 0.528 * gmi + 0.404 * aqi + 0.892 * sgi + 0.115 * depi - 0.172 * sgai + 4.679 * accruals - 0.327 * lvgi;

  return {
    computable: true,
    m_score: Number(mScore.toFixed(3)),
    variables: { dsri, gmi, aqi, sgi, depi, sgai, accruals, lvgi },
    verdict: mScore > -1.78 ? 'VETO' : (mScore > -2.22 ? 'YELLOW' : 'PASS'),
    threshold: { veto: -1.78, yellow: -2.22 },
  };
}

function computeSloanAccruals(data) {
  const { facts } = data;
  const totAssets_t = pickFromSeries(facts, 'Assets', 0);
  const totAssets_t1 = pickFromSeries(facts, 'Assets', 1);
  const netIncome_t = pickFromSeries(facts, 'NetIncomeLoss', 0);
  const cfo_t = pickFromSeries(facts, 'NetCashProvidedByUsedInOperatingActivities', 0);

  if (!totAssets_t || !totAssets_t1 || netIncome_t === null || cfo_t === null) {
    return { computable: false, reason: 'Missing fields' };
  }

  const avgAssets = (totAssets_t + totAssets_t1) / 2;
  const accrualsRatio = (netIncome_t - cfo_t) / avgAssets;

  return {
    computable: true,
    accruals_ratio: Number(accrualsRatio.toFixed(4)),
    accruals_pct_of_assets: Number((accrualsRatio * 100).toFixed(2)),
    verdict: accrualsRatio > 0.20 ? 'VETO' : (accrualsRatio > 0.10 ? 'YELLOW' : 'PASS'),
    threshold: { veto: 0.20, yellow: 0.10 },
  };
}

async function checkGoingConcern(ticker, cik) {
  // SEC EDGAR full-text search for the GAAP phrase that audit firms use
  // when raising substantial doubt about going concern.
  // EFTS API: https://efts.sec.gov/LATEST/search-index?q=...&forms=10-K&ciks=...
  if (!cik) return { computable: false, verdict: 'UNKNOWN', note: 'No CIK' };

  const cikNum = parseInt(cik, 10);
  // Search last 18 months of 10-K filings for the phrase
  const dateFrom = new Date(Date.now() - 18 * 30 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const url = `https://efts.sec.gov/LATEST/search-index?q=%22substantial+doubt+about+the+company%27s+ability+to+continue+as+a+going+concern%22&forms=10-K&ciks=${cikNum}&dateRange=custom&startdt=${dateFrom}`;

  try {
    const res = await new Promise((resolve, reject) => {
      https.get(url, { headers: { 'User-Agent': 'investment-skill tomas@p5.is', 'Accept': 'application/json' } }, (r) => {
        let body = '';
        r.on('data', (c) => { body += c; });
        r.on('end', () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
      }).on('error', reject);
    });

    const hits = res.hits?.hits || res.hits?.total?.value ? res.hits.hits : [];
    const hitCount = res.hits?.total?.value ?? hits.length;

    if (hitCount > 0) {
      return {
        computable: true,
        verdict: 'VETO',
        note: `Going-concern language found in ${hitCount} 10-K filing(s) in last 18 months`,
        hit_filings: hits.slice(0, 3).map((h) => h._source?.adsh || h._id),
      };
    }
    return { computable: true, verdict: 'PASS', note: 'No going-concern language detected in recent 10-K filings' };
  } catch (err) {
    return {
      computable: false,
      verdict: 'UNKNOWN',
      note: `Going-concern check failed (${err.message}). Manual review required if other signals are weak.`,
    };
  }
}

async function main() {
  const ticker = process.argv[2];
  if (!ticker) {
    console.error('Usage: compute-fraud-check.js TICKER');
    process.exit(1);
  }

  let data;
  try {
    data = ensureFinancials(ticker);
  } catch (err) {
    console.error(`FATAL: cannot load financials: ${err.message}`);
    process.exit(2);
  }

  const beneish = computeBeneishMScore(data);
  const sloan = computeSloanAccruals(data);
  // Resolve CIK for going-concern check
  const cik = data.facts?.cik;
  const goingConcern = await checkGoingConcern(ticker, cik);

  let overall = 'PASS';
  const reasons = [];
  if (goingConcern.verdict === 'VETO') { overall = 'VETO'; reasons.push(goingConcern.note); }
  if (beneish.verdict === 'VETO') { overall = 'VETO'; reasons.push(`Beneish M-Score = ${beneish.m_score} (> -1.78)`); }
  if (sloan.verdict === 'VETO') { overall = 'VETO'; reasons.push(`Sloan accruals = ${sloan.accruals_pct_of_assets}% (> 20% of assets)`); }
  if (beneish.verdict === 'YELLOW' || sloan.verdict === 'YELLOW') {
    if (overall === 'PASS') overall = 'YELLOW';
    if (beneish.verdict === 'YELLOW') reasons.push(`Beneish M-Score = ${beneish.m_score} (elevated, between -2.22 and -1.78) — apply -5 Quality bundle penalty AND require pre-mortem documenting why earnings-quality concerns are non-material`);
    if (sloan.verdict === 'YELLOW') reasons.push(`Sloan accruals = ${sloan.accruals_pct_of_assets}% (elevated, between 10% and 20%) — apply -5 Quality bundle penalty AND require pre-mortem`);
  }

  // Fail-safe: a fraud VETO that could not compute its core signals must NOT report a
  // clean PASS — escalate to UNKNOWN so the caller treats the name as un-vetted, not cleared.
  if (overall === 'PASS' && (beneish.computable === false || sloan.computable === false)) {
    overall = 'UNKNOWN';
    reasons.push('Fraud veto could not compute Beneish/Sloan from available SEC facts — treat as UN-VETTED (manual review), NOT fraud-cleared.');
  }

  const out = {
    ticker,
    fetched_at: new Date().toISOString(),
    beneish_m_score: beneish.m_score ?? null,
    beneish_diagnostics: beneish,
    sloan_accruals_pct: sloan.accruals_pct_of_assets ?? null,
    sloan_diagnostics: sloan,
    going_concern_flag: goingConcern.verdict,
    going_concern_diagnostics: goingConcern,
    overall_verdict: overall,
    veto_reasons: reasons,
    references: 'See references/06-red-flags-fraud.md',
  };

  process.stdout.write(JSON.stringify(out, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
