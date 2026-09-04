#!/usr/bin/env node
/**
 * compute-sizing.js
 * Deterministic Stage-6 sizing pipeline. Position size, Kelly fraction, vol-target scalar,
 * cluster budget, regime dial, hard caps — all computed HERE, never composed in free text by
 * the LLM (references/llm-guardrails.md §13: "the LLM never does arithmetic"). This closes the
 * gap between that guardrail and execution-prompt.md Stage 6, which previously asked the LLM to
 * do this arithmetic in its head. See references/risk-and-sizing.md for the full rationale
 * (fractional Kelly at the cluster level §1, inverse-vol tilt §4, momentum-crash vol-target §3-4,
 * binary hard cap §5, eToro concentration envelope §10, ADV capacity ceiling §13).
 *
 * PIPELINE (order matters — see risk-and-sizing.md, each step below cites its source):
 *   1. Per-name Kelly: b = upside_pct/downside_pct, p = confidence, f_full = (p(b+1)-1)/b,
 *      floored at 0. Catalyst-sleeve names need >=3:1 payoff (SKILL.md / signals.md) or they're
 *      disqualified before Kelly is even evaluated.
 *   2. Fractional Kelly: f = f_full * kelly_fraction (10-25% of full — locked ceiling, §1).
 *   3. Cluster budget: cap the SUM of a cluster's f at its largest single member's f (§1, §2) —
 *      correlated names may not consume more budget than one name in the cluster would.
 *   4. Inverse-vol tilt WITHIN the cluster: split the cluster budget by (confidence/realized_vol),
 *      not equally and not by each member's own f (§4).
 *   5. Book vol-target scalar s = min(1, book_vol_target/book_realized_vol) (§3-4, momentum-crash
 *      throttle — scale to the STRATEGY's own trailing vol, not market VIX).
 *   6. Regime dial (Stage 1 output) — the LAST scalar, applied once, never stacked with #5.
 *   7. Hard caps, last, never overridden: binary-catalyst 2-5% (§5), single-name 25%, top-5 <=60%
 *      (§10), and the ADV capacity cap min(weight_usd, 1% of 20-day ADV) (§13).
 *
 * EXECUTION: this script sizes a book that is executed LIVE. There is no track-record gate and no
 * shadow mode — that was considered and removed at the account owner's explicit direction. Note
 * honestly what that means: every threshold this script depends on (the Kelly fraction, the
 * vol-target band, the composite weights feeding `confidence`, the regime dial mapping) is an
 * UNVALIDATED PRIOR taken from published literature or judgment, not a finding earned from this
 * book's own results, and the learning-loop calibration in learning-loop.md stays inert until
 * resolved trades accumulate. The hard caps below (§5, §10, §13) are therefore the ONLY thing
 * bounding worst-case loss on an unproven edge — do not relax them.
 *
 * `binding_constraint` on each position names whichever step in the list above was the LAST one
 * to actually change that position's number (a scalar of exactly 1, or a cap that isn't touched,
 * doesn't overwrite it) — i.e. the real reason the final weight is what it is.
 *
 * INPUT: JSON file path as argv[1], or stdin if omitted. See references/risk-and-sizing.md and
 * the calling skill's Stage 6 for the expected shape (equity_usd, regime_dial, book_vol_target,
 * book_realized_vol, kelly_fraction, candidates[]).
 *
 * Never silently defaults a missing risk input — confidence, upside_pct, downside_pct, and
 * realized_vol_annual are MANDATORY per candidate; a missing one is a fatal error, not a guess.
 *
 * Usage: node compute-sizing.js input.json
 *    or: node compute-sizing.js < input.json
 *    or: node compute-sizing.js --self-test
 */

const fs = require('node:fs');

