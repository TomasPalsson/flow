#!/usr/bin/env node
/**
 * fold-check.mjs — measures whether the first viewport is an illustrated scene (vary SKILL S1-S3).
 *
 * Usage:  node fold-check.mjs <url-or-html> [--mode persuade|experience|operate|read] [--treatment scene|pattern|photography|product-ui|typography|data-visual|utility] [--out <dir>]
 * Treatment (default typography for persuade/experience, utility for operate/read; pass --treatment scene for the drawn-scene rows) decides which rows are gated; the rest print INFO
 * ("informational for treatment <t>"). The gate table lives in fold-gates.mjs, the row text in fold-rows.mjs.
 * Loads the page at 1440x900 and 390x844, waits 1.5 s, and measures in the first viewport:
 *   coverage  union area of visible svg/canvas/img/video/background-image(url) boxes / viewport area
 *   detail    visible svg shape elements (path circle rect polygon ellipse line polyline); a canvas/img/video/svg-image/
 *             css-mask image
 *             covering >= 0.15 of the viewport also satisfies it, since raster detail cannot be counted
 *   headline  whether the h1 box overlaps an art box (headline set into the scene)
 *   plates    distinct svg/canvas >= 400px wide down the full page (hero included)
 *   collisions  (all modes, both viewports) visible text boxes (HTML and svg <text>) that overlap another text box, or are
 *             > 30% covered by an opaque later-painted element (document.elementsFromPoint grid sampling); prints both texts
 *   dead-zone   (persuade/experience) largest near-uniform-colour rectangle in the desktop fold screenshot (24px grid);
 *             FAIL above 20% of the fold area; prints size and position
 *   card-over-art (persuade/experience, both viewports) translucent (alpha < 0.95) or backdrop-filter element holding text
 *             over a hero art box
 *   art-down-page (persuade/experience) sections (>= 300px tall children of main/body) below the fold holding a drawn plate
 *             >= 40% of the section width and >= 120px tall; FAIL when under 60% do (contact/footer excluded)
 *   card-over-art also fails on a SOLID text container covering > 6% of the hero art area (fold-depth.browser.js; a full-width nav bar is exempt)
 *   full-bleed  (persuade/experience, both viewports) hero art union box (boxes >= 8% of the viewport) spans >= 95% of the width, margins <= 3% each
 *   rendering-depth  (persuade/experience) desktop hero art area: luminance p95-p5 >= 90 and >= 5 of 16 bins holding >= 2% of pixels;
 *             flat-block texture (mean sd of the flattest 30% of 8x8 blocks) is printed, not gated (smooth gradient skies are flat)
 *   plates-size (persuade/experience) largest drawn element per below-fold section: >= 35% of the section width, >= 280px tall, >= 3 value
 *             steps; FAIL when fewer than 50% of the plates pass. Thresholds calibrated on ara-bar/1, hitataekni/1,/4 (all pass).
 *   duplicate-content (all modes, full page, footer excluded; fold-content.browser.js) text blocks >= 40 chars appearing twice, and price
 *             lists (>= 3 amounts in one block, HTML or svg text) sharing >= 3 amounts with another non-nested block; FAIL prints them
 *   hidden-content (all modes, both viewports, after a scroll through the page; fold-craft.browser.js) text whose effective opacity is 0 / visibility
 *             hidden, or a hero art box (>= 8% of the viewport) fully transparent; display:none, [hidden], menus, dialogs, sr-only are exempt
 *   stray-overlay (all modes, both viewports) a fixed/absolute element, ::before/::after, or last-painted svg shape covering >= 80% of the viewport
 *             with a semi-opaque (alpha 0.2-0.98; a lighter grain rect is allowed) dark (luminance < 0.35) fill
 *   clipped-text (all modes, both viewports) text with overflow hidden and scrollWidth > clientWidth (not ellipsis), or svg <text> whose bbox crosses its svg viewBox
 *   page-overflow (all modes and treatments, both viewports; fold-page.browser.js) documentElement.scrollWidth > innerWidth + 1, or a visible text
 *             element, img, svg, video, canvas, iframe or table crossing the viewport edge (right > innerWidth + 1, left < -1) with no
 *             ancestor whose overflow-x is auto/scroll/hidden/clip; prints up to 5 offenders; visually hidden elements are ignored
 *   meta-copy (all modes and treatments, both viewports) visible text (not script/style/code/pre, not inside [data-meta-ok], not alt/aria-label)
 *             holding designer or scaffold language ("design note", "signature device", "placeholder", "lorem ipsum", "TODO", "REF XX-1" ...); prints each hit with context
 *   headline-on-fold (persuade/experience, desktop) a visible h1 (or role=heading level 1) in the first viewport plus another visible
 *             text line (>= 10 chars, outside nav/buttons) within 200px of it, plus an action (a link or button with visible text,
 *             outside nav) in the first viewport. An h1 laid over an art box is the intended pattern and passes; svg <text> alone
 *             (no h1) fails.
 *   title-on-fold (operate/read) a visible h1 or [role=heading][aria-level=1] in the first desktop viewport
 *   BLOCKING  final line listing the FAIL rows that must be fixed before shipping: collisions, clipped-text, hidden-content,
 *             stray-overlay, page-overflow, meta-copy, duplicate-content, headline-on-fold, title-on-fold, and headline-in-scene when the treatment gates it
 * Scene thresholds: coverage >= 0.55 desktop / 0.45 phone, detail >= 50 desktop, plates >= 4, h1 overlaps art.
 * Screenshots fold-desktop.png / fold-phone.png go to --out (default: next to a local file, else cwd).
 * Playwright is resolved from cwd, /tmp, $FOLD_CHECK_PW (a dir holding node_modules), or this script's dir; absent -> prints SKIP and exits 0.
 * Exit: 0 = all PASS (or SKIP) · 1 = any FAIL · 2 = usage
 */
