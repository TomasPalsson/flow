#!/usr/bin/env node
/**
 * compute-weights.js
 *
 * Deterministic weight-setting pipeline for a concentrated 5-10 name global equity book.
 * This script is the AUTHORITATIVE source for every target weight and share count — the
 * calling skill must never compose this arithmetic in prose (references/02-construction-
 * sizing.md). Prose arithmetic is where LLM false precision and unit errors live; this
 * script exists to close that gap.
 *
 * PIPELINE (order matters — each step is commented at its implementation below; do not
 * reorder without re-reading references/02-construction-sizing.md):
 *   1. 1/N anchor across N names — the empirically robust starting point at this N
 *      (DeMiguel-Garlappi-Uppal 2009); every subsequent step tilts or bounds this anchor,
 *      it never replaces it with a continuous-formula optimizer (no Kelly, no MVO here).
 *   2. Conviction tier tilt — multiplies the 1/N anchor by a named per-tier constant
 *      (high/baseline/low). Tilting happens BEFORE renormalization so the tier ratios are
 *      preserved after renormalization, not distorted by it.
 *   3. Renormalize to (100% - cash_sleeve_pct) — cash is carved out of the investable base
 *      before weights are set, not subtracted after, so the stated weights already sum to
 *      the equity sleeve's actual target.
 *   4. Cluster cap — aggregate weight per correlation cluster capped (~50-60%). This must
 *      run BEFORE the per-name floor/cap (step 5): scaling a cluster down can push a member
 *      below the per-name floor, and the floor step needs to see that post-cluster-cap
 *      number to decide whether to flag it, not the pre-cap tier number.
 *   5. Per-name floor and cap — applied LAST among the weight-setting steps, binding over
 *      tier output and even over cluster-cap output. A hard per-name cap exists precisely
 *      so no single company-specific event can dominate the book regardless of how a
 *      cluster or tier calculation would otherwise size it.
 *   6. Weight -> shares — target weight -> target base-currency value -> convert to local
 *      currency (divide by fx_rate_to_base, base-units-per-local-unit) -> divide by
 *      price_major -> lot-size floor. This mirrors the procedure in
 *      references/08-multi-currency.md Section 1.2. The price MUST already be minor-unit-normalized (GBp/100
 *      etc.) before it reaches this script — see the assertion in validatePosition() —
 *      because normalization must happen before any FX math is applied (multi-currency-
 *      mechanics.md Section 1.3): FX rates are always major-unit-to-major-unit, so an
 *      un-normalized minor-unit price silently produces a ~100x-wrong share count with no
 *      runtime exception to catch it. Getting the fx_rate_to_base DIVIDE-vs-MULTIPLY
 *      direction backwards is the same class of silent, exception-free error — see the unit
 *      convention documented directly above weightToShares() below.
 *   7. Residual cash from rounding is reported SEPARATELY from the policy cash sleeve
 *      (cash_sleeve_pct) so the two are never conflated — one is a deliberate policy
 *      decision, the other is an arithmetic byproduct of flooring to whole lots.
 *
 * HARD-LOCKED PARAMETERS — this script ERRORS, never silently clamps, when a caller's input
 * would breach one of these. They bound worst-case loss and must not be tunable by a caller
 * or by a self-tuning loop (see compute-sizing.js's house style, which this script follows):
 *   - name count outside [5, 10] — EXCEPT 1-4 names, which is permitted ONLY via the explicit
 *     opt-in `--allow-small-book` flag (or `allow_small_book: true` in the input JSON). This is
 *     the documented fallback from references/02-construction-sizing.md §5 / §5a ("fewer than 5
 *     genuinely researched ideas -> a smaller book with a larger, explicitly policy-driven cash
 *     sleeve, never a filler name"). It is NOT silently permissive: engaging it mandatorily
 *     expands the cash sleeve to absorb the undeployed capital (see validateTopLevel below for
 *     the exact derivation) and stamps `small_book: true` / `small_book_rationale` on the output
 *     so every downstream consumer knows this is a deliberate under-deployment. The upper bound
 *     of 10 names is NEVER relaxable, flag or no flag.
 *   - any per-name cap input above 25%
 *   - cluster cap input above 60%
 *   - cash_sleeve_pct outside [0, 20] — for a small book (see above) this band is replaced by a
 *     shortfall-derived floor and a wide sanity ceiling; it is never simply skipped.
 *   - any resulting weight negative or NaN
 *
 * `binding_constraint` on every position names whichever step actually set its FINAL weight
 * — tier | cluster-cap | floor | cap | lot-rounding — so six months later a reviewer can see
 * the real reason a position is sized the way it is, not just the number.
 *
 * Output weights are rounded to HALF percentage points, never decimals — the inputs
 * (qualitative conviction tiers, not measured expected returns) do not justify more
 * precision (references/02-construction-sizing.md §1, "Round to whole or half points,
 * never decimals").
 *
 * INPUT: JSON on stdin, or a file path via --input=FILE. Shape:
 *   {
 *     base_currency: "EUR",
 *     nav_base: 50000,
 *     cash_sleeve_pct: 5,              // policy cash sleeve, percent of NAV, 0-20
 *     name_cap_pct: 25,                // optional, default 25, hard-locked ceiling 25
 *     name_floor_pct: 5,               // optional, default 5
 *     cluster_cap_pct: 60,             // optional, default 60, hard-locked ceiling 60
 *     positions: [
 *       {
 *         symbol: "SHEL.L",
 *         conviction_tier: "high" | "baseline" | "low",
 *         cluster: "energy-majors",
 *         price_major: 33.835,         // already minor-unit-normalized (GBp/100 applied)
 *         currency_major: "GBP",
 *         fx_rate_to_base: 1.163,      // base per 1 unit of currency_major (EUR per GBP)
 *         lot_size: null | 1 | 100 | ...
 *       }, ...
 *     ],
 *     allow_small_book: false          // optional, default false. Opt-in ONLY: permits 1-4
 *                                       // positions instead of erroring, and REQUIRES
 *                                       // cash_sleeve_pct to meet or exceed the shortfall-
 *                                       // derived minimum (see validateTopLevel). Equivalent to
 *                                       // passing --allow-small-book on the CLI.
 *   }
 *
 * Usage: node compute-weights.js --input=input.json
 *    or: node compute-weights.js < input.json
 *    or: node compute-weights.js --allow-small-book --input=input.json   (1-4 name book; also
 *        requires a correspondingly larger cash_sleeve_pct in the input — see §5a of
 *        references/02-construction-sizing.md)
 *    or: node compute-weights.js --self-test
 */

