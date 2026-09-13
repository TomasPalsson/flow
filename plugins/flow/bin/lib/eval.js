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
      '  --max-cost-usd N     cost ceiling before the run goes partial (default 25)',
      '  --ablation <arm>     forwarded to the CLI as-is',
      '  -j, --concurrency N  parallel runs, 1..8 (forwarded to the CLI as --concurrency)',
      '  --history            print the last 10 ledger lines as a table, then exit',
      '  --dry-run            print the `claude plugin eval` argv and exit, without spawning',
      '',
      '  A selected case with postcheck.sh runs it in the kept workspace after grading (adds --keep-temp); a failed post-check fails the run.',
      '',
      'Exit codes: 0 ok, 1 fail (or claude missing / an unparsable result), 2 partial\n',
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

// readCaseTags(yamlText) -> string[]. A minimal reader for the one shape
// case.yaml uses: `tags: [a, b]` or a `tags:` block list. No YAML library
// (code-design.md decision 2 — cases are plain files, checked at test time).
function readCaseTags(yamlText) {
  const inline = yamlText.match(/^tags:\s*\[([^\]]*)\]/m);
  if (inline) {
    return inline[1]
      .split(',')
      .map((s) => s.trim().replace(/^['"]|['"]$/g, ''))
      .filter(Boolean);
  }
  const block = yamlText.match(/^tags:\s*\n((?:[ \t]*-[ \t]*.+\n?)+)/m);
  if (!block) return [];
  return block[1]
    .split('\n')
    .map((l) => l.match(/-\s*(.+)/))
    .filter(Boolean)
    .map((m) => m[1].trim().replace(/^['"]|['"]$/g, ''));
}

function caseTags(toplevel, caseName) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(toplevel, EVALS_ROOT, caseName, 'case.yaml'), 'utf8');
  } catch {
    return [];
  }
  return readCaseTags(raw);
}

// anyCaseNeedsBash(toplevel, selectedTags) -> true if a case dir under
// EVALS_ROOT carries both `needs-bash` and at least one tag in selectedTags.
// Cases can carry two tags (e.g. `[pipeline, needs-bash]`), so a plain
// `selectedTags.includes('needs-bash')` check misses them whenever the
// caller selects by the *other* tag (`--tag pipeline`) — evals/README.md's
// own `--allow-tools Write Edit (and Bash for needs-bash cases)` contract
// depends on this, not on the literal tag name in the selection.
function anyCaseNeedsBash(toplevel, selectedTags) {
  let entries;
  try {
    entries = fs.readdirSync(path.join(toplevel, EVALS_ROOT), { withFileTypes: true });
  } catch {
    return false;
  }
  return entries.some((e) => {
    if (!e.isDirectory()) return false;
    const tags = caseTags(toplevel, e.name);
    return tags.includes('needs-bash') && tags.some((t) => selectedTags.includes(t));
  });
}

// tagRollup(toplevel, cases, selectedTags, postResults) — per-tag {score,
// delta, cases} from cases[].aggregates grouped by the tags each case dir's
// case.yaml declares (code-design.md section 5 GREEN description). Tags with
// no matching case are left out of the result, not zeroed. postResults (from
// eval/postcheck.js's runAllPostchecks, default {}) adds a `post: {pass,
// total}` field to any tag bucket that owns a case with post-check results
// (FR-021).
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

function buildChildArgv(model, judgeModel, args, jsonPath, selectedTags, allowBash, keepTemp) {
  const allowTools = allowBash ? ['Write', 'Edit', 'Bash'] : ['Write', 'Edit'];
  const argv = [
    'plugin', 'eval', 'plugins/flow',
    '--trust-plugin', '--no-publish', '--scaffold',
    '--allow-tools', ...allowTools,
    '--model', model,
    '--judge-model', judgeModel,
    '--runs', String(args.runs === null ? 3 : args.runs),
    '--max-cost-usd', String(args.maxCostUsd === null ? 25 : args.maxCostUsd),
  ];
  if (args.threshold !== null) argv.push('--threshold', String(args.threshold));
  if (args.ablation !== null) argv.push('--ablation', String(args.ablation));
  if (args.concurrency !== null) argv.push('--concurrency', String(args.concurrency));
  for (const tag of selectedTags) argv.push('--tag', tag);
  if (keepTemp) argv.push('--keep-temp');
  argv.push('--json', jsonPath);
  return argv;
}

// executeAndReport — spawn the child CLI, parse its --json output, roll it
// up per tag, run any selected case's postcheck.sh in its kept workspace
// (FR-021), append the ledger line, print the summary, and return the mapped
// exit code. Split out of run() so each stays under the size guard.
function executeAndReport(claudePath, childArgv, toplevel, selectedTags, model, judgeModel, jsonPath, postcheckNames, env) {
  const spawnResult = spawnSync(claudePath, childArgv, { cwd: toplevel, encoding: 'utf8' });

  let raw = null;
  try {
    raw = fs.readFileSync(jsonPath, 'utf8');
  } catch {
    raw = null;
  }
  const parsed = raw !== null ? parseAggregate(raw) : { ok: false, error: 'no result file' };
  if (!parsed.ok) {
    stderr.write(`flow eval: unparsable result (${parsed.error})\n`);
    return EXIT.fail;
  }
  try {
    fs.unlinkSync(jsonPath);
  } catch { /* best effort */ }

  const report = parsed.data;
  const postResults = postcheckNames.length
    ? postcheck.runAllPostchecks(toplevel, EVALS_ROOT, path.join(toplevel, 'plugins', 'flow'), env, report.cases, postcheckNames)
    : {};
  const postFailed = postcheck.anyFailed(postResults);
  const postcheckLines = postcheck.formatSummaryLines(postResults);
  const mappedExit = mapExit(spawnResult.status);
  const rollup = tagRollup(toplevel, report.cases, selectedTags, postResults);
  const allDeltas = (report.cases || [])
    .map((c) => c.aggregates && c.aggregates.delta)
    .filter((n) => typeof n === 'number');
  const meanDelta = report.aggregates && typeof report.aggregates.meanDelta === 'number' ? report.aggregates.meanDelta : avg(allDeltas);
  const costUsd = typeof report.costUsd === 'number' ? report.costUsd : (report.aggregates && report.aggregates.costUsd) || 0;
  const partial = mappedExit === EXIT.partial || report.partial === true;
  const reason = report.reason || '';

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
  if (postFailed && mappedExit === EXIT.ok) return EXIT.fail;
  return mappedExit;
}

// selectTagsForRun(args, env) -> {selectedTags, socatPath, notice}. Narrows
// args.tags (default: every tag) by dropping `needs-bash` when socat is
// unavailable; `notice`, when set, is the one-line stdout message for that
// narrowing. FLOW_EVAL_TEST_HIDE_SOCAT is test_eval_cli.sh's hook to force
// "socat absent" regardless of the host's real PATH.
function selectTagsForRun(args, env) {
  let selectedTags = args.tags.length ? args.tags : TAGS.slice();
  const socatPath = env.FLOW_EVAL_TEST_HIDE_SOCAT ? null : resolveOnPath('socat', env);
  let notice = null;
  if (selectedTags.includes('needs-bash') && !socatPath) {
    notice = 'flow eval: socat not found — skipping needs-bash cases (notice, not a failure)';
    selectedTags = selectedTags.filter((t) => t !== 'needs-bash');
  }
  return { selectedTags, socatPath, notice };
}

// dispatchEval — builds the child argv (adding --keep-temp when a selected
// case has a postcheck.sh), then either prints it (--dry-run) or spawns and
// reports. Split out of run() so each stays under the size guard.
function dispatchEval(args, toplevel, claudePath, selectedTags, socatPath, env) {
  const model = readConfigKey(toplevel, CONFIG_KEYS.model) || DEFAULT_MODELS.model;
  const judgeModel = readConfigKey(toplevel, CONFIG_KEYS.judgeModel) || DEFAULT_MODELS.judgeModel;
  const jsonPath = path.join(os.tmpdir(), `flow-eval-${process.pid}-${Date.now()}.json`);
  const allowBash = Boolean(socatPath) && anyCaseNeedsBash(toplevel, selectedTags);
  const postcheckNames = postcheck.postcheckCaseNames(toplevel, EVALS_ROOT, caseTags, selectedTags);
  const childArgv = buildChildArgv(model, judgeModel, args, jsonPath, selectedTags, allowBash, postcheckNames.length > 0);

  if (args.dryRun) {
    stdout.write(`claude ${childArgv.join(' ')}\n`);
    if (postcheckNames.length) stdout.write(`postcheck cases: ${postcheckNames.join(', ')}\n`);
    return EXIT.ok;
  }

  return executeAndReport(claudePath, childArgv, toplevel, selectedTags, model, judgeModel, jsonPath, postcheckNames, env);
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

  const { selectedTags, socatPath, notice } = selectTagsForRun(args, env);
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
