'use strict';

// lint.js — `flow lint [<TASKS.md>] [--json] [--waves]`, a thin pass-through
// to scripts/flow-lint so the grammar has exactly one implementation.

const { spawnSync } = require('child_process');
const { pluginScript } = require('./router.js');

function run(argv, root, io, env) {
  const script = pluginScript('flow-lint', env);
  if (!script) {
    io.stderr.write('flow lint: flow-lint is not installed beside this CLI\n  fix: reinstall the flow plugin (flow install), or run scripts/flow-lint directly\n');
    return 2;
  }
  const r = spawnSync('bash', [script].concat(argv), { cwd: root, stdio: 'inherit' });
  return r.status === null ? 2 : r.status;
}

module.exports = { run };
