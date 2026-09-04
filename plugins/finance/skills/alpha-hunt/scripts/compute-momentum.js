#!/usr/bin/env node
/**
 * compute-momentum.js
 * Compute momentum-sleeve signals for a BATCH of tickers in one process
 * (never per-ticker subprocess — keeps Yahoo request count/crumb cost down).
 * Uses the keyless Yahoo v8 chart endpoint, weekly bars. A market proxy
 * (SPY) is fetched once and reused for the residual-momentum regression.
 *
 * Per ticker (weekly bars; ~52 weeks = 1y, ~4 weeks skip):
 *   mom_12_1            total return from ~52 weeks ago to ~4 weeks ago.
 *                        Still COMPUTED and REPORTED (other stages read it)
 *                        but carries ZERO weight in the composite — see the
 *                        comment above COMPOSITE_WEIGHTS for why.
 *   high_52w_proximity  last adjclose / max(adjclose over trailing 52 weeks).
 *   discreteness        frog-in-the-pan JUMP proxy — reported diagnostic
 *                        ONLY, not weighted in the composite (see
 *                        info_discreteness for the weighted version): abs
 *                        (largest single weekly return in the 12-1 window)
 *                        / sum(abs(weekly returns) in the window). LOWER =
 *                        steadier grinder. NOTE: daily bars would be the
 *                        ideal input for this metric; weekly bars are the
 *                        keyless-endpoint approximation.
 *   info_discreteness   the WEIGHTED frog-in-the-pan measure: a sign-count
 *                        analog of Da, Gurun & Warachka (2014)'s information
 *                        discreteness, ID = sign(PRET) x (%neg - %pos) over
 *                        the formation window. Built from fields already on
 *                        hand: sign(mom_12_1) * (1 - 2*up_ratio), since
 *                        %neg - %pos = (1-up_ratio) - up_ratio. LOWER =
 *                        steadier "continuous" information = better forward
 *                        returns per the paper. The paper's measure is built
 *                        on DAILY bars; this weekly-bar version is
 *                        faithful-in-form but coarser-in-resolution.
 *   up_ratio            fraction of up weeks in the 12-1 window.
 *   residual_mom        OLS beta+intercept of ticker weekly returns on SPY
 *                        weekly returns, then residuals = actual - predicted
 *                        over the 12-1 window, standardized as
 *                        sum(residuals) / std(residuals) — an INFORMATION
 *                        RATIO, per Blitz, Huij & Martens (2011). The
 *                        division is mandatory, not cosmetic: a raw
 *                        (unstandardized) sum biases the ranking toward
 *                        high-idiosyncratic-vol names, which carry
 *                        documented POOR forward returns (Ang, Hodrick, Xing
 *                        & Zhang). If the residual std is 0/non-finite the
 *                        ticker is skipped, same as any other
 *                        regression-skip path. IMPORTANT: beta is fit
 *                        over the FULL available history (up to the 1-month
 *                        cutoff), not just the 12-1 window itself — fitting
 *                        and summing residuals over the identical sample
 *                        would force the sum to be exactly zero (a property
 *                        of OLS-with-intercept), producing a degenerate
 *                        always-0 signal. Ticker/SPY bars are paired by a
 *                        week-bucket key (round(ts / 1 week)), not raw array
 *                        position, since shorter-history tickers can have
 *                        fewer/offset bars than SPY.
 *   above_200dma        last adjclose > mean(trailing 40 weekly closes), a
 *                        weekly-bar proxy for "above the 200-day MA" (~200
 *                        calendar days ~= 40 weekly bars). Names with <41
 *                        weekly bars are excluded from the breadth
 *                        denominator. NOT part of the composite — feeds the
 *                        batch-level `breadth` block in the cache file only.
 *
 * Before cross-sectional z-scoring, every COMPOSITE_WEIGHTS field is
 * WINSORIZED (clipped to its [1st, 99th] percentile across the batch — see
 * WINSOR_PCT) because raw mean/std across ~1500 fat-tailed names lets a
 * single extreme mover inflate sigma and compress everyone else's score.
 * Cross-sectional z-scores are then computed across the successfully-
 * fetched batch and combined into `composite` (see COMPOSITE_WEIGHTS).
 * Output is a JSON array to stdout, sorted descending by composite with a
 * `rank` field, and cached to ~/.cache/alpha-hunt/momentum-rank.json as
 * { fetched_at, universe_size, n_input_tickers, n_scored, breadth,
 * results: [...] } — universe_size/n_input_tickers/n_scored let a later run
 * tell a rank drop caused by universe-composition shrinkage apart from an
 * actual momentum break. A second cache file,
 * ~/.cache/alpha-hunt/returns-series.json, persists each scored ticker's
 * trailing ~60 weekly returns (aligned by the same week-bucket key) as
 * { fetched_at, week_keys, series: { TICKER: [...] } } — this is what makes
 * the risk-and-sizing.md §12 rolling pairwise-correlation throttle
 * computable. Progress/warnings go to stderr.
 *
 * Usage: node compute-momentum.js AAPL MSFT NVDA
 *    or: node compute-momentum.js --file tickers.txt  (newline-separated, '#' = comment)
 */

