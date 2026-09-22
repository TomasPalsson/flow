'use strict';

// loop/init.js — `flow loop init` (K-C, K-G).

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { readContract, writeContract } = require('./contract.js');
const { runVerify } = require('./verify.js');
const { runNegControl } = require('./negcontrol.js');
const { countTestFiles, targetSha, envSha } = require('./tamper.js');
const { appendLog } = require('./log.js');
const { sha1, slugify, ensureLoopGitignore } = require('./util.js');
const { cmdStop } = require('./status.js');
const { EVALS_ROOT } = require('../eval/contract.js');

const DEFAULT_PROMPT = [
  'You are one iteration of a loop. The loop, not you, decides when the goal is met: it runs',
  '`{verify}` after every iteration and stops when it exits 0. Do not claim completion.',
  '',
  'Goal: {goal}',
  '',
  'Each iteration:',
  '1. Read .claude/loop/LEARNINGS.md (Codebase patterns first) and `git log --oneline {base}..HEAD`.',
  '2. Run the verifier yourself and read the failure. Pick the ONE smallest change that moves it.',
  '3. Make that change. Run the verifier again. Commit on green with a message that names the change.',
  '4. Append one dated entry to .claude/loop/LEARNINGS.md: what you did, what you learned, what is next.',
  '5. Stop. The loop will re-run the verifier and start the next iteration.',
  '',
  'Never edit, delete, skip or weaken a test, and never change the verifier command or gate config,',
  'to make the verifier pass; the loop checks for that and will mark the run suspect.',
  'If the goal cannot be met (wrong premise, missing access, contradictory tests), write',
  '.claude/loop/BLOCKED.md with what you tried and why it cannot work, then stop.',
  '',
].join('\n');

function defaultBody(verify, goal, base) {
  return DEFAULT_PROMPT.replace('{verify}', verify).replace('{goal}', goal).replace('{base}', base);
}

function parseInitArgs(argv) {
  const out = {
    goal: null, verify: null, shape: 'session', promptFile: null, prompt: null, session: '',
    maxIterations: null, maxMinutes: null, maxUsd: 0, stallAfter: 3, verifyTimeout: 600,
    permissionMode: 'auto', model: '', maxTurns: 0, allowGreen: false, force: false, testFiles: [],
    target: null, negControlFile: null,
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--verify') out.verify = argv[++i];
    else if (a === '--shape') out.shape = argv[++i];
    else if (a === '--prompt-file') out.promptFile = argv[++i];
    else if (a === '--prompt') out.prompt = argv[++i];
    else if (a === '--session') out.session = argv[++i];
    else if (a === '--max-iterations') out.maxIterations = argv[++i];
    else if (a === '--max-minutes') out.maxMinutes = argv[++i];
    else if (a === '--max-usd') out.maxUsd = argv[++i];
    else if (a === '--stall-after') out.stallAfter = argv[++i];
    else if (a === '--verify-timeout') out.verifyTimeout = argv[++i];
    else if (a === '--permission-mode') out.permissionMode = argv[++i];
    else if (a === '--model') out.model = argv[++i];
    else if (a === '--max-turns') out.maxTurns = argv[++i];
    else if (a === '--allow-green') out.allowGreen = true;
    else if (a === '--force') out.force = true;
    else if (a === '--test-files') out.testFiles.push(argv[++i]);
    else if (a === '--target') out.target = argv[++i];
    else if (a === '--neg-control-file') out.negControlFile = argv[++i];
    else if (!a.startsWith('--') && out.goal === null) out.goal = a;
  }
  if (out.maxIterations === null) out.maxIterations = out.shape === 'fresh' ? 30 : 8;
  if (out.maxMinutes === null) out.maxMinutes = out.shape === 'fresh' ? 480 : 0;
  return out;
}

function refuseIfActive(toplevel, args, stderrW) {
  const existing = readContract(toplevel);
  if (!existing || existing.front.status !== 'active') return 0;
  if (!args.force) {
    stderrW('flow loop init: an active loop contract exists; use --force to replace it (or flow loop stop)\n');
    return 1;
  }
  cmdStop(['--reason', 'manual'], toplevel);
  return 0;
}

