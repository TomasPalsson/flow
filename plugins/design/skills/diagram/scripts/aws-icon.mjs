#!/usr/bin/env node
// Official AWS Architecture Icons for diagrams, inlined as SVG.
//
//   node aws-icon.mjs find <words...>                 best matches (alias, then name search)
//   node aws-icon.mjs get <name> [--x N --y N --size N] [--id prefix] [--raw]
//
// <name> is an alias from data/aws-icons.json (lambda, s3, apigw, vpc, ...), a full
// path like architecture-service/AWSLambda, or search words. Icons come from the
// aws-icons npm package (AWS Architecture Icons 01/30/2026) via jsDelivr and are
// cached under $XDG_CACHE_HOME/design-diagram/aws-icons/<version>/. Set
// AWS_ICONS_DIR to a local `icons/` directory to work offline.

import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { homedir } from 'node:os';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const INDEX = JSON.parse(readFileSync(join(here, '..', 'data', 'aws-icons.json'), 'utf8'));
const KIND_RANK = { 'architecture-service': 0, 'architecture-group': 1, resource: 2, category: 3 };

const norm = s => s.toLowerCase().replace(/[^a-z0-9]/g, '');

export function find(query, limit = 8) {
  const q = query.trim().toLowerCase().replace(/\s+/g, '-');
  if (INDEX.aliases[q]) return [INDEX.aliases[q]];
  if (INDEX.icons.includes(query)) return [query];
  const words = query.toLowerCase().split(/[\s,/_-]+/).filter(Boolean).map(norm);
  const scored = [];
  for (const path of INDEX.icons) {
    const [kind, file] = path.split('/');
    const name = norm(file);
    if (!words.every(w => name.includes(w))) continue;
    const bare = name.replace(/^(amazon|aws)/, '');
    const exact = words.join('') === bare ? 0 : 1;
    scored.push([exact, KIND_RANK[kind], name.length, path]);
  }
  scored.sort((a, b) => a[0] - b[0] || a[1] - b[1] || a[2] - b[2] || (a[3] < b[3] ? -1 : 1));
  return scored.slice(0, limit).map(s => s[3]);
}

async function load(path) {
  if (process.env.AWS_ICONS_DIR) return readFileSync(join(process.env.AWS_ICONS_DIR, `${path}.svg`), 'utf8');
  const cacheRoot = process.env.XDG_CACHE_HOME || join(homedir(), '.cache');
  const cached = join(cacheRoot, 'design-diagram', 'aws-icons', INDEX.version, `${path}.svg`);
  if (existsSync(cached)) return readFileSync(cached, 'utf8');
  const res = await fetch(`${INDEX.base}${path}.svg`);
  if (!res.ok) throw new Error(`fetch ${path}: HTTP ${res.status}`);
  const svg = await res.text();
  if (!svg.includes('<svg')) throw new Error(`fetch ${path}: not an SVG`);
  mkdirSync(dirname(cached), { recursive: true });
  writeFileSync(cached, svg);
  return svg;
}

// Nested <svg> placed at x,y with the icon's own viewBox; <title> dropped (the
// diagram's label carries the name) and any ids prefixed so inlined icons never collide.
export function inline(svg, { x = 0, y = 0, size = 48, id = 'aws' } = {}) {
  const viewBox = (svg.match(/viewBox="([^"]+)"/) || [, '0 0 64 64'])[1];
  let body = svg.replace(/^[\s\S]*?<svg[^>]*>/, '').replace(/<\/svg>\s*$/, '').replace(/<title>[\s\S]*?<\/title>/g, '');
  body = body.replace(/\bid="([^"]+)"/g, `id="${id}-$1"`).replace(/url\(#([^)]+)\)/g, `url(#${id}-$1)`)
    .replace(/(xlink:)?href="#([^"]+)"/g, (_, x, ref) => `${x || ''}href="#${id}-${ref}"`);
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}" aria-hidden="true" focusable="false">${body.trim()}</svg>`;
}

function args(argv) {
  const opts = { _: [] };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--raw') opts.raw = true;
    else if (a.startsWith('--')) opts[a.slice(2)] = argv[++i];
    else opts._.push(a);
  }
  return opts;
}

async function main() {
  const [cmd, ...rest] = process.argv.slice(2);
  const o = args(rest);
  const query = o._.join(' ');
  if (cmd === 'find' && query) {
    const hits = find(query);
    if (!hits.length) { console.error(`no AWS icon matches "${query}"`); process.exit(1); }
    console.log(hits.join('\n'));
  } else if (cmd === 'get' && query) {
    const [path] = find(query, 1);
    if (!path) { console.error(`no AWS icon matches "${query}"; try: node aws-icon.mjs find <words>`); process.exit(1); }
    const svg = await load(path);
    console.log(o.raw ? svg.trim() : inline(svg, { x: +(o.x ?? 0), y: +(o.y ?? 0), size: +(o.size ?? 48), id: o.id ?? norm(path.split('/')[1]) }));
  } else {
    console.error('usage: aws-icon.mjs find <words...> | get <name> [--x N --y N --size N --id prefix --raw]');
    process.exit(2);
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) main().catch(e => { console.error(e.message); process.exit(1); });
