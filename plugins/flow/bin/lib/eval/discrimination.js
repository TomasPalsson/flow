'use strict';

// eval/discrimination.js — what a `claude plugin eval` report says about its own
// measurements: which runs errored, the per-case delta over the runs that did
// not, and whether each grader tells the plugin arm from the baseline arm.
// Reads the CLI's --json shape (cases[].arms.{with,without}[].graders[]);
// nothing here grades anything.
//
// Credit: adapted from anthropics/claude-plugins-official skill-creator/agents/analyzer.md @ a9fd216 (Apache-2.0).

// A run that merely hit its case's max_turns is a budget the routing cases sit
// on by design, not an outage.
const BENIGN_RUN_ERROR = /maximum number of turns/i;

function isErroredRun(r) {
  return Boolean(r && r.error && !BENIGN_RUN_ERROR.test(String(r.error)));
}

function avg(nums) {
  return nums.length ? nums.reduce((a, b) => a + b, 0) / nums.length : 0;
}

const armRuns = (c, arm) => ((c && c.arms && c.arms[arm]) || []).filter(Boolean);
const measuredRuns = (c, arm) => armRuns(c, arm).filter((r) => !isErroredRun(r));

// caseDelta(c) -> number | null. The CLI averages an errored run (graded on an
// empty workspace) as a zero. With no errored run the CLI's own aggregate stands.
// With some, the delta is recomputed from the measured runs of each arm; when an
// arm has runs but none measured, the delta cannot be known and is null.
function caseDelta(c) {
  const agg = c && c.aggregates;
  const given = agg && typeof agg.delta === 'number' ? agg.delta : null;
  const withRuns = armRuns(c, 'with');
  const withoutRuns = armRuns(c, 'without');
  if (![...withRuns, ...withoutRuns].some(isErroredRun)) return given;
  if (!withRuns.length || !withoutRuns.length) return given;
  const w = measuredRuns(c, 'with');
  const wo = measuredRuns(c, 'without');
  if (!w.length || !wo.length) return null;
  return avg(w.map((r) => Number(r.score) || 0)) - avg(wo.map((r) => Number(r.score) || 0));
}

// gradeTable(c, arm, skip) -> Map<grader name, boolean[]> over the arm's measured
// runs; a grader marked withOnly or unscored in any run goes into `skip` (it is
// not part of the baseline-vs-plugin comparison).
function gradeTable(c, arm, skip) {
  const table = new Map();
  for (const r of measuredRuns(c, arm)) {
    for (const g of r.graders || []) {
      if (!g || typeof g.name !== 'string') continue;
      if (g.withOnly === true || g.scored === false) skip.add(g.name);
      if (!table.has(g.name)) table.set(g.name, []);
      table.get(g.name).push(g.passed === true);
    }
  }
  return table;
}

const majority = (xs) => xs.filter(Boolean).length * 2 > xs.length;
const mixed = (xs) => xs.some(Boolean) && xs.some((x) => !x);

// classifyGraders(cases) -> [{case, name, cls}] with cls one of both-pass,
// both-fail, with-only, hurts, flaky. flaky needs 3+ measured runs in an arm that
// disagree among themselves; fewer runs are classed by strict majority.
function classifyGraders(cases) {
  const out = [];
  for (const c of cases || []) {
    const skip = new Set();
    const withT = gradeTable(c, 'with', skip);
    const withoutT = gradeTable(c, 'without', skip);
    for (const [name, w] of withT) {
      const wo = withoutT.get(name);
      if (!wo || skip.has(name)) continue;
      let cls;
      if ((w.length >= 3 && mixed(w)) || (wo.length >= 3 && mixed(wo))) cls = 'flaky';
      else if (majority(w)) cls = majority(wo) ? 'both-pass' : 'with-only';
      else cls = majority(wo) ? 'hurts' : 'both-fail';
      out.push({ case: c.name, name, cls });
    }
  }
  return out;
}

const NOTES = {
  'both-pass': 'passes with and without the plugin, no signal',
  'both-fail': 'fails in both arms, no signal',
  hurts: 'passes without the plugin, fails with it',
  flaky: 'varies between runs of one arm',
};

// summarize(cases, tagsOf) -> {ranges: {tag: {min, max}}, lines: [string]}, or
// null when the report has no per-grader data for both arms (the summary then
// prints as it always did). tagsOf(caseName) -> tag list.
function summarize(cases, tagsOf) {
  const classes = classifyGraders(cases);
  if (!classes.length) return null;
  const ranges = {};
  for (const c of cases) {
    const d = caseDelta(c);
    if (d === null) continue;
    for (const tag of tagsOf(c.name)) {
      const s = ranges[tag] || (ranges[tag] = { min: d, max: d });
      s.min = Math.min(s.min, d);
      s.max = Math.max(s.max, d);
    }
  }
  const lines = classes
    .filter((g) => NOTES[g.cls])
    .map((g) => `grader ${g.case}/${g.name}: ${g.cls} (${NOTES[g.cls]})`);
  return { ranges, lines };
}

module.exports = { isErroredRun, caseDelta, classifyGraders, summarize };
