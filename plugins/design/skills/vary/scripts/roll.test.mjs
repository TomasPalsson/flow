// node --test roll.test.mjs  (from vary/scripts, or by path)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFile, spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, mkdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const ROLL = join(here, 'roll.mjs');
const DOSSIER = join(here, 'fixtures', 'dossier.json');
const CONCEPTS = join(here, 'fixtures', 'concepts.json');
const worlds = JSON.parse(readFileSync(join(here, '..', 'data', 'worlds.json'), 'utf8'));
const concepts = JSON.parse(readFileSync(CONCEPTS, 'utf8'));
const tmp = mkdtempSync(join(tmpdir(), 'roll-test-'));
const env = { ...process.env, XDG_STATE_HOME: join(tmp, 'xdg') }; // never touch the real memory

const SECTORS = ['food-drink', 'hospitality-travel', 'retail-ecommerce', 'trades-construction', 'industrial-hardware',
  'engineering-technical', 'healthcare-clinical', 'finance-insurance', 'legal-public', 'kids-education',
  'culture-arts', 'music-events-nightlife', 'fashion-beauty-luxury', 'sports-fitness', 'media-publishing',
  'dev-tools', 'enterprise-saas', 'nature-outdoor', 'maritime-logistics', 'nonprofit-activism', 'wellness', 'gaming'];

const base = ['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', CONCEPTS, '--no-memory'];
const run = (args, opts = {}) => spawnSync('node', [ROLL, ...args], { encoding: 'utf8', env, ...opts });
const runJSON = args => { const r = run([...args, '--json']); assert.equal(r.status, 0, r.stderr); return JSON.parse(r.stdout); };
function runAsync(args) {
  return new Promise((res, rej) => execFile('node', [ROLL, ...args, '--json'], { env, maxBuffer: 1 << 24 }, (e, out, err) => (e ? rej(new Error(err || e.message)) : res(JSON.parse(out)))));
}
async function many(n, mk, conc = 8) {
  const out = new Array(n);
  let next = 0;
  await Promise.all(Array.from({ length: conc }, async () => { for (let i = next++; i < n; i = next++) out[i] = await mk(i); }));
  return out;
}
function withConcepts(name, mutate) {
  const c = JSON.parse(JSON.stringify(concepts)); const r = mutate(c) || c;
  const p = join(tmp, name); writeFileSync(p, JSON.stringify(r)); return p;
}

test('worlds.json: every non-trap world has sectors, all values from the enum', () => {
  for (const w of worlds) {
    assert.ok(Array.isArray(w.sectors) && Array.isArray(w.avoid_sectors), `${w.id}: sectors and avoid_sectors arrays`);
    if (w.trap) { assert.deepEqual([w.sectors, w.avoid_sectors], [[], []], `${w.id}: trap has empty arrays`); continue; }
    assert.ok(w.sectors.length >= 1, `${w.id}: at least one sector`);
    for (const s of [...w.sectors, ...w.avoid_sectors]) assert.ok(SECTORS.includes(s), `${w.id}: ${s} not in enum`);
    assert.deepEqual(w.sectors.filter(s => w.avoid_sectors.includes(s)), [], `${w.id}: a sector is both suited and avoided`);
  }
});

test('1. bad concepts exit 2 (too few, duplicate angle, unknown fact, unknown technique)', () => {
  const cases = {
    'few.json': c => c.slice(0, 3),
    'dup-angle.json': c => { c[1].angle = c[0].angle.toUpperCase(); },
    'bad-fact.json': c => { c[0].facts[2] = 'F999'; },
    'bad-technique.json': c => { c[0].devices[0].technique = 'wobble-art'; },
  };
  for (const [name, mutate] of Object.entries(cases)) {
    const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', withConcepts(name, mutate), '--no-memory', '--from', 'k1']);
    assert.equal(r.status, 2, `${name}: expected exit 2, got ${r.status}\n${r.stdout}`);
    assert.match(r.stderr, /--concepts/, name);
  }
});

test('2. --from K replays the same concept, device and world', () => {
  for (const k of ['alpha', 'bravo', 'charlie']) {
    const a = runJSON([...base, '--from', k]), b = runJSON([...base, '--from', k]);
    assert.deepEqual([a.concept, a.device, a.world], [b.concept, b.device, b.world]);
    assert.ok(a.concept && a.device && a.world);
  }
});

