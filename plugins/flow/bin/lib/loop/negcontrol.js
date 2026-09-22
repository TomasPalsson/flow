'use strict';

// loop/negcontrol.js — the arming safety net (spec 010 FR-04, FR-05, FR-11):
// prove the composed verifier can go red before a loop is armed on it, by
// deliberately breaking one tracked file and re-running the same verifier.
// Never writes the contract; init.js only arms after a passing verdict.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { runVerify, signatureOf } = require('./verify.js');

// inducedBreak(filePath) — the single-file edit: truncate to empty. Reverted
// from the bytes read before the break, never a multi-file mutation, so
// recovery is one write and cannot partially apply.
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
  // restore rewrites only that file, so unrelated tree dirt (a verifier's
  // own log file, a stray scratch file) is none of this check's business —
  // only uncommitted work IN the target would be lost.
  const dirty = spawnSync('git', ['-C', toplevel, 'status', '--porcelain', '--', file], { encoding: 'utf8' });
  if ((dirty.stdout || '').trim() !== '') {
    throw Object.assign(new Error(`${file} has uncommitted changes; refusing to arm`), { preflight: true });
  }
}

// runAfterUnderTrap(toplevel, file, verify, verifyTimeoutSec, env) -> { rc, output }
// One synchronous shell owns the break, the verifier and the restore: its
// `trap` restores on INT, TERM or plain exit, completing before this
// spawnSync returns, so nothing outlives it and a real Ctrl-C (which hits
// this whole process group) is covered. The restore reads the blob
// straight from the object database, never `git checkout`, so a verifier
// briefly holding `.git/index.lock` cannot turn a restorable file into a
// false "could not restore". `file` and `verify` cross into the shell only
// through `env`, never string interpolation.
function runAfterUnderTrap(toplevel, file, verify, verifyTimeoutSec, env) {
  const t = parseInt(verifyTimeoutSec, 10) || 600;
  const restoreCmd = 'git cat-file blob "HEAD:$NC_FILE" >"$NC_FILE.nc_tmp" 2>/dev/null '
    + '&& mv "$NC_FILE.nc_tmp" "$NC_FILE" || rm -f "$NC_FILE.nc_tmp"';
  const script = [
    `trap '${restoreCmd}' EXIT`,
    "trap 'exit 130' INT",
    "trap 'exit 143' TERM",
    ': > "$NC_FILE"',
    'sh -c "$NC_VERIFY"',
    'exit $?',
  ].join('\n');
  const r = spawnSync('sh', ['-c', script], {
    cwd: toplevel,
    env: Object.assign({}, env, { CI: 'true', FLOW_LOOP: '1', NC_FILE: file, NC_VERIFY: verify }),
    timeout: t * 1000,
    encoding: 'utf8',
  });
  let output = (r.stdout || '') + (r.stderr || '');
  let rc = r.status;
  if (r.error && r.error.code === 'ETIMEDOUT') {
    rc = 124;
    output += `\nverify timed out after ${t} s`;
  } else if (rc === null) {
    rc = 1;
  }
  return { rc, output };
}

// breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original)
// -> { after, restored }. FR-05: restoration happens whether the run
// "passed, failed, or was interrupted". The trap in runAfterUnderTrap is
// the first restore; this direct byte-write, from what was read before the
// break, is the second — needs no git command and so no index lock either.
function breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original) {
  let after;
  try {
    inducedBreak(filePath);
    after = runAfterUnderTrap(toplevel, file, verify, verifyTimeout, env);
  } finally {
    try { fs.writeFileSync(filePath, original); } catch { /* the read-back below reports the state */ }
  }
  let restored;
  try {
    restored = fs.readFileSync(filePath).equals(original);
  } catch {
    restored = false;
  }
  return { after, restored };
}

// runNegControl(toplevel, opts) -> { verdict, file, restored, ms }
// opts = { verify, verifyTimeout, file, env, baseline }. Costs exactly 2
// verifier runs of its own (spec §5): one before the break, one after.
// `baseline` (cmdInit's own pre-gate verify run, optional) and the
// control's own "before" run are two runs on an identical tree; comparing
// them measures whether this verifier's output is stable before trusting
// it to say anything about the break.
function runNegControl(toplevel, opts) {
  const { verify, verifyTimeout, file, env, baseline } = opts;
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
  const stable = baseline ? signatureOf(baseline.output) === signatureOf(before.output) : false;
  const outputChanged = stable && signatureOf(before.output) !== signatureOf(after.output);
  if (rcChanged || outputChanged) return { verdict: 'red-then-restored', file, restored, ms };
  return { verdict: 'survived', file, restored, ms, outputUnstable: !stable };
}

module.exports = { runNegControl };
