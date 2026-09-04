#!/usr/bin/env node
/**
 * fetch-universe.js
 *
 * Assemble the GLOBAL large/mid-cap candidate universe for BUILD Stage 1
 * (`execution-prompt-build.md` Stage 1 says "assemble the candidate
 * universe" but historically had no script backing that instruction — a
 * live run had to supply candidates from the operator's recall, which is
 * an unmeasured selection bias upstream of every downstream decision).
 * This script is the fix: a deterministic, source-named, sanity-checked
 * scrape, mirroring the house pattern in
 * `investment/scripts/fetch-universe.js` (Wikipedia constituent tables,
 * 7-day cache, fail-loud) but emitting symbols in the Yahoo-suffix form
 * `fetch-global-quote.js` / `fetch-global-fundamentals.js` actually
 * consume, resolved through `data/exchange-currency-map.json`.
 *
 * WHAT THIS COVERS
 *   - US:      S&P 500 (Wikipedia constituent table)
 *   - Europe:  FTSE 100 (UK), DAX (Germany), CAC 40 (France),
 *              AEX (Netherlands), IBEX 35 (Spain), SMI (Switzerland),
 *              OMX Stockholm 30 (Sweden), OMX Copenhagen 25 (Denmark),
 *              OBX Index (Norway)
 *
 * WHAT THIS DOES NOT COVER — read before treating this as "the" universe
 *   - APAC is DELIBERATELY EXCLUDED. The skill's own research
 *     (`references/08-multi-currency.md`) established that Japanese
 *     ("round lot") and Hong Kong ("board lot") local lines carry
 *     non-1, per-security lot constraints that make them impractical to
 *     size freely at small account sizes, and no reliable public source
 *     for the exact per-security lot unit is wired up here. Rather than
 *     silently include APAC names as if they were freely sizable, this
 *     script omits them outright. A future reader wanting APAC coverage
 *     must add it with lot-size data attached, not just a suffix.
 *   - Other European markets are NOT covered: Ireland (.IR), Italy (.MI),
 *     Finland (.HE), Portugal, Austria, Belgium, Poland, and others all
 *     have entries in `data/exchange-currency-map.json` (so
 *     `fetch-global-quote.js` can quote a name on those exchanges) but
 *     this script has no constituent-list source wired up for them.
 *   - Small caps are NOT covered anywhere — every source here is a
 *     large/mid-cap benchmark index.
 *   - Canada (.TO), Australia (.AX), and the rest of `exchange-currency-
 *     map.json`'s coverage are likewise not sourced here — the map can
 *     resolve a symbol you already have, it does not imply this script
 *     enumerates every market the map knows about.
 *   Treat the `regions_covered` / `regions_not_covered` fields in this
 *   script's own output as the authoritative, current statement of scope
 *   — this header can drift, that field cannot (it is generated from the
 *   same SOURCES list that does the fetching).
 *
 * SUFFIX RESOLUTION
 *   Wikipedia gives local tickers. Some source tables (DAX, CAC 40, AEX,
 *   IBEX 35, OMX Stockholm 30) already publish a Yahoo-suffixed ticker
 *   column (e.g. "ADS.DE", "MT.AS") verified live in the build-time
 *   research for this script and used as-is. Others (S&P 500, FTSE 100,
 *   SMI, OMX Copenhagen 25, OBX) publish a bare local ticker and this
 *   script appends the suffix itself (share-class separators normalized
 *   to Yahoo's hyphen convention, e.g. Wikipedia's "BT.A" -> "BT-A.L",
 *   "AMBU B" -> "AMBU-B.CO"). Every emitted suffix is looked up in
 *   `data/exchange-currency-map.json`; a suffix this script would emit
 *   that is NOT a key in that file is a hard self-test failure (see
 *   `--self-test`), not a silent pass-through.
 *
 * VALIDATION — "turning local tickers into Yahoo symbols is the whole
 * value of this script," so it is verified two ways, both reported, never
 * silently trusted:
 *   1. Structural (always, offline): every emitted symbol's suffix must
 *      be a key in `data/exchange-currency-map.json`.
 *   2. Live sample (default on, skip with --skip-live-validation): a
 *      small per-source sample is actually queried via `yahoo-finance2`
 *      (same dependency `fetch-global-quote.js` uses) to confirm Yahoo
 *      resolves it. This is what catches a source-table quirk no
 *      structural check can — e.g. a constituent table publishing a
 *      ticker that LOOKS like a valid `.SW`/`.CO`/etc. symbol but that
 *      Yahoo does not actually recognize.
 *
 * FAIL LOUD — each source has a sanity floor (~80% of its nominal
 * constituent count). A source that returns zero, or implausibly few,
 * constituents is reported as an ERROR naming that source — never
 * silently folded into a shorter-than-it-looks universe. A source in
 * ERROR contributes NO entries to the output, and the run's cache is not
 * written (a bad partial must not calcify into a week of bad partials).
 * `process.exitCode` is set non-zero whenever any source errored.
 *
 * Caching: 7-day TTL at ~/.cache/portfolio-skill/universe.json (full,
 * unfiltered universe — `--region` filters the OUTPUT, not what's cached,
 * so switching `--region` never forces a re-fetch within the TTL).
 *
 * Usage:
 *   node fetch-universe.js [--refresh] [--region=us,eu] [--skip-live-validation]
 *   node fetch-universe.js --self-test
 *
 * Output: JSON on stdout — { as_of, regions_covered, regions_not_covered,
 * sources: [...], entries: [...], validation: {...}, warnings: [...] }.
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import https from 'node:https';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'portfolio-skill');
const CACHE_FILE = path.join(CACHE_DIR, 'universe.json');
const CACHE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

const MAP_FILE = new URL('../data/exchange-currency-map.json', import.meta.url);

// Derived suffix -> ISO country code, for the required `country` field.
// `data/exchange-currency-map.json` maps suffix -> exchange/currency, not
// country, so this small table is this script's own addition — derived
// from each suffix's `exchange_name` in that file, not an independent
// source of truth. Only suffixes this script actually emits need entries.
const SUFFIX_COUNTRY = {
  '': 'US',
  '.L': 'GB',
  '.DE': 'DE',
  '.PA': 'FR',
  '.AS': 'NL',
  '.MC': 'ES',
  '.SW': 'CH',
  '.ST': 'SE',
  '.OL': 'NO',
  '.CO': 'DK',
};

// ---------------------------------------------------------------------------------------------
// Ticker transforms — turn a raw Wikipedia cell into a Yahoo-suffixed symbol.
// ---------------------------------------------------------------------------------------------

// Yahoo's share-class convention is a hyphen ("BRK-B", "BT-A.L"), not the
// dot/space various local conventions use ("BRK.B", "BT.A", "AMBU B").
function normalizeLocalTicker(raw) {
  return raw
    .trim()
    .replace(/\s+/g, '-')
    .replace(/\./g, '-')
    .toUpperCase();
}

// Append a suffix to a bare local ticker already normalized to Yahoo's
// hyphen convention.
function appendSuffix(rawTicker, suffix) {
  return normalizeLocalTicker(rawTicker) + suffix;
}

// OBX's Wikipedia column prefixes the ticker with its exchange, e.g.
// "OSE: EQNR" — strip the prefix before normalizing.
function stripExchangePrefix(raw) {
  return raw.replace(/^[A-Z]+:\s*/, '');
}

