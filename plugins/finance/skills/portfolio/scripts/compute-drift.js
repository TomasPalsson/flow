#!/usr/bin/env node
/**
 * compute-drift.js
 *
 * Deterministic weekly/monthly/quarterly drift + return-attribution pipeline for a
 * concentrated 5-10 name global equity book. This script is the AUTHORITATIVE source for
 * current weights, drift-vs-target, local/FX return decomposition, and drift-cause
 * classification — the calling skill must never compose this arithmetic in prose
 * (references/03-review-doctrine.md; references/08-multi-currency.md §§3-4).
 *
 * ORDER OF OPERATIONS AND WHY (each is re-explained at its implementation below):
 *   1. Assert a SINGLE consistent snapshot — one price-fetch pass, one FX-fetch pass, both
 *      timestamped. Mixing a fresh price with a stale FX rate produces apparent drift that
 *      is a pure data-freshness artifact and is indistinguishable, in the output, from real
 *      drift (multi-currency-mechanics.md Section 4.2) — so this is checked FIRST, before
 *      any value is computed from the inputs.
 *   2. Compute current per-name and per-cash-sleeve value in BASE currency, then NAV.
 *   3. Reconcile computed NAV against IBKR's own reported base-currency NAV. This is the
 *      single most reliable integrity check available (it does not depend on any of the
 *      per-contract currency inference the rest of this pipeline relies on) — a mismatch
 *      beyond tolerance means stale FX, a missed position, or a bad price, and this script
 *      FAILS LOUD rather than emitting drift numbers built on an unreconciled NAV
 *      (multi-currency-mechanics.md Section 4.1 step 5; SKILL.md "fail loud and stop").
 *   4. Current weights = value_base / RECONCILED nav (IBKR's number, not the computed one,
 *      once step 3 passes) — using the reconciled denominator, not the computed one, is
 *      deliberate: it is the more trustworthy of the two once they've been shown to agree
 *      within tolerance.
 *   5. Drift vs target — absolute pp and relative-to-target %, soft/hard bands.
 *   6. Return attribution — local vs FX component since entry, compounding (not additive).
 *      THE LOAD-BEARING FEATURE: downstream stages must never react to a blended number.
 *   7. Drift-cause classification — one of four mutually exclusive labels per name, so the
 *      reading agent never has to infer "why" from raw numbers (see classifyDriftCause()
 *      for the exact decision tree and its rationale).
 *   8. Same-currency co-movement detection — collapse N single-name FX signals sharing a
 *      currency into ONE portfolio-level macro event when they moved together.
 *
 * INPUT: JSON on stdin, or a file path via --input=FILE. Shape:
 *   {
 *     base_currency: "EUR",
 *     snapshot_time: "2026-08-01T12:00:00Z",        // ISO8601 — when prices were fetched
 *     fx_snapshot_time: "2026-08-01T11:55:00Z",      // ISO8601 — when FX rates were fetched
 *     ibkr_reported_nav_base: 50000,                 // IBKR NetLiquidation, base currency
 *     nav_reconciliation_tolerance_pct: 0.5,         // optional, default 0.5, ceiling 2
 *     fx_stale_warn_minutes: 60,                     // optional, default 60
 *     soft_band_relative_pct: 20,                    // optional, default 20
 *     hard_band_upper_multiple: 1.875,               // optional, default 1.875 (mid of 1.75-2x)
 *     hard_band_lower_multiple: 0.35,                // optional, default 0.35 (mid of 0.3-0.4x)
 *     positions: [
 *       {
 *         symbol: "SHEL.L",
 *         cluster: "energy",                          // optional, informs co-movement context
 *         shares: 265,
 *         currency_major: "GBP",                       // already minor-unit-normalized
 *         price_major: 35.10,                          // CURRENT price, minor-unit-normalized
 *         fx_rate_to_base: 1.17,                        // CURRENT rate, base per 1 local unit
 *         target_weight_pct: 21,
 *         entry: { price_major: 33.835, fx_rate_to_base: 1.1628 }
 *       }, ...
 *     ],
 *     cash_positions: [                                // cash carries its own target too
 *       { currency: "EUR", balance_local: 2500, fx_rate_to_base: 1, target_weight_pct: 5,
 *         entry_fx_rate_to_base: 1 }                    // entry_fx optional — omit for base ccy
 *     ]
 *   }
 *
 * fx_rate_to_base UNIT CONVENTION — identical to compute-weights.js, so a caller can source
 * both scripts from the same fetch layer without a unit translation step: base-currency
 * units per 1 unit of the position's local major currency (e.g. EUR per 1 GBP). Therefore
 * value_base = value_local * fx_rate_to_base, and FX return r_fx = fx_now/fx_entry - 1
 * (positive = local currency strengthened vs base), matching references/08-multi-currency.md
 * Section 3.1's fx_rate(local -> EUR) direction exactly (that section's
 * direction, unlike Section 1.2's, already matches this field's natural name).
 *
 * Output: a compact human-readable table on STDERR (so it never corrupts machine-readable
 * stdout), and the full JSON result on STDOUT.
 *
 * Usage: node compute-drift.js --input=input.json
 *    or: node compute-drift.js < input.json
 *    or: node compute-drift.js --self-test
 */

