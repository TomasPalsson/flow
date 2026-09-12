'use strict';

// loop/tick.js — K-H state machine, both shapes; `run` (driver.js) calls
// this same function in-process for the fresh shape.

const fs = require('node:fs');
const path = require('node:path');
const { readContract, writeContract, disarmContract } = require('./contract.js');
const { runVerify } = require('./verify.js');
const { tamperCheck } = require('./tamper.js');
const { fingerprint } = require('./fingerprint.js');
const { appendLog } = require('./log.js');
const { continuationReason, finishReason } = require('./reasons.js');
const { toInt, toFloat, headSha, fmtCost } = require('./util.js');

function terminalFinish(toplevel, front, body, now) {
  if (!front.finished_at) front.finished_at = new Date(now).toISOString();
  front.finish_reported = '1';
  writeContract(toplevel, front, body);
  return { action: 'finish', reason: finishReason(front), status: front.status, iteration: toInt(front.iteration) };
}

// Rules 1-3: cases where the loop must not touch the contract at all and
// simply allows the Stop hook (or a caller) to proceed.
function tickAllowChecks(front, opts) {
  if (front.status !== 'active' && String(front.finish_reported) === '1') return true;
  if (front.shape === 'fresh' && opts.hook) return true;
  // Rule 3: a contract bound to a session yields to any other session — and
  // to an unknown one (empty --session): cannot judge → allow.
  if (front.shape === 'session' && front.session_id && (opts.session || '') !== front.session_id) return true;
  return false;
}

// Rule 7: fingerprint/stall/wedge bookkeeping. Mutates `front` with the new
// fp/sig/streak state and returns { unchanged, stopReason }.
function tickStallWedge(toplevel, front, verifySig) {
  const fp = fingerprint(toplevel);
  const prevFp = front.fp || '';
  const prevSig = front.sig || '';
  const stallAfter = toInt(front.stall_after) || 3;
  const unchanged = fp === prevFp ? toInt(front.unchanged) + 1 : 0;
  let stopReason = null;
  let wedgeStreak = toInt(front.wedge_streak);
  if (fp !== prevFp && verifySig === prevSig) {
    wedgeStreak += 1;
    if (wedgeStreak >= stallAfter) stopReason = 'wedge';
  } else {
    wedgeStreak = 0;
  }
  if (unchanged >= stallAfter) stopReason = stopReason || 'stall';
  front.fp = fp;
  front.sig = verifySig;
  front.unchanged = String(unchanged);
  front.wedge_streak = String(wedgeStreak);
  return { unchanged, stopReason };
}

// Rule 8: caps (cap/time/budget), checked only when rule 7 found no reason.
function tickCapReason(front, now) {
  if (toInt(front.iteration) >= toInt(front.max_iterations)) return 'cap';
  const maxMinutes = toInt(front.max_minutes);
  if (maxMinutes > 0 && (now - Date.parse(front.started_at)) / 60000 >= maxMinutes) return 'time';
  const maxUsd = toFloat(front.max_usd);
  if (maxUsd > 0 && toFloat(front.cost_usd) >= maxUsd) return 'budget';
  return null;
}

function logEvent(toplevel, front, event, verify, changed, note) {
  appendLog(toplevel, {
    event,
    iter: front.iteration,
    headBefore: front.base,
    headAfter: headSha(toplevel),
    verify: verify ? verify.rc : '-',
    sig: verify ? verify.sig : '-',
    changed: changed ? 1 : 0,
    cost: fmtCost(front.cost_usd),
    dur: '-',
    note,
  });
}

// The fail path (K-H rules 7-9): stall/wedge detection, then caps, then
// either a terminal `stopped` or a `continue`.
function tickFailPath(toplevel, front, body, verify, now) {
  const { unchanged, stopReason: stallStopReason } = tickStallWedge(toplevel, front, verify.sig);
  front.iteration = String(toInt(front.iteration) + 1);
  const stopReason = stallStopReason || tickCapReason(front, now);
  if (stopReason) {
    front.status = 'stopped';
    front.stop_reason = stopReason;
    logEvent(toplevel, front, 'stop', verify, true, stopReason);
    return terminalFinish(toplevel, front, body, now);
  }
  logEvent(toplevel, front, 'iter', verify, true, '');
  writeContract(toplevel, front, body);
  return {
    action: 'continue',
    reason: continuationReason(front, verify, unchanged, body),
    status: front.status,
    iteration: toInt(front.iteration),
  };
}

// Rule 6: run check. pass/suspect end the run right here (no iteration
// bump — K-I: "an already-green goal ends at iteration 0"); fail falls
// through to the stall/wedge/cap path.
function tickCheckPath(toplevel, front, body, now, env) {
  const verify = runVerify(toplevel, front.verify, front.verify_timeout, env);
  const tamper = tamperCheck(toplevel, front, env);
  const verdict = verify.rc === 0 ? (tamper.length ? 'suspect' : 'pass') : 'fail';
  if (verdict === 'fail') return tickFailPath(toplevel, front, body, verify, now);
  front.status = verdict === 'pass' ? 'done' : 'suspect';
  if (verdict === 'suspect') front.tamper_note = tamper.join('; ');
  logEvent(toplevel, front, front.status, verify, true, tamper.join('; '));
  return terminalFinish(toplevel, front, body, now);
}

function tickBlockedCheck(toplevel, front, body, now) {
  const blockedPath = path.join(toplevel, '.claude', 'loop', 'BLOCKED.md');
  if (!fs.existsSync(blockedPath)) return null;
  front.status = 'stopped';
  front.stop_reason = 'blocked';
  logEvent(toplevel, front, 'stop', null, false, 'blocked');
  return terminalFinish(toplevel, front, body, now);
}

function tick(toplevel, opts) {
  opts = opts || {};
  const now = opts.now || Date.now();
  const contract = readContract(toplevel);
  if (!contract) return { action: 'allow', reason: '', status: null, iteration: 0 };
  const front = contract.front;
  if (contract.corrupt) {
    disarmContract(toplevel);
    return { action: 'allow', reason: `corrupt contract: ${contract.corrupt}`, status: null, iteration: toInt(front.iteration) };
  }
  if (tickAllowChecks(front, opts)) {
    return { action: 'allow', reason: '', status: front.status, iteration: toInt(front.iteration) };
  }
  if (['done', 'suspect', 'stopped'].includes(front.status) && String(front.finish_reported) !== '1') {
    return terminalFinish(toplevel, front, contract.body, now);
  }
  const blocked = tickBlockedCheck(toplevel, front, contract.body, now);
  if (blocked) return blocked;
  return tickCheckPath(toplevel, front, contract.body, now, opts.env || process.env);
}

module.exports = { tick };