// ---------------------------------------------------------------------------------------------
// Source configuration
// ---------------------------------------------------------------------------------------------
// tickerMode:
//   'already-suffixed' — the Wikipedia ticker column IS a Yahoo symbol
//     already (verified live for DAX/CAC40/AEX/IBEX35/OMXS30 at build
//     time); used as-is.
//   'append-suffix'    — the column is a bare local ticker; this script
//     normalizes it and appends `suffix`.
// sanityFloor is ~80% of the nominal constituent count observed live at
// build time — enough slack for ordinary index reconstitution churn,
// tight enough that a broken parse (wrong table index, changed class
// names, near-empty table) cannot pass as "just a smaller universe."

const SOURCES = [
  {
    name: 'S&P 500',
    region: 'us',
    url: 'https://en.wikipedia.org/wiki/List_of_S%26P_500_companies',
    tableIndex: 0,
    minCells: 3,
    sanityFloor: 480,
    tickerMode: 'append-suffix',
    suffix: '',
    tickerCol: 0,
    nameCol: 1,
  },
  {
    name: 'FTSE 100',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/FTSE_100_Index',
    tableIndex: 3,
    minCells: 3,
    sanityFloor: 80,
    tickerMode: 'append-suffix',
    suffix: '.L',
    tickerCol: 1,
    nameCol: 0,
  },
  {
    name: 'DAX',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/DAX',
    tableIndex: 3,
    minCells: 4,
    sanityFloor: 32,
    tickerMode: 'already-suffixed',
    tickerCol: 0,
    nameCol: 2,
  },
  {
    name: 'CAC 40',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/CAC_40',
    tableIndex: 3,
    minCells: 4,
    sanityFloor: 32,
    tickerMode: 'already-suffixed',
    tickerCol: 3,
    nameCol: 0,
  },
  {
    name: 'AEX',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/AEX_index',
    tableIndex: 2,
    minCells: 3,
    sanityFloor: 20,
    tickerMode: 'already-suffixed',
    tickerCol: 0,
    nameCol: 1,
  },
  {
    name: 'IBEX 35',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/IBEX_35',
    tableIndex: 1,
    minCells: 3,
    sanityFloor: 28,
    tickerMode: 'already-suffixed',
    tickerCol: 0,
    nameCol: 1,
  },
  {
    name: 'SMI',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/Swiss_Market_Index',
    tableIndex: 0,
    minCells: 4,
    sanityFloor: 16,
    tickerMode: 'append-suffix',
    suffix: '.SW',
    tickerCol: 3,
    nameCol: 1,
  },
  {
    name: 'OMX Stockholm 30',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/OMX_Stockholm_30',
    tableIndex: 0,
    minCells: 3,
    sanityFloor: 24,
    tickerMode: 'already-suffixed',
    tickerCol: 0,
    nameCol: 1,
  },
  {
    name: 'OMX Copenhagen 25',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/OMX_Copenhagen_25',
    tableIndex: 0,
    minCells: 3,
    sanityFloor: 20,
    tickerMode: 'append-suffix',
    suffix: '.CO',
    tickerCol: 2,
    nameCol: 0,
  },
  {
    name: 'OBX Index',
    region: 'eu',
    url: 'https://en.wikipedia.org/wiki/OBX_Index',
    tableIndex: 0,
    minCells: 3,
    sanityFloor: 20,
    tickerMode: 'append-suffix',
    suffix: '.OL',
    tickerCol: 2,
    nameCol: 0,
    preTransform: stripExchangePrefix,
  },
];

