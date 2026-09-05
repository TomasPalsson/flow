#!/usr/bin/env node
/**
 * roll.mjs — external dice for the `vary` design skill.
 *
 * Why this exists: the model derives varied candidates but always argmax-picks the same one
 * (measured 30/35 identical concepts; hand-selection reverted 27/30). Only an ASSIGNMENT made
 * outside the model breaks that. This script assigns, dependently, in order:
 *   world → archetype (from the world's list) → colour strategy (from the world's list)
 *         → palette seed (from the world's hue buckets, matching the strategy)
 *         → display + body font (from the world's type classes)
 * so the parts cannot contradict each other (coherence by construction).
 *
 * Usage:
 *   node roll.mjs --mode persuade [--platform web|ios|android]
 *                 [--scene light|dark] [--scripts latin,cyrillic] [--no-webfonts]
 *                 [--longevity long|campaign] [--lock world=<id>] [--lock archetype=<id>]
 *                 [--lock strategy=<id>] [--lock seed=<id>] [--lock palette=#hex]
 *                 [--lock display=<font-id>] [--lock body=<font-id>]
 *                 [--from <key>] [--reroll <n>] [--register safer|bolder] [--canon]
 *                 [--grounded <candidates.json>] [--project <dir>] [--json] [--no-memory]
 *
 *   --from <key>    replay a roll exactly.   --reroll n   next hand under the same key
 *                   (excludes every world dealt in rounds 0..n-1).
 *   --grounded      JSON array [{"name":"…","p":0.3,"why":"…"}] of the model's own cultural
 *                   antecedents with self-estimated probabilities; the script picks from the
 *                   TAIL (drops the top third) and prints it as GROUNDED ANTECEDENT.
 *   --canon         the category standard, played straight and with craft (the user's exit).
 *
 * Exit codes: 0 ok · 2 bad arguments · 3 data missing/corrupt.
 * No dependencies. Node ≥ 18.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
const DATA = resolve(here, '..', 'data');

// ---- tunables (starting points, not measured optima; adjust from real usage) ----------------
const GLOBAL_WINDOW = 8;   // recent picks remembered across projects, per axis
const PROJECT_WINDOW = 3;  // recent picks remembered inside one project, per axis
const BASE_TICKETS = 4;    // weight of an untouched entry
const DEMOTED_TICKETS = 1; // weight of a recently-used / decaying entry
const DEFAULT_TICKETS = 0.5; // weight of a second-order-default face (Satoshi, Geist, Inter…): kept, rarely dealt
const TAG_BONUS = 1;       // extra weight for a font the world card names; capped so over-tagged faces don't dominate
const TAG_CAP = 6;         // fonts tagged with more worlds than this get no bonus

// mode → colour strategies bold enough to be allowed on that surface (the gate)
const MODE_STRATEGIES = {
  operate: ['restrained', 'monochrome-tonal', 'ink-on-paper', 'muted-earth', 'two-field-split', 'dark-with-warm-light', 'committed'],
  read: ['restrained', 'ink-on-paper', 'monochrome-tonal', 'muted-earth', 'high-key-pastel', 'committed', 'two-field-split'],
  persuade: ['restrained', 'committed', 'full-palette', 'drenched', 'duotone', 'two-field-split', 'ink-on-paper', 'dark-with-warm-light', 'high-key-pastel', 'muted-earth', 'primary-triad', 'jewel-tones', 'monochrome-tonal', 'acid-hi-vis'],
  experience: ['restrained', 'committed', 'full-palette', 'drenched', 'duotone', 'two-field-split', 'ink-on-paper', 'dark-with-warm-light', 'high-key-pastel', 'acid-hi-vis', 'muted-earth', 'primary-triad', 'jewel-tones', 'monochrome-tonal'],
};
// archetypes that need a pointer / wide viewport; excluded on phones
const PHONE_EXCLUDED_ARCHETYPES = new Set(['dense-console', 'spec-sheet', 'split-screen', 'sidebar-tool', 'cardless-table', 'asymmetric-offset', 'scroll-narrative', 'zine-collage']);
const QUIET_STRATEGIES = new Set(['restrained', 'ink-on-paper', 'monochrome-tonal', 'muted-earth']);
const BODY_CLASSES_OK = new Set(['neo-grotesque', 'geometric-sans', 'humanist-sans', 'transitional-serif', 'old-style-serif', 'slab', 'mono', 'condensed', 'variable-showpiece', 'system-stack']);

// ---- args ------------------------------------------------------------------------------------
function parseArgs(argv) {
  const a = { locks: {}, scripts: ['latin'], platform: 'web', reroll: 0, json: false, memory: true, longevity: 'long' };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i], v = argv[i + 1];
    const take = () => { i++; return v; };
    switch (k) {
      case '--mode': a.mode = take(); break;
      case '--platform': a.platform = take(); break;
      case '--scene': a.scene = take(); break;
      case '--scripts': a.scripts = take().split(',').map(s => s.trim().toLowerCase()).filter(Boolean); break;
      case '--no-webfonts': a.noWebfonts = true; break;
      case '--longevity': a.longevity = take(); break;
      case '--lock': { const [lk, ...rest] = take().split('='); a.locks[lk] = rest.join('='); break; }
      case '--from': a.key = take(); break;
      case '--reroll': a.reroll = Number(take()); break;
      case '--register': a.register = take(); break;
      case '--canon': a.canon = true; break;
      case '--grounded': a.grounded = take(); break;
      case '--project': a.project = take(); break;
      case '--json': a.json = true; break;
      case '--no-memory': a.memory = false; break;
      case '-h': case '--help': a.help = true; break;
      default: die(2, `unknown argument ${k}`);
    }
  }
  return a;
}
function die(code, msg) { process.stderr.write(`roll: ${msg}\n`); process.exit(code); }

// ---- data ------------------------------------------------------------------------------------
function loadJSON(name) {
  const p = join(DATA, name);
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch (e) { die(3, `cannot load ${p}: ${e.message}. The roll must not fall back to the model's own choice; fix the data file.`); }
}

// ---- deterministic randomness -----------------------------------------------------------------
function unit(key, salt) {
  const h = createHash('sha256').update(`${salt}:${key}`).digest();
  return h.readUInt32BE(0) / 0x100000000;
}
function weightedPick(items, weights, key, salt) {
  const total = weights.reduce((s, w) => s + w, 0);
  if (!items.length || total <= 0) return null;
  let r = unit(key, salt) * total;
  for (let i = 0; i < items.length; i++) { r -= weights[i]; if (r < 0) return items[i]; }
  return items[items.length - 1];
}

// ---- memory ----------------------------------------------------------------------------------
function stateFile(project) {
  const xdg = process.env.XDG_STATE_HOME || join(homedir(), '.local', 'state');
  const global = join(xdg, 'vary', 'recent.json');
  const local = project ? join(resolve(project), '.vary', 'recent.json') : null;
  return { global, local };
}
function readPicks(p) { try { return JSON.parse(readFileSync(p, 'utf8')).picks || []; } catch { return []; } }
function recentSet(picks, axis, n) { return new Set(picks.slice(-n).map(x => x[axis]).filter(Boolean)); }
function recordPick(p, pick, cap) {
  try {
    mkdirSync(dirname(p), { recursive: true });
    const picks = readPicks(p); picks.push(pick);
    writeFileSync(p, JSON.stringify({ picks: picks.slice(-cap) }, null, 1));
    // keep project state out of git
    const gi = join(dirname(dirname(p)), '.gitignore');
    if (p.includes(`${'/'}.vary${'/'}`) && existsSync(dirname(dirname(p)))) {
      const cur = existsSync(gi) ? readFileSync(gi, 'utf8') : '';
      if (!cur.split('\n').includes('.vary/')) appendFileSync(gi, (cur.endsWith('\n') || cur === '' ? '' : '\n') + '.vary/\n');
    }
  } catch (e) { process.stderr.write(`roll: memory not written (${e.message})\n`); }
}

// ---- colour helpers (OKLCH ↔ sRGB, for --lock palette) ------------------------------------------
function hexToOklch(hex) {
  const m = hex.replace('#', '');
  const n = m.length === 3 ? m.split('').map(c => c + c).join('') : m;
  const [r, g, b] = [0, 2, 4].map(i => parseInt(n.slice(i, i + 2), 16) / 255);
  const lin = c => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
  const [R, G, B] = [lin(r), lin(g), lin(b)];
  const l = Math.cbrt(0.4122214708 * R + 0.5363325363 * G + 0.0514459929 * B);
  const m_ = Math.cbrt(0.2119034982 * R + 0.6806995451 * G + 0.1073969566 * B);
  const s = Math.cbrt(0.0883024619 * R + 0.2817188376 * G + 0.6299787005 * B);
  const L = 0.2104542553 * l + 0.7936177850 * m_ - 0.0040720468 * s;
  const a = 1.9779984951 * l - 2.4285922050 * m_ + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m_ - 0.8086757660 * s;
  const C = Math.hypot(a, bb); let H = (Math.atan2(bb, a) * 180) / Math.PI; if (H < 0) H += 360;
  return { l: +L.toFixed(3), c: +C.toFixed(4), h: +H.toFixed(1) };
}
const bucketOf = h => Math.min(24, Math.floor(((h % 360) + 360) % 360 / 15) + 1);

// ---- main ------------------------------------------------------------------------------------
const args = parseArgs(process.argv.slice(2));
if (args.help) { console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('*/')[0]); process.exit(0); }
if (!args.mode || !MODE_STRATEGIES[args.mode]) die(2, '--mode must be persuade | operate | read | experience (decide it from the SURFACE, not the product)');
if (!['web', 'ios', 'android'].includes(args.platform)) die(2, '--platform must be web | ios | android');
if (args.register && !['safer', 'bolder'].includes(args.register)) die(2, '--register must be safer | bolder');
if (args.register && args.reroll < 1) die(2, '--register steers a re-roll; pass --reroll <n> with it');
if (args.scene && !['light', 'dark'].includes(args.scene)) die(2, '--scene must be light | dark');

