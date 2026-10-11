'use strict';

// eval/graders.js — a hash per eval case over what grades it, so `flow eval
// --history` can tell a grader edit from a skill edit. The bytes are case.yaml
// followed by postcheck.sh (when present); scripts/case-selfcheck hashes the
// same bytes for its own ledger lines.
//
// Credit: adapted from vercel-labs/agent-skills vercel-optimize/lib/gates/index.mjs @ 063bee9 (MIT).

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

function graderHash(caseDir) {
  const h = crypto.createHash('sha256');
  let any = false;
  for (const f of ['case.yaml', 'postcheck.sh']) {
    try {
      h.update(fs.readFileSync(path.join(caseDir, f)));
      any = true;
    } catch { /* an absent file contributes nothing */ }
  }
  return any ? h.digest('hex') : null;
}

// graderHashes(toplevel, evalsRoot, names) -> {<case>: <hash>} for the cases that have a dir.
function graderHashes(toplevel, evalsRoot, names) {
  const out = {};
  for (const name of [...new Set(names)].sort()) {
    const hash = graderHash(path.join(toplevel, evalsRoot, name));
    if (hash) out[name] = hash;
  }
  return out;
}

// changedGraders(prev, cur) -> case names present in both whose hash differs.
function changedGraders(prev, cur) {
  const isMap = (m) => m && typeof m === 'object' && !Array.isArray(m);
  if (!isMap(prev) || !isMap(cur)) return [];
  return Object.keys(cur).filter((k) => k in prev && prev[k] !== cur[k]).sort();
}

module.exports = { graderHash, graderHashes, changedGraders };
