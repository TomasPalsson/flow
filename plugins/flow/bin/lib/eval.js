'use strict';

// eval.js — `flow eval`: run the plugin eval suite via `claude plugin eval`,
// record a ledger line and print a summary (Slice 5, .claude/slices/5-brief.md;
// spec .specs/007-plugin-eval-suite-and-optimisation-loop/spec.md Journey 1
// AC-001..AC-004, FR-005..FR-009). Thin runner only: no grading logic here
// (code-design.md decision 1) — everything PASS/FAIL lives in the CLI and
// in evals/*/graders/.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { TAGS, EVALS_ROOT, LEDGER_PATH, CONFIG_KEYS, DEFAULT_MODELS, ledgerLine } = require('./eval/contract.js');
const { resolveOnPath, headSha, gitToplevel } = require('./loop/util.js');
const postcheck = require('./eval/postcheck.js');
const { caseTags, anyCaseNeedsBash, selectCases } = require('./eval/cases.js');

const { stdout, stderr } = process;

const EXIT = { ok: 0, fail: 1, partial: 2 };

function mapExit(status) {
  if (status === 0) return EXIT.ok;
  if (status === 1) return EXIT.fail;
  if (status === 2) return EXIT.partial;
  return EXIT.fail;
}

function avg(nums) {
  return nums.length ? nums.reduce((a, b) => a + b, 0) / nums.length : 0;
}

function printHelp() {
  stdout.write(
    [
      'flow eval — run the plugin eval suite (claude plugin eval) and append a ledger line',
      '',
      'Usage:',
      '  flow eval [--tag <tag>]... [--runs N] [--threshold N] [--max-cost-usd N]',
      '            [--ablation <arm>] [--history] [--dry-run]',
      '',
      'Options:',
      '  --tag <tag>          one of ' + TAGS.join(', ') + ' (repeatable;',
      '                       default: all tags)',
      '  --runs N             repetitions per case (default 3)',
      '  --threshold N        minimum per-case score to pass (forwarded to the CLI)',
      '  --max-cost-usd N     cost ceiling per case before that case\'s run goes partial (default 25)',
      '  --ablation <arm>     forwarded to the CLI as-is',
      '  -j, --concurrency N  parallel runs, 1..8 (forwarded to the CLI as --concurrency)',
      '  --history            print the last 10 ledger lines as a table, then exit',
      '  --dry-run            print each case\'s `claude plugin eval` argv and exit, without spawning',
      '',
      '  Each selected case runs in its own claude plugin eval invocation and is granted only the gated tools (Write, Edit, Bash) its case.yaml allowed_tools names.',
      '',
      '  A selected case with postcheck.sh runs it in the kept workspace after grading (adds --keep-temp); a failed post-check fails the run.',
      '',
      'Exit codes: 0 ok, 1 fail (or claude missing / an unparsable result), 2 partial (cost ceiling, or any run that ended in an error such as a session limit)\n',
    ].join('\n')
  );
}

// readConfigKey(toplevel, key) -> string. Mirrors bin/flow's own
// .claude/flow.config.json readers (doctorHarnessJsonOverridesCheck):
// absent file or key, or invalid JSON, all resolve to '' — never throw.
function readConfigKey(toplevel, key) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(toplevel, '.claude', 'flow.config.json'), 'utf8');
  } catch {
    return '';
  }
  let cfg;
  try {
    cfg = JSON.parse(raw);
  } catch {
    return '';
  }
  const v = cfg && cfg[key];
  return typeof v === 'string' ? v : '';
}

// parseAggregate(text) -> {ok, data} | {ok: false, error}. The CLI's --json
// output is the only untrusted boundary this module reads (code-design.md
// section 2): whole run fails with "unparsable result" if this fails.
function parseAggregate(text) {
  try {
    return { ok: true, data: JSON.parse(text) };
  } catch (e) {
    return { ok: false, error: e.message };
  }
}

// readCaseTags, caseTags, anyCaseNeedsBash now live in ./eval/cases.js
// (required above), alongside selectCases and the gated-tool grant logic.