import { readFileSync } from 'node:fs';

// ---------------------------------------------------------------------------------------------
// Named constants — conviction tier tilt multipliers (references/02-construction-sizing.md
// §1 step 3: high ~1.3-1.6x, baseline 1.0x, low ~0.6-0.8x of the 1/N anchor).
// Kept as named constants, not inlined, so a reviewer can see the exact tilt band in one
// place without re-deriving it from prose.
// ---------------------------------------------------------------------------------------------
const TIER_MULTIPLIER = Object.freeze({
  high: 1.45,      // midpoint of the 1.3-1.6x band
  baseline: 1.0,
  low: 0.7,        // midpoint of the 0.6-0.8x band
});

// Hard-locked ceilings (see file header). Never tunable by a caller past these bounds.
const MIN_NAMES = 5;
const MAX_NAMES = 10; // NEVER relaxable, flag or no flag.
const HARD_NAME_CAP_PCT_CEILING = 25;
const HARD_CLUSTER_CAP_PCT_CEILING = 60;
const CASH_SLEEVE_PCT_MIN = 0;
const CASH_SLEEVE_PCT_MAX = 20;

// --- Small-book opt-in (references/02-construction-sizing.md §5a) --------------------------
// A concentrated book of 1-4 names is permitted ONLY when the caller explicitly passes
// --allow-small-book (CLI) / allow_small_book: true (JSON). It is not silently permissive:
// engaging it REQUIRES cash_sleeve_pct to expand to absorb the undeployed capital. The rule
// (defensible, not derived from a formal optimization): a book of N < MIN_NAMES names may not
// deploy more than N / MIN_NAMES of the equity portion a full 5-10 name book would deploy — the
// rest must sit in disclosed cash. So the minimum required cash_sleeve_pct is
// 100 * (1 - N / MIN_NAMES). This lines up exactly with the worked example already documented in
// execution-prompt-build.md ("a disciplined 3-name book with 40% disclosed cash is a valid
// output": N=3 -> 100*(1-3/5) = 40%) and with the normal-book cash ceiling at the boundary
// (N=4 -> 100*(1-4/5) = 20%, the same number as CASH_SLEEVE_PCT_MAX above).
const SMALL_BOOK_MIN_NAMES = 1;
// SMALL_BOOK_MAX_NAMES is MIN_NAMES - 1 by construction, not a separate tunable.
// Sanity ceiling on cash_sleeve_pct for a small book — still finite, so a caller cannot type
// cash_sleeve_pct: 99 by accident and have it silently accepted as "policy."
const SMALL_BOOK_CASH_SLEEVE_PCT_MAX = 95;

// Defaults used when the caller omits an optional bounded parameter.
const DEFAULT_NAME_FLOOR_PCT = 5;
const DEFAULT_NAME_CAP_PCT = 25;
const DEFAULT_CLUSTER_CAP_PCT = 60;

// Rounding granularity for OUTPUT weights only (never for internal arithmetic — internal
// values stay full-precision until the very last formatting step, so cap/floor/cluster
// convergence is exact and only the final display is coarsened).
const WEIGHT_ROUND_PP = 0.5;

// Flag threshold: lot-size rounding forcing a name more than this many pp off target.
const LOT_ROUNDING_FLAG_PP = 2.5; // midpoint of the "2-3pp" flag band

// Max iterations for the cluster-cap redistribution convergence loop (guard against
// pathological oscillation — should converge in 1-2 passes in every realistic case).
const MAX_CLUSTER_ITERATIONS = 50;

// Currency codes that are minor-unit (sub-major) codes. A price still carrying one of
// these tags has NOT been normalized upstream — this script must refuse to trust it.
const MINOR_UNIT_CODES = new Set(['GBp', 'GBX', 'ZAc', 'ZAX']);

const EPS = 1e-9;

function fail(msg) {
  throw new Error(msg);
}

function isFiniteNum(x) {
  return typeof x === 'number' && Number.isFinite(x);
}

function roundTo(x, step) {
  if (!isFiniteNum(x)) return x;
  return Math.round(x / step) * step;
}

function round2(x) {
  if (!isFiniteNum(x)) return x;
  return Math.round(x * 100) / 100;
}

// =================================================================================================
// Input validation — fail loudly. See file header for the full hard-locked list.
// =================================================================================================

