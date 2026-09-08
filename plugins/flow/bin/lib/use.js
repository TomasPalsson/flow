'use strict';

// use.js — `flow use <NNN-slug>`: write .specs/.current.
// The pointer is authoritative; the completeness scan can only report (11 §6).

const fs = require('fs');
const path = require('path');
const { featureDirs, resetCount } = require('./router.js');

function run(argv, root, io) {
  const { stdout, stderr } = io;
  const want = argv.find((a) => !a.startsWith('-'));
  const specsDir = path.join(root, '.specs');
  const found = featureDirs(specsDir);
  if (found.error) {
    stderr.write(`flow use: cannot read ${specsDir} (${found.error})\n`);
    return 1;
  }
  if (!want) {
    stderr.write(`flow use: which feature?\n  fix: flow use <NNN-slug>${found.dirs.length ? ` — on disk: ${found.dirs.join(', ')}` : ' (none on disk yet; /flow:spec starts one)'}\n`);
    return 1;
  }
  const hit = found.dirs.find((d) => d === want) || found.dirs.find((d) => d.slice(4) === want);
  if (!hit) {
    stderr.write(`flow use: no .specs/${want}/\n  fix: pick one of ${found.dirs.join(', ') || '(none)'}, or run /flow:spec to start it\n`);
    return 1;
  }
  fs.mkdirSync(specsDir, { recursive: true });
  fs.writeFileSync(path.join(specsDir, '.current'), `${hit}\n`);
  resetCount(root);
  stdout.write(`flow: active feature is ${hit} (.specs/.current)\n`);
  return 0;
}

module.exports = { run };