const KELLY_FRACTION_MAX = 0.25;      // locked risk parameter (risk-and-sizing.md §1) — NEVER a tunable
const BOOK_VOL_TARGET_MIN = 0.18;     // locked band — a 5-15 name concentrated book can't hit 12% vol
const BOOK_VOL_TARGET_MAX = 0.25;     // without ~60% cash, which breaks the concentration mandate
const CATALYST_MIN_PAYOFF_RATIO = 3;  // SKILL.md / signals.md: catalyst sleeve needs >=3:1 or disqualified
const BINARY_CAP = 0.05;              // flat 2-5% band cap on binary-catalyst names (§5) — top of band used
const SINGLE_NAME_CAP = 0.25;         // eToro execution envelope (§10)
const VOL_TILT_MIN = 0.5;             // clamp on the across-book inverse-vol tilt (§4) — a tilt, not a lever
const VOL_TILT_MAX = 2.0;
const TOP5_CAP = 0.60;                // eToro execution envelope (§10)
const ADV_CAP_FRACTION = 0.01;        // capacity/ADV ceiling (§13): min(weight_usd, 1% of 20-day ADV)
const EPS = 1e-9;


function fail(msg) {
  throw new Error(msg);
}

function round(x, d) {
  if (x === null || x === undefined || Number.isNaN(x)) return null;
  const m = 10 ** d;
  return Math.round(x * m) / m;
}

function isFiniteNum(x) {
  return typeof x === 'number' && Number.isFinite(x);
}

// ---- Top-level input validation — fail loudly, never substitute a default for a risk input ----
function validateTopLevel(input) {
  if (!input || typeof input !== 'object') fail('input must be a JSON object');
  if (!isFiniteNum(input.equity_usd) || input.equity_usd <= 0) fail('equity_usd is required and must be a positive number');
  if (!isFiniteNum(input.regime_dial) || input.regime_dial < 0 || input.regime_dial > 1) {
    fail(`regime_dial is required and must be a number in [0,1], got ${JSON.stringify(input.regime_dial)}`);
  }
  if (!isFiniteNum(input.book_vol_target)) fail('book_vol_target is required and must be a number');
  if (input.book_vol_target < BOOK_VOL_TARGET_MIN - EPS || input.book_vol_target > BOOK_VOL_TARGET_MAX + EPS) {
    fail(`book_vol_target must be in [${BOOK_VOL_TARGET_MIN}, ${BOOK_VOL_TARGET_MAX}] (locked band — a concentrated single-stock book cannot reach 12% vol without ~60% cash); got ${input.book_vol_target}`);
  }
  if (!isFiniteNum(input.book_realized_vol) || input.book_realized_vol <= 0) fail('book_realized_vol is required and must be a positive number');
  if (!isFiniteNum(input.kelly_fraction) || input.kelly_fraction <= 0) fail('kelly_fraction is required and must be a positive number');
  if (input.kelly_fraction > KELLY_FRACTION_MAX + EPS) {
    fail(`kelly_fraction (${input.kelly_fraction}) exceeds the locked ceiling of ${KELLY_FRACTION_MAX} — this is a hard risk parameter, not a tunable input`);
  }
  if (!Array.isArray(input.candidates)) fail('candidates must be an array');
}