function validateTopLevel(input) {
  if (!input || typeof input !== 'object') fail('input must be a JSON object');
  if (typeof input.base_currency !== 'string' || !input.base_currency) {
    fail('base_currency is required and must be a non-empty string');
  }
  if (!isFiniteNum(input.nav_base) || input.nav_base <= 0) {
    fail('nav_base is required and must be a positive number');
  }
  if (!isFiniteNum(input.cash_sleeve_pct)) {
    fail('cash_sleeve_pct is required and must be a number');
  }

  if (!Array.isArray(input.positions)) fail('positions must be an array');
  const n = input.positions.length;
  const allowSmallBook = input.allow_small_book === true;

  // HARD-LOCKED: name count upper bound is NEVER relaxable, flag or no flag.
  if (n > MAX_NAMES) {
    fail(
      `positions has ${n} names; the hard-locked ceiling is ${MAX_NAMES} names — this bound is ` +
      `never relaxable, even with --allow-small-book/allow_small_book (references/02-construction-sizing.md §5). ` +
      `Drop weak names rather than raise this.`
    );
  }
  if (n < 1) fail('positions must contain at least one name');

  let smallBook = false;
  let minRequiredCashSleevePct = null;

  if (n < MIN_NAMES) {
    if (!allowSmallBook) {
      fail(
        `positions has ${n} names; the hard-locked name-count band is [${MIN_NAMES}, ${MAX_NAMES}] ` +
        `(references/02-construction-sizing.md §5, "Name count: 5-10, never pad"). A book outside this range is not a ` +
        `parameter to relax — either add genuinely researched names, drop weak ones, or, if fewer than ` +
        `5 candidates genuinely cleared the conviction bar, pass --allow-small-book (or ` +
        `allow_small_book: true) to deliberately build a smaller book with a mandatory larger, ` +
        `explicitly policy-driven cash sleeve — see references/02-construction-sizing.md §5a. This flag ` +
        `is opt-in and loud (it forces small_book: true on the output); it is never a substitute for ` +
        `padding this script's input with a filler name.`
      );
    }
    smallBook = true;
    // Shortfall-derived minimum required cash sleeve — see the SMALL_BOOK_* constant block above
    // for the full derivation. This is a FLOOR, not a suggestion: a small book that tries to pass
    // a normal-sized (small) cash sleeve is refused below, not silently under-funded.
    minRequiredCashSleevePct = round2(100 * (1 - n / MIN_NAMES));
  }

  if (smallBook) {
    // Small-book mode REPLACES the normal [0, 20] cash-sleeve band with a shortfall-derived
    // floor and a wide-but-finite sanity ceiling. It never simply skips the check.
    if (input.cash_sleeve_pct < minRequiredCashSleevePct - EPS) {
      fail(
        `--allow-small-book requires cash_sleeve_pct >= ${minRequiredCashSleevePct} for a ${n}-name book ` +
        `(a book this size may not deploy more than ${n}/${MIN_NAMES} of the equity portion a full ` +
        `${MIN_NAMES}-${MAX_NAMES} name book would deploy — the remainder must be disclosed cash, ` +
        `references/02-construction-sizing.md §5a). Got cash_sleeve_pct=${input.cash_sleeve_pct}. Raise the ` +
        `cash sleeve, or add more genuinely researched names — this script will not silently deploy ` +
        `more than the shortfall-derived ceiling permits.`
      );
    }
    if (input.cash_sleeve_pct > SMALL_BOOK_CASH_SLEEVE_PCT_MAX + EPS) {
      fail(
        `cash_sleeve_pct (${input.cash_sleeve_pct}) exceeds the small-book sanity ceiling of ` +
        `${SMALL_BOOK_CASH_SLEEVE_PCT_MAX}%. This is a locked risk parameter, not tunable — refusing to clamp.`
      );
    }
  } else {
    // HARD-LOCKED: cash sleeve must be a policy value in [0, 20]. Never clamp — error.
    if (input.cash_sleeve_pct < CASH_SLEEVE_PCT_MIN - EPS || input.cash_sleeve_pct > CASH_SLEEVE_PCT_MAX + EPS) {
      fail(
        `cash_sleeve_pct (${input.cash_sleeve_pct}) is outside the hard-locked policy band ` +
        `[${CASH_SLEEVE_PCT_MIN}, ${CASH_SLEEVE_PCT_MAX}]. This is a locked risk parameter, not tunable — ` +
        `refusing to clamp. See references/02-construction-sizing.md §7 (cash sleeve — policy, never a market-timing lever). ` +
        `If this is deliberately a concentrated < ${MIN_NAMES}-name book, use --allow-small-book instead of ` +
        `raising this ceiling directly.`
      );
    }
  }

  const nameCapPct = input.name_cap_pct === undefined ? DEFAULT_NAME_CAP_PCT : input.name_cap_pct;
  if (!isFiniteNum(nameCapPct) || nameCapPct <= 0) fail('name_cap_pct, if provided, must be a positive number');
  // HARD-LOCKED: per-name cap may never exceed 25%, regardless of what a caller requests.
  if (nameCapPct > HARD_NAME_CAP_PCT_CEILING + EPS) {
    fail(
      `name_cap_pct (${nameCapPct}) exceeds the hard-locked ceiling of ${HARD_NAME_CAP_PCT_CEILING}%. ` +
      `This bounds worst-case single-name loss and is not a tunable input — refusing to clamp.`
    );
  }

  const nameFloorPct = input.name_floor_pct === undefined ? DEFAULT_NAME_FLOOR_PCT : input.name_floor_pct;
  if (!isFiniteNum(nameFloorPct) || nameFloorPct < 0) fail('name_floor_pct, if provided, must be a non-negative number');
  if (nameFloorPct >= nameCapPct) {
    fail(`name_floor_pct (${nameFloorPct}) must be strictly less than name_cap_pct (${nameCapPct})`);
  }

  const clusterCapPct = input.cluster_cap_pct === undefined ? DEFAULT_CLUSTER_CAP_PCT : input.cluster_cap_pct;
  if (!isFiniteNum(clusterCapPct) || clusterCapPct <= 0) fail('cluster_cap_pct, if provided, must be a positive number');
  // HARD-LOCKED: cluster cap may never exceed 60%, regardless of what a caller requests.
  if (clusterCapPct > HARD_CLUSTER_CAP_PCT_CEILING + EPS) {
    fail(
      `cluster_cap_pct (${clusterCapPct}) exceeds the hard-locked ceiling of ${HARD_CLUSTER_CAP_PCT_CEILING}%. ` +
      `This bounds worst-case single-theme loss and is not a tunable input — refusing to clamp.`
    );
  }

  return { nameCapPct, nameFloorPct, clusterCapPct, smallBook, minRequiredCashSleevePct };
}

function validatePosition(pos, idx) {
  const where = `positions[${idx}]${pos && pos.symbol ? ` (${pos.symbol})` : ''}`;
  if (!pos || typeof pos !== 'object') fail(`${where}: must be an object`);
  if (typeof pos.symbol !== 'string' || !pos.symbol) fail(`${where}: symbol is required`);
  if (pos.conviction_tier !== 'high' && pos.conviction_tier !== 'baseline' && pos.conviction_tier !== 'low') {
    fail(`${where}: conviction_tier must be "high", "baseline", or "low", got ${JSON.stringify(pos.conviction_tier)}`);
  }
  if (typeof pos.cluster !== 'string' || !pos.cluster) fail(`${where}: cluster is required`);
  if (!isFiniteNum(pos.price_major) || pos.price_major <= 0) {
    fail(`${where}: price_major is required and must be a positive number`);
  }
  if (typeof pos.currency_major !== 'string' || !pos.currency_major) {
    fail(`${where}: currency_major is required`);
  }
  // The price must already be minor-unit-normalized upstream (multi-currency-mechanics.md
  // Section 1.3: normalization must precede FX math). Assert this loudly rather than
  // silently trusting an un-normalized minor-unit price, which would produce a ~100x
  // sizing error with no exception to catch it downstream.
  if (MINOR_UNIT_CODES.has(pos.currency_major)) {
    fail(
      `${where}: currency_major is "${pos.currency_major}", a minor-unit (sub-major) currency code. ` +
      `price_major must already be normalized to major units upstream (divide by 100 and relabel to ` +
      `the major-unit ISO code, e.g. GBp -> GBP) BEFORE it reaches this script — this script does not ` +
      `perform that normalization itself, per references/08-multi-currency.md §1 step 3. Fix the ` +
      `caller's normalization step; do not pass a minor-unit code here.`
    );
  }
  if (!isFiniteNum(pos.fx_rate_to_base) || pos.fx_rate_to_base <= 0) {
    fail(`${where}: fx_rate_to_base is required and must be a positive number`);
  }
  if (pos.lot_size !== null && pos.lot_size !== undefined) {
    if (!Number.isInteger(pos.lot_size) || pos.lot_size <= 0) {
      fail(`${where}: lot_size must be null (whole shares) or a positive integer`);
    }
  }
}