const REGIONS_NOT_COVERED = [
  'APAC (Japan .T, Hong Kong .HK, and all other Asia-Pacific listings) — ' +
    'excluded because per-security round-lot/board-lot constraints make ' +
    'freely-sized positions impractical at small account sizes and no ' +
    'lot-size source is wired up here; see the file header before adding.',
  'European markets outside the 9 indices sourced here — Ireland (.IR), ' +
    'Italy (.MI), Finland (.HE), Portugal, Austria, Belgium, Poland, etc. ' +
    '`data/exchange-currency-map.json` can still resolve a symbol on one ' +
    'of these once you have it; this script just does not enumerate them.',
  'Canada (.TO), Australia (.AX), and any other exchange-currency-map.json ' +
    'entry not listed in regions_covered.',
  'Small/micro caps in any region — every source here is a large/mid-cap benchmark index.',
];

// ---------------------------------------------------------------------------------------------
// Fetch + parse
// ---------------------------------------------------------------------------------------------

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

function fetchHtml(url) {
  return new Promise((resolve, reject) => {
    const opts = {
      headers: { 'User-Agent': 'Mozilla/5.0 (portfolio-skill; tomas@p5.is)' },
    };
    https
      .get(url, opts, (res) => {
        if (res.statusCode !== 200) {
          reject(new Error(`HTTP ${res.statusCode} for ${url}`));
          return;
        }
        let body = '';
        res.on('data', (chunk) => { body += chunk; });
        res.on('end', () => resolve(body));
      })
      .on('error', reject);
  });
}