// ---- Per-candidate validation — missing p/upside/downside/vol is a FATAL error, never a default ----
function validateCandidate(cand, idx) {
  const where = `candidates[${idx}]${cand && cand.ticker ? ` (${cand.ticker})` : ''}`;
  if (!cand || typeof cand !== 'object') fail(`${where}: must be an object`);
  if (typeof cand.ticker !== 'string' || !cand.ticker) fail(`${where}: ticker is required`);
  if (cand.sleeve !== 'momentum' && cand.sleeve !== 'catalyst') fail(`${where}: sleeve must be "momentum" or "catalyst", got ${JSON.stringify(cand.sleeve)}`);
  if (typeof cand.cluster !== 'string' || !cand.cluster) fail(`${where}: cluster is required`);
  if (cand.confidence === undefined) fail(`${where}: confidence (calibrated P(win)) is required — refusing to default a missing risk input`);
  if (!isFiniteNum(cand.confidence) || cand.confidence < 0 || cand.confidence > 1) fail(`${where}: confidence must be a number in [0,1]`);
  if (cand.upside_pct === undefined) fail(`${where}: upside_pct is required — refusing to default a missing risk input`);
  if (!isFiniteNum(cand.upside_pct) || cand.upside_pct <= 0) fail(`${where}: upside_pct must be a positive number`);
  if (cand.downside_pct === undefined) fail(`${where}: downside_pct is required — refusing to default a missing risk input`);
  if (!isFiniteNum(cand.downside_pct) || cand.downside_pct <= 0) fail(`${where}: downside_pct must be a positive number`);
  if (!isFiniteNum(cand.realized_vol_annual) || cand.realized_vol_annual <= 0) fail(`${where}: realized_vol_annual is required and must be a positive number (feeds the inverse-vol tilt, §4)`);
  if (cand.adv_usd !== undefined && (!isFiniteNum(cand.adv_usd) || cand.adv_usd <= 0)) fail(`${where}: adv_usd, if present, must be a positive number`);
  if (cand.is_binary !== undefined && typeof cand.is_binary !== 'boolean') fail(`${where}: is_binary, if present, must be a boolean`);
}

// ---- Step 1-2: per-name Kelly ----
function computeKelly(cand, kellyFraction) {
  const b = cand.upside_pct / cand.downside_pct;
  const p = cand.confidence;
  const f_full_raw = (p * (b + 1) - 1) / b;
  const f_full = Math.max(0, f_full_raw);
  const f_fractional = f_full * kellyFraction;
  return { b, f_full, f_fractional };
}

// ---- Step 2b: ACROSS-BOOK inverse-vol tilt (risk-and-sizing.md §4) ----
// Kelly sizes on EDGE; it is blind to volatility. Without this step a
// singleton-cluster name never has its vol considered at all, so a 33%-vol
// name and an 18%-vol name at equal conviction get identical weight — the
// book is then Kelly-weighted, not risk-weighted, and its riskiest names
// quietly dominate realized vol.
//
// Fix: scale each f by (refVol / own vol) so dollar-vol contribution is
// ~equal ACROSS the book, not merely within a cluster. refVol is the MEDIAN
// candidate vol, which makes this a relative tilt — the typical position is
// unchanged and gross is not inflated, only redistributed. The multiplier is
// clamped: an unclamped 1/vol on a very low-vol name levers it up several-
// fold on the strength of a vol estimate, which is not what a conviction
// book should do. Clamping keeps the tilt a tilt.
function applyInverseVolTilt(positions) {
  const vols = positions.map((p) => p.realized_vol_annual).sort((a, b) => a - b);
  if (vols.length === 0) return null;
  const mid = Math.floor(vols.length / 2);
  const refVol = vols.length % 2 === 1 ? vols[mid] : (vols[mid - 1] + vols[mid]) / 2;
  if (!isFiniteNum(refVol) || refVol <= 0) return null;

  for (const p of positions) {
    const raw = refVol / p.realized_vol_annual;
    const mult = Math.min(VOL_TILT_MAX, Math.max(VOL_TILT_MIN, raw));
    p.vol_tilt = round(mult, 4);
    p.f_fractional *= mult;
    p.notes.push(
      `inverse-vol tilt x${round(mult, 3)} (vol ${round(p.realized_vol_annual, 4)} vs book median ${round(refVol, 4)})`
      + (Math.abs(raw - mult) > EPS ? ` — clamped from x${round(raw, 3)} into [${VOL_TILT_MIN}, ${VOL_TILT_MAX}]` : '')
    );
  }
  return round(refVol, 6);
}