test('3. --reroll 1 never returns the round-0 concept', () => {
  for (let i = 0; i < 25; i++) {
    const a = runJSON([...base, '--from', `rr${i}`]), b = runJSON([...base, '--from', `rr${i}`, '--reroll', '1']);
    assert.notEqual(a.concept.id, b.concept.id, `key rr${i}`);
  }
});

test('4. --sector food-drink never deals a world whose avoid_sectors includes it (200 keys)', async () => {
  const avoided = new Set(worlds.filter(w => (w.avoid_sectors || []).includes('food-drink')).map(w => w.id));
  assert.ok(avoided.size >= 1, 'data must have at least one world avoiding food-drink');
  const mode = 'operate';
  const keys = Array.from({ length: 200 }, (_, i) => `s${i}`);
  const filtered = await many(200, i => runAsync(['--mode', mode, '--sector', 'food-drink', '--no-memory', '--from', keys[i]]));
  for (const r of filtered) assert.ok(!avoided.has(r.world), `dealt ${r.world}`);
  // not vacuous: without the filter the same keys do deal an avoided world
  const unfiltered = await many(200, i => runAsync(['--mode', mode, '--no-memory', '--from', keys[i]]));
  assert.ok(unfiltered.some(r => avoided.has(r.world)), 'control run never dealt an avoided world; test would be vacuous');
});

