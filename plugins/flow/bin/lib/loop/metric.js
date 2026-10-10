'use strict';

// loop/metric.js — the metric (hillclimb) form of a loop. A candidate commit
// is kept only when the median of --runs metric runs beats the best value so
// far by more than the noise measured at init, and the --verify regression
// gate is green. Otherwise it is undone with `git revert --no-edit`, which
// keeps the attempt in history; the loop never discards work with a hard
// reset. Every attempt is one row in .claude/loop/decisions.tsv.
// Idea adapted from cursor/plugins pstack playbooks/hillclimb.md @ ccb5507 (MIT).

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { sha1, toInt, toFloat, headSha } = require('./util.js');

const TSV_HEADER = 'sha\thypothesis\tbefore\tafter\tdelta\tkept';
const LOOP_STATE_EXCLUDE = ':(exclude).claude/loop';
const PIVOT_AFTER = 3;

function decisionsPath(toplevel) {
  return path.join(toplevel, '.claude', 'loop', 'decisions.tsv');
}

// The last number printed. A metric command may print progress before it.
function parseMetricOutput(text) {
  const m = String(text || '').match(/-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?/g);
  if (!m) return null;
  const n = Number(m[m.length - 1]);
  return Number.isFinite(n) ? n : null;
}

function median(values) {
  const s = values.slice().sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

function fmtNum(n) {
  return String(Number(Number(n).toFixed(6)));
}

function runMetricOnce(toplevel, cmd, timeoutSec, env) {
  const r = spawnSync('sh', ['-c', cmd], {
    cwd: toplevel,
    env: Object.assign({}, env, { CI: 'true', FLOW_LOOP: '1' }),
    timeout: (toInt(timeoutSec) || 600) * 1000,
    encoding: 'utf8',
  });
  if (r.status !== 0) return { ok: false, reason: `metric command exited ${r.status === null ? 'by signal/timeout' : r.status}` };
  const value = parseMetricOutput(r.stdout);
  if (value === null) return { ok: false, reason: 'metric command printed no number' };
  return { ok: true, value };
}

// measure -> { ok, values, median, spread } or { ok: false, reason }.
function measure(toplevel, cmd, runs, timeoutSec, env) {
  const values = [];
  for (let i = 0; i < runs; i++) {
    const r = runMetricOnce(toplevel, cmd, timeoutSec, env);
    if (!r.ok) return { ok: false, reason: r.reason };
    values.push(r.value);
  }
  return { ok: true, values, median: median(values), spread: Math.max(...values) - Math.min(...values) };
}

function beats(direction, value, best, noise) {
  return direction === 'min' ? value < best - noise : value > best + noise;
}

function reachedTarget(direction, best, target) {
  return direction === 'min' ? best <= target : best >= target;
}

function git(toplevel, args) {
  return spawnSync('git', ['-C', toplevel].concat(args), { encoding: 'utf8' });
}

// Dirty tree, ignoring loop state (LEARNINGS.md rides outside every
// candidate commit so a revert can never undo a learnings entry).
function dirtyOutsideLoop(toplevel) {
  const r = git(toplevel, ['status', '--porcelain', '--', '.', LOOP_STATE_EXCLUDE]);
  return r.status === 0 && (r.stdout || '').trim() !== '';
}

// Paths a metric run left in the tree, for the message.
function dirtyFiles(toplevel) {
  const r = git(toplevel, ['status', '--porcelain', '--', '.', LOOP_STATE_EXCLUDE]);
  return (r.stdout || '').split('\n').filter(Boolean).map((l) => l.slice(3)).slice(0, 5).join(', ');
}

// initMetric(toplevel, args, env) -> { front } or { error, code }. Runs the
// metric --runs times on the clean tree; refuses with no number, or with a
// spread larger than the distance to the target.
function initMetric(toplevel, args, env) {
  if (args.direction !== 'max' && args.direction !== 'min') {
    return { error: 'flow loop init: --metric needs --direction max|min', code: 1 };
  }
  if (!(toInt(args.runs) >= 1)) return { error: 'flow loop init: --runs must be a positive integer', code: 1 };
  if (dirtyOutsideLoop(toplevel)) {
    return { error: 'flow loop init: the working tree is dirty; commit or stash first so the baseline is measured on a clean tree', code: 1 };
  }
  const m = measure(toplevel, args.metric, toInt(args.runs), args.verifyTimeout, env);
  if (!m.ok) return { error: `flow loop init: ${m.reason}; refusing to arm`, code: 1 };
  if (dirtyOutsideLoop(toplevel)) {
    return {
      error: `flow loop init: the metric command wrote files into the repo (${dirtyFiles(toplevel)}); add them to .gitignore ` +
        'or make the metric write outside the repo, or its output would be judged as model work; refusing to arm',
      code: 1,
    };
  }
  const hasTarget = args.metricTarget !== null && args.metricTarget !== undefined;
  if (hasTarget) {
    const target = Number(args.metricTarget);
    if (!Number.isFinite(target)) return { error: `flow loop init: --target '${args.metricTarget}' is not a number`, code: 1 };
    const delta = Math.abs(target - m.median);
    if (m.spread > delta) {
      return {
        error: `flow loop init: metric spread ${fmtNum(m.spread)} over ${args.runs} runs exceeds the distance to the target ${fmtNum(delta)}; ` +
          'the number is too noisy to climb. Make the metric deterministic or raise --runs; refusing to arm',
        code: 1,
      };
    }
  }
  return {
    front: {
      metric: args.metric,
      metric_dir: args.direction,
      metric_runs: String(toInt(args.runs)),
      metric_min_attempts: String(toInt(args.minAttempts)),
      metric_target: hasTarget ? fmtNum(Number(args.metricTarget)) : '',
      metric_noise: fmtNum(m.spread),
      metric_best: fmtNum(m.median),
      metric_head: '',
      metric_attempts: '0',
      metric_rejects: '0',
    },
    median: m.median,
    spread: m.spread,
  };
}

function appendDecision(toplevel, row) {
  const p = decisionsPath(toplevel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  if (!fs.existsSync(p)) fs.writeFileSync(p, `${TSV_HEADER}\n`);
  const clean = (s) => String(s).replace(/[\t\r\n]+/g, ' ');
  fs.appendFileSync(p, `${[row.sha, row.hypothesis, row.before, row.after, row.delta, row.kept].map(clean).join('\t')}\n`);
}

function readDecisions(toplevel, n) {
  let raw = '';
  try {
    raw = fs.readFileSync(decisionsPath(toplevel), 'utf8');
  } catch { /* none yet */ }
  const rows = raw.split('\n').filter(Boolean).slice(1);
  return n ? rows.slice(-n) : rows;
}

function commitCandidate(toplevel, front) {
  if (!dirtyOutsideLoop(toplevel)) return null;
  const add = git(toplevel, ['add', '-A', '--', '.', LOOP_STATE_EXCLUDE]);
  const c = add.status === 0
    ? git(toplevel, ['commit', '-q', '-m', `loop(${front.slug}) iteration ${front.iteration}: candidate`])
    : add;
  if (c.status === 0) return null;
  const tail = `${c.stderr || ''}${c.stdout || ''}`.trim().split('\n').slice(-5).join(' | ');
  return tail || `git exited ${c.status}`;
}

function revertCandidate(toplevel, front, head) {
  const from = front.metric_head;
  const count = toInt((git(toplevel, ['rev-list', '--count', `${from}..${head}`]).stdout || '').trim());
  const spec = count > 1 ? `${from}..${head}` : head;
  const r = git(toplevel, ['revert', '--no-edit', spec]);
  if (r.status !== 0) {
    git(toplevel, ['revert', '--abort']);
    return false;
  }
  return true;
}

// metricStep(toplevel, front, verify, env) — called by tick after the gate
// ran. Mutates `front`. Returns { reached, sig, stopReason }.
function metricStep(toplevel, front, verify, env) {
  const commitErr = commitCandidate(toplevel, front);
  const head = headSha(toplevel);
  if (!front.metric_head) front.metric_head = front.base;
  const out = { reached: false, sig: verify.sig, stopReason: null };
  if (commitErr) {
    process.stderr.write(`flow loop: candidate commit failed (hook or git error), change left staged: ${commitErr}\n`);
    out.stopReason = 'commit-failed';
    return out;
  }
  if (head !== front.metric_head) {
    const before = toFloat(front.metric_best);
    const m = measure(toplevel, front.metric, toInt(front.metric_runs) || 1, front.verify_timeout, env);
    if (dirtyOutsideLoop(toplevel)) {
      process.stderr.write(`flow loop: the metric command wrote files into the repo (${dirtyFiles(toplevel)}); gitignore them. Stopping.\n`);
      out.stopReason = 'metric-wrote-files';
      return out;
    }
    const kept = m.ok && verify.rc === 0 && beats(front.metric_dir, m.median, before, toFloat(front.metric_noise));
    const subject = (git(toplevel, ['log', '-1', '--format=%s', head]).stdout || '').trim();
    appendDecision(toplevel, {
      sha: head.slice(0, 7),
      hypothesis: subject,
      before: fmtNum(before),
      after: m.ok ? fmtNum(m.median) : '-',
      delta: m.ok ? fmtNum(m.median - before) : '-',
      kept: kept ? 'yes' : 'no',
    });
    front.metric_attempts = String(toInt(front.metric_attempts) + 1);
    if (kept) {
      front.metric_best = fmtNum(m.median);
      front.metric_head = head;
      front.metric_rejects = '0';
    } else {
      front.metric_rejects = String(toInt(front.metric_rejects) + 1);
      if (!revertCandidate(toplevel, front, head)) {
        out.stopReason = 'revert-failed';
        return out;
      }
      front.metric_head = headSha(toplevel);
    }
    out.sig = sha1(`${verify.sig}:${m.ok ? fmtNum(m.median) : 'x'}:${kept ? 1 : 0}`);
  }
  const hasTarget = front.metric_target !== '' && front.metric_target !== undefined;
  out.reached = hasTarget && toInt(front.metric_attempts) >= toInt(front.metric_min_attempts) &&
    reachedTarget(front.metric_dir, toFloat(front.metric_best), toFloat(front.metric_target));
  return out;
}

// Stall/wedge stops wait until --min-attempts attempts were made, since a
// reverted attempt leaves the tree where it was and looks like no progress.
function stallSuppressed(front) {
  return Boolean(front.metric) && toInt(front.metric_attempts) < toInt(front.metric_min_attempts);
}

// metricNote(toplevel, front) -> text appended to the continuation prompt.
function metricNote(toplevel, front) {
  const lines = [
    `metric \`${front.metric}\` (${front.metric_dir}): best ${front.metric_best}, noise ${front.metric_noise}` +
      `${front.metric_target ? `, target ${front.metric_target}` : ''}; attempts ${front.metric_attempts}.`,
    'Read .claude/loop/decisions.tsv first: it lists every attempt and whether it was kept.',
  ];
  const rows = readDecisions(toplevel, 5);
  if (rows.length) lines.push('last attempts (sha, hypothesis, before, after, delta, kept):', ...rows);
  if (toInt(front.metric_rejects) >= PIVOT_AFTER) {
    lines.push(`${front.metric_rejects} attempts in a row were rejected: pivot to a different category of change, not another variation of the last idea.`);
  }
  return lines.join('\n');
}

module.exports = {
  parseMetricOutput, median, measure, beats, initMetric, metricStep, stallSuppressed, metricNote,
  dirtyOutsideLoop, decisionsPath, readDecisions, fmtNum,
};