import { createRequire } from 'node:module';
import { existsSync, mkdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { GATES, MODES, TREATMENTS, defaultTreatment } from './fold-gates.mjs';
import { buildRows, blockingRegex } from './fold-rows.mjs';
// the text-collision measure runs in the page; it lives in its own file (see its header)
const FOLD_TEXT = fileURLToPath(new URL('./fold-text.browser.js', import.meta.url));
// frame / solid-card / plate / rendering-depth measures (G1-G4 of round 5) live in their own browser file too
const FOLD_DEPTH = fileURLToPath(new URL('./fold-depth.browser.js', import.meta.url));
// duplicate-content and headline-on-fold measures (F6, F7 of round 6) live in their own browser file too
const FOLD_CONTENT = fileURLToPath(new URL('./fold-content.browser.js', import.meta.url));
// craft-bug measures (hidden content, stray overlay, clipped text; round 7) live in their own browser file too
const FOLD_CRAFT = fileURLToPath(new URL('./fold-craft.browser.js', import.meta.url));
// page-overflow and meta-copy measures (B1, B2 of round 8) live in their own browser file too
const FOLD_PAGE = fileURLToPath(new URL('./fold-page.browser.js', import.meta.url));

const args = process.argv.slice(2);
const opt = n => { const i = args.indexOf(n); return i < 0 ? null : args[i + 1]; };
const mode = opt('--mode') || 'persuade';
const treatment = opt('--treatment') || defaultTreatment(mode);
const G = GATES[treatment];
const target = args.find((a, i) => !a.startsWith('--') && !['--mode', '--out', '--treatment'].includes(args[i - 1]));
if (!target || !MODES.includes(mode) || !G) {
  console.error(`usage: node fold-check.mjs <url-or-html> [--mode ${MODES.join('|')}] [--treatment ${TREATMENTS.join('|')}] [--out <dir>]`); process.exit(2);
}
const isUrl = /^https?:\/\/|^file:\/\//.test(target);
const url = isUrl ? target : pathToFileURL(resolve(target)).href;
const outDir = resolve(opt('--out') || (isUrl ? process.cwd() : dirname(resolve(target))));

let chromium;
for (const base of [process.cwd(), '/tmp', ...(process.env.FOLD_CHECK_PW ? [process.env.FOLD_CHECK_PW] : []), dirname(fileURLToPath(import.meta.url))]) {
  for (const name of ['playwright', 'playwright-core']) {
    try { chromium = createRequire(join(base, 'x.js'))(name).chromium; if (chromium) break; } catch { /* try next */ }
  }
  if (chromium) break;
}
if (!chromium) { console.log('fold-check SKIP: Playwright not found (looked in cwd, /tmp, $FOLD_CHECK_PW, script dir); install it to measure the fold'); process.exit(0); }

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
  // the first h1 that is actually seen: a visually hidden duplicate must not hide the real one set over the art
  const h1s = [...document.querySelectorAll('h1,[role="heading"][aria-level="1"]')];
  const h1 = h1s.find(e => visible(e) && clip(box(e))) || h1s[0]; const hb = h1 ? clip(box(h1)) : null;
  const overlap = !!hb && art.some(a => Math.min(a.x2, hb.x2) > Math.max(a.x1, hb.x1) && Math.min(a.y2, hb.y2) > Math.max(a.y1, hb.y1))
    || !!(h1 && h1.closest('svg'));
  let plates = 0;
  for (const el of document.querySelectorAll('svg,canvas')) {
    if (el.parentElement && el.parentElement.closest('svg')) continue;
    if (visible(el) && el.getBoundingClientRect().width >= 400) plates++;
  }
  return { art, raster, detail, hasH1: !!h1, overlap, plates };
};

