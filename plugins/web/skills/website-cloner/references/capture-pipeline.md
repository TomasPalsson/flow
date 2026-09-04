---
name: capture-pipeline
description: Playwright capture mechanics for cloning — wait discipline, the three animation-freeze classes, consent dismissal, lazy/content-visibility forcing, CDP font detection, and the launch flags that matter. Load before writing or debugging any capture code.
---

# Capture Pipeline — getting a complete, correct render

The default instinct — `page.screenshot({ fullPage: true })` — is the **broken** one. It expands a
virtual canvas without moving the viewport, so `IntersectionObserver`, `content-visibility:auto`,
lazy images, and WebGL never activate. You get a skeleton. The script `scripts/clone-extract.mjs`
already encodes everything below; read this to understand or adapt it.

## The canonical order (never skip a step)

```
launch (throwaway context) → addInitScript (freeze + eager) → route (CORS re-serve)
→ goto(domcontentloaded) → ABORT if auth-walled → networkidle{}.catch
→ dismiss consent → waitForSelector(hero) → SETTLE → screenshot(viewport clip)
```

**SETTLE** = the wait sequence that makes the render real:
1. **Scroll loop** (incremental ~600px steps, ~130ms pause) then back to `scrollTo(0,0)`. Triggers IntersectionObserver, lazy images, `content-visibility:auto` layout.
2. `waitForLoadState('networkidle', {timeout}).catch(()=>{})` — **always catch**; analytics/WebSocket/streaming SSR may never idle.
3. `await document.fonts.ready` → `FontFace.load()` on every `status!=='loaded'` face → `document.fonts.ready` again. (Fonts triggered by the scroll only enter the queue after step 1.)
4. `img.decode()` on incomplete images.
5. Pause animations (next section).
6. Double `requestAnimationFrame` — single rAF fires *before* paint commit.

## Freezing animations — there are THREE classes, each needs a different fix

| Class | Frozen by `animations:'disabled'` / `duration:0`? | Fix |
|-------|---------------------------------------------------|-----|
| Time-based (CSS keyframes, transitions, WAAPI) | ✅ yes | `screenshot({animations:'disabled'})` + `*{animation/transition-duration:.001ms!important}` |
| **Scroll-timeline** (`animation-timeline:scroll()`/`view()`) | ❌ **immune** (no time dimension) | inject `*{animation-timeline:none!important;scroll-timeline:none!important}` AND screenshot at scroll 0 |
| **SVG SMIL** (`<animate>`) | ❌ **immune** (open Playwright bug) | `document.querySelectorAll('svg').forEach(s=>s.pauseAnimations())` + `getAnimations().forEach(a=>a.pause())` |

Scroll-triggered heroes (`opacity:0` until in-view via AOS/GSAP/Framer) screenshot **blank** at
the top. The init-script CSS forces `[data-aos],[style*="opacity:0"]{opacity:1!important;transform:none!important}`.

The `screenshot({ style })` option **pierces shadow DOM automatically** — use it to freeze Web
Components (Shoelace/Lit) without manual shadow-root traversal.

## Consent banners — preset cookies first, DOM-remove as fallback

Pre-set known cookies on the context *before* navigation (cleanest — the dialog never renders):
`OptanonAlertBoxClosed` (OneTrust), `CookieConsent` (Cookiebot), `cookieconsent_status`. Then a
DOM pass removes leftovers by selector (`#onetrust-consent-sdk`, `#CybotCookiebotDialog`,
`.axeptio_mount`, `#truste-consent-track`, …) and a heuristic: `position:fixed/sticky` +
`z-index>999` + text matching `/cookie|consent|gdpr/`. Re-enable body scroll afterward (banners lock it).

## CDP font detection — the only ground truth

`getComputedStyle(el).fontFamily` is **spec-forbidden** from returning the painted font; it gives
the declared stack even when the browser fell back. Use Chrome DevTools Protocol:

```js
const cdp = await page.context().newCDPSession(page);
await cdp.send('DOM.enable'); await cdp.send('CSS.enable');
const { root } = await cdp.send('DOM.getDocument', { depth: -1 });
const { nodeId } = await cdp.send('DOM.querySelector', { nodeId: root.nodeId, selector: 'h1' });
await page.waitForFunction(() => document.fonts.ready);
const { fonts } = await cdp.send('CSS.getPlatformFontsForNode', { nodeId });
// → [{ familyName: 'Inter', isCustomFont: true, glyphCount: 42 }]
// isCustomFont:false on a heading you expected to be a web font = the font FAILED to load.
```

This eliminates the old canvas-width fingerprint hack entirely.

## Launch flags — the footguns

- **`--disable-web-security` must be paired with `bypassCSP:true`** (different layers; either alone fails — GH #20078). Add `--disable-features=IsolateOrigins,site-per-process` only when you need cross-origin **iframe** content. Always a **throwaway** context — this is genuinely insecure; never reuse with real credentials.
- **`--disable-web-security` breaks WebGL** context creation on some drivers. If the hero is Three.js/Spline, capture in a separate launch *without* it; add `--use-angle=gl --enable-gpu-rasterization` for WebGL and screenshot the canvas to a PNG (WebGL can't be rebuilt as CSS).
- **`channel:'chrome'`** (with `headless:true`) renders fonts identically to headed Chrome; the bundled `chrome-headless-shell` has subpixel drift. Use it when typographic fidelity is critical and Chrome is installed.
- **Never** set `PW_TEST_SCREENSHOT_NO_FONTS_READY` — it skips the font wait and renders fallback fonts. Catastrophic for cloning, where font identity *is* the output.
- `serviceWorkers:'block'` on the context is **mandatory** for reliable asset interception — Next/Gatsby/Nuxt SWs answer requests before Playwright sees them.

## SPA / streaming SSR waits

Snapshot the **rendered DOM**, never view-source (SPAs ship an empty shell). `networkidle` is
unreliable for Next.js 15 / React 19 streaming (chunks reset the idle timer). Prefer
`waitForSelector` on a concrete hero element over framework-internal signals like `__NEXT_DATA__`
(version-fragile). The double-rAF at the end is what guarantees the paint committed.

## Fast-path fallback: SingleFile CLI

When you need a self-contained snapshot in one command and editability doesn't matter
(`single-file --browser-headless true --browser-wait-until networkidle0 <url> out.html`), SingleFile
**hooks IntersectionObserver at the API level** (calls callbacks synthetically) rather than
scrolling — categorically better than `fullPage:true` for lazy images. Downside: a 15MB+ frozen
monolith that's painful to brand-swap. Use it for reference/archive, the rebuild for demos.
