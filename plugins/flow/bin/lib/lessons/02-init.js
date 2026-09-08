'use strict';

const fs = require('node:fs');
const path = require('node:path');

// Lesson 2 — flow init. Checks the three files flow init writes
// unconditionally, regardless of detected stack: REVIEW.md, PROGRESS.md and
// .claude/flow.config.json. This sandbox has no package.json/pyproject.toml/
// Cargo.toml/go.mod, so no stack is detected and the stack-specific files
// (CI gate, lint thresholds, CLAUDE.md) are skipped — see
// .claude/slices/2-brief.md: "Lesson 2 check: the three files exist."

const REQUIRED_FILES = ['REVIEW.md', 'PROGRESS.md', path.join('.claude', 'flow.config.json')];

module.exports = {
  number: 2,
  title: 'flow init — scaffold the governance files',
  intro: [
    'flow init always writes REVIEW.md, PROGRESS.md and .claude/flow.config.json;',
    'a CI gate and lint thresholds only follow when it can detect a stack (this',
    'scratch repo has none, so it skips them).',
  ].join('\n'),
  tryIt: 'flow init',
  check(result, ctx) {
    return REQUIRED_FILES.every((rel) => fs.existsSync(path.join(ctx.sandboxDir, rel)));
  },
};
