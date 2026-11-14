#!/usr/bin/env node
// probe.mjs <page.html|url> [outdir] [--json] — drives a built page in Chromium and reports whether it
// answers touch (hover, press, focus), whether its motion is sound, and whether it carries the
// mechanical AI-made tells. FAIL rows gate Phase 5b of the design skill; WARN rows need a reason; INFO is context.
// Writes desktop/phone screenshots and a hover+press filmstrip of the primary action to outdir.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';

const args = process.argv.slice(2);
const asJson = args.includes('--json');
const [target, outArg] = args.filter((a) => !a.startsWith('--'));
if (!target) { console.error('usage: probe.mjs <page.html|url> [outdir] [--json]'); process.exit(2); }
const outDir = outArg || path.join(path.dirname(path.resolve(target)), 'probe');
fs.mkdirSync(outDir, { recursive: true });
const url = /^https?:|^file:/.test(target) ? target : 'file://' + path.resolve(target);

function loadPlaywright() {
  const bases = [process.cwd() + '/', ...(process.env.NODE_PATH || '').split(path.delimiter).filter(Boolean).map((p) => p + '/'), '/opt/node-tools/node_modules/'];
  for (const b of bases) { try { return createRequire(b)('playwright'); } catch { /* next */ } }
  console.error('probe.mjs: playwright not found (set NODE_PATH to the folder that holds it)'); process.exit(2);
}
const { chromium } = loadPlaywright();

const HARD_BUZZ = ['seamless', 'unlock', 'revolutioni', 'elevate your', 'empower', 'supercharge', 'effortless', 'cutting-edge', 'game-chang',
  'next-level', 'next level', 'the future of', 'say goodbye', 'look no further', "in today's", 'unleash', 'harness the', 'world-class',
  'best-in-class', 'like never before', 'reimagin', 'delve'];
const SOFT_BUZZ = ['robust', 'streamline', 'curated', 'crafted', 'journey', 'built for', 'designed for', 'peace of mind', 'all-in-one',
  'at your fingertips', 'in seconds', 'no fluff', 'nothing more', 'whether you'];
const DEFAULT_FONTS = ['inter', 'roboto', 'arial', 'helvetica', 'helvetica neue', 'system-ui', '-apple-system', 'space grotesk', 'poppins', 'montserrat', 'open sans', 'lato'];
const INTERACTIVE = 'a[href], button, input:not([type=hidden]), select, textarea, summary, [role=button], [role=tab], [role=switch], [role=radio], label:has(> input[type=radio]), label:has(> input[type=checkbox]), label[for]';

// Serialised state of an element, its pseudo-elements and small descendants: any visible change on hover/press shows up here.
const snapshot = (el) => {
  const p = (e, s) => { const c = getComputedStyle(e, s); return [c.color, c.backgroundColor, c.borderColor, c.boxShadow, c.transform, c.scale, c.translate, c.opacity, c.textDecorationColor, c.textUnderlineOffset, c.outlineStyle, c.outlineColor, c.filter, c.backgroundImage].join('|'); };
  let s = p(el, null) + p(el, '::before') + p(el, '::after');
  for (const k of el.querySelectorAll('*')) if (k.children.length <= 4) s += p(k, null);
  return s;
};

