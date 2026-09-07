'use strict';

// loop/verify.js — K-D verifier run: `sh -c "<verify>"`, CI=true FLOW_LOOP=1,
// merged stdout+stderr written to verify.last, timeout -> rc 124.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { sha1, firstNLines, toInt } = require('./util.js');

// The signature of a run: cksum-equivalent (sha1) of the first 60 lines of
// output with hex hashes and timestamps/durations masked.
function signatureOf(output) {
  const masked = firstNLines(output, 60)
    .replace(/[0-9a-f]{7,40}/g, 'H')
    .replace(/[0-9]+(\.[0-9]+)?(ms|s)\b/g, 'T');
  return sha1(masked);
}

function runVerify(toplevel, verify, timeoutSec, env) {
  const t = toInt(timeoutSec) || 600;
  const r = spawnSync('sh', ['-c', verify], {
    cwd: toplevel,
    env: Object.assign({}, env, { CI: 'true', FLOW_LOOP: '1' }),
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
  try {
    fs.mkdirSync(path.join(toplevel, '.claude', 'loop'), { recursive: true });
    fs.writeFileSync(path.join(toplevel, '.claude', 'loop', 'verify.last'), output);
  } catch { /* best effort */ }
  return { rc, output, sig: signatureOf(output) };
}

module.exports = { runVerify, signatureOf };
