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
  const st = require('./stealth.js').detect(root);
  if (st.active) {
    stderr.write(`flow publish: stealth mode — issues would name the private tasks in public\n  fix: nothing to do; the tasks stay in ${st.store}\n`);
    return 1;
  }
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
    const m = line.replace(/\r$/, '').match(/^- \[ \] (T\d{3,})(?: \[P\])? (.+?)(?: — files:| — verify:|$)/);
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
  const existing = gh(root, ['issue', 'list', '--state', 'all', '--limit', '400', '--json', 'title,body']);
  if (!existing.ok) {
    stderr.write(`flow publish: gh issue list failed (${existing.err.split('\n')[0] || 'is gh installed and authenticated?'})\n  fix: gh auth login, or run with --dry-run to see what would be created\n`);
    return 1;
  }
  let issues = [];
  try {
    issues = JSON.parse(existing.out || '[]');
  } catch {
    stderr.write('flow publish: gh issue list returned something that is not JSON\n  fix: update gh, or run with --dry-run to see what would be created\n');
    return 1;
  }
  // Task ids restart in every feature, so the dedupe key is feature + id,
  // carried in the issue body. Issues made before markers existed name the
  // feature in their body (`.specs/<slug>/TASKS.md`) and start with the id.
  const marker = (id) => `flow:${resolved.slug}/${id}`;
  const legacy = `.specs/${resolved.slug}/TASKS.md`;
  const alreadyThere = (t) => issues.some((i) => {
    const body = String((i && i.body) || '');
    const title = String((i && i.title) || '');
    return new RegExp(marker(t.id).replace(/[.*+?^${}()|[\]\\]/g, '\\$&') + '(?!\\d)').test(body) || (body.includes(legacy) && title.startsWith(`${t.id} `));
  });
  let made = 0;
  for (const t of open) {
    if (alreadyThere(t)) continue; // idempotent by feature-scoped marker
    const body = `${marker(t.id)}\nFrom \`.specs/${resolved.slug}/TASKS.md\`. The build does not read this issue; \`flow next\` does.`;
    const r = gh(root, ['issue', 'create', '--title', t.title, '--body', body]);
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