import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------------------------
// Named constants — reasoned defaults per references/03-review-doctrine.md /
// execution-prompt-review.md Stage 2: "reasoned defaults, not literature-validated for
// single-stock books, state them as such, configurable, not sacred." Kept as named,
// overridable constants (not hard-locked like compute-weights.js's caps) because these are
// review-cadence *triggers*, not worst-case-loss bounds — the thing that actually bounds
// loss is the per-name cap enforced at BUILD time by compute-weights.js.
// ---------------------------------------------------------------------------------------------
const DEFAULT_SOFT_BAND_RELATIVE_PCT = 20;      // ~20% relative to target — a "keep watching" floor
const DEFAULT_HARD_BAND_UPPER_MULTIPLE = 1.875; // midpoint of the 1.75-2.0x-target hard band
const DEFAULT_HARD_BAND_LOWER_MULTIPLE = 0.35;  // midpoint of the 0.3-0.4x-target hard band

const DEFAULT_NAV_RECONCILIATION_TOLERANCE_PCT = 0.5; // references/08-multi-currency.md §4 step 5
const MAX_NAV_RECONCILIATION_TOLERANCE_PCT = 2;        // ceiling — do not let a caller loosen
                                                         // the integrity check into uselessness
const DEFAULT_FX_STALE_WARN_MINUTES = 60;

// Materiality thresholds for the drift-cause classifier (see classifyDriftCause()).
//
// SOURCING — read before changing or trusting these. The four category names themselves
// (fx-driven / winner-appreciation / underperformance / denominator-shrinkage) come from the
// source material (references/03-review-doctrine.md, execution-prompt-review.md Stage 4/6).
// The BOUNDARY LOGIC below — exactly where "meaningfully local" or "FX-dominant" begins,
// numerically — is NOT sourced from either of those documents or from any cited study. These
// four numbers are this script's own synthesized decision-tree boundaries, invented to turn a
// qualitative distinction into a deterministic label. They are not literature-derived and have
// not been empirically validated against realized portfolios. Treat them as tunable defaults,
// not calibrated constants — reasonable starting points, safe to override via input — not as
// carrying the same evidentiary weight as the NAV reconciliation tolerance or the hard drift
// bands above, both of which trace to an explicit source. The same disclosure and these same
// default values are documented in prose in references/08-multi-currency.md Section 3.1.
const MEANINGFUL_LOCAL_RETURN_PCT = 5;   // local return must exceed this to count as a "real"
                                          // winner-appreciation / underperformance signal
const FX_DOMINANCE_RATIO = 1.5;          // |r_fx| must exceed this multiple of |r_local| ...
const FX_MATERIALITY_PCT = 2;            // ... AND itself exceed this floor, to be "fx-driven"

// Same-currency co-movement detector materiality floor — same sourcing caveat as the block
// above: this script's own synthesized threshold, not literature-derived, not empirically
// validated. Tunable default, not a calibrated constant.
const COMOVEMENT_MIN_FX_RETURN_PCT = 1;

const IDLE_CASH_SUSTAINED_PCT = 5; // execution-prompt-review.md Stage 2: idle cash beyond ~5%

const EPS = 1e-9;

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

function roundHalfPp(x) {
  if (!isFiniteNum(x)) return x;
  return Math.round(x * 2) / 2;
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
    fail('base_currency is required and must be a non-empty string');
  }
  if (!isFiniteNum(input.ibkr_reported_nav_base) || input.ibkr_reported_nav_base <= 0) {
    fail('ibkr_reported_nav_base is required and must be a positive number — this is the reconciliation anchor');
  }

  const navTolPct = input.nav_reconciliation_tolerance_pct === undefined
    ? DEFAULT_NAV_RECONCILIATION_TOLERANCE_PCT
    : input.nav_reconciliation_tolerance_pct;
  if (!isFiniteNum(navTolPct) || navTolPct <= 0) fail('nav_reconciliation_tolerance_pct, if provided, must be a positive number');
  if (navTolPct > MAX_NAV_RECONCILIATION_TOLERANCE_PCT + EPS) {
    fail(
      `nav_reconciliation_tolerance_pct (${navTolPct}) exceeds the ceiling of ${MAX_NAV_RECONCILIATION_TOLERANCE_PCT}% — ` +
      `loosening this past a couple of percent defeats the point of the reconciliation check, refusing to clamp silently.`
    );
  }

  const fxStaleWarnMinutes = input.fx_stale_warn_minutes === undefined ? DEFAULT_FX_STALE_WARN_MINUTES : input.fx_stale_warn_minutes;
  if (!isFiniteNum(fxStaleWarnMinutes) || fxStaleWarnMinutes < 0) fail('fx_stale_warn_minutes, if provided, must be a non-negative number');

  const softBandPct = input.soft_band_relative_pct === undefined ? DEFAULT_SOFT_BAND_RELATIVE_PCT : input.soft_band_relative_pct;
  if (!isFiniteNum(softBandPct) || softBandPct <= 0) fail('soft_band_relative_pct, if provided, must be a positive number');

  const hardUpper = input.hard_band_upper_multiple === undefined ? DEFAULT_HARD_BAND_UPPER_MULTIPLE : input.hard_band_upper_multiple;
  if (!isFiniteNum(hardUpper) || hardUpper <= 1) fail('hard_band_upper_multiple, if provided, must be a number > 1');

  const hardLower = input.hard_band_lower_multiple === undefined ? DEFAULT_HARD_BAND_LOWER_MULTIPLE : input.hard_band_lower_multiple;
  if (!isFiniteNum(hardLower) || hardLower <= 0 || hardLower >= 1) fail('hard_band_lower_multiple, if provided, must be a number in (0, 1)');

  const snapshotTime = parseTime(input.snapshot_time, 'snapshot_time');
  const fxSnapshotTime = parseTime(input.fx_snapshot_time, 'fx_snapshot_time');

  if (!Array.isArray(input.positions)) fail('positions must be an array');
  if (input.positions.length === 0) fail('positions must contain at least one entry');

  if (input.cash_positions !== undefined && !Array.isArray(input.cash_positions)) {
    fail('cash_positions, if provided, must be an array');
  }

  return { navTolPct, fxStaleWarnMinutes, softBandPct, hardUpper, hardLower, snapshotTime, fxSnapshotTime };
}