// protectedFilesFront(toplevel, testFiles) -> the comma list tamper.js reads.
// FR-008: the eval suite is tamper-protected in any repo that has it, with or
// without --test-files, so an optimisation loop cannot rewrite the cases it is
// being scored on (AC-011). Repos without plugins/flow/evals are unaffected.
function protectedFilesFront(toplevel, testFiles) {
  const paths = testFiles.filter(Boolean);
  if (fs.existsSync(path.join(toplevel, EVALS_ROOT))) paths.push(EVALS_ROOT);
  return [...new Set(paths)].join(',');
}

// negControlExitCodes — §3 of design.md: survived -> 4, not-restored -> 5,
// timeout -> 6. 'red-then-restored' is not a refusal and has no entry here.
const NEG_CONTROL_EXIT_CODES = { survived: 4, 'not-restored': 5, timeout: 6 };

// runNegControlGate(toplevel, args, env, stderrW) -> exit code, or 0 to
// proceed arming. FR-04/FR-05/FR-11: the control runs before writeContract
// (design §7 decision 2), so a refusal here leaves no contract file behind.
function runNegControlGate(toplevel, args, env, stderrW) {
  if (!args.negControlFile) return 0;
  const result = runNegControl(toplevel, {
    verify: args.verify, verifyTimeout: args.verifyTimeout, file: args.negControlFile, env,
  });
  if (result.verdict === 'red-then-restored') return 0;
  const messages = {
    survived: `flow loop init: the negative control broke ${result.file} but the verifier's verdict did not change; refusing to arm\n`,
    'not-restored': `flow loop init: the negative control could not restore ${result.file}; a human must look\n`,
    timeout: `flow loop init: the negative control did not return within its time bound; refusing to arm\n`,
  };
  stderrW(messages[result.verdict]);
  return NEG_CONTROL_EXIT_CODES[result.verdict];
}

