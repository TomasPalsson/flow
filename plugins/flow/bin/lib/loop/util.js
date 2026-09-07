'use strict';

// loop/util.js — small numeric/text/git helpers shared across the loop
// modules. No fs writes here; pure helpers only.

const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

function toInt(v) {
  const n = parseInt(v, 10);
  return Number.isFinite(n) ? n : 0;
}

function toFloat(v) {
  const n = parseFloat(v);
  return Number.isFinite(n) ? n : 0;
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

module.exports = { toInt, toFloat, sha1, lastNLines, firstNLines, capReason, slugify, headSha, gitDirty, humanDuration };
