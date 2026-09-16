'use strict';

// stealth-move.js — what to do with an existing REAL DIRECTORY at
// <root>/.specs (dirState, applyPendingMove). Split out of stealth.js to
// keep that file under the size guard.

const fs = require('fs');
const path = require('path');

// A store .specs holding only its own state dotfiles (.gitignore — written
// by ensureStoreRepo itself — plus .current/.next-call-count) counts as
// empty for the move: nothing there is a spec.
const STORE_SPECS_STATE_FILES = ['.gitignore', '.current', '.next-call-count'];

// dirState -> the real-directory sub-cases of step 3: move it whole (store
// side absent/empty), clean up local state-only files (store side already
// populated), or a merge conflict (both sides hold specs).
function dirState(specsLink, store) {
  const storeSpecs = path.join(store, '.specs');
  let storeSpecsAbsent = false;
  let storeSpecsEmpty = false;
  try {
    const sst = fs.statSync(storeSpecs);
    storeSpecsEmpty = sst.isDirectory()
      && fs.readdirSync(storeSpecs).every((e) => STORE_SPECS_STATE_FILES.indexOf(e) !== -1);
  } catch { storeSpecsAbsent = true; }
  if (storeSpecsAbsent || storeSpecsEmpty) return { alreadyLinked: false, pendingMove: 'move', store };
  let entries = [];
  try { entries = fs.readdirSync(specsLink); } catch { entries = []; }
  if (!entries.every((e) => e === '.next-call-count' || e === '.current')) {
    return { error: `both ${specsLink} and ${storeSpecs} hold specs — merge them by hand, then re-run` };
  }
  return { alreadyLinked: false, pendingMove: 'clean', cleanEntries: entries, store };
}

// applyPendingMove -> null on success, else a fail message. The first
// mutation of a `flow stealth` run.
function applyPendingMove(pendingMove, cleanEntries, specsLink, store) {
  if (pendingMove === 'clean') {
    for (const e of cleanEntries) { try { fs.unlinkSync(path.join(specsLink, e)); } catch { /* gone */ } }
    try { fs.rmdirSync(specsLink); } catch { /* step 5's symlinkSync reports a real conflict */ }
    return null;
  }
  if (pendingMove !== 'move') return null;
  const storeSpecs = path.join(store, '.specs');
  let wasEmptyDir = false;
  try { wasEmptyDir = fs.statSync(storeSpecs).isDirectory(); } catch { wasEmptyDir = false; }
  if (wasEmptyDir) {
    // A dotfiles-only store side (dirState's definition of "empty") has to
    // be cleared before rmdir, which refuses a non-empty directory.
    for (const f of STORE_SPECS_STATE_FILES) { try { fs.unlinkSync(path.join(storeSpecs, f)); } catch { /* absent */ } }
    try { fs.rmdirSync(storeSpecs); } catch { /* renameSync below reports the real problem */ }
  }
  // mkdirSync AFTER the empty-side cleanup, so an EXDEV refusal below can
  // remove exactly what this call created and leave no new directory.
  const storeExisted = fs.existsSync(store);
  if (!wasEmptyDir) fs.mkdirSync(store, { recursive: true });
  try {
    fs.renameSync(specsLink, storeSpecs);
  } catch (e) {
    if (!wasEmptyDir && !storeExisted) { try { fs.rmdirSync(store); } catch { /* best-effort cleanup */ } }
    if (e.code === 'EXDEV') {
      return `cannot move ${specsLink} across devices\n  fix: mv ${specsLink} ${storeSpecs} && flow stealth ${store}`;
    }
    return `cannot move ${specsLink} to ${storeSpecs} (${e.code || e.message})\n  fix: mv ${specsLink} ${storeSpecs} && flow stealth ${store}`;
  }
  return null;
}

module.exports = { dirState, applyPendingMove };
