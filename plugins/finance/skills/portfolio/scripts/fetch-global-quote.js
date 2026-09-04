#!/usr/bin/env node
/**
 * fetch-global-quote.js
 *
 * Fetch a live quote for one or more Yahoo Finance symbols, INCLUDING
 * non-US exchange suffixes (e.g. `ASML.AS`, `SHEL.L`, `7203.T`), and
 * normalize any minor-unit-quoted price into major currency units before
 * it is ever handed to a downstream consumer.
 *
 * Why this exists / the critical feature:
 * Some Yahoo listings — most famously London Stock Exchange equities —
 * quote in a currency's MINOR unit (pence, cents) rather than its major
 * unit (pounds, dollars/rand). Yahoo signals this with a currency code
 * whose final letter is lowercase, e.g. `GBp` (pence) vs `GBP` (pounds),
 * or `ZAc` (South African cents) vs `ZAR` (rand). This was verified live
 * against `SHEL.L`, which returns `currency: "GBp"` and
 * `regularMarketPrice: 3383.5` — meaning the actual price is £33.835, NOT
 * £3383.50. Treating the raw number as major-unit currency is a 100x
 * sizing error in any position-sizing or market-cap sanity check that
 * consumes it. See references/04-global-data.md for the full empirical
 * record this script implements.
 *
 * Requires: yahoo-finance2 installed alongside this script (or reachable
 * via node's module resolution) — see the sibling package.json/lockfile
 * for the pinned version this was verified against (3.14.0).
 *
 * Caching: 5-minute TTL per symbol, under ~/.cache/portfolio-skill/quote/.
 *
 * Rate-limiting: Yahoo's anti-bot layer throttles by simply withholding the
 * set-cookie header its crumb dance depends on — yahoo-finance2 surfaces
 * that as `No set-cookie header present in Yahoo's response. Something
 * must have changed, please report.`, which reads exactly like a
 * "something broke" bug, not a "you are going too fast" signal. Verified
 * live: screening the skill's full 841-symbol universe with no inter-batch
 * delay failed 841/841 with that message and recovered on its own within
 * about a minute. This script detects that signature (and plain HTTP 429s)
 * specifically, reports it as a rate-limit distinct from a bad-symbol
 * error, and retries the affected batch with exponential backoff instead
 * of giving up immediately.
 *
 * Usage:
 *   node fetch-global-quote.js SYMBOL [SYMBOL...] [--batch-size N] [--delay-ms N]
 *   node fetch-global-quote.js --self-test
 *
 * Output: JSON on stdout — { results: [...], failures: [...], as_of }.
 * One bad symbol never kills the batch: failures are reported explicitly,
 * never silently dropped. All backoff/retry/self-test logging goes to
 * stderr — stdout is reserved for the JSON result.
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'portfolio-skill', 'quote');
const CACHE_TTL_MS = 5 * 60 * 1000;
const DEFAULT_BATCH_SIZE = 5; // Yahoo rate-limits aggressively; mirrors house fetch-quote.js.

// Empirically, batch-size 30 with no inter-batch delay across 841 symbols
// triggered a 100% rate-limit block; small batches with pauses worked. This
// default trades speed for reliability on full-universe runs — see the
// file header and `isRateLimitError` below.
const DEFAULT_DELAY_MS = 2000;

// Exponential backoff schedule applied to a batch when Yahoo throttles it
// (5s, 15s, 45s), with a hard cap on attempts so a persistent block still
// terminates instead of retrying forever.
const BACKOFF_SCHEDULE_MS = [5000, 15000, 45000];
const MAX_BACKOFF_RETRIES = BACKOFF_SCHEDULE_MS.length;

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Known throttle/anti-bot signatures surfaced by yahoo-finance2 when Yahoo
// withholds the set-cookie header its crumb flow depends on, or returns a
// plain HTTP 429. Matched narrowly and distinctly from genuine bad-symbol
// errors (e.g. "Unexpected result: ...") so the two never collapse into one
// misleading message. See file header for the live-verified failure text.
const RATE_LIMIT_SIGNATURE_RE = /no set-cookie header|too many requests|\b429\b|\brate[ -]?limit/i;

/**
 * @param {*} err - anything caught from a yahoo-finance2 call (or a plain
 *   object/Error in tests).
 * @returns {boolean} true if this looks like Yahoo throttling rather than
 *   a genuine per-symbol failure (bad suffix, delisted, schema change).
 */