// tagRollup(toplevel, cases, selectedTags, postResults) — per-tag {score,
// delta, cases} from cases[].aggregates grouped by the tags each case dir's
// case.yaml declares (code-design.md section 5 GREEN description). Tags with
// no matching case are left out of the result, not zeroed. postResults (from
// eval/postcheck.js's runAllPostchecks, default {}) adds a `post: {pass,
// total}` field to any tag bucket that owns a case with post-check results
// (FR-021).
// runErrors(cases) -> the `error` string of every run (either arm) that
// ended with one, except a run that merely hit its case's max_turns (a
// budget the routing cases sit on by design). The CLI still grades an
// errored run's empty workspace and exits 1, which would ledger a
// session-limit outage as a plain fail.
const BENIGN_RUN_ERROR = /maximum number of turns/i;
function runErrors(cases) {
  const out = [];
  for (const c of cases || []) {
    const arms = c.arms || {};
    for (const arm of ['with', 'without']) {
      for (const r of arms[arm] || []) {
        if (r && r.error && !BENIGN_RUN_ERROR.test(String(r.error))) out.push(String(r.error));
      }
    }
  }
  return out;
}

function tagRollup(toplevel, cases, selectedTags, postResults) {
  postResults = postResults || {};
  const buckets = {};
  for (const tag of selectedTags) buckets[tag] = { scores: [], deltas: [], postPass: 0, postTotal: 0, hasPost: false };
  for (const c of cases || []) {
    const tags = caseTags(toplevel, c.name);
    const agg = c.aggregates || {};
    const post = postResults[c.name];
    for (const tag of tags) {
      if (!buckets[tag]) continue;
      if (typeof agg.score === 'number') buckets[tag].scores.push(agg.score);
      if (typeof agg.delta === 'number') buckets[tag].deltas.push(agg.delta);
      if (post) {
        buckets[tag].hasPost = true;
        buckets[tag].postPass += post.pass;
        buckets[tag].postTotal += post.total;
      }
    }
  }
  const out = {};
  for (const tag of selectedTags) {
    const { scores, deltas, hasPost, postPass, postTotal } = buckets[tag];
    if (!scores.length) continue;
    out[tag] = { score: avg(scores), delta: avg(deltas), cases: scores.length };
    if (hasPost) out[tag].post = { pass: postPass, total: postTotal };
  }
  return out;
}

function parseArgs(argv) {
  const out = { tags: [], runs: null, threshold: null, maxCostUsd: null, ablation: null, concurrency: null, history: false, dryRun: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--tag') out.tags.push(argv[++i]);
    else if (a === '--runs') out.runs = argv[++i];
    else if (a === '--threshold') out.threshold = argv[++i];
    else if (a === '--max-cost-usd') out.maxCostUsd = argv[++i];
    else if (a === '--ablation') out.ablation = argv[++i];
    else if (a === '-j' || a === '--concurrency') out.concurrency = argv[++i];
    else if (a === '--history') out.history = true;
    else if (a === '--dry-run') out.dryRun = true;
  }
  return out;
}

function printHistory(toplevel) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(toplevel, LEDGER_PATH), 'utf8');
  } catch {
    stdout.write('flow eval: no ledger yet\n');
    return EXIT.ok;
  }
  const lines = raw.split('\n').filter(Boolean).slice(-10);
  stdout.write('ts                        sha       meanDelta  costUsd  partial\n');
  for (const line of lines) {
    let obj;
    try {
      obj = JSON.parse(line);
    } catch {
      continue;
    }
    stdout.write(`${obj.ts}  ${String(obj.sha || '').slice(0, 7)}  ${obj.meanDelta}  ${obj.costUsd}  ${obj.partial}\n`);
  }
  return EXIT.ok;
}

function printSummary(rollup, meanDelta, costUsd, partial, reason, postcheckLines) {
  stdout.write('flow eval summary\n');
  for (const tag of Object.keys(rollup)) {
    const r = rollup[tag];
    stdout.write(`  ${tag}: score=${r.score.toFixed(2)} delta=${r.delta.toFixed(2)} (${r.cases} cases)\n`);
  }
  stdout.write(`  meanDelta: ${meanDelta}  cost: $${costUsd}\n`);
  if (partial) stdout.write(`  partial: ${reason || 'yes'}\n`);
  for (const line of postcheckLines || []) stdout.write(`  ${line}\n`);
}

function appendLedger(toplevel, line) {
  const p = path.join(toplevel, LEDGER_PATH);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.appendFileSync(p, `${line}\n`);
}

