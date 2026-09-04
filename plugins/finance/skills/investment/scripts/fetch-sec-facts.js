#!/usr/bin/env node
/**
 * fetch-sec-facts.js
 * SEC EDGAR companyfacts API — standardized GAAP/XBRL facts for a ticker.
 * Primary source (more reliable than yfinance due to data shift bug).
 *
 * Rate limit: SEC requires User-Agent header AND ≤ 10 req/sec.
 *
 * Output: JSON with normalized fields (Revenues, NetIncomeLoss, Assets, etc.)
 *
 * Caching: 30-day TTL (financial facts only change quarterly).
 *
 * Usage: node fetch-sec-facts.js TICKER
 *        node fetch-sec-facts.js --cik=0000320193
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill', 'sec-facts');
const TICKER_MAP_FILE = path.join(os.homedir(), '.cache', 'investment-skill', 'sec-tickers.json');
const CACHE_TTL_MS = 30 * 24 * 60 * 60 * 1000;
const USER_AGENT = 'investment-skill tomas@p5.is (research/educational)';
const SEC_BASE = 'https://data.sec.gov';

const KEY_FACTS = [
  'Revenues', 'RevenueFromContractWithCustomerExcludingAssessedTax', 'SalesRevenueNet',
  'NetIncomeLoss', 'OperatingIncomeLoss',
  'Assets', 'AssetsCurrent', 'Liabilities', 'LiabilitiesCurrent', 'AccountsReceivableNetCurrent',
  'StockholdersEquity', 'CashAndCashEquivalentsAtCarryingValue',
  'LongTermDebt', 'LongTermDebtNoncurrent',
  'PropertyPlantAndEquipmentGross', 'PropertyPlantAndEquipmentNet',
  'CommonStockSharesOutstanding', 'WeightedAverageNumberOfDilutedSharesOutstanding',
  'EarningsPerShareDiluted',
  'CostOfRevenue', 'CostOfGoodsAndServicesSold', 'GrossProfit',
  'NetCashProvidedByUsedInOperatingActivities',
  'PaymentsToAcquirePropertyPlantAndEquipment',
  'ResearchAndDevelopmentExpense',
  'SellingGeneralAndAdministrativeExpense',
  'DepreciationAndAmortization', 'DepreciationDepletionAndAmortization',
];

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    const opts = {
      headers: { 'User-Agent': USER_AGENT, 'Accept': 'application/json' },
    };
    https.get(url, opts, (res) => {
      if (res.statusCode === 429) return reject(new Error('SEC rate-limited (429)'));
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        try { resolve(JSON.parse(body)); } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

async function getTickerMap() {
  if (fs.existsSync(TICKER_MAP_FILE)) {
    const stat = fs.statSync(TICKER_MAP_FILE);
    if (Date.now() - stat.mtimeMs < 30 * 24 * 60 * 60 * 1000) {
      return JSON.parse(fs.readFileSync(TICKER_MAP_FILE, 'utf8'));
    }
  }
  const data = await getJson(`${SEC_BASE.replace('data.', 'www.')}/files/company_tickers.json`);
  // Map by ticker → cik
  const map = {};
  for (const k of Object.keys(data)) {
    const row = data[k];
    map[row.ticker.toUpperCase()] = String(row.cik_str).padStart(10, '0');
  }
  fs.writeFileSync(TICKER_MAP_FILE, JSON.stringify(map));
  return map;
}

async function fetchFacts(cik) {
  const cacheFile = path.join(CACHE_DIR, `${cik}.json`);
  if (fs.existsSync(cacheFile)) {
    const stat = fs.statSync(cacheFile);
    if (Date.now() - stat.mtimeMs < CACHE_TTL_MS) {
      return JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    }
  }

  const url = `${SEC_BASE}/api/xbrl/companyfacts/CIK${cik}.json`;
  let data;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      data = await getJson(url);
      break;
    } catch (err) {
      if (err.message.includes('429')) {
        await new Promise((r) => setTimeout(r, 5000 * (attempt + 1)));
        continue;
      }
      throw err;
    }
  }

  fs.writeFileSync(cacheFile, JSON.stringify(data));
  return data;
}

function pickLatestAnnual(facts, key) {
  // facts.facts['us-gaap'][key].units.USD = array of {end, val, fy, fp, form}
  const gaap = facts.facts?.['us-gaap']?.[key]?.units?.USD || facts.facts?.['us-gaap']?.[key]?.units?.shares;
  if (!gaap) return null;
  const annual = gaap.filter((d) => d.fp === 'FY' && d.form === '10-K').sort((a, b) => b.end.localeCompare(a.end));
  return annual[0] || null;
}

function pickAnnualSeries(facts, key, n = 5) {
  const gaap = facts.facts?.['us-gaap']?.[key]?.units?.USD || facts.facts?.['us-gaap']?.[key]?.units?.shares;
  if (!gaap) return [];
  const annual = gaap.filter((d) => d.fp === 'FY' && d.form === '10-K').sort((a, b) => b.end.localeCompare(a.end));
  return annual.slice(0, n);
}

async function main() {
  const args = process.argv.slice(2);
  const cikArg = args.find((a) => a.startsWith('--cik='))?.split('=')[1];
  const ticker = args.find((a) => !a.startsWith('--'));

  if (!cikArg && !ticker) {
    console.error('Usage: fetch-sec-facts.js TICKER  OR  fetch-sec-facts.js --cik=0000320193');
    process.exit(1);
  }

  ensureCacheDir();

  let cik = cikArg;
  if (!cik) {
    const map = await getTickerMap();
    cik = map[ticker.toUpperCase()];
    if (!cik) {
      console.error(`No CIK found for ${ticker}`);
      process.exit(2);
    }
  }

  const facts = await fetchFacts(cik);

  const summary = {
    cik,
    ticker: ticker || null,
    entity_name: facts.entityName,
    fetched_at: new Date().toISOString(),
    facts: {},
    series: {},
  };

  for (const key of KEY_FACTS) {
    const latest = pickLatestAnnual(facts, key);
    if (latest) {
      summary.facts[key] = { value: latest.val, fy: latest.fy, end: latest.end };
      summary.series[key] = pickAnnualSeries(facts, key, 7).map((d) => ({ fy: d.fy, end: d.end, val: d.val }));
    }
  }

  process.stdout.write(JSON.stringify(summary, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
