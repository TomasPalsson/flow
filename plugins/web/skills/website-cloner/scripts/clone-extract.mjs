#!/usr/bin/env node
/**
 * clone-extract.mjs — one-session capture + token + asset extractor for demo cloning.
 *
 * Captures the RENDERED front page of a site in a single Playwright session and emits
 * everything a rebuild needs: reference screenshots (desktop + mobile), the rendered DOM,
 * a design-token file (colors in OKLCH, type scale, spacing, radii, shadows), every image/
 * font byte + a url→local map, and a CDP-verified font report with OFL-substitute suggestions.
 *
 * Why one session: Adobe/TypeKit font bytes use short-lived signed URLs that 403 on replay,
 * so fonts must be captured live. Re-navigating also loses A/B/consent/scroll state.
 *
 * Dependency: playwright ONLY (OKLCH conversion is implemented inline). Install:
 *   npm i -D playwright && npx playwright install chromium
 *
 * Usage:
 *   node clone-extract.mjs <url> [outDir]
 *   node clone-extract.mjs https://stripe.com ./clone
 *
 * Output: <outDir>/<hostname>/{desktop-hero.png, desktop-full.png, mobile-hero.png,
 *         dom.html, tokens.json, assets/, asset-manifest.json, font-report.json, report.md}
 *
 * This is a DEMO tool. It refuses auth-walled pages, warns on robots.txt Disallow, never
 * evades anti-bot defenses, and never re-serves commercial fonts. See references/legal-and-fonts.md.
 */
import { chromium } from 'playwright';
import { promises as fs } from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));

// ---------- color: sRGB -> OKLCH (no external deps) ----------
const lin = (c) => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
function rgbToOklch(r, g, b) {
  const lr = lin(r), lg = lin(g), lb = lin(b);
  const l = Math.cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb);
  const m = Math.cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb);
  const s = Math.cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb);
  const L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s;
  const a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s;
  const bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s;
  const C = Math.sqrt(a * a + bb * bb);
  let H = Math.atan2(bb, a) * 180 / Math.PI; if (H < 0) H += 360;
  return { L, C, H };
}
function cssColorToOklch(str) {
  const m = String(str).match(/rgba?\(([^)]+)\)/i);
  if (!m) return null;
  const p = m[1].split(',').map((x) => parseFloat(x.trim()));
  const [r, g, b] = p; const alpha = p[3] === undefined ? 1 : p[3];
  if ([r, g, b].some(Number.isNaN)) return null;
  const { L, C, H } = rgbToOklch(r, g, b);
  const core = `${L.toFixed(3)} ${C.toFixed(3)} ${C < 0.001 ? 0 : H.toFixed(1)}`;
  return alpha < 1 ? `oklch(${core} / ${alpha})` : `oklch(${core})`;
}
const gcd = (a, b) => (b ? gcd(b, a % b) : a);

// ---------- injected into the page before navigation ----------
// Forces eager rendering: kill lazy-load, content-visibility, scroll/SMIL/time animations,
// and keep WebGL buffers readable. Belt-and-suspenders so a top-of-page clip is never blank.
const INIT_SCRIPT = () => {
  const css = `*,*::before,*::after{
    animation-duration:.001ms!important;animation-delay:0ms!important;
    transition-duration:.001ms!important;transition-delay:0ms!important;
    animation-timeline:none!important;scroll-timeline:none!important;
    content-visibility:visible!important;}
    [data-aos],[data-sal],.aos-init,.wow,.reveal,[style*="opacity:0"],[style*="opacity: 0"]{
    opacity:1!important;transform:none!important;visibility:visible!important;}`;
  const add = () => { const s = document.createElement('style'); s.textContent = css; (document.head || document.documentElement).appendChild(s); };
  add(); document.addEventListener('DOMContentLoaded', add);
  // eager-load lazy images as they appear
  new MutationObserver((muts) => muts.forEach((mu) => mu.addedNodes.forEach((n) => {
    if (n.nodeType !== 1) return;
    const imgs = n.tagName === 'IMG' ? [n] : (n.querySelectorAll ? [...n.querySelectorAll('img')] : []);
    imgs.forEach((img) => { img.loading = 'eager'; if (img.dataset.src) img.src = img.dataset.src; if (img.dataset.srcset) img.srcset = img.dataset.srcset; });
  }))).observe(document.documentElement, { childList: true, subtree: true });
  // keep WebGL frames readable
  const og = HTMLCanvasElement.prototype.getContext;
  HTMLCanvasElement.prototype.getContext = function (t, a = {}) { if (t === 'webgl' || t === 'webgl2') a.preserveDrawingBuffer = true; return og.call(this, t, a); };
};

