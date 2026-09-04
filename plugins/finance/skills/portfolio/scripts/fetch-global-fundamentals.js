#!/usr/bin/env node
/**
 * fetch-global-fundamentals.js
 *
 * Fetch fundamentals (valuation ratios, quality metrics, and — best
 * effort — statement history) for one or more Yahoo Finance symbols,
 * including non-US exchange suffixes, via `quoteSummary`.
 *
 * This script encodes binding constraints from
 * references/04-global-data.md (empirically verified against 21 real
 * symbols across 17 non-US markets, yahoo-finance2 v3.14.0). Read that
 * file before changing the module list or the fundamentalsTimeSeries
 * decision below.
 *
 * 1. `summaryDetail`, `defaultKeyStatistics`, `financialData`, `price`
 *    had 100% coverage across all 21 tested symbols — these are the
 *    always-requested modules.
 * 2. `financialData.financialCurrency` (the currency a company's
 *    FINANCIAL STATEMENTS are reported in) differs from `price.currency`
 *    (the currency its SHARES TRADE in) on ~24% of global names in the
 *    tested sample (e.g. Shopify: CAD shares / USD financials; Tencent:
 *    HKD shares / CNY financials). Both are captured separately here,
 *    with an explicit `currency_mismatch` flag — never assume they match.
 *    A mismatch means any ratio mixing a price-based figure (market cap,
 *    share price) with a financials-based figure (revenue, book value)
 *    is NOT directly comparable/valid unless FX-converted first.
 * 3. `incomeStatementHistory` / `balanceSheetHistory` /
 *    `cashflowStatementHistory` are attempted opportunistically but can
 *    come back EMPTY WITH NO THROWN ERROR (observed live for ITX.MC and
 *    D05.SI, 2 of 21 symbols, despite `summaryDetail`/`financialData`
 *    being fully populated on the same call). This script explicitly
 *    detects that empty-but-no-error case and marks the corresponding
 *    output field UNKNOWN — it never treats an empty array as "no data,
 *    therefore fine." The yahoo-finance2 library itself additionally
 *    emits a blanket deprecation warning on every call regardless of
 *    outcome ("...have provided almost no data since Nov 2024...") —
 *    that warning firing is NOT a reliable signal of emptiness for any
 *    single symbol and is not used as one here.
 * 4. `fundamentalsTimeSeries` is DELIBERATELY NOT USED. It was tested
 *    live against 6 non-US symbols using the exact call shape the house
 *    `fetch-financials.js` script uses and failed on every single one
 *    with `yahooFinance.fundamentalsTimeSeries() option type invalid.`
 *    Do NOT "helpfully" add it back without re-verifying against a fixed
 *    package version — see references/04-global-data.md §1 (data sourcing reality).
 * 5. If this script (or any future edit to it) calls `yf.search()`, it
 *    MUST pass `{ validateResult: false }` as the third argument — the
 *    pinned 3.14.0 package throws `Failed Yahoo Schema validation`
 *    otherwise, on every query, because Yahoo's live response no longer
 *    matches the bundled Ajv schema. This script does not currently call
 *    `search()` at all (symbols must be passed in pre-resolved), but the
 *    rule is documented here for whoever adds that next.
 *
 * Caching: 7-day TTL per symbol, under ~/.cache/portfolio-skill/fundamentals/.
 *
 * Rate-limiting: Yahoo's anti-bot layer throttles by withholding the
 * set-cookie header its crumb dance depends on — yahoo-finance2 surfaces
 * that as `No set-cookie header present in Yahoo's response. Something
 * must have changed, please report.`, which reads like a bug report, not a
 * "slow down" signal. This script detects that signature (and plain HTTP
 * 429s) specifically, reports it as a rate-limit distinct from a genuine
 * bad-symbol/missing-coverage failure, and retries the affected batch with
 * exponential backoff instead of giving up immediately. See
 * fetch-global-quote.js's header for the live-verified 841/841 failure
 * this defends against.
 *
 * Usage:
 *   node fetch-global-fundamentals.js SYMBOL [SYMBOL...] [--batch-size N] [--delay-ms N]
 *   node fetch-global-fundamentals.js --self-test
 *
 * Output: JSON on stdout — { results: [...], failures: [...], as_of }.
 * All backoff/retry/self-test logging goes to stderr — stdout is reserved
 * for the JSON result.
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'portfolio-skill', 'fundamentals');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

// Default batch size (quoteSummary with 7 modules is heavier than a plain
// quote() call — stay conservative on concurrency to avoid tripping
// Yahoo's rate limiter) and the delay between batches. Empirically,
// unthrottled batches at scale triggered a 100% rate-limit block; small
// batches with pauses worked. quoteSummary is heavier than quote(), so the
// default delay here is larger than fetch-global-quote.js's.
const DEFAULT_BATCH_SIZE = 3;
const DEFAULT_DELAY_MS = 3000;

// Exponential backoff schedule applied to a batch when Yahoo throttles it
// (5s, 15s, 45s), with a hard cap on attempts so a persistent block still
// terminates instead of retrying forever.
const BACKOFF_SCHEDULE_MS = [5000, 15000, 45000];
const MAX_BACKOFF_RETRIES = BACKOFF_SCHEDULE_MS.length;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Known throttle/anti-bot signatures surfaced by yahoo-finance2 when Yahoo
// withholds the set-cookie header its crumb flow depends on, or returns a
// plain HTTP 429. Matched narrowly and distinctly from genuine per-symbol
// failures (missing core modules, invalid symbol) so the two never
// collapse into one misleading message.
const RATE_LIMIT_SIGNATURE_RE = /no set-cookie header|too many requests|\b429\b|\brate[ -]?limit/i;

/**
 * @param {*} err - anything caught from a yahoo-finance2 call (or a plain
 *   object/Error in tests).
 * @returns {boolean} true if this looks like Yahoo throttling rather than
 *   a genuine per-symbol failure.
 */
