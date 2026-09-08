'use strict';

// Lesson 3 — flow next. Spec 004 K-C: the router recomputes its answer from
// .specs/ and git on every call, so /clear, a crash or a compaction all
// self-heal. Nothing is remembered, and PROGRESS.md is never consulted.
// Check: stdout names the drafting state's runnable answer and its /clear.

module.exports = {
  number: 3,
  title: 'flow next — one deterministic next step',
  intro: [
    'flow next never guesses and never remembers: it recomputes one answer',
    'from .specs/ and git every time you ask. Point .specs/.current at a',
    'feature and the answer changes — with no session, no state file, and no',
    'PROGRESS.md in the loop. Every turn that ends in work ends with a /clear.',
  ].join('\n'),
  tryIt:
    'give it a feature to route to, e.g.: '
    + 'mkdir -p .specs/001-hello && printf \'# Spec\\n\' > .specs/001-hello/spec.md '
    + '&& flow use 001-hello && flow next',
  check(result) {
    return result.stdout.indexOf('Next: /flow:next') !== -1
      && result.stdout.indexOf('Then: /clear') !== -1;
  },
};
