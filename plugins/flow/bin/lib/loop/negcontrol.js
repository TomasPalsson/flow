'use strict';

// loop/negcontrol.js — the arming safety net (spec 010 FR-04, FR-05, FR-11):
// prove the composed verifier can go red before a loop is armed on it, by
// deliberately breaking one tracked file and re-running the same verifier.
// Never writes the contract; init.js only arms after a passing verdict.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { runVerify } = require('./verify.js');

// inducedBreak(filePath) — the single-file edit: truncate to empty. Reverted
// by `git checkout -- <file>` (design §7 decision 1), never a multi-file
// mutation, so recovery is one command and cannot partially apply.
function inducedBreak(filePath) {
  fs.writeFileSync(filePath, Buffer.alloc(0));
}

// runNegControl(toplevel, opts) -> { verdict, file, restored, ms }
// opts = { verify, verifyTimeout, file, env }. Costs exactly 2 verifier runs
// (spec §5): one before the break, one after, compared by signature so a
// verifier blind to this file (same signature both times) is caught even
// when both runs are red for an unrelated reason.
function runNegControl(toplevel, opts) {
  const { verify, verifyTimeout, file, env } = opts;
  const filePath = path.join(toplevel, file);
  const timeoutSec = parseInt(verifyTimeout, 10) || 600;
  const boundMs = 2 * timeoutSec * 1000;
  const start = Date.now();

  const before = runVerify(toplevel, verify, verifyTimeout, env);
  if (before.rc === 124) return { verdict: 'timeout', file, restored: true, ms: Date.now() - start };

  const original = fs.readFileSync(filePath);
  inducedBreak(filePath);
  const after = runVerify(toplevel, verify, verifyTimeout, env);

  const restore = spawnSync('git', ['-C', toplevel, 'checkout', '--', file], { encoding: 'utf8' });
  let restoredBytes = null;
  try { restoredBytes = fs.readFileSync(filePath); } catch { /* left missing */ }
  const restored = restore.status === 0 && restoredBytes !== null && restoredBytes.equals(original);
  const ms = Date.now() - start;

  // Not-restored is the loudest case (design §2): a broken tree outranks any
  // other reading of the two verifier runs.
  if (!restored) return { verdict: 'not-restored', file, restored, ms };
  if (after.rc === 124 || ms > boundMs) return { verdict: 'timeout', file, restored, ms };
  if (after.sig === before.sig) return { verdict: 'survived', file, restored, ms };
  return { verdict: 'red-then-restored', file, restored, ms };
}

module.exports = { runNegControl };
