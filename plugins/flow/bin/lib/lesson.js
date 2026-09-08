#!/usr/bin/env node
'use strict';

// lesson.js — `flow lesson`: one mistake in, one guardrail out. See
// .specs/005-lesson-v2/spec.md (D-3, D-4, D-6) for the contracts this module
// implements and scripts/tests/test_lesson.sh for the tests it is judged by.
//
// A thin entry point (same module shape as loop.js); the logic lives in
// ./lesson/*.js — the rung decision and drafting, the store (rule files,
// notes, index, LEDGER), and the manage subcommands.

const { run } = require('./lesson/cli.js');

module.exports = { run };
