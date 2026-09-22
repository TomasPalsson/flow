'use strict';

// loop/negcontrol.js — the arming safety net (spec 010 FR-04, FR-05, FR-11):
// prove the composed verifier can go red before a loop is armed on it, by
// deliberately breaking one tracked file and re-running the same verifier.
// Never writes the contract; init.js only arms after a passing verdict.

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { runVerify, signatureOf } = require('./verify.js');

// inducedBreak — the single-file edit: truncate to empty, run by the
// control's shell only after its traps are set, so there is no instant at
// which the target is broken and nothing is armed to put it back.
const inducedBreak = ': >"$NC_FILE"';

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

// runAfterUnderTrap(toplevel, file, verify, verifyTimeoutSec, env, backupPath, mode)
// -> { rc, output, signal }. One synchronous bash owns the break, the
// verifier and the restore. The verifier runs as `& wait` in its own
// process group (`set -m`): a trap only fires between foreground commands,
// but `wait` is interruptible, so spawnSync's timeout SIGTERM and a real
// Ctrl-C (which hits this whole foreground group) both reach the trap at
// once; it kills the verifier's whole group, then the EXIT trap restores.
// The restore copies the pre-control bytes back IN PLACE, keeping inode
// and mode, and runs no git command, so `.git/index.lock` cannot block it.
// `file`, `verify` and the backup path cross into the shell only through
// `env`, never string interpolation. Node ignores SIGINT/SIGTERM only while
// spawnSync blocks, so it cannot die before the shell has restored; the
// trap reports which signal stopped the run on fd 3, where the verifier's
// own output cannot forge it.
function runAfterUnderTrap(toplevel, file, verify, verifyTimeoutSec, env, backupPath, mode) {
  const t = parseInt(verifyTimeoutSec, 10) || 600;
  const script = [
    'set -m',
    `trap 'cat "$NC_BACKUP" >"$NC_FILE"; chmod "$NC_MODE" "$NC_FILE"' EXIT`,
    "trap 'kill -KILL -$! 2>/dev/null; wait $! 2>/dev/null; echo SIGINT >&3; exit 130' INT",
    "trap 'kill -KILL -$! 2>/dev/null; wait $! 2>/dev/null; echo SIGTERM >&3; exit 143' TERM",
    inducedBreak,
    'sh -c "$NC_VERIFY" 3>&- &',
    'wait $!',
  ].join('\n');
  const ignore = () => {};
  process.on('SIGINT', ignore);
  process.on('SIGTERM', ignore);
  let r;
  try {
    r = spawnSync('bash', ['-c', script], {
      cwd: toplevel,
      env: Object.assign({}, env, {
        CI: 'true', FLOW_LOOP: '1', NC_FILE: file, NC_VERIFY: verify, NC_BACKUP: backupPath,
        NC_MODE: (mode & 0o7777).toString(8),
      }),
      stdio: ['pipe', 'pipe', 'pipe', 'pipe'],
      timeout: t * 1000,
      encoding: 'utf8',
    });
  } finally {
    process.removeListener('SIGINT', ignore);
    process.removeListener('SIGTERM', ignore);
  }
  let output = (r.stdout || '') + (r.stderr || '');
  let rc = r.status;
  let signal = null;
  if (r.error && r.error.code === 'ETIMEDOUT') {
    rc = 124;
    output += `\nverify timed out after ${t} s`;
  } else {
    // A signal that landed before bash set its traps kills bash outright.
    signal = (r.output[3] || '').trim() || (['SIGINT', 'SIGTERM'].includes(r.signal) ? r.signal : null);
    if (rc === null) rc = 1;
  }
  return { rc, output, signal };
}

// breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original)
// -> { after, restored }. FR-05: restoration happens whether the run
// "passed, failed, or was interrupted". `original` = { bytes, mode },
// captured before any verifier run. The shell's EXIT trap is the first
// restore, from a backup kept outside the repo; this direct write is the
// second — needs no git command and so no index lock either.
function breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original) {
  const backupDir = fs.mkdtempSync(path.join(os.tmpdir(), 'flow-negcontrol-'));
  const backupPath = path.join(backupDir, 'target');
  let after;
  try {
    fs.writeFileSync(backupPath, original.bytes);
    after = runAfterUnderTrap(toplevel, file, verify, verifyTimeout, env, backupPath, original.mode);
  } finally {
    try {
      fs.writeFileSync(filePath, original.bytes);
      fs.chmodSync(filePath, original.mode & 0o7777);
    } catch { /* the read-back below reports the state */ }
    fs.rmSync(backupDir, { recursive: true, force: true });
  }
  return { after, restored: matches(filePath, original) };
}

// matches(filePath, original) — same mode (file type included) and bytes.
function matches(filePath, original) {
  try {
    return fs.lstatSync(filePath).mode === original.mode && fs.readFileSync(filePath).equals(original.bytes);
  } catch {
    return false;
  }
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
  // The state FR-05 promises to return to: taken before any verifier run,
  // so a "before" run that edits the target cannot become the baseline.
  const original = { bytes: fs.readFileSync(filePath), mode: fs.lstatSync(filePath).mode };

  const before = runVerify(toplevel, verify, verifyTimeout, env);
  if (before.rc === 124) {
    return { verdict: 'timeout', file, restored: true, ms: Date.now() - start, verifierTimedOut: true };
  }
  // The verifier itself changed the target on an unbroken tree: not ours to
  // put back, and no longer the file the control would be testing.
  if (!matches(filePath, original)) throw new Error(`${file} changed during the verifier's unbroken run`);

  const { after, restored } = breakAndRerun(toplevel, filePath, file, verify, verifyTimeout, env, original);
  const ms = Date.now() - start;

  // Not-restored is the loudest case (design §2): a broken tree outranks any
  // other reading of the two verifier runs.
  if (!restored) return { verdict: 'not-restored', file, restored, ms };
  // Interrupted: the tree is back, so die of the same signal without
  // arming, as the operator asked; the exit is the fallback if it is late.
  if (after.signal) {
    process.kill(process.pid, after.signal);
    process.exit(128 + os.constants.signals[after.signal]);
  }
  if (after.rc === 124) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: true };
  if (ms > boundMs) return { verdict: 'timeout', file, restored, ms, verifierTimedOut: false };

  const rcChanged = before.rc !== after.rc;
  const stable = baseline ? signatureOf(baseline.output) === signatureOf(before.output) : false;
  const outputChanged = stable && signatureOf(before.output) !== signatureOf(after.output);
  if (rcChanged || outputChanged) return { verdict: 'red-then-restored', file, restored, ms };
  return { verdict: 'survived', file, restored, ms, outputUnstable: !stable };
}

module.exports = { runNegControl };