function validatePosition(pos, idx) {
  const where = `positions[${idx}]${pos && pos.symbol ? ` (${pos.symbol})` : ''}`;
  if (!pos || typeof pos !== 'object') fail(`${where}: must be an object`);
  if (typeof pos.symbol !== 'string' || !pos.symbol) fail(`${where}: symbol is required`);
  if (!isFiniteNum(pos.shares) || pos.shares < 0) fail(`${where}: shares is required and must be a non-negative number`);
  if (typeof pos.currency_major !== 'string' || !pos.currency_major) fail(`${where}: currency_major is required`);
  if (!isFiniteNum(pos.price_major) || pos.price_major <= 0) fail(`${where}: price_major (current) is required and must be a positive number`);
  if (!isFiniteNum(pos.fx_rate_to_base) || pos.fx_rate_to_base <= 0) fail(`${where}: fx_rate_to_base (current) is required and must be a positive number`);
  if (!isFiniteNum(pos.target_weight_pct) || pos.target_weight_pct < 0) fail(`${where}: target_weight_pct is required and must be a non-negative number`);
  if (!pos.entry || typeof pos.entry !== 'object') fail(`${where}: entry snapshot is required — refusing to default a missing return-attribution input`);
  if (!isFiniteNum(pos.entry.price_major) || pos.entry.price_major <= 0) fail(`${where}: entry.price_major is required and must be a positive number`);
  if (!isFiniteNum(pos.entry.fx_rate_to_base) || pos.entry.fx_rate_to_base <= 0) fail(`${where}: entry.fx_rate_to_base is required and must be a positive number`);
}

function validateCashPosition(cash, idx) {
  const where = `cash_positions[${idx}]${cash && cash.currency ? ` (${cash.currency})` : ''}`;
  if (!cash || typeof cash !== 'object') fail(`${where}: must be an object`);
  if (typeof cash.currency !== 'string' || !cash.currency) fail(`${where}: currency is required`);
  if (!isFiniteNum(cash.balance_local) || cash.balance_local < 0) fail(`${where}: balance_local is required and must be a non-negative number`);
  if (!isFiniteNum(cash.fx_rate_to_base) || cash.fx_rate_to_base <= 0) fail(`${where}: fx_rate_to_base is required and must be a positive number`);
  if (!isFiniteNum(cash.target_weight_pct) || cash.target_weight_pct < 0) fail(`${where}: target_weight_pct is required and must be a non-negative number`);
  if (cash.entry_fx_rate_to_base !== undefined && (!isFiniteNum(cash.entry_fx_rate_to_base) || cash.entry_fx_rate_to_base <= 0)) {
    fail(`${where}: entry_fx_rate_to_base, if provided, must be a positive number`);
  }
}

// =================================================================================================
// Step 1: single-snapshot consistency assertion — must run before anything is computed.
// =================================================================================================

function checkSnapshotConsistency(snapshotTime, fxSnapshotTime, fxStaleWarnMinutes) {
  const warnings = [];
  const staleMinutes = (snapshotTime - fxSnapshotTime) / 60000; // positive => FX is OLDER than price
  if (staleMinutes > fxStaleWarnMinutes + EPS) {
    warnings.push(
      `FX snapshot is ${round2(staleMinutes)} minutes older than the price snapshot (threshold ` +
      `${fxStaleWarnMinutes}m) — this run may be mixing a fresh price with a stale FX rate ` +
      `(multi-currency-mechanics.md Section 4.2). Apparent drift from this run should be treated ` +
      `with caution until re-run with a fresh FX fetch.`
    );
  }
  // A price snapshot older than the FX snapshot by a lot is the mirror-image trap — also flag it.
  if (staleMinutes < -fxStaleWarnMinutes - EPS) {
    warnings.push(
      `Price snapshot is ${round2(-staleMinutes)} minutes older than the FX snapshot (threshold ` +
      `${fxStaleWarnMinutes}m) — same data-freshness risk as a stale FX rate, mirrored.`
    );
  }
  return { staleMinutes: round2(staleMinutes), warnings };
}