// G1: text collisions in the first viewport. Returns { texts: n, hits: [{a, b, why}] }.
// G3: translucent/blurred element with text over a hero art box.
const measureCards = () => {
  const vw = innerWidth, vh = innerHeight;
  const alphaOf = c => {
    if (!c || c === 'transparent') return 0;
    const m = c.match(/(?:,|\/)\s*([\d.]+)(%?)\s*\)$/);
    return m ? (m[2] ? +m[1] / 100 : +m[1]) : 1;
  };
  const artEls = [];
  for (const el of document.querySelectorAll('svg,canvas,img,video,*')) {
    const cs = getComputedStyle(el);
    if (/^(svg|canvas|img|video)$/i.test(el.tagName) || /url\(/.test(cs.backgroundImage)) {
      if (el === document.body || el === document.documentElement) continue;
      if (el.parentElement && el.parentElement.closest('svg')) continue;
      if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) continue;
      artEls.push(el);
    }
  }
  const hits = [];
  for (const el of document.querySelectorAll('body *')) {
    if (el.closest('svg,defs,template') || /^(script|style|noscript)$/i.test(el.tagName)) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || +cs.opacity === 0) continue;
    const blur = (cs.backdropFilter && cs.backdropFilter !== 'none') || (cs.webkitBackdropFilter && cs.webkitBackdropFilter !== 'none');
    const a = alphaOf(cs.backgroundColor);
    if (!blur && !(a > 0 && a < 0.95)) continue;
    const text = (el.textContent || '').replace(/\s+/g, ' ').trim();
    if (!text) continue;
    const r = el.getBoundingClientRect();
    const c = { x1: Math.max(0, r.left), y1: Math.max(0, r.top), x2: Math.min(vw, r.right), y2: Math.min(vh, r.bottom) };
    if (c.x2 - c.x1 < 20 || c.y2 - c.y1 < 12) continue;
    const over = artEls.find(e => {
      if (e === el || el.contains(e)) return false;
      const b = e.getBoundingClientRect();
      return Math.min(b.right, c.x2) > Math.max(b.left, c.x1) && Math.min(b.bottom, c.y2) > Math.max(b.top, c.y1);
    });
    if (over) hits.push({ text: text.slice(0, 40), why: blur ? 'backdrop-filter' : `background alpha ${a.toFixed(2)}`, art: `<${over.tagName.toLowerCase()}>` });
  }
  return hits;
};

