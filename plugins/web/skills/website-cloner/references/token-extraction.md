---
name: token-extraction
description: Turning a computed-style dump into a clean, re-skinnable design-token set — colors to OKLCH, type scale, spacing via GCD, radii/shadows, framework token detection (Tailwind/Bootstrap/MUI/shadcn), and the getComputedStyle live-object trap. Load when extracting or refining design tokens.
---

# Token Extraction — style dump → ~80 reusable tokens

Goal: collapse a 3,000-value computed-style dump into a small, semantically-named token set the
demo can be **re-skinned** from by changing a few values. `scripts/clone-extract.mjs` emits a first
pass into `tokens.json`; refine by hand against the reference screenshot.

## The `getComputedStyle` live-object trap (read first)

`getComputedStyle` returns a **live** `CSSStyleDeclaration`. Returning it from `page.evaluate`
serializes to `{}` / numeric indices — silent data loss. **Always destructure to a plain object
inside the evaluate**, and read **longhands** (`fontFamily`,`fontSize`,…) — the `font` shorthand
serializes empty in most browsers. Values are *resolved*: `2em`→`32px`, `hsl()`→`rgb()`, `50%`→px.
For cloning that's a feature (you get the real rendered geometry); just know authored units are gone.

## Colors → OKLCH

Harvest `color`/`backgroundColor`/`borderColor` from above-fold elements; pull gradient stops
separately (a gradient element's `backgroundColor` is `rgba(0,0,0,0)` — the colors live in
`backgroundImage`). Convert every `rgb()` to OKLCH (the script does this inline, no dependency) and
**cluster in Oklab space**, not sRGB — Euclidean distance in sRGB is perceptually wrong. Use the
elbow method, k≈5–8 for a hero. Heuristics: neutrals `C<0.04` (split by lightness → surface/border/
text); the highest-mass chromatic cluster is **primary**; a second cluster >30° hue away is a true
**accent**. Aim for **12–20 color tokens** — over-tokenizing makes re-skinning harder.

Output OKLCH in the token file even if the source was hex: re-skinning by lightness/chroma slider
beats a color picker, and it preserves perceptual relationships when you rotate to the prospect's hue.

## CSS custom properties — the resolution problem

`getComputedStyle(el).getPropertyValue('--x')` returns the **literal string**, including any nested
`var()` — not the resolved color. Two escapes:
- **`@property`-registered vars DO resolve** via getComputedStyle (the browser knows their type). Tailwind v4 uses `@property` for interpolatable tokens, so v4 extraction "just works."
- For plain `--vars`, use a **probe element**: set `el.style.color = var(--x)`, read back `getComputedStyle(el).color` → resolved `rgb()`.

## Framework detection → shortcut the extraction

| Framework | Fingerprint | Strategy |
|-----------|-------------|----------|
| Tailwind v4 | `@theme` block, `--color-*`/`--spacing-*` on `:root`, `@import "tailwindcss"` | **Read `:root` vars directly — one call harvests the whole token set.** |
| Tailwind v3 | `--tw-*` vars, numeric class suffixes (`px-6`,`text-blue-600`) | Infer from class names + default scale (`px-6`→`1.5rem`). |
| Bootstrap 5 | `--bs-*` on `:root` | Direct var read. |
| MUI | `--mui-*` or `.Mui*` | `--mui-palette-primary-main` etc. |
| shadcn/ui | unprefixed `--background`,`--primary`,`--radius` | Direct var read. |
| Vanilla | no prefix pattern | Full computed-style extraction. |

Run `npx wappalyzer <url> --pretty` first — 2 minutes of recon picks the right path. Filter `:root`
vars to design-token prefixes; Intercom/analytics inject 40+ junk `--intercom-*` vars.

Tailwind v4 wraps `@theme` tokens in `@layer theme`; iterating `cssRules` expecting only
`CSSStyleRule` silently skips them. Handle `CSSLayerBlockRule`, or just read computed `:root` vars
(cascade already resolved — origin-independent).

## Type scale

Font **identity** comes from CDP `CSS.getPlatformFontsForNode` (see capture-pipeline.md), never
`fontFamily`. For the scale, dedupe by the tuple `(fontFamily,fontSize,fontWeight,lineHeight,
letterSpacing,textTransform,fontStyle,fontVariationSettings)` and map each to a role (h1/h2/body/
caption/CTA). Variable fonts: `font-weight:650` is valid and real — don't round it; capture
`fontVariationSettings` axes (`wght`,`opsz`,`slnt`) verbatim. For fluid `clamp()` font sizes, Typed
OM `el.computedStyleMap().get('font-size')` yields a `CSSMathClamp` with `.lower/.value/.upper`
(reliable for font-size/gap; width/height usually resolve to px — fall back to the px value).

## Spacing, radius, shadow

You won't find a scale — reconstruct it. Collect `padding-*`/`margin-*`/`gap` px values from the
hero, **drop values > viewport/8** (auto-margins, not scale), build a frequency histogram, and take
the **GCD of the frequent values** — almost always 4 or 8px (the base unit). Name by `value/base`.
Radii cluster into 3–5 values (`sm/md/lg/full`). Multi-layer `box-shadow` is comma-separated but
colors contain commas too — split with a paren-aware parser, not a naive `,`.

## Output format

Target **DTCG v1.0** (`$type`/`$value`/`$description`/`$extensions`, stable since Oct 2025) so
`style-dictionary` can emit a Tailwind config or `:root`/`@theme` block. Store fluid sizes as
`clamp(...)` with min/max in `$extensions`. For dark-mode sites, run extraction twice with
`page.emulateMedia({colorScheme:'dark'})` → `tokens.light.json` + `tokens.dark.json`.
