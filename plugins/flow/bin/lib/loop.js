#!/usr/bin/env node
'use strict';

// loop.js — `flow loop`: run a task until a deterministic verifier passes,
// never until the model says so. See .specs/006-loop-engineering/spec.md
// (K-A..K-L) for the contracts this module implements, and
// .claude/slices/1-brief.md for the tests it is judged by (test_loop.sh).
//
// This file is a thin entry point (frozen module shape below); the actual
// logic lives in ./loop/*.js (contract I/O, verifier, tamper check,
// fingerprint, the K-H tick state machine, the K-I fresh driver and the K-C
// CLI dispatcher), split into small, single-purpose modules.

const { run } = require('./loop/cli.js');
const { parseContract } = require('./loop/contract.js');
const { tick } = require('./loop/tick.js');
const { tamperCheck } = require('./loop/tamper.js');
const { runVerify } = require('./loop/verify.js');

module.exports = { run, parseContract, tick, tamperCheck, runVerify };

if (require.main === module) {
  process.exit(run(process.argv.slice(2), process.cwd(), process.env));
}