const worlds = loadJSON('worlds.json');
const archetypes = loadJSON('archetypes.json');
const seeds = loadJSON('seeds.json');
const fonts = loadJSON('fonts.json');
const archById = Object.fromEntries(archetypes.map(a => [a.id, a]));
const key = args.key || randomBytes(4).toString('hex');
const phone = args.platform !== 'web';
const files = stateFile(args.project);
const recentGlobal = args.memory ? readPicks(files.global) : [];
const recentLocal = args.memory && files.local ? readPicks(files.local) : [];
const recent = axis => new Set([...recentSet(recentGlobal, axis, GLOBAL_WINDOW), ...recentSet(recentLocal, axis, PROJECT_WINDOW)]);
const notes = [];
const coherence = [];

// ---- canon ---------------------------------------------------------------------------------
if (args.canon) {
  const canonArch = { persuade: 'split-screen', operate: 'sidebar-tool', read: 'single-column', experience: 'poster' }[args.mode];
  const body = fonts.find(f => f.id === 'system-ui') || fonts[0];
  const out = contract({
    key, reroll: args.reroll, mode: args.mode, platform: args.platform,
    world: { id: 'canon', name: 'Category standard, played straight', grammar: ['Match the two or three products the user names as peers; their craft level is the bar.', 'No irony, no smuggled quirk: convention executed at full fidelity.', 'Distinctiveness lives in details: spacing rhythm, focus states, empty states, copy that only this product could say.'], refuse: ['half-committed novelty on top of the conventional skeleton'], motion: { moment: 'one state transition tuned to the product (e.g. the primary action\'s success), nothing else animates', easing: 'ease-out, 150-250ms', forbidden: ['uniform fade-up on every section'] } },
    archetype: archById[canonArch], strategy: 'restrained', seed: null, display: body, body,
  });
  emit(out, { canon: true });
  process.exit(0);
}