// =================================================================================================
// Step 2: current value in base currency, per position and per cash sleeve, then NAV.
// =================================================================================================

function computePositionValue(p) {
  // value_base = value_local * fx_rate_to_base (see UNIT CONVENTION note in the file header).
  const valueLocal = p.shares * p.price_major;
  const valueBase = valueLocal * p.fx_rate_to_base;
  return { valueLocal, valueBase };
}

function computeCashValue(c) {
  const valueBase = c.balance_local * c.fx_rate_to_base;
  return valueBase;
}

// =================================================================================================
// Step 3: reconcile computed NAV against IBKR's own reported base-currency NAV. FAIL LOUD on a
// mismatch beyond tolerance — this is a data-quality gate, not a display footnote
// (multi-currency-mechanics.md Section 4.1 step 5; SKILL.md "hard-stop on failure").
// =================================================================================================

function reconcileNav(navComputed, navReported, tolerancePct) {
  const diffBase = navComputed - navReported;
  const diffPct = (diffBase / navReported) * 100;
  const reconciled = Math.abs(diffPct) <= tolerancePct + EPS;
  if (!reconciled) {
    fail(
      `NAV RECONCILIATION FAILED — computed NAV (${round2(navComputed)}) diverges from IBKR's ` +
      `reported NAV (${round2(navReported)}) by ${round2(diffPct)}% (tolerance ${tolerancePct}%). ` +
      `This is a data-quality failure — stale FX, a missed position, or a bad price — not a ` +
      `rounding footnote. HARD STOP: refusing to emit drift numbers built on an unreconciled NAV. ` +
      `Resolve the discrepancy (re-fetch prices/FX, check for a missing position) and re-run.`
    );
  }
  return { nav_computed_base: round2(navComputed), nav_reported_base: round2(navReported), diff_base: round2(diffBase), diff_pct: round2(diffPct), reconciled };
}

// =================================================================================================
// Steps 5-6: drift bands and local/FX return attribution — references/08-multi-currency.md
// Section 3.1's exact compounding decomposition. The additive approximation is NOT used here even
// though the source notes it's fine for weekly commentary, because this script's numbers may be
// read at any cadence (weekly through annual) and the exact formula's error is never worse, so
// there is no reason to take the approximation's risk at longer horizons.
// =================================================================================================

function computeReturnAttribution(entryPriceMajor, currentPriceMajor, entryFx, currentFx) {
  const rLocal = currentPriceMajor / entryPriceMajor - 1;
  const rFx = currentFx / entryFx - 1;
  const rTotal = (1 + rLocal) * (1 + rFx) - 1; // exact compounding, per Section 3.1 step 5
  return {
    local_return_pct: round2(rLocal * 100),
    fx_return_pct: round2(rFx * 100),
    total_return_pct: round2(rTotal * 100),
    _rLocal: rLocal,
    _rFx: rFx,
  };
}

function classifyDriftBand(currentWeightPct, targetWeightPct, softBandPct, hardUpper, hardLower) {
  if (targetWeightPct <= EPS) {
    // A target of exactly 0% (e.g. a name flagged for full exit) can't have a meaningful
    // relative drift denominator — report absolute-only and skip band classification.
    return { relative_drift_pct: null, band: currentWeightPct > EPS ? 'hard-upper' : 'in-band' };
  }
  const relativeDrift = (currentWeightPct / targetWeightPct - 1) * 100; // e.g. +20 = 1.2x target
  const multiple = currentWeightPct / targetWeightPct;
  let band = 'in-band';
  if (multiple >= hardUpper - EPS) band = 'hard-upper';
  else if (multiple <= hardLower + EPS) band = 'hard-lower';
  else if (Math.abs(relativeDrift) >= softBandPct - EPS) band = relativeDrift > 0 ? 'soft-upper' : 'soft-lower';
  return { relative_drift_pct: round2(relativeDrift), band };
}

// =================================================================================================
// Step 7: drift-cause classification. FOUR mutually exclusive labels, decided by a deterministic
// priority order — this is a synthesis of the four category names given in the task brief and
// SKILL.md's usage of "denominator shrinkage" for up-drift (references/03-review-doctrine.md /
// execution-prompt-review.md Stage 4/6: "Drift up from denominator shrinkage -> mechanical trim
// defensible"). The four categories are generalized here into a symmetric decision tree so every
// name gets exactly one label, never zero, never more than one:
//
//   1. fx-driven          — the FX leg, not the name's own local return, dominates the move
//                            (either direction). Per Section 3.2 rules 1-2, an FX-driven move is
//                            never a thesis signal in either direction.
//   2. winner-appreciation — weight drifted UP and the name's own local return meaningfully
//                            explains it (a genuine business outperformance, not a portfolio-size
//                            artifact).
//   3. underperformance    — weight drifted DOWN and the name's own local return meaningfully
//                            explains it (a genuine business decline — the ONLY case that should
//                            trigger a thesis re-check per the review doctrine's asymmetric bar).
//   4. denominator-shrinkage — the residual bucket: weight moved (either direction) but neither
//                            FX nor the name's own local return meaningfully explains it — the
//                            move is a portfolio-relative-size effect (other positions/cash grew
//                            or shrank around this one), not a signal about this name at all.
// =================================================================================================

