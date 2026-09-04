#!/usr/bin/env node
/**
 * fetch-universe.js
 * Scrape Wikipedia for S&P 1500 constituents (S&P 500 + S&P 400 MidCap + S&P 600 SmallCap).
 * Outputs JSON to stdout: array of {ticker, name, sector, sub_industry, cik}.
 *
 * Caching: 7-day TTL at ~/.cache/investment-skill/universe.json
 *
 * Usage: node fetch-universe.js [--output=cache] [--no-cache] [--format=json|csv]
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill');
const CACHE_FILE = path.join(CACHE_DIR, 'universe.json');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

const SOURCES = [
  { name: 'S&P 500', url: 'https://en.wikipedia.org/wiki/List_of_S%26P_500_companies', tableIndex: 0 },
  { name: 'S&P 400', url: 'https://en.wikipedia.org/wiki/List_of_S%26P_400_companies', tableIndex: 0 },
  { name: 'S&P 600', url: 'https://en.wikipedia.org/wiki/List_of_S%26P_600_companies', tableIndex: 0 },
];

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function fetchHtml(url) {
  return new Promise((resolve, reject) => {
    const opts = {
      headers: {
        'User-Agent': 'Mozilla/5.0 (investment-skill; tomas@p5.is)',
      },
    };
    https.get(url, opts, (res) => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode} for ${url}`));
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });
}

function parseTable(html, tableIndex = 0) {
  // Wikipedia "wikitable sortable" — extract rows
  const tableMatches = [...html.matchAll(/<table[^>]*class="[^"]*wikitable[^"]*"[^>]*>([\s\S]*?)<\/table>/g)];
  if (tableMatches.length <= tableIndex) {
    throw new Error(`Table ${tableIndex} not found (only ${tableMatches.length} tables)`);
  }
  const tableHtml = tableMatches[tableIndex][1];
  const rows = [...tableHtml.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)];

  const stripTags = (s) => s.replace(/<[^>]*>/g, '').replace(/&amp;/g, '&').replace(/&nbsp;/g, ' ').replace(/&#?\w+;/g, '').trim();

  const data = [];
  for (let i = 1; i < rows.length; i++) { // skip header
    const cells = [...rows[i][1].matchAll(/<t[hd][^>]*>([\s\S]*?)<\/t[hd]>/g)].map((m) => stripTags(m[1]));
    if (cells.length < 3) continue;
    data.push(cells);
  }
  return data;
}

function normalizeRow(row, sourceName) {
  // Column patterns vary across S&P 500 / 400 / 600 — handle defensively
  // S&P 500: Symbol, Security, GICS Sector, GICS Sub-Industry, Headquarters, Date added, CIK, Founded
  // S&P 400: Symbol, Security, GICS Sector, GICS Sub-Industry, Headquarters, Date added, CIK
  // S&P 600: Symbol, Company, GICS economic sector, GICS sub-industry, Headquarters, CIK
  const ticker = (row[0] || '').replace(/[^A-Z.\-]/gi, '').toUpperCase();
  const name = row[1] || '';
  const sector = row[2] || '';
  const subIndustry = row[3] || '';
  // CIK column is variable
  const cikRaw = (row[6] || row[5] || '').match(/\d+/);
  const cik = cikRaw ? cikRaw[0].padStart(10, '0') : null;
  return ticker ? { ticker, name, sector, sub_industry: subIndustry, cik, index: sourceName } : null;
}

async function fetchOne(source) {
  const html = await fetchHtml(source.url);
  const rows = parseTable(html, source.tableIndex);
  return rows.map((r) => normalizeRow(r, source.name)).filter(Boolean);
}

async function main() {
  const args = new Set(process.argv.slice(2));
  const useCache = !args.has('--no-cache');
  const format = process.argv.includes('--format=csv') ? 'csv' : 'json';

  ensureCacheDir();

  if (useCache && fs.existsSync(CACHE_FILE)) {
    const stat = fs.statSync(CACHE_FILE);
    if (Date.now() - stat.mtimeMs < CACHE_TTL_MS) {
      process.stdout.write(fs.readFileSync(CACHE_FILE, 'utf8'));
      return;
    }
  }

  const all = [];
  for (const source of SOURCES) {
    try {
      const rows = await fetchOne(source);
      all.push(...rows);
      console.error(`Fetched ${rows.length} from ${source.name}`);
    } catch (err) {
      console.error(`WARN: ${source.name} failed: ${err.message}`);
    }
  }

  // De-duplicate by ticker (dual-class issuance creates duplicates)
  const seen = new Set();
  const dedup = all.filter((r) => {
    if (seen.has(r.ticker)) return false;
    seen.add(r.ticker);
    return true;
  });

  const out = JSON.stringify({ fetched_at: new Date().toISOString(), count: dedup.length, tickers: dedup }, null, 2);
  fs.writeFileSync(CACHE_FILE, out);

  if (format === 'csv') {
    console.log('ticker,name,sector,sub_industry,cik,index');
    for (const r of dedup) {
      console.log([r.ticker, JSON.stringify(r.name), JSON.stringify(r.sector), JSON.stringify(r.sub_industry), r.cik || '', r.index].join(','));
    }
  } else {
    process.stdout.write(out);
  }
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
