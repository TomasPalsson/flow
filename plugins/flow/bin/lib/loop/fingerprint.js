'use strict';

// loop/fingerprint.js — K-H step 7: HEAD sha + cksum(git status --porcelain)
// + cksum(git diff).

const { spawnSync } = require('node:child_process');
const { sha1, headSha } = require('./util.js');

function fingerprint(toplevel) {
  const head = headSha(toplevel);
  const status = spawnSync('git', ['-C', toplevel, 'status', '--porcelain'], { encoding: 'utf8' }).stdout || '';
  const diff = spawnSync('git', ['-C', toplevel, 'diff'], { encoding: 'utf8' }).stdout || '';
  return `${head}:${sha1(status)}:${sha1(diff)}`;
}

module.exports = { fingerprint };
