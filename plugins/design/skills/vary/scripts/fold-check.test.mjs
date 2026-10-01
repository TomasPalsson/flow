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
const sky = '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#001"/><stop offset="1" stop-color="#fed"/></linearGradient></defs><rect width="1440" height="900" fill="url(#g)"/>';
const shapes = n => sky + Array.from({ length: n }, (_, i) => `<rect x="${(i * 37) % 1400}" y="${(i * 53) % 880}" width="40" height="30" fill="#${((i * 99991) % 0xffffff).toString(16).padStart(6, '0')}"/>`).join('');
const plate = n => `<svg viewBox="0 0 1400 400" width="1400" height="400" aria-hidden="true">${shapes(n)}</svg>`;
const scene = `<!doctype html><body style="margin:0"><svg viewBox="0 0 1440 900" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true">${shapes(160)}</svg>
<h1 style="position:relative;margin:120px 40px;font-size:60px">Fjalar Bar</h1><p style="position:relative;margin:-100px 40px 0;font-size:24px;width:max-content;background:#123;color:#fff">Cocktails and small plates, open daily.</p><div style="margin-top:900px">${plate(10)}${plate(10)}${plate(10)}</div></body>`;
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

const flatHero = `<!doctype html><body style="margin:0"><svg viewBox="0 0 1440 900" style="position:absolute;inset:0;width:100%;height:100%" aria-hidden="true"><rect width="1440" height="900" fill="#456"/></svg><h1 style="position:relative;margin:120px 40px">Fjalar Bar</h1></body>`;
test('a framed hero picture fails full-bleed and names its margins', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('framed', `<!doctype html><body style="margin:0"><svg viewBox="0 0 1440 900" style="display:block;width:900px;height:700px;margin:40px auto" aria-hidden="true">${shapes(160)}</svg><h1>Fjalar Bar</h1></body>`);
  assert.match(r.stdout, /\[FAIL\] full-bleed-desktop: hero art box spans 63% .*margins left 270px right 270px/);
  assert.match(fold('bleed', scene).stdout, /\[PASS\] full-bleed-desktop: hero art box spans 100%/);
});
test('a flat single-fill hero fails rendering-depth and prints the three numbers; a gradient scene passes', { skip: noPw && 'Playwright absent' }, () => {
  assert.match(fold('flat', flatHero).stdout, /\[FAIL\] rendering-depth: desktop art area: value range \d+ \(need >= 90\), \d+ value steps \(need >= 5\), flat-block texture \d/);
  assert.match(fold('depth-ok', scene).stdout, /\[PASS\] rendering-depth/);
});
test('a big solid headline card over the hero art fails card-over-art', { skip: noPw && 'Playwright absent' }, () => {
  const r = fold('bigcard', sceneWith('<div style="position:absolute;left:100px;top:100px;width:700px;height:400px;background:#123;color:#fff">Open daily 17-23</div>'));
  assert.match(r.stdout, /\[FAIL\] card-over-art-desktop: "Open daily 17-23" \(solid card covering \d+% of the hero art/);
});
test('thin section plates fail plates-size; big rendered plates pass', { skip: noPw && 'Playwright absent' }, () => {
  const hero = `<section style="height:900px"><svg viewBox="0 0 1440 900" style="width:100%;height:100%" aria-hidden="true">${shapes(160)}</svg></section>`;
  const sec = (id, w, h) => `<section id="${id}" style="height:400px"><svg viewBox="0 0 1440 900" style="width:${w};height:${h}" aria-hidden="true">${shapes(5)}</svg></section>`;
  const thin = fold('thin', `<!doctype html><body style="margin:0"><main>${hero}${sec('menu', '300px', '200px')}${sec('team', '300px', '200px')}</main></body>`);
  assert.match(thin.stdout, /\[FAIL\] plates-size: 0\/2 .*menu 300x200 of 1440px/);
  const big = fold('big', `<!doctype html><body style="margin:0"><main>${hero}${sec('menu', '900px', '320px')}</main></body>`);
  assert.match(big.stdout, /\[PASS\] plates-size: 1\/1/);
});

const prices = (id, rows) => `<ul id="${id}">${rows.map(r => `<li>${r}</li>`).join('')}</ul>`;
const ladder = ['Rebacking £180', 'Full rebind £420', 'Clamshell box £150'];
test('a price list shown twice fails duplicate-content and names the amounts; once passes', { skip: noPw && 'Playwright absent' }, () => {
  const twice = fold('dup-price', sceneWith(`<section>${prices('a', ladder)}</section><section>${prices('b', ladder)}</section>`));
  assert.match(twice.stdout, /\[FAIL\] duplicate-content: .*price list 180\/420\/150 repeats in <ul#a> and <ul#b>/);
  assert.match(fold('once-price', sceneWith(`<section>${prices('a', ladder)}</section>`)).stdout, /\[PASS\] duplicate-content/);
});
test('a repeated paragraph outside the footer fails; the same text in the footer passes', { skip: noPw && 'Playwright absent' }, () => {
  const para = '<p>We rebind and repair books by hand in the old print works.</p>';
  assert.match(fold('dup-text', sceneWith(`<section>${para}</section><section>${para}</section>`)).stdout, /\[FAIL\] duplicate-content: "we rebind and repair books by hand/);
  assert.match(fold('foot-text', sceneWith(`<section>${para}</section><footer>${para}</footer>`)).stdout, /\[PASS\] duplicate-content/);
});
test('an h1 with no value-proposition line near it fails headline-on-fold; no h1 fails too', { skip: noPw && 'Playwright absent' }, () => {
  assert.match(fold('lone-h1', sceneWith('<h1 style="position:relative;margin:120px 40px">Fjalar Bar</h1>')).stdout, /\[FAIL\] headline-on-fold: h1 "Fjalar Bar" has no other text line/);
  assert.match(fold('no-h1', '<!doctype html><body style="margin:0"><p>Fjalar Bar, open daily to all.</p></body>').stdout, /\[FAIL\] headline-on-fold: no visible h1/);
  assert.match(fold('with-line', scene).stdout, /\[PASS\] headline-on-fold: h1 "Fjalar Bar" with line "Cocktails/);
});

test('text that never reveals fails hidden-content; a reveal that fires passes', { skip: noPw && 'Playwright absent' }, () => {
  const bad = fold('hid', sceneWith('<p id="tag" style="position:relative;margin:0 40px;opacity:0">Open daily 17-23</p>'));
  assert.match(bad.stdout, /\[FAIL\] hidden-content-desktop: <p#tag> opacity 0 "Open daily 17-23"/);
  const ok = fold('rev', sceneWith('<style>@keyframes up{from{opacity:0}to{opacity:1}}</style><p style="position:relative;margin:0 40px;animation:up .3s forwards">Open daily 17-23</p>'));
  assert.match(ok.stdout, /\[PASS\] hidden-content-desktop/);
});
test('a dark semi-opaque full-viewport layer fails stray-overlay, in html and inside the svg', { skip: noPw && 'Playwright absent' }, () => {
  const html = fold('ovl', sceneWith('<div id="veil" style="position:fixed;inset:0;background:rgba(0,0,0,.5)"></div>'));
  assert.match(html.stdout, /\[FAIL\] stray-overlay-desktop: <div#veil> covers the viewport with a dark fill at alpha 0\.50/);
  const inSvg = fold('ovl-svg', scene.replace('</svg>', '<rect width="1440" height="900" opacity="0.5"/></svg>'));
  assert.match(inSvg.stdout, /\[FAIL\] stray-overlay-desktop: <rect> in svg/);
  assert.match(fold('ovl-ok', scene).stdout, /\[PASS\] stray-overlay-desktop/);
});
test('text clipped by overflow hidden or by its svg viewport fails clipped-text', { skip: noPw && 'Playwright absent' }, () => {
  const html = fold('clip', sceneWith('<div style="position:relative;margin:0 40px;width:80px;overflow:hidden;white-space:nowrap">Open daily seventeen to twenty-three</div>'));
  assert.match(html.stdout, /\[FAIL\] clipped-text-desktop: "Open daily seventeen/);
  const svg = fold('clip-svg', sceneWith('<svg viewBox="0 0 200 60" width="200" height="60" style="position:relative;margin:0 40px"><text x="150" y="30" font-size="20">UKAS ACCREDITED</text></svg>'));
  assert.match(svg.stdout, /\[FAIL\] clipped-text-desktop: "UKAS ACCREDITED" \(svg text crosses/);
  assert.match(fold('clip-ok', scene).stdout, /\[PASS\] clipped-text-desktop/);
});