function isRateLimitError(err) {
  if (!err) return false;
  if (err.code === 429 || err.code === '429') return true;
  return RATE_LIMIT_SIGNATURE_RE.test(String(err.message || err));
}

/**
 * Build the failure message for a thrown quoteSummary() error, branching
 * on whether it is a detected rate-limit vs a genuine per-symbol problem.
 * Pure function — exercised directly by --self-test, no network needed.
 *
 * @param {string} symbol
 * @param {Error} err
 * @returns {{ rateLimited: boolean, message: string }}
 */
function classifyAndDescribeFundamentalsError(symbol, err) {
  if (isRateLimitError(err)) {
    return {
      rateLimited: true,
      message: `quoteSummary() failed for "${symbol}": rate-limited by Yahoo Finance (${err.message}). ` +
        'This is NOT a bad-symbol/exchange-suffix problem — Yahoo is throttling this run. ' +
        'Reduce --batch-size and/or increase --delay-ms, then retry.',
    };
  }
  return {
    rateLimited: false,
    message: `quoteSummary() failed for "${symbol}": ${err.message}. ` +
      'Verify the symbol includes the correct Yahoo exchange suffix (e.g. ".L", ".AS", ".T").',
  };
}

// Verified 100%-coverage core modules (see file header, point 1).
const CORE_MODULES = ['summaryDetail', 'defaultKeyStatistics', 'financialData', 'price'];

// Statement-history modules: attempted opportunistically. Verified to be
// unreliable (empty-without-error for 2/21 tested symbols) — see file
// header, point 3. Requested in the SAME call as the core modules so a
// symbol only costs one HTTP round trip; their absence/emptiness never
// fails the whole fetch.
const STATEMENT_HISTORY_MODULES = [
  'incomeStatementHistory',
  'balanceSheetHistory',
  'cashflowStatementHistory',
];

const ALL_MODULES = [...CORE_MODULES, ...STATEMENT_HISTORY_MODULES];

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

async function loadYf() {
  try {
    const mod = await import('yahoo-finance2');
    const YahooFinance = mod.default;
    // v3 requires instantiation. NOTE: unlike the house fetch-quote.js /
    // fetch-financials.js pattern (`if (yf.suppressNotices) yf.suppressNotices(...)`),
    // the installed 3.14.0 build has NO `suppressNotices` instance method —
    // that guarded call silently no-ops. Notice suppression must instead be
    // passed as a CONSTRUCTOR option, confirmed working live. This matters
    // because the unsuppressed notice is written via the default logger
    // (console.info -> stdout) and would otherwise corrupt this script's
    // JSON stdout output for any downstream JSON.parse() consumer.
    // This does NOT suppress the separate per-call statement-history
    // deprecation warning referenced in the file header — that one is
    // emitted by quoteSummary itself, not a "notice" in the suppressible
    // sense, and its presence/absence is not used as a data-quality signal
    // here regardless.
    const yf = (typeof YahooFinance === 'function')
      ? new YahooFinance({ suppressNotices: ['yahooSurvey', 'ripHistorical'] })
      : YahooFinance;
    return yf;
  } catch (err) {
    console.error(
      'FATAL: yahoo-finance2 not installed/importable. Run `npm install yahoo-finance2` ' +
      'in the skill directory (pinned version 3.14.0 verified — see references/04-global-data.md).'
    );
    throw err;
  }
}

