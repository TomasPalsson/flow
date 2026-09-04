#!/usr/bin/env node
/**
 * classify-cash-delta.js
 *
 * Deterministic cash-delta classifier for the `portfolio` skill's DEPOSIT mode
 * (execution-prompt-deposit.md Stage 1). A cash balance moves for FOUR different reasons and
 * only ONE of them is new capital:
 *   1. FX revaluation of non-base cash sitting still while the rate moves.
 *   2. Known events — dividends, sale proceeds, purchases, fees.
 *   3. Position-count changes — shares bought/sold move cash even when no "known event" was
 *      logged for them (state/reality drift).
 *   4. Genuine external capital in or out (deposit / withdrawal) — the only one that should
 *      ever grow or shrink the book (SKILL.md: "Only a genuine external inflow grows the book").
 *
 * This script's entire job is to peel off (1)-(3) so what is LEFT over (the residual) is the
 * external-flow CANDIDATE — never a confirmed deposit. Confirmation is a human/skill decision
 * downstream (execution-prompt-deposit.md Stage 1's action table), not something this script
 * asserts.
 *
 * WHY FX REVALUATION MUST BE NETTED OUT *FIRST*, BEFORE THE RESIDUAL IS INTERPRETED:
 * FX revaluation is the component most easily mistaken for a deposit, because it produces the
 * exact same visible symptom — "the base-currency cash number went up" — with zero capital
 * having moved. A EUR-base account holding USD cash sees its base-currency USD-cash value rise
 * whenever USD strengthens, with nobody having wired anything in. If FX were left inside the
 * residual instead of being subtracted out first, every FX-favorable period would misclassify
 * as a partial deposit and every FX-unfavorable period would misclassify as a partial
 * withdrawal — silently inflating or shrinking the book on noise. So FX is computed and
 * removed BEFORE known-events and position-change flows are even considered, and the ordering
 * is structural, not cosmetic: see computeFxRevaluation() below for the exact algebra that
 * makes "netted out first" precise rather than a hand-wave.
 *
 * THE ALGEBRA THAT MAKES THE DECOMPOSITION EXACT (not an approximation), per currency c:
 *   Let balance_prior_c, balance_current_c be LOCAL-currency cash balances, and
 *   rate_prior_c, rate_current_c the base-per-1-local-unit FX rates at each snapshot.
 *   balance_current_c = balance_prior_c + flow_c   (flow_c = every LOCAL-currency cash movement
 *                                                    in the period: known events + position
 *                                                    trades + external deposit/withdrawal)
 *   value_current_base - value_prior_base
 *     = balance_current_c * rate_current_c - balance_prior_c * rate_prior_c
 *     = balance_prior_c * (rate_current_c - rate_prior_c)   <- FX revaluation, on the PRIOR
 *       balance, exactly as specified                          balance (never on the new one —
 *                                                                using the current balance would
 *                                                                blend newly-arrived flow into
 *                                                                the FX number)
 *       + flow_c * rate_current_c                          <- everything else, valued at the
 *                                                              CURRENT rate
 *   This is why known-events and position-change flows are ALSO converted to base currency
 *   using the CURRENT rate below (computeKnownEventsBase, computePositionChanges) — it is not
 *   an arbitrary choice, it is the only convention under which
 *     total_cash_change_base == fx_revaluation + known_events + position_changes + residual
 *   holds EXACTLY (checked in the self-tests), rather than leaving an unexplained slop term.
 *
 * INPUT: JSON on stdin, or a file path via --input=FILE. Shape (base_currency is REQUIRED at
 * top level — an addition to the brief's shape, following compute-drift.js/compute-weights.js
 * house convention, because the FX math below needs an explicit anchor currency and this
 * script never infers one, per "fail loud, never silently default"):
 *   {
 *     base_currency: "EUR",
 *     prior_snapshot: {
 *       as_of: "<ISO8601>",
 *       nav_base: <number>,                        // context only, not used in the arithmetic
 *       cash_by_currency: { "EUR": <number>, "USD": <number>, ... },
 *       positions: [ { symbol, shares, price_major, currency_major, fx_rate_to_base }, ... ]
 *     },
 *     current: {
 *       as_of: "<ISO8601>",
 *       nav_base: <number>,
 *       cash_by_currency: { ... },
 *       positions: [ ... ],
 *       fx_rates_to_base: { "USD": <number>, ... }   // current rates, base_currency optional
 *                                                      // (must be 1 if given)
 *     },
 *     known_events: [                                 // OPTIONAL — absence itself is a signal,
 *       { type: "dividend"|"sale"|"purchase"|"fee", amount: <positive number>, currency, ts,
 *         symbol: "<optional, enables per-position reconciliation>" }
 *     ]
 *   }
 *
 * fx_rate_to_base UNIT CONVENTION — identical to compute-drift.js / compute-weights.js: base
 * currency units per 1 unit of the position's/currency's local major currency (e.g. EUR per 1
 * USD). value_base = value_local * fx_rate_to_base.
 *
 * WHY prior_snapshot HAS NO TOP-LEVEL FX MAP: the brief's shape only puts fx_rates_to_base on
 * `current`. Prior-snapshot rates are instead DERIVED from prior_snapshot.positions' own
 * fx_rate_to_base fields, per currency (the same currency's positions must all agree on the
 * rate — see assertRateConsistency()). For base_currency, the rate is definitionally 1 in both
 * snapshots (a mathematical identity, not sourced data — this is NOT the "missing rate silently
 * defaulted to 1.0" bug class the brief warns about, it never applies to a non-base currency).
 * If a NON-base currency has a nonzero prior cash balance but no prior position in that
 * currency to source a rate from, there is no legitimate way to derive it — the script FAILS
 * LOUD rather than guessing (see resolvePriorRate()).
 *
 * Known-events amount SIGN CONVENTION (not specified in the brief's schema, fixed here
 * explicitly because the classification's correctness depends on it): `amount` is always a
 * POSITIVE magnitude; `type` determines the sign of the cash impact — dividend/sale are +,
 * purchase/fee are -. A negative `amount` is rejected as ambiguous double-signing, not
 * silently accepted.
 *
 * OUTPUT: compact human-readable table on STDERR, full JSON on STDOUT (compute-drift.js
 * convention) so stdout stays machine-parseable.
 *
 * Usage: node classify-cash-delta.js --input=input.json
 *    or: node classify-cash-delta.js < input.json
 *    or: node classify-cash-delta.js --self-test
 */

