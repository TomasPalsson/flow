#!/usr/bin/env node
/**
 * fold-check.mjs — measures whether the first viewport is an illustrated scene (vary SKILL S1-S3).
 *
 * Usage:  node fold-check.mjs <url-or-html> [--mode persuade|experience|operate|read] [--out <dir>]
 * Loads the page at 1440x900 and 390x844, waits 1.5 s, and measures in the first viewport:
 *   coverage  union area of visible svg/canvas/img/video/background-image(url) boxes / viewport area
 *   detail    visible svg shape elements (path circle rect polygon ellipse line polyline); a canvas/img/video/svg-image/
 *             css-mask image
 *             covering >= 0.15 of the viewport also satisfies it, since raster detail cannot be counted
 *   headline  whether the h1 box overlaps an art box (headline set into the scene)
 *   plates    distinct svg/canvas >= 400px wide down the full page (hero included)
 * Thresholds: coverage >= 0.55 desktop / 0.45 phone (persuade, experience only; informational for
 * operate/read), detail >= 50 desktop, plates >= 4, h1 overlaps art (persuade, experience).
 * Screenshots fold-desktop.png / fold-phone.png go to --out (default: next to a local file, else cwd).
 * Playwright is resolved from cwd, /tmp, or this script's dir; absent -> prints SKIP and exits 0.
 * Exit: 0 = all PASS (or SKIP) · 1 = any FAIL · 2 = usage
 */
import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const args = process.argv.slice(2);
const opt = n => { const i = args.indexOf(n); return i < 0 ? null : args[i + 1]; };
const mode = opt('--mode') || 'persuade';
const target = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--mode' && args[i - 1] !== '--out');
if (!target || !['persuade', 'experience', 'operate', 'read'].includes(mode)) {
  console.error('usage: node fold-check.mjs <url-or-html> [--mode persuade|experience|operate|read] [--out <dir>]'); process.exit(2);
}
const isUrl = /^https?:\/\/|^file:\/\//.test(target);
const url = isUrl ? target : pathToFileURL(resolve(target)).href;
const outDir = resolve(opt('--out') || (isUrl ? process.cwd() : dirname(resolve(target))));

let chromium;
for (const base of [process.cwd(), '/tmp', dirname(fileURLToPath(import.meta.url))]) {
  for (const name of ['playwright', 'playwright-core']) {
    try { chromium = createRequire(join(base, 'x.js'))(name).chromium; if (chromium) break; } catch { /* try next */ }
  }
  if (chromium) break;
}
if (!chromium) { console.log('fold-check SKIP: Playwright not found (looked in cwd, /tmp, script dir); install it to measure the fold'); process.exit(0); }

