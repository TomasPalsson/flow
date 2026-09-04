#!/usr/bin/env node
/**
 * preflight.js
 * Liveness + environment gate for the portfolio skill. Run this FIRST, every run, both
 * modes (SKILL.md: "Preflight — every run, both modes"). A dead data source or a broken
 * currency assumption must abort the run with the exact fix — never run a half-blind
 * pass, and never let a silently degraded data layer produce confident garbage.
 *
 * Checks:
 *   1. Node version >= 18.
 *   2. yahoo-finance2 importable (dynamic import, v3-style instantiation).
 *   3. Live Yahoo quote for a US symbol (AAPL).
 *   4. Live Yahoo quote for a non-US symbol (SHEL.L) WITH an explicit currency-field
 *      verification — currency handling is safety-critical (GBp is pence, not pounds;
 *      see references/04-global-data.md). If the observed currency is not exactly
 *      "GBp", the minor-unit divide-by-100 assumption this skill hard-codes needs
 *      re-verification before any sizing math runs on London-listed names.
 *   5. Cache dir ~/.cache/portfolio-skill exists or is creatable.
 *   6. Whether portfolio state is already present in the cache — informational only,
 *      reports a BUILD vs REVIEW mode hint. Never a failure; mode selection is decided
 *      by the skill itself (SKILL.md "Mode selection"), not by this script.
 *   7. Git repo + read/auth check against origin, as a proxy for state.sh's push
 *      capability. Absence is WARNED, not failed — but the warning is explicit that
 *      state will not persist across runs if this is broken.
 *
 * This script makes NO live IBKR calls — IBKR is reachable only via MCP tools, which
 * are not reachable from a plain Node process. The agent running this skill MUST
 * separately verify IBKR reachability itself (e.g. get_account_summary) before trusting
 * any IBKR-dependent stage. This script prints a reminder to do so.
 *
 * Output: PASS/FAIL/UNKNOWN table to stderr; JSON summary {ok, checks[]} to stdout.
 * Exit code: 0 if every CRITICAL check is PASS, 1 otherwise. Non-critical checks
 * (state-presence hint, git push capability) never affect the exit code, but are still
 * printed with their true status rather than being folded into PASS.
 *
 * Usage: node scripts/preflight.js
 */

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

const CACHE_DIR = path.join(os.homedir(), '.cache', 'portfolio-skill');
const STATE_FILE = path.join(CACHE_DIR, 'portfolio.json');
const HTTP_TIMEOUT_MS = 15000;

// status: 'PASS' | 'FAIL' | 'UNKNOWN'
// critical: whether a non-PASS status here should fail the whole preflight
function check(name, status, detail, critical = true) {
  return { name, status, detail, critical };
}

function withTimeout(promise, ms, label) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(`timeout after ${ms}ms waiting on ${label}`)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function checkNodeVersion() {
  const major = Number(process.versions.node.split('.')[0]);
  if (Number.isNaN(major)) {
    return check('node:version', 'UNKNOWN', `Could not parse Node version from "${process.versions.node}". Fix: run with a standard Node 18+ build.`);
  }
  if (major >= 18) {
    return check('node:version', 'PASS', `Node ${process.versions.node} (>= 18 required)`);
  }
  return check('node:version', 'FAIL', `Node ${process.versions.node} is < 18. Fix: install Node 18+ (nvm install 18, or your platform's package manager) and re-run.`);
}

async function loadYf() {
  const mod = await import('yahoo-finance2');
  const YahooFinance = mod.default;
  // v3 requires instantiation, matching the house fetch-quote.js pattern.
  const yf = (typeof YahooFinance === 'function') ? new YahooFinance() : YahooFinance;
  if (yf.suppressNotices) yf.suppressNotices(['yahooSurvey', 'ripHistorical']);
  return yf;
}

async function checkYahooImport() {
  try {
    const yf = await loadYf();
    if (!yf || typeof yf.quote !== 'function') {
      return { result: check('yahoo-finance2:import', 'FAIL', 'Module imported but no usable .quote() method found on the instance. Fix: check installed yahoo-finance2 version matches the v3 API shape (npm ls yahoo-finance2).'), yf: null };
    }
    return { result: check('yahoo-finance2:import', 'PASS', 'yahoo-finance2 imported and instantiated'), yf };
  } catch (err) {
    return { result: check('yahoo-finance2:import', 'FAIL', `Import failed: ${err.message}. Fix: run "npm install yahoo-finance2" in the skill directory.`), yf: null };
  }
}