// G4: drawn plate >= 40% of the section width, per section (children of main/body >= 300px tall).
const measureSections = () => {
  const vh = innerHeight;
  const ok = el => { const s = getComputedStyle(el); return s.display !== 'none' && s.visibility !== 'hidden' && +s.opacity > 0; };
  const big = c => [...c.children].filter(e => ok(e) && e.getBoundingClientRect().height >= 300);
  let container = document.querySelector('main') || document.body;
  for (let i = 0; i < 3; i++) {
    const b = big(container);
    if (b.length === 1 && b[0].children.length > 1 && b[0].getBoundingClientRect().height > 0.6 * container.getBoundingClientRect().height) container = b[0]; else break;
  }
  const out = [];
  for (const sec of big(container)) {
    const r = sec.getBoundingClientRect(), top = r.top + scrollY;
    const name = (sec.id || sec.getAttribute('aria-label') || sec.className || sec.tagName).toString().slice(0, 30);
    const tag = (sec.tagName + ' ' + sec.id + ' ' + sec.className + ' ' + (sec.getAttribute('aria-label') || '')).toLowerCase();
    const excluded = /^footer\b/.test(tag) || /contact|footer|kontakt|samband/.test(tag);
    let plate = false;
    for (const el of sec.querySelectorAll('svg,canvas,img,video,*')) {
      const cs = getComputedStyle(el);
      if (!(/^(svg|canvas|img|video)$/i.test(el.tagName) || /url\(/.test(cs.backgroundImage))) continue;
      if (el.parentElement && el.parentElement.closest('svg')) continue;
      if (!ok(el)) continue;
      const b = el.getBoundingClientRect();
      if (b.width >= 0.4 * r.width && b.height >= 120) { plate = true; break; }
    }
    const below = top >= vh * 0.5;
    if (below && !excluded) { sec.setAttribute('data-fold-sec', String(out.length)); sec.setAttribute('data-fold-name', name); }
    out.push({ name, top: Math.round(top), h: Math.round(r.height), below, excluded, plate });
  }
  return out;
};

// G2 helper: 24px cell stats of a screenshot, computed in the browser (no PNG decoder needed in node).
const cellStats = async b64 => {
  const img = new Image(); img.src = 'data:image/png;base64,' + b64; await img.decode();
  const cv = document.createElement('canvas'); cv.width = img.width; cv.height = img.height;
  const ctx = cv.getContext('2d'); ctx.drawImage(img, 0, 0);
  const C = 24, cols = Math.floor(img.width / C), rows = Math.floor(img.height / C), cells = [];
  for (let r = 0; r < rows; r++) {
    for (let c = 0; c < cols; c++) {
      const d = ctx.getImageData(c * C, r * C, C, C).data, n = C * C, mean = [0, 0, 0], sq = [0, 0, 0];
      for (let i = 0; i < d.length; i += 4) for (let k = 0; k < 3; k++) { mean[k] += d[i + k]; sq[k] += d[i + k] * d[i + k]; }
      const sd = Math.max(...[0, 1, 2].map(k => Math.sqrt(Math.max(0, sq[k] / n - (mean[k] / n) ** 2))));
      cells.push({ m: mean.map(v => v / n), sd });
    }
  }
  return { cols, rows, cells, w: img.width, h: img.height };
};

const deadZone = ({ cols, rows, cells, w, h }) => {
  const C = 24, SD = 8, TOL = 36, clusters = [];
  const label = new Array(cells.length).fill(-1);
  cells.forEach((c, i) => {
    if (c.sd >= SD) return;
    let k = clusters.findIndex(s => Math.max(...s.map((v, j) => Math.abs(v - c.m[j]))) <= TOL);
    if (k < 0) { clusters.push(c.m); k = clusters.length - 1; }
    label[i] = k;
  });
  let best = { cells: 0 };
  clusters.forEach((_, k) => {
    const height = new Array(cols).fill(0);
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) height[c] = label[r * cols + c] === k ? height[c] + 1 : 0;
      const st = [];
      for (let c = 0; c <= cols; c++) {
        const cur = c === cols ? 0 : height[c];
        while (st.length && height[st[st.length - 1]] >= cur) {
          const hh = height[st.pop()], left = st.length ? st[st.length - 1] + 1 : 0, wd = c - left;
          if (hh * wd > best.cells) best = { cells: hh * wd, x: left * C, y: (r - hh + 1) * C, w: wd * C, h: hh * C };
        }
        st.push(c);
      }
    }
  });
  return best.cells ? { ...best, frac: (best.w * best.h) / (w * h) } : { x: 0, y: 0, w: 0, h: 0, frac: 0 };
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

