#!/usr/bin/env node
'use strict';

/**
 * scorecard.js — deterministic idea scorecard with BLOCKING dimensions.
 *
 * This is an anti-sycophancy commitment device, not a calculator. Its whole
 * purpose is that it CANNOT be talked out of a fatal verdict: if a blocking
 * dimension scores below threshold, the verdict is DO-NOT-PROCEED regardless of
 * how strong everything else is. That removes the model's discretion to "average
 * away" a fatal flaw — the most common way a soft critique launders a bad idea.
 *
 * Usage:
 *   node scorecard.js '<json>'      # JSON object of dimension -> score (1..5)
 *   echo '<json>' | node scorecard.js
 *   node scorecard.js --dimensions  # print the dimension reference and exit
 *
 * Example:
 *   node scorecard.js '{"problem_reality":4,"market_evidence":2,"team_fit":3,
 *     "graveyard_clearance":1,"distribution":2,"unit_economics":3,"timing":2}'
 *
 * Scores are 1 (fatal/absent) .. 5 (strong, well-evidenced). Score the QUALITY OF
 * THE EVIDENCE for each leg, not your hope for it. Partial scoring is allowed:
 * omit dimensions you genuinely cannot assess (they're excluded from the composite
 * and listed as UNSCORED — an unscored blocking dimension is itself a finding).
 */

// Dimension definitions. `blocking: true` means: below `threshold` kills the verdict.
const DIMENSIONS = [
  { key: 'problem_reality',     label: 'Problem reality',        blocking: true,
    help: 'Evidence the problem is real, painful, and frequent for the stated user.' },
  { key: 'graveyard_clearance', label: 'Graveyard clearance',    blocking: true,
    help: 'Quality of analysis of who tried this before and died, and why that does not apply.' },
  { key: 'market_evidence',     label: 'Market-size evidence',   blocking: false,
    help: 'Quality of the market-size evidence (NOT the size itself).' },
  { key: 'team_fit',            label: 'Team domain fit',        blocking: false,
    help: 'Specific (not general) domain expertise alignment.' },
  { key: 'distribution',        label: 'Distribution clarity',   blocking: true,
    help: 'Specificity of the customer-acquisition mechanism. "SEO + word of mouth" is not a plan.' },
  { key: 'unit_economics',      label: 'Unit economics',         blocking: false,
    help: 'Whether rough CAC / LTV / payback math exists and survives scrutiny.' },
  { key: 'timing',              label: 'Timing evidence',        blocking: false,
    help: 'Specific evidence that NOW is the moment (a dated enabler), not "the market is growing".' },
];

const THRESHOLD = 2;   // a blocking dimension at or below this kills the verdict
const MIN = 1, MAX = 5;

function printDimensions() {
  console.log('\nScorecard dimensions (score 1..5 = absent/fatal .. strong+evidenced):\n');
  for (const d of DIMENSIONS) {
    const tag = d.blocking ? '  [BLOCKING]' : '';
    console.log(`  ${d.key}${tag}`);
    console.log(`     ${d.label} — ${d.help}`);
  }
  console.log(`\n  A BLOCKING dimension at or below ${THRESHOLD} forces VERDICT: DO NOT PROCEED.\n`);
}

function fail(msg) {
  console.error(`\nscorecard error: ${msg}\n`);
  console.error("Run `node scorecard.js --dimensions` to see valid keys and the scoring scale.\n");
  process.exit(1);
}

function readStdin() {
  try {
    return require('fs').readFileSync(0, 'utf8').trim();
  } catch (_) {
    return '';
  }
}

function main() {
  const argv = process.argv.slice(2);
  if (argv.includes('--dimensions') || argv.includes('-d')) {
    printDimensions();
    process.exit(0);
  }

  const raw = (argv[0] && argv[0].trim()) || readStdin();
  if (!raw) {
    fail('no input. Pass a JSON object of dimension->score as the first argument or on stdin.');
  }

  let scores;
  try {
    scores = JSON.parse(raw);
  } catch (e) {
    fail(`input is not valid JSON (${e.message}).`);
  }
  if (typeof scores !== 'object' || scores === null || Array.isArray(scores)) {
    fail('input must be a JSON object mapping dimension keys to scores.');
  }

  const known = new Set(DIMENSIONS.map(d => d.key));
  for (const k of Object.keys(scores)) {
    if (!known.has(k)) fail(`unknown dimension "${k}". See --dimensions.`);
    const v = scores[k];
    if (typeof v !== 'number' || !Number.isFinite(v) || v < MIN || v > MAX) {
      fail(`dimension "${k}" must be a number in ${MIN}..${MAX} (got ${JSON.stringify(v)}).`);
    }
  }

  // Build the report.
  const rows = [];
  const blockedBy = [];
  const unscored = [];
  let sum = 0, scoredCount = 0;

  for (const d of DIMENSIONS) {
    if (!(d.key in scores)) {
      unscored.push(d);
      if (d.blocking) blockedBy.push({ dim: d, score: null, reason: 'UNSCORED blocking dimension' });
      continue;
    }
    const s = scores[d.key];
    sum += s; scoredCount++;
    const flag = (d.blocking && s <= THRESHOLD) ? '  <-- BLOCKING, below threshold' : '';
    if (d.blocking && s <= THRESHOLD) blockedBy.push({ dim: d, score: s, reason: `scored ${s} <= ${THRESHOLD}` });
    rows.push(`  ${d.label.padEnd(22)} ${s}/5${d.blocking ? '  [blocking]' : ''}${flag}`);
  }

  const out = [];
  out.push('\nSTRUCTURED SCORECARD');
  out.push('====================');
  out.push(...rows);
  for (const d of unscored) {
    out.push(`  ${d.label.padEnd(22)} —/5${d.blocking ? '  [blocking]  <-- UNSCORED (a finding in itself)' : '  (unscored)'}`);
  }

  const composite = scoredCount ? sum : 0;
  const compositeMax = scoredCount * MAX;
  const pct = scoredCount ? Math.round((composite / compositeMax) * 100) : 0;
  out.push('');
  out.push(`  COMPOSITE: ${composite}/${compositeMax}  (${pct}%)  across ${scoredCount} scored dimension(s)`);

  out.push('');
  if (blockedBy.length) {
    out.push('  VERDICT: DO NOT PROCEED');
    out.push('  The composite is irrelevant — a blocking dimension is fatal:');
    for (const b of blockedBy) out.push(`    - ${b.dim.label}: ${b.reason}`);
    out.push('  Fix or de-risk the blocking dimension(s) before this idea is worth scoring at all.');
  } else if (pct < 50) {
    out.push('  VERDICT: WEAK — no fatal blocker, but the evidence base is thin. Treat as high-risk.');
  } else if (pct < 70) {
    out.push('  VERDICT: PROCEED WITH CONDITIONS — clears the blocking gates; weakest legs need de-risking.');
  } else {
    out.push('  VERDICT: WORTH PURSUING — clears the blocking gates with a solid evidence base.');
    out.push('  (This is "the scorecard does not object," NOT "ship it." Your written verdict still rules.)');
  }
  out.push('');
  console.log(out.join('\n'));
}

main();