// ---- Steps 3-4: cluster budget cap, then inverse-vol split within the cluster ----
function sizeClusters(positions) {
  const byCluster = new Map();
  for (const p of positions) {
    if (!byCluster.has(p.cluster)) byCluster.set(p.cluster, []);
    byCluster.get(p.cluster).push(p);
  }
  for (const members of byCluster.values()) {
    const sumF = members.reduce((a, m) => a + m.f_fractional, 0);
    const maxF = Math.max(...members.map((m) => m.f_fractional));
    const clusterBudget = Math.min(sumF, maxF);
    const capped = sumF > maxF + EPS;

    if (members.length === 1) {
      // Singleton cluster: budget == its own f, nothing to redistribute.
      members[0].weight_f = clusterBudget;
      members[0].binding_constraint = 'kelly';
      members[0].notes.push('singleton cluster — no cluster-level redistribution');
      continue;
    }

    const scores = members.map((m) => m.confidence / m.realized_vol_annual);
    const sumScores = scores.reduce((a, b) => a + b, 0);
    members.forEach((m, i) => {
      m.weight_f = sumScores > 0 ? clusterBudget * (scores[i] / sumScores) : 0;
      m.binding_constraint = 'cluster-budget';
      const note = capped
        ? `cluster "${m.cluster}" sum-f (${round(sumF, 4)}) exceeded its largest member's f (${round(maxF, 4)}) — scaled to that cap, then split by confidence/vol`
        : `cluster "${m.cluster}" split by confidence/vol (no sum-cap needed, sum-f=${round(sumF, 4)} <= max-f=${round(maxF, 4)})`;
      m.notes.push(note);
    });
  }
}

// ---- Steps 5-6: book vol-target scalar, then regime dial (last scalar, applied once) ----
function applyBookScalars(positions, bookVolTarget, bookRealizedVol, regimeDial) {
  const s = Math.min(1, bookVolTarget / bookRealizedVol);
  for (const p of positions) {
    p.weight_f *= s;
    if (s < 1 - EPS) {
      p.binding_constraint = 'vol-target';
      p.notes.push(`book vol-target scalar s=${round(s, 4)} (target ${bookVolTarget} / realized ${bookRealizedVol})`);
    }
    p.weight_f *= regimeDial;
    if (regimeDial < 1 - EPS) {
      p.binding_constraint = 'regime-dial';
      p.notes.push(`regime dial ${regimeDial} applied (Stage 1)`);
    }
  }
  return s;
}

// ---- Step 7: hard caps, applied last, never overridden ----
function applyHardCaps(positions, equityUsd) {
  // 7a. Binary-catalyst cap.
  for (const p of positions) {
    if (p.is_binary && p.weight_f > BINARY_CAP + EPS) {
      p.notes.push(`binary-catalyst cap: ${round(p.weight_f * 100, 4)}% -> ${BINARY_CAP * 100}%`);
      p.weight_f = BINARY_CAP;
      p.binding_constraint = 'binary-cap';
    }
  }
  // 7b. Single-name cap.
  for (const p of positions) {
    if (p.weight_f > SINGLE_NAME_CAP + EPS) {
      p.notes.push(`single-name cap: ${round(p.weight_f * 100, 4)}% -> ${SINGLE_NAME_CAP * 100}%`);
      p.weight_f = SINGLE_NAME_CAP;
      p.binding_constraint = 'single-name-cap';
    }
  }
  // 7c. Top-5 combined cap — identify the top 5 by current weight, scale only those pro-rata.
  const byWeightDesc = [...positions].sort((a, b) => b.weight_f - a.weight_f);
  const top5 = byWeightDesc.slice(0, 5);
  const top5Sum = top5.reduce((a, p) => a + p.weight_f, 0);
  let top5Bound = false;
  if (top5Sum > TOP5_CAP + EPS) {
    top5Bound = true;
    const factor = TOP5_CAP / top5Sum;
    for (const p of top5) {
      p.notes.push(`top-5 cap: cluster of top-5 summed ${round(top5Sum * 100, 4)}% -> scaled x${round(factor, 4)} to hit ${TOP5_CAP * 100}%`);
      p.weight_f *= factor;
      p.binding_constraint = 'top5-cap';
    }
  }
  // 7d. Capacity / ADV cap — only when adv_usd is present.
  let advBound = false;
  for (const p of positions) {
    const weightUsd = p.weight_f * equityUsd;
    if (p.adv_usd !== undefined) {
      const advCeilingUsd = ADV_CAP_FRACTION * p.adv_usd;
      if (advCeilingUsd < weightUsd - EPS) {
        advBound = true;
        p.notes.push(`ADV cap: $${round(weightUsd, 2)} -> $${round(advCeilingUsd, 2)} (${ADV_CAP_FRACTION * 100}% of $${p.adv_usd} ADV)`);
        p.weight_f = advCeilingUsd / equityUsd;
        p.binding_constraint = 'adv-cap';
      }
    }
  }
  return { top5Bound, advBound };
}