const stripTags = (s) =>
  s
    .replace(/<[^>]*>/g, '')
    .replace(/&amp;/g, '&')
    .replace(/&nbsp;/g, ' ')
    .replace(/&#?\w+;/g, '')
    .trim();

function parseWikitable(html, tableIndex, minCells) {
  const tableMatches = [...html.matchAll(/<table[^>]*class="[^"]*wikitable[^"]*"[^>]*>([\s\S]*?)<\/table>/g)];
  if (tableMatches.length <= tableIndex) {
    throw new Error(`table index ${tableIndex} not found (page has ${tableMatches.length} wikitables — HTML structure likely changed)`);
  }
  const tableHtml = tableMatches[tableIndex][1];
  const rows = [...tableHtml.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/g)];
  const data = [];
  for (let i = 1; i < rows.length; i++) {
    // skip header row
    const cells = [...rows[i][1].matchAll(/<t[hd][^>]*>([\s\S]*?)<\/t[hd]>/g)].map((m) => stripTags(m[1]));
    if (cells.length < minCells) continue;
    data.push(cells);
  }
  return data;
}

function rowToEntry(cells, source) {
  let rawTicker = (cells[source.tickerCol] || '').trim();
  const name = (cells[source.nameCol] || '').trim();
  if (!rawTicker || !name) return null;
  if (source.preTransform) rawTicker = source.preTransform(rawTicker);
  if (!rawTicker) return null;

  const symbol =
    source.tickerMode === 'already-suffixed'
      ? rawTicker.trim().toUpperCase()
      : appendSuffix(rawTicker, source.suffix);

  return { symbol, name, source_index: source.name, region: source.region };
}

async function fetchSource(source) {
  const html = await fetchHtml(source.url);
  const rows = parseWikitable(html, source.tableIndex, source.minCells);
  const entries = rows.map((r) => rowToEntry(r, source)).filter(Boolean);
  return entries;
}

// ---------------------------------------------------------------------------------------------
// Exchange-currency-map resolution
// ---------------------------------------------------------------------------------------------

function loadMap() {
  const raw = fs.readFileSync(MAP_FILE, 'utf8');
  return JSON.parse(raw).markets;
}

function suffixOf(symbol) {
  const dot = symbol.lastIndexOf('.');
  // A bare US symbol ("AAPL") has no dot at all -> suffix "".
  // A suffixed symbol's suffix is everything from the LAST dot onward
  // (share-class hyphens like "BT-A.L" never contain a dot themselves,
  // since normalizeLocalTicker() replaced dots with hyphens up front).
  return dot === -1 ? '' : symbol.slice(dot);
}

// Extract the leading ISO-4217-shaped currency code from a map entry's
// (sometimes prose) `trading_currency` field, and uppercase it to the
// MAJOR-unit code — mirrors fetch-global-quote.js's own minor-unit
// convention (GBp -> GBP) so this script's `currency` field always means
// "major-unit ISO code," never a possibly-minor-unit raw Yahoo string.
function majorCurrencyOf(mapEntry) {
  const m = /^[A-Za-z]{3}/.exec(mapEntry.trading_currency || '');
  return m ? m[0].toUpperCase() : null;
}

// Resolve one entry's exchange/country/currency via the map. Returns
// { resolved: true, exchange, country, currency } or
// { resolved: false, reason }. NEVER guesses a fill value.
function resolveViaMap(entry, map) {
  const suffix = suffixOf(entry.symbol);
  const mapEntry = map[suffix];
  if (!mapEntry) {
    return { resolved: false, reason: `suffix "${suffix}" (from ${entry.symbol}) is not a key in exchange-currency-map.json` };
  }
  const country = SUFFIX_COUNTRY[suffix];
  if (!country) {
    return { resolved: false, reason: `suffix "${suffix}" is in the map but has no SUFFIX_COUNTRY entry in this script` };
  }
  const currency = majorCurrencyOf(mapEntry);
  if (!currency) {
    return { resolved: false, reason: `could not extract a currency code from map entry for suffix "${suffix}"` };
  }
  return { resolved: true, exchange: mapEntry.exchange_name, country, currency };
}

