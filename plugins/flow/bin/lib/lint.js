'use strict';

// lint.js — `flow lint [<TASKS.md>] [--json] [--waves]`, a pass-through to
// scripts/flow-lint so the grammar has exactly one implementation, plus one
// check that needs the feature's verify/ directory: an unattended
// `Verified: <date> ... (pre-approved: /flow:next --finish)` line dated on or
// after CLAIM_CHECK_FROM must be backed by verify/claim-check.md with no
// unsupported claims (next/SKILL.md §Finish rule 5). Older lines stay clean so
// features finished before this check existed do not turn into errors.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { pluginScript } = require('./router.js');

const CLAIM_CHECK_FROM = '2026-10-09';
const RULE = 'claim-check-missing';

// The feature dir is the directory of the TASKS.md flow-lint resolved, so a
// stealth store (.specs symlinked elsewhere) needs no special case: verify/
// sits beside TASKS.md wherever that physically is.
function claimCheckProblem(header, tasksFile, root) {
  const v = (header && header.verified) || '';
  if (!/\(pre-approved: \/flow:next --finish\)/.test(v)) return null;
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(v);
  if (!m || m[1] < CLAIM_CHECK_FROM) return null;
  const file = path.join(path.dirname(path.resolve(root, tasksFile)), 'verify', 'claim-check.md');
  let text;
  try {
    text = fs.readFileSync(file, 'utf8');
  } catch {
    return {
      message: `Verified: is pre-approved but ${file} is missing`,
      fix: 'spawn the claim-check agent on the acceptance rows, have it write verify/claim-check.md, then re-run flow lint',
    };
  }
  // Only the summary line counts; CLAIM/OUTPUT lines above it may quote any number.
  const sums = [...text.matchAll(/\d+ confirmed, (\d+) unsupported/g)];
  const u = sums.length ? sums[sums.length - 1] : null;
  if (u && Number(u[1]) > 0) {
    return {
      message: `${file} reports ${u[1]} unsupported claim(s) behind a pre-approved Verified:`,
      fix: 'an unsupported acceptance row is unmet: append a task per the converge rule and clear Verified: until it is re-checked',
    };
  }
  return null;
}

function run(argv, root, io, env) {
  const script = pluginScript('flow-lint', env);
  if (!script) {
    io.stderr.write('flow lint: flow-lint is not installed beside this CLI\n  fix: reinstall the flow plugin (flow install), or run scripts/flow-lint directly\n');
    return 2;
  }
  const wantJson = argv.includes('--json');
  const probeArgs = argv.filter((a) => a !== '--waves' && a !== '--json').concat('--json');
  const probe = spawnSync('bash', [script].concat(probeArgs), { cwd: root, encoding: 'utf8' });
  let parsed = null;
  try {
    parsed = JSON.parse(probe.stdout || '');
  } catch {
    parsed = null;
  }
  const problem = parsed && parsed.file ? claimCheckProblem(parsed.header, parsed.file, root) : null;
  if (!problem) {
    const r = spawnSync('bash', [script].concat(argv), { cwd: root, stdio: 'inherit' });
    return r.status === null ? 2 : r.status;
  }
  if (wantJson) {
    parsed.errors.push({ line: 0, id: '', rule: RULE, message: problem.message, fix: problem.fix });
    parsed.ok = false;
    io.stdout.write(`${JSON.stringify(parsed)}\n`);
    return 1;
  }
  const r = spawnSync('bash', [script].concat(argv), { cwd: root, encoding: 'utf8', stdio: ['inherit', 'pipe', 'inherit'] });
  const kept = (r.stdout || '').split('\n').filter((l) => !/^OK /.test(l)).join('\n').replace(/\n+$/, '');
  if (kept) io.stdout.write(`${kept}\n`);
  io.stdout.write(`ERROR 0: [${RULE}] ${problem.message}\n  fix: ${problem.fix}\n`);
  return r.status === null ? 2 : 1;
}

// withClaimCheck(json, root) -> json with the claim-check ERROR added. The
// router calls it so `flow next` routes a pre-approved Verified: with no
// claim-check to invalid, not only a hand-run `flow lint`.
function withClaimCheck(json, root) {
  const problem = json && json.file ? claimCheckProblem(json.header, json.file, root) : null;
  if (!problem) return json;
  json.errors = (json.errors || []).concat({ line: 0, id: '', rule: RULE, message: problem.message, fix: problem.fix });
  json.ok = false;
  return json;
}

module.exports = { run, withClaimCheck };
