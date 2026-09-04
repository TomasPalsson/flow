---
name: pitfalls
description: The failure-mode catalog for site cloning — every way a clone comes out wrong (blank lazy images, invisible scroll-in heroes, wrong font, consent overlays, CSS-in-JS, A/B variants, DPR, wrong viewport) with the WHY and the fix, plus tool-selection trade-offs. Load when a clone looks wrong or to sanity-check an approach.
---

# Pitfalls — why a clone comes out wrong, and the fix

Failures cluster into three roots: **(1)** content that only exists post-JS or post-scroll, **(2)**
assets the browser blocks cross-origin, **(3)** visual state that depends on scroll position. Each
row below is a real, documented failure mode.

## Render-completeness failures

| Symptom | Why | Fix |
|---------|-----|-----|
| Hero images blank / placeholders | `fullPage:true` never scrolls → IntersectionObserver never fires | Scroll loop → back to top → viewport-clip screenshot (capture-pipeline.md) |
| Hero is white / empty | Scroll-triggered `opacity:0` (AOS/GSAP/Framer) captured pre-animation | init-script `*{opacity:1!important;transform:none!important}` on animated selectors |
| Empty `<div id="root">` | SPA ships a JS shell; wget/curl/HTTrack see only that | Use Playwright (real engine); snapshot rendered DOM |
| Stale placeholder content | Screenshot taken mid-hydration | `waitForSelector` on a real hero element + `img.naturalWidth>0` |
| Grey skeleton boxes | Captured before data fetch returned | wait for `[class*="skeleton"]` hidden / `aria-busy="false"` |
| Section below fold missing | `content-visibility:auto` skips layout until near viewport | scroll pass + inject `*{content-visibility:visible!important}` |
| Animation captured mid-motion | time-anim not frozen | `animations:'disabled'` + duration:0 + `getAnimations().pause()` |
| Animated SVG / scroll-timeline still moving | both **immune** to `animations:'disabled'` | `svg.pauseAnimations()`; inject `animation-timeline:none!important`; screenshot at scroll 0 |

## Asset / CORS failures

| Symptom | Why | Fix |
|---------|-----|-----|
| Fonts render as system fallback | web-font CORS 403 in headless, or FOUT mid-screenshot | `page.route` re-serve fonts with `ACAO:*`; `document.fonts.ready` + `FontFace.load()` |
| Wrong font, but you "matched" fontFamily | `getComputedStyle().fontFamily` is the declared stack, not the painted font | CDP `CSS.getPlatformFontsForNode` (`isCustomFont` reveals fallback) |
| `font-display:optional` never swaps in | one-shot 100ms block window missed | `FontFace.load()` is the only escape; preload as a last resort |
| Many requests invisible to interception | a Service Worker answered first (Next/Gatsby/Nuxt) | `serviceWorkers:'block'` on the context (mandatory) |
| Tainted-canvas SecurityError | `html2canvas`/`dom-to-image` + cross-origin image | use Playwright `response.body()` (TCP-layer, CORS-immune) — don't use canvas libs on third-party sites |
| `cssRules` throws SecurityError | cross-origin stylesheet | `page.route` re-serve; or use `document.fonts` + computed `:root` vars; always `try/catch` per sheet |

## "Looks right locally, wrong to the prospect"

| Symptom | Why | Fix |
|---------|-----|-----|
| Different headline/CTA than prospect sees | A/B test (Optimizely/VWO) assigns variant by cookie/IP | pin the variant cookie, or capture from the prospect's perspective |
| Wrong language / cookie wall | geo/locale routing by IP | set `locale`/`Accept-Language`/`timezoneId`; `en-US` often dodges the EU GDPR variant |
| Whole layout off | wrong viewport captured (`clamp()`/grid resolve per width) | lock to the demo viewport (1440×900); capture mobile separately at 390 |
| Blurry on Retina | `deviceScaleFactor:1` default | `deviceScaleFactor:2` for screenshots (DPR 1 only for measurement — rects are CSS px regardless) |
| Dark clone of a light site | headless inherits machine `prefers-color-scheme` | set `colorScheme:'light'` on the context |
| Consent modal covers hero | OneTrust/Cookiebot/Axeptio overlay | preset consent cookies + DOM-remove fallback (capture-pipeline.md) |
| Transparent nav looks wrong | nav starts transparent, solidifies on scroll | decide the state; nudge scroll then back, or toggle the `scrolled` class |
| Chat widget in the corner | Intercom/Drift inject delayed iframes | `page.route('**/{intercom,drift,zopim,tawk}**', r=>r.abort())` |

## Structure-copy failures

- **Pseudo-elements & CSS `background-image` vanish on `cloneNode()`** — they live in the paint layer, not the DOM. Decorative overlays, gradient tints, icon glyphs disappear. Screenshot-first for fidelity; inline computed `background-image`/`::before` if you need editable HTML.
- **CSS-in-JS hashed classnames** (`.sc-bdfxgF`, `.css-1a2b3c`) are runtime-generated and may differ per load. Copying HTML without the injected `<style>` tags yields an unstyled page. Read computed styles, ignore the class names.
- **`:visited` link colors are deliberately wrong** (anti history-sniffing) — nav link colors from getComputedStyle may be off on first visit.
- **Icon-font logos** (`::before{content:"\e900";font-family:Icons}`) are invisible as image assets — capture the woff2 + replicate the CSS, or screenshot the glyph.

## Tool selection (one-liner each)

Playwright = primary (full render + CDP + interception). SingleFile CLI = fast monolith fallback
(hooks IntersectionObserver). Wappalyzer = stack recon, run first. monolith/wget/HTTrack = **dead on
SPAs** (no JS engine). html2canvas/dom-to-image = canvas-taint on third-party assets, avoid. Urlbox/
ScreenshotOne = paid fallback **only** when the target blocks headless — and if it actively blocks
you, that's a stop signal, not a workaround (legal-and-fonts.md). AI cloners (v0) = ~70–80% skeleton,
always needs a token-patch pass.
