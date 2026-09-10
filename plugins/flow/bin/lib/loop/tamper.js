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

// UI_ENV_VARS — ui-verify.sh's entire boot config (SERVE/PORT/HEALTH/BOOT/
// BASE_URL/FLOW_UI_SCORE) is `${VAR:-default}`, fully caller-overridable,
// and none of it is covered by target_sha/verify_sha (those only hash file
// bytes). Without freezing it too, overriding SERVE alone at check/tick
// time re-points the loop's re-verification at a different process (e.g. a
// pre-baked static fixture) while every hashed file stays untouched.
const UI_ENV_VARS = ['SERVE', 'PORT', 'HEALTH', 'BOOT', 'BASE_URL', 'FLOW_UI_SCORE'];

function envSha(env) {
  return sha1(UI_ENV_VARS.map((k) => `${k}=${(env || {})[k] || ''}`).join('\n'));
}

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
  const deleted = new Set(gitLines(toplevel, ['ls-files', '--deleted']));
  return gitLines(toplevel, ['ls-files']).filter((f) => !deleted.has(f))
    .concat(untrackedFiles(toplevel)).filter(isTestPath).length;
}

// walkFiles — every regular file under `dir`, as paths relative to `base`.
// Returns null when `dir` cannot be read (missing/not-a-dir), so the caller
// can tell "target deleted" apart from "target is empty".
function walkFiles(dir, base) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return null;
  }
  let out = [];
  for (const e of entries) {
    const abs = path.join(dir, e.name);
    if (e.isDirectory()) {
      const sub = walkFiles(abs, base);
      if (sub === null) return null;
      out = out.concat(sub);
    } else if (e.isFile()) {
      out.push(path.relative(base, abs));
    }
  }
  return out;
}

// targetSha — sha1 over sorted "sha1(base64 bytes)\0relpath" lines for every
// file under `target` plus each existing path in `extraPaths`. 'MISSING'
// when `target` cannot be walked (so deleting it is itself a finding).
function targetSha(toplevel, target, extraPaths) {
  let lines = [];
  if (target) {
    const abs = path.join(toplevel, target);
    const files = walkFiles(abs, abs);
    if (files === null) return 'MISSING';
    lines = files.map((rel) => `${sha1(fs.readFileSync(path.join(abs, rel)).toString('base64'))}\0${rel}`);
  }
  for (const p of extraPaths || []) {
    if (!p) continue;
    const full = path.isAbsolute(p) ? p : path.join(toplevel, p);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    if (!st.isFile()) continue;
    lines.push(`${sha1(fs.readFileSync(full).toString('base64'))}\0${p}`);
  }
  if (!lines.length) return '';
  lines.sort();
  return sha1(lines.join('\n'));
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

function tamperCheck(toplevel, front, env) {
  const findings = [];
  // Scoped to --target (a UI loop): a plain non-UI loop never records
  // env_sha, so a coincidental SERVE/PORT in someone's shell never marks an
  // unrelated loop suspect (same scoping target_script already uses).
  if (front.target && front.env_sha && envSha(env || process.env) !== front.env_sha) {
    findings.push(`ui-verify env overridden since init (${UI_ENV_VARS.join('/')})`);
  }
  const initCount = toInt(front.test_files);
  const curCount = countTestFiles(toplevel);
  if (curCount < initCount) findings.push(`test files removed: ${initCount} → ${curCount}`);
  const changes = changesSinceBase(toplevel, front.base);
  for (const [file, change] of Object.entries(changes)) {
    if (isTestPath(file) && change.added.some((l) => SKIP_RE.test(l))) findings.push(`skip/xfail added in ${file}`);
    if (isGateConfigPath(file) && gateWeakened(change)) findings.push(`gate config weakened (${file})`);
  }
  if (front.verify_sha && sha1(front.verify || '') !== front.verify_sha) findings.push('verifier rewritten');
  const extraPaths = [front.target_script, ...String(front.verify_script || '').split(/\s+/)];
  if (front.target_sha && targetSha(toplevel, front.target, extraPaths) !== front.target_sha) {
    const changed = [front.target, front.verify_script].filter(Boolean).join(', ');
    findings.push(`guarded files changed: ${changed}`);
  }
  return findings;
}

module.exports = { tamperCheck, countTestFiles, targetSha, envSha, UI_ENV_VARS };