function cacheFileFor(symbol) {
  const safe = symbol.replace(/[^A-Za-z0-9._-]/g, '_');
  return path.join(CACHE_DIR, `${safe}.json`);
}

function readCache(symbol) {
  const cacheFile = cacheFileFor(symbol);
  if (!fs.existsSync(cacheFile)) return null;
  const stat = fs.statSync(cacheFile);
  if (Date.now() - stat.mtimeMs >= CACHE_TTL_MS) return null;
  try {
    return JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
  } catch {
    return null; // Corrupt cache entry — treat as a miss, refetch.
  }
}

function writeCache(symbol, record) {
  fs.writeFileSync(cacheFileFor(symbol), JSON.stringify(record, null, 2));
}

/**
 * Determine whether a statement-history module's payload is genuinely
 * populated. Yahoo's shape is `{ <moduleName>: [ {...}, {...} ] }` when
 * present; the verified failure mode is that the array comes back present
 * but EMPTY (length 0) with no thrown error — that must read as UNKNOWN,
 * not as an implicit "no history exists for this company."
 *
 * @param {object|undefined} moduleResult - e.g. quoteSummaryResult.incomeStatementHistory
 * @param {string} arrayKey - e.g. 'incomeStatementHistory'
 * @returns {{ populated: boolean, entries: Array|null }}
 */
function checkStatementHistoryModule(moduleResult, arrayKey) {
  if (!moduleResult || !Array.isArray(moduleResult[arrayKey])) {
    // Module absent entirely from the response (e.g. request itself
    // failed for just this submodule) — also UNKNOWN, not an error.
    return { populated: false, entries: null };
  }
  const entries = moduleResult[arrayKey];
  return { populated: entries.length > 0, entries: entries.length > 0 ? entries : null };
}

/**
 * Core valuation/quality metrics pulled from the four verified-100%
 * modules. Field names are exactly as observed live in
 * references/04-global-data.md / yahoo-finance2's quoteSummary shape —
 * no invented field names.
 */
function extractCoreMetrics(qs) {
  const summaryDetail = qs.summaryDetail || {};
  const defaultKeyStatistics = qs.defaultKeyStatistics || {};
  const financialData = qs.financialData || {};
  const price = qs.price || {};

  return {
    // -- Valuation --
    trailingPE: summaryDetail.trailingPE ?? null,
    forwardPE: summaryDetail.forwardPE ?? null,
    priceToBook: defaultKeyStatistics.priceToBook ?? null,
    priceToSalesTrailing12Months: summaryDetail.priceToSalesTrailing12Months ?? null,
    pegRatio: defaultKeyStatistics.pegRatio ?? null,
    enterpriseValue: defaultKeyStatistics.enterpriseValue ?? null,
    enterpriseToRevenue: defaultKeyStatistics.enterpriseToRevenue ?? null,
    enterpriseToEbitda: defaultKeyStatistics.enterpriseToEbitda ?? null,
    dividendYield: summaryDetail.dividendYield ?? null,
    marketCap: summaryDetail.marketCap ?? price.marketCap ?? null,

    // -- Quality / profitability --
    returnOnEquity: financialData.returnOnEquity ?? null,
    returnOnAssets: financialData.returnOnAssets ?? null,
    profitMargins: financialData.profitMargins ?? null,
    operatingMargins: financialData.operatingMargins ?? null,
    grossMargins: financialData.grossMargins ?? null,
    revenueGrowth: financialData.revenueGrowth ?? null,
    earningsGrowth: financialData.earningsGrowth ?? null,
    debtToEquity: financialData.debtToEquity ?? null,
    currentRatio: financialData.currentRatio ?? null,
    quickRatio: financialData.quickRatio ?? null,

    // -- Cash / balance sheet --
    freeCashflow: financialData.freeCashflow ?? null,
    operatingCashflow: financialData.operatingCashflow ?? null,
    totalCash: financialData.totalCash ?? null,
    totalDebt: financialData.totalDebt ?? null,
    ebitda: financialData.ebitda ?? null,

    // -- Shares / sentiment --
    sharesOutstanding: defaultKeyStatistics.sharesOutstanding ?? null,
    beta: defaultKeyStatistics.beta ?? null,
    targetMeanPrice: financialData.targetMeanPrice ?? null,
    recommendationKey: financialData.recommendationKey ?? null,

    // -- Current price (as reported inside financialData, price-currency-denominated) --
    currentPrice: financialData.currentPrice ?? null,
  };
}