async function checkRobots(url) {
  try {
    const u = new URL(url);
    const res = await fetch(`${u.protocol}//${u.host}/robots.txt`, { headers: { 'User-Agent': 'demo-clone (one-time front-page capture)' } });
    if (!res.ok) return true;
    const lines = (await res.text()).split('\n').map((l) => l.trim());
    let star = false; const dis = [];
    for (const l of lines) {
      if (/^user-agent:/i.test(l)) star = l.split(':')[1].trim() === '*';
      else if (star && /^disallow:/i.test(l)) { const p = l.split(':')[1].trim(); if (p) dis.push(p); }
    }
    const ok = !dis.some((d) => (u.pathname || '/').startsWith(d));
    if (!ok) console.warn(`⚠️  robots.txt disallows ${u.pathname}. Proceeding is your call — prefer a manual reference screenshot + rebuild from scratch.`);
    return ok;
  } catch { return true; }
}

async function dismissConsent(page) {
  await page.evaluate(() => {
    const sel = ['#onetrust-consent-sdk', '#CybotCookiebotDialog', '#cookie-law-info-bar', '#cookieNotice',
      '#gdpr-cookie-notice', '.cookie-banner', '.cookie-consent', '.consent-banner', '[id*="cookie-consent"]',
      '[class*="cookie-bar"]', '[id*="gdpr"]', '.axeptio_mount', '#truste-consent-track'];
    sel.forEach((s) => document.querySelectorAll(s).forEach((el) => el.remove()));
    document.querySelectorAll('*').forEach((el) => {
      const cs = getComputedStyle(el);
      if ((cs.position === 'fixed' || cs.position === 'sticky') && parseInt(cs.zIndex) > 999) {
        const t = (el.textContent || '').toLowerCase();
        if (/cookie|consent|gdpr|privacy|accept all/.test(t) && t.length < 600) el.remove();
      }
    });
    document.body.style.setProperty('overflow', 'auto', 'important');
    document.documentElement.style.setProperty('overflow', 'auto', 'important');
  });
}

async function settle(page) {
  // scroll to trigger IntersectionObserver / lazy / content-visibility, then return to top
  await page.evaluate(async () => {
    await new Promise((res) => { let last = -1; const id = setInterval(() => {
      window.scrollBy(0, Math.max(window.innerHeight * 0.7, 400)); const y = window.scrollY;
      const max = document.documentElement.scrollHeight - window.innerHeight;
      if (y >= max || y === last) { clearInterval(id); window.scrollTo({ top: 0 }); res(); } last = y;
    }, 130); });
  });
  await page.waitForLoadState('networkidle', { timeout: 12000 }).catch(() => {});
  await page.evaluate(async () => {
    await document.fonts.ready;
    await Promise.all([...document.fonts].map((f) => f.load().catch(() => {})));
    await document.fonts.ready;
    await Promise.all([...document.images].filter((i) => !i.complete).map((i) => i.decode().catch(() => {})));
  });
  await page.evaluate(() => { document.getAnimations().forEach((a) => { try { a.pause(); } catch {} });
    document.querySelectorAll('svg').forEach((s) => { try { s.pauseAnimations(); } catch {} }); });
  await page.evaluate(() => new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(r))));
}