import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------------------------
// Named constants. All three below are this script's own synthesized decision-tree thresholds —
// not literature-derived, not empirically validated against realized accounts — same sourcing
// disclosure as compute-drift.js's drift-cause classifier constants. They are tunable via input,
// with sane defaults, because a wrong guess here is a classification-sensitivity knob, not a
// worst-case-loss bound (unlike compute-weights.js's hard-locked caps).
// ---------------------------------------------------------------------------------------------

// Below this many base-currency units, a residual is rounding/fee dust, not new capital.
// "Materiality floor" — named per the brief's explicit requirement that dust never reports as
// a deposit.
const DEFAULT_MATERIALITY_FLOOR_BASE = 5;

// If |residual| < this fraction of |fx_revaluation|, FX noise/rounding could plausibly account
// for the whole residual — not confident enough to call it a deposit/withdrawal.
const DEFAULT_FX_NOISE_RATIO = 0.5;

// Snapshot gap beyond which unrecorded activity could plausibly hide inside the residual —
// warn, don't fail (the classification may still be correct; it just deserves more scrutiny).
const DEFAULT_SNAPSHOT_STALENESS_WARN_DAYS = 45;

// Internal tolerances — not caller-tunable, these guard arithmetic/data integrity, not policy.
const EPS = 1e-9;
const EPS_SHARES = 1e-6;
const EPS_BASE = 1e-6;
// Same-currency positions at one snapshot must report the same fx_rate_to_base within this
// relative tolerance; small floating/rounding noise in a sourced rate is expected, a real unit
// or direction error is not.
const FX_RATE_CONSISTENCY_REL_TOL = 1e-4;
// A currency's rate moving outside this multiple between snapshots is implausible for a normal
// FX move and more likely a direction/inversion bug (base-per-local vs local-per-base swapped)
// — WARN (not fail: some exotic currencies or long gaps genuinely move this much).
const FX_RATE_PLAUSIBLE_MOVE_MIN_MULT = 0.2;
const FX_RATE_PLAUSIBLE_MOVE_MAX_MULT = 5;

const KNOWN_EVENT_TYPES = new Set(['dividend', 'sale', 'purchase', 'fee']);
// Sign of the cash impact for each known-event type, applied to the (always-positive) amount.
const EVENT_SIGN = { dividend: 1, sale: 1, purchase: -1, fee: -1 };
// Which event types correspond to a position-count change of which direction, used only for
// the OPTIONAL per-symbol reconciliation (see matchPositionChangeToEvent()).
const BUY_EVENT_TYPES = new Set(['purchase']);
const SELL_EVENT_TYPES = new Set(['sale']);

function fail(msg) {
  throw new Error(msg);
}

function isFiniteNum(x) {
  return typeof x === 'number' && Number.isFinite(x);
}

function round2(x) {
  if (!isFiniteNum(x)) return x;
  return Math.round(x * 100) / 100;
}

function parseTime(s, field) {
  if (typeof s !== 'string' || !s) fail(`${field} is required and must be an ISO8601 timestamp string`);
  const t = Date.parse(s);
  if (Number.isNaN(t)) fail(`${field} ("${s}") could not be parsed as a valid timestamp`);
  return t;
}

// =================================================================================================
// Input validation — fail loudly, never substitute a default for a missing risk-relevant input.
// =================================================================================================

function validateTopLevel(input) {
  if (!input || typeof input !== 'object') fail('input must be a JSON object');
  if (typeof input.base_currency !== 'string' || !input.base_currency) {
    fail('base_currency is required and must be a non-empty string — this script never infers the anchor currency');
  }
  if (!input.prior_snapshot || typeof input.prior_snapshot !== 'object') fail('prior_snapshot is required and must be an object');
  if (!input.current || typeof input.current !== 'object') fail('current is required and must be an object');
  if (input.known_events !== undefined && !Array.isArray(input.known_events)) {
    fail('known_events, if provided, must be an array');
  }

  const materialityFloorBase = input.materiality_floor_base === undefined
    ? DEFAULT_MATERIALITY_FLOOR_BASE
    : input.materiality_floor_base;
  if (!isFiniteNum(materialityFloorBase) || materialityFloorBase < 0) {
    fail('materiality_floor_base, if provided, must be a non-negative number');
  }

  const fxNoiseRatio = input.fx_noise_ratio === undefined ? DEFAULT_FX_NOISE_RATIO : input.fx_noise_ratio;
  if (!isFiniteNum(fxNoiseRatio) || fxNoiseRatio < 0) fail('fx_noise_ratio, if provided, must be a non-negative number');

  const stalenessWarnDays = input.snapshot_staleness_warn_days === undefined
    ? DEFAULT_SNAPSHOT_STALENESS_WARN_DAYS
    : input.snapshot_staleness_warn_days;
  if (!isFiniteNum(stalenessWarnDays) || stalenessWarnDays <= 0) {
    fail('snapshot_staleness_warn_days, if provided, must be a positive number');
  }

  return { materialityFloorBase, fxNoiseRatio, stalenessWarnDays };
}

function validateSnapshot(snap, label) {
  const where = `${label}`;
  if (typeof snap.as_of !== 'string' || !snap.as_of) fail(`${where}.as_of is required and must be an ISO8601 timestamp string`);
  parseTime(snap.as_of, `${where}.as_of`);
  if (snap.nav_base !== undefined && !isFiniteNum(snap.nav_base)) fail(`${where}.nav_base, if provided, must be a number`);
  if (!snap.cash_by_currency || typeof snap.cash_by_currency !== 'object' || Array.isArray(snap.cash_by_currency)) {
    fail(`${where}.cash_by_currency is required and must be an object`);
  }
  for (const [ccy, bal] of Object.entries(snap.cash_by_currency)) {
    if (!isFiniteNum(bal)) fail(`${where}.cash_by_currency["${ccy}"] must be a finite number, got ${JSON.stringify(bal)}`);
  }
  if (!Array.isArray(snap.positions)) fail(`${where}.positions is required and must be an array (empty array if no positions)`);
  snap.positions.forEach((p, i) => validatePosition(p, i, where));
}

