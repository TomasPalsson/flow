import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROLL = join(dirname(fileURLToPath(import.meta.url)), 'roll.mjs');
const tmp = mkdtempSync(join(tmpdir(), 'roll-test-'));
let counter = 0;

function mkSlices(count) {
  const dir = join(tmp, `run-${counter++}`);
  mkdirSync(dir, { recursive: true });
  const slices = Array.from({ length: count }, (_, i) => ({
    id: `s${i + 1}`, title: `Slice ${i + 1}`, packet: `packet ${i + 1}`,
    primary_files: [`src/f${i}.rs`, `src/g${i}.rs`], strength: 0.5,
  }));
  const p = join(dir, 'slices.json');
  writeFileSync(p, JSON.stringify({ slices }));
  return p;
}
const run = (...args) => spawnSync('node', [ROLL, ...args], { encoding: 'utf8' });
const roll = (slices, ...extra) => run('--slices', slices, '--no-memory', '--json', ...extra);
const parse = r => { assert.equal(r.status, 0, r.stderr); return JSON.parse(r.stdout); };

test('same key and inputs give byte-identical output', () => {
  const s = mkSlices(10);
  const a = roll(s, '--key', 'abc123'), b = roll(s, '--key', 'abc123');
  assert.equal(a.stdout, b.stdout);
  assert.equal(readFileSync(join(dirname(s), 'cells.json'), 'utf8'), a.stdout);
  assert.notEqual(roll(s, '--key', 'other').stdout, a.stdout);
});

test('subtract first, no repeats, wildcard last with a constraint', () => {
  const s = mkSlices(10);
  for (let k = 0; k < 40; k++) {
    const { cells } = parse(roll(s, '--key', `k${k}`));
    assert.equal(cells.length, 9);
    assert.equal(cells[0].lens.id, 'subtract');
    const uniq = f => { const v = cells.map(f); assert.equal(new Set(v).size, v.length); };
    uniq(c => c.lens.id); uniq(c => c.persona.id);
    const cons = cells.filter(c => c.constraint).map(c => c.constraint.id);
    assert.equal(new Set(cons).size, cons.length);
    assert.deepEqual(cells.slice(0, 8).map(c => c.persona.pool),
      ['role', 'outsider', 'role', 'outsider', 'role', 'outsider', 'role', 'outsider']);
    const w = cells[8];
    assert.equal(w.id, 'c9');
    assert.equal(w.wildcard, true);
    assert.equal(w.persona.pool, 'outsider');
    assert.ok(w.constraint);
    assert.ok(cells.slice(0, 8).every(c => !c.wildcard));
  }
});

test('constraints never meet a lens they contradict', () => {
  const s = mkSlices(10);
  for (let k = 0; k < 40; k++) {
    for (const c of parse(roll(s, '--key', `n${k}`)).cells) {
      if (c.lens.id === 'subtract') assert.ok(!c.constraint || !['one-month', 'net-negative'].includes(c.constraint.id));
      if (c.lens.id === 'make-visible') assert.ok(!c.constraint || c.constraint.id !== 'invisible');
    }
  }
});

test('lock fills cells in order and replaces the subtract default', () => {
  const s = mkSlices(10);
  const { cells } = parse(roll(s, '--key', 'x', '--lock', 'lens=borrow', '--lock', 'lens=unlock'));
  assert.equal(cells[0].lens.id, 'borrow');
  assert.equal(cells[1].lens.id, 'unlock');
  assert.equal(new Set(cells.map(c => c.lens.id)).size, cells.length);
});

test('bad args exit 2, bad data exit 3', () => {
  const s = mkSlices(5);
  assert.equal(roll(s, '--lock', 'lens=nope').status, 2);
  assert.equal(roll(s, '--bogus').status, 2);
  assert.equal(roll(s, '--cells', 'x').status, 2);
  assert.equal(parse(roll(s, '--cells', '30', '--key', 'k')).cells.length, 7); // n = max(slices, 6), plus wildcard
  assert.equal(run('--slices', s).status, 2); // memory on without --repo
  const empty = join(dirname(s), 'empty.json'); writeFileSync(empty, '{"slices":[]}');
  assert.equal(roll(empty).status, 3);
  const bad = join(dirname(s), 'bad.json'); writeFileSync(bad, '{nope');
  assert.equal(roll(bad).status, 3);
  assert.equal(roll(join(dirname(s), 'missing.json')).status, 3);
});

test('more cells than lenses allow exits 2', () => {
  assert.equal(roll(mkSlices(20), '--cells', '12').status, 2);
});