// ---------------------------------------------------------------------------------------------
// Live sample validation
// ---------------------------------------------------------------------------------------------

const SAMPLE_PER_SOURCE = 2;

async function loadYf() {
  const mod = await import('yahoo-finance2');
  const YahooFinance = mod.default;
  return typeof YahooFinance === 'function'
    ? new YahooFinance({ suppressNotices: ['yahooSurvey', 'ripHistorical'] })
    : YahooFinance;
}

async function validateLiveSample(entriesBySource) {
  let yf;
  try {
    yf = await loadYf();
  } catch (err) {
    return {
      ran: false,
      reason: `yahoo-finance2 not importable: ${err.message}. Run \`npm install\` in the skill directory.`,
      checked: [],
      failures: [],
    };
  }

  const sample = [];
  for (const [sourceName, entries] of Object.entries(entriesBySource)) {
    for (const e of entries.slice(0, SAMPLE_PER_SOURCE)) sample.push({ ...e, source_index: sourceName });
  }

  const checked = [];
  const failures = [];
  for (const item of sample) {
    try {
      const q = await yf.quote(item.symbol);
      if (!q || (q.regularMarketPrice === undefined && q.regularMarketPrice !== 0)) {
        failures.push({ symbol: item.symbol, source_index: item.source_index, reason: 'quote() resolved with no regularMarketPrice' });
      } else {
        checked.push(item.symbol);
      }
    } catch (err) {
      failures.push({ symbol: item.symbol, source_index: item.source_index, reason: err.message });
    }
    // Gentle pacing — Yahoo rate-limits aggressively (house convention, see fetch-global-quote.js).
    await new Promise((r) => setTimeout(r, 150));
  }

  return { ran: true, checked, failures };
}

// ---------------------------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = { refresh: false, regions: null, skipLiveValidation: false, selfTest: false };
  for (const arg of argv) {
    if (arg === '--refresh') opts.refresh = true;
    else if (arg === '--skip-live-validation') opts.skipLiveValidation = true;
    else if (arg === '--self-test') opts.selfTest = true;
    else if (arg.startsWith('--region=')) {
      opts.regions = arg
        .slice('--region='.length)
        .split(',')
        .map((r) => r.trim().toLowerCase())
        .filter(Boolean);
    } else {
      console.error(`FATAL: unrecognized option "${arg}"`);
      process.exit(1);
    }
  }
  return opts;
}

function readCache() {
  if (!fs.existsSync(CACHE_FILE)) return null;
  const stat = fs.statSync(CACHE_FILE);
  if (Date.now() - stat.mtimeMs >= CACHE_TTL_MS) return null;
  try {
    return JSON.parse(fs.readFileSync(CACHE_FILE, 'utf8'));
  } catch {
    return null; // corrupt cache -> treat as miss
  }
}

function applyRegionFilter(fullResult, regions) {
  if (!regions || regions.length === 0) return fullResult;
  const filteredEntries = fullResult.entries.filter((e) => regions.includes(e.region));
  const filteredSources = fullResult.sources.filter((s) => regions.includes(s.region));
  return { ...fullResult, entries: filteredEntries, sources: filteredSources, region_filter: regions };
}

