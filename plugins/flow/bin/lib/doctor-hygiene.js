'use strict';
// doctor-hygiene.js — three WARN-only `flow doctor` checks for repo rot that
// no gate catches: worktrees nobody removed, personal absolute paths in
// shipped files, and reference docs that drifted from the files they list.
// Each check pushes PASS or WARN rows through doctor's own push(id, status,
// detail); none ever pushes FAIL, removes anything or rewrites a file.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// The marketplace repo root, from plugins/flow/bin/lib/.
const REPO_ROOT = path.resolve(__dirname, '..', '..', '..', '..');

function worktreeHygieneCheck(push, cwd) {}

function personalPathsCheck(push, repoRoot) {}

function referenceDocsCheck(push, repoRoot) {}

module.exports = { REPO_ROOT, worktreeHygieneCheck, personalPathsCheck, referenceDocsCheck };
