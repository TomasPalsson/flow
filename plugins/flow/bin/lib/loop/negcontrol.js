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

// preflight(toplevel, filePath, file) — design §2: the working tree and the
// target are untrusted input, checked before anything is written. Throws
// with a one-line reason naming the file; init.js maps that to exit 3.
function preflight(toplevel, filePath, file) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch {
    throw new Error(`${file} does not exist; refusing to arm`);
  }
  if (stat.isSymbolicLink()) throw new Error(`${file} is a symlink; refusing to arm`);
  if (stat.isDirectory()) throw new Error(`${file} is a directory; refusing to arm`);
  const tracked = spawnSync('git', ['-C', toplevel, 'ls-files', '--error-unmatch', file], { encoding: 'utf8' });
  if (tracked.status !== 0) throw new Error(`${file} is not a tracked file; refusing to arm`);
  // Excludes .claude: runVerify (called once already, before this gate) has
  // already written .claude/loop/verify.last, its own scratch file, which
  // would otherwise make every tree look dirty.
  const dirty = spawnSync(
    'git', ['-C', toplevel, 'status', '--porcelain', '--', '.', ':!.claude'], { encoding: 'utf8' }
  );
  if ((dirty.stdout || '').trim() !== '') {
    throw new Error(`the working tree is dirty; refusing to arm before touching ${file}`);
  }
}

// normalizeOutput — digit runs (PIDs, epoch/nanosecond timestamps, run
// counters) vary between the two verifier calls without the break causing
// it, and would otherwise read as a real change; collapse them before
// comparing. ponytail: does not scrub letters-only random tokens (e.g. a
// mktemp suffix); widen the pattern if that starts producing false arms.
function normalizeOutput(output) {
  return String(output || '').replace(/[0-9]+/g, '#');
}

// runNegControl(toplevel, opts) -> { verdict, file, restored, ms }
// opts = { verify, verifyTimeout, file, env }. Costs exactly 2 verifier runs
// (spec §5): one before the break, one after, compared on exit code and on
// normalized output so a verifier blind to this file (same result both
// times) is caught even when both runs are red for an unrelated reason.
function runNegControl(toplevel, opts) {
  const { verify, verifyTimeout, file, env } = opts;
  const filePath = path.join(toplevel, file);
  const timeoutSec = parseInt(verifyTimeout, 10) || 600;
  const boundMs = 2 * timeoutSec * 1000;
  const start = Date.now();

  preflight(toplevel, filePath, file);

  const before = runVerify(toplevel, verify, verifyTimeout, env);
  if (before.rc === 124) {
    return { verdict: 'timeout', file, restored: true, ms: Date.now() - start, verifierTimedOut: true };
  }

  const original = fs.readFileSync(filePath);
  let restored = false;

  const restore = () => {
    const r = spawnSync('git', ['-C', toplevel, 'checkout', '--', file], { encoding: 'utf8' });
    let restoredBytes = null;
    try { restoredBytes = fs.readFileSync(filePath); } catch { /* left missing */ }
    restored = r.status === 0 && restoredBytes !== null && restoredBytes.equals(original);
    return restored;
  };

  // FR-05: restoration happens whether the run "passed, failed, or was
  // interrupted" — a signal during the after-run must not skip it.
  const onSignal = (code) => () => {
    restore();
    process.exit(code);
  };
  const onSigint = onSignal(130);
  const onSigterm = onSignal(143);
  process.on('SIGINT', onSigint);
  process.on('SIGTERM', onSigterm);

  let after;
  try {
    inducedBreak(filePath);
    after = runVerify(toplevel, verify, verifyTimeout, env);
  } finally {
    restore();
    process.removeListener('SIGINT', onSigint);
    process.removeListener('SIGTERM', onSigterm);
  }
  const ms = Date.now() - start;

  // Not-restored is the loudest case (design §2): a broken tree outranks any
  // other reading of the two verifier runs.
  if (!restored) return { verdict: 'not-restored', file, restored, ms };
  if (after.rc === 124) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: true };
  if (ms > boundMs) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: false };
  const rcChanged = before.rc !== after.rc;
  const outputChanged = normalizeOutput(before.output) !== normalizeOutput(after.output);
  if (!rcChanged && !outputChanged) return { verdict: 'survived', file, restored, ms };
  return { verdict: 'red-then-restored', file, restored, ms };
}

module.exports = { runNegControl };
