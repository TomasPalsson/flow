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
 *                 [--lock treatment=<scene|pattern|photography|product-ui|typography|data-visual|utility>] [--lock device=<technique>]
 *                 [--from <key>] [--reroll <n>] [--register safer|bolder] [--canon]
 *                 [--dossier <file> --concepts <file>] [--sector <id>] [--concept-only]
 *                 [--project <dir>] [--json] [--no-memory]
 *
 *   --from <key>    replay a roll exactly.   --reroll n   next hand under the same key
 *                   (excludes every world dealt in rounds 0..n-1).
 *   --dossier       .vary/dossier.json: the project's facts [{id,kind,text,source}]. Required with --concepts.
 *   --concepts      .vary/concepts.json: 4-7 concepts the MODEL wrote, each tied to dossier facts; the script, not the
 *                   model, picks one (uniform; a recently used angle is demoted), then picks the
 *                   signature-device technique from that concept's devices (recent techniques demoted).
 *   --sector <id>   the project's sector (enum below). Worlds whose avoid_sectors list it are removed;
 *                   worlds whose sectors list it are weighted up. --lock world still wins.
 *   --lock concept=<id>  world-only veto: keep the concept, --reroll n re-deals world and device. With a concept dealt the
 *                   world pool is concept.world_hints only; 5% of scene/pattern rounds (never operate/read, never a non-drawn treatment) print WILDCARD and widen it to every sector-allowed world, where sector-suited worlds keep their weight.
 *                   Each concept needs a `temperament` (heritage-craft, warm-domestic, civic-calm, technical-precise,
 *                   playful-bright, natural-raw, nocturnal-social, avant-garde); worlds not listing it are removed first.
 *   --concept-only  print only the CONCEPT / FACTS / FUNCTIONAL RESKIN / SIGNATURE DEVICE block (no world).
 *   --canon         the category standard, played straight and with craft (the user's exit).
 *   treatment       every concept may name a hero `treatment` (roll-treatment.mjs); otherwise it follows the dealt device's technique.
 *                   dossier.directives[].locks ("key=value", from the user's own words) are merged into --lock and outrank it:
 *                   a conflicting CLI lock exits 2.
 *
 * Exit codes: 0 ok · 2 bad arguments · 3 data missing/corrupt.
 * No dependencies. Node ≥ 18.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';
import { TECHNIQUES, TREATMENTS, TECH_TREATMENT, allowedFor, fallbackTreatment, mergeDirectiveLocks, resolveTreatment, fitDevice, noAccent, drawn, treatmentProblem, directiveLines, OBLIGATION, scaleLine, ruleSentence } from './roll-treatment.mjs';

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
const HINT_MULT = 8;       // world named in the dealt concept's world_hints
const SUIT_MULT = 1.5;     // world.sectors includes --sector

// controlled sector vocabulary (worlds.json `sectors` / `avoid_sectors` draw from this)
const SECTORS = ['food-drink', 'hospitality-travel', 'retail-ecommerce', 'trades-construction', 'industrial-hardware',
  'engineering-technical', 'healthcare-clinical', 'finance-insurance', 'legal-public', 'kids-education',
  'culture-arts', 'music-events-nightlife', 'fashion-beauty-luxury', 'sports-fitness', 'media-publishing',
  'dev-tools', 'enterprise-saas', 'nature-outdoor', 'maritime-logistics', 'nonprofit-activism', 'wellness', 'gaming'];
// the business's own register (concept.temperament); every world lists the 2-4 it can serve (worlds.json `temperaments`)
const TEMPERAMENTS = ['heritage-craft', 'warm-domestic', 'civic-calm', 'technical-precise', 'playful-bright',
  'natural-raw', 'nocturnal-social', 'avant-garde'];
// techniques that cannot be the hero device on a surface of that mode (the device stays at plate/micro scale there)
const HERO_FORBIDDEN = { operate: ['shader', 'scroll-scene'], read: ['shader'] };

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
      case '--dossier': a.dossier = take(); break;
      case '--concepts': a.concepts = take(); break;
      case '--sector': a.sector = take(); if (!SECTORS.includes(a.sector)) die(2, `--sector ${a.sector} is not in the sector list: ${SECTORS.join(', ')}`); break;
      case '--concept-only': a.conceptOnly = true; break;
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
if (args.concepts && !args.dossier) die(2, '--concepts needs --dossier (every cited fact id must resolve in it)');
if (args.locks.concept && !args.concepts) die(2, '--lock concept=<id> needs --dossier and --concepts');
if (args.conceptOnly && !args.concepts) die(2, '--concept-only needs --dossier and --concepts');

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

// ---- 0. concept (the model wrote the options; the script deals) --------------------------------
function readJSONArg(flag, path) {
  try { return JSON.parse(readFileSync(path, 'utf8')); } catch (e) { die(2, `${flag}: cannot read ${path}: ${e.message}`); }
}
function validateConcepts(list, dossier) {
  if (!Array.isArray(list)) die(2, '--concepts: file must be a JSON array of concepts');
  if (list.length < 4 || list.length > 7) die(2, `--concepts: need 4-7 concepts, got ${list.length}`);
  const factIds = new Set((dossier.facts || []).map(f => f.id));
  const ids = new Set(), angles = new Set();
  for (const [i, c] of list.entries()) {
    const at = `--concepts[${i}]${c && c.id ? ` (${c.id})` : ''}`;
    if (!c || typeof c.id !== 'string' || !c.id) die(2, `${at}: missing id`);
    if (ids.has(c.id)) die(2, `${at}: duplicate id ${c.id}`);
    ids.add(c.id);
    if (typeof c.angle !== 'string' || !c.angle.trim()) die(2, `${at}: missing angle`);
    const ang = c.angle.trim().toLowerCase();
    if (angles.has(ang)) die(2, `${at}: duplicate angle "${c.angle}" (each concept needs a different angle on the business)`);
    angles.add(ang);
    if (!Array.isArray(c.facts) || c.facts.length < 3) die(2, `${at}: needs at least 3 facts, got ${Array.isArray(c.facts) ? c.facts.length : 0}`);
    for (const f of c.facts) if (!factIds.has(f)) die(2, `${at}: fact id ${f} is not in the dossier`);
    if (typeof c.functional_reskin !== 'string' || !c.functional_reskin.trim()) die(2, `${at}: functional_reskin is empty`);
    if (!Array.isArray(c.devices)) die(2, `${at}: devices must be an array`);
    for (const d of c.devices) if (!d || !TECHNIQUES.includes(d.technique)) die(2, `${at}: unknown technique ${d && d.technique}; use one of ${TECHNIQUES.join(', ')}`);
    const problem = treatmentProblem(c, dossier); if (problem) die(2, `${at}: ${problem}`);
    if (!TEMPERAMENTS.includes(c.temperament)) die(2, `${at}: temperament must be one of ${TEMPERAMENTS.join(', ')} (the business's own register, from the dossier), got ${c.temperament ?? 'none'}`);
    const hints = c.world_hints ?? [];
    if (!Array.isArray(hints) || hints.length < 2 || hints.length > 3) die(2, `${at}: world_hints must name 2-3 world ids (worlds whose grammar suits this concept), got ${Array.isArray(hints) ? hints.length : 'none'}`);
    for (const h of hints) if (!worlds.some(w => w.id === h)) die(2, `${at}: world_hint ${h} is not a world id; valid ids: ${worlds.map(w => w.id).join(', ')}`);
    if (!hints.some(h => worlds.find(w => w.id === h).temperaments?.includes(c.temperament))) die(2, `${at}: no world_hint fits temperament ${c.temperament}; name at least one world whose temperaments list it`);
  }
}
function validateDossier(d) {
  if (!d || typeof d !== 'object' || Array.isArray(d)) die(2, '--dossier: file must be a JSON object');
  if (!Array.isArray(d.facts)) die(2, '--dossier: "facts" array is missing (schema in references/dossier.md: facts:[{id,kind,text,source}])');
  if (d.facts.length < 12) die(2, `--dossier: need at least 12 facts, got ${d.facts.length}`);
  for (const [i, f] of d.facts.entries()) {
    if (!f || typeof f.id !== 'string' || !f.id) die(2, `--dossier: facts[${i}] has no id`);
    if (typeof f.source !== 'string' || !f.source.trim()) die(2, `--dossier: fact ${f.id} has no source (every fact needs a URL, file path or "user brief")`);
  }
  const kinds = new Set(d.facts.map(f => f.kind).filter(k => typeof k === 'string' && k));
  if (kinds.size < 4) die(2, `--dossier: need at least 4 distinct fact kinds, got ${kinds.size} (${[...kinds].join(', ') || 'none'})`);
  if (d.sector && args.sector && d.sector !== args.sector) die(2, `--dossier: sector "${d.sector}" does not match --sector ${args.sector}`);
}
const dossierData = args.dossier ? readJSONArg('--dossier', args.dossier) : null;
if (dossierData) validateDossier(dossierData);
{
  const conflict = mergeDirectiveLocks(args.locks, dossierData); if (conflict) die(2, conflict);
  if (args.locks.treatment && !TREATMENTS.includes(args.locks.treatment)) die(2, `--lock treatment=${args.locks.treatment} is not a treatment (${TREATMENTS.join(', ')})`);
  if (args.locks.device && !TECHNIQUES.includes(args.locks.device)) die(2, `--lock device=${args.locks.device} is not a technique (${TECHNIQUES.join(', ')})`);
}
let treatment = null;
// with a treatment lock, prefer concepts whose treatment equals it or is unset; when none qualify the dealt concept stays and is overridden
const eligible = list => { const l = args.locks.treatment ? list.filter(c => !c.treatment || c.treatment === args.locks.treatment) : list; return l.length ? l : list; };
let concept = null, device = null, conceptFacts = [];
if (args.concepts) {
  const dossier = dossierData;
  const list = readJSONArg('--concepts', args.concepts);
  validateConcepts(list, dossier);
  const factById = Object.fromEntries((dossier.facts || []).map(f => [f.id, f]));
  const recentAngles = recentSet(recentLocal, 'angle', PROJECT_WINDOW);
  // every concept is fact-backed, so none is dropped for being likely; only a recently used angle is demoted
  const pickConcept = (cands, round) => weightedPick(cands, cands.map(c => (recentAngles.has(c.angle) ? DEMOTED_TICKETS : BASE_TICKETS)), key, `concept:${round}`);
  if (args.locks.concept) {
    // world-only veto: the concept stays, only the world and device re-roll
    concept = list.find(c => c.id === args.locks.concept) || die(2, `--lock concept=${args.locks.concept} is not a concept id in --concepts (${list.map(c => c.id).join(', ')})`);
    notes.push(`concept locked to ${concept.id}; --reroll changes only the world and device`);
  } else {
    const dealt = new Set();
    for (let r = 0; r < args.reroll; r++) {
      const left = eligible(list).filter(c => !dealt.has(c.id));
      const prev = pickConcept(left.length ? left : list, r);
      if (prev) dealt.add(prev.id);
    }
    let cPool = eligible(list).filter(c => !dealt.has(c.id));
    if (!cPool.length) { cPool = eligible(list); notes.push('re-roll exhausted the concepts; reusing'); }
    concept = pickConcept(cPool, args.reroll);
  }
  conceptFacts = concept.facts.map(id => factById[id]);
  const forbidden = HERO_FORBIDDEN[args.mode] || [];
  let devCands = concept.devices.filter(d => !forbidden.includes(d.technique));
  if (!devCands.length && concept.devices.length) { devCands = concept.devices; notes.push(`every device of ${concept.id} is a poor hero for mode ${args.mode}; keep it at plate/micro scale, not hero`); }
  const rt = recent('technique');
  const deal = (pool, maps) => weightedPick(pool, pool.map(d => (rt.has(d.technique) ? DEMOTED_TICKETS : BASE_TICKETS) * (maps && TECH_TREATMENT[d.technique] === maps ? 4 : 1)), key, `device:${args.reroll}`);
  device = devCands.length ? deal(devCands) : null;
  const rt2 = resolveTreatment({ concept, device, mode: args.mode, lock: args.locks.treatment });
  treatment = rt2.treatment; notes.push(...rt2.notes);
  if (args.locks.device) {
    device = concept.devices.find(d => d.technique === args.locks.device) || { technique: args.locks.device, what: '(locked by the user or a directive; the concept names no device of this technique)' };
    notes.push(`device locked to ${args.locks.device}`);
  } else if (!rt2.fromDevice && devCands.length) device = deal(devCands, treatment);
  if (!args.locks.device) { const fd = fitDevice(device, concept, treatment); device = fd.device; if (fd.note) notes.push(fd.note); }
  coherence.push({ check: 'concept facts resolve in dossier', ok: conceptFacts.every(Boolean) });
  coherence.push({ check: 'device allowed as hero for mode', ok: !device || !forbidden.includes(device.technique) });
  coherence.push({ check: 'treatment allowed for mode', ok: rt2.locked || allowedFor(args.mode, treatment) });
} else {
  notes.push('no --concepts: subject-blind roll; for a new project vary requires Step 0-1 (dossier, then concepts)');
  if (args.locks.treatment) treatment = args.locks.treatment;
}
if (args.conceptOnly) {
  const lines = [`SEED KEY: ${key}  (reroll ${args.reroll}) · mode ${args.mode} · concept only`, ...conceptLines(concept, device, conceptFacts, treatment)];
  if (args.json) console.log(JSON.stringify({ key, reroll: args.reroll, mode: args.mode, concept: concept.id, angle: concept.angle, treatment, device, facts: conceptFacts, coherence, notes, contract: lines }, null, 1));
  else {
    console.log('<!--'); for (const l of lines) console.log(l); console.log('-->'); console.log('');
    console.log('COHERENCE:'); for (const r of coherence) console.log(`  [${r.ok ? 'ok' : 'FAIL'}] ${r.check}`);
    if (notes.length) { console.log('NOTES:'); for (const n of notes) console.log(`  - ${n}`); }
    console.log(''); console.log(`RULE: commit to this concept and device; the model does not swap them. Replay: --from ${key}${args.reroll ? ` --reroll ${args.reroll}` : ''}. Next hand: --from ${key} --reroll ${args.reroll + 1}.`);
  }
  if (args.memory) {
    const pick = { ts: new Date().toISOString(), key, mode: args.mode, concept: concept.id, angle: concept.angle, technique: device?.technique, treatment };
    recordPick(files.global, pick, 64);
    if (files.local) recordPick(files.local, pick, 32);
  }
  process.exit(0);
}

// ---- canon ---------------------------------------------------------------------------------
if (args.canon) {
  const canonArch = { persuade: phone ? 'poster' : 'split-screen', operate: phone ? 'index-list' : 'sidebar-tool', read: 'single-column', experience: 'poster' }[args.mode];
  if (!concept) { treatment = args.locks.treatment || fallbackTreatment(args.mode); notes.push(`canon with no concept: treatment ${treatment}`); }
  else if (drawn(treatment) && !args.locks.treatment) {
    // split-screen cannot carry a drawn scene (headline-in-scene, full-bleed rows), so canon never takes a drawn treatment
    treatment = fallbackTreatment(args.mode); notes.push(`canon: concept ${concept.id} treatment is drawn; split-screen cannot carry it, using ${treatment}`);
    if (!args.locks.device) { const fd = fitDevice(device, concept, treatment); device = fd.device; if (fd.note) notes.push(fd.note); }
  }
  const body = fonts.find(f => f.id === 'system-ui') || fonts[0];
  const out = contract({
    key, reroll: args.reroll, mode: args.mode, platform: args.platform,
    world: { id: 'canon', name: 'Category standard, played straight', grammar: ['Match the two or three products the user names as peers; their craft level is the bar.', 'No irony, no smuggled quirk: convention executed at full fidelity.', 'Distinctiveness lives in details: spacing rhythm, focus states, empty states, copy that only this product could say.'], refuse: ['half-committed novelty on top of the conventional skeleton'], motion: { moment: 'one state transition tuned to the product (e.g. the primary action\'s success), nothing else animates', easing: 'ease-out, 150-250ms', forbidden: ['uniform fade-up on every section'] } },
    archetype: archById[canonArch], strategy: 'restrained', seed: null, display: body, body, concept, device, conceptFacts, treatment,
  });
  emit(out, { canon: true });
  if (args.memory && concept) {
    const pick = { ts: new Date().toISOString(), key, mode: args.mode, concept: concept?.id, angle: concept?.angle, technique: device?.technique, treatment };
    recordPick(files.global, pick, 64);
    if (files.local) recordPick(files.local, pick, 32);
  }
  process.exit(0);
}

// ---- 1. world pool (mode + platform + locks + register) ------------------------------------------
let pool = worlds.filter(w => !w.trap && w.modes?.includes(args.mode));
pool = pool.filter(w => w.archetypes.some(a => archById[a] && (!phone || !PHONE_EXCLUDED_ARCHETYPES.has(a))));
if (args.locks.world) {
  const w = worlds.find(x => x.id === args.locks.world);
  if (!w) die(2, `--lock world=${args.locks.world} is not a world id`);
  pool = [w];
  if (args.sector && (w.avoid_sectors || []).includes(args.sector)) notes.push(`locked world ${w.id} lists ${args.sector} in avoid_sectors (user lock honoured)`);
}
if (args.register === 'safer') pool = pool.filter(w => w.decay === 'slow' && w.color_strategies.some(s => QUIET_STRATEGIES.has(s)));
if (args.register === 'bolder') pool = pool.filter(w => w.modes.includes('experience') || w.decay !== 'slow');
// sector fit: a world that lists the project's sector in avoid_sectors is not dealt (a user lock still wins)
// temperament fit: with a concept dealt, a world whose temperaments exclude the concept's is never dealt (the wildcard
// widens sector, never temperament)
// avant-garde worlds are dealt only to avant-garde concepts, by any path (hint, sector fit or wildcard)
const tempOk = w => !concept || !!args.locks.world || ((w.temperaments || []).includes(concept.temperament)
  && (concept.temperament === 'avant-garde' || !(w.temperaments || []).includes('avant-garde')));
const sectorOk = w => !args.sector || !(w.avoid_sectors || []).includes(args.sector);
if (concept && !args.locks.world) {
  const before = pool.length; pool = pool.filter(tempOk);
  if (pool.length < before) notes.push(`${before - pool.length} worlds removed: temperaments exclude ${concept.temperament}`);
}
if (args.sector && !args.locks.world) {
  const before = pool.length; pool = pool.filter(sectorOk);
  if (pool.length < before) notes.push(`${before - pool.length} worlds removed: avoid_sectors includes ${args.sector}`);
}
if (!pool.length) {
  // relax: adjacent mode, then everything non-trap (the sector filter still applies)
  const adjacent = { persuade: 'experience', experience: 'persuade', read: 'persuade', operate: 'read' }[args.mode];
  pool = worlds.filter(w => !w.trap && w.modes?.includes(adjacent) && sectorOk(w) && tempOk(w));
  notes.push(`world pool empty for mode=${args.mode}; relaxed to adjacent mode ${adjacent}`);
  if (!pool.length) { pool = worlds.filter(w => !w.trap && sectorOk(w) && tempOk(w)); notes.push('relaxed to full catalog'); }
}
// relevance: with a concept dealt, the pool is concept.world_hints only; WILDCARD_P of the rounds widen to every
// sector-allowed world (sector-suited worlds keep their SUIT_MULT weight there and in the empty-pool fallback). The wildcard
// never fires for a non-drawn treatment or for operate/read: those stay inside their hints. Recency demotion stays inside whichever pool.
const WILDCARD_P = 0.05;
const narrowFor = (round, excluded) => {
  const open = pool.filter(w => !excluded.has(w.id));
  if (!concept || args.locks.world) return { list: open };
  const wildOk = drawn(treatment) && args.mode !== 'operate' && args.mode !== 'read';
  if (wildOk && unit(key, `wild:${round}`) < WILDCARD_P) {
    // the wildcard never deals an avant-garde-tagged world to a concept that is not itself avant-garde
    const calm = open.filter(w => concept.temperament === 'avant-garde' || !(w.temperaments || []).includes('avant-garde'));
    return { list: calm.length ? calm : open, wild: true };
  }
  const hints = new Set(concept.world_hints || []);
  const narrow = open.filter(w => hints.has(w.id));
  return narrow.length ? { list: narrow } : { list: open, empty: true };
};
// exclusion chain for re-rolls: recompute rounds 0..n-1 under this key and drop what they dealt
const excludedWorlds = new Set();
for (let r = 0; r < args.reroll; r++) {
  const prev = pickWorld(narrowFor(r, excludedWorlds).list, r);
  if (prev) excludedWorlds.add(prev.id);
}
let { list: worldPool, wild, empty } = narrowFor(args.reroll, excludedWorlds);
if (!worldPool.length) { worldPool = pool; notes.push('re-roll exhausted the pool; reusing'); }
if (wild) notes.push('WILDCARD: this round (5% of rolls) widened the world pool beyond the concept hints; make the world earn its place or re-roll');
if (empty) notes.push('no world matches the concept hints in this mode; pool widened to every sector-allowed world');
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
    // multiplicative, so recency still bites: a recent but hinted world is dealt about as often as an untouched, unhinted one
    if (concept?.world_hints?.includes(w.id)) t *= HINT_MULT;
    if (args.sector && (w.sectors || []).includes(args.sector)) t *= SUIT_MULT;
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
const bw = noAccent(dossierData, strategy);
if (bw) notes.push('directive asks for black and white with ink-on-paper: no accent colour, no tinted palette seed');
if (args.locks.palette) {
  lockedHex = args.locks.palette.startsWith('#') ? args.locks.palette : `#${args.locks.palette}`;
  const ok = hexToOklch(lockedHex); const b = bucketOf(ok.h);
  const near = seeds.filter(s => s.bucket === b).map(s => ({ s, d: Math.hypot(s.oklch.l - ok.l, (s.oklch.c - ok.c) * 2) })).sort((x, y) => x.d - y.d)[0];
  if (near && near.d < 0.15) { seed = near.s; notes.push(`brand ${lockedHex} matched to ${seed.id} (bucket ${b}); the literal hex stays the anchor`); }
  else notes.push(`brand ${lockedHex} (bucket ${b}) has no close seed; carry the literal hex as PALETTE SEED`);
} else if (bw) {
  // no seed: true black and paper white only
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

// ---- 6. coherence check (script-side rows) ----------------------------------------------------------
coherence.push({ check: 'strategy passes mode gate', ok: MODE_STRATEGIES[args.mode].includes(strategy) });
coherence.push({ check: 'seed light/dark compatible with --scene', ok: !seed || !args.scene || seed.light_or_dark === 'either' || seed.light_or_dark === args.scene });
coherence.push({ check: 'archetype allowed on platform', ok: !phone || !PHONE_EXCLUDED_ARCHETYPES.has(archetype.id) });
coherence.push({ check: 'fonts cover required scripts', ok: [display, body].every(f => !f || fontOk(f)) });
coherence.push({ check: 'body face ships ≥3 weights or is variable', ok: !body || body.id === 'system-ui' || body.variable || (body.weights || '').split(/[,;]/).length >= 3 });
coherence.push({ check: 'world not in sector avoid list', ok: !args.sector || !(world.avoid_sectors || []).includes(args.sector) });

// ---- 7. output --------------------------------------------------------------------------------------
const result = contract({ key, reroll: args.reroll, mode: args.mode, platform: args.platform, world, archetype, strategy, seed, lockedHex, display, body, concept, device, conceptFacts, treatment, bw });
emit(result, {});
if (args.memory) {
  const pick = { ts: new Date().toISOString(), key, mode: args.mode, world: world.id, archetype: archetype.id, strategy, seed: seed?.id, display: display?.id, body: body?.id, concept: concept?.id, angle: concept?.angle, technique: device?.technique, treatment };
  recordPick(files.global, pick, 64);
  if (files.local) recordPick(files.local, pick, 32);
}

function fontLine(f) {
  if (!f) return 'none';
  const load = f.load?.type === 'system' ? 'system stack (no webfont)' : f.load?.url || f.load?.download_url || '';
  const w = f.variable ? `variable ${f.weights}` : `weights ${f.weights}`;
  return `${f.name} (${f.class}; ${w}) · ${load}`;
}
function conceptLines(cn, dv, facts, tr) {
  if (!cn) return ['CONCEPT: none', ...(tr ? [`HERO TREATMENT: ${tr} — ${OBLIGATION[tr]}`] : []), ...directiveLines(dossierData)];
  const l = [`CONCEPT: ${cn.id} — ${cn.name || cn.id} — angle: ${cn.angle} — antecedent: ${cn.antecedent || 'n/a'}`, 'FACTS:'];
  for (const f of facts) { const t = (f.text || '').replace(/\s+/g, ' '); l.push(`  - ${f.id} "${t.length > 100 ? t.slice(0, 99) + '…' : t}" (${f.source || 'no source'})`); }
  l.push(`FUNCTIONAL RESKIN: ${cn.functional_reskin}`);
  l.push(`SIGNATURE DEVICE: ${dv ? `${dv.technique} — ${dv.what || ''}` : 'none'} · ${scaleLine(tr)}`);
  if (tr) l.push(`HERO TREATMENT: ${tr} — ${OBLIGATION[tr]}`);
  l.push(...directiveLines(dossierData));
  return l;
}
function contract(c) {
  const lines = [];
  lines.push(`SEED KEY: ${c.key}  (reroll ${c.reroll}) · mode ${c.mode} · platform ${c.platform}`);
  lines.push(`WORLD: ${c.world.id} — ${c.world.name}${c.world.one_line ? ' — ' + c.world.one_line : ''}`);
  lines.push(...conceptLines(c.concept, c.device, c.conceptFacts, c.treatment));
  if (c.world.suits) lines.push(`FIT: sector ${args.sector || 'unspecified'} · world suits: ${[].concat(c.world.suits).join(', ')} · world avoid_for: ${[].concat(c.world.avoid_for || []).join(', ')}`);
  lines.push(`ARCHETYPE: ${c.archetype.id} — ${c.archetype.structure}`);
  lines.push(`  first viewport: ${c.archetype.first_viewport}; primary action: ${c.archetype.primary_action}; scroll: ${c.archetype.scroll}`);
  lines.push(`  mobile: ${c.archetype.mobile_fallback}`);
  lines.push(`STRATEGY: ${c.strategy}${c.bw ? ' — true black + paper white only; NO accent colour (the directive overrides the world palette hint)' : c.world.palette_hint ? ' — ' + c.world.palette_hint : ''}`);
  if (c.lockedHex && !c.seed) lines.push(`PALETTE SEED: brand ${c.lockedHex} (locked) · oklch(${Object.values(hexToOklch(c.lockedHex)).join(' ')})`);
  else if (c.seed) lines.push(`PALETTE SEED: ${c.seed.id} · oklch(${c.seed.oklch.l} ${c.seed.oklch.c} ${c.seed.oklch.h}) · ${c.seed.hex_srgb} · role ${c.seed.role_hint} · text on it: ${c.seed.text_on_it} · ${c.seed.mood} (${c.seed.material})${c.lockedHex ? ` · brand anchor ${c.lockedHex}` : ''}`);
  else if (c.bw) lines.push('PALETTE SEED: none — black and white by directive; neutrals only, no tint');
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
  lines.push('SIGNATURE GRAPHIC: <model: what is drawn, which FACTS it encodes, how it renders (engine/file), its three placements>');
  return { lines, c };
}
function emit(out, extra) {
  if (args.json) {
    const { c } = out;
    console.log(JSON.stringify({ key, reroll: args.reroll, mode: args.mode, platform: args.platform, world: c.world.id, archetype: c.archetype.id, strategy: c.strategy, seed: c.seed?.id || null, locked_hex: c.lockedHex || null, display: c.display?.id, body: c.body?.id, concept: c.concept ? { id: c.concept.id, angle: c.concept.angle } : null, treatment: c.treatment || null, device: c.device || null, facts: c.conceptFacts || [], coherence, notes, contract: out.lines, ...extra }, null, 1));
    return;
  }
  console.log('<!--');
  for (const l of out.lines) console.log(l);
  console.log('-->');
  console.log('');
  if (coherence.length) { console.log('COHERENCE:'); for (const r of coherence) console.log(`  [${r.ok ? 'ok' : 'FAIL'}] ${r.check}`); }
  if (notes.length) { console.log('NOTES:'); for (const n of notes) console.log(`  - ${n}`); }
  console.log('');
  console.log('RULE: paste the comment block above verbatim as the first child of <body> in the root layout. Fill SCENE, FIRST VIEWPORT, THESIS and SIGNATURE GRAPHIC. ' + ruleSentence(out.c.treatment) + ' Re-roll only on named grounds: a FAIL above; a script the font lacks; the world cannot carry the SIGNATURE DEVICE; or the user vetoes the world for this trade. Replay: --from ' + key + (args.reroll ? ` --reroll ${args.reroll}` : '') + '. Next hand: --from ' + key + ` --reroll ${args.reroll + 1}.`);
}