const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const https = require('node:https');

const CACHE_DIR = path.join(os.homedir(), '.cache', 'alpha-hunt');
const CACHE_FILE = path.join(CACHE_DIR, 'momentum-rank.json');
const RETURNS_CACHE_FILE = path.join(CACHE_DIR, 'returns-series.json');
const USER_AGENT = 'Mozilla/5.0';
const WEEK_SECONDS = 7 * 24 * 60 * 60;
const MIN_WEEKS = 53; // need index (n-52) valid, i.e. at least 53 bars
const MIN_PAIRS = 20; // min SPY-paired weeks required, applied to both the beta-estimation sample and the 12-1 window sample
const WINSOR_PCT = 0.01; // clip each composite field to its [1st,99th] percentile before z-scoring — MSCI Barra's USE4 methodology winsorizes outliers as standard practice
const RETURNS_LOOKBACK_WEEKS = 60; // trailing weekly-return history persisted for the risk-and-sizing.md §12 pairwise-correlation throttle
const VOL_LOOKBACK_WEEKS = 26;     // ~6 months of weekly bars for realized_vol_annual (compute-sizing.js input)
const VOL_PROXY_TICKER = 'MTUM';   // risk-and-sizing.md §3 bootstrap: a new book has no own-strategy vol history

// residual_mom carries the most weight because it IS the momentum signal in
// its superior (Blitz-Huij-Martens) construction; mom_12_1 (raw 12-1 total
// return) is kept at ZERO weight rather than dropped outright — it stays in
// the composite/output for diagnostics and because other stages read it —
// but giving it nonzero weight alongside residual_mom would double-count
// one phenomenon twice (the two are heavily overlapping measures of the
// same momentum effect). discreteness (jump-magnitude) is likewise reported
// but unweighted in favor of info_discreteness (sign-count), which is the
// more faithful analog of the Da-Gurun-Warachka construction. These are
// fixed, roughly-equal-ish weights rather than optimized ones on purpose:
// DeMiguel, Garlappi & Uppal (2009, RFS) show mean-variance-optimized
// weights need on the order of ~3000 months of data for 25 assets to beat
// naive 1/N-style weighting out-of-sample — far more history than this
// sleeve has — so fixed weights are the more robust choice here.
const COMPOSITE_WEIGHTS = { residual_mom: 0.50, mom_12_1: 0.00, high_52w_proximity: 0.25, up_ratio: 0.10, info_discreteness: 0.15 };

function ensureCacheDir() {
  if (!fs.existsSync(CACHE_DIR)) fs.mkdirSync(CACHE_DIR, { recursive: true });
}
function sleep(ms) { return new Promise((resolve) => setTimeout(resolve, ms)); }
function round(x, d) {
  if (x === null || x === undefined || Number.isNaN(x)) return null;
  const m = 10 ** d;
  return Math.round(x * m) / m;
}
function weekKey(ts) { return Math.round(ts / WEEK_SECONDS); }

