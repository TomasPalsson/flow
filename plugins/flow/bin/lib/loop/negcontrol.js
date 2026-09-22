'use strict';

// loop/negcontrol.js — the arming safety net (spec 010 FR-04, FR-05, FR-11):
// prove the composed verifier can go red before a loop is armed on it, by
// deliberately breaking one tracked file and re-running the same verifier.
// Never writes the contract; init.js only arms after a passing verdict.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const { runVerify, signatureOf } = require('./verify.js');

// inducedBreak(filePath) — the single-file edit: truncate to empty. Reverted
// by `git checkout -- <file>` (design §7 decision 1), never a multi-file
// mutation, so recovery is one command and cannot partially apply.
function inducedBreak(filePath) {
  fs.writeFileSync(filePath, Buffer.alloc(0));
}

// preflight(toplevel, filePath, file) — design §2: the working tree and the
// target are untrusted input, checked before anything is written. Throws
// with a one-line reason naming the file, tagged so init.js can tell an
// input problem (exit 3) apart from a failure once the control is running.
function preflight(toplevel, filePath, file) {
  let stat;
  try {
    stat = fs.lstatSync(filePath);
  } catch {
    throw Object.assign(new Error(`${file} does not exist; refusing to arm`), { preflight: true });
  }
  if (stat.isSymbolicLink()) throw Object.assign(new Error(`${file} is a symlink; refusing to arm`), { preflight: true });
  if (stat.isDirectory()) throw Object.assign(new Error(`${file} is a directory; refusing to arm`), { preflight: true });
  const tracked = spawnSync('git', ['-C', toplevel, 'ls-files', '--error-unmatch', file], { encoding: 'utf8' });
  if (tracked.status !== 0) {
    throw Object.assign(new Error(`${file} is not a tracked file; refusing to arm`), { preflight: true });
  }
  // Scoped to the target path only: the break writes one file and the
  // restore is `git checkout -- <that file>`, so unrelated tree dirt (a
  // verifier's own log file, a stray scratch file) is none of this check's
  // business — only uncommitted work IN the target would be lost.
  const dirty = spawnSync('git', ['-C', toplevel, 'status', '--porcelain', '--', file], { encoding: 'utf8' });
  if ((dirty.stdout || '').trim() !== '') {
    throw Object.assign(new Error(`${file} has uncommitted changes; refusing to arm`), { preflight: true });
  }
}

// sigFor — verify.js's signatureOf already masks hashes, addresses and
// durations; a PID, a run counter, or a mktemp path is none of those, so
// collapse long digit runs and long mixed alnum tokens first (both are
// generated fresh each call and carry no signal about the break) before
// signatureOf's own, narrower masking and hashing.
function sigFor(output) {
  // Order matters: a long random token (e.g. a 10-char mktemp suffix) can
  // contain an internal run of 4+ digits; masking digits first fragments
  // it into pieces each under 7 chars, so the second pass no longer sees
  // one token to mask and the token leaks through unmasked.
  const collapsed = String(output || '')
    .replace(/[A-Za-z0-9]{7,}/g, '#')
    .replace(/[0-9]{4,}/g, '#');
  return signatureOf(collapsed);
}

// startRestoreGuardian — a detached shell that outlives a killed parent.
// `spawnSync` blocks Node's one thread until its child returns, so a
// `process.on('SIGINT', ...)` handler here cannot run until AFTER that
// call returns (Node's own docs for spawnSync say no other work happens
// until the child exits) — by then the CLI's synchronous dispatch has
// already reached its final `process.exit()` and the handler never gets a
// turn, so it can neither restore reliably nor stop an arm the run would
// otherwise reach. A real Ctrl-C also lands on this whole process group,
// so the guardian's own `trap` (bash's signal handling, not Node's)
// restores immediately; a signal aimed only at the parent instead kills it
// outright, with no handler suppressing that, and the guardian notices the
// parent is gone and restores a moment later either way.
function startRestoreGuardian(toplevel, file, env) {
  const script = [
    'trap \'git -C "$NC_TOPLEVEL" checkout -- "$NC_FILE" 2>/dev/null; exit 0\' INT TERM',
    'while kill -0 "$NC_PPID" 2>/dev/null; do sleep 0.2; done',
    'git -C "$NC_TOPLEVEL" checkout -- "$NC_FILE" 2>/dev/null',
  ].join('\n');
  return spawn('sh', ['-c', script], {
    cwd: toplevel,
    env: Object.assign({}, env, { NC_TOPLEVEL: toplevel, NC_FILE: file, NC_PPID: String(process.pid) }),
    stdio: 'ignore',
  });
}

// breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original)
// -> { after, restored }. FR-05: restoration happens whether the run
// "passed, failed, or was interrupted".
function breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original) {
  let restored = false;
  const restore = () => {
    const r = spawnSync('git', ['-C', toplevel, 'checkout', '--', file], { encoding: 'utf8' });
    let restoredBytes = null;
    try { restoredBytes = fs.readFileSync(filePath); } catch { /* left missing */ }
    restored = r.status === 0 && restoredBytes !== null && restoredBytes.equals(original);
    return restored;
  };

  const guardian = startRestoreGuardian(toplevel, file, env);
  let after;
  try {
    inducedBreak(filePath);
    after = runVerify(toplevel, verify, verifyTimeout, env);
  } finally {
    guardian.kill();
    restore();
  }
  return { after, restored };
}

// runNegControl(toplevel, opts) -> { verdict, file, restored, ms }
// opts = { verify, verifyTimeout, file, env }. Costs exactly 2 verifier runs
// (spec §5): one before the break, one after, compared on exit code and on
// a masked signature so a verifier blind to this file (same result both
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
  const { after, restored } = breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original);
  const ms = Date.now() - start;

  // Not-restored is the loudest case (design §2): a broken tree outranks any
  // other reading of the two verifier runs.
  if (!restored) return { verdict: 'not-restored', file, restored, ms };
  if (after.rc === 124) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: true };
  if (ms > boundMs) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: false };
  const rcChanged = before.rc !== after.rc;
  const sigChanged = sigFor(before.output) !== sigFor(after.output);
  if (!rcChanged && !sigChanged) return { verdict: 'survived', file, restored, ms };
  return { verdict: 'red-then-restored', file, restored, ms };
}

module.exports = { runNegControl };