/**
 * THE DUAL-CURRENCY CAPTURE — see file header point 2.
 *
 * `price.currency` (== `quote.currency` == `summaryDetail.currency`, all
 * three verified identical, see references/04-global-data.md) is the TRADING currency the shares
 * are quoted in. `financialData.financialCurrency` is the REPORTING
 * currency the underlying financial statements use. These are separate
 * concepts that happen to coincide most of the time but were observed to
 * differ for ~24% of tested global names (dual-currency-reporting
 * multinationals, ADR-heavy resource companies). Every valuation ratio
 * that divides a price-based number by a financials-based number (e.g.
 * price/sales, EV/EBITDA when EV is computed from market cap) is INVALID
 * as a raw number when these differ, unless one side is FX-converted to
 * match the other first — this script does not attempt that conversion,
 * it only flags the mismatch loudly so a consumer cannot miss it.
 */
function extractCurrencyInfo(qs) {
  const priceCurrency = qs.price?.currency ?? null;
  const financialCurrency = qs.financialData?.financialCurrency ?? null;
  const currency_mismatch = Boolean(
    priceCurrency && financialCurrency && priceCurrency !== financialCurrency
  );
  return { price_currency: priceCurrency, financial_currency: financialCurrency, currency_mismatch };
}

async function fetchOneSymbol(yf, symbol) {
  const cached = readCache(symbol);
  if (cached) return cached;

  // Batch-level backoff/retry (in main()) handles rate-limiting; this is a
  // single attempt so its outcome can be classified cleanly by the caller.
  let qs;
  try {
    qs = await yf.quoteSummary(symbol, { modules: ALL_MODULES });
  } catch (err) {
    const { rateLimited, message } = classifyAndDescribeFundamentalsError(symbol, err);
    const wrapped = new Error(message);
    wrapped.rateLimited = rateLimited;
    throw wrapped;
  }

  if (!qs) {
    throw new Error(`quoteSummary() failed for "${symbol}": unknown error (resolved to no data). `);
  }

  // Core-module coverage: these four are verified 100% across the tested
  // sample, so any absence here is unexpected and must be surfaced, not
  // quietly treated as normal.
  const modulesPopulated = [];
  const modulesEmpty = [];
  for (const mod of CORE_MODULES) {
    if (qs[mod] && Object.keys(qs[mod]).length > 0) modulesPopulated.push(mod);
    else modulesEmpty.push(mod);
  }

  const coreOk = CORE_MODULES.every((m) => modulesPopulated.includes(m));
  if (!coreOk) {
    // A core module verified at 100% coverage came back missing for this
    // symbol — this is exactly the class of surprise the source document
    // says must never be silently defaulted. Fail loudly rather than
    // return a half-populated record dressed up as success.
    throw new Error(
      `quoteSummary() for "${symbol}" is missing core module(s) [${modulesEmpty.join(', ')}] ` +
      'that references/04-global-data.md verified at 100% coverage for 21 real symbols. ' +
      'This symbol may be invalid, delisted, or Yahoo coverage has genuinely regressed — ' +
      'do not guess; drop this candidate or re-verify manually.'
    );
  }

  // Statement history: opportunistic, verified-unreliable (point 3).
  // Each can be legitimately UNKNOWN without that being an error.
  const incomeCheck = checkStatementHistoryModule(qs.incomeStatementHistory, 'incomeStatementHistory');
  const balanceCheck = checkStatementHistoryModule(qs.balanceSheetHistory, 'balanceSheetHistory');
  const cashflowCheck = checkStatementHistoryModule(qs.cashflowStatementHistory, 'cashflowStatementHistory');

  for (const [name, check] of [
    ['incomeStatementHistory', incomeCheck],
    ['balanceSheetHistory', balanceCheck],
    ['cashflowStatementHistory', cashflowCheck],
  ]) {
    if (check.populated) modulesPopulated.push(name);
    else modulesEmpty.push(name); // Empty-without-error, or absent — either way, UNKNOWN.
  }

  const currencyInfo = extractCurrencyInfo(qs);
  const coreMetrics = extractCoreMetrics(qs);

  const record = {
    symbol,
    ...coreMetrics,
    price_currency: currencyInfo.price_currency,
    financial_currency: currencyInfo.financial_currency,
    currency_mismatch: currencyInfo.currency_mismatch,
    statement_history: {
      incomeStatementHistory: incomeCheck.populated ? incomeCheck.entries : 'UNKNOWN',
      balanceSheetHistory: balanceCheck.populated ? balanceCheck.entries : 'UNKNOWN',
      cashflowStatementHistory: cashflowCheck.populated ? cashflowCheck.entries : 'UNKNOWN',
    },
    coverage: {
      modules_populated: modulesPopulated,
      modules_empty: modulesEmpty, // Includes core-missing (would have already thrown) and empty statement-history.
    },
    as_of: new Date().toISOString(),
  };

  writeCache(symbol, record);
  return record;
}