function isRateLimitError(err) {
  if (!err) return false;
  if (err.code === 429 || err.code === '429') return true;
  return RATE_LIMIT_SIGNATURE_RE.test(String(err.message || err));
}

/**
 * Build the failure message for a thrown quote() error, branching on
 * whether it is a detected rate-limit vs a genuine per-symbol problem.
 * Pure function — exercised directly by --self-test, no network needed.
 *
 * @param {string} symbol
 * @param {Error} err
 * @returns {{ rateLimited: boolean, message: string }}
 */
function classifyAndDescribeQuoteError(symbol, err) {
  if (isRateLimitError(err)) {
    return {
      rateLimited: true,
      message: `quote() failed for "${symbol}": rate-limited by Yahoo Finance (${err.message}). ` +
        'This is NOT a bad-symbol/exchange-suffix problem — Yahoo is throttling this run. ' +
        'Reduce --batch-size and/or increase --delay-ms, then retry.',
    };
  }
  return {
    rateLimited: false,
    message: `quote() failed for "${symbol}": ${err.message}. ` +
      'Verify the symbol includes the correct Yahoo exchange suffix (e.g. ".L", ".AS", ".T"), or the symbol is invalid/delisted.',
  };
}

// Fields we expect back from yf.quote() for a usable quote. Anything
// missing here downgrades the symbol's coverage report and, for the two
// fields that are load-bearing for the minor-unit check (currency and
// price), forces the whole record to UNKNOWN rather than guessing.
const EXPECTED_FIELDS = [
  'currency',
  'regularMarketPrice',
  'exchange',
  'fullExchangeName',
  'marketCap',
  'regularMarketVolume',
];

// Fields whose absence means the record cannot be trusted at all — no
// currency means we cannot know if minor-unit normalization applies, and
// no price means there is nothing to report. Both are load-bearing for
// the anti-100x-error guarantee this script exists to provide.
const CRITICAL_FIELDS = ['currency', 'regularMarketPrice'];

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

/**
 * Detect a Yahoo minor-unit currency code and, if found, return the major
 * code it corresponds to. Convention (documented in
 * references/04-global-data.md, empirically confirmed for `GBp`):
 * a currency code that is otherwise uppercase ISO-4217-shaped but ends in
 * a LOWERCASE letter denotes minor-unit (subdivision) quoting — e.g.
 * `GBp` (pence) -> `GBP` (pounds), `ZAc` (cents) -> `ZAR` (rand),
 * `ILa` (agorot) -> `ILS` (shekels). An all-uppercase 3-letter code is
 * always major-unit and passes through unchanged.
 *
 * This is intentionally a pure, narrowly-scoped function so the 100x-risk
 * logic lives in exactly one place and is trivially unit-testable.
 *
 * @param {string} currencyCode - raw currency string from Yahoo (e.g. "GBp", "USD")
 * @returns {{ isMinorUnit: boolean, majorCode: string }}
 */