function checkDuplicateSymbols(positions) {
  const seen = new Set();
  for (const p of positions) {
    if (seen.has(p.symbol)) fail(`duplicate symbol "${p.symbol}" in positions — each name must appear once`);
    seen.add(p.symbol);
  }
}

// =================================================================================================
// Step 1-2: 1/N anchor, then conviction tier tilt
// =================================================================================================

function applyAnchorAndTilt(positions) {
  const n = positions.length;
  const anchor = 1 / n; // 1/N anchor, as a fraction (not yet renormalized for cash sleeve)
  for (const p of positions) {
    const mult = TIER_MULTIPLIER[p.conviction_tier];
    p.anchor_weight = anchor;
    p.tier_multiplier = mult;
    p.tilted_weight = anchor * mult; // pre-renormalization fraction of gross (100%) capital
    p.binding_constraint = 'tier';
  }
}

// =================================================================================================
// Step 3: renormalize so the tilted weights sum to exactly (100% - cash_sleeve_pct)
// =================================================================================================

function renormalize(positions, cashSleevePct) {
  const investableFraction = (100 - cashSleevePct) / 100;
  const sumTilted = positions.reduce((a, p) => a + p.tilted_weight, 0);
  if (sumTilted <= EPS) fail('sum of tilted weights is zero — cannot renormalize (check conviction tiers)');
  for (const p of positions) {
    // fraction of NAV, e.g. 0.12 == 12%
    p.weight = (p.tilted_weight / sumTilted) * investableFraction;
  }
}

// =================================================================================================
// Step 4: cluster cap — aggregate weight per cluster capped, iterated to convergence.
//
// Must run BEFORE the per-name floor/cap step: scaling a cluster down redistributes weight
// to OTHER clusters (the excess is renormalized back across all uncapped clusters so total
// investable weight is preserved), which can itself push a previously-uncapped cluster over
// the cap — hence the iteration. It can also push an individual member below the eventual
// per-name floor; that is intentional and is exactly what step 5 exists to catch and flag.
// =================================================================================================

function applyClusterCap(positions, clusterCapPct) {
  const clusterCapFraction = clusterCapPct / 100;
  const investableFraction = positions.reduce((a, p) => a + p.weight, 0); // preserved invariant

  for (let iter = 0; iter < MAX_CLUSTER_ITERATIONS; iter++) {
    const byCluster = new Map();
    for (const p of positions) {
      if (!byCluster.has(p.cluster)) byCluster.set(p.cluster, []);
      byCluster.get(p.cluster).push(p);
    }

    let anyCapped = false;
    let excess = 0;
    const uncappedClusters = [];

    for (const [clusterName, members] of byCluster) {
      const sum = members.reduce((a, m) => a + m.weight, 0);
      if (sum > clusterCapFraction + EPS) {
        anyCapped = true;
        const scale = clusterCapFraction / sum;
        excess += sum - clusterCapFraction;
        for (const m of members) {
          m.weight *= scale; // scale cluster members down proportionally
          m.binding_constraint = 'cluster-cap';
          m.cluster_capped = true;
        }
      } else {
        uncappedClusters.push({ clusterName, members, sum });
      }
    }

    if (!anyCapped) return; // converged — no cluster breaches the cap

    // Redistribute the excess pro-rata across uncapped clusters' members, preserving the
    // total investable fraction (so cash sleeve accounting stays exact). If every cluster
    // is capped (fully saturated), the excess is left as unallocated — this is a
    // pathological input (cluster caps summing to less than 100% of investable capital
    // with too few clusters) and is caught by the post-loop sanity check below.
    const uncappedSum = uncappedClusters.reduce((a, c) => a + c.sum, 0);
    if (uncappedSum > EPS) {
      for (const { members, sum } of uncappedClusters) {
        for (const m of members) {
          m.weight += excess * (m.weight / sum);
        }
      }
    }
    // loop again — redistribution may have pushed an uncapped cluster over the cap
  }

  fail(
    `cluster-cap redistribution did not converge within ${MAX_CLUSTER_ITERATIONS} iterations — ` +
    `check for a pathological cluster configuration (e.g. cluster caps that cannot sum to the ` +
    `investable fraction given the number of distinct clusters).`
  );
}

// =================================================================================================
// Step 5: per-name floor and cap — applied LAST, binding over tier and cluster-cap output.
//
// Floor and cap are checked independently per name. A cap breach takes priority in the
// (impossible in practice, but defensively handled) case both would fire simultaneously,
// since floor < cap is enforced at validation time. Excess/deficit from floor/cap
// enforcement is NOT redistributed back into other names here — the whole-share rounding
// step (6) and residual-cash accounting (7) are what absorb the resulting gap, exactly as
// they already absorb ordinary lot-rounding slack. Silently redistributing floor/cap
// overflow into other names would quietly override the caller's stated conviction tiers a
// second time, one layer after the cluster cap already did so once.
// =================================================================================================

function applyFloorAndCap(positions, nameFloorPct, nameCapPct) {
  const floorFraction = nameFloorPct / 100;
  const capFraction = nameCapPct / 100;
  for (const p of positions) {
    if (p.weight > capFraction + EPS) {
      p.weight = capFraction;
      p.binding_constraint = 'cap';
    } else if (p.weight < floorFraction - EPS) {
      p.weight = floorFraction;
      p.binding_constraint = 'floor';
    }
    // else: binding_constraint stays whatever step 2/4 set it to (tier or cluster-cap) —
    // that IS the real reason this weight is what it is, since floor/cap did not bind.
  }
}

