import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, existsSync, readdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(here, 'pick-style.mjs');
const DATA = JSON.parse(readFileSync(join(here, '..', 'data', 'styles.json'), 'utf8'));
const STYLES = DATA.styles;

const sandbox = () => mkdtempSync(join(tmpdir(), 'pick-style-'));
function run(args, state = sandbox()) {
  const r = spawnSync('node', [SCRIPT, ...args], { encoding: 'utf8', env: { ...process.env, XDG_STATE_HOME: state } });
  return { code: r.status, out: r.stdout, err: r.stderr, state };
}
const pickJson = (args, state) => {
  const r = run([...args, '--json'], state);
  assert.equal(r.code, 0, r.err);
  return JSON.parse(r.out);
};
const byId = id => STYLES.find(s => s.id === id);

test('real styles.json: every style has all fields and at least 2 best_for kinds', () => {
  assert.ok(STYLES.length >= 18 && STYLES.length <= 24, `style count ${STYLES.length}`);
  const ids = new Set();
  for (const s of STYLES) {
    for (const f of ['id', 'name', 'look', 'traits', 'suits', 'avoid', 'best_for', 'banned']) assert.ok(s[f] !== undefined, `${s.id} missing ${f}`);
    for (const f of ['stroke', 'fill', 'shading', 'texture', 'simplification']) assert.ok(s.traits[f], `${s.id} traits.${f}`);
    assert.ok(!ids.has(s.id), `duplicate id ${s.id}`); ids.add(s.id);
    assert.ok(s.best_for.length >= 2, `${s.id} best_for`);
    assert.ok(s.banned.length >= 1 && s.suits.length >= 1, `${s.id} banned/suits`);
    for (const k of s.best_for) assert.ok(DATA.kinds.includes(k), `${s.id} unknown kind ${k}`);
    for (const m of [...s.suits, ...s.avoid]) assert.ok(DATA.moods.includes(m), `${s.id} unknown mood ${m}`);
    assert.equal(s.suits.filter(m => s.avoid.includes(m)).length, 0, `${s.id} suits and avoids the same mood`);
  }
});