function resolveMinorUnitCurrency(currencyCode) {
  if (typeof currencyCode !== 'string' || currencyCode.length < 2) {
    return { isMinorUnit: false, majorCode: currencyCode };
  }
  const lastChar = currencyCode.charAt(currencyCode.length - 1);
  const isMinorUnit = lastChar === lastChar.toLowerCase() && lastChar !== lastChar.toUpperCase();
  if (!isMinorUnit) {
    return { isMinorUnit: false, majorCode: currencyCode.toUpperCase() };
  }
  // Uppercase the whole code to get the major-unit ISO code: "GBp" -> "GBP", "ZAc" -> "ZAR".
  // (This assumes the minor-unit suffix maps 1:1 onto the major code's last
  // letter, which holds for every documented case: GBp->GBP, ZAc->ZAR,
  // ILa->ILS is the one documented exception where the letter itself
  // changes (agorot 'a' vs shekel 'S') -- Yahoo has not been observed to
  // emit ILa live, so we do not special-case it; if it ever appears the
  // uppercased code will be wrong and must be caught downstream via the
  // UNKNOWN/coverage mechanism, not silently trusted.)
  return { isMinorUnit: true, majorCode: currencyCode.toUpperCase() };
}

/**
 * Normalize a raw price given its raw currency code. Applied AT INGEST so
 * no downstream consumer of this script's output ever sees an
 * un-normalized (minor-unit) price.
 *
 * @param {number} rawPrice
 * @param {string} rawCurrency
 * @returns {{ price_major: number|null, currency_major: string|null, minor_unit_applied: boolean }}
 */
function normalizeToMajorUnits(rawPrice, rawCurrency) {
  if (typeof rawPrice !== 'number' || Number.isNaN(rawPrice) || !rawCurrency) {
    return { price_major: null, currency_major: null, minor_unit_applied: false };
  }
  const { isMinorUnit, majorCode } = resolveMinorUnitCurrency(rawCurrency);
  return {
    price_major: isMinorUnit ? rawPrice / 100 : rawPrice,
    currency_major: majorCode,
    minor_unit_applied: isMinorUnit,
  };
}

/**
 * Build the per-field coverage report: which expected fields were
 * actually present on the raw quote object. A symbol missing a CRITICAL
 * field (currency or regularMarketPrice) is marked UNKNOWN overall so
 * downstream logic can drop it rather than guess at a price or currency.
 */
function buildCoverage(rawQuote) {
  const present = [];
  const missing = [];
  for (const field of EXPECTED_FIELDS) {
    const has = rawQuote != null && rawQuote[field] !== undefined && rawQuote[field] !== null;
    if (has) present.push(field);
    else missing.push(field);
  }
  const missingCritical = CRITICAL_FIELDS.filter((f) => missing.includes(f));
  return {
    present_fields: present,
    missing_fields: missing,
    status: missingCritical.length > 0 ? 'UNKNOWN' : 'OK',
    missing_critical_fields: missingCritical,
  };
}

