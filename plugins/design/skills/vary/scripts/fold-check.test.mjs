// node --test fold-check.test.mjs — tiny fixture pages; skipped when Playwright is absent.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dir = mkdtempSync(join(tmpdir(), 'fold-'));
const fold = (name, html, extra = []) => {
  const f = join(dir, name + '.html'); writeFileSync(f, html);
  return spawnSync('node', [join(here, 'fold-check.mjs'), f, '--out', join(dir, name), ...extra], { encoding: 'utf8', cwd: tmpdir() });
};
const noPw = /fold-check SKIP/.test(fold('probe', '<p>x</p>').stdout);
const shapes = n => Array.from({ length: n }, (_, i) => `<rect x="${(i * 37) % 1400}" y="${(i * 53) % 880}" width="40" height="30" fill="#${((i * 99991) % 0xffffff).toString(16).padStart(6, '0')}"/>`).join('');
const plate = n => `<svg viewBox="0 0 1400 400" width="1400" height="400" aria-hidden="true">${shapes(n)}</svg>`;
const scene = `<!doctype html><body style="margin:0"><svg viewBox="0 0 1440 900" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true">${shapes(160)}</svg>
<h1 style="position:relative;margin:120px 40px;font-size:60px">Fjalar Bar</h1><div style="margin-top:900px">${plate(10)}${plate(10)}${plate(10)}</div></body>`;
const textOnly = '<!doctype html><body style="margin:0"><h1 style="margin:120px 40px">Fjalar Bar</h1><p>Open daily.</p></body>';

test('text-only hero fails every scene metric', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('text', textOnly);
  assert.equal(r.status, 1, r.stdout);
  for (const id of ['coverage-desktop', 'detail', 'headline-in-scene', 'plates']) assert.match(r.stdout, new RegExp(`\\[FAIL\\] ${id}`));
});
test('full-bleed layered svg scene passes', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('scene', scene);
  assert.equal(r.status, 0, r.stdout);
  assert.match(r.stdout, /fold-check PASS/);
});
test('operate mode reports coverage as informational', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('op', scene, ['--mode', 'operate']);
  assert.match(r.stdout, /\[INFO\] coverage-desktop/);
});
test('missing target is a usage error', () => assert.equal(spawnSync('node', [join(here, 'fold-check.mjs')]).status, 2));