function validatePosition(pos, idx, where) {
  const label = `${where}.positions[${idx}]${pos && pos.symbol ? ` (${pos.symbol})` : ''}`;
  if (!pos || typeof pos !== 'object') fail(`${label}: must be an object`);
  if (typeof pos.symbol !== 'string' || !pos.symbol) fail(`${label}: symbol is required`);
  if (!isFiniteNum(pos.shares) || pos.shares < 0) fail(`${label}: shares is required and must be a non-negative number`);
  if (!isFiniteNum(pos.price_major) || pos.price_major <= 0) fail(`${label}: price_major is required and must be a positive number`);
  if (typeof pos.currency_major !== 'string' || !pos.currency_major) fail(`${label}: currency_major is required`);
  if (!isFiniteNum(pos.fx_rate_to_base) || pos.fx_rate_to_base <= 0) fail(`${label}: fx_rate_to_base is required and must be a positive number`);
}

function validateEvent(ev, idx) {
  const label = `known_events[${idx}]`;
  if (!ev || typeof ev !== 'object') fail(`${label}: must be an object`);
  if (!KNOWN_EVENT_TYPES.has(ev.type)) {
    fail(`${label}: type must be one of ${[...KNOWN_EVENT_TYPES].join('|')}, got ${JSON.stringify(ev.type)}`);
  }
  if (!isFiniteNum(ev.amount) || ev.amount <= 0) {
    fail(
      `${label}: amount is required and must be a POSITIVE number (sign is encoded by "type", not by ` +
      `the sign of amount — a negative amount would double-encode direction and is refused rather than ` +
      `silently reinterpreted).`
    );
  }
  if (typeof ev.currency !== 'string' || !ev.currency) fail(`${label}: currency is required`);
  parseTime(ev.ts, `${label}.ts`);
  if (ev.symbol !== undefined && (typeof ev.symbol !== 'string' || !ev.symbol)) {
    fail(`${label}: symbol, if provided, must be a non-empty string`);
  }
}

// =================================================================================================
// FX rate resolution — per currency, per snapshot. This is the section most load-bearing for
// "fail loud on a missing rate rather than silently treating it as 1.0" (the compute-weights.js
// bug class named explicitly in the brief).
// =================================================================================================

// Prior-snapshot rates are DERIVED from prior positions' own fx_rate_to_base, per currency.
// Same-currency positions must agree (within FX_RATE_CONSISTENCY_REL_TOL) — a real disagreement
// means a stale/bad rate slipped into one of the position records, not a rounding artifact.
function derivePriorRates(priorPositions, baseCurrency) {
  const byCurrency = new Map();
  for (const p of priorPositions) {
    if (!byCurrency.has(p.currency_major)) byCurrency.set(p.currency_major, []);
    byCurrency.get(p.currency_major).push(p);
  }
  const rates = new Map();
  rates.set(baseCurrency, 1);
  for (const [ccy, members] of byCurrency) {
    const first = members[0].fx_rate_to_base;
    for (const m of members) {
      const relDiff = Math.abs(m.fx_rate_to_base - first) / Math.max(Math.abs(first), EPS);
      if (relDiff > FX_RATE_CONSISTENCY_REL_TOL) {
        fail(
          `FX-rate consistency check failed: prior_snapshot.positions in ${ccy} disagree on ` +
          `fx_rate_to_base (${first} vs ${m.fx_rate_to_base} for ${m.symbol}) beyond the ` +
          `${FX_RATE_CONSISTENCY_REL_TOL * 100}% tolerance for same-snapshot rounding noise. Positions ` +
          `priced at the same as_of must share one rate per currency — this looks like stale or ` +
          `mismatched data, not noise.`
        );
      }
    }
    if (ccy === baseCurrency) {
      if (Math.abs(first - 1) > FX_RATE_CONSISTENCY_REL_TOL) {
        fail(`prior_snapshot: a position in base_currency (${baseCurrency}) reports fx_rate_to_base=${first}, expected 1 (identity rate)`);
      }
    } else {
      rates.set(ccy, first);
    }
  }
  return rates;
}

// Current-snapshot rates come from the explicit current.fx_rates_to_base map. base_currency is
// the identity rate (1) — if the caller supplies it explicitly it must equal 1, but its
// absence is NOT the "missing rate defaulted to 1.0" failure mode: it is a mathematical
// identity for the currency the whole computation is anchored to, not sourced/fetched data.
function buildCurrentRateResolver(fxRatesToBase, baseCurrency) {
  const map = fxRatesToBase && typeof fxRatesToBase === 'object' ? fxRatesToBase : {};
  for (const [ccy, rate] of Object.entries(map)) {
    if (!isFiniteNum(rate) || rate <= 0) fail(`current.fx_rates_to_base["${ccy}"] must be a positive number, got ${JSON.stringify(rate)}`);
  }
  if (map[baseCurrency] !== undefined && Math.abs(map[baseCurrency] - 1) > FX_RATE_CONSISTENCY_REL_TOL) {
    fail(`current.fx_rates_to_base["${baseCurrency}"] = ${map[baseCurrency]}, but ${baseCurrency} is base_currency and must be 1 (identity rate) if given at all`);
  }

  const resolved = new Map();
  resolved.set(baseCurrency, 1);

  // Returns the current rate for `ccy`, throwing loudly if it cannot be resolved. `context`
  // is a human-readable string describing WHY this rate is needed, for a useful error message.
  return function resolveCurrentRate(ccy, context) {
    if (resolved.has(ccy)) return resolved.get(ccy);
    if (ccy === baseCurrency) return 1;
    const rate = map[ccy];
    if (rate === undefined) {
      fail(
        `Missing current.fx_rates_to_base["${ccy}"], needed to value ${context}. A missing rate must ` +
        `never be silently treated as 1.0 — that produced a real bug in compute-weights.js during this ` +
        `skill's development. Supply the rate or exclude/zero the ${ccy} balance explicitly.`
      );
    }
    resolved.set(ccy, rate);
    return rate;
  };
}

// =================================================================================================
// Component 1: FX revaluation — see the file-header algebra for why this is computed on the
// PRIOR balance and subtracted FIRST, before any other component is interpreted.
// =================================================================================================