async function buildUniverse(map) {
  const sourceReports = [];
  const entriesBySource = {};
  const warnings = [];

  for (const source of SOURCES) {
    try {
      const entries = await fetchSource(source);
      const count = entries.length;
      const status = count >= source.sanityFloor ? 'OK' : 'ERROR';
      if (status === 'ERROR') {
        warnings.push(
          `ERROR: ${source.name} returned ${count} constituents, below its sanity floor of ${source.sanityFloor} ` +
            `(nominal ~${Math.round(source.sanityFloor / 0.8)}). Source's HTML structure likely changed. ` +
            'Excluded from this universe — not silently folded in as a shorter list.',
        );
        console.error(`ERROR: ${source.name} — ${count} < floor ${source.sanityFloor}`);
      } else {
        console.error(`OK: ${source.name} — ${count} constituents`);
      }
      sourceReports.push({ name: source.name, region: source.region, url: source.url, count, sanity_floor: source.sanityFloor, status });
      entriesBySource[source.name] = status === 'OK' ? entries : [];
    } catch (err) {
      warnings.push(`ERROR: ${source.name} failed to fetch/parse: ${err.message}`);
      console.error(`ERROR: ${source.name} — ${err.message}`);
      sourceReports.push({ name: source.name, region: source.region, url: source.url, count: 0, sanity_floor: source.sanityFloor, status: 'ERROR', error: err.message });
      entriesBySource[source.name] = [];
    }
  }

  // Resolve every surviving entry via the exchange-currency-map, dedupe by symbol.
  const seen = new Set();
  const entries = [];
  const unresolved = [];
  for (const [sourceName, list] of Object.entries(entriesBySource)) {
    for (const raw of list) {
      if (seen.has(raw.symbol)) continue;
      seen.add(raw.symbol);
      const resolution = resolveViaMap(raw, map);
      if (!resolution.resolved) {
        unresolved.push({ symbol: raw.symbol, source_index: sourceName, reason: resolution.reason });
        continue;
      }
      entries.push({
        symbol: raw.symbol,
        name: raw.name,
        exchange: resolution.exchange,
        country: resolution.country,
        currency: resolution.currency,
        source_index: sourceName,
        region: raw.region,
      });
    }
  }
  if (unresolved.length > 0) {
    warnings.push(`${unresolved.length} candidate symbol(s) did not resolve against exchange-currency-map.json — see structural_failures.`);
  }

  return { sourceReports, entriesBySource, entries, unresolved, warnings };
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.selfTest) {
    process.exit(runSelfTests() ? 0 : 1);
  }

  ensureCacheDir();
  const map = loadMap();

  let result;
  let fromCache = false;

  if (!opts.refresh) {
    const cached = readCache();
    if (cached) {
      result = cached;
      fromCache = true;
      for (const s of cached.sources) console.error(`(cache) ${s.status}: ${s.name} — ${s.count} constituents`);
    }
  }

  if (!result) {
    const built = await buildUniverse(map);

    let validation = { ran: false, reason: 'skipped (--skip-live-validation)', checked: [], failures: [] };
    if (!opts.skipLiveValidation) {
      const okEntriesBySource = {};
      for (const [name, list] of Object.entries(built.entriesBySource)) {
        if (list.length > 0) okEntriesBySource[name] = list;
      }
      validation = await validateLiveSample(okEntriesBySource);
      if (validation.ran && validation.failures.length > 0) {
        for (const f of validation.failures) {
          console.error(`VALIDATION FAIL: ${f.symbol} (${f.source_index}) — ${f.reason}`);
          built.warnings.push(`Live validation: ${f.symbol} (${f.source_index}) did not resolve — ${f.reason}`);
        }
      }
    }

    const anyError = built.sourceReports.some((s) => s.status === 'ERROR');
    const regionsCovered = [...new Set(SOURCES.map((s) => s.region))];

    result = {
      as_of: new Date().toISOString(),
      status: anyError ? 'PARTIAL_FAILURE' : 'OK',
      regions_covered: regionsCovered,
      regions_not_covered: REGIONS_NOT_COVERED,
      sources: built.sourceReports,
      entries: built.entries,
      structural_failures: built.unresolved,
      validation,
      warnings: built.warnings,
    };

    if (!anyError) {
      fs.writeFileSync(CACHE_FILE, JSON.stringify(result, null, 2));
    } else {
      console.error('NOT caching this run — at least one source is in ERROR; a bad partial must not persist for the 7-day TTL.');
    }
  }

  const output = applyRegionFilter(result, opts.regions);
  process.stdout.write(JSON.stringify(output, null, 2));

  console.error(
    `\n${output.entries.length} candidates across ${output.sources.length} source(s)` +
      (fromCache ? ' [from cache]' : ''),
  );

  if (result.status !== 'OK') process.exitCode = 1;
}

