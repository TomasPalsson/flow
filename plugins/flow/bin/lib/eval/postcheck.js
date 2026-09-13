'use strict';

// eval/postcheck.js — FR-021 (.specs/007-plugin-eval-suite-and-optimisation-loop/spec.md):
// a case may ship `postcheck.sh`, which `flow eval` runs once per run of that
// case, in the kept `--keep-temp` workspace, after `claude plugin eval`
// returns. Split out of eval.js to keep it under the size guard (see the
// header comment there). Contract: scratchpad/postcheck-contract.md (Slice 5
// review). Never edited by the case-authoring agent (evals/**) or the
// tests-path agent (eval/contract.js) — this file is this unit's alone.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { lastNLines } = require('../loop/util.js');

const POSTCHECK_TIMEOUT_MS = 120000;

// hasExecutablePostcheck(toplevel, evalsRoot, caseName) -> true if
// evals/<case>/postcheck.sh exists and is executable.
function hasExecutablePostcheck(toplevel, evalsRoot, caseName) {
  const p = path.join(toplevel, evalsRoot, caseName, 'postcheck.sh');
  try {
    fs.accessSync(p, fs.constants.X_OK);
    return true;
  } catch {
    return false;
  }
}

// postcheckCaseNames(toplevel, evalsRoot, caseTagsFn, selectedTags) -> the
// names of case dirs under evalsRoot whose case.yaml tags intersect
// selectedTags and that carry an executable postcheck.sh — i.e. the subset
// of this run's selection that needs `--keep-temp` and a post-run check.
function postcheckCaseNames(toplevel, evalsRoot, caseTagsFn, selectedTags) {
  let entries;
  try {
    entries = fs.readdirSync(path.join(toplevel, evalsRoot), { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((e) => e.isDirectory())
    .map((e) => e.name)
    .filter((name) => {
      const tags = caseTagsFn(toplevel, name);
      return tags.some((t) => selectedTags.includes(t)) && hasExecutablePostcheck(toplevel, evalsRoot, name);
    })
    .sort();
}

// keptDirFromTracePath(tracePath) -> <kept>, given <kept>/out/trace.jsonl.
function keptDirFromTracePath(tracePath) {
  return path.dirname(path.dirname(tracePath));
}

// resolveWorkspace(keptDir) -> {ok: true, dir} | {ok: false, reason}. chmod
// 700 the kept dir and its `sealed` subdir (both mode 000 when sealed, per
// the contract) before resolving; the workspace is sealed/home/cwd when
// sealed exists, else home/cwd.
function resolveWorkspace(keptDir) {
  try {
    fs.chmodSync(keptDir, 0o700);
  } catch {
    return { ok: false, reason: `kept dir missing: ${keptDir}` };
  }
  const sealed = path.join(keptDir, 'sealed');
  let sealedExists = true;
  try {
    fs.chmodSync(sealed, 0o700);
  } catch {
    sealedExists = false;
  }
  const dir = sealedExists ? path.join(sealed, 'home', 'cwd') : path.join(keptDir, 'home', 'cwd');
  try {
    if (!fs.statSync(dir).isDirectory()) return { ok: false, reason: `workspace missing: ${dir}` };
  } catch {
    return { ok: false, reason: `workspace missing: ${dir}` };
  }
  return { ok: true, dir };
}

// runOnePostcheck(scriptPath, workspace, env) -> {pass, tail}. Spawns
// `bash <scriptPath>` with cwd=workspace and the given env, a 120s timeout;
// keeps the last 20 lines of combined stdout+stderr.
function runOnePostcheck(scriptPath, workspace, env) {
  const r = spawnSync('bash', [scriptPath], {
    cwd: workspace,
    env,
    encoding: 'utf8',
    timeout: POSTCHECK_TIMEOUT_MS,
  });
  const combined = `${r.stdout || ''}${r.stderr || ''}`;
  const pass = !r.error && r.status === 0;
  return { pass, tail: lastNLines(combined, 20) };
}

// runPostchecksForCase(toplevel, evalsRoot, pluginRoot, env, caseName, runs)
// -> {pass, total, failures: [{run, reason}]}. `runs` is the case's
// aggregate `runs` array, each `{tracePath}`; every kept dir this touches is
// removed before returning, pass or fail.
function runPostchecksForCase(toplevel, evalsRoot, pluginRoot, env, caseName, runs) {
  const scriptPath = path.join(toplevel, evalsRoot, caseName, 'postcheck.sh');
  const failures = [];
  let pass = 0;
  const list = Array.isArray(runs) ? runs : [];
  list.forEach((run, idx) => {
    const runIndex = idx + 1;
    const tracePath = run && run.tracePath;
    if (!tracePath) {
      failures.push({ run: runIndex, reason: 'no trace recorded for this run' });
      return;
    }
    const keptDir = keptDirFromTracePath(tracePath);
    const resolved = resolveWorkspace(keptDir);
    if (!resolved.ok) {
      failures.push({ run: runIndex, reason: resolved.reason });
      try {
        fs.rmSync(keptDir, { recursive: true, force: true });
      } catch { /* best effort */ }
      return;
    }
    const childEnv = Object.assign({}, env, {
      EVAL_CASE: caseName,
      EVAL_RUN: String(runIndex),
      EVAL_TRACE: tracePath,
      EVAL_PLUGIN_ROOT: pluginRoot,
    });
    const result = runOnePostcheck(scriptPath, resolved.dir, childEnv);
    if (result.pass) {
      pass += 1;
    } else {
      failures.push({ run: runIndex, reason: result.tail || 'postcheck exited non-zero' });
    }
    try {
      fs.rmSync(keptDir, { recursive: true, force: true });
    } catch { /* best effort */ }
  });
  return { pass, total: list.length, failures };
}

// runAllPostchecks(toplevel, evalsRoot, pluginRoot, env, cases, names) ->
// {<caseName>: {pass, total, failures}} for every name in `names` that has a
// matching entry in `cases` (the parsed aggregate's `cases` array). Per-run
// data lives at `cases[].arms.with[]` in the CLI's real schemaVersion 1
// output (post-checks only ever run against the plugin arm, never
// `arms.without`, the baseline); `c.runs` is a fallback for a shape that
// isn't the real one.
function runAllPostchecks(toplevel, evalsRoot, pluginRoot, env, cases, names) {
  const byName = {};
  for (const c of cases || []) byName[c.name] = c;
  const out = {};
  for (const name of names) {
    const c = byName[name];
    if (!c) continue;
    const runs = (c.arms && c.arms.with) || c.runs;
    out[name] = runPostchecksForCase(toplevel, evalsRoot, pluginRoot, env, name, runs);
  }
  return out;
}

// formatSummaryLines(results) -> one 'postcheck <case> <pass>/<total>' line
// per case (sorted), followed by the failure-tail block for any case with a
// failed run.
function formatSummaryLines(results) {
  const lines = [];
  const names = Object.keys(results).sort();
  for (const name of names) {
    const r = results[name];
    lines.push(`postcheck ${name} ${r.pass}/${r.total}`);
  }
  for (const name of names) {
    const r = results[name];
    for (const f of r.failures) {
      lines.push(`  postcheck ${name} run ${f.run} failed:`);
      for (const l of String(f.reason).split('\n')) lines.push(`    ${l}`);
    }
  }
  return lines;
}

// anyFailed(results) -> true if any case in the results has a failed run.
function anyFailed(results) {
  return Object.keys(results).some((name) => results[name].failures.length > 0);
}

module.exports = {
  hasExecutablePostcheck,
  postcheckCaseNames,
  keptDirFromTracePath,
  resolveWorkspace,
  runPostchecksForCase,
  runAllPostchecks,
  formatSummaryLines,
  anyFailed,
};
