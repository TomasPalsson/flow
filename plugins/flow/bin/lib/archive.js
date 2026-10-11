'use strict';

// archive.js — `flow archive [<slug>]`: move a shipped, merged feature to
// .specs/archive/<YYYY-MM-DD>-<NNN-slug> with the guards a hand-typed
// `git mv` lacks. `git mv` into a directory that already exists nests the
// source inside it, which hides the feature from the archive/*/ globs the
// spec skill and the stealth hooks read; a resumed archive can also stack a
// second date prefix. The target is computed once, refused when it exists,
// and checked afterwards for TASKS.md at depth 1.
//
// Under stealth .specs is a link into the store repo, so the move is a plain
// rename there (git mv would address the wrong repo); the store commit stays
// with the caller, as the next skill's Stealth section says.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveFeature, featureDirs } = require('./router.js');

const DATED = /^\d{4}-\d{2}-\d{2}-/;

function fail(stderr, msg, fix) {
  stderr.write(`flow archive: ${msg}\n  fix: ${fix}\n`);
  return 1;
}

function isDir(p) {
  try { return fs.statSync(p).isDirectory(); } catch { return false; }
}

function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function gitOut(root, args) {
  const r = spawnSync('git', ['-C', root].concat(args), { encoding: 'utf8', timeout: 15000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

// sourceName(root, want, env) -> { name } | { why }
function sourceName(root, want, env) {
  const specsDir = path.join(root, '.specs');
  if (want) {
    if (want === 'archive' || want.indexOf('/') !== -1 || want === '.' || want === '..') {
      return { why: `"${want}" is not a feature directory name` };
    }
    if (isDir(path.join(specsDir, want))) return { name: want };
    const found = featureDirs(specsDir);
    const hit = (found.dirs || []).find((d) => d.slice(4) === want);
    if (hit) return { name: hit };
    return { why: `no .specs/${want}/ to archive${archivedHint(specsDir, want)}` };
  }
  let branch = '';
  const b = gitOut(root, ['rev-parse', '--abbrev-ref', 'HEAD']);
  if (b.ok) branch = b.out;
  const resolved = resolveFeature(root, branch, env);
  if (resolved.slug) return { name: resolved.slug };
  return { why: 'no active feature to archive' };
}

function archivedHint(specsDir, want) {
  let entries = [];
  try { entries = fs.readdirSync(path.join(specsDir, 'archive')); } catch { return ''; }
  const hit = entries.find((e) => e === want || e.endsWith(`-${want}`));
  return hit ? ` (already archived as .specs/archive/${hit})` : '';
}

// record(...) — the LEDGER line, then the optional spec-merge.
function record(root, name, targetName, target, io) {
  const { stdout, stderr } = io;
  const head = gitOut(root, ['rev-parse', '--short', 'HEAD']);
  const ledger = path.join(root, '.specs', 'LEDGER.md');
  let prefix = '';
  try {
    const cur = fs.readFileSync(ledger, 'utf8');
    if (cur !== '' && !cur.endsWith('\n')) prefix = '\n';
  } catch { /* no ledger yet: the append creates it */ }
  fs.appendFileSync(ledger, `${prefix}- ${today()} · ${name} · merged${head.ok ? ` ${head.out}` : ''}\n`);

  stdout.write(`flow archive: .specs/${name} -> .specs/archive/${targetName}\n`);

  // spec-merge is optional: ship without it and the archive still completes.
  const merge = path.join(__dirname, '..', '..', 'scripts', 'spec-merge');
  if (fs.existsSync(merge)) {
    const m = spawnSync('python3', ['-I', merge, path.join(target, 'TASKS.md')], { cwd: root, encoding: 'utf8', timeout: 30000 });
    if (m.status !== 0) {
      const why = ((m.stderr || '') + (m.stdout || '')).trim().split('\n').slice(0, 3).join(' | ');
      stderr.write(`flow archive: archived, but spec-merge exited ${m.status === null ? 'abnormally' : m.status}: ${why}\n  fix: SPEC.md was left as it was; resolve the key collision or Spec-base: and run scripts/spec-merge by hand\n`);
    } else if ((m.stdout || '').trim()) {
      stdout.write(m.stdout);
    }
  }
}

function run(argv, root, io, env) {
  const { stdout, stderr } = io;
  const want = argv.find((a) => !a.startsWith('-'));
  const src = sourceName(root, want, env || process.env);
  if (!src.name) return fail(stderr, src.why, 'flow archive <NNN-slug> (a shipped, merged feature under .specs/)');

  const specsDir = path.join(root, '.specs');
  const srcDir = path.join(specsDir, src.name);
  if (!fs.existsSync(path.join(srcDir, 'TASKS.md'))) {
    return fail(stderr, `.specs/${src.name}/ has no TASKS.md`, 'archive only a feature directory that holds TASKS.md');
  }

  // Computed once; a slug that already carries a date prefix keeps it.
  const targetName = DATED.test(src.name) ? src.name : `${today()}-${src.name}`;
  const archiveDir = path.join(specsDir, 'archive');
  const target = path.join(archiveDir, targetName);
  if (fs.existsSync(target)) {
    return fail(stderr, `.specs/archive/${targetName} already exists; moving into it would nest the feature one level down`,
      'inspect both directories; remove or rename the stale target by hand, then re-run');
  }

  fs.mkdirSync(archiveDir, { recursive: true });
  const stealth = require('./stealth.js').detect(root);
  if (stealth.active) {
    try {
      fs.renameSync(srcDir, target);
    } catch (e) {
      return fail(stderr, `move failed (${e.code || e.message})`, 'both directories are untouched; check permissions and re-run');
    }
  } else {
    const mv = gitOut(root, ['mv', path.join('.specs', src.name), path.join('.specs', 'archive', targetName)]);
    if (!mv.ok) {
      return fail(stderr, `git mv failed: ${mv.err || 'unknown error'}`, 'the feature directory must be tracked by git; git add it, then re-run');
    }
  }

  if (!fs.existsSync(path.join(target, 'TASKS.md'))) {
    return fail(stderr, `moved, but .specs/archive/${targetName}/TASKS.md is missing`,
      'the feature landed one level too deep or lost its TASKS.md; inspect .specs/archive/ by hand');
  }

  record(root, src.name, targetName, target, io);
  return 0;
}

module.exports = { run };