function classifyDriftCause(driftPp, rLocalFraction, rFxFraction) {
  const rLocalPct = rLocalFraction * 100;
  const rFxPct = rFxFraction * 100;

  const fxDominant = Math.abs(rFxPct) >= FX_MATERIALITY_PCT - EPS
    && Math.abs(rFxPct) >= FX_DOMINANCE_RATIO * Math.abs(rLocalPct) - EPS;
  if (fxDominant) return 'fx-driven';

  if (driftPp > EPS && rLocalPct >= MEANINGFUL_LOCAL_RETURN_PCT - EPS) return 'winner-appreciation';
  if (driftPp < -EPS && rLocalPct <= -MEANINGFUL_LOCAL_RETURN_PCT + EPS) return 'underperformance';

  return 'denominator-shrinkage';
}

// =================================================================================================
// Step 8: same-currency co-movement detector — collapse N single-name FX signals into one event.
// =================================================================================================

function detectCoMovement(positionsOut) {
  const byCurrency = new Map();
  for (const p of positionsOut) {
    if (!byCurrency.has(p.currency_major)) byCurrency.set(p.currency_major, []);
    byCurrency.get(p.currency_major).push(p);
  }

  const events = [];
  for (const [currency, members] of byCurrency) {
    if (members.length < 2) continue; // co-movement requires at least 2 names sharing a currency
    const material = members.filter((m) => Math.abs(m.fx_return_pct) >= COMOVEMENT_MIN_FX_RETURN_PCT - EPS);
    if (material.length < 2) continue;
    const allPositive = material.every((m) => m.fx_return_pct > 0);
    const allNegative = material.every((m) => m.fx_return_pct < 0);
    if (allPositive || allNegative) {
      const avgFx = round2(material.reduce((a, m) => a + m.fx_return_pct, 0) / material.length);
      events.push({
        currency,
        direction: allPositive ? 'strengthened vs base' : 'weakened vs base',
        symbols: material.map((m) => m.symbol),
        avg_fx_return_pct: avgFx,
        note: `${material.length} names sharing ${currency} moved together on the FX leg — ` +
          `report this as ONE macro event (the currency moved), not ${material.length} independent ` +
          `stock signals (multi-currency-mechanics.md Section 3.2 rule 4).`,
      });
    }
  }
  return events;
}

// =================================================================================================
// Pipeline driver
// =================================================================================================