function runPipeline(input) {
  validateTopLevel(input);
  input.candidates.forEach(validateCandidate);

  const dropped = [];
  const positions = [];

  for (const cand of input.candidates) {
    const { b, f_full, f_fractional } = computeKelly(cand, input.kelly_fraction);
    if (cand.sleeve === 'catalyst' && b < CATALYST_MIN_PAYOFF_RATIO - EPS) {
      dropped.push({ ticker: cand.ticker, reason: 'catalyst-payoff-below-3to1' });
      continue;
    }
    if (f_full <= EPS) {
      dropped.push({ ticker: cand.ticker, reason: 'negative-edge' });
      continue;
    }
    positions.push({
      ticker: cand.ticker,
      sleeve: cand.sleeve,
      cluster: cand.cluster,
      confidence: cand.confidence,
      realized_vol_annual: cand.realized_vol_annual,
      is_binary: !!cand.is_binary,
      adv_usd: cand.adv_usd,
      b,
      f_full,
      f_fractional,
      notes: [],
    });
  }

  // Step 2b runs BEFORE cluster budgeting so the cluster caps bind on
  // vol-adjusted numbers, not raw Kelly (§4).
  const volTiltRefVol = applyInverseVolTilt(positions);
  sizeClusters(positions);
  const s = applyBookScalars(positions, input.book_vol_target, input.book_realized_vol, input.regime_dial);

  const { top5Bound, advBound } = applyHardCaps(positions, input.equity_usd);

  const finalPositions = positions.map((p) => {
    const weightPct = p.weight_f * 100;
    const weightUsd = p.weight_f * input.equity_usd;
    return {
      ticker: p.ticker,
      sleeve: p.sleeve,
      cluster: p.cluster,
      f_full: round(p.f_full, 6),
      f_fractional: round(p.f_fractional, 6),
      realized_vol_annual: p.realized_vol_annual,
      vol_tilt: p.vol_tilt ?? null,
      weight_pct: round(weightPct, 4),
      weight_usd: round(weightUsd, 2),
      binding_constraint: p.binding_constraint,
      notes: p.notes,
    };
  });

  finalPositions.sort((a, b) => b.weight_pct - a.weight_pct);

  const grossPct = finalPositions.reduce((a, p) => a + p.weight_pct, 0);
  const top5Pct = [...finalPositions].sort((a, b) => b.weight_pct - a.weight_pct).slice(0, 5).reduce((a, p) => a + p.weight_pct, 0);
  const clusterWeights = {};
  for (const p of finalPositions) {
    clusterWeights[p.cluster] = round((clusterWeights[p.cluster] || 0) + p.weight_pct, 4);
  }

  return {
    generated_at: new Date().toISOString(),
    inputs_echo: {
      equity_usd: input.equity_usd,
      regime_dial: input.regime_dial,
      book_vol_target: input.book_vol_target,
      book_realized_vol: input.book_realized_vol,
      kelly_fraction: input.kelly_fraction,
      book_vol_target_scalar: round(s, 6),
      vol_tilt_reference_vol: volTiltRefVol,
      n_candidates: input.candidates.length,
    },
    execution: {
      execute: true,
      // No track-record gate: this book is sized for LIVE execution from the first run, at the
      // account owner's explicit direction. The thresholds feeding these weights are unvalidated
      // priors (see the EXECUTION note in the header) — the hard caps are the only backstop.
      note: 'live execution — hard caps (binary 5%, single-name 25%, top-5 60%, ADV 1%) are the only bound on an unvalidated edge',
    },
    positions: finalPositions,
    summary: {
      gross_pct: round(grossPct, 4),
      cash_pct: round(100 - grossPct, 4),
      n_positions: finalPositions.length,
      top5_pct: round(top5Pct, 4),
      cluster_weights: clusterWeights,
      top5_cap_bound: top5Bound,
      adv_cap_bound: advBound,
      dropped,
    },
  };
}

