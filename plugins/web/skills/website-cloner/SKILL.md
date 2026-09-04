---
name: website-cloner
description: >-
  Use WHENEVER the user wants to clone, copy, replicate, recreate, or mirror a website or landing
  page, "make our demo look like the customer's site", personalize/white-label a demo for a
  prospect, extract a site's design (styles, fonts, colors, design tokens, exact pixel sizing) from
  a URL, capture/screenshot a page faithfully with Playwright, or figure out what font/colors a
  site uses. Trigger phrases: "clone this site", "copy this website", "recreate this landing page",
  "rebuild their homepage", "extract the styles/fonts", "match this design", "demo on their own
  branding". Reproduces a site's hero / above-the-fold and reskins it with the prospect's brand.
---

# Website Cloner — front-page clones for sales demos

You are reproducing a site's **front page** faithfully enough that a prospect sees their own brand
on a familiar-looking layout. The output is an editable, locally-served clone — not a screenshot.

The naive approach fails predictably — `fullPage` screenshot, trusting `fontFamily`, copying the DOM,
eyeballing colors, a needless responsive rebuild, keeping the original assets — and each failure is
corrected below. **Default to running `scripts/clone-extract.mjs`**, which bakes in every mitigation,
then rebuild and reskin from its output.

## Before anything: the legal gate (non-negotiable)

```
Is it the PROSPECT's own site?           no  → stop; get sign-off or use a generic reference
Does it require login / paywall?         yes → ABORT (never capture gated content)
robots.txt disallows the path?           yes → manual screenshot + rebuild, don't scrape
Site actively blocks bots (Cloudflare)?  yes → stop signal — do NOT evade
```
Then, always: **replace every original image**, **substitute commercial fonts with OFL**, **clone
the prospect's brand only**, **inject the demo disclaimer**, **serve on localhost only — never a
public URL**. **MANDATORY — READ ENTIRE FILE before capturing or shipping**: load
[`references/legal-and-fonts.md`](references/legal-and-fonts.md).

**Reference loading (strict):** load each `references/` file ONLY at the step that names it — never
front-load all five, and do NOT load a step's reference before you reach that step. Early loads:
`legal-and-fonts.md` (legal gate, above) and `pitfalls.md` (Step 0). Just-in-time: `capture-pipeline.md`
(Step 1), `token-extraction.md` (Step 2), `rebuild-and-reskin.md` (Steps 3–5).

## The pipeline

### Step 0 — Recon + capture decisions (1–2 min)
`npx wappalyzer <url> --pretty` → CSS framework (Tailwind v3/v4, Bootstrap, custom), JS framework,
font service, and blockers (WebGL hero, Cloudflare, login). The stack picks your token strategy
(Tailwind v4 → read `:root` vars directly; custom CSS → full computed extraction). No Wappalyzer?
Infer from the page: `__NEXT_DATA__`/`/_next/` → Next.js, `--tw-`/`@theme` → Tailwind v3/v4,
`--bs-` → Bootstrap, `--mui-` → MUI; **default to full computed extraction when unsure**. **Decide now**
(these are pre-capture, not fixable later): target viewport (default 1440×900), `colorScheme`
(match what the prospect sees, usually `light`), and whether the page runs an A/B test or geo
variant you must pin. Several fidelity failures are decisions made here, not bugs found later, so
read the catalog **before** capturing. **MANDATORY — READ ENTIRE FILE now**: load
[`references/pitfalls.md`](references/pitfalls.md) (covers the pre-capture decisions: DPR,
dark-mode, A/B variant, wrong viewport, transparent-nav). Re-consult it later if a clone still
looks wrong.

### Step 1 — Capture + extract (one Playwright session)
Run the workhorse. It captures the **rendered** page in a single session (font bytes can't be
re-fetched later) and emits screenshots, the DOM, tokens, assets, and a CDP-verified font report:

```bash
npm i -D playwright && npx playwright install chromium   # first time
node scripts/clone-extract.mjs https://prospect.com ./clone
# → ./clone/prospect.com/{desktop-hero.png, desktop-full.png, mobile-hero.png,
#     dom.html, tokens.json, asset-manifest.json, font-report.json, report.md, assets/}
```

It already handles: scroll-to-trigger lazy load, the three animation-freeze classes, consent
banners, font-CORS re-serve, `serviceWorkers:'block'`, CDP font detection, auth-wall abort, OKLCH
token conversion, spacing-GCD, and OFL substitute suggestions. **Read `report.md` first** — it flags
licensed fonts to substitute. To understand or adapt the capture mechanics, **MANDATORY — READ
ENTIRE FILE**: load [`references/capture-pipeline.md`](references/capture-pipeline.md). Do NOT reload
it once the capture succeeded — only revisit if a screenshot is blank or in the wrong state.

### Step 2 — Refine the tokens
**How much refinement?** Tailwind v4 detected (Step 0) **and** `tokens.json` has ≤20 colors → the
`:root` vars are already a clean token set; just verify fonts and move on. Custom CSS, or >40 raw
colors → cluster in Oklab down to a 12–20 token palette. Any heading showing `isCustomFont:false`
in `font-report.json` → the web font **failed to load during capture**; fix the capture (font CORS /
wait discipline) before trusting any token.