// ---- 1. world pool (mode + platform + locks + register) ------------------------------------------
let pool = worlds.filter(w => !w.trap && w.modes?.includes(args.mode));
pool = pool.filter(w => w.archetypes.some(a => archById[a] && (!phone || !PHONE_EXCLUDED_ARCHETYPES.has(a))));
if (args.locks.world) {
  const w = worlds.find(x => x.id === args.locks.world);
  if (!w) die(2, `--lock world=${args.locks.world} is not a world id`);
  pool = [w];
}
if (args.register === 'safer') pool = pool.filter(w => w.decay === 'slow' && w.color_strategies.some(s => QUIET_STRATEGIES.has(s)));
if (args.register === 'bolder') pool = pool.filter(w => w.modes.includes('experience') || w.decay !== 'slow');
if (!pool.length) {
  // relax: adjacent mode, then everything non-trap
  const adjacent = { persuade: 'experience', experience: 'persuade', read: 'persuade', operate: 'read' }[args.mode];
  pool = worlds.filter(w => !w.trap && w.modes?.includes(adjacent));
  notes.push(`world pool empty for mode=${args.mode}; relaxed to adjacent mode ${adjacent}`);
  if (!pool.length) { pool = worlds.filter(w => !w.trap); notes.push('relaxed to full catalog'); }
}
// exclusion chain for re-rolls: recompute rounds 0..n-1 under this key and drop what they dealt
const excludedWorlds = new Set();
for (let r = 0; r < args.reroll; r++) {
  const prev = pickWorld(pool.filter(w => !excludedWorlds.has(w.id)), r);
  if (prev) excludedWorlds.add(prev.id);
}
let worldPool = pool.filter(w => !excludedWorlds.has(w.id));
if (!worldPool.length) { worldPool = pool; notes.push('re-roll exhausted the pool; reusing'); }
const world = pickWorld(worldPool, args.reroll);
if (!world) die(3, 'no world could be assigned');

