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

const tail = `<div style="margin-top:900px">${plate(10)}${plate(10)}${plate(10)}</div>`;
const sceneWith = extra => `<!doctype html><body style="margin:0"><svg viewBox="0 0 1440 900" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true">${shapes(160)}</svg>${extra}${tail}</body>`;

test('two overlapping text elements are a collision and both texts are printed', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('collide', sceneWith('<h1 style="position:absolute;left:40px;top:100px;font-size:60px;margin:0">Fjalar Bar</h1><p style="position:absolute;left:60px;top:110px;font-size:30px;margin:0">Open daily</p>'));
  assert.equal(r.status, 1, r.stdout);
  assert.match(r.stdout, /\[FAIL\] collisions-desktop: .*"Fjalar Bar" vs "Open daily"/);
});
test('text under a later-painted opaque box is a collision', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('covered', sceneWith('<h1 style="position:absolute;left:40px;top:100px;font-size:60px;margin:0">Fjalar Bar</h1><div style="position:absolute;left:0;top:90px;width:500px;height:100px;background:#123"></div>'));
  assert.match(r.stdout, /\[FAIL\] collisions-desktop: .*"Fjalar Bar".*covered by an opaque/);
});
test('a flat empty fold fails the dead-zone check and reports its size', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('dead', '<!doctype html><body style="margin:0;background:#223"><h1 style="margin:20px">Fjalar Bar</h1></body>');
  assert.match(r.stdout, /\[FAIL\] dead-zone: largest near-uniform rectangle \d+x\d+px at \(\d+,\d+\)/);
});
test('a translucent text card over hero art fails; a solid one passes', { skip: noPw && 'Playwright absent' }, () => {
  const card = (bg, extra = '') => `<h1 style="position:relative;margin:120px 40px;font-size:60px">Fjalar Bar</h1><div style="position:absolute;left:700px;top:400px;width:400px;height:120px;background:${bg};color:#fff;${extra}">Open daily 17-23</div>`;
  const glass = fold('glass', sceneWith(card('rgba(0,0,0,.6)')));
  assert.match(glass.stdout, /\[FAIL\] card-over-art-desktop: "Open daily 17-23" \(background alpha 0\.60\)/);
  const blur = fold('blur', sceneWith(card('#123', 'backdrop-filter:blur(8px)')));
  assert.match(blur.stdout, /\[FAIL\] card-over-art-desktop: .*\(backdrop-filter\)/);
  const solid = fold('solid', sceneWith(card('#123')));
  assert.match(solid.stdout, /\[PASS\] card-over-art-desktop/);
});
test('sections below the fold without a wide plate fail art-down-page; contact is excluded', { skip: noPw && 'Playwright absent' }, () => {
  const hero = `<section style="height:900px"><svg viewBox="0 0 1440 900" style="width:100%;height:100%" aria-hidden="true">${shapes(160)}</svg></section>`;
  const textSec = id => `<section id="${id}" style="height:400px"><p>Plain text section</p></section>`;
  const contact = '<section id="contact" style="height:400px"><p>Call</p></section>';
  const r = fold('sections', `<!doctype html><body style="margin:0"><main>${hero}${textSec('menu')}${textSec('team')}${contact}</main></body>`);
  assert.match(r.stdout, /\[FAIL\] art-down-page: 0\/2 sections .*menu@\d+, team@\d+/);
  const ok = fold('sections-ok', `<!doctype html><body style="margin:0"><main>${hero}<section id="menu" style="height:400px">${plate(5)}</section>${contact}</main></body>`);
  assert.match(ok.stdout, /\[PASS\] art-down-page: 1\/1/);
});
