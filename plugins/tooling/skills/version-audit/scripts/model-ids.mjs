#!/usr/bin/env node
// model-ids.mjs - inventory Claude model IDs in a repo and classify each hit.
// Node built-ins only. Advisory: always exits 0 unless the path is unreadable (2).
//
//   node model-ids.mjs [path] [--catalog <file>] [--json]
//
// --catalog is the LIVE list, fetched by the caller (never a copy kept in this skill):
//   aws bedrock list-foundation-models --region us-east-1 --by-provider anthropic \
//     --query 'modelSummaries[].[modelId,modelLifecycle.status]' --output text > catalog.txt
// Write it outside the scanned tree (the file itself is skipped if it is inside). Plain IDs count as current. Add a status word after an ID (active, legacy, deprecated,
// retired; Bedrock's ACTIVE/LEGACY lifecycle words work) and optionally a date: "claude-3-5-sonnet-20241022 retired 2025-10-28".
// Without --catalog every ID is reported "unverified", never "current".
//
// Output: sync markers first, then one line per hit:
//   <file>:<line> <status> <bucket> <id> [(date)]
//   <file>:<line> gate add-alongside <partial id>
// status: current | legacy | deprecated | retired | unknown | unverified
// bucket: caller | definer | opaque | suffixed
import fs from 'node:fs';
import path from 'node:path';

const args = process.argv.slice(2);
const flag = (n) => { const i = args.indexOf(n); return i < 0 ? null : args.splice(i, 2)[1]; };
const json = args.includes('--json');
const catalogPath = flag('--catalog');
const root = path.resolve(args.filter((a) => a !== '--json')[0] || '.');
if (!fs.existsSync(root)) { console.error(`model-ids: no such path: ${root}`); process.exit(2); }

const SKIP_DIRS = new Set(['node_modules', '.git', '.next', 'dist', 'build', '.venv', '__pycache__', 'coverage', 'target']);
const SKIP_FILES = /(^|\/)(package-lock\.json|bun\.lockb?|yarn\.lock|pnpm-lock\.yaml|uv\.lock|Cargo\.lock|poetry\.lock)$/;
const CODE = /\.(py|js|mjs|cjs|ts|tsx|jsx|go|rb|java|kt|rs|cs|php|swift|sh)$/;
const ID = /(?:(?:us|eu|apac|global|us-gov|jp|au|ca)\.)?(?:anthropic\.)?claude-(?:(?:opus|sonnet|haiku|fable|instant|mythos)|[a-z]+-\d|\d)[a-z0-9._-]*(?::\d+)?(?:\[[0-9a-z]+\])?/gi;
const PARTIAL = /\b(?:opus|sonnet|haiku|fable|mythos)-(?:\d|preview)[a-z0-9.-]*/gi;
const COND = /\bif\b|\bin\b|startswith|startsWith|includes\(|\.match\(|re\.(?:search|match)|\bcase\b|\bswitch\b|===|==/;
const MARKER = /KEEP IN SYNC|MODEL LAUNCH|@model-update/;
const SUFFIXED = /(?:-(?:fast|\d+k|\d+m)|\[[0-9a-z]+\])$/i;
const CALLER = /\b(?:model|model_?id|modelId|model_name)\b["']?\s*[:=(]/i;
const DEFINER = /^\s*(?:["']?[\w.-]+["']?\s*[:=]\s*["']|[A-Z][A-Z0-9_]*\s*=)/;

const norm = (id) => id.toLowerCase()
  .replace(/^(?:us|eu|apac|global|us-gov|jp|au|ca)\./, '')
  .replace(/^anthropic\./, '');
const VER = /-v\d+(?::\d+)?$/;
const bare = (id) => id.replace(VER, '');

const catalog = new Map();
const unversioned = new Map(); // base name -> entry, from catalog tokens that carry no -vN:M
const lookup = (id) => {
  const n = norm(id);
  if (catalog.has(n)) return catalog.get(n);
  if (VER.test(n)) return unversioned.get(bare(n));
  for (const [k, v] of catalog) if (bare(k) === n) return v;
};
if (catalogPath) {
  const toks = fs.readFileSync(catalogPath, 'utf8').split(/\s+/).filter(Boolean);
  let last = null;
  for (const t of toks) {
    if (/^(current|active|legacy|deprecated|retired)$/i.test(t) && last) { catalog.get(last).status = t.toLowerCase() === 'active' ? 'current' : t.toLowerCase(); continue; }
    if (/^\d{4}-\d{2}-\d{2}$/.test(t) && last) { catalog.get(last).date = t; continue; }
    last = norm(t);
    if (!catalog.has(last)) catalog.set(last, { status: 'current', date: '' });
    if (!VER.test(last)) unversioned.set(last, catalog.get(last));
  }
}

function* walk(dir) {
  const st = fs.statSync(dir);
  if (st.isFile()) { yield dir; return; }
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    if (e.isDirectory()) { if (!SKIP_DIRS.has(e.name)) yield* walk(path.join(dir, e.name)); }
    else if (e.isFile()) yield path.join(dir, e.name);
  }
}

const base = fs.statSync(root).isFile() ? path.dirname(root) : root;
const markers = [];
const hits = [];
const gates = [];

for (const file of walk(root)) {
  if (catalogPath && path.resolve(file) === path.resolve(catalogPath)) continue;
  const rel = path.relative(base, file) || path.basename(file);
  if (SKIP_FILES.test(rel)) continue;
  let text;
  try {
    if (fs.statSync(file).size > 1_000_000) continue;
    text = fs.readFileSync(file, 'utf8');
  } catch { continue; }
  if (text.includes('\0')) continue;
  text.split('\n').forEach((line, i) => {
    const at = `${rel}:${i + 1}`;
    if (MARKER.test(line)) markers.push({ at, text: line.trim().slice(0, 100) });
    const ids = [...line.matchAll(ID)].map((m) => m[0].replace(/[.-]+$/, ''));
    for (const id of ids) {
      const known = lookup(id);
      const status = !catalogPath ? 'unverified' : known ? known.status : 'unknown';
      const bucket = SUFFIXED.test(id) ? 'suffixed' : CALLER.test(line) ? 'caller' : DEFINER.test(line) ? 'definer' : 'opaque';
      hits.push({ at, status, bucket, id, date: known?.date || '' });
    }
    if (!ids.length && CODE.test(rel) && COND.test(line)) {
      const m = line.match(PARTIAL);
      if (m) gates.push({ at, partial: m[0] });
    }
  });
}

if (json) {
  console.log(JSON.stringify({ markers, hits, gates }, null, 2));
  process.exit(0);
}
for (const m of markers) console.log(`${m.at} marker ${m.text}`);
for (const h of hits) console.log(`${h.at} ${h.status} ${h.bucket} ${h.id}${h.date ? ` (${h.date})` : ''}`);
for (const g of gates) console.log(`${g.at} gate add-alongside ${g.partial}`);
if (hits.length || gates.length) {
  console.log('actions: caller = swap the ID and apply the target version checklist; definer = keep the entry, add the new model alongside;');
  console.log('opaque = swap after checking parsers and substring matches; suffixed = verify in the registry, else leave and flag; gate = add alongside.');
}
