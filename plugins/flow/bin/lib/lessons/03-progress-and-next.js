'use strict';

// Lesson 3 — flow next. Reads PROGRESS.md's "## Now" section for a bullet
// starting with `resume:` and prints the BACKTICKED command in it as the one
// deterministic next step (FU-09: `Next:` is always something you can run).
// Check: stdout contains `Next: ` and `Why: PROGRESS.md · Now:`.

module.exports = {
  number: 3,
  title: 'flow next — one deterministic next step',
  intro: [
    'flow next never guesses: it reads PROGRESS.md\'s "## Now" section for a',
    'line starting with `resume:` and prints the backticked command in it.',
    'Prose without a backticked command is skipped — Next: is always runnable.',
  ].join('\n'),
  tryIt:
    'put "- resume: `/flow`" under "## Now" in PROGRESS.md, e.g.: ' +
    'awk \'1;/^## Now$/{print "- resume: `/flow`"}\' PROGRESS.md > p.tmp && mv p.tmp PROGRESS.md ' +
    '— then: flow next',
  check(result) {
    return result.stdout.indexOf('Next: ') !== -1 && result.stdout.indexOf('Why: PROGRESS.md · Now:') !== -1;
  },
};
