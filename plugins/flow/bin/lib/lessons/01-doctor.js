'use strict';

// Lesson 1 — flow doctor. Per .claude/slices/2-brief.md: "Lesson 1 check:
// last command's stdout contains `flow doctor`" — this only confirms the
// right command was run, not that every doctor check comes back PASS.

module.exports = {
  number: 1,
  title: 'flow doctor — what does the deployment think of itself?',
  intro: [
    'flow doctor prints one PASS/WARN/FAIL line per deployment check it knows',
    'about, then a summary. Nothing here can touch your real machine — this',
    'shell runs inside a disposable sandbox.',
  ].join('\n'),
  tryIt: 'flow doctor',
  check(result) {
    return typeof result.stdout === 'string' && result.stdout.indexOf('flow doctor') !== -1;
  },
};