// Parse a Yahoo v8 chart response into aligned {timestamps, prices} arrays,
// dropping any bar whose adjclose is null (holidays/gaps).
function parseChartResponse(data) {
  const chartErr = data && data.chart && data.chart.error;
  if (chartErr) throw new Error(chartErr.description || 'Yahoo chart API error');
  const result = data && data.chart && data.chart.result && data.chart.result[0];
  if (!result) throw new Error('no chart result (invalid ticker?)');
  const timestamps = result.timestamp || [];
  const adjcloseArr = (result.indicators && result.indicators.adjclose && result.indicators.adjclose[0] && result.indicators.adjclose[0].adjclose) || [];
  const prices = [];
  const outTs = [];
  for (let i = 0; i < timestamps.length; i++) {
    const p = adjcloseArr[i];
    if (p !== null && p !== undefined) { prices.push(p); outTs.push(timestamps[i]); }
  }
  if (prices.length === 0) throw new Error('no adjclose data returned');
  return { timestamps: outTs, prices };
}

function fetchChart(ticker) {
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?range=2y&interval=1wk&events=div,splits`;
  return new Promise((resolve, reject) => {
    const req = https.get(url, { headers: { 'User-Agent': USER_AGENT }, timeout: 15000 }, (res) => {
      if (res.statusCode !== 200) { res.resume(); return reject(new Error(`HTTP ${res.statusCode}`)); }
      let body = '';
      res.on('data', (c) => { body += c; });
      res.on('end', () => {
        let data;
        try { data = JSON.parse(body); } catch (e) { return reject(new Error(`bad JSON response: ${e.message}`)); }
        try { resolve(parseChartResponse(data)); } catch (e) { reject(e); }
      });
    });
    req.on('timeout', () => req.destroy(new Error('request timed out')));
    req.on('error', reject);
  });
}

function buildReturnsByWeek(series) {
  const map = new Map();
  for (let i = 1; i < series.prices.length; i++) {
    map.set(weekKey(series.timestamps[i]), series.prices[i] / series.prices[i - 1] - 1);
  }
  return map;
}

function meanOf(arr) { return arr.reduce((a, b) => a + b, 0) / arr.length; }
function stdOf(arr, mean) { return Math.sqrt(arr.reduce((a, b) => a + (b - mean) ** 2, 0) / arr.length); }
function zscore(value, mean, std) { return std === 0 ? 0 : (value - mean) / std; }

// Linear-interpolation percentile over an ALREADY-SORTED (ascending) array.
// p in [0,1]. Used to winsorize each composite field before z-scoring.
function percentile(sortedArr, p) {
  if (sortedArr.length === 0) return NaN;
  if (sortedArr.length === 1) return sortedArr[0];
  const idx = p * (sortedArr.length - 1);
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  if (lo === hi) return sortedArr[lo];
  return sortedArr[lo] + (sortedArr[hi] - sortedArr[lo]) * (idx - lo);
}

// Simple OLS: y = beta*x + intercept, via least squares. Returns
// {beta, intercept} or null if x has no variance (can't fit a slope).
function olsFit(xs, ys) {
  const mx = meanOf(xs);
  const my = meanOf(ys);
  let cov = 0;
  let varX = 0;
  for (let i = 0; i < xs.length; i++) { cov += (xs[i] - mx) * (ys[i] - my); varX += (xs[i] - mx) ** 2; }
  if (varX === 0) return null;
  const beta = cov / varX;
  return { beta, intercept: my - beta * mx };
}

function computeTickerMetrics(ticker, series, spyReturnsByWeek) {
  const { timestamps, prices } = series;
  if (prices.length < MIN_WEEKS) throw new Error(`insufficient history: need >=${MIN_WEEKS} weekly bars, got ${prices.length}`);

  const n = prices.length - 1;
  const idxRecent = n - 4; // ~1 month ago (skip most recent 4 weeks)
  const idxStart = n - 52; // ~12 months ago
  if (prices[idxStart] === 0) throw new Error('invalid price data (zero price)');
  const mom_12_1 = prices[idxRecent] / prices[idxStart] - 1;

  const last52 = prices.slice(n - 51, n + 1);
  const high_52w_proximity = prices[n] / Math.max(...last52);

  const windowReturns = [];
  const windowTs = [];
  for (let i = idxStart + 1; i <= idxRecent; i++) {
    windowReturns.push(prices[i] / prices[i - 1] - 1);
    windowTs.push(timestamps[i]);
  }

  // Frog-in-the-pan proxy: fraction of total absolute movement contributed
  // by the single largest weekly move. Lower = steadier grinder. (Daily
  // bars would sharpen this; weekly is the keyless-endpoint tradeoff.)
  const absReturns = windowReturns.map(Math.abs);
  const maxAbsReturn = Math.max(...absReturns);
  const sumAbsReturns = absReturns.reduce((a, b) => a + b, 0);
  const discreteness = sumAbsReturns === 0 ? 0 : maxAbsReturn / sumAbsReturns;

  const upWeeks = windowReturns.filter((r) => r > 0).length;
  const up_ratio = upWeeks / windowReturns.length;

  // Frog-in-the-pan, WEIGHTED version: a sign-count analog of Da, Gurun &
  // Warachka (2014)'s information discreteness, ID = sign(PRET) x (%neg -
  // %pos) over the formation window. %neg - %pos = (1-up_ratio) - up_ratio
  // = 1 - 2*up_ratio, so this is built entirely from fields already on
  // hand. LOWER = steadier "continuous" information = better forward
  // returns per the paper. The paper's ID is built on DAILY bars; this is
  // faithful-in-form but coarser-in-resolution given weekly inputs.
  const info_discreteness = Math.sign(mom_12_1) * (1 - 2 * up_ratio);

  // 200-day-MA proxy (weekly bars): ~200 calendar days ~= 40 weekly bars.
  // Names with <41 weekly bars (40 trailing bars plus the current one) are
  // excluded from the breadth denominator downstream. In practice this
  // branch never fires while MIN_WEEKS=53 gates entry above, since anything
  // that reaches this point already has far more than 41 bars — kept
  // explicit for correctness if MIN_WEEKS is ever lowered.
  let above_200dma = null;
  if (prices.length >= 41) {
    const last40 = prices.slice(n - 39, n + 1);
    above_200dma = prices[n] > meanOf(last40);
  }

  // Trailing annualized realized volatility, from the MOST RECENT weeks
  // (deliberately NOT the 12-1 formation window — sizing needs vol as it is
  // NOW, not as it was a year ago). compute-sizing.js takes this as a
  // MANDATORY per-candidate input for the inverse-vol tilt (§4); emitting it
  // here is what keeps that number a computed value rather than an LLM
  // estimate, per llm-guardrails.md §13.
  let realized_vol_annual = null;
  if (prices.length >= VOL_LOOKBACK_WEEKS + 1) {
    const recent = [];
    for (let i = n - VOL_LOOKBACK_WEEKS + 1; i <= n; i++) recent.push(prices[i] / prices[i - 1] - 1);
    const rStd = stdOf(recent, meanOf(recent));
    if (Number.isFinite(rStd) && rStd > 0) realized_vol_annual = rStd * Math.sqrt(52);
  }

  // Beta-estimation sample: ALL available weekly returns up to the 1-month
  // cutoff (a superset of, and longer than, the 12-1 window below).
  const estX = [];
  const estY = [];
  for (let i = 1; i <= idxRecent; i++) {
    const spyRet = spyReturnsByWeek.get(weekKey(timestamps[i]));
    if (spyRet !== undefined) { estX.push(spyRet); estY.push(prices[i] / prices[i - 1] - 1); }
  }

  let residual_mom = null;
  let regressionSkipReason = null;
  if (estX.length < MIN_PAIRS) {
    regressionSkipReason = `only ${estX.length} SPY-paired weeks in estimation history (need >=${MIN_PAIRS})`;
  } else {
    const fit = olsFit(estX, estY);
    if (!fit) {
      regressionSkipReason = 'SPY returns have zero variance in estimation sample (cannot fit beta)';
    } else {
      const residuals = [];
      for (let i = 0; i < windowReturns.length; i++) {
        const spyRet = spyReturnsByWeek.get(weekKey(windowTs[i]));
        if (spyRet !== undefined) { residuals.push(windowReturns[i] - (fit.beta * spyRet + fit.intercept)); }
      }
      if (residuals.length < MIN_PAIRS) {
        regressionSkipReason = `only ${residuals.length} SPY-paired weeks in the 12-1 window (need >=${MIN_PAIRS})`;
      } else {
        // Blitz, Huij & Martens (2011): residual momentum is the cumulative
        // residual return over the formation window DIVIDED BY the std of
        // those residuals — an information-ratio form, not a raw sum. The
        // division is what makes this an IR rather than a raw cumulative
        // residual: skipping it biases the ranking toward
        // high-idiosyncratic-volatility names, which carry documented POOR
        // forward returns (Ang, Hodrick, Xing & Zhang) — the opposite of
        // this signal's intent.
        const residSum = residuals.reduce((a, b) => a + b, 0);
        const residMean = meanOf(residuals);
        const residStd = stdOf(residuals, residMean);
        if (residStd === 0 || !Number.isFinite(residStd)) {
          regressionSkipReason = 'residual std is zero/non-finite in the 12-1 window (degenerate information-ratio denominator)';
        } else {
          residual_mom = residSum / residStd;
        }
      }
    }
  }

  return { ticker, mom_12_1, high_52w_proximity, discreteness, info_discreteness, up_ratio, residual_mom, above_200dma, realized_vol_annual, _regressionSkipReason: regressionSkipReason };
}

function computeCompositeAndRank(results) {
  const fields = Object.keys(COMPOSITE_WEIGHTS);
  const stats = {};
  for (const f of fields) {
    // Exclude null/non-finite values (e.g. residual_mom when the regression was
    // skipped) so a missing field can't drag the cross-sectional mean/std.
    const vals = results.map((r) => r[f]).filter((v) => typeof v === 'number' && Number.isFinite(v));
    // Winsorize to the [WINSOR_PCT, 1-WINSOR_PCT] percentile band BEFORE
    // computing mean/std — one extreme mover across ~1500 fat-tailed names
    // otherwise inflates sigma and compresses everyone else's z-score.
    const sorted = [...vals].sort((a, b) => a - b);
    const lo = percentile(sorted, WINSOR_PCT);
    const hi = percentile(sorted, 1 - WINSOR_PCT);
    const clipped = vals.map((v) => Math.min(hi, Math.max(lo, v)));
    const m = meanOf(clipped);
    stats[f] = { mean: m, std: stdOf(clipped, m), lo, hi };
  }
  for (const r of results) {
    const z = {};
    // A missing field contributes a neutral z=0 rather than a spurious value.
    // Present values are clipped to the same winsor band used for mean/std
    // before z-scoring, so a single outlier can't dominate its own z either.
    for (const f of fields) {
      if (typeof r[f] === 'number' && Number.isFinite(r[f])) {
        const clippedVal = Math.min(stats[f].hi, Math.max(stats[f].lo, r[f]));
        z[f] = zscore(clippedVal, stats[f].mean, stats[f].std);
      } else {
        z[f] = 0;
      }
    }
    // info_discreteness is inverted: higher composite should reward LOWER
    // info_discreteness (steadier, more continuous information flow).
    // mom_12_1's weight is 0.00 (see comment above COMPOSITE_WEIGHTS) so it
    // contributes exactly 0 here regardless of its z-score.
    r.composite = COMPOSITE_WEIGHTS.residual_mom * z.residual_mom
      + COMPOSITE_WEIGHTS.mom_12_1 * z.mom_12_1
      + COMPOSITE_WEIGHTS.high_52w_proximity * z.high_52w_proximity
      + COMPOSITE_WEIGHTS.up_ratio * z.up_ratio
      + COMPOSITE_WEIGHTS.info_discreteness * -z.info_discreteness;
  }
  results.sort((a, b) => b.composite - a.composite);
  results.forEach((r, idx) => { r.rank = idx + 1; });
}

function readTickers(argv) {
  if (argv[0] === '--file') {
    const filePath = argv[1];
    if (!filePath) throw new Error('--file requires a path argument');
    if (!fs.existsSync(filePath)) throw new Error(`file not found: ${filePath}`);
    return fs.readFileSync(filePath, 'utf8').split('\n').map((l) => l.trim()).filter((l) => l && !l.startsWith('#'));
  }
  return argv;
}

async function main() {
  let tickers;
  try {
    tickers = readTickers(process.argv.slice(2));
  } catch (err) {
    console.error(`FATAL: ${err.message}`);
    process.exit(1);
  }
  tickers = [...new Set(tickers.map((t) => t.toUpperCase()).filter(Boolean))];
  if (tickers.length === 0) {
    console.error('Usage: node compute-momentum.js TICKER1 [TICKER2 ...]');
    console.error('   or: node compute-momentum.js --file <path>');
    process.exit(1);
  }

  ensureCacheDir();

  console.error('Fetching market proxy SPY for residual-momentum regression...');
  let spyReturnsByWeek;
  try {
    spyReturnsByWeek = buildReturnsByWeek(await fetchChart('SPY'));
  } catch (err) {
    console.error(`FATAL: could not fetch SPY market proxy: ${err.message}`);
    process.exit(1);
  }

  const results = [];
  const seriesReturnsByTicker = {}; // ticker -> Map(weekKey -> weekly return), scored tickers only; feeds returns-series.json (FIX 6)
  let failCount = 0;
  for (let i = 0; i < tickers.length; i++) {
    const ticker = tickers[i];
    if (i > 0) await sleep(60 + Math.floor(Math.random() * 61)); // 60-120ms stagger
    try {
      const series = await fetchChart(ticker);
      const metrics = computeTickerMetrics(ticker, series, spyReturnsByWeek);
      if (metrics.residual_mom === null) {
        console.error(`WARN: ${ticker}: ${metrics._regressionSkipReason} — skipping`);
        failCount++;
        continue;
      }
      delete metrics._regressionSkipReason;
      results.push(metrics);
      seriesReturnsByTicker[ticker] = buildReturnsByWeek(series);
    } catch (err) {
      console.error(`WARN: ${ticker}: ${err.message} — skipping`);
      failCount++;
    }
  }

  console.error(`Momentum signals: ${results.length}/${tickers.length} succeeded, ${failCount}/${tickers.length} failed.`);
  if (results.length === 0) {
    console.error('FATAL: no tickers produced usable data.');
    process.exit(1);
  }

  computeCompositeAndRank(results);

  const output = results.map((r) => ({
    ticker: r.ticker,
    mom_12_1: round(r.mom_12_1, 6),
    residual_mom: round(r.residual_mom, 6),
    high_52w_proximity: round(r.high_52w_proximity, 6),
    discreteness: round(r.discreteness, 6),
    info_discreteness: round(r.info_discreteness, 6),
    up_ratio: round(r.up_ratio, 6),
    above_200dma: r.above_200dma,
    realized_vol_annual: round(r.realized_vol_annual, 6),
    composite: round(r.composite, 6),
    rank: r.rank,
  }));

  // Batch-level market breadth (FIX 5): % of the scored universe above its
  // 200DMA proxy. This is one of the four regime-dial inputs regime-
  // throttle.md expects and is not otherwise produced anywhere. Lives only
  // in the cache payload (top-level `breadth`), not the per-ticker stdout
  // array that other stages parse.
  const withHistory = results.filter((r) => r.above_200dma !== null);
  const nAbove = withHistory.filter((r) => r.above_200dma === true).length;
  const breadth = {
    pct_above_200dma: withHistory.length > 0 ? round(nAbove / withHistory.length, 4) : null,
    n_with_200dma_history: withHistory.length,
    universe_size: results.length,
  };
  console.error(`Market breadth: ${withHistory.length > 0 ? round((nAbove / withHistory.length) * 100, 1) : 'N/A'}% of universe (${nAbove}/${withHistory.length}) above 200DMA proxy.`);

  const fetchedAt = new Date().toISOString();

  // Book-vol BOOTSTRAP (risk-and-sizing.md §3): compute-sizing.js requires
  // `book_realized_vol`, but a brand-new book has no own-strategy return
  // history to measure. §3 specifies MTUM's trailing realized vol as the
  // stand-in until >=6 months of picks-log history exists. Computing it here
  // is what stops that input from being an LLM guess (llm-guardrails.md §13).
  // Non-fatal: a failed proxy fetch emits null, it does not sink the run.
  let vol_proxy = { ticker: VOL_PROXY_TICKER, realized_vol_annual: null, lookback_weeks: VOL_LOOKBACK_WEEKS, error: null };
  try {
    const proxySeries = await fetchChart(VOL_PROXY_TICKER);
    const pp = proxySeries.prices;
    if (pp.length >= VOL_LOOKBACK_WEEKS + 1) {
      const rets = [];
      for (let i = pp.length - VOL_LOOKBACK_WEEKS; i < pp.length; i++) rets.push(pp[i] / pp[i - 1] - 1);
      const s = stdOf(rets, meanOf(rets));
      if (Number.isFinite(s) && s > 0) vol_proxy.realized_vol_annual = round(s * Math.sqrt(52), 6);
    } else {
      vol_proxy.error = `insufficient history: ${pp.length} weekly bars`;
    }
  } catch (err) {
    vol_proxy.error = err.message;
  }
  console.error(vol_proxy.realized_vol_annual !== null
    ? `Book-vol bootstrap (${VOL_PROXY_TICKER}): ${round(vol_proxy.realized_vol_annual * 100, 1)}% annualized over ${VOL_LOOKBACK_WEEKS}w.`
    : `WARN: book-vol bootstrap (${VOL_PROXY_TICKER}) unavailable: ${vol_proxy.error} — supply book_realized_vol to compute-sizing.js another way.`);

  // universe_size/n_input_tickers/n_scored (ALSO section): so a later run
  // can tell a rank drop caused by universe-composition shrinkage apart
  // from an actual momentum break.
  const cachePayload = {
    fetched_at: fetchedAt,
    universe_size: tickers.length,
    n_input_tickers: tickers.length,
    n_scored: results.length,
    breadth,
    vol_proxy,
    results: output,
  };
  fs.writeFileSync(CACHE_FILE, JSON.stringify(cachePayload, null, 2));

  // FIX 6: persist trailing ~60-week return series per scored ticker,
  // aligned by the same week-bucket key the script already uses (weekKey),
  // so tickers with different history lengths remain alignable — this is
  // what makes the risk-and-sizing.md §12 rolling pairwise-correlation
  // throttle computable (it currently has nothing persisted to read).
  const spyWeekKeysSorted = [...spyReturnsByWeek.keys()].sort((a, b) => a - b);
  const week_keys = spyWeekKeysSorted.slice(-RETURNS_LOOKBACK_WEEKS);
  const series = {};
  for (const ticker of Object.keys(seriesReturnsByTicker)) {
    const retMap = seriesReturnsByTicker[ticker];
    series[ticker] = week_keys.map((wk) => (retMap.has(wk) ? round(retMap.get(wk), 6) : null));
  }
  const returnsPayload = { fetched_at: fetchedAt, week_keys, series };
  fs.writeFileSync(RETURNS_CACHE_FILE, JSON.stringify(returnsPayload, null, 2));

  process.stdout.write(JSON.stringify(output, null, 2) + '\n');
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
