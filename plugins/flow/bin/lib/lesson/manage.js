'use strict';

// lesson/manage.js — D-6 `list`, `undo`, `off`, `on`, `stale`: everything that
// reads or retires a lesson once it is locked. A lesson you cannot find and
// remove is a guardrail nobody will keep.

const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { isSlug } = require('./decide.js');
const store = require('./store.js');

const COLS = ['slug', 'rung', 'action', 'created', 'hits', 'enabled'];

function ruleMeta(sc, slug) {
  return store.parseRule(store.read(store.ruleFile(sc, slug)));
}

// Index entries first (they know the rung and the note/test files), then any
// rule file written by hand — `list` must never hide a rule that is live.
function rows(sc) {
  const index = store.readIndex(sc);
  const out = index.map((e) => {
    const meta = e.wrote === 'rule' ? ruleMeta(sc, e.slug) : null;
    return {
      slug: e.slug,
      rung: e.rung,
      action: e.action,
      created: e.created,
      hits: meta ? meta.hits || '0' : '-',
      enabled: e.wrote !== 'rule' ? 'true' : meta ? meta.enabled || 'true' : 'missing',
    };
  });
  const known = index.map((e) => e.slug);
  for (const slug of store.ruleSlugs(sc)) {
    if (known.indexOf(slug) >= 0) continue;
    const meta = ruleMeta(sc, slug) || {};
    out.push({ slug, rung: 'rule', action: meta.action || '?', created: meta.created || '-', hits: meta.hits || '0', enabled: meta.enabled || 'true' });
  }
  return out.sort((a, b) => (a.slug < b.slug ? -1 : 1));
}

function list(flags, root, io, env) {
  const sc = store.scope(root, flags.global, env);
  const all = rows(sc);
  if (!all.length) {
    io.stdout.write('flow lesson: no lessons locked yet\n  fix: /lesson after the next correction, or flow lesson propose --did … --should … --input …\n');
    return 0;
  }
  const width = COLS.map((c) => Math.max(c.length, ...all.map((r) => String(r[c]).length)));
  const line = (vals) => vals.map((v, i) => String(v).padEnd(width[i])).join('  ').replace(/\s+$/, '');
  io.stdout.write(`${[line(COLS)].concat(all.map((r) => line(COLS.map((c) => r[c])))).join('\n')}\n`);
  return 0;
}

// undo, off and on all take a slug from argv and turn it into a path under the
// store, so they all come through here first: a slug that is not the shape
// slugify produces (`../../elsewhere/notes`, an absolute path) addresses a file
// this command was never meant to delete or rewrite, and is refused.
function resolve(args, flags, root, io, env, cmd) {
  const slug = args[0];
  if (slug && isSlug(slug)) return { slug, sc: store.scope(root, flags.global, env) };
  io.stderr.write(
    slug
      ? `flow lesson ${cmd}: '${slug}' is not a lesson slug — kebab-case, as flow lesson list prints it\n  fix: flow lesson list\n`
      : `flow lesson ${cmd}: which lesson?\n  fix: flow lesson list\n`
  );
  return null;
}

function entryFor(sc, slug) {
  const hit = store.readIndex(sc).find((e) => e.slug === slug);
  if (hit) return hit;
  const file = store.ruleFile(sc, slug);
  return store.exists(file) ? { slug, rung: 'rule', wrote: 'rule', file } : null;
}

// D-6: a test lesson is code. Name the file and stop — flow never deletes it.
function undo(args, flags, root, io, env) {
  const target = resolve(args, flags, root, io, env, 'undo');
  if (!target) return 1;
  const { slug, sc } = target;
  const entry = entryFor(sc, slug);
  if (!entry) {
    io.stderr.write(`flow lesson undo: no lesson '${slug}'\n  fix: flow lesson list\n`);
    return 1;
  }
  const shown = entry.wrote === 'test' ? path.relative(root, entry.file) : store.display(sc, entry.file || store.ruleFile(sc, slug));
  if (entry.wrote === 'test') {
    io.stdout.write(`flow: lesson ${slug} dropped — delete ${shown} yourself; flow never deletes code\n`);
  } else if (entry.wrote === 'note') {
    store.dropNote(sc, entry.file, slug);
    io.stdout.write(`flow: lesson ${slug} undone — note removed from ${shown}\n`);
  } else {
    fs.unlinkSync(entry.file || store.ruleFile(sc, slug));
    io.stdout.write(`flow: lesson ${slug} undone — ${shown} deleted\n`);
  }
  store.updateIndex(sc, (index) => index.filter((e) => e.slug !== slug));
  return 0;
}

function toggle(on, args, flags, root, io, env) {
  const target = resolve(args, flags, root, io, env, on ? 'on' : 'off');
  if (!target) return 1;
  const { slug, sc } = target;
  const file = store.ruleFile(sc, slug);
  if (!store.exists(file)) {
    io.stderr.write(`flow lesson ${on ? 'on' : 'off'}: no rule file for '${slug}'\n  fix: flow lesson list — only rule lessons can be switched\n`);
    return 1;
  }
  if (!store.setEnabled(file, on ? 'true' : 'false')) {
    io.stderr.write(`flow lesson ${on ? 'on' : 'off'}: ${store.display(sc, file)} has no enabled: key\n`);
    return 1;
  }
  io.stdout.write(`flow: lesson ${slug} is ${on ? 'on' : 'off'} (${store.display(sc, file)})\n`);
  return 0;
}

function trackedFiles(root) {
  const r = spawnSync('git', ['-C', root, 'ls-files'], { encoding: 'utf8' });
  return r.status === 0 ? (r.stdout || '').split('\n').filter(Boolean) : null;
}

function matchesNothing(meta, files) {
  if (!files || meta.tool === 'Bash') return false; // a command rule never matches a path
  try {
    const re = new RegExp(meta.pattern);
    return !files.some((f) => re.test(f));
  } catch {
    return false; // an ERE JavaScript cannot compile is not evidence of anything
  }
}

function stale(flags, root, io, env) {
  const days = flags.days === undefined ? 30 : Number(flags.days);
  if (!Number.isFinite(days) || days < 0) {
    io.stderr.write('flow lesson stale: --days takes a number of days\n');
    return 1;
  }
  const sc = store.scope(root, flags.global, env);
  const files = trackedFiles(root);
  const out = [];
  for (const slug of store.ruleSlugs(sc)) {
    const meta = ruleMeta(sc, slug);
    if (!meta) continue;
    const age = (Date.now() - Date.parse(`${meta.created}T00:00:00Z`)) / 86400000;
    const why = [];
    if (Number(meta.hits || 0) === 0 && age >= days) why.push(`0 hits since ${meta.created}`);
    if (matchesNothing(meta, files)) why.push('pattern matches nothing in the repo');
    if (why.length) out.push(`${slug}  ${why.join('; ')}`);
  }
  io.stdout.write(out.length ? `${out.join('\n')}\n` : 'flow lesson: nothing stale\n');
  return 0;
}

module.exports = { list, undo, toggle, stale };