test('5. a hinted world is dealt more often than unhinted peers (500 keys, ratio > 1.8)', async () => {
  const hinted = 'bauhaus';
  const p = withConcepts('hint.json', c => { for (const x of c) x.world_hints = [hinted, 'de-stijl']; });
  const peers = worlds.filter(w => !w.trap && w.id !== hinted && w.id !== 'de-stijl' &&w.modes.includes('persuade') && w.decay === 'slow' && w.confidence === 'high').map(w => w.id);
  assert.ok(peers.length >= 5);
  const rolls = await many(500, i => runAsync(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', `h${i}`]));
  const count = id => rolls.filter(r => r.world === id).length;
  const hintedN = count(hinted);
  const peerMean = peers.reduce((s, id) => s + count(id), 0) / peers.length;
  assert.ok(peerMean > 0, 'peers never dealt');
  assert.ok(hintedN / peerMean > 1.8, `hinted ${hintedN} vs peer mean ${peerMean.toFixed(1)}`);
});

test('6. --concept-only prints the concept block and no WORLD line', () => {
  const r = run([...base, '--concept-only', '--from', 'co1']);
  assert.equal(r.status, 0, r.stderr);
  for (const label of ['CONCEPT:', 'FACTS:', 'FUNCTIONAL RESKIN:', 'SIGNATURE DEVICE:']) assert.match(r.stdout, new RegExp(`^${label}`, 'm'), label);
  assert.doesNotMatch(r.stdout, /^WORLD:/m);
});

test('7. without --concepts the roll still prints, with the subject-blind note', () => {
  const r = run(['--mode', 'persuade', '--no-memory', '--from', 'nc1']);
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /^WORLD:/m);
  assert.match(r.stdout, /^CONCEPT: none/m);
  assert.match(r.stdout, /no --concepts: subject-blind roll/);
});

test('8. recency: the last angle is dealt at most 25% of the time (400 keys, 4 concepts)', async () => {
  const last = concepts[0];
  const hits = await many(400, async i => {
    const proj = join(tmp, `proj-${i}`);
    mkdirSync(join(proj, '.vary'), { recursive: true });
    writeFileSync(join(proj, '.vary', 'recent.json'), JSON.stringify({ picks: [{ key: 'old', angle: last.angle }] }));
    const r = await runAsync(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', CONCEPTS, '--concept-only', '--project', proj, '--from', `r${i}`]);
    return r.concept === last.id;
  });
  const share = hits.filter(Boolean).length / 400;
  assert.ok(share <= 0.25, `recent angle dealt ${(share * 100).toFixed(1)}%`);
});

test('full contract carries CONCEPT, FACTS, SIGNATURE DEVICE, FIT and SIGNATURE GRAPHIC', () => {
  const r = run([...base, '--sector', 'food-drink', '--from', 'full1']);
  assert.equal(r.status, 0, r.stderr);
  for (const label of ['CONCEPT:', 'FACTS:', 'FUNCTIONAL RESKIN:', 'SIGNATURE DEVICE:', 'FIT: sector food-drink', 'SIGNATURE GRAPHIC:', 'WORLD:']) assert.ok(r.stdout.includes(label), label);
  assert.match(r.stdout, /\[ok\] world not in sector avoid list/);
  assert.match(r.stdout, /\[ok\] concept facts resolve in dossier/);
});

const COMMON = ['food-drink', 'hospitality-travel', 'retail-ecommerce', 'trades-construction', 'culture-arts', 'music-events-nightlife', 'nature-outdoor', 'wellness'];
test('common sectors list at least 8 suited worlds; food-drink has 8 in persuade mode', () => {
  for (const s of COMMON) assert.ok(worlds.filter(w => !w.trap && w.sectors.includes(s)).length >= 8, `${s}: fewer than 8 suited worlds`);
  assert.ok(worlds.filter(w => !w.trap && w.modes.includes('persuade') && w.sectors.includes('food-drink')).length >= 8);
});

test('9. hinted or sector-suited worlds only, except ~15% WILDCARD rounds (300 keys)', async () => {
  const rolls = await many(300, i => runAsync([...base, '--sector', 'food-drink', '--from', `p${i}`]));
  let wild = 0;
  for (const r of rolls) {
    const c = concepts.find(x => x.id === r.concept.id);
    const w = worlds.find(x => x.id === r.world);
    if (r.notes.some(n => /^WILDCARD/.test(n))) { wild++; continue; }
    assert.ok(c.world_hints.includes(w.id) || w.sectors.includes('food-drink'), `${r.concept.id} dealt ${w.id}, neither hinted nor food-drink-suited`);
    assert.ok(!w.avoid_sectors.includes('food-drink'), `${w.id} avoids food-drink`);
  }
  const share = wild / 300;
  assert.ok(share >= 0.09 && share <= 0.21, `WILDCARD share ${(share * 100).toFixed(1)}%`);
});

test('10. world_hints with fewer than 2 entries exits 2', () => {
  for (const [name, hints] of [['h0.json', []], ['h1.json', ['bauhaus']]]) {
    const p = withConcepts(name, c => { c[2].world_hints = hints; });
    const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', 'k1']);
    assert.equal(r.status, 2, name);
    assert.match(r.stderr, /world_hints/, name);
  }
});

test('11. --lock concept keeps the concept and changes the world across rerolls', () => {
  for (const id of ['kvold', 'matchday']) {
    const rolls = [0, 1, 2, 3].map(n => runJSON([...base, '--sector', 'food-drink', '--from', 'lk1', '--lock', `concept=${id}`, '--reroll', String(n)]));
    for (const r of rolls) assert.equal(r.concept.id, id);
    assert.equal(new Set(rolls.map(r => r.world)).size, 4, `worlds ${rolls.map(r => r.world)}`);
  }
  const bad = run([...base, '--from', 'lk1', '--lock', 'concept=nope']);
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /concept/);
});

test('12. dossier validation: facts missing, <12 facts, <4 kinds, missing source, sector mismatch exit 2', () => {
  const dossier = JSON.parse(readFileSync(DOSSIER, 'utf8'));
  const cases = {
    'no-facts': [d => { delete d.facts; }, /"facts" array is missing/],
    'few-facts': [d => { d.facts = d.facts.slice(0, 11); }, /at least 12 facts, got 11/],
    'few-kinds': [d => { d.facts.forEach((f, i) => { f.kind = ['product', 'price', 'hours'][i % 3]; }); }, /at least 4 distinct fact kinds, got 3/],
    'no-source': [d => { d.facts[4].source = ''; }, /fact F5 has no source/],
  };
  for (const [name, [mutate, re]] of Object.entries(cases)) {
    const d = JSON.parse(JSON.stringify(dossier)); mutate(d);
    const p = join(tmp, `d-${name}.json`); writeFileSync(p, JSON.stringify(d));
    const r = run(['--mode', 'persuade', '--dossier', p, '--concepts', CONCEPTS, '--no-memory', '--from', 'k1']);
    assert.equal(r.status, 2, `${name}: ${r.stdout}`);
    assert.match(r.stderr, re, name);
  }
  const mism = run([...base, '--sector', 'legal-public', '--from', 'k1']);
  assert.equal(mism.status, 2);
  assert.match(mism.stderr, /does not match --sector legal-public/);
  assert.equal(run([...base, '--sector', 'food-drink', '--from', 'k1']).status, 0);
});
