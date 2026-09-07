'use strict';

// loop/status.js — `flow loop status`, `flow loop stop`, `flow loop log`.

const fs = require('node:fs');
const path = require('node:path');
const { readContract, writeContract } = require('./contract.js');
const { appendLog, lastLogLines } = require('./log.js');
const { headSha, fmtCost } = require('./util.js');

function verifyTail(toplevel, n) {
  let raw = '';
  try {
    raw = fs.readFileSync(path.join(toplevel, '.claude', 'loop', 'verify.last'), 'utf8');
  } catch { /* nothing run yet */ }
  return raw.split('\n').slice(-n).join('\n');
}

function cmdStatus(argv, toplevel) {
  const jsonMode = argv.includes('--json');
  const contract = readContract(toplevel);
  if (!contract) {
    if (jsonMode) process.stdout.write(`${JSON.stringify({ error: 'no contract' })}\n`);
    else process.stdout.write('flow loop status: no loop contract\n');
    return 3;
  }
  const lastLog = lastLogLines(toplevel, 1)[0] || '';
  const tail = verifyTail(toplevel, 20);
  if (jsonMode) {
    process.stdout.write(`${JSON.stringify({ front: contract.front, lastLog, verifyTail: tail }, null, 2)}\n`);
    return 0;
  }
  const f = contract.front;
  process.stdout.write(
    [
      `status: ${f.status}`,
      `slug: ${f.slug}`,
      `shape: ${f.shape}`,
      `iteration: ${f.iteration}/${f.max_iterations}`,
      `stop_reason: ${f.stop_reason || '-'}`,
      `last log: ${lastLog}`,
      '--- verify.last (tail) ---',
      tail,
      '',
    ].join('\n')
  );
  return 0;
}

function cmdStop(argv, toplevel) {
  const ri = argv.indexOf('--reason');
  const reason = ri !== -1 ? argv[ri + 1] : 'manual';
  const contract = readContract(toplevel);
  if (!contract || contract.front.status !== 'active') {
    process.stdout.write('no active loop\n');
    return 0;
  }
  const front = contract.front;
  front.status = 'stopped';
  front.stop_reason = reason;
  front.finished_at = new Date().toISOString();
  writeContract(toplevel, front, contract.body);
  appendLog(toplevel, {
    event: 'stop', iter: front.iteration, headBefore: front.base, headAfter: headSha(toplevel),
    verify: '-', sig: '-', changed: 0, cost: fmtCost(front.cost_usd), dur: '-', note: reason,
  });
  process.stdout.write(`flow loop stop: stopped (${reason})\n`);
  return 0;
}

function cmdLog(argv, toplevel) {
  const ni = argv.indexOf('-n');
  const n = ni !== -1 ? parseInt(argv[ni + 1], 10) || 20 : 20;
  const lines = lastLogLines(toplevel, n);
  if (argv.includes('--json')) {
    process.stdout.write(`${JSON.stringify({ lines })}\n`);
    return 0;
  }
  process.stdout.write(lines.length ? `${lines.join('\n')}\n` : '');
  return 0;
}

module.exports = { cmdStatus, cmdStop, cmdLog };
