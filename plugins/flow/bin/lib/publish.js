'use strict';

// publish.js — `flow publish [--dry-run]`: mirror unchecked T### tasks to
// GitHub issues. An OPTIONAL LEAF. Nothing in the pipeline ever calls it;
// GitHub is not a step, and the router never names it.

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');
const { resolveFeature } = require('./router.js');

function gh(root, args) {
  const r = spawnSync('gh', args, { cwd: root, encoding: 'utf8', timeout: 30000 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function run(argv, root, io, env) {
  const { stdout, stderr } = io;
  const dry = argv.includes('--dry-run');
  const resolved = resolveFeature(root, '', env);
  if (!resolved.slug) {
    stderr.write('flow publish: no active feature\n  fix: flow use <NNN-slug>\n');
    return 1;
  }
  const tasksPath = path.join(root, '.specs', resolved.slug, 'TASKS.md');
  let raw;
  try {
    raw = fs.readFileSync(tasksPath, 'utf8');
  } catch {
    stderr.write(`flow publish: no ${tasksPath}\n  fix: there is nothing to mirror until TASKS.md exists\n`);
    return 1;
  }
  const open = [];
  for (const line of raw.split('\n')) {
    const m = line.replace(/\r$/, '').match(/^- \[ \] (T\d{3})(?: \[P\])? (.+?)(?: — files:| — verify:|$)/);
    if (m) open.push({ id: m[1], title: `${m[1]} ${m[2].trim()}` });
  }
  if (!open.length) {
    stdout.write(`flow publish: nothing open in ${resolved.slug}\n`);
    return 0;
  }
  if (dry) {
    for (const t of open) stdout.write(`would create: ${t.title}\n`);
    return 0;
  }
  const existing = gh(root, ['issue', 'list', '--state', 'all', '--limit', '400', '--json', 'title', '-q', '.[].title']);
  if (!existing.ok) {
    stderr.write(`flow publish: gh issue list failed (${existing.err.split('\n')[0] || 'is gh installed and authenticated?'})\n  fix: gh auth login, or run with --dry-run to see what would be created\n`);
    return 1;
  }
  const have = new Set(existing.out.split('\n').map((s) => s.trim()).filter(Boolean));
  let made = 0;
  for (const t of open) {
    if (have.has(t.title)) continue; // idempotent by title
    const r = gh(root, ['issue', 'create', '--title', t.title, '--body', `From \`.specs/${resolved.slug}/TASKS.md\`. The build does not read this issue; \`flow next\` does.`]);
    if (!r.ok) {
      stderr.write(`flow publish: gh issue create failed for ${t.id} (${r.err.split('\n')[0]})\n`);
      return 1;
    }
    made++;
  }
  stdout.write(`flow publish: ${made} created, ${open.length - made} already there (${resolved.slug})\n`);
  return 0;
}

module.exports = { run };