function parseArgs(argv) {
  const symbols = [];
  let batchSize = DEFAULT_BATCH_SIZE;
  let delayMs = DEFAULT_DELAY_MS;
  const parseIntOpt = (name, raw) => {
    const val = Number(raw);
    if (!Number.isInteger(val) || val < 0) {
      console.error(`FATAL: ${name} requires a non-negative integer, got "${raw}"`);
      process.exit(1);
    }
    return val;
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (arg === '--batch-size') {
      batchSize = parseIntOpt('--batch-size', argv[i + 1]);
      if (batchSize === 0) {
        console.error('FATAL: --batch-size requires a positive integer, got "0"');
        process.exit(1);
      }
      i++;
    } else if (arg.startsWith('--batch-size=')) {
      batchSize = parseIntOpt('--batch-size', arg.split('=')[1]);
      if (batchSize === 0) {
        console.error('FATAL: --batch-size requires a positive integer, got "0"');
        process.exit(1);
      }
    } else if (arg === '--delay-ms') {
      delayMs = parseIntOpt('--delay-ms', argv[i + 1]);
      i++;
    } else if (arg.startsWith('--delay-ms=')) {
      delayMs = parseIntOpt('--delay-ms', arg.split('=')[1]);
    } else if (arg.startsWith('--')) {
      console.error(`FATAL: unrecognized option "${arg}"`);
      process.exit(1);
    } else {
      symbols.push(arg);
    }
  }
  return { symbols, batchSize, delayMs };
}

/**
 * Offline assertions for rate-limit detection and error-classification —
 * no network, no cache dir. Run via `node fetch-global-fundamentals.js --self-test`.
 */
function runSelfTest() {
  const checks = [];
  const check = (name, actual, expected) => checks.push({ name, pass: actual === expected, actual, expected });

  check(
    'detects reported set-cookie/crumb signature',
    isRateLimitError(new Error("No set-cookie header present in Yahoo's response.  Something must have changed, please report.")),
    true
  );
  check(
    'detects consent-flow set-cookie variant',
    isRateLimitError(new Error('No set-cookie header on copyConsentResponse, please report.')),
    true
  );
  const httpErr = new Error('Too Many Requests');
  httpErr.code = 429;
  check('detects HTTPError with code 429', isRateLimitError(httpErr), true);
  check(
    'detects "429" inside a message',
    isRateLimitError(new Error('Failed to get crumb, status 429, statusText: Too Many Requests')),
    true
  );
  check(
    'does NOT flag a genuine missing-coverage error',
    isRateLimitError(new Error('quoteSummary() for "XYZ" is missing core module(s) [price] that references/04-global-data.md verified at 100% coverage')),
    false
  );
  check(
    'does NOT flag a generic network error',
    isRateLimitError(new Error('getaddrinfo ENOTFOUND query1.finance.yahoo.com')),
    false
  );
  check('does NOT flag a falsy/missing error', isRateLimitError(null), false);

  const rateLimitMsg = classifyAndDescribeFundamentalsError(
    'MMM',
    new Error("No set-cookie header present in Yahoo's response.  Something must have changed, please report.")
  );
  check('rate-limit classification sets rateLimited=true', rateLimitMsg.rateLimited, true);
  check('rate-limit message does NOT suggest checking exchange suffix', /exchange suffix/i.test(rateLimitMsg.message), false);
  check('rate-limit message tells operator to adjust batch-size/delay-ms', /--batch-size/.test(rateLimitMsg.message) && /--delay-ms/.test(rateLimitMsg.message), true);

  const badSymbolMsg = classifyAndDescribeFundamentalsError('ZZZINVALID', new Error('Unexpected result: {}'));
  check('bad-symbol classification sets rateLimited=false', badSymbolMsg.rateLimited, false);
  check('bad-symbol message DOES suggest checking exchange suffix', /exchange suffix/i.test(badSymbolMsg.message), true);

  let failed = 0;
  for (const c of checks) {
    if (!c.pass) failed++;
    console.error(`[self-test] ${c.pass ? 'PASS' : 'FAIL'} - ${c.name}${c.pass ? '' : ` (expected ${c.expected}, got ${c.actual})`}`);
  }
  console.error(`[self-test] ${checks.length - failed}/${checks.length} passed`);
  process.exit(failed > 0 ? 1 : 0);
}