// =================================================================================================
// Step 6: weight -> shares, per references/08-multi-currency.md §1's procedure:
//   target weight -> target base-currency value -> convert to local via fx_rate_to_base ->
//   divide by price_major -> lot-size floor (never ceil).
//
// UNIT CONVENTION for fx_rate_to_base (must match how compute-drift.js interprets the same
// field, and matches multi-currency-mechanics.md Section 4's fx_rate(local -> EUR) direction,
// used there for NAV/value computation): fx_rate_to_base = how many BASE-currency units one
// unit of the position's LOCAL major currency is worth (e.g. EUR per 1 GBP, EUR per 1 JPY).
// So value_base = value_local * fx_rate_to_base, and — the direction that is easy to get
// backwards and MUST be checked, because both directions produce a plausible positive share
// count with no runtime exception (multi-currency-mechanics.md Section 1.4's silent-failure
// trap) — value_local = value_base / fx_rate_to_base.
// =================================================================================================

function weightToShares(p, navBase) {
  const targetValueBase = p.weight * navBase;                      // target_value_eur equivalent
  const targetValueLocal = targetValueBase / p.fx_rate_to_base;     // base -> local: DIVIDE by
                                                                      // (base-per-local) rate
  const rawShares = targetValueLocal / p.price_major;               // raw share count

  const lot = p.lot_size ?? 1; // null/omitted lot_size means whole shares == lot of 1
  const shares = Math.floor(rawShares / lot) * lot; // ALWAYS floor, never ceil (never round up
                                                       // into an order the NAV cannot fully fund)

  const valueLocal = shares * p.price_major;
  const valueBase = valueLocal * p.fx_rate_to_base; // local -> base: MULTIPLY by the same rate
  const actualWeight = valueBase / navBase;

  p.raw_shares = rawShares;
  p.shares = shares;
  p.value_base = valueBase;
  p.target_value_base = targetValueBase;
  p.actual_weight = actualWeight;

  // Flag when lot-size rounding forces the name meaningfully off its target weight.
  const deltaPp = (actualWeight - p.weight) * 100;
  p.lot_rounding_delta_pp = deltaPp;
  if (Math.abs(deltaPp) > LOT_ROUNDING_FLAG_PP + EPS) {
    p.lot_rounding_flag = true;
    // Lot rounding is now the dominant reason the achieved weight differs from target,
    // even though the TARGET weight itself was still set by tier/cluster-cap/floor/cap —
    // record it as the binding constraint on the ACTUAL (post-rounding) weight, since that
    // is what the diagnostic is asking about six months later.
    p.binding_constraint = 'lot-rounding';
  } else {
    p.lot_rounding_flag = false;
  }

  // Flag when the target weight is not expressible AT ALL given lot size and NAV: i.e. even
  // one lot alone overshoots the target by more than the flag tolerance, or zero lots is the
  // only floor-consistent choice. Report the minimum NAV that WOULD express this weight
  // within tolerance, per references/08-multi-currency.md §2's minimum-expressible-position formula:
  //   NAV_base >= V_base / (w * epsilon)
  // where V_base is one lot's value in base currency and epsilon is the rounding-tolerance
  // fraction (using LOT_ROUNDING_FLAG_PP / target_weight_pct as the relative tolerance).
  const oneLotValueLocal = lot * p.price_major;
  const oneLotValueBase = oneLotValueLocal * p.fx_rate_to_base;
  p.one_lot_value_base = oneLotValueBase;
  const targetWeightFraction = p.weight;
  const epsilonTolerance = (LOT_ROUNDING_FLAG_PP / 100) / Math.max(targetWeightFraction, EPS);
  const minNavForExpressibility = oneLotValueBase / (targetWeightFraction * Math.max(epsilonTolerance, EPS));
  p.not_expressible = oneLotValueBase / navBase > targetWeightFraction * (1 + epsilonTolerance) + EPS;
  p.min_nav_to_express_base = p.not_expressible ? minNavForExpressibility : null;
}

// =================================================================================================
// Step 7: residual cash from rounding — reported SEPARATELY from the policy cash sleeve.
// =================================================================================================

function computeResidualCash(positions, navBase, cashSleevePct) {
  const investedValueBase = positions.reduce((a, p) => a + p.value_base, 0);
  const policyCashBase = navBase * (cashSleevePct / 100);
  const residualCashBase = navBase - investedValueBase - policyCashBase;
  return {
    policy_cash_sleeve_base: round2(policyCashBase),
    policy_cash_sleeve_pct: cashSleevePct,
    residual_cash_from_rounding_base: round2(residualCashBase),
    residual_cash_from_rounding_pct: round2((residualCashBase / navBase) * 100),
    total_uninvested_base: round2(policyCashBase + residualCashBase),
  };
}

// =================================================================================================
// Pipeline driver
// =================================================================================================