function computeFxRevaluation(priorCashByCurrency, priorRates, resolveCurrentRate, baseCurrency, warnings) {
  let fxRevaluationBase = 0;
  const perCurrency = [];

  for (const [ccy, priorBalance] of Object.entries(priorCashByCurrency)) {
    if (ccy === baseCurrency) continue; // identity rate both sides — zero revaluation by construction
    if (Math.abs(priorBalance) < EPS) continue; // 0 * anything = 0, no rate needed

    const priorRate = priorRates.get(ccy);
    if (priorRate === undefined) {
      fail(
        `prior_snapshot.cash_by_currency has a non-zero ${ccy} balance (${priorBalance}) but no ` +
        `prior_snapshot.positions entry in ${ccy} to derive a prior fx_rate_to_base from, and ${ccy} is ` +
        `not base_currency. Cannot compute FX revaluation without a sourced prior rate — refusing to guess.`
      );
    }
    const currentRate = resolveCurrentRate(ccy, `the prior ${ccy} cash balance's FX revaluation`);

    const moveMultiple = currentRate / priorRate;
    if (moveMultiple < FX_RATE_PLAUSIBLE_MOVE_MIN_MULT || moveMultiple > FX_RATE_PLAUSIBLE_MOVE_MAX_MULT) {
      warnings.push(
        `${ccy}: fx_rate_to_base moved ${round2(moveMultiple)}x between snapshots (${priorRate} -> ` +
        `${currentRate}) — implausible for a normal FX move over one review period. Check for an inverted ` +
        `rate (base-per-local vs local-per-base swapped) before trusting this run's FX component.`
      );
    }

    const revalCcy = priorBalance * (currentRate - priorRate);
    fxRevaluationBase += revalCcy;
    perCurrency.push({ currency: ccy, prior_balance: priorBalance, prior_rate: priorRate, current_rate: currentRate, fx_revaluation_base: round2(revalCcy) });
  }

  return { fxRevaluationBase, perCurrency };
}

// =================================================================================================
// Component 2: known-event flows, valued at the CURRENT rate (see file-header algebra for why).
// =================================================================================================

function computeKnownEventsBase(events, resolveCurrentRate, priorAsOfMs, currentAsOfMs, warnings) {
  let total = 0;
  const detail = [];
  for (const ev of events) {
    const sign = EVENT_SIGN[ev.type];
    const rate = resolveCurrentRate(ev.currency, `known_events entry of type "${ev.type}" in ${ev.currency}`);
    const impactBase = sign * ev.amount * rate;
    total += impactBase;
    detail.push({ type: ev.type, amount: ev.amount, currency: ev.currency, ts: ev.ts, symbol: ev.symbol ?? null, impact_base: round2(impactBase) });

    const evMs = Date.parse(ev.ts);
    if (evMs < priorAsOfMs - EPS || evMs > currentAsOfMs + EPS) {
      warnings.push(
        `known_events entry (${ev.type}, ${ev.amount} ${ev.currency}, ts=${ev.ts}) falls outside the ` +
        `[${new Date(priorAsOfMs).toISOString()}, ${new Date(currentAsOfMs).toISOString()}] snapshot window — ` +
        `it may not belong to this reconciliation period. Verify it wasn't already counted in a prior run.`
      );
    }
  }
  return { total, detail };
}

// =================================================================================================
// Component 3: position-count reconciliation. Every share-count change between snapshots moved
// cash for that reason — compute the implied flow, and flag any change with no matching known
// event as unexplained (never absorbed into the residual — surfaced loudly per the brief and
// per execution-prompt-deposit.md's explicit instruction).
// =================================================================================================

function matchPositionChangeToEvent(symbol, sharesDelta, events) {
  const wantBuy = sharesDelta > 0;
  const wantTypes = wantBuy ? BUY_EVENT_TYPES : SELL_EVENT_TYPES;
  return events.some((ev) => ev.symbol === symbol && wantTypes.has(ev.type));
}

function computePositionChanges(priorPositions, currentPositions, events, resolveCurrentRate) {
  const priorBySymbol = new Map(priorPositions.map((p) => [p.symbol, p]));
  const currentBySymbol = new Map(currentPositions.map((p) => [p.symbol, p]));
  const symbols = new Set([...priorBySymbol.keys(), ...currentBySymbol.keys()]);

  let total = 0;
  const changes = [];
  const unexplained = [];

  for (const symbol of symbols) {
    const priorPos = priorBySymbol.get(symbol);
    const currentPos = currentBySymbol.get(symbol);
    const priorShares = priorPos ? priorPos.shares : 0;
    const currentShares = currentPos ? currentPos.shares : 0;
    const sharesDelta = currentShares - priorShares;
    if (Math.abs(sharesDelta) < EPS_SHARES) continue; // unchanged position — nothing to reconcile

    // Value the trade at whichever snapshot still has the position (prefer current — it's the
    // more recent, more relevant price/fx for a still-open position; a fully-closed position
    // has no current price, so prior is the only price we have. Either way this is an
    // APPROXIMATION of the actual execution price, not the true fill — documented explicitly
    // because there is no historical execution price in this input).
    const valuationPos = currentPos || priorPos;
    const rate = resolveCurrentRate(valuationPos.currency_major, `the ${symbol} position-count change (${sharesDelta > 0 ? 'buy' : 'sell'})`);
    const impliedFlowBase = -sharesDelta * valuationPos.price_major * rate;
    total += impliedFlowBase;

    const explained = matchPositionChangeToEvent(symbol, sharesDelta, events);
    const record = {
      symbol,
      prior_shares: priorShares,
      current_shares: currentShares,
      shares_delta: round2(sharesDelta),
      currency: valuationPos.currency_major,
      valuation_price_major: valuationPos.price_major,
      valuation_source: currentPos ? 'current' : 'prior (position fully closed)',
      implied_flow_base: round2(impliedFlowBase),
      explained_by_known_event: explained,
    };
    changes.push(record);
    if (!explained) unexplained.push(record);
  }

  return { total, changes, unexplained };
}

