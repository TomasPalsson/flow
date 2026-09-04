#!/usr/bin/env node
/**
 * fetch-insider.js
 * SEC Form 4 insider transactions for a ticker (last 12 months).
 * Applies Cohen-Malloy-Pomorski "opportunistic" filter where possible.
 *
 * Output JSON: { ticker, cik, transactions[], cluster_buy_detected, cluster_sell_detected }
 *
 * Caching: 24-hour TTL.
 *
 * Usage: node fetch-insider.js TICKER
 *
 * FIELD GUIDE -- STRICT vs LEGACY cluster tests (do not confuse the two):
 *   LEGACY / LOOSE  -- `summary.cluster_buy_max_unique_in_90d` and `summary.cluster_buy_signal`.
 *     3+ distinct buyers in a flat 90-day window. NO transaction-type filter beyond code
 *     P/direction A, NO 10b5-1 exclusion. Kept as-is -- the sibling investment skill may
 *     depend on it. Treat it as noisy: Cohen, Malloy & Pomorski (2012) find this loose
 *     definition mixes ~zero-alpha ROUTINE clusters in with the real signal.
 *   STRICT / OPPORTUNISTIC -- `summary.cluster_buy_opportunistic_7d` / `_14d`,
 *     `summary.has_c_suite_buyer`, `summary.opportunistic_cluster_signal`.
 *     3+ distinct insiders, transaction_code 'P' ONLY, `is_10b5_1 !== true` (undetermined
 *     still counts -- see below), within a rolling 7d or 14d window. This is the closer
 *     approximation of the ~82bp/mo "opportunistic" cluster from Cohen/Malloy/Pomorski.
 *     Per-transaction `is_10b5_1` is true|false|null -- null means UNDETERMINED (could not
 *     confirm either way from the XML), not false. A null is deliberately still counted as
 *     "not confirmed-scheduled" for clustering purposes -- see cluster helper below.
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill', 'insider');
const TICKER_MAP_FILE = path.join(os.homedir(), '.cache', 'investment-skill', 'sec-tickers.json');
const CACHE_TTL_MS = 24 * 60 * 60 * 1000;
const USER_AGENT = 'investment-skill tomas@p5.is (research/educational)';
const SEC_DATA = 'https://data.sec.gov';
const SEC_WWW = 'https://www.sec.gov';

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function getJson(url) {
  return new Promise((resolve, reject) => {
    https.get(url, { headers: { 'User-Agent': USER_AGENT, 'Accept': 'application/json' } }, (res) => {
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

async function getCikForTicker(ticker) {
  if (!fs.existsSync(TICKER_MAP_FILE)) {
    const data = await getJson(`${SEC_WWW}/files/company_tickers.json`);
    const map = {};
    for (const k of Object.keys(data)) {
      map[data[k].ticker.toUpperCase()] = String(data[k].cik_str).padStart(10, '0');
    }
    fs.writeFileSync(TICKER_MAP_FILE, JSON.stringify(map));
  }
  const map = JSON.parse(fs.readFileSync(TICKER_MAP_FILE, 'utf8'));
  return map[ticker.toUpperCase()];
}

// 10b5-1 footnote text is free-form legalese; SEC's own boilerplate + common filer phrasing
// all contain "10b5-1" or "10b5(1)" somewhere, so a loose regex is deliberate here.
const RULE_10B5_1_TEXT_RE = /10b5-?1/i;

function detectDocLevelAff10b5One(xml) {
  // Document-level checkbox added by SEC's 2023 Rule 10b5-1 amendments (Release 33-11138).
  // 0/1 = filer affirmatively answered; missing on pre-2023 filings = undetermined (null).
  const m = xml.match(/<aff10b5One>\s*([01])\s*<\/aff10b5One>/);
  return m ? m[1] === '1' : null;
}

function parseFootnotes(xml) {
  const map = {};
  for (const m of xml.matchAll(/<footnote\s+id="([^"]+)">([\s\S]*?)<\/footnote>/g)) {
    map[m[1]] = m[2];
  }
  return map;
}

// Per-transaction 10b5-1 detection. Verified against a real 2026 EDGAR Form 4
// (StepStone Group, CIK 1796022, accession 0001822276-26-000006): the current schema
// (X0609) has NO per-transaction structured 10b5-1 element -- the plan disclosure lives
// ONLY in free-text footnotes ("...executed pursuant to a Rule 10b5-1 trading plan...")
// referenced from the transaction via <footnoteId id="..."/>, plus the document-level
// <aff10b5One> checkbox. We still probe for a structured per-transaction tag defensively
// (some filer software may emit one, and SEC's schema has changed before), but in practice
// it is the footnote text + doc-level flag doing the real work.
function detectTransactionIs10b5_1(block, footnotesMap, docAff10b5One) {
  // Defensive: structured element, if some filing ever carries one (not observed in the wild).
  const structuredMatch = block.match(/<rule10b5-?1(?:Plan)?>\s*(?:<value>)?\s*([01]|true|false)\s*(?:<\/value>)?\s*<\/rule10b5-?1(?:Plan)?>/i);
  const structuredValue = structuredMatch ? /^(1|true)$/i.test(structuredMatch[1]) : null;

  const footnoteIds = [...block.matchAll(/<footnoteId\s+id="([^"]+)"/g)].map((m) => m[1]);
  const footnoteText = footnoteIds.map((id) => footnotesMap[id] || '').join(' ');
  const footnoteSaysPlan = RULE_10B5_1_TEXT_RE.test(footnoteText);

  if (structuredValue === true || footnoteSaysPlan) return true;
  if (structuredValue === false) return false;
  if (docAff10b5One === false) return false; // filer affirmatively said: no 10b5-1 activity in this filing
  return null; // undetermined -- NOT false
}

function parseForm4Xml(xml) {
  // Best-effort regex parse of Form 4 XML (full XML parsing is heavy; the structure is consistent)
  const reporting = xml.match(/<reportingOwnerId>[\s\S]*?<rptOwnerName>([^<]+)<\/rptOwnerName>[\s\S]*?<\/reportingOwnerId>/)?.[1] || 'Unknown';
  const isOfficer = /<isOfficer>1<\/isOfficer>/.test(xml);
  const isDirector = /<isDirector>1<\/isDirector>/.test(xml);
  const officerTitle = xml.match(/<officerTitle>([^<]+)<\/officerTitle>/)?.[1] || null;
  const docAff10b5One = detectDocLevelAff10b5One(xml);
  const footnotesMap = parseFootnotes(xml);

  const transactions = [];
  // Non-derivative transactions (direct stock buys/sells)
  const txns = [...xml.matchAll(/<nonDerivativeTransaction>([\s\S]*?)<\/nonDerivativeTransaction>/g)];
  for (const t of txns) {
    const block = t[1];
    const date = block.match(/<transactionDate>[\s\S]*?<value>([^<]+)<\/value>/)?.[1];
    const code = block.match(/<transactionCode>([^<]+)<\/transactionCode>/)?.[1];
    const shares = parseFloat(block.match(/<transactionShares>[\s\S]*?<value>([^<]+)<\/value>/)?.[1] || '0');
    const price = parseFloat(block.match(/<transactionPricePerShare>[\s\S]*?<value>([^<]+)<\/value>/)?.[1] || '0');
    const acqDisp = block.match(/<transactionAcquiredDisposedCode>[\s\S]*?<value>([^<]+)<\/value>/)?.[1];
    const is10b51 = detectTransactionIs10b5_1(block, footnotesMap, docAff10b5One);
    transactions.push({
      date,
      code,
      transaction_code: code, // explicit alias -- see house rule: additive fields only
      shares,
      price,
      value: shares * price,
      direction: acqDisp,
      is_10b5_1: is10b51,
    });
  }
  return { reporting, isOfficer, isDirector, officerTitle, docAff10b5One, transactions };
}

async function fetchInsider(ticker) {
  const cik = await getCikForTicker(ticker);
  if (!cik) throw new Error(`No CIK for ${ticker}`);

  // Get submissions list
  const subs = await getJson(`${SEC_DATA}/submissions/CIK${cik}.json`);
  const recent = subs.filings?.recent;
  if (!recent) return { ticker, cik, transactions: [], note: 'No filings in submissions' };

  // Find Form 4 filings in last 365 days
  const cutoff = new Date(Date.now() - 365 * 24 * 3600 * 1000).toISOString().slice(0, 10);
  const indices = [];
  for (let i = 0; i < recent.accessionNumber.length; i++) {
    if (recent.form[i] === '4' && recent.filingDate[i] >= cutoff) {
      indices.push(i);
    }
  }

  const allTxns = [];
  const peopleSeen = new Set();
  // SEC rate limit: 10 req/sec → 110ms spacing
  for (const idx of indices.slice(0, 40)) {
    const accession = recent.accessionNumber[idx].replace(/-/g, '');
    const filingDate = recent.filingDate[idx];
    const primaryDoc = recent.primaryDocument[idx];

    if (!primaryDoc.endsWith('.xml')) continue; // Form 4 has XML primary doc

    // PRE-EXISTING BUG FIX (discovered while verifying the 10b5-1 work below): SEC's
    // submissions.json primaryDocument frequently includes an "xslF345X0N/" folder prefix
    // (e.g. "xslF345X06/form4.xml") -- that path is the XSLT-RENDERED HTML VIEWER, not the
    // raw filer XML, even though it ends in ".xml" and returns HTTP 200. The raw XML always
    // sits flat in the accession root under its bare filename. Verified against real EDGAR
    // filings (StepStone Group CIK 1796022 accession 0001822276-26-000006, Palantir CIK
    // 1321655 filer 0001140361, Apple CIK 320193) -- every recent filing checked had this
    // prefix. Without stripping it, parseForm4Xml() silently receives HTML and returns zero
    // transactions with no error (HTTP 200), which is why this script has likely been
    // returning empty results for most/all tickers in production.
    const primaryDocFile = primaryDoc.split('/').pop();
    const url = `${SEC_WWW}/Archives/edgar/data/${parseInt(cik)}/${accession}/${primaryDocFile}`;
    try {
      const xml = await getText(url);
      const parsed = parseForm4Xml(xml);
      peopleSeen.add(parsed.reporting);
      for (const t of parsed.transactions) {
        allTxns.push({
          ...t,
          reporting: parsed.reporting,
          is_officer: parsed.isOfficer,
          is_director: parsed.isDirector,
          officer_title: parsed.officerTitle,
          filing_date: filingDate,
        });
      }
    } catch (err) {
      console.error(`WARN: ${url} failed: ${err.message}`);
    }
    await new Promise((r) => setTimeout(r, 110));
  }

  // Cluster detection
  const buys = allTxns.filter((t) => t.code === 'P' && t.direction === 'A'); // Code P = open-market purchase, Acquired
  const sells = allTxns.filter((t) => t.code === 'S' && t.direction === 'D');

  const buyersUnique = new Set(buys.map((t) => t.reporting));
  const sellersUnique = new Set(sells.map((t) => t.reporting));

  // LEGACY / LOOSE: 90-day rolling cluster of 3+ unique buyers (open-market), no 10b5-1
  // filtering. Kept unchanged -- see header comment for why this is the weak-lead field.
  const buyDates = buys.map((b) => new Date(b.filing_date).getTime());
  let clusterBuyCount = 0;
  for (const date of buyDates) {
    const within90d = buys.filter((b) => Math.abs(new Date(b.filing_date).getTime() - date) <= 90 * 24 * 3600 * 1000);
    const uniqueIn90d = new Set(within90d.map((b) => b.reporting));
    if (uniqueIn90d.size >= 3) {
      clusterBuyCount = Math.max(clusterBuyCount, uniqueIn90d.size);
    }
  }

  const ceoCfoBuys = buys.filter((b) => /CEO|Chief Executive|CFO|Chief Financial/i.test(b.officer_title || ''));

  // STRICT / OPPORTUNISTIC (Cohen, Malloy & Pomorski 2012): code 'P' only, and exclude
  // CONFIRMED 10b5-1 scheduled trades. `is_10b5_1 !== true` deliberately keeps null
  // (undetermined) in the opportunistic pool -- an unconfirmed trade is not proof of a
  // scheduled plan, and dropping every null would starve the signal on older filings
  // where the footnote/checkbox disclosure simply doesn't exist.
  const opportunisticBuys = buys.filter((b) => b.is_10b5_1 !== true);

  const DAY_MS = 24 * 3600 * 1000;
  // Rolling window over actual trade date (falls back to filing_date if the XML's
  // transactionDate didn't parse) -- trade date is the correct clustering axis per
  // Cohen/Malloy/Pomorski's methodology; filing_date only reflects reporting lag.
  function clusterWindowAnalysis(txns, windowMs) {
    let best = { max_unique_insiders: 0, contributors: [] };
    for (const anchor of txns) {
      const anchorTime = new Date(anchor.date || anchor.filing_date).getTime();
      if (Number.isNaN(anchorTime)) continue;
      const within = txns.filter((o) => {
        const t = new Date(o.date || o.filing_date).getTime();
        return !Number.isNaN(t) && Math.abs(t - anchorTime) <= windowMs;
      });
      const uniqueReporters = new Set(within.map((o) => o.reporting));
      if (uniqueReporters.size > best.max_unique_insiders) {
        const seen = new Set();
        const contributors = [];
        for (const o of within) {
          if (seen.has(o.reporting)) continue;
          seen.add(o.reporting);
          contributors.push({ reporting: o.reporting, date: o.date || o.filing_date, officer_title: o.officer_title });
        }
        best = { max_unique_insiders: uniqueReporters.size, contributors };
      }
    }
    return best;
  }

  const cluster7d = clusterWindowAnalysis(opportunisticBuys, 7 * DAY_MS);
  const cluster14d = clusterWindowAnalysis(opportunisticBuys, 14 * DAY_MS);

  const C_SUITE_RE = /\b(CEO|Chief Executive|CFO|Chief Financial|COO|Chief Operating|President)\b/i;
  const hasCSuiteBuyer = opportunisticBuys.some((b) => C_SUITE_RE.test(b.officer_title || ''));

  // Combined signal. Thresholds (3+ insiders, 7d/14d window widths, C-suite gate) are
  // UNVALIDATED PRIORS loosely drawn from Cohen/Malloy/Pomorski's opportunistic-cluster
  // description -- they have NOT been backtested against this account's universe. Rationale:
  // a same-week (7d) cluster of 3+ opportunistic buyers is tight enough to stand on its own;
  // a looser 14d cluster is only treated as a real signal if a C-suite buyer (weighted above
  // directors per Cohen et al.) participated, since C-suite buys carry more information.
  const opportunisticClusterSignal =
    (cluster14d.max_unique_insiders >= 3 && hasCSuiteBuyer) || cluster7d.max_unique_insiders >= 3;

  return {
    ticker,
    cik,
    fetched_at: new Date().toISOString(),
    filings_examined: indices.length,
    transactions: allTxns,
    summary: {
      total_buys_open_market: buys.length,
      unique_buyers: buyersUnique.size,
      total_sells: sells.length,
      unique_sellers: sellersUnique.size,
      ceo_cfo_open_market_buys: ceoCfoBuys.length,
      cluster_buy_max_unique_in_90d: clusterBuyCount,
      cluster_buy_signal: clusterBuyCount >= 3,
      total_buy_value_usd: buys.reduce((sum, b) => sum + b.value, 0),
      total_sell_value_usd: sells.reduce((sum, s) => sum + s.value, 0),
      // -- STRICT opportunistic fields (see header comment) --
      cluster_buy_opportunistic_7d: {
        max_unique_insiders: cluster7d.max_unique_insiders,
        signal: cluster7d.max_unique_insiders >= 3,
        window_days: 7,
        contributors: cluster7d.contributors,
      },
      cluster_buy_opportunistic_14d: {
        max_unique_insiders: cluster14d.max_unique_insiders,
        signal: cluster14d.max_unique_insiders >= 3,
        window_days: 14,
        contributors: cluster14d.contributors,
      },
      has_c_suite_buyer: hasCSuiteBuyer,
      opportunistic_cluster_signal: opportunisticClusterSignal,
    },
  };
}

async function main() {
  const ticker = process.argv[2];
  if (!ticker) {
    console.error('Usage: fetch-insider.js TICKER');
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

  const result = await fetchInsider(ticker);
  const out = JSON.stringify(result, null, 2);
  fs.writeFileSync(cacheFile, out);
  process.stdout.write(out);
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