// buildChildArgv(...) -> one `claude plugin eval` argv for a single case.
// `grant` (a case's allowed_tools ∩ GATED, from selectCases) is omitted from
// --allow-tools when empty. No `--tag` any more: each spawn picks exactly
// one case via `--case`, so there is nothing left for a tag to narrow (also loads sibling plugins/flow-extras, if present, via --plugin-dir).
function buildChildArgv(model, judgeModel, args, jsonPath, caseName, grant, keepTemp, toplevel) {
  const argv = ['plugin', 'eval', 'plugins/flow', '--trust-plugin', '--no-publish', '--scaffold'];
  if (toplevel && fs.existsSync(path.join(toplevel, 'plugins', 'flow-extras'))) argv.push('--plugin-dir', 'plugins/flow-extras');
  if (grant.length) argv.push('--allow-tools', ...grant);
  argv.push(
    '--model', model,
    '--judge-model', judgeModel,
    '--runs', String(args.runs === null ? 3 : args.runs),
    '--max-cost-usd', String(args.maxCostUsd === null ? 25 : args.maxCostUsd)
  );
  if (args.threshold !== null) argv.push('--threshold', String(args.threshold));
  if (args.ablation !== null) argv.push('--ablation', String(args.ablation));
  if (args.concurrency !== null) argv.push('--concurrency', String(args.concurrency));
  argv.push('--case', caseName);
  if (keepTemp) argv.push('--keep-temp');
  argv.push('--json', jsonPath);
  return argv;
}

// spawnCase — spawn one case's child CLI, parse its --json (cleaned up
// either way), keeping only the `cases[]` entry whose `name` matches (the
// CLI's `--case` glob could in principle match more than one).
function spawnCase(claudePath, spec, toplevel) {
  const spawnResult = spawnSync(claudePath, spec.argv, { cwd: toplevel, encoding: 'utf8' });
  let raw = null;
  try {
    raw = fs.readFileSync(spec.jsonPath, 'utf8');
  } catch {
    raw = null;
  }
  const parsed = raw !== null ? parseAggregate(raw) : { ok: false, error: 'no result file' };
  try {
    fs.unlinkSync(spec.jsonPath);
  } catch { /* best effort */ }
  if (!parsed.ok) return { ok: false, error: parsed.error };
  const childReport = parsed.data;
  const mappedExit = mapExit(spawnResult.status);
  return {
    ok: true,
    cases: (childReport.cases || []).filter((c) => c && c.name === spec.name),
    costUsd: typeof childReport.costUsd === 'number' ? childReport.costUsd : (childReport.aggregates && childReport.aggregates.costUsd) || 0,
    mappedExit,
    partial: mappedExit === EXIT.partial || childReport.partial === true,
    reason: childReport.reason || '',
  };
}

// executeAndReport — spawn each case via spawnCase (sequentially, in
// order), merge into one report, roll up per tag, run every selected case's
// postcheck.sh once over the merged cases (FR-021), append one ledger line,
// print one summary, and return the mapped exit code.
function executeAndReport(claudePath, specs, toplevel, selectedTags, model, judgeModel, postcheckNames, env) {
  const mergedCases = [];
  let costUsd = 0;
  let anyChildPartial = false;
  let firstReason = '';
  let worstExit = EXIT.ok;

  for (const spec of specs) {
    const result = spawnCase(claudePath, spec, toplevel);
    if (!result.ok) {
      stderr.write(`flow eval: unparsable result (${result.error})\n`);
      return EXIT.fail;
    }
    mergedCases.push(...result.cases);
    costUsd += result.costUsd;
    if (result.mappedExit > worstExit) worstExit = result.mappedExit;
    if (result.partial) anyChildPartial = true;
    if (!firstReason && result.reason) firstReason = result.reason;
  }

  const postResults = postcheckNames.length
    ? postcheck.runAllPostchecks(toplevel, EVALS_ROOT, path.join(toplevel, 'plugins', 'flow'), env, mergedCases, postcheckNames)
    : {};
  const postFailed = postcheck.anyFailed(postResults);
  const postcheckLines = postcheck.formatSummaryLines(postResults);
  const rollup = tagRollup(toplevel, mergedCases, selectedTags, postResults);
  const allDeltas = mergedCases.map((c) => c.aggregates && c.aggregates.delta).filter((n) => typeof n === 'number');
  const meanDelta = avg(allDeltas);
  const erroredRuns = runErrors(mergedCases);
  const partial = anyChildPartial || erroredRuns.length > 0;
  const reason = firstReason || (erroredRuns.length ? `${erroredRuns.length} runs errored: ${erroredRuns[0]}` : '');

  appendLedger(
    toplevel,
    ledgerLine({
      ts: new Date().toISOString(),
      sha: headSha(toplevel),
      model,
      judgeModel,
      tags: rollup,
      meanDelta,
      costUsd,
      partial,
      reason,
    })
  );
  printSummary(rollup, meanDelta, costUsd, partial, reason, postcheckLines);
  if (partial) return EXIT.partial;
  if (postFailed && worstExit === EXIT.ok) return EXIT.fail;
  return worstExit;
}