async function checkUsQuote(yf) {
  if (!yf) return check('yahoo:quote:AAPL', 'UNKNOWN', 'Skipped — yahoo-finance2 did not import; cannot test a live quote.');
  try {
    const q = await withTimeout(yf.quote('AAPL'), HTTP_TIMEOUT_MS, 'yf.quote(AAPL)');
    if (q && typeof q.regularMarketPrice === 'number' && q.currency) {
      return check('yahoo:quote:AAPL', 'PASS', `AAPL price=${q.regularMarketPrice} ${q.currency}`);
    }
    return check('yahoo:quote:AAPL', 'FAIL', `Quote returned but missing regularMarketPrice/currency: ${JSON.stringify(q).slice(0, 200)}. Fix: Yahoo response shape may have changed — inspect yf.quote('AAPL') manually.`);
  } catch (err) {
    return check('yahoo:quote:AAPL', 'FAIL', `Live quote failed: ${err.message}. Fix: check network connectivity to query1/query2.finance.yahoo.com and that yahoo-finance2 is not rate-limited (HTTP 429).`);
  }
}

// The currency-critical check. GBp (lowercase p, pence) vs GBP (pounds) is a documented
// 100x sizing error waiting to happen (SKILL.md references/04-global-data.md) — this
// check exists specifically to catch Yahoo silently changing that convention.
async function checkNonUsQuoteCurrency(yf) {
  if (!yf) return check('yahoo:quote:SHEL.L:currency', 'UNKNOWN', 'Skipped — yahoo-finance2 did not import; cannot test a live quote.');
  let q;
  try {
    q = await withTimeout(yf.quote('SHEL.L'), HTTP_TIMEOUT_MS, "yf.quote('SHEL.L')");
  } catch (err) {
    return check('yahoo:quote:SHEL.L:currency', 'FAIL', `Live quote failed: ${err.message}. Fix: check network connectivity to Yahoo Finance; SHEL.L (LSE) is the non-US canary symbol for this skill's minor-unit handling.`);
  }
  if (!q || typeof q.regularMarketPrice !== 'number') {
    return check('yahoo:quote:SHEL.L:currency', 'FAIL', `Quote returned but no regularMarketPrice: ${JSON.stringify(q).slice(0, 200)}. Fix: inspect yf.quote('SHEL.L') manually.`);
  }
  if (!q.currency) {
    return check('yahoo:quote:SHEL.L:currency', 'FAIL', 'No currency field at all on a non-US quote. Currency handling is safety-critical for this skill (GBp/pence vs GBP/pounds is a 100x sizing error). Fix: do NOT proceed — Yahoo\'s currency labeling for LSE names may be broken; re-verify manually before running BUILD or REVIEW.');
  }
  if (q.currency !== 'GBp') {
    return check(
      'yahoo:quote:SHEL.L:currency',
      'FAIL',
      `SHEL.L returned currency="${q.currency}" (price=${q.regularMarketPrice}), NOT the expected "GBp". WARNING: this skill's minor-unit divide-by-100 assumption (references/04-global-data.md, references/08-multi-currency.md) needs RE-VERIFICATION before trusting any LSE-listed sizing math — Yahoo may have changed its convention. Fix: manually inspect several .L-suffixed quotes and confirm whether the minor-unit rule still holds before proceeding.`,
    );
  }
  return check('yahoo:quote:SHEL.L:currency', 'PASS', `SHEL.L currency="GBp" (pence) as expected, price=${q.regularMarketPrice} => £${(q.regularMarketPrice / 100).toFixed(3)}`);
}

function checkCacheDir() {
  try {
    fs.mkdirSync(CACHE_DIR, { recursive: true });
    fs.accessSync(CACHE_DIR, fs.constants.W_OK);
    return check('cache:dir', 'PASS', `${CACHE_DIR} exists and is writable`);
  } catch (err) {
    return check('cache:dir', 'FAIL', `Cannot create/write ${CACHE_DIR}: ${err.message}. Fix: check filesystem permissions on ${os.homedir()}/.cache, or set HOME to a writable directory.`);
  }
}

