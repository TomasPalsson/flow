'use strict';

// loop/log.js — K-E log line: append-only, one line per event.

const fs = require('node:fs');
const path = require('node:path');

function appendLog(toplevel, f) {
  const p = path.join(toplevel, '.claude', 'loop', 'loop.log');
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const line =
    `${new Date().toISOString()} ${f.event} iter=${f.iter} head=${f.headBefore || ''}..${f.headAfter || ''} ` +
    `verify=${f.verify} sig=${f.sig} changed=${f.changed} cost=${f.cost} dur=${f.dur}${f.note ? ` ${f.note}` : ''}`;
  fs.appendFileSync(p, `${line}\n`);
}

function lastLogLines(toplevel, n) {
  let raw = '';
  try {
    raw = fs.readFileSync(path.join(toplevel, '.claude', 'loop', 'loop.log'), 'utf8');
  } catch { /* no log yet */ }
  return raw.split('\n').filter(Boolean).slice(-n);
}

module.exports = { appendLog, lastLogLines };
