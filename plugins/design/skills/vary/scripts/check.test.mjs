// node --test check.test.mjs — one passing and one failing fixture per project-specificity check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const run = dir => {
  const r = spawnSync('node', [join(here, 'check.mjs'), join(here, 'fixtures/check', dir), '--json'], { encoding: 'utf8' });
  return Object.fromEntries(JSON.parse(r.stdout).checks.map(c => [c.id, c.status]));
};

test('pass fixture passes every new check', () => {
  const s = run('pass');
  for (const id of ['concept-contract', 'facts-in-build', 'bespoke-graphics', 'seeded-art', 'svg-a11y']) assert.equal(s[id], 'PASS', id);
});
test('unfilled SIGNATURE GRAPHIC fails concept-contract', () => assert.equal(run('fail-concept')['concept-contract'], 'FAIL'));
test('cited facts absent from source fail facts-in-build', () => assert.equal(run('fail-facts')['facts-in-build'], 'FAIL'));
test('persuade build with no drawing source fails bespoke-graphics', () => assert.equal(run('fail-graphics')['bespoke-graphics'], 'FAIL'));
test('Math.random in SVG-emitting code warns seeded-art', () => assert.equal(run('fail-seeded')['seeded-art'], 'WARN'));
test('unlabelled large SVG warns svg-a11y', () => assert.equal(run('fail-a11y')['svg-a11y'], 'WARN'));
test('photography treatment with an img hero and no svg passes bespoke-graphics and photo-fidelity', () => {
  const s = run('pass-photography');
  assert.equal(s['bespoke-graphics'], 'PASS');
  assert.equal(s['photo-fidelity'], 'PASS');
  assert.equal(s['concept-contract'], 'PASS');
});
test('typography treatment gives bespoke-graphics INFO, never FAIL', () => assert.equal(run('typography')['bespoke-graphics'], 'INFO'));
test('WORLD: system: counts as an exempt world and passes concept-contract', () => assert.equal(run('system')['concept-contract'], 'PASS'));
test('backdrop-filter and drop-shadow on a photography page do not trip photo-fidelity', () => assert.equal(run('photo-glass')['photo-fidelity'], 'PASS'));
test('native platform reads .swift sources and reports fold N/A', () => {
  const s = run('native');
  assert.equal(s.fold, 'N/A');
  assert.equal(s['concept-contract'], 'PASS');
});

const microcopy = dir => {
  const r = spawnSync('node', [join(here, 'check.mjs'), join(here, 'fixtures/check', dir), '--json'], { encoding: 'utf8' });
  return JSON.parse(r.stdout).checks.find(c => c.id === 'microcopy-tells');
};
test('microcopy tells: each of the four detectors fires and stays WARN, never FAIL', () => {
  const c = microcopy('microcopy-tells');
  assert.equal(c.status, 'WARN');
  const tells = c.evidence.map(e => e.tell).join('|');
  assert.match(tells, /dot-separated meta string/);
  assert.match(tells, /WORD — fragment label/);
  assert.match(tells, /trailing arrow/);
  assert.match(tells, /01\/02\/03 markers/);
});
test('microcopy tells: footer dots, breadcrumb dots, <ol> and [data-sequence] numbering stay clean', () => {
  assert.equal(microcopy('microcopy-clean').status, 'PASS');
});
test('no near-black colour detector exists (dark modes legitimately use tinted near-black)', () => {
  assert.doesNotMatch(readFileSync(join(here, 'check.mjs'), 'utf8'), /#0b0b0b|#111\b/i);
});
