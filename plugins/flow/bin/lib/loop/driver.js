'use strict';

// loop/driver.js — `flow loop run`, the fresh-shape driver (K-I).

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { readContract, writeContract } = require('./contract.js');
const { tick } = require('./tick.js');
const { appendLog } = require('./log.js');
const { cmdStatus } = require('./status.js');
const { toInt, toFloat, headSha, gitDirty, fmtCost, resolveOnPath } = require('./util.js');

function parseRunArgs(argv) {
  const out = {
    maxIterations: null, maxMinutes: null, maxUsd: null, permissionMode: null, model: null,
    maxTurns: null, dryRun: argv.includes('--dry-run'), noCheckpoint: argv.includes('--no-checkpoint'),
    worktree: argv.includes('--worktree'),
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--max-iterations') out.maxIterations = argv[++i];
    else if (a === '--max-minutes') out.maxMinutes = argv[++i];
    else if (a === '--max-usd') out.maxUsd = argv[++i];
    else if (a === '--permission-mode') out.permissionMode = argv[++i];
    else if (a === '--model') out.model = argv[++i];
    else if (a === '--max-turns') out.maxTurns = argv[++i];
  }
  return out;
}

// Flags given to `run` override the caps recorded at init for this
// invocation only (persisted, since tick() reads caps from the contract).
function applyRunOverrides(front, flags) {
  if (flags.maxIterations !== null) front.max_iterations = String(flags.maxIterations);
  if (flags.maxMinutes !== null) front.max_minutes = String(flags.maxMinutes);
  if (flags.maxUsd !== null) front.max_usd = String(flags.maxUsd);
  if (flags.permissionMode !== null) front.permission_mode = flags.permissionMode;
  if (flags.model !== null) front.model = flags.model;
  if (flags.maxTurns !== null) front.max_turns = String(flags.maxTurns);
  return front;
}

function buildClaudeArgs(front, prompt) {
  const args = ['-p', prompt, '--output-format', 'json', '--permission-mode', front.permission_mode || 'auto'];
  if (front.model) args.push('--model', front.model);
  if (toInt(front.max_turns) > 0) args.push('--max-turns', String(toInt(front.max_turns)));
  const remaining = toFloat(front.max_usd) > 0 ? Math.max(0, toFloat(front.max_usd) - toFloat(front.cost_usd)) : null;
  if (remaining !== null) args.push('--max-budget-usd', String(remaining));
  return args;
}

function printRunPlan(front, claudePath, prompt) {
  const args = buildClaudeArgs(front, `<prompt: ${prompt.length} chars>`);
  process.stdout.write(
    [
      `flow loop run --dry-run: shape=${front.shape} slug=${front.slug}`,
      `caps: max-iterations=${front.max_iterations} max-minutes=${front.max_minutes} max-usd=${front.max_usd}`,
      `argv: ${claudePath || 'claude'} ${args.join(' ')}`,
      'tick rules: verifier runs before any child is spawned (K-H); continue spawns a child, ' +
        'pass/suspect/stopped deliver one finishing block, then further ticks allow.',
      '',
    ].join('\n')
  );
}

function saveIterationJson(toplevel, n, payload) {
  const dir = path.join(toplevel, '.claude', 'loop', 'iterations');
  fs.mkdirSync(dir, { recursive: true });
  const name = `${String(n).padStart(3, '0')}.json`;
  fs.writeFileSync(path.join(dir, name), JSON.stringify(payload, null, 2));
}

function spawnChild(claudePath, front, prompt, toplevel, env) {
  const args = buildClaudeArgs(front, prompt);
  const r = spawnSync(claudePath, args, { cwd: toplevel, input: '', encoding: 'utf8', env });
  let payload = null;
  try {
    payload = JSON.parse(r.stdout || '{}');
  } catch {
    payload = null;
  }
  const isError = r.status !== 0 || Boolean(payload && payload.is_error);
  return { payload: payload || { raw_stdout: r.stdout, raw_stderr: r.stderr, status: r.status }, isError };
}

// Loop state never rides a checkpoint commit (K-A); only LEARNINGS.md may.
const CHECKPOINT_EXCLUDES = [
  ':(exclude).claude/loop/loop.md', ':(exclude).claude/loop/loop.log',
  ':(exclude).claude/loop/verify.last', ':(exclude).claude/loop/iterations',
  ':(exclude).claude/loop/BLOCKED.md', ':(exclude).claude/loop/loop.md.corrupt',
];

function checkpointIfDirty(toplevel, front, iterNum, noCheckpoint, durSec) {
  if (noCheckpoint || !gitDirty(toplevel)) return;
  spawnSync('git', ['-C', toplevel, 'add', '-A', '--', '.'].concat(CHECKPOINT_EXCLUDES));
  spawnSync('git', ['-C', toplevel, 'commit', '-q', '-m', `loop(${front.slug}) iteration ${iterNum}: checkpoint`]);
  appendLog(toplevel, {
    event: 'checkpoint', iter: iterNum, headBefore: front.base, headAfter: headSha(toplevel),
    verify: '-', sig: '-', changed: 1, cost: fmtCost(front.cost_usd), dur: durSec, note: '',
  });
}