function checkPortfolioStatePresence() {
  const exists = fs.existsSync(STATE_FILE);
  const hint = exists ? 'REVIEW' : 'BUILD';
  const detail = exists
    ? `${STATE_FILE} present — mode hint: REVIEW (existing book found). Run "bash scripts/state.sh load" first if this looks stale.`
    : `${STATE_FILE} not present — mode hint: BUILD (no existing book). If this is unexpected, run "bash scripts/state.sh load" first — state may not have been restored yet.`;
  // Informational only — presence or absence of prior state is never a failure; the
  // skill itself does mode selection (SKILL.md "Mode selection — do this first, every run").
  return check('state:portfolio-presence', 'PASS', `${detail} [mode hint: ${hint}]`, false);
}

async function checkGitPushCapability() {
  try {
    await execFileAsync('git', ['rev-parse', '--show-toplevel'], { timeout: 5000 });
  } catch {
    return check('git:state-persistence', 'FAIL', 'Not inside a git repository. Fix: run this skill from within the dotfiles repo checkout, or state.sh will not be able to persist portfolio.json/decision-log.jsonl/thesis-registry.json/fx-cache.json across runs — every run will start blind.', false);
  }
  try {
    await execFileAsync('git', ['remote', 'get-url', 'origin'], { timeout: 5000 });
  } catch {
    return check('git:state-persistence', 'FAIL', 'No "origin" remote configured. Fix: add a git remote named origin with push access, or state will not persist across scheduled runs.', false);
  }
  try {
    // Read-only reachability/auth probe. Does NOT push — preflight must not have side
    // effects. A successful ls-remote is a reasonable proxy that the same credentials
    // will support state.sh's later `git push`, but is not a guarantee of write access.
    await execFileAsync('git', ['ls-remote', '--heads', 'origin'], { timeout: 10000 });
    return check('git:state-persistence', 'PASS', 'origin reachable and readable (read access confirmed; push not tested by preflight — state.sh save will surface a push failure explicitly if credentials lack write access)', false);
  } catch (err) {
    return check('git:state-persistence', 'FAIL', `Cannot reach/read origin: ${err.message}. Fix: check network connectivity and git credentials — WARNING: without this, portfolio state will NOT persist across scheduled runs and every run will start blind.`, false);
  }
}

function renderTable(checks) {
  const nameWidth = Math.max(...checks.map((c) => c.name.length));
  console.error('portfolio skill preflight');
  console.error('='.repeat(70));
  for (const c of checks) {
    // UNKNOWN must render distinctly from PASS — never collapse them into one glyph.
    const tag = c.status === 'PASS' ? ' OK ' : c.status === 'FAIL' ? 'FAIL' : 'UNKN';
    const scope = c.critical ? '' : ' (non-critical)';
    console.error(`[${tag}] ${c.name.padEnd(nameWidth)}${scope}  ${c.detail}`);
  }
  console.error('='.repeat(70));
}

async function main() {
  const checks = [];

  checks.push(checkNodeVersion());

  const { result: yahooImportResult, yf } = await checkYahooImport();
  checks.push(yahooImportResult);

  const [usQuote, nonUsQuote] = await Promise.all([
    checkUsQuote(yf),
    checkNonUsQuoteCurrency(yf),
  ]);
  checks.push(usQuote, nonUsQuote);

  checks.push(checkCacheDir());
  checks.push(checkPortfolioStatePresence());
  checks.push(await checkGitPushCapability());

  renderTable(checks);

  // A critical check is a hard failure only if it FAILs or is UNKNOWN — "UNKNOWN is not
  // PASS" (SKILL.md references/06-agent-guardrails.md): an unresolved check must never
  // be silently treated as green.
  const criticalBroken = checks.filter((c) => c.critical && c.status !== 'PASS');
  const ok = criticalBroken.length === 0;

  console.error(ok ? 'ALL CRITICAL CHECKS PASSED — pipeline may proceed.' : 'PREFLIGHT FAILED — fix the issues above before proceeding.');
  console.error('');
  console.error('REMINDER: this script makes no live IBKR calls (MCP tools are not reachable from');
  console.error('Node). Before trusting any IBKR-dependent stage, separately verify IBKR');
  console.error('reachability yourself via the MCP tools (e.g. get_account_summary) — do not');
  console.error('assume connectivity because Yahoo checks above passed.');

  process.stdout.write(JSON.stringify({ ok, checks }, null, 2) + '\n');
  process.exit(ok ? 0 : 1);
}

main().catch((err) => {
  console.error(`FATAL: ${err.message}`);
  process.exit(1);
});
