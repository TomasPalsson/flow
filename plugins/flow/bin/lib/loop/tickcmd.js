'use strict';

// loop/tickcmd.js — `flow loop tick` CLI wrapper around tick.js's state
// machine. `--hook` prints exactly the Claude Code Stop JSON to emit, or
// nothing on allow; always exits 0 (K-H).

const { tick } = require('./tick.js');

function cmdTick(argv, toplevel, env) {
  const jsonMode = argv.includes('--json');
  const hookMode = argv.includes('--hook');
  const si = argv.indexOf('--session');
  const session = si !== -1 ? argv[si + 1] : '';

  const result = tick(toplevel, { session, hook: hookMode, env });

  if (hookMode) {
    if (result.action === 'continue' || result.action === 'finish') {
      process.stdout.write(`${JSON.stringify({ decision: 'block', reason: result.reason })}\n`);
    }
    return 0;
  }
  if (jsonMode) {
    process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
    return 0;
  }
  const suffix = result.status ? ` (status=${result.status}, iteration=${result.iteration})` : '';
  process.stdout.write(`tick: ${result.action}${suffix}\n`);
  if (result.reason) process.stdout.write(`${result.reason}\n`);
  return 0;
}

module.exports = { cmdTick };
