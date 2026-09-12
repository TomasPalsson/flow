'use strict';

// loop/tamper.js — K-F tamper check: test files removed, skip/xfail added,
// gate config weakened, verifier rewritten. Changes are read from
// `git diff <base>` PLUS every untracked, non-ignored file (all of whose
// lines count as added) — a file the model never staged must not be
// invisible to the check.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { sha1, toInt } = require('./util.js');
const { LEDGER_PATH } = require('../eval/contract.js');

const SKIP_RE = /\.skip\(|\.only\(|it\.todo\(|xfail|@pytest\.mark\.skip|#\[ignore\]|t\.Skip\(/;
const STOPGATE_RE = /"?stopGate"?\s*[:=]\s*false/;
const THRESHOLD_KEY_RE = /^(max[-_A-Za-z]*|complexity|threshold)$/i;
const KV_RE = /"?([A-Za-z_][A-Za-z0-9_-]*)"?\s*[:=]\s*(-?[0-9]+)/g;
const MAX_SCAN_BYTES = 1024 * 1024;

function isTestPath(p) {
  const base = path.basename(p);
  return (
    /_test\.[^/]+$/.test(base) || /\.test\.[^/]+$/.test(base) || /\.spec\.[^/]+$/.test(base) ||
    /^test_.+\.[^/]+$/.test(base) || /(^|\/)tests\//.test(p) || /(^|\/)__tests__\//.test(p) || /(^|\/)spec\//.test(p)
  );
}

function isGateConfigPath(p) {
  const base = path.basename(p);
  return (
    p === '.claude/flow.config.json' || /^eslint\.config\./.test(base) || /^\.eslintrc/.test(base) ||
    base === 'pyproject.toml' || base === 'ruff.toml' || base === 'clippy.toml' || base === '.golangci.yml'
  );
}

function gitLines(toplevel, args) {
  const r = spawnSync('git', ['-C', toplevel, ...args], { encoding: 'utf8' });
  return (r.status === 0 ? r.stdout : '').split('\n').filter(Boolean);
}

function untrackedFiles(toplevel) {
  return gitLines(toplevel, ['ls-files', '--others', '--exclude-standard']).filter((f) => !f.startsWith('.claude/loop/'));
}

function countTestFiles(toplevel) {
  return gitLines(toplevel, ['ls-files']).concat(untrackedFiles(toplevel)).filter(isTestPath).length;
}

// Per changed file: { added: [...], removed: [...] } from a unified diff.
function changedLinesByFile(diffText) {
  const files = {};
  let current = null;
  for (const line of String(diffText || '').split('\n')) {
    const m = line.match(/^\+\+\+ b\/(.*)$/);
    if (m) { current = m[1]; files[current] = files[current] || { added: [], removed: [] }; continue; }
    if (!current) continue;
    if (line.startsWith('+') && !line.startsWith('+++')) files[current].added.push(line.slice(1));
    else if (line.startsWith('-') && !line.startsWith('---')) files[current].removed.push(line.slice(1));
  }
  return files;
}

// All changes since base: the diff for tracked files, and the whole content
// of each untracked file as added lines.
function changesSinceBase(toplevel, base) {
  const diff = base ? spawnSync('git', ['-C', toplevel, 'diff', base], { encoding: 'utf8' }) : null;
  const files = changedLinesByFile(diff && diff.status === 0 ? diff.stdout : '');
  for (const f of untrackedFiles(toplevel)) {
    const abs = path.join(toplevel, f);
    let st;
    try { st = fs.statSync(abs); } catch (_e) { continue; }
    if (!st.isFile() || st.size > MAX_SCAN_BYTES) continue;
    files[f] = { added: fs.readFileSync(abs, 'utf8').split('\n'), removed: [] };
  }
  return files;
}

function thresholdPairs(lines) {
  const out = {};
  for (const l of lines) {
    for (const m of l.matchAll(KV_RE)) if (THRESHOLD_KEY_RE.test(m[1])) out[m[1]] = m[2];
  }
  return out;
}

function gateWeakened(change) {
  if (change.added.some((l) => STOPGATE_RE.test(l))) return true;
  const before = thresholdPairs(change.removed);
  const after = thresholdPairs(change.added);
  return Object.keys(after).some((k) => k in before && before[k] !== after[k]);
}

// protectedPaths(front) -> string[]. --test-files (K-F, FR-008) names files
// or directories that must survive the loop untouched, independent of the
// isTestPath heuristic countTestFiles relies on. loop/init.js seeds the list
// with plugins/flow/evals when the repo has it.
function protectedPaths(front) {
  return String(front.protected_files || '')
    .split(',')
    .map((p) => p.trim())
    .filter(Boolean);
}

function isUnder(file, root) {
  return file === root || file.startsWith(root.endsWith('/') ? root : `${root}/`);
}

// changedPaths(toplevel, base) -> every path that differs from base, tracked
// (git diff --name-only, which reports deletions and renames too) or
// untracked-and-not-ignored. Deliberately name-based: changedLinesByFile only
// sees files with a `+++ b/` header, so it misses deletions entirely.
function changedPaths(toplevel, base) {
  const tracked = base ? gitLines(toplevel, ['diff', '--name-only', base]) : [];
  return [...new Set(tracked.concat(untrackedFiles(toplevel)))];
}

// protectedFindings(toplevel, front) -> string[]. AC-011/FR-008: an iteration
// that edits, deletes or adds anything at or under a protected path is
// suspect — not just one that makes a named path vanish. The eval ledger is
// the one exemption: `flow eval` (the verifier itself) appends a line to it on
// every run, so protecting it would flag every iteration of the very loop
// FR-008 exists to protect.
function protectedFindings(toplevel, front) {
  const roots = protectedPaths(front);
  if (!roots.length) return [];
  const findings = [];
  const gone = roots.filter((p) => !fs.existsSync(path.join(toplevel, p)));
  for (const p of gone) findings.push(`protected file removed: ${p}`);
  for (const f of changedPaths(toplevel, front.base)) {
    if (f === LEDGER_PATH || gone.includes(f)) continue;
    if (roots.some((r) => isUnder(f, r))) findings.push(`protected file changed: ${f}`);
  }
  return findings;
}

function tamperCheck(toplevel, front) {
  const findings = [];
  const initCount = toInt(front.test_files);
  const curCount = countTestFiles(toplevel);
  if (curCount < initCount) findings.push(`test files removed: ${initCount} → ${curCount}`);
  findings.push(...protectedFindings(toplevel, front));
  const changes = changesSinceBase(toplevel, front.base);
  for (const [file, change] of Object.entries(changes)) {
    if (isTestPath(file) && change.added.some((l) => SKIP_RE.test(l))) findings.push(`skip/xfail added in ${file}`);
    if (isGateConfigPath(file) && gateWeakened(change)) findings.push(`gate config weakened (${file})`);
  }
  if (front.verify_sha && sha1(front.verify || '') !== front.verify_sha) findings.push('verifier rewritten');
  return findings;
}

module.exports = { tamperCheck, countTestFiles };