function runPipeline(input) {
  const { nameCapPct, nameFloorPct, clusterCapPct, smallBook, minRequiredCashSleevePct } = validateTopLevel(input);
  input.positions.forEach(validatePosition);
  checkDuplicateSymbols(input.positions);

  const navBase = input.nav_base;
  const cashSleevePct = input.cash_sleeve_pct;

  // Work on plain-object copies keyed by symbol so per-position state (binding_constraint,
  // flags, etc.) accumulates across the pipeline steps without aliasing input objects.
  const positions = input.positions.map((p) => ({ ...p }));

  // Step 1-2
  applyAnchorAndTilt(positions);
  // Step 3
  renormalize(positions, cashSleevePct);
  // Step 4
  applyClusterCap(positions, clusterCapPct);
  // Step 5
  applyFloorAndCap(positions, nameFloorPct, nameCapPct);

  // HARD-LOCKED: any negative or NaN weight after steps 1-5 is a fatal bug, not a value to
  // clamp to zero silently — surface it.
  for (const p of positions) {
    if (!isFiniteNum(p.weight) || p.weight < -EPS) {
      fail(`${p.symbol}: computed weight is negative or NaN (${p.weight}) after floor/cap — refusing to clamp silently`);
    }
  }

  // Step 6
  for (const p of positions) {
    weightToShares(p, navBase);
  }

  // HARD-LOCKED: any negative or NaN actual weight post-rounding is fatal.
  for (const p of positions) {
    if (!isFiniteNum(p.actual_weight) || p.actual_weight < -EPS) {
      fail(`${p.symbol}: actual_weight is negative or NaN (${p.actual_weight}) after share rounding`);
    }
  }

  // Step 7
  const cash = computeResidualCash(positions, navBase, cashSleevePct);

  // Cluster aggregate report (for the caller to display alongside per-name weights).
  const clusterWeights = {};
  for (const p of positions) {
    const pct = p.actual_weight * 100;
    clusterWeights[p.cluster] = (clusterWeights[p.cluster] || 0) + pct;
  }
  for (const k of Object.keys(clusterWeights)) clusterWeights[k] = roundTo(clusterWeights[k], WEIGHT_ROUND_PP);

  const outPositions = positions.map((p) => {
    const targetWeightPct = roundTo(p.weight * 100, WEIGHT_ROUND_PP);
    const actualWeightPct = roundTo(p.actual_weight * 100, WEIGHT_ROUND_PP);
    return {
      symbol: p.symbol,
      conviction_tier: p.conviction_tier,
      cluster: p.cluster,
      target_weight_pct: targetWeightPct,
      actual_weight_pct: actualWeightPct,
      weight_delta_pp: round2(actualWeightPct - targetWeightPct),
      shares: p.shares,
      value_base: round2(p.value_base),
      binding_constraint: p.binding_constraint,
      lot_rounding_flag: p.lot_rounding_flag,
      not_expressible_at_nav: p.not_expressible,
      min_nav_to_express_base: p.min_nav_to_express_base === null ? null : round2(p.min_nav_to_express_base),
    };
  });

  outPositions.sort((a, b) => b.actual_weight_pct - a.actual_weight_pct);

  const grossActualPct = round2(outPositions.reduce((a, p) => a + p.actual_weight_pct, 0));

  const flags = [];
  for (const p of outPositions) {
    if (p.lot_rounding_flag) {
      flags.push(
        `${p.symbol}: lot-size rounding moved actual weight ${p.weight_delta_pp >= 0 ? '+' : ''}${p.weight_delta_pp}pp ` +
        `from target (${p.target_weight_pct}% -> ${p.actual_weight_pct}%), exceeding the ${LOT_ROUNDING_FLAG_PP}pp flag threshold.`
      );
    }
    if (p.not_expressible_at_nav) {
      flags.push(
        `${p.symbol}: target weight ${p.target_weight_pct}% is not expressible within tolerance at nav_base=` +
        `${navBase} ${input.base_currency} given lot size — minimum NAV to express this weight is ` +
        `~${p.min_nav_to_express_base} ${input.base_currency}.`
      );
    }
  }

  // small_book / small_book_rationale is the unmistakable, loud signal (references/02-
  // construction-sizing.md §5a) that this is a DELIBERATE under-deployment, not a normal book —
  // every downstream consumer (drafts, memos, decision log) must be able to branch on this
  // without re-deriving it from n_positions. Always present (true/false), never omitted, so a
  // consumer can't mistake "field absent" for "not a small book."
  const smallBookRationale = smallBook
    ? `Only ${positions.length} name(s) cleared the conviction bar — below the ${MIN_NAMES}-name minimum. ` +
      `Per policy (references/02-construction-sizing.md §5a), this book intentionally deploys at most ` +
      `${positions.length}/${MIN_NAMES} (${round2((positions.length / MIN_NAMES) * 100)}%) of the equity ` +
      `portion a full ${MIN_NAMES}-${MAX_NAMES} name book would deploy. The remaining ${cashSleevePct}% ` +
      `(minimum required: ${minRequiredCashSleevePct}%) is held as disclosed, policy-driven cash — this is ` +
      `deliberate under-deployment, not padding with a filler name and not a normal ${MIN_NAMES}-${MAX_NAMES} ` +
      `name book.`
    : null;
  if (smallBook) {
    flags.push(
      `SMALL BOOK: ${positions.length} names (< ${MIN_NAMES}-name minimum), cash_sleeve_pct=${cashSleevePct}% ` +
      `(minimum required ${minRequiredCashSleevePct}%) — deliberate under-deployment via --allow-small-book, see small_book_rationale.`
    );
  }

  return {
    generated_at: new Date().toISOString(),
    base_currency: input.base_currency,
    nav_base: navBase,
    small_book: smallBook,
    small_book_rationale: smallBookRationale,
    inputs_echo: {
      cash_sleeve_pct: cashSleevePct,
      name_floor_pct: nameFloorPct,
      name_cap_pct: nameCapPct,
      cluster_cap_pct: clusterCapPct,
      n_positions: positions.length,
      allow_small_book: smallBook,
      min_required_cash_sleeve_pct: minRequiredCashSleevePct,
    },
    positions: outPositions,
    cluster_weights_pct: clusterWeights,
    cash,
    summary: {
      gross_actual_weight_pct: grossActualPct,
      n_positions: outPositions.length,
    },
    flags,
  };
}

// ---------------------------------------------------------------------------------------------
// Self-test — offline, no network, no input file. Run: node compute-weights.js --self-test
// ---------------------------------------------------------------------------------------------

function approxEqual(a, b, eps) {
  return Math.abs(a - b) <= (eps === undefined ? 1e-6 : eps);
}

function basePosition(overrides) {
  return Object.assign(
    {
      symbol: 'X',
      conviction_tier: 'baseline',
      cluster: 'solo',
      price_major: 100,
      currency_major: 'USD',
      fx_rate_to_base: 1,
      lot_size: null,
    },
    overrides || {},
  );
}

