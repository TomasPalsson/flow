'use strict';

// loop/reasons.js — K-J reason text: continuation (both shapes) and the
// one-time finishing block, by terminal status.

const { toInt, toFloat, lastNLines, capReason, humanDuration } = require('./util.js');

function continuationReason(front, verify, unchanged, body) {
  const lines = [
    `[flow loop] iteration ${front.iteration} of ${front.max_iterations} — goal: ${front.goal}`,
    `verifier \`${front.verify}\` exited ${verify.rc}; last lines:`,
    lastNLines(verify.output, 40),
  ];
  if (unchanged >= 1) lines.push('stall warning: no change in the last k iterations');
  lines.push(
    'Read .claude/loop/LEARNINGS.md, then make the ONE smallest change that moves the verifier. Do not claim completion; the loop checks.'
  );
  lines.push(body || '');
  return capReason(lines.join('\n'));
}

function finishReasonDone(front) {
  const n = toInt(front.iteration);
  const dur = humanDuration(front.started_at, front.finished_at);
  const cost = `$${toFloat(front.cost_usd).toFixed(2)}`;
  return (
    `[flow loop] finished: verifier passed on iteration ${n} (${dur}, ${cost}). ` +
    `Summarise \`git log --oneline ${front.base}..HEAD\`, append the final LEARNINGS entry, and end the turn.`
  );
}

function finishReasonSuspect(front) {
  return (
    `[flow loop] verifier passed but the run is SUSPECT: ${front.tamper_note || ''}. ` +
    'Do not fix this now. Report the findings and end the turn; a human decides.'
  );
}

function finishReasonStopped(front) {
  const n = toInt(front.iteration);
  return (
    `[flow loop] stopped: ${front.stop_reason} after ${n} iterations. ` +
    'Report what was attempted, what remains, and what blocked progress; do not continue working.'
  );
}

function finishReason(front) {
  if (front.status === 'done') return capReason(finishReasonDone(front));
  if (front.status === 'suspect') return capReason(finishReasonSuspect(front));
  return capReason(finishReasonStopped(front));
}

module.exports = { continuationReason, finishReason };