// findVerifyScript — every whitespace-separated token in `verify` that
// resolves (relative to toplevel) to an existing file, space-joined; '' if
// none does. (F2: a wrapper like "cat README.md && sh tests/ui/verify.sh"
// must freeze both files, not just the first token that happens to stat.)
function findVerifyScript(toplevel, verify) {
  const found = [];
  for (const raw of String(verify || '').split(/\s+/)) {
    const tok = raw.replace(/^['"]|['"]$/g, '');
    if (!tok || tok.startsWith('-')) continue;
    try {
      if (fs.statSync(path.join(toplevel, tok)).isFile()) found.push(tok);
    } catch { /* not a file */ }
  }
  return found.join(' ');
}

function repoRelative(toplevel, target) {
  if (!target) return '';
  const abs = path.isAbsolute(target) ? target : path.join(toplevel, target);
  return path.relative(toplevel, abs);
}

function uiScorePath() {
  const p = path.join(__dirname, '..', '..', '..', 'scripts', 'ui-score');
  return fs.existsSync(p) ? p : '';
}

function buildInitFront(toplevel, args, base, env) {
  const now = new Date().toISOString();
  const target = repoRelative(toplevel, args.target);
  // targetScript is an absolute path into the flow plugin's own scripts/;
  // scope it to the --target case or a plugin update marks every unrelated
  // loop on the machine suspect the next time the plugin changes.
  const targetScript = args.target ? uiScorePath() : '';
  const verifyScript = findVerifyScript(toplevel, args.verify);
  return {
    version: '1',
    slug: slugify(args.goal),
    goal: args.goal,
    verify: args.verify,
    shape: args.shape,
    status: 'active',
    stop_reason: '',
    session_id: args.session,
    iteration: '0',
    max_iterations: String(args.maxIterations),
    max_minutes: String(args.maxMinutes),
    max_usd: String(args.maxUsd),
    stall_after: String(args.stallAfter),
    verify_timeout: String(args.verifyTimeout),
    permission_mode: args.permissionMode,
    model: args.model,
    max_turns: String(args.maxTurns),
    base,
    // test_files stays the auto-detected count (tamper.js's "test files
    // removed" check reads it as a number) regardless of --test-files, so
    // naming explicit paths never disables that check for the whole session.
    test_files: String(countTestFiles(toplevel)),
    // Slice 5 (--test-files): explicit tamper-protected paths, checked in
    // addition to test_files above so a caller can protect data dirs the
    // isTestPath heuristic never matches, without weakening the auto-detected
    // count check. FR-008 wires plugins/flow/evals in by default.
    protected_files: protectedFilesFront(toplevel, args.testFiles),
    target,
    target_script: targetScript,
    verify_script: verifyScript,
    target_sha: targetSha(toplevel, target, [targetScript, ...verifyScript.split(/\s+/)]),
    // Scoped to --target (a UI loop) the same way target_script is: freezes
    // ui-verify.sh's boot config (SERVE/PORT/HEALTH/BOOT/BASE_URL/
    // FLOW_UI_SCORE) so a later run can't redirect the verifier at a
    // different process by overriding those env vars (see tamper.js).
    env_sha: target ? envSha(env) : '',
    started_at: now,
    finished_at: '',
    cost_usd: '0',
    finish_reported: '0',
    verify_sha: sha1(args.verify),
    fp: '',
    sig: '',
    unchanged: '0',
    wedge_streak: '0',
  };
}

function initBody(args, base) {
  if (args.promptFile) return fs.readFileSync(args.promptFile, 'utf8');
  if (args.prompt) return args.prompt;
  return defaultBody(args.verify, args.goal, base);
}

function writeSummary(stdoutW, front) {
  stdoutW(
    [
      `loop: ${front.slug}`,
      `  goal:   ${front.goal}`,
      `  verify: ${front.verify}`,
      `  shape:  ${front.shape}`,
      `  caps:   max-iterations=${front.max_iterations} max-minutes=${front.max_minutes} ` +
        `max-usd=${front.max_usd} stall-after=${front.stall_after} verify-timeout=${front.verify_timeout}`,
      '  files:  .claude/loop/loop.md, .claude/loop/LEARNINGS.md, .claude/loop/loop.log\n',
    ].join('\n')
  );
  if (front.shape === 'session') {
    stdoutW('armed: loop-gate.sh will re-feed the prompt on every Stop until the verifier passes\n');
  }
}

function cmdInit(argv, toplevel, env) {
  const args = parseInitArgs(argv);
  const refused = refuseIfActive(toplevel, args, (s) => process.stderr.write(s));
  if (refused) return refused;
  if (!args.goal) {
    process.stderr.write('flow loop init: a goal is required\n');
    return 1;
  }
  if (!args.verify) {
    process.stderr.write('flow loop init: --verify is required\n');
    return 1;
  }

  const verifyRun = runVerify(toplevel, args.verify, args.verifyTimeout, env);
  if (verifyRun.rc === 0 && !args.allowGreen) {
    process.stderr.write('flow loop init: verifier already passes; nothing to loop (use --allow-green to loop anyway)\n');
    return 1;
  }

  const negControlExit = runNegControlGate(toplevel, args, env, (s) => process.stderr.write(s));
  if (negControlExit) return negControlExit;

  const base = (spawnSync('git', ['-C', toplevel, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout || '').trim();
  const front = buildInitFront(toplevel, args, base, env);
  const body = initBody(args, base);
  writeContract(toplevel, front, body);
  ensureLoopGitignore(toplevel);

  const learningsPath = path.join(toplevel, '.claude', 'loop', 'LEARNINGS.md');
  if (!fs.existsSync(learningsPath)) fs.writeFileSync(learningsPath, '## Codebase patterns\n\n');

  appendLog(toplevel, {
    event: 'init', iter: '0', headBefore: base, headAfter: base, verify: verifyRun.rc, sig: verifyRun.sig,
    changed: 0, cost: '-', dur: '-', note: '',
  });

  writeSummary((s) => process.stdout.write(s), front);
  return 0;
}

module.exports = { cmdInit, findVerifyScript };
