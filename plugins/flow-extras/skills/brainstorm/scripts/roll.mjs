#!/usr/bin/env node
/**
 * roll.mjs: external dice for the brainstorm skill.
 *
 * Deals generator "cells" (slice x lens x persona x constraint) with randomness from outside the
 * model, so every run differs and the model never picks. Seeded, so a run can be replayed.
 *
 * Usage:
 *   node roll.mjs --slices <run>/slices.json --repo <name> [--cells 8] [--key <hex>]
 *                 [--lock lens=<id>]... [--no-memory] [--memory-dir <dir>] [--json]
 *
 *   --slices      slices.json: an array, or {"slices":[...]}, of
 *                 {id, title, packet, primary_files:[], strength:number (missing counts as 0)}.
 *   --cells       cells to deal (default 8, max lens count - 1). Dealt n = min(cells, max(slices, 6)).
 *                 When n > slices, every slice is dealt once, then repeat cells pick slices again
 *                 (weighted by strength), each with a new lens (lenses never repeat in a run). No slice
 *                 appears more than 3 times among regular cells unless every slice already has (e.g. 1 slice).
 *                 One wildcard cell is appended.
 *   --key         fixed key (tests, replays with --no-memory); default 4 random bytes as hex.
 *   --lock        lens=<id>, repeatable; locks fill cells in order. Without a lock, cell 1 is "subtract".
 *   --repo        repo name; required when memory is on (slices of the last 3 runs of the same repo
 *                 are demoted).
 *   --memory-dir  default $XDG_STATE_HOME/brainstorm or ~/.local/state/brainstorm; file recent.json
 *                 keeps the last 12 runs. Lenses/personas/constraints of the last 8 runs are demoted.
 *   --no-memory   neither read nor write memory.
 *   --json        JSON on stdout (default: a readable table). cells.json is always written next to
 *                 slices.json.
 *
 * Exit codes: 0 ok, 1 check failed (reserved, unused), 2 bad arguments,
 *             3 data/IO error (unreadable or corrupt JSON, zero slices).
 * No dependencies. Node >= 18.
 */
import { createHash, randomBytes } from 'node:crypto';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { homedir } from 'node:os';

const here = dirname(fileURLToPath(import.meta.url));
const DATA = resolve(here, '..', 'data');

const BASE_TICKETS = 4;
const DEMOTED_TICKETS = 1;
const MEMORY_CAP = 12;
const AXIS_WINDOW = 8;
const SLICE_WINDOW = 3;
const MIN_CELLS = 6;
const MAX_PER_SLICE = 3;
const OVERLAP_LIMIT = 0.5;

function die(code, msg) { process.stderr.write(`roll: ${msg}\n`); process.exit(code); }

function parseArgs(argv) {
  const a = { locks: [], cells: 8, json: false, memory: true };
  for (let i = 0; i < argv.length; i++) {
    const k = argv[i];
    const take = () => { i++; if (argv[i] === undefined) die(2, `${k} needs a value`); return argv[i]; };
    switch (k) {
      case '--slices': a.slices = take(); break;
      case '--cells': {
        const v = take(); a.cells = Number(v);
        if (!/^\d+$/.test(v) || a.cells < 1) die(2, '--cells needs a positive integer');
        break;
      }
      case '--key': a.key = take(); if (!a.key) die(2, '--key must not be empty'); break;
      case '--repo': a.repo = take(); break;
      case '--lock': {
        const [lk, ...rest] = take().split('=');
        if (lk !== 'lens' || !rest.join('=')) die(2, '--lock must be lens=<id>');
        a.locks.push(rest.join('='));
        break;
      }
      case '--memory-dir': a.memoryDir = take(); break;
      case '--no-memory': a.memory = false; break;
      case '--json': a.json = true; break;
      case '-h': case '--help': a.help = true; break;
      default: die(2, `unknown argument ${k}`);
    }
  }
  return a;
}