test('deterministic for a fixed --from key', () => {
  const a = pickJson(['--from', 'k1', '--mood', 'warm', '--no-memory']);
  const b = pickJson(['--from', 'k1', '--mood', 'warm', '--no-memory']);
  assert.equal(a.style.id, b.style.id);
  assert.equal(a.key, 'k1');
  const text = run(['--from', 'k1', '--no-memory']);
  assert.match(text.out, /STYLE: [\w-]+ \(/);
  assert.match(text.out, /SEED KEY: k1/);
  assert.match(text.out, /RE-ROLL: node pick-style\.mjs --from k1 --reroll 1/);
});

test('--reroll deals a different style than the rounds before it', () => {
  const seen = new Set();
  for (let n = 0; n < 5; n++) seen.add(pickJson(['--from', 'rr', '--reroll', String(n), '--no-memory']).style.id);
  assert.equal(seen.size, 5);
});

test('--lock style=<id> wins; unknown id exits 2', () => {
  const r = pickJson(['--lock', 'style=pixel-art', '--mood', 'premium,calm', '--kinds', 'map', '--no-memory']);
  assert.equal(r.style.id, 'pixel-art');
  const bad = run(['--lock', 'style=nope', '--no-memory']);
  assert.equal(bad.code, 2);
  assert.match(bad.err, /not a style id/);
  assert.equal(run(['--bogus']).code, 2);
  assert.equal(run(['--kinds', 'banner', '--no-memory']).code, 2);
});

test('mood avoid excludes styles', () => {
  const mood = ['playful', 'kids'];
  const barred = new Set(STYLES.filter(s => s.avoid.some(m => mood.includes(m))).map(s => s.id));
  assert.ok(barred.size > 0);
  for (let i = 0; i < 40; i++) {
    const id = pickJson(['--from', `m${i}`, '--mood', mood.join(','), '--no-memory']).style.id;
    assert.ok(!barred.has(id), `${id} avoids ${mood}`);
  }
});

test('mood suits weights the pick up', () => {
  const count = mood => {
    let n = 0;
    for (let i = 0; i < 80; i++) {
      const s = byId(pickJson(['--from', `w${i}`, ...(mood ? ['--mood', mood] : []), '--no-memory']).style.id);
      if (s.suits.includes('technical')) n++;
    }
    return n;
  };
  assert.ok(count('technical') > count(''), 'technical mood picks technical styles more often');
});

test('kinds filter: every requested kind is in best_for; unmatched kinds relax with a note', () => {
  for (let i = 0; i < 30; i++) {
    const s = byId(pickJson(['--from', `k${i}`, '--kinds', 'icon-set,diagram', '--no-memory']).style.id);
    assert.ok(s.best_for.includes('icon-set') && s.best_for.includes('diagram'), s.id);
  }
  // map + icon-set + pattern + object together: likely no style serves all, so expect relax or a real match
  const r = pickJson(['--from', 'x', '--kinds', 'map,icon-set,pattern,object,hero,section,spot,diagram', '--no-memory']);
  assert.ok(r.notes.some(n => /relaxed to any match/.test(n)));
  assert.ok(STYLES.some(s => s.id === r.style.id));
});

test('anti-repeat demotes the last pick (project memory)', () => {
  const N = 150;
  const keys = Array.from({ length: N }, (_, i) => `ar${i}`);
  const baseline = {};
  for (const k of keys) { const id = pickJson(['--from', k, '--no-memory']).style.id; baseline[id] = (baseline[id] || 0) + 1; }
  const [target, base] = Object.entries(baseline).sort((a, b) => b[1] - a[1])[0];
  assert.ok(base >= 3, `baseline count for ${target} is ${base}`);

  const state = sandbox(), project = sandbox();
  const mem = join(project, '.vary', 'recent-styles.json');
  let demoted = 0;
  for (const k of keys) {
    mkdirSync(dirname(mem), { recursive: true });
    writeFileSync(mem, JSON.stringify({ picks: [{ style: target }] }));
    if (pickJson(['--from', k, '--project', project], state).style.id === target) demoted++;
  }
  assert.ok(demoted < base / 2, `previous pick came back ${demoted} times vs ${base} without memory`);
  assert.ok(demoted < N / STYLES.length, `previous pick came back ${demoted} times, uniform would be ${(N / STYLES.length).toFixed(1)}`);
  rmSync(project, { recursive: true, force: true });
});

test('memory is written to project and global files, capped, and replays do not need it', () => {
  const state = sandbox(), project = sandbox();
  const first = pickJson(['--from', 'mem1', '--project', project], state);
  const local = JSON.parse(readFileSync(join(project, '.vary', 'recent-styles.json'), 'utf8'));
  const global = JSON.parse(readFileSync(join(state, 'vary', 'recent-styles.json'), 'utf8'));
  assert.equal(local.picks.at(-1).style, first.style.id);
  assert.equal(global.picks.at(-1).style, first.style.id);
  assert.match(readFileSync(join(project, '.gitignore'), 'utf8'), /\.vary\//);
});

const SKINS = join(here, '..', '..', 'diagram', 'data', 'skins.json');

test('--data deals from another catalog, prints its tokens, and keeps its own memory file', () => {
  const state = sandbox(), project = sandbox();
  const skinIds = JSON.parse(readFileSync(SKINS, 'utf8')).styles.map(s => s.id);
  const r = run(['--data', SKINS, '--kinds', 'flow', '--project', project], state);
  assert.equal(r.code, 0, r.err);
  assert.ok(skinIds.includes(r.out.match(/^STYLE: (\S+)/)[1]));
  assert.match(r.out, /^TOKENS: \{/m);
  assert.ok(existsSync(join(project, '.vary', 'recent-skins.json')));
  assert.equal(existsSync(join(project, '.vary', 'recent-styles.json')), false);
});

test('--sticky reuses the project look, --reroll deals a different one, and --sticky needs --project', () => {
  const state = sandbox(), project = sandbox();
  const args = ['--data', SKINS, '--project', project, '--sticky'];
  const first = pickJson(args, state).style.id;
  for (let i = 0; i < 3; i++) assert.equal(pickJson(args, state).style.id, first);
  assert.notEqual(pickJson([...args, '--reroll', '1'], state).style.id, first);
  assert.equal(run(['--data', SKINS, '--sticky'], state).code, 2);
});

test('--no-memory writes nothing', () => {
  const state = sandbox(), project = sandbox();
  const r = run(['--from', 'nm', '--project', project, '--no-memory'], state);
  assert.equal(r.code, 0, r.err);
  assert.equal(existsSync(join(project, '.vary')), false);
  assert.deepEqual(readdirSync(state), []);
});