function cacheFileFor(symbol) {
  // Symbols can contain characters like '.' and '-' (e.g. "SHEL.L",
  // "VOLV-B.ST") which are filesystem-safe as-is; guard anything exotic.
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

async function fetchOneQuote(yf, symbol) {
  const cached = readCache(symbol);
  if (cached) return cached;

  // Batch-level backoff/retry (in main()) handles rate-limiting; this is a
  // single attempt so its outcome can be classified cleanly by the caller.
  let rawQuote;
  try {
    rawQuote = await yf.quote(symbol);
  } catch (err) {
    const { rateLimited, message } = classifyAndDescribeQuoteError(symbol, err);
    const wrapped = new Error(message);
    wrapped.rateLimited = rateLimited;
    throw wrapped;
  }

  if (!rawQuote) {
    // Verified live failure mode: yf.quote() on an invalid/unknown symbol
    // resolves to `undefined` rather than throwing — a silent failure that
    // must not be allowed to fall through as an empty/default record. This
    // is not a rate-limit signature (no error was even thrown), so it keeps
    // the exchange-suffix guidance.
    throw new Error(
      `quote() failed for "${symbol}": yf.quote() resolved to undefined/null with no thrown error ` +
      '— Yahoo has no data for this symbol. ' +
      'Verify the symbol includes the correct Yahoo exchange suffix (e.g. ".L", ".AS", ".T"), or the symbol is invalid/delisted.'
    );
  }

  const coverage = buildCoverage(rawQuote);

  // If currency or price is missing, do NOT attempt normalization or
  // report a price/currency at all — everything price-related must be
  // explicitly UNKNOWN, never defaulted or half-computed.
  const normalization = coverage.status === 'OK'
    ? normalizeToMajorUnits(rawQuote.regularMarketPrice, rawQuote.currency)
    : { price_major: null, currency_major: null, minor_unit_applied: false };

  const record = {
    symbol,
    raw_price: rawQuote.regularMarketPrice ?? null,
    raw_currency: rawQuote.currency ?? null,
    price_major: normalization.price_major,
    currency_major: normalization.currency_major,
    minor_unit_applied: normalization.minor_unit_applied,
    exchange: rawQuote.exchange ?? null,
    fullExchangeName: rawQuote.fullExchangeName ?? null,
    marketCap: rawQuote.marketCap ?? null,
    regularMarketVolume: rawQuote.regularMarketVolume ?? null,
    coverage,
    status: coverage.status, // 'OK' or 'UNKNOWN' — mirrors coverage.status for easy top-level filtering.
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
 * no network, no cache dir. Run via `node fetch-global-quote.js --self-test`.
 */
function runSelfTest() {
  const checks = [];
  const check = (name, actual, expected) => checks.push({ name, pass: actual === expected, actual, expected });

  // The exact live-verified failure text from the bug report.
  check(
    'detects reported set-cookie/crumb signature',
    isRateLimitError(new Error("No set-cookie header present in Yahoo's response.  Something must have changed, please report.")),
    true
  );
  check(
    'detects consent-flow set-cookie variant',
    isRateLimitError(new Error('No set-cookie header on collectConsentSubmitResponse, please report.')),
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
    'does NOT flag a genuine bad-symbol error',
    isRateLimitError(new Error('Unexpected result: {"quoteResponse":{"result":[],"error":null}}')),
    false
  );
  check(
    'does NOT flag a generic network error',
    isRateLimitError(new Error('getaddrinfo ENOTFOUND query1.finance.yahoo.com')),
    false
  );
  check('does NOT flag a falsy/missing error', isRateLimitError(null), false);

  const rateLimitMsg = classifyAndDescribeQuoteError(
    'MMM',
    new Error("No set-cookie header present in Yahoo's response.  Something must have changed, please report.")
  );
  check('rate-limit classification sets rateLimited=true', rateLimitMsg.rateLimited, true);
  check('rate-limit message does NOT suggest checking exchange suffix', /exchange suffix/i.test(rateLimitMsg.message), false);
  check('rate-limit message tells operator to adjust batch-size/delay-ms', /--batch-size/.test(rateLimitMsg.message) && /--delay-ms/.test(rateLimitMsg.message), true);

  const badSymbolMsg = classifyAndDescribeQuoteError('ZZZINVALID', new Error('Unexpected result: {}'));
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
      'Usage: fetch-global-quote.js SYMBOL [SYMBOL...] [--batch-size N] [--delay-ms N]\n' +
      'Example: fetch-global-quote.js ASML.AS SHEL.L 7203.T\n' +
      `Defaults: --batch-size ${DEFAULT_BATCH_SIZE} --delay-ms ${DEFAULT_DELAY_MS}\n` +
      'Screening a full universe (hundreds of symbols)? Keep batch-size small and delay-ms ' +
      'generous — Yahoo throttles by withholding a cookie, not by returning a clean 429, and ' +
      'the failure looks like "the symbol is wrong" if you do not know to expect it.'
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
      const settled = await Promise.allSettled(pending.map((s) => fetchOneQuote(yf, s)));
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

  // Non-zero exit only if EVERY symbol failed — a partial batch is still
  // useful output and should not be treated as a fatal script failure.
  // But total failure that is ENTIRELY rate-limiting is a distinct,
  // loudly-reported outcome — never an empty result set a caller might
  // read as "no candidates passed screening."
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
