'use strict';

// loop/check.js — `flow loop check` (K-C/K-F): runs the verifier and the
// tamper check; never mutates the contract.

const { readContract } = require('./contract.js');
const { runVerify } = require('./verify.js');
const { tamperCheck } = require('./tamper.js');
const { toInt } = require('./util.js');

function verdictOf(rc, tamper) {
  if (rc !== 0) return 'fail';
  return tamper.length ? 'suspect' : 'pass';
}

function cmdCheck(argv, toplevel, env) {
  const jsonMode = argv.includes('--json');
  const contract = readContract(toplevel);
  if (!contract) {
    process.stderr.write('flow loop check: no loop contract (run flow loop init first)\n');
    return 1;
  }
  if (contract.corrupt) {
    process.stderr.write(`corrupt contract: ${contract.corrupt}\n`);
    return 1;
  }
  const front = contract.front;
  const verify = runVerify(toplevel, front.verify, toInt(front.verify_timeout) || 600, env);
  const tamper = tamperCheck(toplevel, front, env);
  const verdict = verdictOf(verify.rc, tamper);
  const tail = verify.output.split('\n').slice(-40).join('\n');

  if (jsonMode) {
    process.stdout.write(`${JSON.stringify({ verdict, verify_rc: verify.rc, tamper, tail }, null, 2)}\n`);
  } else {
    process.stdout.write(
      [`verdict: ${verdict}`, `verify_rc: ${verify.rc}`, `tamper: [${tamper.join(', ')}]`, tail, ''].join('\n')
    );
  }
  if (verdict === 'pass') return 0;
  if (verdict === 'suspect') return 2;
  return 1;
}

module.exports = { cmdCheck };