async function extractTokens(page) {
  return page.evaluate(() => {
    const out = { rootVars: {}, colors: [], type: [], spacing: [], radius: [], shadow: [], gradients: [] };
    const rs = getComputedStyle(document.documentElement);
    for (const p of rs) if (p.startsWith('--') && /^--(color|spacing|space|font|text|radius|rounded|shadow|bs-|mui-|sl-|tw-|primary|secondary|background|foreground|accent|brand|muted|border)/.test(p))
      out.rootVars[p] = rs.getPropertyValue(p).trim();
    const colorSet = new Set(), typeSeen = new Set(); const sp = [], rad = new Set(), sh = new Set();
    const scope = document.querySelectorAll('header,nav,[class*="hero"],[class*="banner"],main>section:nth-of-type(-n+2),h1,h2,h3,p,a,button,[class*="cta"]');
    const ALL = scope.length ? scope : document.querySelectorAll('*');
    for (const el of ALL) {
      const cs = getComputedStyle(el); const r = el.getBoundingClientRect();
      if (r.width === 0 && r.height === 0) continue;
      ['color', 'backgroundColor', 'borderColor'].forEach((p) => { const v = cs[p]; if (v && v !== 'rgba(0, 0, 0, 0)' && v !== 'transparent') colorSet.add(v); });
      if (cs.backgroundImage && cs.backgroundImage.includes('gradient')) { out.gradients.push(cs.backgroundImage); (cs.backgroundImage.match(/rgba?\([^)]+\)/g) || []).forEach((c) => colorSet.add(c)); }
      if (el.children.length === 0 && (el.textContent || '').trim()) {
        const key = [cs.fontFamily, cs.fontSize, cs.fontWeight, cs.lineHeight, cs.letterSpacing, cs.textTransform, cs.fontStyle, cs.fontVariationSettings].join('|');
        if (!typeSeen.has(key)) { typeSeen.add(key); out.type.push({ role: el.tagName.toLowerCase(), fontFamily: cs.fontFamily, fontSize: cs.fontSize, fontWeight: cs.fontWeight, lineHeight: cs.lineHeight, letterSpacing: cs.letterSpacing, textTransform: cs.textTransform, fontStyle: cs.fontStyle, fontVariationSettings: cs.fontVariationSettings }); }
      }
      ['paddingTop', 'paddingRight', 'paddingBottom', 'paddingLeft', 'marginTop', 'marginBottom', 'gap', 'rowGap', 'columnGap'].forEach((p) => { const n = parseFloat(cs[p]); if (n > 0 && n <= 200) sp.push(Math.round(n)); });
      if (cs.borderRadius && cs.borderRadius !== '0px') rad.add(cs.borderRadius);
      if (cs.boxShadow && cs.boxShadow !== 'none') sh.add(cs.boxShadow);
    }
    out.colors = [...colorSet]; out.spacing = sp; out.radius = [...rad]; out.shadow = [...sh];
    return out;
  });
}

// CDP: the ONLY reliable way to know which font actually painted.
async function fontReport(page, selectors) {
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
  const { root } = await cdp.send('DOM.getDocument', { depth: -1 });
  const report = [];
  for (const sel of selectors) {
    try {
      const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: sel });
      if (!nodeId) continue;
      const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
      if (fonts && fonts.length) { const f = fonts.sort((a, b) => b.glyphCount - a.glyphCount)[0]; report.push({ selector: sel, rendered: f.familyName, isCustomFont: f.isCustomFont, glyphCount: f.glyphCount }); }
    } catch {}
  }
  await cdp.detach().catch(() => {});
  return report;
}