async function audit(page) {
  return page.evaluate(({ HARD_BUZZ, SOFT_BUZZ, DEFAULT_FONTS }) => {
    const o = {};
    const vis = (el) => { const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return r.width > 0 && r.height > 0 && cs.visibility !== 'hidden' && cs.display !== 'none'; };
    const text = document.body.innerText; const lower = text.toLowerCase();
    o.words = text.split(/\s+/).filter(Boolean).length;
    o.hardBuzz = HARD_BUZZ.filter((b) => lower.includes(b));
    o.softBuzz = SOFT_BUZZ.filter((b) => lower.includes(b));
    o.emDashPer600 = +((text.match(/—/g) || []).length / Math.max(o.words, 1) * 600).toFixed(1);
    o.notXJustY = (text.match(/\b(No|Not) [^.\n]{1,40}\. (Just|Only|But) /g) || []).length;
    const emojiHosts = [...document.querySelectorAll('body *')].filter((el) => !el.closest('[data-emoji-ok]') && [...el.childNodes].some((n) => n.nodeType === 3 && /\p{Extended_Pictographic}/u.test(n.textContent)));
    o.emoji = emojiHosts.length;
    const fam = (el) => (el ? getComputedStyle(el).fontFamily.split(',')[0].replace(/["']/g, '').trim().toLowerCase() : null);
    const h1 = document.querySelector('h1');
    o.fonts = { heading: fam(h1 || document.querySelector('h2')), body: fam(document.querySelector('p') || document.body), control: fam(document.querySelector('button')) };
    o.defaultFonts = [...new Set(Object.values(o.fonts).filter((f) => f && DEFAULT_FONTS.includes(f)))];
    const all = [...document.querySelectorAll('body *')].filter(vis);
    o.gradientText = all.filter((el) => { const cs = getComputedStyle(el); return (cs.backgroundClip === 'text' || cs.webkitBackgroundClip === 'text') && cs.backgroundImage.includes('gradient'); }).length;
    o.backdrop = all.filter((el) => getComputedStyle(el).backdropFilter !== 'none').length;
    o.blobs = all.filter((el) => { const m = getComputedStyle(el).filter.match(/blur\((\d+)/); return m && +m[1] >= 30; }).length;
    if (h1) { const prev = h1.previousElementSibling; if (prev && prev.innerText && prev.innerText.length < 60) { const cs = getComputedStyle(prev); o.eyebrowPill = parseFloat(cs.borderTopLeftRadius) >= 10 && cs.backgroundColor !== 'rgba(0, 0, 0, 0)' ? prev.innerText.trim() : null; } }
    if (h1) {
      const ink = getComputedStyle(h1).color;
      o.twoToneHeadline = [...h1.querySelectorAll('span, em, i, strong, b')].some((k) => k.innerText.trim().split(/\s+/).length >= 2 && getComputedStyle(k).color !== ink);
      const fs = parseFloat(getComputedStyle(h1).fontSize); const ls = parseFloat(getComputedStyle(h1).letterSpacing) || 0;
      o.h1Tracking = +(ls / fs).toFixed(3);
    }

    // the template top bar: brand at the left, every other control clustered at the right, nothing else in it
    const bar = [...document.querySelectorAll('header, nav, body > *')].find((el) => { const b = el.getBoundingClientRect(); return b.top <= 4 && b.width > innerWidth * 0.8 && b.height >= 40 && b.height <= 110; });
    if (bar) {
      const ctrls = [...bar.querySelectorAll('a[href], button')].filter(vis);
      const W = bar.getBoundingClientRect().width, X = bar.getBoundingClientRect().left;
      // brand = the block holding the first left-hand text, inside the row it shares with the right-most control
      const texts = []; const walker = document.createTreeWalker(bar, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (!n.textContent.trim()) continue; const r = document.createRange(); r.selectNodeContents(n); const rb = r.getBoundingClientRect();
        if (rb.width) texts.push({ n, left: rb.left - X, words: n.textContent.split(/\s+/).filter(Boolean).length });
      }
      const first = texts.find((t) => t.left < W * 0.3);
      const lastCtrl = ctrls.slice().sort((p, q) => q.getBoundingClientRect().right - p.getBoundingClientRect().right)[0];
      let brandWords = 0, contentWords = 0;
      if (first && lastCtrl) {
        let row = first.n.parentElement; while (row && !row.contains(lastCtrl)) row = row.parentElement;
        let brandBlock = first.n.parentElement; while (brandBlock && brandBlock.parentElement !== row) brandBlock = brandBlock.parentElement;
        for (const t of texts) {
          if (brandBlock && brandBlock.contains(t.n)) brandWords += t.words;
          else if (!t.n.parentElement.closest('a[href], button')) contentWords += t.words;
        }
      }
      const rest = ctrls.filter((c) => c.getBoundingClientRect().left - X >= W * 0.3);
      const rightCluster = rest.length >= 1 && rest.every((c) => c.getBoundingClientRect().left - X > W * 0.38);
      o.templateTopBar = brandWords > 0 && rightCluster && contentWords <= 3 ? `${rest.length} controls clustered right of the brand, ${contentWords} words of content` : null;
    }
    // the same section-head arrangement on most sections
    const sig = (h) => { const b = h.getBoundingClientRect(); const sib = h.nextElementSibling || h.parentElement.nextElementSibling; const sb = sib ? sib.getBoundingClientRect() : null; return [Math.round(b.left / 48), Math.round(b.width / 120), getComputedStyle(h).textAlign, sb ? (sb.left > b.right - 4 ? 'beside' : 'below') : 'none', getComputedStyle(h).fontSize].join('|'); };
    const h2s = [...document.querySelectorAll('h2')].filter(vis);
    if (h2s.length >= 3) { const c = {}; h2s.forEach((h) => { const k = sig(h); c[k] = (c[k] || 0) + 1; }); const top = Math.max(...Object.values(c)); o.sameHeads = top >= 3 && top / h2s.length >= 0.75 ? `${top} of ${h2s.length} section heads share one arrangement` : null; }
    // literal colours that bypass the tokens
    const css = [...document.querySelectorAll('style')].map((x) => x.textContent).join('\n').replace(/\/\*[\s\S]*?\*\//g, '');
    const outsideTokens = css.split(/[;{}]/).filter((d) => !/^\s*--[\w-]+\s*:/.test(d));
    o.literalColours = outsideTokens.reduce((n, d) => n + (d.match(/#[0-9a-f]{3,8}\b|\brgba?\(|\bhsla?\(|\boklch\(\s*[\d.]/gi) || []).length, 0);
    const cv = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
    const hue = (color) => { if (!color || color === 'rgba(0, 0, 0, 0)' || color === 'transparent') return null; cv.clearRect(0, 0, 1, 1); cv.fillStyle = color; cv.fillRect(0, 0, 1, 1); const d = cv.getImageData(0, 0, 1, 1).data; if (d[3] < 128) return null; const [r, g, b] = [d[0], d[1], d[2]].map((v) => v / 255); const mx = Math.max(r, g, b), mn = Math.min(r, g, b); if (mx - mn < 0.15) return null; let h = mx === r ? ((g - b) / (mx - mn)) % 6 : mx === g ? (b - r) / (mx - mn) + 2 : (r - g) / (mx - mn) + 4; return (h * 60 + 360) % 360; };
    o.purpleActions = [...document.querySelectorAll('a, button')].filter(vis).filter((el) => { const h = hue(getComputedStyle(el).backgroundColor); return h !== null && h >= 225 && h <= 295; }).length;
    const trans = all.map((el) => getComputedStyle(el)).filter((cs) => cs.transitionDuration.split(',').some((d) => parseFloat(d) > 0)).map((cs) => ({ prop: cs.transitionProperty, dur: cs.transitionDuration }));
    o.transitioned = trans.length;
    o.transitionAll = trans.filter((t) => t.prop.split(',').map((s) => s.trim()).includes('all')).length;
    o.layoutTransitions = trans.filter((t) => t.prop.split(',').map((s) => s.trim()).some((p) => /^(width|height|top|left|right|bottom|margin.*|padding.*|font-size|max-height)$/.test(p))).length;
    const durs = trans.flatMap((t) => t.dur.split(',').map((d) => Math.round(parseFloat(d) * (d.includes('ms') ? 1 : 1000)))).filter((d) => d > 0);
    o.durations = [...new Set(durs)].sort((a, b) => a - b);
    const anims = document.getAnimations();
    o.infiniteRunning = anims.filter((a) => a.playState === 'running' && a.effect && a.effect.getComputedTiming().iterations === Infinity).length;
    o.overflow = document.documentElement.scrollWidth > innerWidth + 1;
    o.hiddenShown = [...document.querySelectorAll('[hidden]')].filter((el) => getComputedStyle(el).display !== 'none').map((el) => el.id || el.className || el.tagName).slice(0, 5);
    o.reducedMotionCSS = [...document.styleSheets].some((s) => { try { return [...s.cssRules].some((r) => (r.conditionText || r.media?.mediaText || '').includes('prefers-reduced-motion')); } catch { return false; } }) || /prefers-reduced-motion/.test(document.documentElement.innerHTML);
    // text that is still invisible after load anywhere on the page (candidates for scroll-reveal)
    const hidden = all.filter((el) => el.innerText && el.innerText.trim().length > 3 && el.childElementCount < 6 && parseFloat(getComputedStyle(el).opacity) < 0.05);
    hidden.forEach((el, i) => el.setAttribute('data-probe-hidden', i));
    o.hiddenAfterLoad = hidden.length;
    o.hiddenInFold = hidden.filter((el) => el.getBoundingClientRect().top < innerHeight).length;
    return o;
  }, { HARD_BUZZ, SOFT_BUZZ, DEFAULT_FONTS });
}

async function scrollReveal(page) {
  const h = await page.evaluate(() => document.documentElement.scrollHeight);
  for (let y = 0; y < h; y += 400) { await page.evaluate((v) => window.scrollTo(0, v), y); await page.waitForTimeout(90); }
  await page.waitForTimeout(700);
  const n = await page.evaluate(() => [...document.querySelectorAll('[data-probe-hidden]')].filter((el) => parseFloat(getComputedStyle(el).opacity) > 0.5).length);
  await page.evaluate(() => window.scrollTo(0, 0)); await page.waitForTimeout(300);
  return n;
}

async function touchAudit(page) {
  const snap = `(${snapshot.toString()})`;
  const rows = [];
  for (const h of await page.$$(INTERACTIVE)) {
    if (rows.length >= 50) break;
    const box = await h.boundingBox().catch(() => null);
    if (!box || box.width < 4 || box.height < 4) continue;
    const info = await h.evaluate((el) => ({ tag: el.tagName.toLowerCase(), labelled: el.matches('input[type=radio], input[type=checkbox]') && el.labels && el.labels.length > 0, textLabel: el.tagName === 'LABEL' && !!el.control && !el.control.matches('input[type=radio], input[type=checkbox]'), selected: ['aria-pressed', 'aria-selected', 'aria-checked'].some((a) => el.getAttribute(a) === 'true') || el.hasAttribute('aria-current') || el.checked === true || !!(el.control && el.control.checked) || !!el.querySelector?.('input:checked'), skip: /^skip\b/i.test((el.innerText || '').trim()), inline: el.tagName === 'A' && !!el.closest('p, li, td, dd, figcaption') && (el.closest('p, li, td, dd, figcaption').innerText.length > el.innerText.length + 10), text: (el.innerText || el.value || el.getAttribute('aria-label') || el.title || '').trim().replace(/\s+/g, ' ').slice(0, 32), disabled: el.disabled || el.getAttribute('aria-disabled') === 'true', w: Math.round(el.getBoundingClientRect().width), h: Math.round(el.getBoundingClientRect().height) }));
    if (info.disabled || info.labelled || info.textLabel || info.skip) continue;
    try {
      await h.scrollIntoViewIfNeeded({ timeout: 800 });
      await page.mouse.move(1, 1); await page.waitForTimeout(220);
      const before = await h.evaluate((el, s) => (0, eval)(s)(el), snap);
      const b2 = await h.boundingBox();
      await page.mouse.move(b2.x + b2.width / 2, b2.y + b2.height / 2); await page.waitForTimeout(420);
      const hover = await h.evaluate((el, s) => (0, eval)(s)(el), snap);
      let press = hover;
      if (['button', 'summary', 'a'].includes(info.tag) || /button|tab|switch|radio/.test(await h.getAttribute('role') || '')) {
        await page.mouse.down(); await page.waitForTimeout(140);
        press = await h.evaluate((el, s) => (0, eval)(s)(el), snap);
        await page.mouse.move(1, 1); await page.mouse.up();
      }
      rows.push({ ...info, hover: before !== hover, press: press !== hover });
    } catch { /* covered or detached: skip */ }
  }
  // static elements that react to hover (hover lift on things that do nothing)
  const statics = await page.$$eval('section *, main *', (els, sel) => els.filter((el) => { const r = el.getBoundingClientRect(); return r.width > 160 && r.height > 100 && r.width < innerWidth * 0.9 && !el.matches(sel) && !el.closest(sel) && !el.querySelector(sel) && getComputedStyle(el).transitionDuration.split(',').some((d) => parseFloat(d) > 0); }).slice(0, 12).map((el, i) => { el.setAttribute('data-probe-static', i); return i; }), INTERACTIVE);
  const staticHover = [];
  for (const i of statics) {
    const h = await page.$(`[data-probe-static="${i}"]`); if (!h) continue;
    try {
      await h.scrollIntoViewIfNeeded({ timeout: 800 }); await page.mouse.move(1, 1); await page.waitForTimeout(200);
      const before = await h.evaluate((el) => { const c = getComputedStyle(el); return c.transform + c.translate + c.boxShadow; });
      const b = await h.boundingBox(); await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2); await page.waitForTimeout(400);
      const after = await h.evaluate((el) => { const c = getComputedStyle(el); return c.transform + c.translate + c.boxShadow; });
      if (before !== after) staticHover.push(await h.evaluate((el) => (el.innerText || el.className || el.tagName).toString().replace(/\s+/g, ' ').trim().slice(0, 30)));
    } catch { /* skip */ }
  }
  // keyboard: every tab stop shows a ring
  await page.mouse.move(1, 1);
  await page.evaluate(() => { document.activeElement?.blur(); window.scrollTo(0, 0); });
  const focus = [];
  for (let i = 0; i < 30; i++) {
    await page.keyboard.press('Tab'); await page.waitForTimeout(200);
    const f = await page.evaluate(() => {
      const el = document.activeElement; if (!el || el === document.body) return null;
      const cs = getComputedStyle(el); const host = el.closest('label') || el.parentElement; const hs = host ? getComputedStyle(host) : null;
      const ring = (cs.outlineStyle !== 'none' && parseFloat(cs.outlineWidth) > 0) || cs.boxShadow !== 'none' || (hs && ((hs.outlineStyle !== 'none' && parseFloat(hs.outlineWidth) > 0) || hs.boxShadow !== 'none'));
      return { key: el.tagName + (el.id || '') + (el.innerText || el.name || '').slice(0, 20), label: `${el.tagName.toLowerCase()}:${(el.innerText || el.getAttribute('aria-label') || el.name || '').trim().slice(0, 24)}`, ring };
    });
    if (f) { if (focus.some((x) => x.key === f.key)) break; focus.push(f); }
  }
  const pressable = rows.filter((r) => ['button', 'summary'].includes(r.tag));
  return {
    probed: rows.length,
    hover: rows.filter((r) => !r.selected).length ? rows.filter((r) => !r.selected && r.hover).length / rows.filter((r) => !r.selected).length : 1,
    noHover: rows.filter((r) => !r.selected && !r.hover).map((r) => `${r.tag}:${r.text}`),
    press: pressable.length ? pressable.filter((r) => r.press).length / pressable.length : 1,
    noPress: pressable.filter((r) => !r.press).map((r) => `${r.tag}:${r.text}`),
    smallTargets: rows.filter((r) => !r.inline && (r.w < 24 || r.h < 24)).map((r) => `${r.tag}:${r.text} ${r.w}x${r.h}`),
    focusStops: focus.length,
    focus: focus.length ? focus.filter((f) => f.ring).length / focus.length : 0,
    noFocus: focus.filter((f) => !f.ring).map((f) => f.label),
    staticHover,
  };
}

async function filmstrip(page) {
  const h = (await page.evaluateHandle(() => [...document.querySelectorAll('button, a[href]')].find((el) => { const r = el.getBoundingClientRect(); const cs = getComputedStyle(el); return r.top >= 0 && r.bottom < innerHeight && r.width > 60 && r.height >= 32 && cs.backgroundColor !== 'rgba(0, 0, 0, 0)'; }) || null)).asElement();
  if (!h) return null;
  const b = await h.boundingBox();
  const clip = { x: Math.max(0, b.x - 20), y: Math.max(0, b.y - 20), width: b.width + 40, height: b.height + 40 };
  await page.mouse.move(1, 1); await page.waitForTimeout(300);
  const t0 = Date.now(); const files = [];
  await page.mouse.move(b.x + b.width / 2, b.y + b.height / 2);
  for (const t of [0, 50, 100, 160, 260]) { const w = t - (Date.now() - t0); if (w > 0) await page.waitForTimeout(w); const f = path.join(outDir, `cta-hover-${t}ms.png`); await page.screenshot({ path: f, clip }); files.push(f); }
  await page.mouse.down(); await page.waitForTimeout(100); const f = path.join(outDir, 'cta-press.png'); await page.screenshot({ path: f, clip }); files.push(f);
  await page.mouse.move(1, 1); await page.mouse.up();
  return { label: (await h.innerText()).trim().slice(0, 40), files };
}

const browser = await chromium.launch();
const res = {};
for (const [name, viewport] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
  const ctx = await browser.newContext({ viewport });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e).slice(0, 160)));
  page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.(googleapis|gstatic)/.test(m.text())) errors.push(m.text().slice(0, 160)); });
  await page.goto(url, { waitUntil: 'networkidle', timeout: 20000 }).catch(() => {});
  await page.waitForTimeout(2200);
  await page.screenshot({ path: path.join(outDir, `${name}-fold.png`) });
  const a = await audit(page);
  a.scrollRevealed = await scrollReveal(page);
  await page.screenshot({ path: path.join(outDir, `${name}-full.png`), fullPage: true });
  const film = name === 'desktop' ? await filmstrip(page) : null;
  const t = name === 'desktop' ? await touchAudit(page) : null;
  res[name] = { audit: a, touch: t, film, errors };
  await ctx.close();
}
const rctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce' });
const rp = await rctx.newPage();
await rp.goto(url, { waitUntil: 'networkidle', timeout: 20000 }).catch(() => {});
await rp.waitForTimeout(1500);
res.reduced = await rp.evaluate(() => ({ infinite: document.getAnimations().filter((x) => x.playState === 'running' && x.effect && x.effect.getComputedTiming().iterations === Infinity).length }));
await browser.close();

const D = res.desktop.audit, P = res.phone.audit, T = res.desktop.touch;
const pct = (x) => `${Math.round(x * 100)}%`;
const list = (xs, n = 6) => (xs.length ? ' — ' + xs.slice(0, n).join('; ') + (xs.length > n ? ` (+${xs.length - n})` : '') : '');
const rows = [];
const row = (status, id, detail) => rows.push({ status, id, detail });
row(T.hover >= 0.9 ? 'PASS' : 'FAIL', 'hover-feedback', `${pct(T.hover)} of ${T.probed} controls change on hover (current selection exempt)${list(T.noHover)}`);
row(T.press >= 0.9 ? 'PASS' : 'FAIL', 'press-feedback', `${pct(T.press)} of buttons respond to press${list(T.noPress)}`);
row(T.focusStops && T.focus === 1 ? 'PASS' : 'FAIL', 'focus-ring', `${pct(T.focus)} of ${T.focusStops} tab stops show a ring${list(T.noFocus)}`);
row(D.transitionAll === 0 ? 'PASS' : 'FAIL', 'no-transition-all', `${D.transitionAll} elements use transition: all`);
row(D.layoutTransitions === 0 ? 'PASS' : 'FAIL', 'no-layout-transitions', `${D.layoutTransitions} elements transition width/height/position/margin/padding`);
row(D.hiddenInFold === 0 && P.hiddenInFold === 0 ? 'PASS' : 'FAIL', 'visible-after-load', `${D.hiddenInFold} desktop / ${P.hiddenInFold} phone text blocks still invisible in the first screen 2s after load`);
row(D.scrollRevealed < 3 && P.scrollRevealed < 3 ? 'PASS' : 'FAIL', 'no-scroll-reveal', `${Math.max(D.scrollRevealed, P.scrollRevealed)} text blocks only appear once scrolled to`);
row(res.reduced.infinite === 0 ? 'PASS' : 'FAIL', 'reduced-motion', `${res.reduced.infinite} infinite animations still running under reduced motion; media query ${D.reducedMotionCSS ? 'present' : 'absent'}`);
row(T.staticHover.length === 0 ? 'PASS' : 'FAIL', 'no-static-hover', `${T.staticHover.length} non-clickable blocks move or gain shadow on hover${list(T.staticHover, 4)}`);
row(res.desktop.errors.length + res.phone.errors.length === 0 ? 'PASS' : 'FAIL', 'no-console-errors', list([...res.desktop.errors, ...res.phone.errors], 3) || 'none');
row(D.hiddenShown.length === 0 ? 'PASS' : 'FAIL', 'hidden-respected', D.hiddenShown.length ? `elements with the hidden attribute still displayed: ${D.hiddenShown.join(', ')}` : 'none');
row(!P.overflow ? 'PASS' : 'FAIL', 'phone-overflow', P.overflow ? 'page scrolls sideways at 390px' : 'none at 390px');
row(D.hardBuzz.length === 0 ? 'PASS' : 'FAIL', 'slop-copy', D.hardBuzz.length ? D.hardBuzz.join(', ') : 'none');
row(D.gradientText === 0 ? 'PASS' : 'FAIL', 'no-gradient-text', `${D.gradientText} elements`);
row(D.emoji === 0 ? 'PASS' : 'FAIL', 'no-emoji-icons', `${D.emoji} elements contain emoji (mark intentional ones data-emoji-ok)`);
row(D.durations.length >= 2 || D.transitioned < 5 ? 'PASS' : 'WARN', 'tiered-durations', `durations in use: ${D.durations.join(', ') || 'none'} ms`);
row(Math.max(0, ...D.durations) <= 600 ? 'PASS' : 'WARN', 'duration-ceiling', `longest transition ${Math.max(0, ...D.durations)}ms`);
row(D.infiniteRunning === 0 ? 'PASS' : 'WARN', 'no-idle-loops', `${D.infiniteRunning} infinite animations running at rest`);
row(D.softBuzz.length === 0 ? 'PASS' : 'WARN', 'soft-slop-copy', D.softBuzz.join(', ') || 'none');
row(D.emDashPer600 <= 7 ? 'PASS' : 'WARN', 'em-dash-density', `${D.emDashPer600} per 600 words`);
row(D.notXJustY === 0 ? 'PASS' : 'WARN', 'not-x-just-y', `${D.notXJustY} "No X. Just Y." constructions`);
row(!D.twoToneHeadline ? 'PASS' : 'WARN', 'two-tone-headline', D.twoToneHeadline ? 'part of the h1 is set in a second colour' : 'none');
row((D.h1Tracking ?? 0) >= -0.035 ? 'PASS' : 'WARN', 'display-tracking', `h1 letter-spacing ${D.h1Tracking ?? 0}em (word gaps close up past about -0.035em)`);
row(!D.eyebrowPill ? 'PASS' : 'WARN', 'eyebrow-pill', D.eyebrowPill ? `pill above the h1: "${D.eyebrowPill}"` : 'none');
row(D.defaultFonts.length === 0 ? 'PASS' : 'WARN', 'default-fonts', `heading ${D.fonts.heading}, body ${D.fonts.body}, controls ${D.fonts.control}`);
row(D.purpleActions === 0 ? 'PASS' : 'WARN', 'indigo-actions', `${D.purpleActions} buttons/links filled indigo-violet`);
row(D.backdrop <= 2 && D.blobs === 0 ? 'PASS' : 'WARN', 'glass-and-blobs', `${D.backdrop} backdrop-filter, ${D.blobs} heavily blurred blobs`);
row(!D.templateTopBar ? 'PASS' : 'WARN', 'template-top-bar', D.templateTopBar ? `wordmark left, links and a button right, nothing of the client in it (${D.templateTopBar}); see the spec's top-bar row` : 'none');
row(!D.sameHeads ? 'PASS' : 'WARN', 'repeated-section-head', D.sameHeads || 'none');
row(D.literalColours <= 8 ? 'PASS' : 'WARN', 'token-discipline', `${D.literalColours} literal colour values outside custom-property definitions`);
row(T.smallTargets.length === 0 ? 'PASS' : 'WARN', 'target-size', `${T.smallTargets.length} controls under 24px${list(T.smallTargets, 4)}`);
row('INFO', 'filmstrip', res.desktop.film ? `"${res.desktop.film.label}": ${res.desktop.film.files.map((f) => path.basename(f)).join(', ')}` : 'no filled primary action in the first screen');

fs.writeFileSync(path.join(outDir, 'probe.json'), JSON.stringify({ url, rows, raw: res }, null, 2));
if (asJson) console.log(JSON.stringify({ url, rows }, null, 2));
else { for (const r of rows) console.log(`${r.status.padEnd(5)} ${r.id.padEnd(22)} ${r.detail}`); console.log(`\nscreenshots and probe.json: ${outDir}`); }
process.exit(rows.some((r) => r.status === 'FAIL') ? 1 : 0);