function runPipeline(input) {
  const { navTolPct, fxStaleWarnMinutes, softBandPct, hardUpper, hardLower, snapshotTime, fxSnapshotTime } = validateTopLevel(input);
  input.positions.forEach(validatePosition);
  (input.cash_positions || []).forEach(validateCashPosition);

  const warnings = [];

  // Step 1
  const snapshotCheck = checkSnapshotConsistency(snapshotTime, fxSnapshotTime, fxStaleWarnMinutes);
  warnings.push(...snapshotCheck.warnings);

  // Step 2 — value everything in base currency.
  const positions = input.positions.map((p) => {
    const { valueLocal, valueBase } = computePositionValue(p);
    return { ...p, value_local: valueLocal, value_base: valueBase };
  });
  const cashPositions = (input.cash_positions || []).map((c) => ({ ...c, value_base: computeCashValue(c) }));

  const navComputed = positions.reduce((a, p) => a + p.value_base, 0)
    + cashPositions.reduce((a, c) => a + c.value_base, 0);

  // Step 3 — reconcile. FAILS LOUD (throws) if outside tolerance; nothing below this line
  // executes on an unreconciled book.
  const reconciliation = reconcileNav(navComputed, input.ibkr_reported_nav_base, navTolPct);
  const navBase = input.ibkr_reported_nav_base; // step 4: use the RECONCILED (IBKR) denominator

  // Steps 4-7 — per position.
  const positionsOut = positions.map((p) => {
    const currentWeightPct = round2((p.value_base / navBase) * 100);
    const driftPp = round2(currentWeightPct - p.target_weight_pct);
    const bandInfo = classifyDriftBand(currentWeightPct, p.target_weight_pct, softBandPct, hardUpper, hardLower);
    const attribution = computeReturnAttribution(p.entry.price_major, p.price_major, p.entry.fx_rate_to_base, p.fx_rate_to_base);
    const driftCause = classifyDriftCause(driftPp, attribution._rLocal, attribution._rFx);

    return {
      symbol: p.symbol,
      cluster: p.cluster ?? null,
      currency_major: p.currency_major,
      shares: p.shares,
      current_weight_pct: currentWeightPct,
      target_weight_pct: p.target_weight_pct,
      drift_pp: driftPp,
      relative_drift_pct: bandInfo.relative_drift_pct,
      band: bandInfo.band,
      local_return_pct: attribution.local_return_pct,
      fx_return_pct: attribution.fx_return_pct,
      total_return_pct: attribution.total_return_pct,
      drift_cause: driftCause,
      value_base: round2(p.value_base),
    };
  });

  // Cash sleeves — same weight/drift treatment; FX-only "return" when entry_fx is available
  // (Section 4.3: non-base cash is itself an unhedged FX exposure, tracked per-currency).
  const cashOut = cashPositions.map((c) => {
    const currentWeightPct = round2((c.value_base / navBase) * 100);
    const driftPp = round2(currentWeightPct - c.target_weight_pct);
    const bandInfo = classifyDriftBand(currentWeightPct, c.target_weight_pct, softBandPct, hardUpper, hardLower);
    let fxReturnPct = null;
    let driftCause = 'denominator-shrinkage'; // cash has no "local return" of its own by construction
    if (c.entry_fx_rate_to_base !== undefined) {
      const rFx = c.fx_rate_to_base / c.entry_fx_rate_to_base - 1;
      fxReturnPct = round2(rFx * 100);
      if (Math.abs(fxReturnPct) >= FX_MATERIALITY_PCT - EPS) driftCause = 'fx-driven';
    }
    return {
      currency: c.currency,
      balance_local: c.balance_local,
      current_weight_pct: currentWeightPct,
      target_weight_pct: c.target_weight_pct,
      drift_pp: driftPp,
      relative_drift_pct: bandInfo.relative_drift_pct,
      band: bandInfo.band,
      fx_return_pct: fxReturnPct,
      drift_cause: driftCause,
      value_base: round2(c.value_base),
    };
  });

  // Idle-cash check (execution-prompt-review.md Stage 2: idle cash beyond ~5% sustained).
  const totalCashWeightPct = round2(cashOut.reduce((a, c) => a + c.current_weight_pct, 0));
  const idleCashFlag = totalCashWeightPct > IDLE_CASH_SUSTAINED_PCT + EPS;

  // Step 8 — same-currency co-movement detector, run over equity positions only.
  const coMovementEvents = detectCoMovement(positionsOut);

  positionsOut.sort((a, b) => Math.abs(b.drift_pp) - Math.abs(a.drift_pp));

  const hardBandBreaches = positionsOut.filter((p) => p.band === 'hard-upper' || p.band === 'hard-lower');
  const softBandFlags = positionsOut.filter((p) => p.band === 'soft-upper' || p.band === 'soft-lower');

  const result = {
    generated_at: new Date().toISOString(),
    base_currency: input.base_currency,
    snapshot: {
      snapshot_time: input.snapshot_time,
      fx_snapshot_time: input.fx_snapshot_time,
      fx_staleness_minutes: snapshotCheck.staleMinutes,
    },
    nav_reconciliation: reconciliation,
    inputs_echo: {
      nav_reconciliation_tolerance_pct: navTolPct,
      soft_band_relative_pct: softBandPct,
      hard_band_upper_multiple: hardUpper,
      hard_band_lower_multiple: hardLower,
      n_positions: positionsOut.length,
      n_cash_sleeves: cashOut.length,
    },
    positions: positionsOut,
    cash_positions: cashOut,
    cash_summary: {
      total_cash_weight_pct: totalCashWeightPct,
      idle_cash_flag: idleCashFlag,
    },
    co_movement_events: coMovementEvents,
    hard_band_breaches: hardBandBreaches.map((p) => p.symbol),
    soft_band_flags: softBandFlags.map((p) => p.symbol),
    warnings,
  };

  return result;
}

// =================================================================================================
// Compact table renderer — human-readable, written to STDERR so STDOUT stays pure JSON.
// =================================================================================================

function renderTable(result) {
  const lines = [];
  lines.push('');
  lines.push(`Drift report — generated ${result.generated_at}`);
  lines.push(`NAV: computed ${result.nav_reconciliation.nav_computed_base} vs reported ${result.nav_reconciliation.nav_reported_base} ${result.base_currency} (diff ${result.nav_reconciliation.diff_pct}%) — RECONCILED`);
  if (result.warnings.length) {
    lines.push('WARNINGS:');
    for (const w of result.warnings) lines.push(`  - ${w}`);
  }
  lines.push('');
  const header = ['symbol', 'cur%', 'tgt%', 'drift(pp)', 'band', 'local%', 'fx%', 'total%', 'cause'];
  const rows = result.positions.map((p) => [
    p.symbol,
    p.current_weight_pct,
    p.target_weight_pct,
    p.drift_pp,
    p.band,
    p.local_return_pct,
    p.fx_return_pct,
    p.total_return_pct,
    p.drift_cause,
  ]);
  const widths = header.map((h, i) => Math.max(String(h).length, ...rows.map((r) => String(r[i]).length)));
  const fmt = (row) => row.map((cell, i) => String(cell).padEnd(widths[i])).join('  ');
  lines.push(fmt(header));
  lines.push(widths.map((w) => '-'.repeat(w)).join('  '));
  for (const r of rows) lines.push(fmt(r));
  if (result.cash_positions.length) {
    lines.push('');
    lines.push(`Cash: total ${result.cash_summary.total_cash_weight_pct}% ${result.cash_summary.idle_cash_flag ? '(IDLE-CASH FLAG)' : ''}`);
  }
  if (result.co_movement_events.length) {
    lines.push('');
    lines.push('Co-movement events:');
    for (const e of result.co_movement_events) {
      lines.push(`  - ${e.currency} ${e.direction}: ${e.symbols.join(', ')} (avg FX return ${e.avg_fx_return_pct}%)`);
    }
  }
  lines.push('');
  return lines.join('\n');
}

