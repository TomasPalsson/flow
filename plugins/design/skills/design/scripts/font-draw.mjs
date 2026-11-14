#!/usr/bin/env node
// font-draw.mjs [--scripts latin,latin-ext] [--source google] [--class a,b] [--exclude id,id] [--seed s] [--n 4]
// Deals a shortlist of display and body faces from the vary font catalogue, skipping faces the catalogue marks as
// second-order defaults (the ones generated pages converge on once told to avoid Inter). Choose from the shortlist by
// fit to the concept; never reach past it for a face from memory. Prints the seed so a draw can be repeated.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const argv = process.argv.slice(2);
const opt = (k, d) => { const i = argv.indexOf(`--${k}`); return i >= 0 ? argv[i + 1] : d; };
const scripts = opt('scripts', 'latin').split(',');
const source = opt('source', 'any');
const classes = opt('class', '').split(',').filter(Boolean);
const exclude = new Set(opt('exclude', '').split(',').filter(Boolean));
const n = +opt('n', 4);
const seed = opt('seed', String(Date.now() % 1e9));

let catalogue;
try { catalogue = JSON.parse(readFileSync(join(here, '../../vary/data/fonts.json'), 'utf8')); }
catch { console.error('font-draw: ../../vary/data/fonts.json not found next to this skill'); process.exit(2); }

// mulberry32 over a string hash: deterministic for a given seed
let h = 1779033703;
for (const c of seed) h = Math.imul(h ^ c.charCodeAt(0), 3432918353), h = (h << 13) | (h >>> 19);
const rand = () => { h |= 0; h = (h + 0x6d2b79f5) | 0; let t = Math.imul(h ^ (h >>> 15), 1 | h); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
const shuffle = (xs) => { const a = [...xs]; for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; } return a; };

const pool = catalogue.filter((f) => !f.second_order_default && !exclude.has(f.id) && f.class !== 'system-stack'
  && scripts.every((s) => (f.scripts || []).includes(s))
  && (source === 'any' || (source === 'google' ? f.source.startsWith('google-fonts') : f.source === source))
  && (!classes.length || classes.includes(f.class)));

const deal = (role, avoidMono) => {
  const out = []; const seenClass = new Set();
  for (const f of shuffle(pool.filter((x) => (x.roles || []).includes(role) && !(avoidMono && x.class === 'mono')))) {
    if (seenClass.has(f.class)) continue;   // one per classification, so the shortlist spans real alternatives
    seenClass.add(f.class); out.push(f);
    if (out.length === n) break;
  }
  return out;
};
const line = (f) => `  ${f.name.padEnd(24)} ${f.class.padEnd(20)} ${f.weights.padEnd(8)} ${f.voice}\n  ${''.padEnd(24)} load: ${f.load?.url || f.source_url}${f.pairs_with?.length ? `\n  ${''.padEnd(24)} pairs with: ${f.pairs_with.join(', ')}` : ''}`;

console.log(`seed ${seed} · scripts ${scripts.join('+')} · source ${source} · pool ${pool.length} faces (second-order defaults excluded)\n`);
console.log('DISPLAY candidates'); deal('display', true).forEach((f) => console.log(line(f)));
console.log('\nBODY candidates'); deal('body', true).forEach((f) => console.log(line(f)));
console.log('\nChoose by fit to the concept and say why in one line. A single family for both roles is fine. Mono only for literal code, commands or tabular data, never for labels.');
