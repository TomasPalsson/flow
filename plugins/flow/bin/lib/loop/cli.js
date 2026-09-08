'use strict';

// loop/cli.js — `flow loop` dispatcher (K-C). All commands anchor at
// `git rev-parse --show-toplevel`.

const { spawnSync } = require('node:child_process');
const { printTopHelp, printSubHelp } = require('./help.js');
const { cmdInit } = require('./init.js');
const { cmdCheck } = require('./check.js');
const { cmdTick } = require('./tickcmd.js');
const { cmdRun } = require('./driver.js');
const { cmdStatus, cmdStop, cmdLog } = require('./status.js');

const SUBCOMMANDS = { init: cmdInit, check: cmdCheck, tick: cmdTick, run: cmdRun, status: cmdStatus, stop: cmdStop, log: cmdLog };

function gitToplevel(cwd, env) {
  const r = spawnSync('git', ['-C', cwd, 'rev-parse', '--show-toplevel'], { encoding: 'utf8', env });
  return r.status === 0 ? (r.stdout || '').trim() : null;
}

function run(argv, cwd, env) {
  env = env || process.env;
  if (argv.length === 0 || argv[0] === '--help' || argv[0] === '-h') {
    printTopHelp();
    return 0;
  }
  const cmd = argv[0];
  const rest = argv.slice(1);
  if (rest.includes('--help') || rest.includes('-h')) {
    printSubHelp(SUBCOMMANDS[cmd] ? cmd : 'init');
    return 0;
  }
  if (!SUBCOMMANDS[cmd]) {
    process.stderr.write(`flow loop: unknown subcommand '${cmd}'\n`);
    printTopHelp();
    return 1;
  }
  const toplevel = gitToplevel(cwd, env);
  if (!toplevel) {
    process.stderr.write('flow loop: not a git repository\n');
    return 1;
  }
  if (cmd === 'status' || cmd === 'stop' || cmd === 'log') return SUBCOMMANDS[cmd](rest, toplevel);
  return SUBCOMMANDS[cmd](rest, toplevel, env);
}

module.exports = { run };