// One driver step: spawn the child for a `continue` tick result, update
// cost/error-streak bookkeeping, checkpoint. Returns the new error streak.
function runIteration(toplevel, claudePath, env, flags, iterNum, prompt, errorStreak) {
  const spawned = spawnChild(claudePath, readContract(toplevel).front, prompt, toplevel, env);
  saveIterationJson(toplevel, iterNum, spawned.payload);

  const durSec = spawned.payload && typeof spawned.payload.duration_ms === 'number' ? Math.round(spawned.payload.duration_ms / 1000) : '-';
  const contract = readContract(toplevel);
  const front = contract.front;
  if (spawned.payload && typeof spawned.payload.total_cost_usd === 'number') {
    front.cost_usd = fmtCost(toFloat(front.cost_usd) + spawned.payload.total_cost_usd, 6);
  }
  let streak = errorStreak;
  if (spawned.isError) {
    streak += 1;
    appendLog(toplevel, {
      event: 'error', iter: iterNum, headBefore: front.base, headAfter: headSha(toplevel),
      verify: '-', sig: '-', changed: 0, cost: fmtCost(front.cost_usd), dur: durSec, note: 'claude -p error',
    });
    if (streak >= 3) {
      front.status = 'stopped';
      front.stop_reason = 'error';
      front.finished_at = new Date().toISOString();
    }
  } else {
    streak = 0;
  }
  writeContract(toplevel, front, contract.body);
  if (front.status === 'active') checkpointIfDirty(toplevel, front, iterNum, flags.noCheckpoint, durSec);
  return streak;
}

function runDriver(toplevel, claudePath, env, flags) {
  let errorStreak = 0;
  for (;;) {
    const result = tick(toplevel, { session: '', hook: false, env, now: Date.now() });
    if (result.action === 'allow') break;
    if (result.action === 'finish') {
      process.stdout.write(`${result.reason}\n`);
      break;
    }
    process.stdout.write(`iter ${result.iteration}: continue\n`);
    errorStreak = runIteration(toplevel, claudePath, env, flags, result.iteration, result.reason, errorStreak);
    // An error-streak stop is delivered by the next tick as a `finish`
    // (K-H rule 4) — never break past it, or the finishing text is lost.
  }
}

// --worktree: reuse (or create) `.claude/worktrees/loop-<slug>` on branch
// `loop/<slug>`, copy the contract dir into it, run everything there.
function setupWorktree(toplevel, front) {
  const wtPath = path.join(toplevel, '.claude', 'worktrees', `loop-${front.slug}`);
  if (!fs.existsSync(wtPath)) {
    spawnSync('git', ['-C', toplevel, 'worktree', 'add', '-b', `loop/${front.slug}`, wtPath, 'HEAD']);
  }
  const src = path.join(toplevel, '.claude', 'loop');
  const dest = path.join(wtPath, '.claude', 'loop');
  fs.mkdirSync(dest, { recursive: true });
  for (const f of fs.readdirSync(src)) fs.cpSync(path.join(src, f), path.join(dest, f), { recursive: true });
  process.stdout.write(`${wtPath}\n`);
  return wtPath;
}

function cmdRun(argv, toplevel, env) {
  const flags = parseRunArgs(argv);
  const contract = readContract(toplevel);
  if (!contract || contract.corrupt) {
    process.stderr.write('flow loop run: no active loop contract (run flow loop init first)\n');
    return 1;
  }
  const front = applyRunOverrides(contract.front, flags);
  if (front.shape !== 'fresh') {
    process.stderr.write('flow loop run: contract shape is not "fresh"\n');
    return 1;
  }
  if (flags.worktree && !flags.dryRun) toplevel = setupWorktree(toplevel, front);
  writeContract(toplevel, front, contract.body);

  const claudePath = resolveOnPath('claude', env);
  if (flags.dryRun) {
    printRunPlan(front, claudePath, contract.body);
    return 0;
  }
  if (front.status !== 'active') {
    process.stderr.write('flow loop run: contract is not active\n');
    return 1;
  }
  if (!claudePath) {
    process.stderr.write('claude CLI not found; run the loop from an interactive session with shape=session instead\n');
    return 2;
  }

  runDriver(toplevel, claudePath, env, flags);

  const final = readContract(toplevel);
  const status = final ? final.front.status : 'stopped';
  cmdStatus([], toplevel);
  if (status === 'done') return 0;
  if (status === 'suspect') return 2;
  return 1;
}

module.exports = { cmdRun };
