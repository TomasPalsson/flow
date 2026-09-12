'use strict';

// loop/init.js — `flow loop init` (K-C, K-G).

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { readContract, writeContract } = require('./contract.js');
const { runVerify } = require('./verify.js');
const { countTestFiles } = require('./tamper.js');
const { appendLog } = require('./log.js');
const { sha1, slugify, ensureLoopGitignore } = require('./util.js');
const { cmdStop } = require('./status.js');

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

function buildInitFront(toplevel, args, base) {
  const now = new Date().toISOString();
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
    // Slice 5 (--test-files): explicit tamper-protected paths (e.g.
    // plugins/flow/evals/**, FR-008) win over the auto-detected count, so a
    // caller can protect data dirs the isTestPath heuristic never matches.
    test_files: args.testFiles.length ? args.testFiles.join(',') : String(countTestFiles(toplevel)),
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

  const base = (spawnSync('git', ['-C', toplevel, 'rev-parse', 'HEAD'], { encoding: 'utf8' }).stdout || '').trim();
  const front = buildInitFront(toplevel, args, base);
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

module.exports = { cmdInit };