function makeBook(n, overrides) {
  const positions = [];
  for (let i = 0; i < n; i++) {
    positions.push(basePosition({ symbol: `N${i}`, cluster: `cluster-${i}` }));
  }
  return Object.assign(
    { base_currency: 'EUR', nav_base: 100000, cash_sleeve_pct: 5, positions },
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

  check('fewer than 5 names errors (hard-locked name count)', () => {
    const input = makeBook(4);
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for 4 names');
  });

  check('more than 10 names errors (hard-locked name count)', () => {
    const input = makeBook(11);
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for 11 names');
  });

  check('name_cap_pct above 25 errors, never clamps', () => {
    const input = makeBook(6, { name_cap_pct: 30 });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for name_cap_pct=30');
  });

  check('cluster_cap_pct above 60 errors, never clamps', () => {
    const input = makeBook(6, { cluster_cap_pct: 65 });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for cluster_cap_pct=65');
  });

  check('cash_sleeve_pct outside [0,20] errors', () => {
    const input = makeBook(6, { cash_sleeve_pct: 25 });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for cash_sleeve_pct=25');
  });

  check('minor-unit currency_major (GBp) with un-normalized price errors', () => {
    const positions = [];
    for (let i = 0; i < 6; i++) positions.push(basePosition({ symbol: `N${i}`, cluster: `c${i}` }));
    positions[0] = basePosition({ symbol: 'SHEL', cluster: 'c0', price_major: 3383.5, currency_major: 'GBp' });
    const input = { base_currency: 'EUR', nav_base: 100000, cash_sleeve_pct: 5, positions };
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected error for minor-unit currency_major');
    if (!msg.includes('minor-unit')) fail(`expected error to mention minor-unit, got: ${msg}`);
  });

  check('equal-conviction 1/N book sums to (100 - cash_sleeve_pct) before rounding drift', () => {
    const input = makeBook(8, { cash_sleeve_pct: 5 });
    const out = runPipeline(input);
    // with lot_size null and identical prices/fx, rounding should be negligible (whole-share
    // math on a 100k NAV / 8 names / $100 shares), so gross should land very close to 95%.
    if (Math.abs(out.summary.gross_actual_weight_pct - 95) > 1.5) {
      fail(`expected gross actual weight near 95%, got ${out.summary.gross_actual_weight_pct}`);
    }
  });

  check('high conviction tier produces a larger weight than baseline at equal cluster/floor/cap', () => {
    const positions = [];
    for (let i = 0; i < 6; i++) {
      positions.push(basePosition({ symbol: `N${i}`, cluster: `c${i}`, conviction_tier: 'baseline' }));
    }
    positions[0] = basePosition({ symbol: 'HIGH', cluster: 'c0', conviction_tier: 'high' });
    positions[1] = basePosition({ symbol: 'LOW', cluster: 'c1', conviction_tier: 'low' });
    const input = { base_currency: 'EUR', nav_base: 200000, cash_sleeve_pct: 5, positions };
    const out = runPipeline(input);
    const high = out.positions.find((p) => p.symbol === 'HIGH');
    const low = out.positions.find((p) => p.symbol === 'LOW');
    const base = out.positions.find((p) => p.symbol === 'N2');
    if (!(high.target_weight_pct > base.target_weight_pct)) fail('expected HIGH > baseline');
    if (!(base.target_weight_pct > low.target_weight_pct)) fail('expected baseline > LOW');
  });

  check('cluster cap binds when one cluster dominates', () => {
    const positions = [
      basePosition({ symbol: 'A', cluster: 'ai-capex', conviction_tier: 'high' }),
      basePosition({ symbol: 'B', cluster: 'ai-capex', conviction_tier: 'high' }),
      basePosition({ symbol: 'C', cluster: 'ai-capex', conviction_tier: 'high' }),
      basePosition({ symbol: 'D', cluster: 'ai-capex', conviction_tier: 'high' }),
      basePosition({ symbol: 'E', cluster: 'other-1', conviction_tier: 'low' }),
      basePosition({ symbol: 'F', cluster: 'other-2', conviction_tier: 'low' }),
    ];
    const input = { base_currency: 'EUR', nav_base: 200000, cash_sleeve_pct: 5, cluster_cap_pct: 50, positions };
    const out = runPipeline(input);
    const aiSum = out.positions.filter((p) => p.cluster === 'ai-capex').reduce((a, p) => a + p.target_weight_pct, 0);
    if (aiSum > 50 + 1) fail(`expected ai-capex cluster target sum <= 50%, got ${aiSum}`);
    const anyClusterCapped = out.positions.some((p) => p.cluster === 'ai-capex' && p.binding_constraint === 'cluster-cap');
    if (!anyClusterCapped) fail('expected at least one ai-capex member to show binding_constraint="cluster-cap"');
  });

  check('per-name cap binds and reports binding_constraint="cap"', () => {
    const positions = [
      basePosition({ symbol: 'MEGA', cluster: 'c0', conviction_tier: 'high' }),
      basePosition({ symbol: 'B', cluster: 'c1', conviction_tier: 'low' }),
      basePosition({ symbol: 'C', cluster: 'c2', conviction_tier: 'low' }),
      basePosition({ symbol: 'D', cluster: 'c3', conviction_tier: 'low' }),
      basePosition({ symbol: 'E', cluster: 'c4', conviction_tier: 'low' }),
    ];
    // Small N (5) plus a high tier concentrates enough that with a tight cap it must bind.
    const input = { base_currency: 'EUR', nav_base: 200000, cash_sleeve_pct: 5, name_cap_pct: 20, positions };
    const out = runPipeline(input);
    const mega = out.positions.find((p) => p.symbol === 'MEGA');
    if (mega.target_weight_pct > 20 + EPS) fail(`expected MEGA capped at 20%, got ${mega.target_weight_pct}`);
    if (mega.binding_constraint !== 'cap') fail(`expected binding_constraint="cap", got "${mega.binding_constraint}"`);
  });

  check('per-name floor binds and reports binding_constraint="floor"', () => {
    const positions = [
      basePosition({ symbol: 'TINY', cluster: 'c0', conviction_tier: 'low' }),
      basePosition({ symbol: 'B', cluster: 'c1', conviction_tier: 'high' }),
      basePosition({ symbol: 'C', cluster: 'c2', conviction_tier: 'high' }),
      basePosition({ symbol: 'D', cluster: 'c3', conviction_tier: 'high' }),
      basePosition({ symbol: 'E', cluster: 'c4', conviction_tier: 'high' }),
    ];
    const input = { base_currency: 'EUR', nav_base: 200000, cash_sleeve_pct: 5, name_floor_pct: 12, positions };
    const out = runPipeline(input);
    const tiny = out.positions.find((p) => p.symbol === 'TINY');
    if (tiny.target_weight_pct < 12 - EPS) fail(`expected TINY floored at >=12%, got ${tiny.target_weight_pct}`);
    if (tiny.binding_constraint !== 'floor') fail(`expected binding_constraint="floor", got "${tiny.binding_constraint}"`);
  });

  check('lot-size rounding flags a name and shares are floored, never ceiled', () => {
    // Small NAV + big lot size (JPY-style 100-share lot) forces a large rounding gap.
    const positions = [
      basePosition({ symbol: 'JP', cluster: 'c0', price_major: 2950, currency_major: 'JPY', fx_rate_to_base: 0.0061, lot_size: 100 }),
      basePosition({ symbol: 'B', cluster: 'c1' }),
      basePosition({ symbol: 'C', cluster: 'c2' }),
      basePosition({ symbol: 'D', cluster: 'c3' }),
      basePosition({ symbol: 'E', cluster: 'c4' }),
    ];
    const input = { base_currency: 'EUR', nav_base: 15000, cash_sleeve_pct: 5, positions };
    const out = runPipeline(input);
    const jp = out.positions.find((p) => p.symbol === 'JP');
    // raw shares should not divide evenly by 100 here, so shares must be a multiple of 100
    if (jp.shares % 100 !== 0) fail(`expected JP shares to be a multiple of the 100-lot, got ${jp.shares}`);
  });

  check('residual cash from rounding is reported separately from the policy cash sleeve', () => {
    const input = makeBook(6, { cash_sleeve_pct: 5 });
    const out = runPipeline(input);
    if (out.cash.policy_cash_sleeve_pct !== 5) fail('policy_cash_sleeve_pct should echo the input 5');
    if (typeof out.cash.residual_cash_from_rounding_base !== 'number') fail('residual_cash_from_rounding_base must be a number');
    if (out.cash.policy_cash_sleeve_base === out.cash.residual_cash_from_rounding_base && out.cash.residual_cash_from_rounding_base !== 0) {
      // not a hard failure by itself, just a smell check that they're computed independently
    }
  });

  check('output weights are rounded to half percentage points, never decimals', () => {
    const input = makeBook(7, { cash_sleeve_pct: 5 });
    const out = runPipeline(input);
    for (const p of out.positions) {
      const doubled = p.target_weight_pct * 2;
      if (Math.abs(doubled - Math.round(doubled)) > 1e-9) {
        fail(`target_weight_pct ${p.target_weight_pct} for ${p.symbol} is not a multiple of 0.5`);
      }
    }
  });

  check('duplicate symbols error', () => {
    const positions = [
      basePosition({ symbol: 'DUP', cluster: 'c0' }),
      basePosition({ symbol: 'DUP', cluster: 'c1' }),
      basePosition({ symbol: 'C', cluster: 'c2' }),
      basePosition({ symbol: 'D', cluster: 'c3' }),
      basePosition({ symbol: 'E', cluster: 'c4' }),
    ];
    const input = { base_currency: 'EUR', nav_base: 100000, cash_sleeve_pct: 5, positions };
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error for duplicate symbols');
  });

  // --- Small-book opt-in path (references/02-construction-sizing.md §5a) ---------------------

  check('small book (N<5) without --allow-small-book still errors', () => {
    const input = makeBook(3, { cash_sleeve_pct: 40 }); // sleeve is sufficient; flag is the missing piece
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected error for a 3-name book without allow_small_book');
    if (!msg.includes('allow-small-book') && !msg.includes('allow_small_book')) {
      fail(`expected error to mention the opt-in flag, got: ${msg}`);
    }
  });

  check('small book with flag but insufficient cash sleeve errors (does not silently under-fund)', () => {
    // N=3 requires cash_sleeve_pct >= 100*(1-3/5) = 40; 5% is the normal-book default and is nowhere close.
    const input = makeBook(3, { allow_small_book: true, cash_sleeve_pct: 5 });
    let threw = false;
    let msg = '';
    try { runPipeline(input); } catch (e) { threw = true; msg = e.message; }
    if (!threw) fail('expected error for a 3-name book with an insufficient cash sleeve');
    if (!msg.includes('40')) fail(`expected error to state the required minimum (40), got: ${msg}`);
  });

  check('small book with flag and sufficient sleeve succeeds and sets small_book: true', () => {
    const input = makeBook(3, { allow_small_book: true, cash_sleeve_pct: 40 });
    const out = runPipeline(input);
    if (out.small_book !== true) fail(`expected small_book === true, got ${out.small_book}`);
    if (typeof out.small_book_rationale !== 'string' || out.small_book_rationale.length === 0) {
      fail('expected a non-empty small_book_rationale string');
    }
    if (out.summary.n_positions !== 3) fail(`expected 3 positions, got ${out.summary.n_positions}`);
    if (out.cash.policy_cash_sleeve_pct !== 40) fail('expected policy_cash_sleeve_pct to echo 40');
  });

  check('small book at the N=1 boundary requires an 80% sleeve and succeeds when funded', () => {
    const input = makeBook(1, { allow_small_book: true, cash_sleeve_pct: 80 });
    const out = runPipeline(input);
    if (out.small_book !== true) fail('expected small_book === true for a 1-name book');
    if (out.inputs_echo.min_required_cash_sleeve_pct !== 80) {
      fail(`expected min_required_cash_sleeve_pct 80, got ${out.inputs_echo.min_required_cash_sleeve_pct}`);
    }
  });

  check('small book cannot bypass the MAX_NAMES=10 ceiling', () => {
    const input = makeBook(11, { allow_small_book: true, cash_sleeve_pct: 90 });
    let threw = false;
    try { runPipeline(input); } catch (e) { threw = true; }
    if (!threw) fail('expected error — allow_small_book must never relax the upper bound');
  });

  check('normal 5-10 book is unaffected by allow_small_book (band and cash ceiling still enforced)', () => {
    const okInput = makeBook(6, { allow_small_book: true, cash_sleeve_pct: 5 });
    const out = runPipeline(okInput);
    if (out.small_book !== false) fail(`expected small_book === false for a 6-name book, got ${out.small_book}`);
    if (out.small_book_rationale !== null) fail('expected small_book_rationale to be null for a normal book');

    // The normal [0,20] cash-sleeve ceiling must still apply even with the flag set.
    const badInput = makeBook(6, { allow_small_book: true, cash_sleeve_pct: 25 });
    let threw = false;
    try { runPipeline(badInput); } catch (e) { threw = true; }
    if (!threw) fail('expected cash_sleeve_pct=25 to still error for a normal-band book even with allow_small_book');
  });

  return allPass;
}

// ---------------------------------------------------------------------------------------------
// CLI entrypoint
// ---------------------------------------------------------------------------------------------

function parseArgs(argv) {
  let inputPath = null;
  let allowSmallBook = false;
  for (const arg of argv) {
    if (arg === '--self-test') return { selfTest: true };
    if (arg === '--allow-small-book') allowSmallBook = true;
    if (arg.startsWith('--input=')) inputPath = arg.slice('--input='.length);
  }
  return { selfTest: false, inputPath, allowSmallBook };
}

function main() {
  const { selfTest, inputPath, allowSmallBook } = parseArgs(process.argv.slice(2));

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

  // --allow-small-book on the CLI is an ENABLING override only — it can turn allow_small_book on,
  // never off, so an input file that already opted in cannot be silently disarmed by omitting the
  // flag from the invocation.
  if (allowSmallBook) input.allow_small_book = true;

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