function readJson(p, what) {
  try { return JSON.parse(readFileSync(p, 'utf8')); }
  catch (e) { die(3, `cannot read ${what} ${p}: ${e.message}`); }
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

// ---- inputs ----------------------------------------------------------------------------------
function loadSlices(p) {
  const raw = readJson(p, 'slices');
  const list = Array.isArray(raw) ? raw : raw && raw.slices;
  if (!Array.isArray(list)) die(3, `${p}: expected an array or {"slices":[...]}`);
  if (!list.length) die(3, `${p}: zero slices`);
  const seen = new Set();
  for (const [i, s] of list.entries()) {
    if (!s || typeof s.id !== 'string' || !s.id) die(3, `${p}: slice ${i} has no string id`);
    if (seen.has(s.id)) die(3, `${p}: duplicate slice id ${s.id}`);
    seen.add(s.id);
    if (s.primary_files !== undefined && !Array.isArray(s.primary_files)) die(3, `${p}: slice ${s.id} primary_files must be an array`);
    if (s.strength !== undefined && (typeof s.strength !== 'number' || !Number.isFinite(s.strength))) die(3, `${p}: slice ${s.id} strength must be a number`);
  }
  return list;
}

function loadData() {
  const lenses = readJson(join(DATA, 'lenses.json'), 'lenses').lenses;
  const pj = readJson(join(DATA, 'personas.json'), 'personas');
  const constraints = readJson(join(DATA, 'constraints.json'), 'constraints').constraints;
  if (![lenses, pj.role, pj.outsider, constraints].every(x => Array.isArray(x) && x.length)) die(3, 'data files are missing lenses, personas or constraints');
  return { lenses, role: pj.role, outsider: pj.outsider, constraints };
}

// ---- memory ----------------------------------------------------------------------------------
function memoryFile(dir) {
  const base = dir ? resolve(dir) : join(process.env.XDG_STATE_HOME || join(homedir(), '.local', 'state'), 'brainstorm');
  return join(base, 'recent.json');
}
function readRuns(file) {
  let text;
  try { text = readFileSync(file, 'utf8'); }
  catch (e) { if (e.code === 'ENOENT') return []; die(3, `cannot read memory ${file}: ${e.message}`); }
  try {
    const d = JSON.parse(text);
    if (!d || !Array.isArray(d.runs)) throw new Error('no runs array');
    return d.runs;
  } catch (e) { die(3, `corrupt memory ${file}: ${e.message}`); }
}
function writeRuns(file, runs) {
  try {
    mkdirSync(dirname(file), { recursive: true });
    writeFileSync(file, JSON.stringify({ runs: runs.slice(-MEMORY_CAP) }, null, 1));
  } catch (e) { die(3, `cannot write memory ${file}: ${e.message}`); }
}
const recentSet = (runs, field, window) => new Set(runs.slice(-window).flatMap(r => r[field] || []));

// ---- dealing ---------------------------------------------------------------------------------
function overlapRatio(a, b) {
  const A = a.primary_files || [], B = b.primary_files || [];
  if (!A.length || !B.length) return 0;
  const set = new Set(B);
  return A.filter(f => set.has(f)).length / Math.min(A.length, B.length);
}

function dealSlices(slices, n, key, demoted) {
  const weight = s => (demoted.has(s.id) ? DEMOTED_TICKETS : BASE_TICKETS) * (0.5 + (s.strength || 0));
  const out = [];
  let rest = slices.slice();
  for (let i = 0; i < Math.min(n, slices.length); i++) {
    let pool = rest.filter(s => !out.some(d => overlapRatio(s, d) >= OVERLAP_LIMIT));
    if (!pool.length) pool = rest;
    const pick = weightedPick(pool, pool.map(weight), key, `slice:${i}`);
    out.push(pick);
    rest = rest.filter(s => s.id !== pick.id);
  }
  for (let i = out.length; i < n; i++) { // repeat cells: same slice again, capped per slice when possible
    const count = s => out.filter(d => d.id === s.id).length;
    const open = slices.filter(s => count(s) < MAX_PER_SLICE);
    const pool = open.length ? open : slices;
    out.push(weightedPick(pool, pool.map(weight), key, `rep:${i}`));
  }
  return out;
}

function pickFrom(pool, demoted, key, salt) {
  return weightedPick(pool, pool.map(x => (demoted.has(x.id) ? DEMOTED_TICKETS : BASE_TICKETS)), key, salt);
}

function deal(slices, data, args, key, mem) {
  const n = Math.min(args.cells, Math.max(slices.length, MIN_CELLS));
  if (n + 1 > data.lenses.length) die(2, `${n} cells plus a wildcard need ${n + 1} distinct lenses; only ${data.lenses.length} exist`);
  for (const id of args.locks) if (!data.lenses.some(l => l.id === id)) die(2, `--lock lens=${id} is not a lens id; valid: ${data.lenses.map(l => l.id).join(', ')}`);
  if (new Set(args.locks).size !== args.locks.length) die(2, 'the same lens is locked twice');
  if (args.locks.length > n + 1) die(2, `${args.locks.length} locks but only ${n + 1} cells`);

  const dealt = dealSlices(slices, n, key, mem.slices);
  const usedLens = new Set(), usedPersona = new Set(), usedConstraint = new Set();
  const cells = [];

  const lensFor = (i, slice, any) => {
    const locked = i === 0 && !args.locks.length ? 'subtract' : args.locks[i];
    let lens;
    if (locked !== undefined) lens = data.lenses.find(l => l.id === locked);
    else {
      const free = data.lenses.filter(l => !usedLens.has(l.id));
      const fit = any ? free : free.filter(l => (l.pairs_with || []).includes('*') || (l.pairs_with || []).includes(slice.id));
      lens = pickFrom(fit.length ? fit : free, mem.lenses, key, `lens:${i}`);
    }
    if (!lens || usedLens.has(lens.id)) die(3, `no lens available for cell ${i + 1}`);
    usedLens.add(lens.id);
    return lens;
  };
  const personaFor = (i, poolName) => {
    const pool = data[poolName].filter(p => !usedPersona.has(p.id));
    if (!pool.length) die(3, `persona pool ${poolName} is exhausted at cell ${i + 1}`);
    const p = pickFrom(pool, mem.personas, key, `persona:${i}`);
    usedPersona.add(p.id);
    return { id: p.id, pool: poolName, line: p.line, moment: p.moment };
  };
  const constraintFor = (i, lens, forced) => {
    if (!forced && !(unit(key, `c?:${i}`) < 0.5)) return null;
    const pool = data.constraints.filter(c => !usedConstraint.has(c.id) && !(c.not_with || []).includes(lens.id));
    if (!pool.length) { if (forced) die(3, 'no constraint left for the wildcard cell'); return null; }
    const c = pickFrom(pool, mem.constraints, key, `constraint:${i}`);
    usedConstraint.add(c.id);
    return { id: c.id, text: c.text };
  };
  const sliceOut = s => ({ id: s.id, title: s.title, packet: s.packet, primary_files: s.primary_files || [] });
  const cell = (i, slice, lens, persona, constraint, wildcard) =>
    ({ id: `c${i + 1}`, slice: sliceOut(slice), lens: { id: lens.id, shape: lens.shape }, persona, constraint, wildcard });

  for (let i = 0; i < n; i++) {
    const lens = lensFor(i, dealt[i], false);
    const persona = personaFor(i, i % 2 === 0 ? 'role' : 'outsider');
    cells.push(cell(i, dealt[i], lens, persona, constraintFor(i, lens, false), false));
  }
  // wildcard: any slice (may repeat), any unused lens (a lock beyond n wins), outsider, forced constraint
  const wslice = weightedPick(slices, slices.map(() => 1), key, `slice:${n}`);
  const wlens = lensFor(n, wslice, true);
  const wpersona = personaFor(n, 'outsider');
  cells.push(cell(n, wslice, wlens, wpersona, constraintFor(n, wlens, true), true));
  return cells;
}

function table(r) {
  const rows = r.cells.map(c => [
    `${c.id}${c.wildcard ? ' (wildcard)' : ''}`,
    `slice: ${c.slice.id} - ${c.slice.title ?? ''}`,
    `lens: ${c.lens.id}`,
    `persona: ${c.persona.id} (${c.persona.pool})`,
    `constraint: ${c.constraint ? `${c.constraint.id} - ${c.constraint.text}` : 'none'}`,
  ].join('\n  '));
  return `KEY: ${r.key}\n\n${rows.join('\n\n')}\n`;
}

function main() {
  const args = parseArgs(process.argv.slice(2));
  if (args.help) {
    process.stdout.write('usage: roll.mjs --slices <slices.json> --repo <name> [--cells n] [--key hex] [--lock lens=id]... [--no-memory] [--memory-dir dir] [--json]\n');
    return;
  }
  if (!args.slices) die(2, '--slices is required');
  if (args.memory && !args.repo) die(2, '--repo is required unless --no-memory is given');

  const slicesPath = resolve(args.slices);
  const slices = loadSlices(slicesPath);
  const data = loadData();
  const key = args.key || randomBytes(4).toString('hex');

  const file = args.memory ? memoryFile(args.memoryDir) : null;
  const runs = file ? readRuns(file) : [];
  const sameRepo = runs.filter(r => r.repo === args.repo);
  const mem = {
    lenses: recentSet(runs, 'lenses', AXIS_WINDOW),
    personas: recentSet(runs, 'personas', AXIS_WINDOW),
    constraints: recentSet(runs, 'constraints', AXIS_WINDOW),
    slices: recentSet(sameRepo, 'slices', SLICE_WINDOW),
  };

  const cells = deal(slices, data, args, key, mem);
  const result = { key, cells };
  const json = JSON.stringify(result, null, 2) + '\n';
  try { writeFileSync(join(dirname(slicesPath), 'cells.json'), json); }
  catch (e) { die(3, `cannot write cells.json: ${e.message}`); }
  process.stdout.write(args.json ? json : table(result));

  if (file) {
    runs.push({
      key, repo: args.repo,
      lenses: cells.map(c => c.lens.id),
      personas: cells.map(c => c.persona.id),
      constraints: cells.filter(c => c.constraint).map(c => c.constraint.id),
      slices: [...new Set(cells.map(c => c.slice.id))],
    });
    writeRuns(file, runs);
  }
}

main();
