---
name: rebuild-and-reskin
description: Turning captured tokens + assets into an editable, brand-swapped, demo-hardened clone — scaffold the minimum slice, fixed-width vs responsive, the brand-swap checklist, URL rewriting, serving locally, packaging, and handling iframes/WebGL. Load when building the clone HTML or reskinning for a prospect.
---

# Rebuild & Reskin — from capture to a convincing prospect demo

## Pick the strategy

| Strategy | When | Trade |
|----------|------|-------|
| **A — SingleFile/monolith snapshot** | <30 min, screenshot/screen-share demo, no editing | Instant, self-contained; frozen 15MB file, painful to brand-swap |
| **B — wget/HTTrack mirror** | (almost never) static site only | No JS engine → empty shells on any SPA; broken CDN paths |
| **C — Clean rebuild from tokens** | brand-swap, click-through, reuse across prospects | Most editable; ~2–4h |

Default to **C** for any demo that needs the prospect's brand in it.

## Scaffold the MINIMUM slice

Build **nav + hero + ONE social-proof/feature section** — not the page. It's ~10x less work, loads
fast, and is all a sales call shows. Either trim `dom.html` to the above-fold region, or build fresh
HTML using `tokens.json` as `:root` CSS variables (cleaner to reskin).

## Fixed-width beats responsive (~10x, identical demo result)

Build a **fixed 1440px** clone (the laptop viewport you captured at). Wrap in `transform: scale()`
to fit a narrower projector. A fully responsive rebuild is 3x the work for zero demo benefit — the
prospect isn't on a phone during the call. Keep these as-is, don't hardcode:
- `min-height:100vh` heroes → keep `100vh` (hardcoded px breaks on other screens).
- `aspect-ratio` → apply the computed ratio string directly (`16 / 9`).
- exact `z-index` values from computed styles — **never flatten to 1,2,3**; sites use 10/100/1000 as intentional layers.
- `position:sticky` nav → convert to `position:fixed;top:0` + `padding-top:<header height>` on the hero.
- `transform:matrix(...)` → apply the matrix directly; don't reverse-engineer the shorthand.

## Make it self-contained — rewrite asset URLs

Use the `urlToLocal` map from `asset-manifest.json`. Replace remote URLs with local paths, **sorting
entries by URL length descending** so a short URL doesn't partially replace inside a longer one.
Inline SVG logos from `dom.html` (`querySelectorAll('svg').outerHTML`). For Next.js
`/_next/image?url=…` proxies, decode the `url` param and use the original at full res; for
Cloudinary/Imgix, strip `w_`/`q_`/`f_` transform params for the highest-quality source.

## Brand-swap checklist (the demo payoff)

1. **Logo** → prospect's logo; match the original element's `height`/`width` exactly (avoid layout shift).
2. **Primary color** → find `--color-primary`/`--brand`/etc. and change it; if hardcoded, replace every instance. Rotate the OKLCH hue and keep lightness/chroma relationships intact.
3. **Headline + subhead** → replace **text content only**; keep wrapping elements, classes, inline styles.
4. **CTA** → change text; point `href` to the demo URL or `#`.
5. **Hero image/background** → prospect-relevant image (their office/product, or CC0 from Unsplash/Pexels). **No original image survives.**
6. **All other images** → prospect content or placeholders (e.g. `https://placehold.co/WxH`).
7. **Fonts** → if `font-report.json` flags a licensed font, set the OFL substitute on `:root` (see legal-and-fonts.md). Never re-serve the captured commercial woff2.

## Demo-harden before showing

```html
<!-- top of <body>: mandatory disclaimer, 37px, doesn't obscure the hero -->
<div style="position:fixed;top:0;left:0;right:0;z-index:2147483647;background:#1e293b;
  color:#f1f5f9;font:13px system-ui;padding:8px 16px;text-align:center;border-bottom:2px solid #f59e0b;">
  DEMO ONLY — Visual mockup for a sales demonstration. Not affiliated with or endorsed by any third party.
</div><style>body{padding-top:37px!important}</style>
```
- Strip analytics/tracking/chat scripts (Segment, GA, Intercom, Drift, Hotjar) — they throw console errors and fire network requests mid-demo.
- Add `<meta name="robots" content="noindex,nofollow">`.
- Freeze leftover animations: `*{animation-play-state:paused!important}` **except** intentional CTA hover.
- Test in a **clean browser profile** (no extensions; ad blockers can break remaining scripts).

## Serve & package

- Local only: `python -m http.server 8080` or `bun --serve` in the clone dir. **Never** push to a public URL (legal + phishing exposure — see legal-and-fonts.md).
- Remote demo: screen-share, or a **password-protected** internal preview with no public DNS. Subset fonts and compress images so it loads instantly on an unfamiliar connection.
- Handoff: zip the clone dir with **relative** asset paths; verify it opens from `file://` or a fresh `http.server`.

## Hard cases

- **Cross-origin iframes** (Vimeo/Wistia/HubSpot/Intercom): screenshot the embed to a static PNG and drop it in as a placeholder — don't fight Site Isolation for a demo.
- **WebGL/Three.js/Spline hero**: cannot be rebuilt as CSS. Use the captured canvas PNG as a static hero background (or a short `<video>` loop).
- **Canvas/`<video>` heroes**: same — static frame as background image.

## On AI screenshot-to-code (v0, etc.)

Useful for a fast skeleton (~70–80% structure), but colors and typography drift every time. Always
follow with a token-patch pass using the CDP-verified values from `tokens.json` — AI skeleton +
computed-token patch is faster than either alone, but the patch is non-optional for demo fidelity.
