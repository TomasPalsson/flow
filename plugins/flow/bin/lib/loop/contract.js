'use strict';

// loop/contract.js — K-A layout + K-B loop.md contract I/O: parse, write
// (atomic), read (with corrupt detection), disarm.

const fs = require('node:fs');
const path = require('node:path');

const CONTRACT_KEY_ORDER = [
  'version', 'slug', 'goal', 'verify', 'shape', 'status', 'stop_reason', 'session_id',
  'iteration', 'max_iterations', 'max_minutes', 'max_usd', 'stall_after', 'verify_timeout',
  'permission_mode', 'model', 'max_turns', 'base', 'test_files', 'started_at', 'finished_at',
  'cost_usd', 'finish_reported',
];
const QUOTED_KEYS = new Set(['verify', 'goal', 'prompt_file']);

function contractPath(toplevel) {
  return path.join(toplevel, '.claude', 'loop', 'loop.md');
}

function formatKV(key, value) {
  if (QUOTED_KEYS.has(key)) return `${key}: ${JSON.stringify(String(value))}`;
  return `${key}: ${value}`;
}

// parseContract(text) -> { front, body }. Frontmatter is between the first
// two `---` lines, one `key: value` per line; a value beginning with `"` is
// JSON-string-unquoted (so any key can round-trip a quoted value, not only
// the three the spec requires to be quoted — verify/goal/prompt_file).
// Everything after the second `---` (skipping one blank separator line) is
// the body.
function parseContract(text) {
  const lines = String(text).split('\n');
  if (lines[0] !== '---') return { front: {}, body: text };
  const front = {};
  let i = 1;
  for (; i < lines.length; i++) {
    if (lines[i] === '---') { i++; break; }
    const idx = lines[i].indexOf(':');
    if (idx === -1) continue;
    const key = lines[i].slice(0, idx).trim();
    let val = lines[i].slice(idx + 1).trim();
    if (val.startsWith('"')) {
      try { val = JSON.parse(val); } catch { /* leave as the raw quoted text */ }
    }
    front[key] = val;
  }
  if (lines[i] === '') i++;
  return { front, body: lines.slice(i).join('\n') };
}

function serializeContract(front, body) {
  const lines = ['---'];
  const seen = new Set();
  for (const k of CONTRACT_KEY_ORDER) {
    if (!(k in front)) continue;
    seen.add(k);
    lines.push(formatKV(k, front[k]));
  }
  for (const k of Object.keys(front)) {
    if (seen.has(k)) continue;
    lines.push(formatKV(k, front[k]));
  }
  lines.push('---', '');
  const b = body || '';
  return `${lines.join('\n')}\n${b}${b.endsWith('\n') || b === '' ? '' : '\n'}`;
}

function writeContract(toplevel, front, body) {
  const p = contractPath(toplevel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const tmp = `${p}.tmp.${process.pid}`;
  fs.writeFileSync(tmp, serializeContract(front, body));
  fs.renameSync(tmp, p);
}

// A contract is corrupt when iteration/max_iterations are non-numeric or
// verify is empty (K-B). Returns the reason string, or null when clean.
function corruptReason(front) {
  if (!/^\d+$/.test(String(front.iteration || '').trim())) return `iteration is not numeric: '${front.iteration}'`;
  if (!/^\d+$/.test(String(front.max_iterations || '').trim())) {
    return `max_iterations is not numeric: '${front.max_iterations}'`;
  }
  if (!front.verify || String(front.verify).trim() === '') return 'verify is empty';
  return null;
}

function readContract(toplevel) {
  let raw;
  try {
    raw = fs.readFileSync(contractPath(toplevel), 'utf8');
  } catch {
    return null;
  }
  const { front, body } = parseContract(raw);
  return { front, body, corrupt: corruptReason(front) };
}

function disarmContract(toplevel) {
  const p = contractPath(toplevel);
  try {
    fs.renameSync(p, `${p}.corrupt`);
  } catch { /* best effort */ }
}

module.exports = { contractPath, parseContract, serializeContract, writeContract, readContract, disarmContract, corruptReason };