// ---------------------------------------------------------------------------------------------
// Self-test — offline, no network, no input file. Run: node compute-sizing.js --self-test
// ---------------------------------------------------------------------------------------------

function approxEqual(a, b, eps) {
  return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps);
}

function baseInput(candidates, overrides) {
  return Object.assign(
    {
      equity_usd: 25000,
      regime_dial: 1,
      book_vol_target: 0.20,
      book_realized_vol: 0.20,
      kelly_fraction: 0.20,
      candidates,
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

  check('a negative-edge name is dropped with reason "negative-edge"', () => {
    const input = baseInput([
      { ticker: 'BAD', sleeve: 'momentum', cluster: 'solo-bad', confidence: 0.40, upside_pct: 0.10, downside_pct: 0.20, realized_vol_annual: 0.30 },
      { ticker: 'GOOD', sleeve: 'momentum', cluster: 'solo-good', confidence: 0.60, upside_pct: 0.30, downside_pct: 0.10, realized_vol_annual: 0.30 },
    ]);
    const out = runPipeline(input);
    const d = out.summary.dropped.find((x) => x.ticker === 'BAD');
    if (!d) fail('BAD was not present in dropped[]');
    if (d.reason !== 'negative-edge') fail(`expected reason "negative-edge", got "${d.reason}"`);
    if (out.positions.some((p) => p.ticker === 'BAD')) fail('BAD must not appear in positions[]');
  });

  check('a 3-name cluster cannot exceed its largest member\'s f (pre-scalar budget)', () => {
    const input = baseInput(
      [
        { ticker: 'A1', sleeve: 'momentum', cluster: 'semis', confidence: 0.65, upside_pct: 0.30, downside_pct: 0.10, realized_vol_annual: 0.35 },
        { ticker: 'A2', sleeve: 'momentum', cluster: 'semis', confidence: 0.60, upside_pct: 0.28, downside_pct: 0.12, realized_vol_annual: 0.40 },
        { ticker: 'A3', sleeve: 'momentum', cluster: 'semis', confidence: 0.55, upside_pct: 0.25, downside_pct: 0.10, realized_vol_annual: 0.38 },
      ],
      { regime_dial: 1, book_vol_target: 0.20, book_realized_vol: 0.20 }, // s=1, dial=1: isolate cluster math
    );
    const out = runPipeline(input);
    const semis = out.positions.filter((p) => p.cluster === 'semis');
    if (semis.length !== 3) fail(`expected 3 survivors in cluster "semis", got ${semis.length}`);
    const maxF = Math.max(...semis.map((p) => p.f_fractional));
    const sumWeightPct = semis.reduce((a, p) => a + p.weight_pct, 0);
    if (sumWeightPct > maxF * 100 + 1e-2) {
      fail(`cluster sum weight_pct (${sumWeightPct}) exceeds largest member's f_fractional (${maxF * 100}%)`);
    }
    if (!approxEqual(sumWeightPct / 100, maxF, 1e-3)) {
      fail(`with s=1, dial=1 and no hard caps, cluster sum should equal the cap exactly; got sum=${sumWeightPct / 100}, cap=${maxF}`);
    }
  });

  check('a binary-catalyst position is capped at 5% regardless of conviction', () => {
    const input = baseInput([
      { ticker: 'BIN', sleeve: 'momentum', cluster: 'solo-bin', confidence: 0.90, upside_pct: 1.00, downside_pct: 0.10, realized_vol_annual: 0.50, is_binary: true },
    ]);
    const out = runPipeline(input);
    const p = out.positions.find((x) => x.ticker === 'BIN');
    if (!p) fail('BIN missing from positions[]');
    if (!approxEqual(p.weight_pct, 5, 1e-3)) fail(`expected weight_pct=5, got ${p.weight_pct}`);
    if (p.binding_constraint !== 'binary-cap') fail(`expected binding_constraint="binary-cap", got "${p.binding_constraint}"`);
  });

  check('kelly_fraction > 0.25 errors (locked ceiling, not a tunable)', () => {
    const input = baseInput(
      [{ ticker: 'X', sleeve: 'momentum', cluster: 'c', confidence: 0.6, upside_pct: 0.3, downside_pct: 0.1, realized_vol_annual: 0.3 }],
      { kelly_fraction: 0.30 },
    );
    let threw = false;
    try {
      runPipeline(input);
    } catch (err) {
      threw = true;
    }
    if (!threw) fail('expected runPipeline to throw for kelly_fraction=0.30');
  });

  check('a candidate missing confidence/upside/downside errors rather than defaulting', () => {
    const input = baseInput([{ ticker: 'MISSING', sleeve: 'momentum', cluster: 'c', upside_pct: 0.3, downside_pct: 0.1, realized_vol_annual: 0.3 }]);
    let threw = false;
    try {
      runPipeline(input);
    } catch (err) {
      threw = true;
    }
    if (!threw) fail('expected runPipeline to throw for a candidate missing confidence');
  });

  check('book_vol_target outside the locked [0.18, 0.25] band errors', () => {
    const input = baseInput(
      [{ ticker: 'X', sleeve: 'momentum', cluster: 'c', confidence: 0.6, upside_pct: 0.3, downside_pct: 0.1, realized_vol_annual: 0.3 }],
      { book_vol_target: 0.12 },
    );
    let threw = false;
    try {
      runPipeline(input);
    } catch (err) {
      threw = true;
    }
    if (!threw) fail('expected runPipeline to throw for book_vol_target=0.12');
  });

  // Regression guard for the defect this tilt exists to fix: before it, two
  // singleton-cluster names at equal conviction got IDENTICAL weights no
  // matter how far apart their volatilities were.
  check('across-book vol tilt: the lower-vol singleton is sized larger at equal conviction', () => {
    const input = baseInput([
      { ticker: 'LOWVOL', sleeve: 'momentum', cluster: 'a', confidence: 0.6, upside_pct: 0.3, downside_pct: 0.1, realized_vol_annual: 0.18 },
      { ticker: 'HIGHVOL', sleeve: 'momentum', cluster: 'b', confidence: 0.6, upside_pct: 0.3, downside_pct: 0.1, realized_vol_annual: 0.36 },
    ]);
    const out = runPipeline(input);
    const lo = out.positions.find((p) => p.ticker === 'LOWVOL');
    const hi = out.positions.find((p) => p.ticker === 'HIGHVOL');
    if (!lo || !hi) fail('expected both positions to survive');
    if (!(lo.weight_pct > hi.weight_pct + EPS)) {
      fail(`expected LOWVOL (${lo.weight_pct}%) to outweigh HIGHVOL (${hi.weight_pct}%) — vol is being ignored at the position level`);
    }
    // 2x the vol at equal edge should mean ~half the weight, within the clamp.
    const ratio = lo.weight_pct / hi.weight_pct;
    if (ratio < 1.5 || ratio > 2.5) fail(`expected a ~2x weight ratio for a 2x vol gap, got ${round(ratio, 3)}x`);
  });

  // ---- Track-record meta-throttle self-tests ----

  
  
  
  
  return allPass;
}

function main() {
  const arg = process.argv[2];
  if (arg === '--self-test') {
    const ok = runSelfTests();
    process.exit(ok ? 0 : 1);
  }

  let raw;
  try {
    raw = arg ? fs.readFileSync(arg, 'utf8') : fs.readFileSync(0, 'utf8');
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

  process.stdout.write(JSON.stringify(output, null, 2) + '\n');
}

main();