function pickWorld(cands, round) {
  const rw = recent('world');
  const weights = cands.map(w => {
    let t = BASE_TICKETS;
    if (rw.has(w.id)) t = DEMOTED_TICKETS;
    if (args.longevity === 'long' && w.decay === 'fast') t = Math.min(t, DEMOTED_TICKETS);
    if (w.confidence === 'medium') t = Math.max(1, t - 1);
    if (w.confidence === 'verify') t = Math.min(t, DEMOTED_TICKETS); // grammar not fully corroborated: dealt rarely
    return t;
  });
  return weightedPick(cands, weights, key, `world:${round}`);
}

// ---- 2. archetype (from the world's list) ---------------------------------------------------
let archCands = world.archetypes.filter(a => archById[a] && (!phone || !PHONE_EXCLUDED_ARCHETYPES.has(a)));
if (args.locks.archetype) {
  if (!archById[args.locks.archetype]) die(2, `--lock archetype=${args.locks.archetype} is not an archetype id`);
  archCands = [args.locks.archetype];
  if (!world.archetypes.includes(args.locks.archetype)) notes.push(`archetype ${args.locks.archetype} is locked but not native to ${world.id}; the world's grammar still governs`);
}
const ra = recent('archetype');
const archetype = archById[weightedPick(archCands, archCands.map(a => (ra.has(a) ? DEMOTED_TICKETS : BASE_TICKETS)), key, `archetype:${args.reroll}`)];

// ---- 3. colour strategy (world ∩ mode gate) --------------------------------------------------
let stratCands = world.color_strategies.filter(s => MODE_STRATEGIES[args.mode].includes(s));
if (!stratCands.length) { stratCands = MODE_STRATEGIES[args.mode].filter(s => QUIET_STRATEGIES.has(s)); notes.push(`none of ${world.id}'s strategies pass the ${args.mode} gate; using a quiet strategy`); }
if (args.locks.strategy) stratCands = [args.locks.strategy];
const rs = recent('strategy');
const strategy = weightedPick(stratCands, stratCands.map(s => (rs.has(s) ? DEMOTED_TICKETS : BASE_TICKETS)), key, `strategy:${args.reroll}`);