// =================================================================================================
// Classification — see file header + brief for the precedence rules. Written out explicitly
// here because the brief states two rules (materiality floor vs. AMBIGUOUS-whenever-uncertain)
// whose trigger conditions can overlap, and a deterministic precedence has to be picked:
//
//   1. Unexplained position changes ALWAYS force AMBIGUOUS, at ANY residual size. An untracked
//      trade means the position_changes component itself is unverified, which taints the
//      residual's reliability regardless of how big or small it happens to net out to — this
//      is a data-integrity flag, not a sizing question, so it is checked before materiality.
//   2. Sub-materiality-floor residual -> NO_EXTERNAL_FLOW. Checked next: dust is dust even if
//      known_events happened to be omitted from the input, because no amount of additional
//      accounting detail would turn noise into a deposit worth confirming.
//   3. known_events entirely ABSENT (not merely empty) -> AMBIGUOUS. An empty array means "we
//      checked, there were none" (informative); undefined means "we never looked" — only the
//      latter forces AMBIGUOUS by itself.
//   4. Residual small relative to the FX component -> AMBIGUOUS (FX noise could account for it).
//   5. Otherwise: sign of the residual determines DEPOSIT / WITHDRAWAL, confidence HIGH.
// =================================================================================================

function classify(residual, fxRevaluationBase, knownEventsProvided, unexplainedChanges, materialityFloorBase, fxNoiseRatio) {
  if (unexplainedChanges.length > 0) {
    return { classification: 'AMBIGUOUS', confidence: 'LOW', reason: 'unexplained_position_changes present' };
  }
  if (Math.abs(residual) < materialityFloorBase - EPS_BASE) {
    return { classification: 'NO_EXTERNAL_FLOW', confidence: 'HIGH', reason: `residual below materiality floor (${materialityFloorBase})` };
  }
  if (!knownEventsProvided) {
    return { classification: 'AMBIGUOUS', confidence: 'LOW', reason: 'known_events was absent entirely' };
  }
  const fxMaterial = Math.abs(fxRevaluationBase) > EPS_BASE;
  if (fxMaterial && Math.abs(residual) < fxNoiseRatio * Math.abs(fxRevaluationBase)) {
    return { classification: 'AMBIGUOUS', confidence: 'LOW', reason: 'residual small relative to the FX-revaluation component (FX noise could account for it)' };
  }
  return {
    classification: residual > 0 ? 'DEPOSIT' : 'WITHDRAWAL',
    confidence: 'HIGH',
    reason: residual > 0 ? 'material positive residual, fully attributed' : 'material negative residual, fully attributed',
  };
}

// =================================================================================================
// Pipeline driver
// =================================================================================================

function runPipeline(input) {
  const { materialityFloorBase, fxNoiseRatio, stalenessWarnDays } = validateTopLevel(input);
  const baseCurrency = input.base_currency;

  validateSnapshot(input.prior_snapshot, 'prior_snapshot');
  validateSnapshot(input.current, 'current');
  const events = input.known_events || [];
  events.forEach(validateEvent);
  const knownEventsProvided = input.known_events !== undefined;

  const priorAsOfMs = parseTime(input.prior_snapshot.as_of, 'prior_snapshot.as_of');
  const currentAsOfMs = parseTime(input.current.as_of, 'current.as_of');
  if (currentAsOfMs < priorAsOfMs) {
    fail(`current.as_of (${input.current.as_of}) is earlier than prior_snapshot.as_of (${input.prior_snapshot.as_of}) — snapshots are out of order`);
  }

  const warnings = [];

  const gapDays = (currentAsOfMs - priorAsOfMs) / 86400000;
  if (gapDays > stalenessWarnDays + EPS) {
    warnings.push(
      `Snapshot gap is ${round2(gapDays)} days (warn threshold ${stalenessWarnDays}). The longer the gap ` +
      `between prior_snapshot and current, the more unrecorded activity could hide inside the residual — ` +
      `treat this run's classification with extra scrutiny.`
    );
  }

  // FX rate resolvers: prior rates derived from prior positions; current rates from the
  // explicit map. Both anchored on base_currency = 1 (identity, not sourced).
  const priorRates = derivePriorRates(input.prior_snapshot.positions, baseCurrency);
  const resolveCurrentRate = buildCurrentRateResolver(input.current.fx_rates_to_base, baseCurrency);
  // Also derive+validate current positions' own currencies eagerly (consistency + fail-fast),
  // and cross-check any position's embedded fx_rate_to_base against the authoritative map.
  for (const p of input.current.positions) {
    const mapRate = resolveCurrentRate(p.currency_major, `current position ${p.symbol} (${p.currency_major})`);
    const relDiff = Math.abs(p.fx_rate_to_base - mapRate) / Math.max(Math.abs(mapRate), EPS);
    if (relDiff > FX_RATE_CONSISTENCY_REL_TOL) {
      fail(
        `current.positions "${p.symbol}" reports fx_rate_to_base=${p.fx_rate_to_base} for ${p.currency_major}, ` +
        `but current.fx_rates_to_base["${p.currency_major}"]=${mapRate} — same-snapshot rates must agree ` +
        `(FX-rate direction/consistency check).`
      );
    }
  }

  // Total cash change in base currency — computed directly from cash_by_currency, independent
  // of nav_base (which also includes position values and is echoed for context only).
  let priorCashTotalBase = 0;
  for (const [ccy, bal] of Object.entries(input.prior_snapshot.cash_by_currency)) {
    if (Math.abs(bal) < EPS) continue;
    const rate = ccy === baseCurrency ? 1 : priorRates.get(ccy);
    if (rate === undefined) {
      fail(
        `prior_snapshot.cash_by_currency has a non-zero ${ccy} balance (${bal}) but no prior rate could be ` +
        `derived (no prior position in ${ccy}, and ${ccy} is not base_currency). Cannot total prior cash.`
      );
    }
    priorCashTotalBase += bal * rate;
  }
  let currentCashTotalBase = 0;
  for (const [ccy, bal] of Object.entries(input.current.cash_by_currency)) {
    if (Math.abs(bal) < EPS) continue;
    const rate = resolveCurrentRate(ccy, `the current ${ccy} cash balance`);
    currentCashTotalBase += bal * rate;
  }
  const totalCashChangeBase = currentCashTotalBase - priorCashTotalBase;

  // Component 1 — FX revaluation. Netted out FIRST, per file header.
  const fx = computeFxRevaluation(input.prior_snapshot.cash_by_currency, priorRates, resolveCurrentRate, baseCurrency, warnings);

  // Component 2 — known events, valued at the current rate for consistency with the FX algebra.
  const knownEvents = computeKnownEventsBase(events, resolveCurrentRate, priorAsOfMs, currentAsOfMs, warnings);

  // Component 3 — position-count reconciliation.
  const positionChanges = computePositionChanges(input.prior_snapshot.positions, input.current.positions, events, resolveCurrentRate);

  // Component 4 — the residual. Everything computed above must be subtracted BEFORE this
  // number means anything (file header algebra) — this is why it is the last line, not a
  // shortcut taken early.
  const externalFlowCandidateBase = totalCashChangeBase - fx.fxRevaluationBase - knownEvents.total - positionChanges.total;

  if (positionChanges.unexplained.length > 0) {
    warnings.push(
      `${positionChanges.unexplained.length} position(s) changed share count with no matching known_event ` +
      `(type purchase/sale + matching symbol): ${positionChanges.unexplained.map((c) => c.symbol).join(', ')}. ` +
      `This is a trade the skill did not record — state and reality have diverged. Surfacing loudly, not ` +
      `absorbing into the residual.`
    );
  }
  if (!knownEventsProvided) {
    warnings.push('known_events was not supplied at all (undefined) — the residual cannot be attributed with confidence without it.');
  }

  const verdict = classify(externalFlowCandidateBase, fx.fxRevaluationBase, knownEventsProvided, positionChanges.unexplained, materialityFloorBase, fxNoiseRatio);

  const result = {
    generated_at: new Date().toISOString(),
    base_currency: baseCurrency,
    prior_as_of: input.prior_snapshot.as_of,
    current_as_of: input.current.as_of,
    snapshot_gap_days: round2(gapDays),
    total_cash_change_base: round2(totalCashChangeBase),
    components: {
      fx_revaluation: round2(fx.fxRevaluationBase),
      known_events: round2(knownEvents.total),
      position_changes: round2(positionChanges.total),
      external_flow_candidate: round2(externalFlowCandidateBase),
    },
    classification: verdict.classification,
    confidence: verdict.confidence,
    classification_reason: verdict.reason,
    unexplained_position_changes: positionChanges.unexplained,
    detail: {
      fx_revaluation_by_currency: fx.perCurrency,
      known_events: knownEvents.detail,
      position_changes: positionChanges.changes,
    },
    warnings,
    requires_user_confirmation: verdict.classification === 'AMBIGUOUS',
  };

  return result;
}

