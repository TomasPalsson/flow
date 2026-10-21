#!/usr/bin/env node
/**
 * pick-style.mjs: external dice for the `graphics` design skill.
 *
 * The model, left alone, draws the same look every time. This script assigns one illustration
 * style from data/styles.json from outside the model, seeded, so a run can be replayed.
 *
 * Usage:
 *   node pick-style.mjs [--mood playful,warm] [--kinds icon-set,spot] [--project <dir>]
 *                       [--lock style=<id>] [--from <key>] [--reroll <n>] [--json] [--no-memory]
 *
 *   --mood     comma or space separated mood words; styles whose `suits` overlap are weighted up,
 *              styles whose `avoid` overlaps are dropped.
 *   --kinds    asset kinds the style must serve (every one must be in the style's best_for);
 *              if none match, any-match is used and a note is printed.
 *   --from     replay a pick exactly.  --reroll n  the next hand under the same key (excludes
 *              every style dealt in rounds 0..n-1).
 *   --lock     style=<id> wins over everything (exit 2 on an unknown id).
 *   --project  directory whose .vary/recent-styles.json remembers the last 3 picks (demoted);
 *              the last 6 picks across projects are demoted too.
 *   --data     another catalog with the same shape (the diagram skill's data/skins.json); its
 *              memory files are named after it (recent-skins.json).
 *   --sticky   with --project: reuse that project's latest pick instead of dealing, so every
 *              asset in one project shares a look (--reroll or --lock still deal fresh).
 *
 * Exit codes: 0 ok, 2 bad arguments, 3 data missing or corrupt.
 * No dependencies. Node >= 18.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync, existsSync, appendFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
let DATA = resolve(here, '..', 'data', 'styles.json');

const GLOBAL_WINDOW = 6;
const PROJECT_WINDOW = 3;
const BASE_TICKETS = 4;
const DEMOTED_TICKETS = 1;
const MOOD_BONUS = 2; // extra tickets per matching mood tag

function die(code, msg) { process.stderr.write(`pick-style: ${msg}\n`); process.exit(code); }

function parseArgs(argv) {
  const a = { locks: {}, mood: [], kinds: [], reroll: 0, json: false, memory: true };
  const words = s => s.split(/[,\s]+/).map(x => x.trim().toLowerCase()).filter(Boolean);
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i], v = argv[i + 1];
    const take = () => { i++; if (v === undefined) die(2, `${k} needs a value`); return v; };
    switch (k) {
      case '--mood': a.mood = words(take()); break;
      case '--kinds': a.kinds = words(take()); break;
      case '--lock': { const [lk, ...rest] = take().split('='); a.locks[lk] = rest.join('='); break; }
      case '--from': a.key = take(); break;
      case '--reroll': a.reroll = Number(take()); if (!Number.isInteger(a.reroll) || a.reroll < 0) die(2, '--reroll needs a non-negative integer'); break;
      case '--project': a.project = take(); break;
      case '--data': a.data = take(); break;
      case '--sticky': a.sticky = true; break;
      case '--json': a.json = true; break;
      case '--no-memory': a.memory = false; break;
      case '-h': case '--help': a.help = true; break;
      default: die(2, `unknown argument ${k}`);
    }
  }
  return a;
}

function loadStyles() {
  try {
    const d = JSON.parse(readFileSync(DATA, 'utf8'));
    if (!Array.isArray(d.styles) || !d.styles.length) throw new Error('no styles');
    return d;
  } catch (e) { die(3, `cannot load ${DATA}: ${e.message}`); }
}

// ---- deterministic randomness ----------------------------------------------------------------
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
function stateFiles(project) {
  const xdg = process.env.XDG_STATE_HOME || join(homedir(), '.local', 'state');
  const name = `recent-${basename(DATA, '.json')}.json`;
  return {
    global: join(xdg, 'vary', name),
    local: project ? join(resolve(project), '.vary', name) : null,
  };
}
function readPicks(p) { try { return JSON.parse(readFileSync(p, 'utf8')).picks || []; } catch { return []; } }
function recordPick(p, pick, cap) {
  try {
    mkdirSync(dirname(p), { recursive: true });
    const picks = readPicks(p); picks.push(pick);
    writeFileSync(p, JSON.stringify({ picks: picks.slice(-cap) }, null, 1));
    const root = dirname(dirname(p));
    if (p.includes(`${'/'}.vary${'/'}`) && existsSync(root)) {
      const gi = join(root, '.gitignore');
      const cur = existsSync(gi) ? readFileSync(gi, 'utf8') : '';
      if (!cur.split('\n').includes('.vary/')) appendFileSync(gi, (cur.endsWith('\n') || cur === '' ? '' : '\n') + '.vary/\n');
    }
  } catch (e) { process.stderr.write(`pick-style: memory not written (${e.message})\n`); }
}

// ---- the pick --------------------------------------------------------------------------------
const overlap = (a, b) => a.filter(x => b.includes(x));

function deal(styles, args, key, round, recentIds, notes) {
  let pool = styles;
  if (args.kinds.length) {
    const strict = pool.filter(s => args.kinds.every(k => s.best_for.includes(k)));
    if (strict.length) pool = strict;
    else {
      const loose = pool.filter(s => args.kinds.some(k => s.best_for.includes(k)));
      if (loose.length) { pool = loose; notes.push(`no style serves every kind (${args.kinds.join(', ')}); relaxed to any match`); }
      else notes.push(`no style lists ${args.kinds.join(', ')}; kinds ignored`);
    }
  }
  if (args.mood.length) {
    const kept = pool.filter(s => !overlap(s.avoid || [], args.mood).length);
    if (kept.length) pool = kept;
    else notes.push('every style avoids this mood; avoid lists ignored');
  }
  const weights = pool.map(s => {
    let w = BASE_TICKETS + MOOD_BONUS * overlap(s.suits || [], args.mood).length;
    if (recentIds.has(s.id)) w = DEMOTED_TICKETS;
    return w;
  });
  return weightedPick(pool, weights, key, `style:${round}`);
}

function render(r, json) {
  if (json) return JSON.stringify(r, null, 2) + '\n';
  const { style, notes } = r, t = style.traits || {};
  return [
    `STYLE: ${style.id} (${style.name})`,
    `LOOK: ${style.look}`,
    `TRAITS: stroke: ${t.stroke}; fill: ${t.fill}; shading: ${t.shading}; texture: ${t.texture}; people and objects: ${t.simplification}`,
    `BANNED: ${(style.banned || []).join('; ')}`,
    ...(style.tokens ? [`TOKENS: ${JSON.stringify(style.tokens)}`] : []),
    ...notes.map(n => `NOTE: ${n}`),
    `SEED KEY: ${r.key}  (reroll ${r.reroll})`,
    `RE-ROLL: ${r.rerollCommand}`,
  ].join('\n') + '\n';
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write('usage: pick-style.mjs [--mood w,w] [--kinds k,k] [--project dir] [--data file] [--sticky] [--lock style=id] [--from key] [--reroll n] [--json] [--no-memory]\n');
    return;
  }
  if (args.data) DATA = resolve(args.data);
  if (args.sticky && !args.project) die(2, '--sticky needs --project');
  const data = loadStyles();
  const styles = data.styles;
  if (data.kinds) for (const k of args.kinds) if (!data.kinds.includes(k)) die(2, `unknown kind ${k}; valid: ${data.kinds.join(', ')}`);
  for (const lk of Object.keys(args.locks)) if (lk !== 'style') die(2, `unknown lock ${lk}; only style=<id> is supported`);

  const key = args.key || randomBytes(6).toString('hex');
  const files = stateFiles(args.project);
  const globalPicks = args.memory ? readPicks(files.global) : [];
  const localPicks = args.memory && files.local ? readPicks(files.local) : [];
  const recentIds = new Set([
    ...globalPicks.slice(-GLOBAL_WINDOW).map(p => p.style),
    ...localPicks.slice(-PROJECT_WINDOW).map(p => p.style),
  ].filter(Boolean));

  const notes = [];
  let style;
  const kept = args.sticky && !args.reroll && args.locks.style === undefined && !args.key
    ? styles.find(s => s.id === readPicks(files.local).at(-1)?.style) : null;
  if (kept) {
    style = kept;
    notes.push('kept this project\'s look (--sticky); --reroll 1 deals a new one');
  } else if (args.locks.style !== undefined) {
    style = styles.find(s => s.id === args.locks.style);
    if (!style) die(2, `--lock style=${args.locks.style} is not a style id; valid: ${styles.map(s => s.id).join(', ')}`);
    notes.push('style locked');
  } else {
    // round 0..reroll: each round excludes the styles already dealt
    let remaining = styles;
    for (let round = 0; round <= args.reroll; round++) {
      if (!remaining.length) { remaining = styles; notes.push('every style dealt; wrapped around'); }
      style = deal(remaining, args, key, round, recentIds, round === args.reroll ? notes : []);
      remaining = remaining.filter(s => s.id !== style.id);
    }
  }

  const reroll = `node pick-style.mjs --from ${key} --reroll ${args.reroll + 1}` +
    (args.mood.length ? ` --mood ${args.mood.join(',')}` : '') +
    (args.kinds.length ? ` --kinds ${args.kinds.join(',')}` : '') +
    (args.project ? ` --project ${args.project}` : '') +
    (args.data ? ` --data ${args.data}` : '');

  process.stdout.write(render({ key, reroll: args.reroll, style, notes, rerollCommand: reroll }, args.json));

  if (args.memory) {
    const pick = { ts: new Date().toISOString(), key, style: style.id };
    recordPick(files.global, pick, 32);
    if (files.local) recordPick(files.local, pick, 16);
  }
}

main();