// selectTagsForRun(args, env, toplevel) -> {selectedTags, socatPath, notice}.
// Drops `needs-bash` from args.tags (default: every tag) when socat is
// unavailable, either because it's itself selected or because some other
// selected tag's case also carries it (anyCaseNeedsBash) — `--tag pipeline`
// alone must still notice and drop a `[pipeline, needs-bash]` case in
// selectCases. FLOW_EVAL_TEST_HIDE_SOCAT forces "socat absent" for tests.
function selectTagsForRun(args, env, toplevel) {
  let selectedTags = args.tags.length ? args.tags : TAGS.slice();
  const socatPath = env.FLOW_EVAL_TEST_HIDE_SOCAT ? null : resolveOnPath('socat', env);
  let notice = null;
  if (!socatPath && (selectedTags.includes('needs-bash') || anyCaseNeedsBash(toplevel, selectedTags))) {
    notice = 'flow eval: socat not found — skipping needs-bash cases (notice, not a failure)';
    selectedTags = selectedTags.filter((t) => t !== 'needs-bash');
  }
  return { selectedTags, socatPath, notice };
}

// dispatchEval — selects this run's cases (selectCases), builds each case's
// own argv (its own --allow-tools grant, --keep-temp if it has a
// postcheck.sh), then prints (--dry-run) or spawns and reports.
function dispatchEval(args, toplevel, claudePath, selectedTags, socatPath, env) {
  const model = readConfigKey(toplevel, CONFIG_KEYS.model) || DEFAULT_MODELS.model;
  const judgeModel = readConfigKey(toplevel, CONFIG_KEYS.judgeModel) || DEFAULT_MODELS.judgeModel;
  const allowBash = Boolean(socatPath);
  const cases = selectCases(toplevel, EVALS_ROOT, selectedTags, allowBash);
  const postcheckNames = postcheck.postcheckCaseNames(toplevel, EVALS_ROOT, caseTags, selectedTags);
  const specs = cases.map((c) => {
    const jsonPath = path.join(os.tmpdir(), `flow-eval-${process.pid}-${Date.now()}-${c.name}.json`);
    const keepTemp = postcheck.hasExecutablePostcheck(toplevel, EVALS_ROOT, c.name);
    return { name: c.name, jsonPath, argv: buildChildArgv(model, judgeModel, args, jsonPath, c.name, c.grant, keepTemp, toplevel) };
  });

  if (args.dryRun) {
    for (const spec of specs) stdout.write(`claude ${spec.argv.join(' ')}\n`);
    if (postcheckNames.length) stdout.write(`postcheck cases: ${postcheckNames.join(', ')}\n`);
    return EXIT.ok;
  }

  return executeAndReport(claudePath, specs, toplevel, selectedTags, model, judgeModel, postcheckNames, env);
}

function run(argv, cwd, env) {
  env = env || process.env;
  if (argv.includes('--help') || argv.includes('-h')) {
    printHelp();
    return EXIT.ok;
  }
  const args = parseArgs(argv);
  if (args.concurrency !== null) {
    const n = Number(args.concurrency);
    if (!Number.isInteger(n) || n < 1 || n > 8) {
      stderr.write(`flow eval: --concurrency must be an integer between 1 and 8 (got ${args.concurrency})\n`);
      return EXIT.fail;
    }
  }
  const toplevel = gitToplevel(cwd, env);
  if (!toplevel) {
    stderr.write('flow eval: not a git repository\n');
    return EXIT.fail;
  }
  if (args.history) return printHistory(toplevel);

  const claudePath = resolveOnPath('claude', env);
  if (!claudePath) {
    stderr.write('flow eval: claude not found on PATH — install it, then run `flow doctor` for the eval-ready check\n');
    return EXIT.fail;
  }

  const { selectedTags, socatPath, notice } = selectTagsForRun(args, env, toplevel);
  if (notice) stdout.write(`${notice}\n`);
  // An empty selection must refuse, never spawn: buildChildArgv would emit no
  // `--tag` at all, and the CLI's documented default for "no --tag" is *every*
  // tag — so `--tag needs-bash` alone on a socat-less box would silently run
  // the whole suite the caller just narrowed away from, at full API cost.
  if (!selectedTags.length) {
    stderr.write('flow eval: no cases left to run after skipping needs-bash — nothing to evaluate\n');
    return EXIT.fail;
  }

  return dispatchEval(args, toplevel, claudePath, selectedTags, socatPath, env);
}

module.exports = { run, parseAggregate, readConfigKey, EXIT };

if (require.main === module) {
  process.exit(run(process.argv.slice(2), process.cwd(), process.env));
}
