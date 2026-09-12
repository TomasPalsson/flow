'use strict';

// loop/util.js — small numeric/text/git helpers shared across the loop
// modules. No fs writes here; pure helpers only.

const crypto = require('node:crypto');
const fsSync = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// resolveOnPath(name, env) — the first executable <dir>/<name> found by
// walking env.PATH, or null. Shared by loop/driver.js (spawning `claude`)
// and eval.js (Slice 5: resolving `claude`/`socat` before it shells out).
function resolveOnPath(name, env) {
  const pathVar = (env && env.PATH) || '';
  for (const dir of pathVar.split(path.delimiter)) {
    if (!dir) continue;
    const p = path.join(dir, name);
    try {
      fsSync.accessSync(p, fsSync.constants.X_OK);
      return p;
    } catch { /* keep looking */ }
  }
  return null;
}

function toInt(v) {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : 0;
}

function toFloat(v) {
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : 0;
}

// fmtCost — a dollar amount as a short decimal (≤ 4 dp, no float noise);
// '-' stays '-'. K-E log lines and the contract's cost_usd use this.
function fmtCost(v, dp) {
  if (v === '-' || v === undefined || v === null || v === '') return '-';
  const n = parseFloat(v);
  if (!Number.isFinite(n)) return '-';
  return String(Number(n.toFixed(dp === undefined ? 4 : dp)));
}

// ensureLoopGitignore — K-A: `.claude/loop/*` ignored except LEARNINGS.md.
// Idempotent; appends only the missing lines. `flow init` writes the same
// two lines; `flow loop init` calls this so a repo that never ran `flow
// init` does not sweep loop state into its checkpoint commits.
function ensureLoopGitignore(toplevel) {
  const fs = require('node:fs');
  const path = require('node:path');
  const abs = path.join(toplevel, '.gitignore');
  const existing = fs.existsSync(abs) ? fs.readFileSync(abs, 'utf8') : '';
  const have = (line) => existing.split('\n').some((l) => l.trim() === line);
  let addition = '';
  if (!have('.claude/loop/*')) addition += '.claude/loop/*\n';
  if (!have('!.claude/loop/LEARNINGS.md')) addition += '!.claude/loop/LEARNINGS.md\n';
  if (!addition) return;
  const sep = existing && !existing.endsWith('\n') ? '\n' : '';
  fs.writeFileSync(abs, existing + sep + addition);
}

function sha1(s) {
  return crypto.createHash('sha1').update(String(s)).digest('hex');
}

function lastNLines(text, n) {
  return String(text || '').split('\n').slice(-n).join('\n');
}

function firstNLines(text, n) {
  return String(text || '').split('\n').slice(0, n).join('\n');
}

function capReason(s) {
  return s.length > 8000 ? s.slice(0, 8000) : s;
}

function slugify(goal) {
  let s = String(goal).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
  if (s.length > 40) s = s.slice(0, 40).replace(/-+$/, '');
  return s || 'loop';
}

function headSha(toplevel) {
  const r = spawnSync('git', ['-C', toplevel, 'rev-parse', 'HEAD'], { encoding: 'utf8' });
  return r.status === 0 ? (r.stdout || '').trim() : '';
}

function gitDirty(toplevel) {
  const r = spawnSync('git', ['-C', toplevel, 'status', '--porcelain'], { encoding: 'utf8' });
  return r.status === 0 && (r.stdout || '').trim() !== '';
}

function humanDuration(startIso, endIso) {
  const ms = Math.max(0, Date.parse(endIso) - Date.parse(startIso));
  const sec = Math.round(ms / 1000);
  return `${Math.floor(sec / 60)}m${sec % 60}s`;
}

module.exports = {
  toInt, toFloat, sha1, lastNLines, firstNLines, capReason, slugify, headSha, gitDirty, humanDuration, fmtCost,
  ensureLoopGitignore, resolveOnPath,
};
