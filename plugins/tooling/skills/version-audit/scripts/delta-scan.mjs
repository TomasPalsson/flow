#!/usr/bin/env node
// delta-scan.mjs - intersect a version pair's known breaking changes with what a repo uses.
// Node built-ins only. Read-only and advisory: always exits 0 (2 on bad arguments).
//
//   node delta-scan.mjs <repo> --rules <rules.json> [--ran "<codemod name>"]... [--runnable "<codemod name>"]... [--json]
//
// rules.json is written by the caller from the changelog and migration guide of the version pair:
//   [{"id":"D1","name":"cookies() is async","pattern":"\\bcookies\\(\\)",
//     "include":["*.ts","*.tsx"],"codemod":{"name":"@next/codemod next-async-request-api"}}]
// Each rule becomes one row:
//   confirmed   a hit in executable code, listed as file:line (this is the delta catalog)
//   wrong-site  hits only on comment lines; not a delta, listed so it is not rediscovered
//   not-hit     no hit; reported apart from the catalog, never as a catalog row
// A rule's codemod is "present, not run" unless the caller passes --runnable <name> (it can load the
// project here) or --ran <name> (after really running it).
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const take = (n) => { const out = []; for (let i = 0; i < args.length;) { if (args[i] === n) { out.push(args[i + 1]); args.splice(i, 2); } else i++; } return out; };
const rulesPath = take('--rules')[0];
const ran = new Set(take('--ran'));
const runnable = new Set(take('--runnable'));
const json = args.includes('--json');
const repo = args.filter((a) => a !== '--json')[0];
if (!repo || !rulesPath || !fs.existsSync(repo) || !fs.existsSync(rulesPath)) {
  console.error('usage: delta-scan.mjs <repo> --rules <rules.json> [--ran "<codemod>"]... [--runnable "<codemod>"]... [--json]');
  process.exit(2);
}
const rules = JSON.parse(fs.readFileSync(rulesPath, 'utf8'));
const root = path.resolve(repo);
const SKIP = new Set(['node_modules', '.git', '.next', 'dist', 'build', 'coverage', '.venv', '__pycache__', 'target']);
const COMMENT = /^\s*(?:\/\/|#|\*|\/\*|<!--)/;
const glob = (g) => new RegExp(`^${g.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`);

function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { if (!SKIP.has(e.name)) yield* walk(path.join(dir, e.name)); }
    else if (e.isFile()) yield path.join(dir, e.name);
  }
}
const files = [...walk(root)].map((f) => ({ f, rel: path.relative(root, f) }));
const cache = new Map();
const linesOf = (f) => {
  if (!cache.has(f)) { try { cache.set(f, fs.statSync(f).size > 1_000_000 ? [] : fs.readFileSync(f, 'utf8').split('\n')); } catch { cache.set(f, []); } }
  return cache.get(f);
};

const rows = rules.map((r) => {
  const re = new RegExp(r.pattern);
  const inc = (r.include || ['*']).map(glob);
  const found = [];
  for (const { f, rel } of files) {
    if (!inc.some((g) => g.test(path.basename(rel)))) continue;
    linesOf(f).forEach((line, i) => {
      if (re.test(line)) found.push({ file: rel, line: i + 1, text: line.trim().slice(0, 100), site: COMMENT.test(line) ? 'wrong-site' : 'confirmed' });
    });
  }
  const real = found.filter((h) => h.site === 'confirmed');
  const state = real.length ? 'confirmed' : found.length ? 'wrong-site' : 'not-hit';
  const codemod = r.codemod ? { name: r.codemod.name, state: ran.has(r.codemod.name) ? 'ran' : runnable.has(r.codemod.name) ? 'runnable here, not run' : 'present, not run' } : null;
  return { id: r.id, name: r.name, state, hits: found, codemod };
});

if (json) { console.log(JSON.stringify({ rows }, null, 2)); process.exit(0); }
console.log('Delta catalog (this code hits these):');
for (const r of rows.filter((x) => x.state !== 'not-hit')) {
  for (const h of r.hits) console.log(`${r.id} ${h.site} ${h.file}:${h.line} ${r.name}`);
  if (r.codemod) console.log(`${r.id} codemod ${r.codemod.state} (${r.codemod.name})`);
}
console.log('Not hit (kept out of the catalog):');
for (const r of rows.filter((x) => x.state === 'not-hit')) console.log(`${r.id} not-hit ${r.name}`);