async function main() {
  if (process.argv.slice(2).includes('--self-test')) {
    runSelfTest();
    return;
  }

  const { symbols, batchSize, delayMs } = parseArgs(process.argv.slice(2));
  if (symbols.length === 0) {
    console.error(
      'Usage: fetch-global-fundamentals.js SYMBOL [SYMBOL...] [--batch-size N] [--delay-ms N]\n' +
      'Example: fetch-global-fundamentals.js ASML.AS SHEL.L 0700.HK\n' +
      `Defaults: --batch-size ${DEFAULT_BATCH_SIZE} --delay-ms ${DEFAULT_DELAY_MS}\n` +
      'Screening a full universe (hundreds of symbols)? Keep batch-size small and delay-ms ' +
      'generous — Yahoo throttles by withholding a cookie, not by returning a clean 429.'
    );
    process.exit(1);
  }

  ensureCacheDir();
  const yf = await loadYf();

  const results = [];
  const failures = [];

  for (let i = 0; i < symbols.length; i += batchSize) {
    const batch = symbols.slice(i, i + batchSize);
    const batchIndex = Math.floor(i / batchSize) + 1;
    const totalBatches = Math.ceil(symbols.length / batchSize);

    let pending = batch;
    for (let backoffAttempt = 0; pending.length > 0; backoffAttempt++) {
      // Promise.allSettled: one bad symbol must never kill the batch.
      const settled = await Promise.allSettled(pending.map((s) => fetchOneSymbol(yf, s)));
      const retryable = [];
      settled.forEach((outcome, idx) => {
        const symbol = pending[idx];
        if (outcome.status === 'fulfilled') {
          results.push(outcome.value);
          return;
        }
        const err = outcome.reason;
        const rateLimited = err?.rateLimited === true || isRateLimitError(err);
        if (rateLimited && backoffAttempt < MAX_BACKOFF_RETRIES) {
          retryable.push(symbol);
        } else {
          failures.push({
            symbol,
            error: err?.message || String(err),
            error_type: rateLimited ? 'rate_limit' : 'other',
          });
        }
      });
      if (retryable.length === 0) break;
      const waitMs = BACKOFF_SCHEDULE_MS[backoffAttempt];
      console.error(
        `[rate-limit] batch ${batchIndex}/${totalBatches}: Yahoo throttled ${retryable.length}/${batch.length} ` +
        `symbol(s) (${retryable.join(', ')}). Backing off ${waitMs / 1000}s ` +
        `before retry ${backoffAttempt + 1}/${MAX_BACKOFF_RETRIES}...`
      );
      await sleep(waitMs);
      pending = retryable;
    }

    if (i + batchSize < symbols.length) await sleep(delayMs);
  }

  const output = {
    as_of: new Date().toISOString(),
    requested: symbols.length,
    succeeded: results.length,
    failed: failures.length,
    results,
    failures, // Explicit, never silently dropped.
  };

  if (results.length === 0 && failures.length > 0) {
    const allRateLimited = failures.every((f) => f.error_type === 'rate_limit');
    if (allRateLimited) {
      output.rate_limited = true;
      output.error = 'Rate-limited by the data source (Yahoo Finance); no data retrieved. ' +
        'Reduce --batch-size and/or increase --delay-ms, then retry.';
      console.error(
        `FATAL: all ${failures.length} symbol(s) failed due to Yahoo Finance rate-limiting; no data retrieved. ` +
        'Reduce --batch-size and/or increase --delay-ms, then retry.'
      );
    }
    process.exitCode = 1;
  }

  process.stdout.write(JSON.stringify(output, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
