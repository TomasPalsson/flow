'use strict';

// Lesson 1 — flow doctor. Per .claude/slices/2-brief.md: "Lesson 1 check:
// last command's stdout contains `flow doctor`" — this only confirms the
// right command was run, not that every doctor check comes back PASS.

module.exports = {
  number: 1,
  title: 'flow doctor — what does the deployment think of itself?',
  intro: [
    'flow doctor prints one PASS/WARN/FAIL line per deployment check it knows',
    'about, then a summary. Commands you type run in a throwaway directory:',
    'this is a scratch git repo, not a sandbox — it shares your real HOME,',
    'PATH and network, so only type commands you would run anyway.',
  ].join('\n'),
  tryIt: 'flow doctor',
  check(result) {
    return typeof result.stdout === 'string' && result.stdout.indexOf('flow doctor') !== -1;
  },
};