test('few slices are repeated up to 6 regular cells plus the wildcard, with distinct lenses', () => {
  for (const [count, key] of [[1, 'r'], [2, 'r'], [4, 'r'], [4, 'q']]) {
    const { cells } = parse(roll(mkSlices(count), '--key', key));
    assert.equal(cells.length, 7);
    assert.equal(new Set(cells.map(c => c.lens.id)).size, 7);
    assert.equal(cells.filter(c => c.wildcard).length, 1);
    assert.equal(new Set(cells.slice(0, 6).map(c => c.slice.id)).size, Math.min(count, 6));
  }
});

test('no slice appears more than 3 times among regular cells when avoidable', () => {
  const s = mkSlices(3);
  for (let k = 0; k < 40; k++) {
    const { cells } = parse(roll(s, '--key', `p${k}`));
    const counts = {};
    for (const c of cells.slice(0, 6)) counts[c.slice.id] = (counts[c.slice.id] || 0) + 1;
    assert.ok(Object.values(counts).every(v => v >= 1 && v <= 3), JSON.stringify(counts));
  }
});

test('--cells caps the dealt count: 10 slices with --cells 8 gives 8 plus the wildcard', () => {
  assert.equal(parse(roll(mkSlices(10), '--key', 'c', '--cells', '8')).cells.length, 9);
  assert.equal(parse(roll(mkSlices(4), '--key', 'c', '--cells', '4')).cells.length, 5);
});

test('repeat deals are byte-identical for the same key', () => {
  const s = mkSlices(2);
  assert.equal(roll(s, '--key', 'same').stdout, roll(s, '--key', 'same').stdout);
});

test('overlapping slices are avoided when another candidate remains', () => {
  const dir = join(tmp, 'overlap'); mkdirSync(dir);
  const mk = (id, files) => ({ id, title: id, packet: id, primary_files: files, strength: 0.5 });
  const p = join(dir, 'slices.json');
  writeFileSync(p, JSON.stringify([mk('a', ['x', 'y']), mk('b', ['x', 'y']), mk('c', ['p']), mk('d', ['q'])]));
  for (let k = 0; k < 30; k++) {
    const ids = parse(roll(p, '--key', `o${k}`, '--cells', '3')).cells.slice(0, 3).map(c => c.slice.id);
    assert.ok(!(ids.includes('a') && ids.includes('b')), ids.join());
  }
});

test('memory demotes a recently dealt lens over 200 keys', () => {
  const s = mkSlices(10);
  const seed = JSON.stringify({ runs: [{ key: 'old', repo: 'r', lenses: ['borrow'], personas: [], constraints: [], slices: [] }] });
  let fresh = 0, demoted = 0;
  for (let k = 0; k < 200; k++) {
    if (parse(roll(s, '--key', `d${k}`)).cells.some(c => c.lens.id === 'borrow')) fresh++;
    const mem = join(tmp, `mem-d-${k}`); mkdirSync(mem);
    writeFileSync(join(mem, 'recent.json'), seed); // fresh copy per key so runs do not feed each other
    const out = parse(run('--slices', s, '--repo', 'r', '--memory-dir', mem, '--json', '--key', `d${k}`));
    if (out.cells.some(c => c.lens.id === 'borrow')) demoted++;
  }
  assert.ok(fresh > 60, `baseline too low: ${fresh}`);
  assert.ok(demoted < fresh * 0.75, `demoted ${demoted} vs fresh ${fresh}`);
});

test('memory file is capped at 12 runs and records the deal', () => {
  const s = mkSlices(6);
  const mem = join(tmp, 'mem-cap');
  for (let k = 0; k < 15; k++) parse(run('--slices', s, '--repo', 'r', '--memory-dir', mem, '--key', `m${k}`, '--json'));
  const { runs } = JSON.parse(readFileSync(join(mem, 'recent.json'), 'utf8'));
  assert.equal(runs.length, 12);
  assert.equal(runs.at(-1).key, 'm14');
  assert.equal(runs.at(-1).repo, 'r');
  assert.equal(runs.at(-1).lenses[0], 'subtract');
});

test('corrupt memory exits 3 and --no-memory ignores it', () => {
  const s = mkSlices(6);
  const mem = join(tmp, 'mem-bad'); mkdirSync(mem);
  writeFileSync(join(mem, 'recent.json'), 'garbage');
  assert.equal(run('--slices', s, '--repo', 'r', '--memory-dir', mem).status, 3);
  assert.equal(roll(s, '--key', 'z', '--memory-dir', mem).status, 0);
});