// ---- 4. palette seed ---------------------------------------------------------------------------
let seed = null, lockedHex = null;
if (args.locks.palette) {
  lockedHex = args.locks.palette.startsWith('#') ? args.locks.palette : `#${args.locks.palette}`;
  const ok = hexToOklch(lockedHex); const b = bucketOf(ok.h);
  const near = seeds.filter(s => s.bucket === b).map(s => ({ s, d: Math.hypot(s.oklch.l - ok.l, (s.oklch.c - ok.c) * 2) })).sort((x, y) => x.d - y.d)[0];
  if (near && near.d < 0.15) { seed = near.s; notes.push(`brand ${lockedHex} matched to ${seed.id} (bucket ${b}); the literal hex stays the anchor`); }
  else notes.push(`brand ${lockedHex} (bucket ${b}) has no close seed; carry the literal hex as PALETTE SEED`);
} else if (args.locks.seed) {
  seed = seeds.find(s => s.id === args.locks.seed) || die(2, `--lock seed=${args.locks.seed} is not a seed id`);
} else {
  const buckets = world.seed_buckets?.length ? new Set(world.seed_buckets) : null;
  const tiers = [
    s => (!buckets || buckets.has(s.bucket)) && s.strategy_hint === strategy && s.modes.includes(args.mode) && (!args.scene || s.light_or_dark === 'either' || s.light_or_dark === args.scene),
    s => (!buckets || buckets.has(s.bucket)) && s.strategy_hint === strategy,
    s => (!buckets || buckets.has(s.bucket)) && s.modes.includes(args.mode),
    s => !buckets || buckets.has(s.bucket),
    () => true,
  ];
  const rsd = recent('seed');
  for (let i = 0; i < tiers.length && !seed; i++) {
    const c = seeds.filter(tiers[i]);
    if (c.length) { seed = weightedPick(c, c.map(s => (rsd.has(s.id) ? DEMOTED_TICKETS : BASE_TICKETS)), key, `seed:${args.reroll}`); if (i > 0) notes.push(`seed matched at relaxation tier ${i} (strategy/mode/bucket filters loosened)`); }
  }
}

// ---- 5. fonts ----------------------------------------------------------------------------------
const wantScripts = new Set(args.scripts);
// a face qualifies only if it covers every required script; a face with no scripts list is assumed Latin-only
const fontOk = f => f.roles && [...wantScripts].every(s => (f.scripts && f.scripts.length ? f.scripts : ['latin']).includes(s));
const worldTagged = f => (f.worlds || []).includes(world.id) && (f.worlds || []).length <= TAG_CAP;
function fontWeight(f, rec) {
  let t = BASE_TICKETS;
  if (f.second_order_default) t = DEFAULT_TICKETS;
  if (args.longevity === 'long' && f.decay === 'fast') t = Math.min(t, DEMOTED_TICKETS);
  if (rec.has(f.id)) t = Math.min(t, DEMOTED_TICKETS);
  if (worldTagged(f)) t += TAG_BONUS;
  if (f.confidence === 'medium') t = Math.max(0.5, t - 1);
  return t;
}
function pickFont(role, classes, lockId, salt) {
  if (args.noWebfonts) return fonts.find(f => f.id === 'system-ui');
  if (lockId) return fonts.find(f => f.id === lockId) || die(2, `--lock ${role}=${lockId} is not a font id`);
  const rec = recent(role);
  const bodyCapable = f => f.roles.includes('body') && (f.variable || (f.weights || '').split(/[,;]/).length >= 3);
  let strict = fonts.filter(f => classes.includes(f.class) && f.roles.includes(role) && fontOk(f) && (role !== 'body' || BODY_CLASSES_OK.has(f.class)));
  // one-family worlds (display classes == body classes): the display face should be able to carry body text too
  if (role === 'display' && oneFamilyWorld) { const carry = strict.filter(bodyCapable); if (carry.length) strict = carry; }
  const loose = fonts.filter(f => classes.includes(f.class) && fontOk(f));
  const any = fonts.filter(f => f.roles.includes(role) && fontOk(f) && (role !== 'body' || BODY_CLASSES_OK.has(f.class)));
  const cands = strict.length ? strict : loose.length ? loose : any;
  if (cands === loose) notes.push(`${role} font: no face in ${classes.join('/')} declares the ${role} role; loosened`);
  if (cands === any) notes.push(`${role} font: no face in ${classes.join('/')} covers scripts ${[...wantScripts].join(',')}; picked from any class`);
  return weightedPick(cands, cands.map(f => fontWeight(f, rec)), key, `${salt}:${args.reroll}`);
}
// worlds whose display and body classes coincide (Swiss, transit, Rams) want ONE family carrying the hierarchy
const oneFamilyWorld = JSON.stringify([...world.type.display].sort()) === JSON.stringify([...world.type.body].sort());
const display = pickFont('display', world.type.display, args.locks.display, 'display');
let body = pickFont('body', world.type.body, args.locks.body, 'body');
if (!args.locks.body && display && oneFamilyWorld && display.roles.includes('body') && (display.variable || (display.weights || '').split(/[,;]/).length >= 3) && unit(key, `onefamily:${args.reroll}`) < 0.7) body = display;
if (body && body.id === display?.id) notes.push('display and body are one family: hierarchy must come from weight and size, not a second face');
if (body && !body.variable && (body.weights || '').split(/[,;]/).length < 3 && body.id !== 'system-ui') {
  const alt = fonts.filter(f => world.type.body.includes(f.class) && f.roles.includes('body') && fontOk(f) && (f.variable || (f.weights || '').split(/[,;]/).length >= 3) && BODY_CLASSES_OK.has(f.class));
  if (alt.length) { body = weightedPick(alt, alt.map(f => fontWeight(f, recent('body'))), key, `body-alt:${args.reroll}`); notes.push('body face swapped for one that ships ≥3 weights (no faux bold)'); }
}

