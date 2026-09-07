'use strict';

// loop/tamper.js — K-F tamper check: test files removed, skip/xfail added,
// gate config weakened, verifier rewritten.

const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { sha1, toInt } = require('./util.js');

const TEST_PATH_SPECS = ['*_test.*', '*.test.*', '*.spec.*', 'test_*.*', 'tests/', '__tests__/', 'spec/'];
const SKIP_RE = /\.skip\(|\.only\(|it\.todo\(|xfail|@pytest\.mark\.skip|#\[ignore\]|t\.Skip\(/;
const STOPGATE_RE = /"?stopGate"?\s*[:=]\s*false/;

function isTestPath(p) {
  const base = path.basename(p);
  return (
    /_test\.[^/]+$/.test(base) ||
    /\.test\.[^/]+$/.test(base) ||
    /\.spec\.[^/]+$/.test(base) ||
    /^test_.+\.[^/]+$/.test(base) ||
    /(^|\/)tests\//.test(p) ||
    /(^|\/)__tests__\//.test(p) ||
    /(^|\/)spec\//.test(p)
  );
}

function countTestFiles(toplevel) {
  const tracked = spawnSync('git', ['-C', toplevel, 'ls-files'], { encoding: 'utf8' });
  const untracked = spawnSync('git', ['-C', toplevel, 'ls-files', '--others', '--exclude-standard'], { encoding: 'utf8' });
  const all = `${tracked.stdout || ''}\n${untracked.stdout || ''}`.split('\n').filter(Boolean);
  return all.filter(isTestPath).length;
}

// Maps each changed file (from a unified diff's `+++ b/<file>` headers) to
// its added (`+`, not `+++`) lines.
function addedLinesByFile(diffText) {
  const files = {};
  let current = null;
  for (const line of String(diffText || '').split('\n')) {
    const m = line.match(/^\+\+\+ b\/(.*)$/);
    if (m) {
      current = m[1];
      if (!files[current]) files[current] = [];
      continue;
    }
    if (current && line.startsWith('+') && !line.startsWith('+++')) files[current].push(line.slice(1));
  }
  return files;
}

function tamperTestFileFindings(toplevel, front) {
  const findings = [];
  const initCount = toInt(front.test_files);
  const curCount = countTestFiles(toplevel);
  if (curCount < initCount) findings.push(`test files removed: ${initCount} → ${curCount}`);
  if (!front.base) return findings;
  const diffTests = spawnSync('git', ['-C', toplevel, 'diff', front.base, '--', ...TEST_PATH_SPECS], { encoding: 'utf8' });
  const byFile = addedLinesByFile(diffTests.status === 0 ? diffTests.stdout : '');
  for (const [file, lines] of Object.entries(byFile)) {
    if (lines.some((l) => SKIP_RE.test(l))) findings.push(`skip/xfail added in ${file}`);
  }
  return findings;
}

function tamperGateAndVerifierFindings(toplevel, front) {
  const findings = [];
  if (front.base) {
    const diffAll = spawnSync('git', ['-C', toplevel, 'diff', front.base], { encoding: 'utf8' });
    const byFile = addedLinesByFile(diffAll.status === 0 ? diffAll.stdout : '');
    const allAdded = Object.values(byFile).flat();
    if (allAdded.some((l) => STOPGATE_RE.test(l))) findings.push('gate config weakened');
  }
  if (front.verify_sha && sha1(front.verify || '') !== front.verify_sha) findings.push('verifier rewritten');
  return findings;
}

function tamperCheck(toplevel, front) {
  return [...tamperTestFileFindings(toplevel, front), ...tamperGateAndVerifierFindings(toplevel, front)];
}

module.exports = { tamperCheck, countTestFiles };