// ---------------------------------------------------------------------------------------------
// Self-test — offline, no network. Run: node fetch-universe.js --self-test
// ---------------------------------------------------------------------------------------------

function fail(msg) {
  throw new Error(msg);
}

function runSelfTests() {
  let allPass = true;
  function check(name, fn) {
    try {
      fn();
      console.error(`PASS: ${name}`);
    } catch (err) {
      console.error(`FAIL: ${name} — ${err.message}`);
      allPass = false;
    }
  }

  const map = loadMap();

  // --- Suffix mapping: each source's transform produces a symbol whose
  // suffix is a real key in exchange-currency-map.json, and the transform
  // itself matches the documented Yahoo convention for a known real name.
  const suffixCases = [
    { source: 'S&P 500', mode: 'append-suffix', suffix: '', raw: 'BRK.B', expected: 'BRK-B' },
    { source: 'S&P 500', mode: 'append-suffix', suffix: '', raw: 'AAPL', expected: 'AAPL' },
    { source: 'FTSE 100', mode: 'append-suffix', suffix: '.L', raw: 'BT.A', expected: 'BT-A.L' },
    { source: 'FTSE 100', mode: 'append-suffix', suffix: '.L', raw: 'ADM', expected: 'ADM.L' },
    { source: 'SMI', mode: 'append-suffix', suffix: '.SW', raw: 'NOVN', expected: 'NOVN.SW' },
    { source: 'OMX Copenhagen 25', mode: 'append-suffix', suffix: '.CO', raw: 'AMBU B', expected: 'AMBU-B.CO' },
    { source: 'OBX Index', mode: 'append-suffix', suffix: '.OL', raw: 'OSE: EQNR', expected: 'EQNR.OL', pre: stripExchangePrefix },
    { source: 'DAX', mode: 'already-suffixed', raw: 'ADS.DE', expected: 'ADS.DE' },
    { source: 'CAC 40', mode: 'already-suffixed', raw: 'MT.AS', expected: 'MT.AS' },
  ];

  for (const c of suffixCases) {
    check(`suffix transform: ${c.source} "${c.raw}" -> "${c.expected}"`, () => {
      const rawTicker = c.pre ? c.pre(c.raw) : c.raw;
      const symbol = c.mode === 'already-suffixed' ? rawTicker.trim().toUpperCase() : appendSuffix(rawTicker, c.suffix);
      if (symbol !== c.expected) fail(`got "${symbol}"`);
      const resolution = resolveViaMap({ symbol }, map);
      if (!resolution.resolved) fail(`symbol "${symbol}" did not resolve via exchange-currency-map.json: ${resolution.reason}`);
    });
  }

  // Every SOURCES entry's suffix (when statically known, i.e. append-suffix
  // mode) must itself be a real map key — catches a typo'd suffix in the
  // config before it ever reaches a live fetch.
  for (const source of SOURCES) {
    if (source.tickerMode !== 'append-suffix') continue;
    check(`SOURCES config: ${source.name}'s suffix "${source.suffix}" is a real map key`, () => {
      if (!(source.suffix in map)) fail(`"${source.suffix}" not in exchange-currency-map.json`);
      if (!(source.suffix in SUFFIX_COUNTRY)) fail(`"${source.suffix}" not in this script's SUFFIX_COUNTRY table`);
    });
  }

  // --- Parse-failure detection: a too-small / structurally-changed table
  // must be reported as a sanity-floor failure, never silently accepted.
  check('sanity floor rejects an implausibly small S&P 500 scrape', () => {
    const fakeSource = SOURCES.find((s) => s.name === 'S&P 500');
    const tinyRowCount = 5; // far below the 480 floor
    const status = tinyRowCount >= fakeSource.sanityFloor ? 'OK' : 'ERROR';
    if (status !== 'ERROR') fail('expected ERROR status for a 5-row S&P 500 scrape');
  });

  check('parseWikitable throws when the requested table index does not exist', () => {
    const html = '<table class="wikitable"><tr><th>A</th></tr><tr><td>1</td></tr></table>';
    let threw = false;
    try {
      parseWikitable(html, 3, 1); // only 1 table present, index 3 requested
    } catch {
      threw = true;
    }
    if (!threw) fail('expected parseWikitable to throw for an out-of-range table index');
  });

  check('parseWikitable drops rows below minCells rather than emitting partial rows', () => {
    const html = '<table class="wikitable"><tr><th>A</th><th>B</th><th>C</th></tr><tr><td>x</td><td>y</td></tr></table>';
    const rows = parseWikitable(html, 0, 3); // header row has 3 cells but only header is present; body row has 2
    if (rows.length !== 0) fail(`expected 0 rows (body row has 2 cells, minCells=3), got ${rows.length}`);
  });

  // --- rowToEntry: missing ticker or name must drop the row, not emit a
  // half-populated entry.
  check('rowToEntry drops a row with an empty ticker cell', () => {
    const source = SOURCES.find((s) => s.name === 'FTSE 100');
    const entry = rowToEntry(['Some Company', '', 'Sector'], source);
    if (entry !== null) fail('expected null for empty ticker cell');
  });

  check('rowToEntry drops a row with an empty name cell', () => {
    const source = SOURCES.find((s) => s.name === 'FTSE 100');
    const entry = rowToEntry(['', 'ADM', 'Sector'], source);
    if (entry !== null) fail('expected null for empty name cell');
  });

  // --- suffixOf correctness, including the "no dot at all" US case and a
  // hyphenated share-class symbol that must NOT be mistaken for a suffix.
  check('suffixOf: bare US symbol has empty suffix', () => {
    if (suffixOf('AAPL') !== '') fail(`got "${suffixOf('AAPL')}"`);
  });
  check('suffixOf: hyphenated share class does not confuse suffix extraction', () => {
    if (suffixOf('BT-A.L') !== '.L') fail(`got "${suffixOf('BT-A.L')}"`);
  });

  // --- region filtering: --region=us must actually return only 'us'
  // entries, not silently zero everything out because the `region` field
  // was dropped somewhere between the raw source entry and the final
  // resolved entry (regression caught live once already — this test
  // pins it down).
  check('applyRegionFilter keeps only entries whose region matches the filter', () => {
    const fakeResult = {
      entries: [
        { symbol: 'AAPL', region: 'us' },
        { symbol: 'ADM.L', region: 'eu' },
      ],
      sources: [
        { name: 'S&P 500', region: 'us' },
        { name: 'FTSE 100', region: 'eu' },
      ],
    };
    const filtered = applyRegionFilter(fakeResult, ['us']);
    if (filtered.entries.length !== 1) fail(`expected 1 entry, got ${filtered.entries.length}`);
    if (filtered.entries[0].symbol !== 'AAPL') fail(`expected AAPL, got ${filtered.entries[0].symbol}`);
  });

  // --- resolveViaMap: an unknown suffix must fail structurally, never guess.
  check('resolveViaMap reports an unresolved (not guessed) result for an unmapped suffix', () => {
    const resolution = resolveViaMap({ symbol: 'FOO.ZZ' }, map);
    if (resolution.resolved) fail('expected resolved=false for an unmapped suffix ".ZZ"');
  });

  // --- majorCurrencyOf: must uppercase a minor-unit code (GBp -> GBP) —
  // this is the same trap fetch-global-quote.js documents for prices.
  check('majorCurrencyOf uppercases a minor-unit currency code (GBp -> GBP)', () => {
    const code = majorCurrencyOf(map['.L']);
    if (code !== 'GBP') fail(`got "${code}"`);
  });
  check('majorCurrencyOf passes through a clean major-unit code (USD)', () => {
    const code = majorCurrencyOf(map['']);
    if (code !== 'USD') fail(`got "${code}"`);
  });

  return allPass;
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