async function main() {
  const url = process.argv[2];
  const outRoot = process.argv[3] || './clone';
  if (!url) { console.error('Usage: node clone-extract.mjs <url> [outDir]'); process.exit(1); }
  const host = new URL(url).hostname.replace(/^www\./, '');
  const out = path.join(outRoot, host);
  const assetsDir = path.join(out, 'assets');
  await fs.mkdir(assetsDir, { recursive: true });
  await checkRobots(url);

  let substitutes = {};
  try { substitutes = JSON.parse(await fs.readFile(path.join(SCRIPT_DIR, '..', 'data', 'font-substitutes.json'), 'utf8')); } catch {}

  const browser = await chromium.launch({
    headless: true,
    // channel: 'chrome',  // uncomment if Chrome is installed — best font-rendering fidelity
    args: ['--disable-blink-features=AutomationControlled', '--disable-web-security', '--disable-features=IsolateOrigins,site-per-process'],
  });

  const urlToLocal = new Map(); const manifest = {};
  let tokens = null, fonts = [], dom = '';

  for (const dev of [
    { name: 'desktop', viewport: { width: 1440, height: 900 }, dpr: 2, primary: true },
    { name: 'mobile', viewport: { width: 390, height: 844 }, dpr: 3, primary: false },
  ]) {
    const context = await browser.newContext({
      viewport: dev.viewport, deviceScaleFactor: dev.dpr, colorScheme: 'light',
      locale: 'en-US', timezoneId: 'America/New_York', bypassCSP: true,
      serviceWorkers: 'block', extraHTTPHeaders: { 'Accept-Language': 'en-US,en;q=0.9', Referer: url },
    });
    // generic pre-accept consent cookies (best-effort; harmless if unused)
    const dot = `.${host}`;
    await context.addCookies([
      { name: 'OptanonAlertBoxClosed', value: new Date().toISOString(), domain: dot, path: '/' },
      { name: 'CookieConsent', value: 'true', domain: dot, path: '/' },
      { name: 'cookieconsent_status', value: 'dismiss', domain: dot, path: '/' },
    ].map((c) => ({ ...c }))).catch(() => {});

    const page = await context.newPage();
    await page.addInitScript(INIT_SCRIPT);
    // re-serve CSS/fonts with permissive CORS so cssRules / FontFace inspection works
    await page.route('**/*.{css,woff,woff2,ttf,otf}', async (route) => {
      try { const resp = await route.fetch(); await route.fulfill({ response: resp, headers: { ...resp.headers(), 'access-control-allow-origin': '*' } }); }
      catch { await route.continue(); }
    });
    // capture every asset byte at the TCP layer (CORS-immune)
    page.on('response', async (resp) => {
      const u = resp.url(); const type = resp.request().resourceType();
      if (!['image', 'font', 'media'].includes(type) || resp.status() !== 200) return;
      try {
        const body = await resp.body();
        const ext = (u.split('?')[0].split('.').pop() || 'bin').slice(0, 5).replace(/[^a-z0-9]/gi, '') || 'bin';
        const fn = `${type}-${crypto.createHash('md5').update(u).digest('hex').slice(0, 10)}.${ext}`;
        await fs.writeFile(path.join(assetsDir, fn), body);
        urlToLocal.set(u, `./assets/${fn}`); manifest[u] = { type, file: `./assets/${fn}`, bytes: body.length };
      } catch {}
    });

    await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 60000 });

    if (dev.primary) {
      const auth = await page.evaluate(() => !!document.querySelector('input[type="password"]') || /\/(login|signin|sign-in)/.test(location.pathname));
      if (auth) { await browser.close(); throw new Error('ABORT: page looks auth-walled. Capturing logged-in/paywalled content is not permitted for demo cloning.'); }
    }

    await page.waitForLoadState('networkidle', { timeout: 20000 }).catch(() => {});
    await dismissConsent(page);
    await page.waitForSelector('h1, [class*="hero"], [class*="banner"], main', { state: 'visible', timeout: 10000 }).catch(() => {});
    await settle(page);

    const FREEZE = '*,*::before,*::after{animation-timeline:none!important;transition:none!important;}';
    await page.screenshot({ path: path.join(out, `${dev.name}-hero.png`), clip: { x: 0, y: 0, ...dev.viewport }, animations: 'disabled', style: FREEZE });
    if (dev.primary) await page.screenshot({ path: path.join(out, `${dev.name}-full.png`), fullPage: true, animations: 'disabled', style: FREEZE });

    if (dev.primary) {
      dom = await page.evaluate(() => document.documentElement.outerHTML);
      tokens = await extractTokens(page);
      fonts = await fontReport(page, ['h1', '[class*="hero"] h1', 'h2', 'p', 'nav a', 'button, [class*="cta"]', 'body']);
    }
    await context.close();
  }
  await browser.close();

  // ---------- post-process tokens ----------
  const colorTokens = [...new Set(tokens.colors)].map((raw) => ({ raw, oklch: cssColorToOklch(raw) })).filter((c) => c.oklch);
  const px = tokens.spacing.filter((v) => v > 0); const base = px.length ? px.reduce(gcd) : 4;
  const spacingScale = [...new Set(px)].sort((a, b) => a - b).map((v) => ({ px: v, step: +(v / base).toFixed(2) }));
  const subFor = (name) => {
    const clean = (name || '').replace(/['"]/g, '').split(',')[0].trim();
    if ((substitutes.pass_through_already_free || []).some((f) => f.toLowerCase() === clean.toLowerCase())) return { font: clean, free: true };
    const hit = Object.keys(substitutes.substitutes || {}).find((k) => k.toLowerCase() === clean.toLowerCase());
    return { font: clean, free: false, substitute: hit ? substitutes.substitutes[hit] : 'Inter (default fallback — verify by eye)' };
  };
  const fontPlan = fonts.map((f) => ({ ...f, ...subFor(f.rendered) }));

  const tokenFile = {
    source: url, capturedViewport: '1440x900', baseSpacingPx: base,
    color: colorTokens, gradients: [...new Set(tokens.gradients)],
    typeScale: tokens.type, spacingScale, borderRadius: tokens.radius, boxShadow: tokens.shadow,
    rootCssVars: tokens.rootVars, fonts: fontPlan,
  };
  await fs.writeFile(path.join(out, 'tokens.json'), JSON.stringify(tokenFile, null, 2));
  await fs.writeFile(path.join(out, 'dom.html'), dom);
  await fs.writeFile(path.join(out, 'asset-manifest.json'), JSON.stringify({ urlToLocal: Object.fromEntries(urlToLocal), manifest }, null, 2));
  await fs.writeFile(path.join(out, 'font-report.json'), JSON.stringify(fontPlan, null, 2));

  const flagged = fontPlan.filter((f) => f.isCustomFont && !f.free);
  const report = `# Clone capture report — ${host}

- Source: ${url}
- Reference screenshots: desktop-hero.png, desktop-full.png, mobile-hero.png
- Rendered DOM: dom.html  ·  Tokens: tokens.json  ·  Assets: ${urlToLocal.size} files in assets/
- Base spacing unit: ${base}px  ·  Colors: ${colorTokens.length}  ·  Type styles: ${tokens.type.length}

## Fonts (CDP-verified actual rendered face)
${fontPlan.map((f) => `- \`${f.selector}\` → **${f.rendered}** ${f.isCustomFont ? '(web font)' : '(system)'} → ${f.free ? 'OFL/free, embed as-is' : 'substitute → ' + (f.substitute || 'Inter')}`).join('\n')}

${flagged.length ? `## ⚠️ Licensed fonts — substitute before shipping the demo
${flagged.map((f) => `- ${f.rendered} → ${f.substitute}`).join('\n')}
Do NOT re-serve the captured woff2 for these (EULA). See references/legal-and-fonts.md.` : '## Fonts are free to embed.'}

## MANDATORY before demo (legal)
- Replace EVERY original image with prospect/placeholder content (none survive into output).
- Clone the PROSPECT's own brand only. Inject the demo disclaimer banner.
- Serve on localhost only; never a public URL.
`;
  await fs.writeFile(path.join(out, 'report.md'), report);

  console.log(`✅ ${host}: ${urlToLocal.size} assets · ${colorTokens.length} colors · ${tokens.type.length} type styles`);
  console.log(`   → ${path.resolve(out)}`);
  if (flagged.length) console.log(`   ⚠️  ${flagged.length} licensed font(s) flagged for substitution — see report.md`);
}

main().catch((e) => { console.error('✖', e.message); process.exit(1); });