// ---- 6. grounded antecedents (Verbalized Sampling tail pick) ---------------------------------------
let grounded = null;
if (args.grounded) {
  let list; try { list = JSON.parse(readFileSync(args.grounded, 'utf8')); } catch (e) { die(2, `--grounded: cannot read ${args.grounded}: ${e.message}`); }
  if (!Array.isArray(list) || list.length < 3) die(2, '--grounded needs an array of ≥3 {name,p,why}');
  const ranked = [...list].sort((a, b) => (b.p ?? 0) - (a.p ?? 0));
  const drop = Math.max(1, Math.floor(ranked.length / 3));
  const tail = ranked.slice(drop);
  grounded = weightedPick(tail, tail.map(() => 1), key, `grounded:${args.reroll}`);
  grounded.rank = ranked.indexOf(grounded) + 1; grounded.of = ranked.length;
}

// ---- 7. coherence check (script-side rows) ----------------------------------------------------------
coherence.push({ check: 'strategy passes mode gate', ok: MODE_STRATEGIES[args.mode].includes(strategy) });
coherence.push({ check: 'seed light/dark compatible with --scene', ok: !seed || !args.scene || seed.light_or_dark === 'either' || seed.light_or_dark === args.scene });
coherence.push({ check: 'archetype allowed on platform', ok: !phone || !PHONE_EXCLUDED_ARCHETYPES.has(archetype.id) });
coherence.push({ check: 'fonts cover required scripts', ok: [display, body].every(f => !f || fontOk(f)) });
coherence.push({ check: 'body face ships ≥3 weights or is variable', ok: !body || body.id === 'system-ui' || body.variable || (body.weights || '').split(/[,;]/).length >= 3 });

// ---- 8. output --------------------------------------------------------------------------------------
const result = contract({ key, reroll: args.reroll, mode: args.mode, platform: args.platform, world, archetype, strategy, seed, lockedHex, display, body, grounded });
emit(result, {});
if (args.memory) {
  const pick = { ts: new Date().toISOString(), key, mode: args.mode, world: world.id, archetype: archetype.id, strategy, seed: seed?.id, display: display?.id, body: body?.id };
  recordPick(files.global, pick, 64);
  if (files.local) recordPick(files.local, pick, 32);
}

