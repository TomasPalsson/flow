#!/usr/bin/env node
/**
 * fetch-quote.js
 * Fetch current quote data for tickers via yahoo-finance2 npm package.
 *
 * Requires: npm install -g yahoo-finance2  (or run from a project with it installed)
 *
 * Output: JSON array, one object per ticker, with price/market cap/basic ratios.
 *
 * Caching: 5-minute TTL per ticker.
 *
 * Usage: node fetch-quote.js TICKER1 [TICKER2] ...
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';

const CACHE_DIR = path.join(os.homedir(), '.cache', 'investment-skill', 'quote');
const CACHE_TTL_MS = 5 * 60 * 1000;

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}

async function loadYf() {
  try {
    const mod = await import('yahoo-finance2');
    const YahooFinance = mod.default;
    // v3 requires instantiation
    const yf = (typeof YahooFinance === 'function') ? new YahooFinance() : YahooFinance;
    // Suppress survey + historical-deprecation notices that spam stderr
    if (yf.suppressNotices) yf.suppressNotices(['yahooSurvey', 'ripHistorical']);
    return yf;
  } catch (err) {
    console.error('yahoo-finance2 not installed. Run: npm install yahoo-finance2 in the skill dir.');
    throw err;
  }
}

async function fetchTicker(yf, ticker) {
  const cacheFile = path.join(CACHE_DIR, `${ticker}.json`);
  if (fs.existsSync(cacheFile)) {
    const stat = fs.statSync(cacheFile);
    if (Date.now() - stat.mtimeMs < CACHE_TTL_MS) {
      return JSON.parse(fs.readFileSync(cacheFile, 'utf8'));
    }
  }

  // Multi-attempt with backoff for yfinance rate-limiting
  let lastErr;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const [quote, summary] = await Promise.all([
        yf.quote(ticker),
        yf.quoteSummary(ticker, { modules: ['summaryDetail', 'defaultKeyStatistics', 'financialData', 'price'] }).catch(() => null),
      ]);

      // Guard the known-bad Yahoo dateShortInterest field: it occasionally comes
      // back as a 1974-epoch placeholder instead of a real biweekly settlement
      // date. Null it out rather than propagate garbage.
      const rawDateShortInterest = summary?.defaultKeyStatistics?.dateShortInterest;
      const parsedDateShortInterest = rawDateShortInterest ? new Date(rawDateShortInterest) : null;
      const dateShortInterest = (parsedDateShortInterest && !Number.isNaN(parsedDateShortInterest.getTime()) && parsedDateShortInterest.getUTCFullYear() >= 2000)
        ? parsedDateShortInterest.toISOString().slice(0, 10)
        : null;

      const out = {
        ticker,
        fetched_at: new Date().toISOString(),
        price: quote.regularMarketPrice,
        market_cap: quote.marketCap,
        currency: quote.currency,
        exchange: quote.exchange,
        avg_daily_volume_3mo: quote.averageDailyVolume3Month,
        avg_daily_dollar_volume_3mo: (quote.averageDailyVolume3Month || 0) * (quote.regularMarketPrice || 0),
        // Deprecated aliases -- old key names mislabelled a 3-MONTH average as
        // "30d". Kept pointing at the same values so nothing downstream (the
        // alpha-hunt capacity rule, etc.) breaks on the rename. Prefer the
        // *_3mo keys above.
        avg_daily_volume_30d: quote.averageDailyVolume3Month,
        avg_daily_dollar_volume_30d: (quote.averageDailyVolume3Month || 0) * (quote.regularMarketPrice || 0),
        // True ~20-trading-day proxy: alpha-hunt's capacity rule is specified
        // on ~20-day ADV, and a 10-day average is far closer to that than the
        // 3-month figure above. No extra HTTP request -- summaryDetail is
        // already fetched.
        avg_daily_volume_10d: summary?.summaryDetail?.averageDailyVolume10Day,
        avg_daily_dollar_volume_10d: (summary?.summaryDetail?.averageDailyVolume10Day || 0) * (quote.regularMarketPrice || 0),
        fifty_two_week_high: quote.fiftyTwoWeekHigh,
        fifty_two_week_low: quote.fiftyTwoWeekLow,
        fifty_day_avg: quote.fiftyDayAverage,
        two_hundred_day_avg: quote.twoHundredDayAverage,
        price_to_book: summary?.defaultKeyStatistics?.priceToBook,
        price_to_sales_ttm: summary?.summaryDetail?.priceToSalesTrailing12Months,
        pe_trailing: quote.trailingPE,
        pe_forward: quote.forwardPE,
        peg: summary?.defaultKeyStatistics?.pegRatio,
        eps_trailing: quote.epsTrailingTwelveMonths,
        beta: summary?.defaultKeyStatistics?.beta,
        dividend_yield: summary?.summaryDetail?.dividendYield,
        return_on_equity: summary?.financialData?.returnOnEquity,
        return_on_assets: summary?.financialData?.returnOnAssets,
        profit_margin: summary?.financialData?.profitMargins,
        operating_margin: summary?.financialData?.operatingMargins,
        revenue_growth: summary?.financialData?.revenueGrowth,
        debt_to_equity: summary?.financialData?.debtToEquity,
        free_cashflow: summary?.financialData?.freeCashflow,
        operating_cashflow: summary?.financialData?.operatingCashflow,
        shares_outstanding: summary?.defaultKeyStatistics?.sharesOutstanding,
        // [WARN] sharesOutstanding may be stale by 6-12 months — cross-check from EDGAR XBRL when available
        shares_short: summary?.defaultKeyStatistics?.sharesShort,
        short_ratio: summary?.defaultKeyStatistics?.shortRatio,
        short_pct_of_float: summary?.defaultKeyStatistics?.shortPercentOfFloat,
        // [WARN] dateShortInterest is a biweekly settlement date, not real-time.
        // Yahoo sometimes returns a garbage 1974-epoch placeholder for this field
        // -- treat anything that parses before 2000 as absent rather than emit
        // the bogus date.
        date_short_interest: dateShortInterest,
      };

      fs.writeFileSync(cacheFile, JSON.stringify(out, null, 2));
      return out;
    } catch (err) {
      lastErr = err;
      // Rate limit backoff
      const msg = err.message || '';
      if (msg.includes('429') || msg.toLowerCase().includes('rate')) {
        await new Promise((r) => setTimeout(r, 5000 * (attempt + 1)));
      } else {
        // Non-rate error — log and move on
        break;
      }
    }
  }

  return { ticker, error: lastErr?.message || 'unknown', fetched_at: new Date().toISOString() };
}

async function main() {
  const tickers = process.argv.slice(2).filter((a) => !a.startsWith('--'));
  if (tickers.length === 0) {
    console.error('Usage: fetch-quote.js TICKER1 [TICKER2] ...');
    process.exit(1);
  }

  ensureCacheDir();
  const yf = await loadYf();

  // Parallel batches of 5 (yfinance rate-limits aggressively)
  const results = [];
  for (let i = 0; i < tickers.length; i += 5) {
    const batch = tickers.slice(i, i + 5);
    const batchResults = await Promise.all(batch.map((t) => fetchTicker(yf, t)));
    results.push(...batchResults);
    if (i + 5 < tickers.length) await new Promise((r) => setTimeout(r, 200));
  }

  process.stdout.write(JSON.stringify(results, null, 2));
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