// ---------------------------------------------------------------------------------------------
// Self-test — offline, no network, no input file. Run: node compute-drift.js --self-test
// ---------------------------------------------------------------------------------------------

function baseInput(overrides) {
  const t0 = '2026-08-01T12:00:00Z';
  return Object.assign(
    {
      base_currency: 'EUR',
      snapshot_time: t0,
      fx_snapshot_time: t0,
      ibkr_reported_nav_base: 100000,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
      cash_positions: [],
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

  check('NAV mismatch beyond tolerance fails loud', () => {
    const input = baseInput({ ibkr_reported_nav_base: 200000 }); // computed will be 10000 + 0 cash, way off
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected NAV reconciliation to fail loud');
    if (!msg.includes('RECONCILIATION FAILED')) fail(`expected RECONCILIATION FAILED in message, got: ${msg}`);
  });

  check('NAV within tolerance reconciles and returns positions', () => {
    const input = baseInput({ ibkr_reported_nav_base: 10000 });
    const out = runPipeline(input);
    if (!out.nav_reconciliation.reconciled) fail('expected reconciled=true');
    if (out.positions.length !== 1) fail('expected 1 position in output');
  });

  check('stale FX snapshot (older than price) produces a warning, not a failure', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 10000,
      snapshot_time: '2026-08-01T12:00:00Z',
      fx_snapshot_time: '2026-08-01T09:00:00Z', // 3 hours stale, default warn threshold 60min
    });
    const out = runPipeline(input);
    if (!out.warnings.some((w) => w.includes('older than the price snapshot'))) {
      fail('expected a staleness warning');
    }
  });

  check('local return, no FX movement: entirely local, fx_return_pct=0', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 11000,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 110, fx_rate_to_base: 1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
    });
    const out = runPipeline(input);
    const p = out.positions[0];
    if (Math.abs(p.local_return_pct - 10) > 1e-6) fail(`expected local_return_pct=10, got ${p.local_return_pct}`);
    if (Math.abs(p.fx_return_pct - 0) > 1e-6) fail(`expected fx_return_pct=0, got ${p.fx_return_pct}`);
    if (Math.abs(p.total_return_pct - 10) > 1e-6) fail(`expected total_return_pct=10, got ${p.total_return_pct}`);
  });

  check('return decomposition compounds exactly (not additive) for a combined move', () => {
    // local +10%, FX +10% => total should be (1.1*1.1 - 1) = 21%, not the additive 20%.
    const input = baseInput({
      ibkr_reported_nav_base: 12100,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 110, fx_rate_to_base: 1.1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
    });
    const out = runPipeline(input);
    const p = out.positions[0];
    if (Math.abs(p.total_return_pct - 21) > 1e-6) fail(`expected exact compounding total_return_pct=21, got ${p.total_return_pct}`);
  });

  check('winner-appreciation classification: weight up, strong local return, FX flat', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 20000,
      positions: [
        { symbol: 'WIN', shares: 100, currency_major: 'USD', price_major: 150, fx_rate_to_base: 1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
        { symbol: 'B', shares: 50, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 25, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
    });
    const out = runPipeline(input);
    const win = out.positions.find((p) => p.symbol === 'WIN');
    if (win.drift_cause !== 'winner-appreciation') fail(`expected winner-appreciation, got ${win.drift_cause}`);
  });

  check('underperformance classification: weight down, meaningfully negative local return, FX flat', () => {
    // LOSE: 100sh @ 50 = 5000 base, current weight 33.3%, target 50% -> drift down; local -50%.
    // B: 100sh @ 100 = 10000 base, current weight 66.7% (not asserted on). NAV = 15000.
    const input = baseInput({
      ibkr_reported_nav_base: 15000,
      positions: [
        { symbol: 'LOSE', shares: 100, currency_major: 'USD', price_major: 50, fx_rate_to_base: 1, target_weight_pct: 50, entry: { price_major: 100, fx_rate_to_base: 1 } },
        { symbol: 'B', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 50, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
    });
    const out = runPipeline(input);
    const lose = out.positions.find((p) => p.symbol === 'LOSE');
    if (lose.drift_cause !== 'underperformance') fail(`expected underperformance, got ${lose.drift_cause}`);
  });

  check('fx-driven classification: FX leg dominates a drawdown, local return flat/positive', () => {
    // FXVICTIM: 100sh @ 101 GBP * fx 0.90 = 9090 base. NAV must reconcile to that.
    const input = baseInput({
      ibkr_reported_nav_base: 9090,
      positions: [
        { symbol: 'FXVICTIM', shares: 100, currency_major: 'GBP', price_major: 101, fx_rate_to_base: 0.90, target_weight_pct: 11.2, entry: { price_major: 100, fx_rate_to_base: 1.0 } },
      ],
    });
    const out = runPipeline(input);
    const p = out.positions[0];
    if (p.drift_cause !== 'fx-driven') fail(`expected fx-driven, got ${p.drift_cause} (local=${p.local_return_pct}, fx=${p.fx_return_pct})`);
  });

  check('denominator-shrinkage classification: weight drifted but own local return is immaterial', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 12000,
      positions: [
        { symbol: 'FLAT', shares: 100, currency_major: 'USD', price_major: 101, fx_rate_to_base: 1, target_weight_pct: 8, entry: { price_major: 100, fx_rate_to_base: 1 } },
        { symbol: 'B', shares: 100, currency_major: 'USD', price_major: 19, fx_rate_to_base: 1, target_weight_pct: 92, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
    });
    const out = runPipeline(input);
    const flat = out.positions.find((p) => p.symbol === 'FLAT');
    // FLAT's own local return is ~1% (immaterial), but its weight share rose because B collapsed.
    if (flat.drift_cause !== 'denominator-shrinkage') fail(`expected denominator-shrinkage, got ${flat.drift_cause}`);
  });

  check('hard-upper band fires at/above the configured multiple', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 10000,
      hard_band_upper_multiple: 1.875,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 5, entry: { price_major: 100, fx_rate_to_base: 1 } }, // 10% actual / 5% target = 2.0x
      ],
    });
    const out = runPipeline(input);
    if (out.positions[0].band !== 'hard-upper') fail(`expected hard-upper band, got ${out.positions[0].band}`);
    if (!out.hard_band_breaches.includes('A')) fail('expected A in hard_band_breaches');
  });

  check('hard-lower band fires at/below the configured multiple', () => {
    // A: 30sh @ 100 = 3000 base (3% of a 100000 NAV) vs 10% target = 0.3x -> hard-lower.
    // Remaining 97000 parked in cash so the computed NAV reconciles against the 100000 IBKR figure.
    const input = baseInput({
      ibkr_reported_nav_base: 100000,
      hard_band_lower_multiple: 0.35,
      positions: [
        { symbol: 'A', shares: 30, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
      cash_positions: [
        { currency: 'EUR', balance_local: 97000, fx_rate_to_base: 1, target_weight_pct: 90 },
      ],
    });
    const out = runPipeline(input);
    if (out.positions[0].band !== 'hard-lower') fail(`expected hard-lower band, got ${out.positions[0].band}`);
  });

  check('soft band fires between the soft threshold and the hard band', () => {
    // A: 13sh @ 100 = 1300 base; target 10% of a 10000 NAV => current 13% => +30% relative drift,
    // multiple 1.3x (below the 1.875x hard band) -> soft-upper. Remaining 8700 parked in cash.
    const input = baseInput({
      ibkr_reported_nav_base: 10000,
      positions: [
        { symbol: 'A', shares: 13, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 10, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
      cash_positions: [
        { currency: 'EUR', balance_local: 8700, fx_rate_to_base: 1, target_weight_pct: 87 },
      ],
    });
    const out = runPipeline(input);
    if (out.positions[0].band !== 'soft-upper') fail(`expected soft-upper band, got ${out.positions[0].band}`);
  });

  check('same-currency co-movement collapses N single-name FX signals into one event', () => {
    // G1,G2 (GBP, fx +10%) each value_base = 100*100*1.10 = 11000; U1 (USD, fx flat) = 10000.
    // NAV = 11000+11000+10000 = 32000.
    const input = baseInput({
      ibkr_reported_nav_base: 32000,
      positions: [
        { symbol: 'G1', shares: 100, currency_major: 'GBP', price_major: 100, fx_rate_to_base: 1.10, target_weight_pct: 33, entry: { price_major: 100, fx_rate_to_base: 1.00 } },
        { symbol: 'G2', shares: 100, currency_major: 'GBP', price_major: 100, fx_rate_to_base: 1.10, target_weight_pct: 33, entry: { price_major: 100, fx_rate_to_base: 1.00 } },
        { symbol: 'U1', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1.00, target_weight_pct: 33, entry: { price_major: 100, fx_rate_to_base: 1.00 } },
      ],
    });
    const out = runPipeline(input);
    if (out.co_movement_events.length !== 1) fail(`expected exactly 1 co-movement event, got ${out.co_movement_events.length}`);
    const evt = out.co_movement_events[0];
    if (evt.currency !== 'GBP') fail(`expected GBP co-movement event, got ${evt.currency}`);
    if (evt.symbols.length !== 2) fail(`expected 2 symbols in the GBP event, got ${evt.symbols.length}`);
  });

  check('idle cash beyond 5% is flagged', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 10700,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 90, entry: { price_major: 100, fx_rate_to_base: 1 } },
      ],
      cash_positions: [
        { currency: 'EUR', balance_local: 700, fx_rate_to_base: 1, target_weight_pct: 5 },
      ],
    });
    const out = runPipeline(input);
    if (!out.cash_summary.idle_cash_flag) fail('expected idle_cash_flag=true (7% cash > 5% sustained threshold)');
  });

  check('missing entry snapshot on a position fails loud rather than defaulting', () => {
    const input = baseInput({
      ibkr_reported_nav_base: 10000,
      positions: [
        { symbol: 'A', shares: 100, currency_major: 'USD', price_major: 100, fx_rate_to_base: 1, target_weight_pct: 10 },
      ],
    });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for missing entry snapshot');
  });

  check('nav_reconciliation_tolerance_pct above the ceiling errors, never clamps', () => {
    const input = baseInput({ ibkr_reported_nav_base: 10000, nav_reconciliation_tolerance_pct: 5 });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for nav_reconciliation_tolerance_pct=5');
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