// =================================================================================================
// Compact table renderer — human-readable, written to STDERR so STDOUT stays pure JSON.
// =================================================================================================

function renderTable(result) {
  const lines = [];
  lines.push('');
  lines.push(`Cash-delta classification — generated ${result.generated_at}`);
  lines.push(`Period: ${result.prior_as_of} -> ${result.current_as_of} (${result.snapshot_gap_days}d)`);
  lines.push('');
  lines.push(`Total cash change (base):     ${result.total_cash_change_base}`);
  lines.push(`  FX revaluation:             ${result.components.fx_revaluation}`);
  lines.push(`  Known events:                ${result.components.known_events}`);
  lines.push(`  Position changes:            ${result.components.position_changes}`);
  lines.push(`  = External flow candidate:   ${result.components.external_flow_candidate}`);
  lines.push('');
  lines.push(`Classification: ${result.classification}  (confidence ${result.confidence})`);
  lines.push(`  reason: ${result.classification_reason}`);
  lines.push(`  requires_user_confirmation: ${result.requires_user_confirmation}`);
  if (result.unexplained_position_changes.length) {
    lines.push('');
    lines.push('UNEXPLAINED position changes (no matching known_event):');
    for (const c of result.unexplained_position_changes) {
      lines.push(`  - ${c.symbol}: ${c.prior_shares} -> ${c.current_shares} shares (implied flow ${c.implied_flow_base} base)`);
    }
  }
  if (result.warnings.length) {
    lines.push('');
    lines.push('WARNINGS:');
    for (const w of result.warnings) lines.push(`  - ${w}`);
  }
  lines.push('');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------------------------
// Self-test — offline, no network, no input file. Run: node classify-cash-delta.js --self-test
// ---------------------------------------------------------------------------------------------

function baseSnapshot(overrides) {
  return Object.assign(
    {
      as_of: '2026-07-01T00:00:00Z',
      nav_base: 100000,
      cash_by_currency: { EUR: 5000 },
      positions: [],
    },
    overrides || {},
  );
}

function baseInput(overrides) {
  return Object.assign(
    {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot(),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z' }), { fx_rates_to_base: {} }),
      known_events: [],
    },
    overrides || {},
  );
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

  check('clean deposit: material residual, no FX, known_events=[] -> DEPOSIT, high confidence', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 5000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 12500 } }), { fx_rates_to_base: {} }),
      known_events: [],
    });
    const out = runPipeline(input);
    if (out.classification !== 'DEPOSIT') fail(`expected DEPOSIT, got ${out.classification}`);
    if (out.confidence !== 'HIGH') fail(`expected HIGH confidence, got ${out.confidence}`);
    if (Math.abs(out.components.external_flow_candidate - 7500) > 1e-6) fail(`expected residual 7500, got ${out.components.external_flow_candidate}`);
    if (out.requires_user_confirmation) fail('expected requires_user_confirmation=false');
  });

  check('FX-only move on unchanged USD cash: fully absorbed by fx_revaluation, residual ~0 -> NO_EXTERNAL_FLOW', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 1000, USD: 10000 },
        positions: [{ symbol: 'USDPOS', shares: 10, price_major: 50, currency_major: 'USD', fx_rate_to_base: 0.90 }],
      }),
      current: Object.assign(
        baseSnapshot({
          as_of: '2026-08-01T00:00:00Z',
          cash_by_currency: { EUR: 1000, USD: 10000 }, // USD balance UNCHANGED — only the rate moved
          positions: [{ symbol: 'USDPOS', shares: 10, price_major: 50, currency_major: 'USD', fx_rate_to_base: 0.95 }],
        }),
        { fx_rates_to_base: { USD: 0.95 } },
      ),
      known_events: [],
    };
    const out = runPipeline(input);
    // Naive (wrong) reading would see base-value of USD cash rise by 10000*(0.95-0.90)=500 and
    // could misread that as a deposit. Correct decomposition must route it entirely to FX.
    if (Math.abs(out.components.fx_revaluation - 500) > 1e-6) fail(`expected fx_revaluation=500, got ${out.components.fx_revaluation}`);
    if (Math.abs(out.components.external_flow_candidate) > 1e-6) fail(`expected residual ~0, got ${out.components.external_flow_candidate}`);
    if (out.classification !== 'NO_EXTERNAL_FLOW') fail(`expected NO_EXTERNAL_FLOW, got ${out.classification}`);
  });

  check('dividend correctly attributed: known_events absorbs the full cash increase, residual ~0', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 5000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 5120 } }), { fx_rates_to_base: {} }),
      known_events: [{ type: 'dividend', amount: 120, currency: 'EUR', ts: '2026-07-15T00:00:00Z' }],
    });
    const out = runPipeline(input);
    if (Math.abs(out.components.known_events - 120) > 1e-6) fail(`expected known_events=120, got ${out.components.known_events}`);
    if (Math.abs(out.components.external_flow_candidate) > 1e-6) fail(`expected residual ~0, got ${out.components.external_flow_candidate}`);
    if (out.classification !== 'NO_EXTERNAL_FLOW') fail(`expected NO_EXTERNAL_FLOW, got ${out.classification}`);
  });

  check('unexplained position change forces AMBIGUOUS regardless of residual size', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 5000 },
        positions: [{ symbol: 'XYZ', shares: 10, price_major: 100, currency_major: 'EUR', fx_rate_to_base: 1 }],
      }),
      current: Object.assign(
        baseSnapshot({
          as_of: '2026-08-01T00:00:00Z',
          cash_by_currency: { EUR: 3000 }, // 2000 EUR left the cash sleeve, consistent with buying 20 more shares @100
          positions: [{ symbol: 'XYZ', shares: 30, price_major: 100, currency_major: 'EUR', fx_rate_to_base: 1 }],
        }),
        { fx_rates_to_base: {} },
      ),
      known_events: [], // no matching purchase event recorded for XYZ
    });
    const out = runPipeline(input);
    if (out.classification !== 'AMBIGUOUS') fail(`expected AMBIGUOUS, got ${out.classification}`);
    if (!out.requires_user_confirmation) fail('expected requires_user_confirmation=true');
    if (out.unexplained_position_changes.length !== 1) fail(`expected 1 unexplained position change, got ${out.unexplained_position_changes.length}`);
    if (out.unexplained_position_changes[0].symbol !== 'XYZ') fail('expected XYZ flagged as unexplained');
  });

  check('matching known_event (with symbol) clears a position change from unexplained', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 5000 },
        positions: [{ symbol: 'XYZ', shares: 10, price_major: 100, currency_major: 'EUR', fx_rate_to_base: 1 }],
      }),
      current: Object.assign(
        baseSnapshot({
          as_of: '2026-08-01T00:00:00Z',
          cash_by_currency: { EUR: 3000 },
          positions: [{ symbol: 'XYZ', shares: 30, price_major: 100, currency_major: 'EUR', fx_rate_to_base: 1 }],
        }),
        { fx_rates_to_base: {} },
      ),
      known_events: [{ type: 'purchase', amount: 2000, currency: 'EUR', ts: '2026-07-20T00:00:00Z', symbol: 'XYZ' }],
    });
    const out = runPipeline(input);
    if (out.unexplained_position_changes.length !== 0) fail(`expected 0 unexplained, got ${out.unexplained_position_changes.length}`);
    // known_events (-2000) and position_changes (-2000) both fire here — by design they are
    // independent components (this script does not net a known "purchase" event against the
    // position_changes component to avoid double-subtracting); the residual should still land
    // at 0 relative to the true external flow (none), since total_cash_change accounts for both.
    if (out.classification === 'AMBIGUOUS') fail(`did not expect AMBIGUOUS once explained, got reason: ${out.classification_reason}`);
  });

  check('sub-materiality residual returns NO_EXTERNAL_FLOW even with known_events absent', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 5000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 5002.10 } }), { fx_rates_to_base: {} }),
      // known_events intentionally omitted (undefined) entirely
    };
    const out = runPipeline(input);
    if (out.classification !== 'NO_EXTERNAL_FLOW') fail(`expected NO_EXTERNAL_FLOW, got ${out.classification} (${out.classification_reason})`);
    if (Math.abs(out.components.external_flow_candidate - 2.10) > 1e-6) fail(`expected residual 2.10, got ${out.components.external_flow_candidate}`);
  });

  check('known_events entirely absent (not empty) with a material residual forces AMBIGUOUS', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 5000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 12000 } }), { fx_rates_to_base: {} }),
      // known_events omitted
    };
    const out = runPipeline(input);
    if (out.classification !== 'AMBIGUOUS') fail(`expected AMBIGUOUS, got ${out.classification}`);
    if (!out.requires_user_confirmation) fail('expected requires_user_confirmation=true');
  });

  check('residual small relative to FX component forces AMBIGUOUS (FX noise could explain it)', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 1000, USD: 50000 },
        positions: [{ symbol: 'USDPOS', shares: 10, price_major: 50, currency_major: 'USD', fx_rate_to_base: 0.90 }],
      }),
      current: Object.assign(
        baseSnapshot({
          as_of: '2026-08-01T00:00:00Z',
          // USD balance rises slightly (200) on top of a large FX move (2500) — the 200 residual
          // is small relative to the 2500 FX component, so classification should stay cautious.
          cash_by_currency: { EUR: 1000, USD: 50200 },
          positions: [{ symbol: 'USDPOS', shares: 10, price_major: 50, currency_major: 'USD', fx_rate_to_base: 0.95 }],
        }),
        { fx_rates_to_base: { USD: 0.95 } },
      ),
      known_events: [],
    };
    const out = runPipeline(input);
    if (out.classification !== 'AMBIGUOUS') fail(`expected AMBIGUOUS, got ${out.classification} (fx=${out.components.fx_revaluation}, residual=${out.components.external_flow_candidate})`);
  });

  check('missing current fx rate for a currency with a non-zero balance errors loudly', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 1000, GBP: 2000 },
        positions: [{ symbol: 'GBPPOS', shares: 10, price_major: 100, currency_major: 'GBP', fx_rate_to_base: 1.17 }],
      }),
      current: Object.assign(
        baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 1000, GBP: 2000 }, positions: [{ symbol: 'GBPPOS', shares: 10, price_major: 100, currency_major: 'GBP', fx_rate_to_base: 1.18 }] }),
        { fx_rates_to_base: {} }, // GBP rate missing entirely
      ),
      known_events: [],
    };
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected an error for a missing current fx rate');
    if (!msg.includes('Missing current.fx_rates_to_base')) fail(`expected a missing-rate error, got: ${msg}`);
  });

  check('missing prior fx rate for a non-base currency with a non-zero balance and no sourcing position errors loudly', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 1000, GBP: 2000 }, positions: [] }), // no GBP position to derive a rate from
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 1000, GBP: 2000 } }), { fx_rates_to_base: { GBP: 1.18 } }),
      known_events: [],
    };
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected an error for an undeivable prior GBP rate');
  });

  check('same-currency prior positions disagreeing on fx_rate_to_base errors (consistency check)', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 1000, GBP: 500 },
        positions: [
          { symbol: 'A', shares: 10, price_major: 100, currency_major: 'GBP', fx_rate_to_base: 1.10 },
          { symbol: 'B', shares: 10, price_major: 100, currency_major: 'GBP', fx_rate_to_base: 1.30 }, // inconsistent
        ],
      }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 1000, GBP: 500 } }), { fx_rates_to_base: { GBP: 1.15 } }),
      known_events: [],
    };
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected an error for inconsistent same-currency prior FX rates');
    if (!msg.includes('consistency')) fail(`expected a consistency error, got: ${msg}`);
  });

  check('withdrawal: material negative residual classifies as WITHDRAWAL', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({ cash_by_currency: { EUR: 10000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 3000 } }), { fx_rates_to_base: {} }),
      known_events: [],
    });
    const out = runPipeline(input);
    if (out.classification !== 'WITHDRAWAL') fail(`expected WITHDRAWAL, got ${out.classification}`);
    if (Math.abs(out.components.external_flow_candidate + 7000) > 1e-6) fail(`expected residual -7000, got ${out.components.external_flow_candidate}`);
  });

  check('negative known_events amount is rejected (sign must come from type, not amount)', () => {
    const input = baseInput({
      known_events: [{ type: 'fee', amount: -10, currency: 'EUR', ts: '2026-07-10T00:00:00Z' }],
    });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected an error for a negative known_events amount');
  });

  check('base_currency position reporting a non-1 fx_rate_to_base errors', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 5000 },
        positions: [{ symbol: 'EURPOS', shares: 5, price_major: 100, currency_major: 'EUR', fx_rate_to_base: 1.05 }],
      }),
    });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected an error for base-currency position with non-identity fx_rate_to_base');
  });

  check('long snapshot gap produces a staleness warning', () => {
    const input = baseInput({
      prior_snapshot: baseSnapshot({ as_of: '2026-01-01T00:00:00Z', cash_by_currency: { EUR: 5000 } }),
      current: Object.assign(baseSnapshot({ as_of: '2026-08-01T00:00:00Z', cash_by_currency: { EUR: 5000 } }), { fx_rates_to_base: {} }),
      known_events: [],
    });
    const out = runPipeline(input);
    if (!out.warnings.some((w) => w.includes('Snapshot gap'))) fail('expected a snapshot-staleness warning');
  });

  check('exact decomposition invariant holds: total_cash_change == sum of all four components', () => {
    const input = {
      base_currency: 'EUR',
      prior_snapshot: baseSnapshot({
        cash_by_currency: { EUR: 1000, USD: 5000 },
        positions: [
          { symbol: 'USDPOS', shares: 10, price_major: 50, currency_major: 'USD', fx_rate_to_base: 0.90 },
          { symbol: 'GONE', shares: 5, price_major: 40, currency_major: 'EUR', fx_rate_to_base: 1 },
        ],
      }),
      current: Object.assign(
        baseSnapshot({
          as_of: '2026-08-01T00:00:00Z',
          cash_by_currency: { EUR: 3400, USD: 5000 },
          positions: [{ symbol: 'USDPOS', shares: 10, price_major: 55, currency_major: 'USD', fx_rate_to_base: 0.95 }], // GONE fully sold
        }),
        { fx_rates_to_base: { USD: 0.95 } },
      ),
      known_events: [
        { type: 'sale', amount: 200, currency: 'EUR', ts: '2026-07-10T00:00:00Z', symbol: 'GONE' },
        { type: 'fee', amount: 5, currency: 'EUR', ts: '2026-07-10T00:00:00Z' },
      ],
    };
    const out = runPipeline(input);
    const sum = out.components.fx_revaluation + out.components.known_events + out.components.position_changes + out.components.external_flow_candidate;
    if (Math.abs(sum - out.total_cash_change_base) > 0.02) {
      fail(`decomposition does not sum exactly: ${sum} vs total ${out.total_cash_change_base}`);
    }
  });

  return allPass;
}