// Rendering depth of the hero art box (desktop screenshot) and of every below-fold plate; solid cards and frame on both viewports.
const measureDepth = async (page, shot, name) => {
  const frame = await page.evaluate(() => window.__foldDepth.frame());
  const solid = await page.evaluate(() => window.__foldDepth.cards());
  if (name !== 'desktop') return { frame, solid };
  const hero = frame.none ? { range: 0, steps: 0, texture: 0 } : await page.evaluate(([b, r]) => window.__foldDepth.stats(b, r), [shot.toString('base64'), frame.box]);
  const plates = await page.evaluate(() => window.__foldDepth.plates());
  for (const pl of plates) {
    const png = await page.locator(`[data-fold-plate="${pl.id}"]`).first().screenshot().catch(() => null);
    pl.stats = png ? await page.evaluate(([b]) => window.__foldDepth.stats(b, null), [png.toString('base64')]) : { range: 0, steps: 0, texture: 0 };
  }
  return { frame, solid, hero, plates };
};

mkdirSync(outDir, { recursive: true });
const browser = await chromium.launch();
const res = {};
for (const [name, w, h] of [['desktop', 1440, 900], ['phone', 390, 844]]) {
  const page = await browser.newPage({ viewport: { width: w, height: h } });
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForTimeout(1500);
  const m = await page.evaluate(measure);
  await page.addScriptTag({ path: FOLD_TEXT });
  const text = await page.evaluate(() => window.__foldText());
  const cards = await page.evaluate(measureCards);
  const sections = name === 'desktop' ? await page.evaluate(measureSections) : [];
  const shot = await page.screenshot({ path: join(outDir, `fold-${name}.png`) });
  await page.addScriptTag({ path: FOLD_DEPTH });
  const depth = await measureDepth(page, shot, name);
  await page.addScriptTag({ path: FOLD_CONTENT });
  const content = name === 'desktop' ? { head: await page.evaluate(() => window.__foldContent.headline()), dup: await page.evaluate(() => window.__foldContent.duplicates()) } : null;
  await page.addScriptTag({ path: FOLD_CRAFT });
  const craft = { hidden: await page.evaluate(() => window.__foldCraft.hidden()), overlay: await page.evaluate(() => window.__foldCraft.overlay()), clipped: await page.evaluate(() => window.__foldCraft.clipped()) };
  await page.addScriptTag({ path: FOLD_PAGE });
  const pageRows = { overflow: await page.evaluate(() => window.__foldPage.overflow()), meta: await page.evaluate(() => window.__foldPage.meta()) };
  let dead = null;
  if (name === 'desktop') dead = deadZone(await page.evaluate(cellStats, shot.toString('base64')));
  res[name] = { ...m, craft, pageRows, text, cards, sections, dead, depth, content, coverage: union(m.art) / (w * h), rasterCoverage: union(m.raster) / (w * h) };
  await page.close();
}
await browser.close();

const lines = buildRows(res, mode, treatment, G);
console.log(`fold-check ${url} mode=${mode} treatment=${treatment}`);
for (const l of lines) console.log('  ' + l.text);
console.log(`  screenshots: ${join(outDir, 'fold-desktop.png')}, ${join(outDir, 'fold-phone.png')}`);
const fail = lines.some(l => l.ok === false);
const BLOCKING = blockingRegex(G);
const blocking = lines.filter(l => l.ok === false && BLOCKING.test(l.text.slice(7)));
console.log(`BLOCKING: ${blocking.length ? blocking.map(l => l.text.slice(7).split(':')[0]).join(', ') : 'none'}`);
console.log(`fold-check ${fail ? 'FAIL' : 'PASS'}`);
process.exit(fail ? 1 : 0);