`tokens.json` is a first pass. Refine against `desktop-hero.png`: confirm the **CDP-verified** fonts
(never `fontFamily`), tighten the palette to **12–20 OKLCH tokens** clustered by role, name the
spacing scale off the detected base unit, and capture fluid `clamp()` type. For token work,
**MANDATORY — READ ENTIRE FILE**: load [`references/token-extraction.md`](references/token-extraction.md).
**Done when:** ≤20 color tokens, every hero font CDP-confirmed (licensed ones mapped to a
substitute in `report.md`), spacing named off the base unit. **Not done if:** >40 raw colors
remain (you haven't clustered — re-cluster in Oklab) or any hero font is still the declared stack
rather than the painted face. Do NOT reload `token-extraction.md` once tokens are clean — only if
colors or fonts still look off after a rebuild pass.

### Step 3 — Rebuild the minimum slice
Build **nav + hero + one section** as a **fixed-width 1440px** clone (responsive is ~10x the work
for zero demo benefit; wrap in `transform:scale()` for smaller screens). Apply `tokens.json` as
`:root` vars; rewrite asset URLs from `asset-manifest.json` (sort by length desc); inline SVG logos;
preserve exact `z-index`. **MANDATORY — READ ENTIRE FILE**: load
[`references/rebuild-and-reskin.md`](references/rebuild-and-reskin.md). It also covers Steps 4–5 —
keep it loaded through serving; do NOT reload it per step.

### Step 4 — Brand-swap for the prospect
**First, make sure you have the inputs** — the swap is the entire point of the demo. If the
prospect's logo, brand color, or headline copy aren't in hand, **ask for them before starting**
(don't invent a logo or guess the brand color). Then: logo (match original dimensions) · primary
color (compute the hue delta between the original and the prospect's primary in OKLCH, then apply
that **same delta to every `--color-*` token** so the whole palette shifts coherently — keep each
token's lightness and chroma) · headline/subhead text only · CTA text+href · hero image · **all**
remaining images → prospect/placeholder · licensed fonts → OFL substitute. No original image survives.

### Step 5 — Harden, serve & accept
Strip analytics/tracking/chat scripts; add the disclaimer banner + `noindex`; freeze leftover
animations; `python -m http.server 8080` (localhost only); test in a clean profile; final screenshot
→ visually diff against `desktop-hero.png` and trace discrepancies back to tokens or URL rewriting.
**Accept when:** layout matches within ~10px, colors are visually indistinguishable, and fonts read
correctly (a 1–3px width drift from an OFL substitute is expected and fine — do not chase it).
**Must fix before showing:** any blank/placeholder image, layout offset >10px, a wrong-weight or
fallback font (serif where the original is sans), or a missing hero background. Trace each back to a
specific step — blank image → Step 1 capture; wrong color → Step 2 tokens; broken asset → Step 3
URL rewrite.

## When a clone looks wrong

Blank images, invisible hero, wrong font, consent overlay, off layout, blurry, dark-when-it-should-
be-light — these are catalogued failure modes, each with a WHY and a fix. **MANDATORY — READ ENTIRE
FILE when debugging fidelity**: load [`references/pitfalls.md`](references/pitfalls.md).

## Expert decision frameworks

- **Snapshot the rendered DOM, never view-source.** SPAs ship an empty shell.
- **Fixed-width single-viewport > responsive rebuild** for demos. Always, unless multi-device is the point.
- **Minimum convincing slice = nav + hero + one section**, not the whole page.
- **Strategy choice:** editable brand-swap demo → clean rebuild (default). Throwaway screenshot demo, <30 min → SingleFile CLI monolith. Never wget/HTTrack/monolith on a modern (JS) site.
- **Font identity comes from CDP**, never `getComputedStyle().fontFamily`.
- **One capture session.** Adobe/TypeKit font bytes use signed URLs that 403 on replay; A/B/consent/scroll state is lost on re-navigation.

## Footgun cheat-sheet (high-confidence, easy to get wrong)

| Trap | Reality |
|------|---------|
| `screenshot({fullPage:true})` | Never scrolls the viewport → lazy/IO/content-visibility/WebGL blank. Scroll first, then viewport-clip. |
| `getComputedStyle().fontFamily` | Declared stack, not painted font. Use CDP `CSS.getPlatformFontsForNode`. |
| returning `getComputedStyle(el)` from `evaluate` | Live object → serializes to `{}`. Destructure inside; read longhands (not `font` shorthand). |
| `--disable-web-security` alone | Needs `bypassCSP:true` too (GH #20078). And it **breaks WebGL** — separate launch for WebGL heroes. |
| `animations:'disabled'` | Misses scroll-timeline (inject `animation-timeline:none`) and SVG SMIL (`svg.pauseAnimations()`). |
| `networkidle` as the ready signal | Hangs on analytics/streaming SSR; always `.catch()`, and `waitForSelector` a hero element. |
| `PW_TEST_SCREENSHOT_NO_FONTS_READY` | Renders fallback fonts — catastrophic for cloning. Never set it. |
| missing `serviceWorkers:'block'` | SW answers before interception → assets vanish (Next/Gatsby/Nuxt). |
| keeping original images/fonts | Legal landmine — replace images, substitute commercial fonts (OFL). |
| `deviceScaleFactor:1` screenshots | Blurry on Retina. DPR 2 for screenshots; DPR 1 only for measurement. |
| public-URL "easy sharing" | Never. Collapses every legal defense. Localhost / screen-share only. |
