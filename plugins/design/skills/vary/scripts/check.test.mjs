// node --test check.test.mjs — one passing and one failing fixture per project-specificity check.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
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
