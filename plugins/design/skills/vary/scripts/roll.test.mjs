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
  const p = withConcepts('hint.json', c => { for (const x of c) { x.temperament = 'avant-garde'; x.world_hints = [hinted, 'de-stijl']; } });
  const peers = worlds.filter(w => !w.trap && w.id !== hinted && w.id !== 'de-stijl' && w.temperaments.includes('avant-garde') && w.modes.includes('persuade') && w.decay === 'slow' && w.confidence === 'high').map(w => w.id);
  assert.ok(peers.length >= 3);
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

test('9. hinted worlds only, except ~5% WILDCARD rounds (300 keys)', async () => {
  const rolls = await many(300, i => runAsync([...base, '--sector', 'food-drink', '--from', `p${i}`]));
  let wild = 0;
  for (const r of rolls) {
    const c = concepts.find(x => x.id === r.concept.id);
    const w = worlds.find(x => x.id === r.world);
    if (r.notes.some(n => /^WILDCARD/.test(n))) { wild++; continue; }
    assert.ok(c.world_hints.includes(w.id), `${r.concept.id} dealt ${w.id}, not hinted`);
    assert.ok(!w.avoid_sectors.includes('food-drink'), `${w.id} avoids food-drink`);
  }
  const share = wild / 300;
  assert.ok(share >= 0.02 && share <= 0.10, `WILDCARD share ${(share * 100).toFixed(1)}%`);
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

const TEMPERAMENTS = ['heritage-craft', 'warm-domestic', 'civic-calm', 'technical-precise', 'playful-bright', 'natural-raw', 'nocturnal-social', 'avant-garde'];
test('temperaments: every world lists 2-4 valid ones, every temperament has at least 6 non-trap worlds', () => {
  for (const w of worlds) {
    assert.ok(Array.isArray(w.temperaments) && w.temperaments.length >= 2 && w.temperaments.length <= 4, `${w.id}: 2-4 temperaments`);
    for (const t of w.temperaments) assert.ok(TEMPERAMENTS.includes(t), `${w.id}: ${t} not in enum`);
  }
  for (const t of TEMPERAMENTS) assert.ok(worlds.filter(w => !w.trap && w.temperaments.includes(t)).length >= 6, `${t}: fewer than 6 worlds`);
});

test('temperaments: a concept without a valid temperament exits 2', () => {
  for (const [name, mutate] of Object.entries({ 'no-temp.json': c => { delete c[0].temperament; }, 'bad-temp.json': c => { c[1].temperament = 'grumpy'; } })) {
    const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', withConcepts(name, mutate), '--no-memory', '--from', 'k1']);
    assert.equal(r.status, 2, name);
    assert.match(r.stderr, /temperament must be one of/, name);
  }
});

test('temperaments: heritage-craft concepts never deal bauhaus, de-stijl, memphis or y2k worlds (300 keys, wildcards included)', async () => {
  const p = withConcepts('heritage.json', c => { c.forEach(x => { x.temperament = 'heritage-craft'; x.world_hints = ['letterpress-wood-type', 'vintage-analog']; }); });
  const rolls = await many(300, i => runAsync(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', `h${i}`, ...(i % 2 ? ['--sector', 'food-drink'] : [])]));
  let wild = 0;
  for (const r of rolls) {
    if (r.notes.some(n => /^WILDCARD/.test(n))) wild++;
    const w = worlds.find(x => x.id === r.world);
    assert.ok(w.temperaments.includes('heritage-craft'), `${r.world} dealt to a heritage-craft concept`);
    assert.ok(!/^(bauhaus|de-stijl|memphis|y2k)/.test(r.world), r.world);
  }
  assert.ok(wild > 0, 'the wildcard path was exercised');
});

test('hints: a concept whose world_hints fit none of its temperament exits 2', () => {
  const p = withConcepts('nofit.json', c => { c[0].temperament = 'heritage-craft'; c[0].world_hints = ['bauhaus', 'de-stijl']; });
  const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', 'k1']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /no world_hint fits temperament heritage-craft/);
});

test('temperaments: bauhaus, de-stijl, constructivist, memphis, risograph and travel-poster worlds never serve civic-calm or warm-domestic loudly', () => {
  const loud = ['bauhaus', 'de-stijl', 'constructivist', 'memphis', 'risograph-zine', 'mid-century-travel-poster'];
  for (const id of loud) {
    const t = worlds.find(w => w.id === id).temperaments;
    assert.ok(!t.includes('civic-calm') && !t.includes('warm-domestic'), `${id}: ${t}`);
  }
});

test('avant-garde worlds are never dealt to a non-avant-garde concept on any path: hints, sector fit or wildcard (sectors x 150 keys)', async () => {
  const p = withConcepts('wild.json', c => { c.forEach(x => { x.temperament = 'playful-bright'; x.world_hints = ['childrens-book', 'corporate-memphis']; }); });
  let wild = 0;
  for (const sector of [null, 'kids-education', 'maritime-logistics', 'wellness', 'food-drink']) {
    const dj = JSON.parse(readFileSync(DOSSIER, 'utf8')); if (sector) dj.sector = sector;
    const dp = join(tmp, `d-${sector}.json`); writeFileSync(dp, JSON.stringify(dj));
    const rolls = await many(150, i => runAsync(['--mode', 'persuade', '--dossier', dp, '--concepts', p, '--no-memory', '--from', `w${sector}${i}`, ...(sector ? ['--sector', sector] : [])]));
    for (const r of rolls) {
      if (r.notes.some(n => /^WILDCARD/.test(n))) wild++;
      assert.ok(!worlds.find(w => w.id === r.world).temperaments.includes('avant-garde'), `${r.world} dealt (sector ${sector})`);
    }
  }
  assert.ok(wild > 3, `only ${wild} wildcard rounds`);
});

// ---- hero treatment (generality spec D) ----
function withDossier(name, mutate) {
  const d = JSON.parse(readFileSync(DOSSIER, 'utf8')); mutate(d);
  const p = join(tmp, name); writeFileSync(p, JSON.stringify(d)); return p;
}
const PHONE_EXCLUDED = ['dense-console', 'spec-sheet', 'split-screen', 'sidebar-tool', 'cardless-table', 'asymmetric-offset', 'scroll-narrative', 'zine-collage'];
const withTypographyDirective = d => { d.directives = [{ text: 'plain, black and white, no illustrations, Swiss style', source: 'user brief', locks: ['treatment=typography', 'world=swiss-international', 'strategy=ink-on-paper'] }]; };

test('treatment: a photography concept with no usable photo asset exits 2', () => {
  const p = withConcepts('photo-nogrounds.json', c => { c[0].treatment = 'photography'; c[0].devices.push({ technique: 'annotated-photo', what: 'the shopfront photographed' }); });
  const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', 'k1']);
  assert.equal(r.status, 2, r.stdout);
  assert.match(r.stderr, /photography needs at least one dossier\.assets/);
  const ok = withDossier('photo-assets.json', d => { d.assets = [{ path: 'assets/front.jpg', kind: 'photo', usable: true }]; });
  assert.equal(run(['--mode', 'persuade', '--dossier', ok, '--concepts', p, '--no-memory', '--from', 'k1']).status, 0);
});

test('treatment: an unknown treatment, or one with no device that maps to it, exits 2', () => {
  assert.equal(run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', withConcepts('t-bad.json', c => { c[0].treatment = 'wobble'; }), '--no-memory']).status, 2);
  const r = run(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', withConcepts('t-nomap.json', c => { c[0].treatment = 'data-visual'; }), '--no-memory']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /needs at least one device whose technique maps to it/);
});

test('treatment: a dossier directive treatment=typography makes every reroll 0..5 print HERO TREATMENT: typography', () => {
  const dp = withDossier('d-typo.json', withTypographyDirective);
  for (let n = 0; n <= 5; n++) {
    const r = run(['--mode', 'persuade', '--dossier', dp, '--concepts', CONCEPTS, '--no-memory', '--from', 'dir1', '--reroll', String(n)]);
    assert.equal(r.status, 0, r.stderr);
    assert.match(r.stdout, /^HERO TREATMENT: typography — /m, `reroll ${n}`);
    assert.match(r.stdout, /^DIRECTIVES: "plain, black and white, no illustrations, Swiss style"/m);
    assert.match(r.stdout, /^WORLD: swiss-international/m, `reroll ${n}`);
    assert.match(r.stdout, /^STRATEGY: ink-on-paper/m);
  }
});

test('treatment: a CLI lock that conflicts with a directive lock exits 2', () => {
  const dp = withDossier('d-typo2.json', withTypographyDirective);
  const r = run(['--mode', 'persuade', '--dossier', dp, '--concepts', CONCEPTS, '--no-memory', '--from', 'k1', '--lock', 'treatment=scene']);
  assert.equal(r.status, 2);
  assert.match(r.stderr, /directive "plain, black and white, no illustrations, Swiss style" locks treatment=typography; the CLI asked scene/);
  assert.equal(run(['--mode', 'persuade', '--dossier', dp, '--concepts', CONCEPTS, '--no-memory', '--from', 'k1', '--lock', 'treatment=typography']).status, 0);
});

test('canon: --platform ios --mode persuade never prints a phone-excluded archetype (and web persuade stays split-screen)', () => {
  for (const mode of ['persuade', 'operate', 'read', 'experience']) {
    for (const k of ['c1', 'c2']) {
      const r = runJSON(['--mode', mode, '--platform', 'ios', '--canon', '--no-memory', '--from', k]);
      assert.ok(!PHONE_EXCLUDED.includes(r.archetype), `${mode}: ${r.archetype}`);
      assert.match(r.contract.join('\n'), /^HERO TREATMENT: (typography|utility) — /m);
    }
  }
  assert.match(run(['--mode', 'persuade', '--platform', 'ios', '--canon', '--no-memory', '--from', 'c1']).stdout, /^ARCHETYPE: poster/m);
  assert.equal(runJSON(['--mode', 'persuade', '--canon', '--no-memory', '--from', 'c1']).archetype, 'split-screen');
});

test('treatment: --mode operate with scene-only concepts falls back to utility and says so', () => {
  const p = withConcepts('scene-only.json', c => { for (const x of c) x.treatment = 'scene'; });
  const rolls = [0, 1, 2].map(n => runJSON(['--mode', 'operate', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', 'op1', '--reroll', String(n)]));
  for (const r of rolls) {
    assert.equal(r.treatment, 'utility');
    assert.ok(r.notes.some(n => /treatment scene is not allowed for mode operate; fell back to utility/.test(n)), r.notes.join('|'));
    assert.match(r.contract.join('\n'), /^HERO TREATMENT: utility — /m);
    assert.match(r.contract.join('\n'), /details: icons, numerals, empty states/);
  }
});

test('treatment: the RULE line mentions the art brief only for scene and pattern', () => {
  const rule = args => run(args).stdout.split('\n').find(l => l.startsWith('RULE:'));
  const lock = t => rule([...base, '--from', 'rl1', '--lock', `treatment=${t}`]);
  assert.match(lock('scene'), /art brief/);
  assert.match(lock('pattern'), /art brief/);
  for (const t of ['photography', 'product-ui', 'typography', 'data-visual', 'utility']) assert.doesNotMatch(lock(t), /art brief/, t);
  assert.doesNotMatch(rule(['--mode', 'operate', '--canon', '--no-memory', '--from', 'rl2']), /art brief/);
});

test('treatment: a concept with no treatment follows the dealt device technique (scene for a drawing technique)', () => {
  const p = withConcepts('drawn.json', c => { for (const x of c) { x.devices = [{ technique: 'seeded-illustration', what: 'x' }, { technique: 'procedural-subject', what: 'y' }]; delete x.treatment; } });
  for (const k of ['a', 'b', 'c']) assert.equal(runJSON(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--from', k]).treatment, 'scene');
});

test('treatment: --lock device wins over the weighted device pick', () => {
  const r = runJSON([...base, '--from', 'dv1', '--lock', 'concept=kvold', '--lock', 'device=material-texture']);
  assert.equal(r.device.technique, 'material-texture');
  assert.equal(run([...base, '--lock', 'device=wobble']).status, 2);
});

test('canon with --concepts never pairs a drawn treatment with split-screen', () => {
  for (let n = 0; n <= 5; n++) {
    const r = runJSON(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', CONCEPTS, '--no-memory', '--from', 'b', '--canon', '--reroll', String(n)]);
    assert.equal(r.archetype, 'split-screen');
    assert.doesNotMatch(r.treatment, /^(scene|pattern)$/, `reroll ${n}: ${r.treatment}`);
  }
});

test('typography lock deals only a typographic device, and black-and-white drops the accent and seed tint', () => {
  const dp = withDossier('d-typo3.json', withTypographyDirective);
  for (let n = 0; n <= 5; n++) {
    for (const extra of [[], ['--lock', 'concept=street']]) {
      const r = runJSON(['--mode', 'persuade', '--dossier', dp, '--concepts', CONCEPTS, '--no-memory', '--from', 'b', '--reroll', String(n), ...extra]);
      assert.equal(r.treatment, 'typography');
      assert.equal(r.device.technique, 'typographic', `reroll ${n}: ${r.device.technique}`);
      const c = r.contract.join('\n');
      assert.doesNotMatch(c, /ONE saturated accent/);
      assert.match(c, /^PALETTE SEED: none — black and white by directive/m);
      assert.equal(r.seed, null);
    }
  }
});

test('product-ui: grounded by dossier.product.screens, still rejected when empty', () => {
  const p = withConcepts('pui.json', c => { c[0].treatment = 'product-ui'; c[0].devices.push({ technique: 'product-capture', what: 'the rota grid rebuilt in HTML' }); });
  const args = d => ['--mode', 'persuade', '--dossier', d, '--concepts', p, '--no-memory', '--from', 'k1'];
  assert.equal(run(args(withDossier('pui-screens.json', d => { d.product = { screens: ['rota grid'] }; }))).status, 0);
  const bad = run(args(withDossier('pui-empty.json', d => { d.product = { screens: [] }; })));
  assert.equal(bad.status, 2);
  assert.match(bad.stderr, /screenshot.*app_path.*screens/);
});

test('world pool: hints only (sector-suited worlds excluded) except WILDCARD rounds (200 rounds)', async () => {
  const hints = ['letterpress-wood-type', 'vintage-analog'];
  const p = withConcepts('hintonly.json', c => { for (const x of c) { x.world_hints = hints; x.temperament = 'nocturnal-social'; x.treatment = 'scene'; } });
  const others = worlds.filter(w => !w.trap && !hints.includes(w.id) && w.sectors.includes('food-drink'));
  assert.ok(others.length >= 1);
  const rolls = await many(200, i => runAsync(['--mode', 'persuade', '--dossier', DOSSIER, '--concepts', p, '--no-memory', '--sector', 'food-drink', '--from', `ho${i}`]));
  for (const r of rolls) {
    if (r.notes.some(n => /^WILDCARD/.test(n))) continue;
    assert.ok(hints.includes(r.world), `dealt ${r.world}`);
  }
});

test('WILDCARD never fires for a product-ui concept or in operate mode (200 rounds each)', async () => {
  const pui = withConcepts('pui-wild.json', c => { for (const x of c) { x.treatment = 'product-ui'; x.devices.push({ technique: 'product-capture', what: 'the rota grid' }); } });
  const dsc = withDossier('pui-wild-d.json', d => { d.product = { screens: ['rota grid'] }; });
  const a = await many(200, i => runAsync(['--mode', 'persuade', '--dossier', dsc, '--concepts', pui, '--no-memory', '--from', `wp${i}`]));
  const sc = withConcepts('scene-wild.json', c => { for (const x of c) x.treatment = 'scene'; });
  const b = await many(200, i => runAsync(['--mode', 'operate', '--dossier', DOSSIER, '--concepts', sc, '--no-memory', '--from', `wo${i}`]));
  for (const r of [...a, ...b]) assert.ok(!r.notes.some(n => /^WILDCARD/.test(n)), r.notes.join('|'));
});