function fontLine(f) {
  if (!f) return 'none';
  const load = f.load?.type === 'system' ? 'system stack (no webfont)' : f.load?.url || f.load?.download_url || '';
  const w = f.variable ? `variable ${f.weights}` : `weights ${f.weights}`;
  return `${f.name} (${f.class}; ${w}) · ${load}`;
}
function contract(c) {
  const lines = [];
  lines.push(`SEED KEY: ${c.key}  (reroll ${c.reroll}) · mode ${c.mode} · platform ${c.platform}`);
  lines.push(`WORLD: ${c.world.id} — ${c.world.name}${c.world.one_line ? ' — ' + c.world.one_line : ''}`);
  if (c.grounded) lines.push(`GROUNDED ANTECEDENT: ${c.grounded.name} (your #${c.grounded.rank} of ${c.grounded.of} by self-estimated likelihood) — ${c.grounded.why || ''}`);
  lines.push(`ARCHETYPE: ${c.archetype.id} — ${c.archetype.structure}`);
  lines.push(`  first viewport: ${c.archetype.first_viewport}; primary action: ${c.archetype.primary_action}; scroll: ${c.archetype.scroll}`);
  lines.push(`  mobile: ${c.archetype.mobile_fallback}`);
  lines.push(`STRATEGY: ${c.strategy}${c.world.palette_hint ? ' — ' + c.world.palette_hint : ''}`);
  if (c.lockedHex && !c.seed) lines.push(`PALETTE SEED: brand ${c.lockedHex} (locked) · oklch(${Object.values(hexToOklch(c.lockedHex)).join(' ')})`);
  else if (c.seed) lines.push(`PALETTE SEED: ${c.seed.id} · oklch(${c.seed.oklch.l} ${c.seed.oklch.c} ${c.seed.oklch.h}) · ${c.seed.hex_srgb} · role ${c.seed.role_hint} · text on it: ${c.seed.text_on_it} · ${c.seed.mood} (${c.seed.material})${c.lockedHex ? ` · brand anchor ${c.lockedHex}` : ''}`);
  else lines.push('PALETTE SEED: none (canon) — use the brand colour or a tinted neutral');
  if (c.seed?.avoid_with?.length) lines.push(`  avoid: ${c.seed.avoid_with.join('; ')}`);
  lines.push(`DISPLAY FONT: ${fontLine(c.display)}`);
  lines.push(`BODY FONT: ${fontLine(c.body)}`);
  if (c.world.type?.notes) lines.push(`  type notes: ${c.world.type.notes}`);
  lines.push(`MOTION MOMENT: ${c.world.motion?.moment} · easing ${c.world.motion?.easing} · never: ${(c.world.motion?.forbidden || []).join(', ')}`);
  lines.push('GRAMMAR:'); for (const g of c.world.grammar || []) lines.push(`  - ${g}`);
  if (c.world.materials?.length) lines.push(`MATERIALS: ${c.world.materials.join('; ')}`);
  if (c.world.physical_antecedents?.length) lines.push(`ANTECEDENTS: ${c.world.physical_antecedents.join('; ')}`);
  lines.push(`REFUSE: ${(c.world.refuse || []).join('; ')}`);
  if (c.world.tell) lines.push(`COSTUME TELL: ${c.world.tell}`);
  lines.push('SCENE: <model: one sentence — who uses this, where, under what light; this decides light or dark>');
  lines.push('FIRST VIEWPORT: <model: what is where, at what scale, where the primary action sits>');
  lines.push('THESIS: <model: the one idea this surface owns, and the category-default arrangement it refuses>');
  return { lines, c };
}
function emit(out, extra) {
  if (args.json) {
    const { c } = out;
    console.log(JSON.stringify({ key, reroll: args.reroll, mode: args.mode, platform: args.platform, world: c.world.id, archetype: c.archetype.id, strategy: c.strategy, seed: c.seed?.id || null, locked_hex: c.lockedHex || null, display: c.display?.id, body: c.body?.id, grounded: c.grounded || null, coherence, notes, contract: out.lines, ...extra }, null, 1));
    return;
  }
  console.log('<!--');
  for (const l of out.lines) console.log(l);
  console.log('-->');
  console.log('');
  if (coherence.length) { console.log('COHERENCE:'); for (const r of coherence) console.log(`  [${r.ok ? 'ok' : 'FAIL'}] ${r.check}`); }
  if (notes.length) { console.log('NOTES:'); for (const n of notes) console.log(`  - ${n}`); }
  console.log('');
  console.log('RULE: paste the comment block above verbatim as the first child of <body> in the root layout, then fill SCENE, FIRST VIEWPORT and THESIS. Writing any UI code before that is a contract violation. Re-roll only on named factual grounds (a script the font lacks; an audience named in the world\'s avoid_for; a FAIL above). Replay: --from ' + key + (args.reroll ? ` --reroll ${args.reroll}` : '') + '. Next hand: --from ' + key + ` --reroll ${args.reroll + 1}.`);
}