const measure = () => {
  const vw = innerWidth, vh = innerHeight, SHAPES = 'path,circle,rect,polygon,ellipse,line,polyline';
  const visible = el => {
    for (let n = el; n && n.nodeType === 1; n = n.parentElement) {
      const s = getComputedStyle(n);
      if (s.display === 'none' || s.visibility === 'hidden' || +s.opacity === 0) return false;
    }
    return true;
  };
  const inert = el => !!el.closest('defs,symbol,clipPath,mask,pattern,marker,template');
  const box = el => { const r = el.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width, h: r.height }; };
  const clip = b => { const x1 = Math.max(0, b.x), y1 = Math.max(0, b.y), x2 = Math.min(vw, b.x + b.w), y2 = Math.min(vh, b.y + b.h); return x2 > x1 && y2 > y1 ? { x1, y1, x2, y2 } : null; };
  const art = [], raster = [];
  for (const el of document.querySelectorAll('svg,canvas,img,video,*')) {
    const cs = getComputedStyle(el), masked = /url\(/.test(cs.maskImage || cs.webkitMaskImage || '');
    const isArt = /^(svg|canvas|img|video)$/i.test(el.tagName) || /url\(/.test(cs.backgroundImage) || masked;
    if (!isArt || (el.parentElement && el.parentElement.closest('svg'))) continue;
    if (!visible(el)) continue;
    const c = clip(box(el)); if (c) { art.push(c); if (masked || /^(canvas|img|video)$/i.test(el.tagName)) raster.push(c); }
  }
  let detail = 0;
  for (const el of document.querySelectorAll(SHAPES)) {
    if (inert(el) || !visible(el)) continue;
    const r = el.getBoundingClientRect();
    if (clip({ x: r.left, y: r.top, w: r.width, h: r.height })) detail++;
  }
  for (const el of document.querySelectorAll('svg image')) {
    if (inert(el) || !visible(el)) continue;
    const c = clip(box(el)); if (c) raster.push(c);
  }
  const h1 = document.querySelector('h1'); const hb = h1 ? clip(box(h1)) : null;
  const overlap = !!hb && art.some(a => Math.min(a.x2, hb.x2) > Math.max(a.x1, hb.x1) && Math.min(a.y2, hb.y2) > Math.max(a.y1, hb.y1))
    || !!(h1 && h1.closest('svg'));
  let plates = 0;
  for (const el of document.querySelectorAll('svg,canvas')) {
    if (el.parentElement && el.parentElement.closest('svg')) continue;
    if (visible(el) && el.getBoundingClientRect().width >= 400) plates++;
  }
  return { art, raster, detail, hasH1: !!h1, overlap, plates };
};

const union = rects => {
  const xs = [...new Set(rects.flatMap(r => [r.x1, r.x2]))].sort((a, b) => a - b);
  let area = 0;
  for (let i = 0; i < xs.length - 1; i++) {
    const iv = rects.filter(r => r.x1 <= xs[i] && r.x2 >= xs[i + 1]).map(r => [r.y1, r.y2]).sort((a, b) => a[0] - b[0]);
    let end = -Infinity, len = 0;
    for (const [a, b] of iv) { if (b > end) { len += b - Math.max(a, end); end = b; } }
    area += len * (xs[i + 1] - xs[i]);
  }
  return area;
};

mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const res = {};
for (const [name, w, h] of [['desktop', 1440, 900], ['phone', 390, 844]]) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(measure);
  await page.screenshot({ path: join(outDir, `fold-${name}.png`) });
  res[name] = { ...m, coverage: union(m.art) / (w * h), rasterCoverage: union(m.raster) / (w * h) };
  await page.close();
}
await browser.close();

const scene = mode === 'persuade' || mode === 'experience';
const lines = [];
const row = (ok, id, text) => lines.push({ ok, text: `[${ok === null ? 'INFO' : ok ? 'PASS' : 'FAIL'}] ${id}: ${text}` });
const d = res.desktop, p = res.phone;
const cov = (v, min) => `${v.toFixed(2)} (need >= ${min})`;
row(scene ? d.coverage >= 0.55 : null, 'coverage-desktop', cov(d.coverage, 0.55) + (scene ? '' : ` informational in ${mode} mode`));
row(scene ? p.coverage >= 0.45 : null, 'coverage-phone', cov(p.coverage, 0.45) + (scene ? '' : ` informational in ${mode} mode`));
const rasterOk = d.rasterCoverage >= 0.15;
row(d.detail >= 50 || rasterOk, 'detail', `${d.detail} shape elements in the desktop hero (need >= 50); phone ${p.detail}` + (d.detail < 50 && rasterOk ? `; passes on raster art covering ${d.rasterCoverage.toFixed(2)} of the viewport (canvas/img/video detail is not countable, judge it by eye)` : ''));
row(scene ? d.hasH1 && d.overlap : null, 'headline-in-scene', !d.hasH1 ? 'no h1 found' : d.overlap ? 'h1 box overlaps an art box' : 'h1 sits clear of every art box (floated beside the picture)');
row(d.plates >= 4, 'plates', `${d.plates} svg/canvas plates >= 400px wide down the page, hero included (need >= 4)`);
console.log(`fold-check ${url} mode=${mode}`);
for (const l of lines) console.log('  ' + l.text);
console.log(`  screenshots: ${join(outDir, 'fold-desktop.png')}, ${join(outDir, 'fold-phone.png')}`);
const fail = lines.some(l => l.ok === false);
console.log(`fold-check ${fail ? 'FAIL' : 'PASS'}`);
process.exit(fail ? 1 : 0);
