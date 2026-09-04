#!/usr/bin/env node
/**
 * fetch-13f.js
 * Track superinvestor 13F holdings — see if any well-known investor holds the ticker.
 *
 * Reads CIKs from ../data/superinvestor-ciks.json
 *
 * Output: { ticker, holdings: [{ holder, holder_cik, shares, value, as_of, percent_of_portfolio }] }
 *
 * Caching: 7-day TTL.
 *
 * Usage: node fetch-13f.js TICKER
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill', '13f');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const USER_AGENT = 'investment-skill tomas@p5.is (research/educational)';
const SEC_DATA = 'https://data.sec.gov';
const SEC_WWW = 'https://www.sec.gov';

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT } }, (res) => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => { try { resolve(JSON.parse(body)); } catch (e) { reject(e); } });
    }).on('error', reject);
  });
}

function getText(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT } }, (res) => {
      if (res.statusCode !== 200) return reject(new Error(`HTTP ${res.statusCode}`));
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => resolve(body));
    }).on('error', reject);
  });
}

function loadSuperinvestors() {
  // Path relative to script location
  const scriptDir = path.dirname(new URL(import.meta.url).pathname);
  const dataPath = path.join(scriptDir, '..', 'data', 'superinvestor-ciks.json');
  if (!fs.existsSync(dataPath)) {
    console.error(`Superinvestor CIK list not found at ${dataPath}`);
    return [];
  }
  return JSON.parse(fs.readFileSync(dataPath, 'utf8'));
}

async function getLatestForm13F(cik) {
  const subs = await getJson(`${SEC_DATA}/submissions/CIK${cik}.json`);
  const recent = subs.filings?.recent;
  if (!recent) return null;
  for (let i = 0; i < recent.accessionNumber.length; i++) {
    if (recent.form[i] === '13F-HR') {
      return {
        accession: recent.accessionNumber[i],
        filing_date: recent.filingDate[i],
        primary_doc: recent.primaryDocument[i],
        period_of_report: recent.reportDate?.[i],
      };
    }
  }
  return null;
}

function parseInfoTable(xml, targetTicker, targetTickerVariants) {
  // 13F-HR information table has rows for each holding
  // <infoTable>
  //   <nameOfIssuer>APPLE INC</nameOfIssuer>
  //   <titleOfClass>COM</titleOfClass>
  //   <cusip>037833100</cusip>
  //   <value>1234567</value>
  //   <shrsOrPrnAmt>
  //     <sshPrnamt>1000000</sshPrnamt>
  //   </shrsOrPrnAmt>
  // ...
  const matches = [...xml.matchAll(/<infoTable>([\s\S]*?)<\/infoTable>/g)];
  const upperTargets = [targetTicker.toUpperCase(), ...(targetTickerVariants || [])];
  for (const m of matches) {
    const block = m[1];
    const name = block.match(/<nameOfIssuer>([^<]+)<\/nameOfIssuer>/)?.[1] || '';
    // Best-effort matching — name often abbreviated
    const upperName = name.toUpperCase();
    if (upperTargets.some((t) => upperName.includes(t) || upperName.includes(t.replace(/\s+/g, '')))) {
      const value = parseInt(block.match(/<value>([^<]+)<\/value>/)?.[1] || '0', 10);
      const shares = parseInt(block.match(/<sshPrnamt>([^<]+)<\/sshPrnamt>/)?.[1] || '0', 10);
      const cusip = block.match(/<cusip>([^<]+)<\/cusip>/)?.[1];
      return { name, value_usd: value * 1000, shares, cusip };
    }
  }
  return null;
}

async function checkHolding(superinvestor, ticker) {
  try {
    const latest = await getLatestForm13F(superinvestor.cik);
    if (!latest) return null;

    const accession = latest.accession.replace(/-/g, '');
    // Information Table URL — typical name is "infotable.xml" or similar
    // We need to find the actual file name; use the filing index
    const indexUrl = `${SEC_WWW}/Archives/edgar/data/${parseInt(superinvestor.cik)}/${accession}/`;
    const indexHtml = await getText(indexUrl);
    const xmlMatch = indexHtml.match(/href="([^"]*infotable[^"]*\.xml|[^"]*Information_Table[^"]*\.xml)"/i);
    if (!xmlMatch) return null;
    const xmlUrl = xmlMatch[1].startsWith('http') ? xmlMatch[1] : `${SEC_WWW}${xmlMatch[1].startsWith('/') ? '' : '/'}${xmlMatch[1]}`;

    const xml = await getText(xmlUrl);
    const holding = parseInfoTable(xml, ticker, superinvestor.tickerVariants);
    if (holding) {
      return {
        holder: superinvestor.name,
        holder_cik: superinvestor.cik,
        as_of: latest.period_of_report,
        ...holding,
      };
    }
  } catch (err) {
    console.error(`WARN: ${superinvestor.name}: ${err.message}`);
  }
  return null;
}

async function main() {
  const ticker = process.argv[2];
  if (!ticker) {
    console.error('Usage: fetch-13f.js TICKER');
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

  const superinvestors = loadSuperinvestors();
  if (superinvestors.length === 0) {
    console.error('No superinvestors configured. Populate data/superinvestor-ciks.json.');
    process.exit(2);
  }

  const holdings = [];
  for (const si of superinvestors) {
    const h = await checkHolding(si, ticker);
    if (h) holdings.push(h);
    await new Promise((r) => setTimeout(r, 250)); // gentle pacing — multiple SEC calls per superinvestor
  }

  const result = {
    ticker,
    fetched_at: new Date().toISOString(),
    superinvestors_checked: superinvestors.length,
    holdings_found: holdings.length,
    holdings,
  };

  fs.writeFileSync(cacheFile, JSON.stringify(result, null, 2));
  process.stdout.write(JSON.stringify(result, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