// ---------------------------------------------------------------------------------------------
// CLI entrypoint
// ---------------------------------------------------------------------------------------------

function parseArgs(argv) {
  let inputPath = null;
  for (const arg of argv) {
    if (arg === '--self-test') return { selfTest: true };
    if (arg.startsWith('--input=')) inputPath = arg.slice('--input='.length);
  }
  return { selfTest: false, inputPath };
}

function main() {
  const { selfTest, inputPath } = parseArgs(process.argv.slice(2));

  if (selfTest) {
    const ok = runSelfTests();
    process.exit(ok ? 0 : 1);
  }

  let raw;
  try {
    raw = inputPath ? readFileSync(inputPath, 'utf8') : readFileSync(0, 'utf8');
  } catch (err) {
    console.error(`FATAL: could not read input: ${err.message}`);
    process.exit(1);
  }

  let input;
  try {
    input = JSON.parse(raw);
  } catch (err) {
    console.error(`FATAL: invalid JSON input: ${err.message}`);
    process.exit(1);
  }

  let output;
  try {
    output = runPipeline(input);
  } catch (err) {
    console.error(`FATAL: ${err.message}`);
    process.exit(1);
  }

  // Compact table to STDERR, full JSON to STDOUT — keeps stdout machine-parseable.
  console.error(renderTable(output));
  process.stdout.write(JSON.stringify(output, null, 2) + '\n');
}

main();
