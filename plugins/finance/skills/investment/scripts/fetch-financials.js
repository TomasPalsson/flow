#!/usr/bin/env node
/**
 * fetch-financials.js
 * Fetch annual + quarterly income statement, balance sheet, cash flow.
 * Uses yahoo-finance2 fundamentalsTimeSeries (NOT broken quoteSummary financials).
 * Cross-validates revenue with SEC EDGAR to detect data-shift bug #2584.
 *
 * Output JSON: { ticker, income[], balance[], cashflow[], shift_warning }
 *
 * Caching: 7-day TTL.
 *
 * Usage: node fetch-financials.js TICKER
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { spawnSync } from 'node:child_process';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill', 'financials');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

async function loadYf() {
  const mod = await import('yahoo-finance2');
  const YahooFinance = mod.default;
  const yf = (typeof YahooFinance === 'function') ? new YahooFinance() : YahooFinance;
  if (yf.suppressNotices) yf.suppressNotices(['yahooSurvey', 'ripHistorical']);
  return yf;
}

async function getYfFundamentals(yf, ticker) {
  // fundamentalsTimeSeries replaces the broken quoteSummary financial modules
  const fields = [
    'annualTotalRevenue', 'annualNetIncome', 'annualOperatingIncome',
    'annualGrossProfit', 'annualCostOfRevenue',
    'annualTotalAssets', 'annualTotalLiabilitiesNetMinorityInterest',
    'annualStockholdersEquity', 'annualCashAndCashEquivalents',
    'annualLongTermDebt', 'annualCurrentLiabilities', 'annualCurrentAssets',
    'annualCapitalExpenditure', 'annualOperatingCashFlow',
    'annualResearchAndDevelopment', 'annualSellingGeneralAndAdministration',
    'annualDilutedAverageShares', 'annualBasicAverageShares',
    'annualEbitda', 'annualEbit',
    'annualNetPPE', 'annualGrossPPE',
    'annualDepreciationAndAmortization',
    'annualStockBasedCompensation',
    'annualFreeCashFlow',
  ];

  const period1 = Math.floor((Date.now() - 7 * 365 * 24 * 3600 * 1000) / 1000);
  const period2 = Math.floor(Date.now() / 1000);

  try {
    const data = await yf.fundamentalsTimeSeries(ticker, {
      period1: new Date(period1 * 1000),
      period2: new Date(period2 * 1000),
      type: fields.join(','),
      module: 'financials',
    });
    return data;
  } catch (err) {
    throw new Error(`fundamentalsTimeSeries failed for ${ticker}: ${err.message}`);
  }
}

function detectShiftBug(yfData, secRevenueSeries) {
  // Bug #2584: yfinance income statement values may be shifted by 1 year.
  // Detection: compare yfinance latest revenue to SEC EDGAR latest revenue.
  // If off by more than 5% but matches PRIOR year EDGAR revenue, shift bug is present.
  if (!yfData || !secRevenueSeries || secRevenueSeries.length < 2) return null;

  const yfLatestRev = yfData.find((row) => row.annualTotalRevenue)?.annualTotalRevenue?.raw;
  if (!yfLatestRev) return null;

  const secLatest = secRevenueSeries[0]?.val;
  const secPrior = secRevenueSeries[1]?.val;

  if (!secLatest || !secPrior) return null;

  const matchLatest = Math.abs(yfLatestRev - secLatest) / secLatest < 0.05;
  const matchPrior = Math.abs(yfLatestRev - secPrior) / secPrior < 0.05;

  if (!matchLatest && matchPrior) {
    return { shift_detected: true, yf_value: yfLatestRev, sec_latest: secLatest, sec_prior: secPrior };
  }
  return { shift_detected: false };
}

async function main() {
  const ticker = process.argv[2];
  if (!ticker) {
    console.error('Usage: fetch-financials.js TICKER');
    process.exit(1);
  }

  ensureCacheDir();
  const cacheFile = path.join(CACHE_DIR, `${ticker}.json`);
  if (fs.existsSync(cacheFile)) {
    const stat = fs.statSync(cacheFile);
    if (Date.now() - stat.mtimeMs < CACHE_TTL_MS) {
      process.stdout.write(fs.readFileSync(cacheFile, 'utf8'));
      return;
    }
  }

  const yf = await loadYf();
  let yfData;
  try {
    yfData = await getYfFundamentals(yf, ticker);
  } catch (err) {
    console.error(`yfinance failed: ${err.message}. Falling back to SEC-only data.`);
    yfData = null;
  }

  // Cross-check with SEC EDGAR
  const secScript = path.join(import.meta.dirname || path.dirname(process.argv[1]), 'fetch-sec-facts.js');
  let secData = null;
  try {
    const result = spawnSync('node', [secScript, ticker], { encoding: 'utf8' });
    if (result.status === 0) {
      secData = JSON.parse(result.stdout);
    }
  } catch (err) {
    console.error(`SEC cross-check failed: ${err.message}`);
  }

  const revenueKey = secData?.series?.Revenues ? 'Revenues' :
                     secData?.series?.RevenueFromContractWithCustomerExcludingAssessedTax ? 'RevenueFromContractWithCustomerExcludingAssessedTax' :
                     'SalesRevenueNet';
  const secRevenueSeries = secData?.series?.[revenueKey] || [];

  const shiftCheck = detectShiftBug(yfData, secRevenueSeries);

  const out = {
    ticker,
    fetched_at: new Date().toISOString(),
    yf_financials: yfData,
    sec_facts: secData,
    shift_check: shiftCheck,
    primary_source_recommendation: shiftCheck?.shift_detected ? 'SEC' : 'YF_with_SEC_cross_check',
  };

  fs.writeFileSync(cacheFile, JSON.stringify(out, null, 2));
  process.stdout.write(JSON.stringify(out, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
