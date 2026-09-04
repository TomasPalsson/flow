---
name: visual-craft
description: Expert-level craft numbers and CSS patterns for typography, color, spacing, motion, and depth. Load only when SKILL.md Phase 3 body rules are insufficient for a specific decision.
---

# Visual Craft — Expert Reference

This reference covers the specific numbers, CSS patterns, and rules that separate engineer-built UI from designer-quality UI. Load only when you need a value not covered in the SKILL.md Phase 3 body.

---

## Typography

### Modular Scales — Ratio Selection

A modular scale is a sequence of sizes derived by repeatedly multiplying a base size by a fixed ratio.

| Ratio | Name | Character | Best for |
|-------|------|-----------|----------|
| 1.125 | Major second | Very tight | Dense data UIs, dashboards with 7-8 size steps |
| 1.25 | Major third | Default | Most product UIs; enough contrast for hierarchy without drama |
| 1.333 | Perfect fourth | Moderate drama | Marketing pages, editorial products needing expressive headings |
| 1.5 | Perfect fifth | High drama | Display-focused; only practical with 4 or fewer steps |
| 1.618 | Golden ratio | Theoretical | Selective use; step 5 at 16px base is already 109px |

**Practical 7-step scale at 1.25 from 16px base:**
- xs: 10px (0.64rem)
- sm: 12px (0.8rem)
- base: 16px (1rem)
- lg: 20px (1.25rem)
- xl: 24px (1.5rem)
- 2xl: 32px (2rem)
- 3xl: 40px (2.5rem)

**When to break the scale:** Call sizes that serve a specific role (small label, caption, hero number) may live off-scale. The rule: breaking must be intentional and rare.

### Type Pairing Archetypes

The goal: controlled contrast — two typefaces that share one structural attribute while differing in another.

Proven pairs:
- **Old-style serif + Humanist sans** — Garamond / Lucida Grande. Shared humanist construction, differ by serif presence.
- **Transitional serif + Geometric sans** — Baskerville / Futura. Shared high contrast, differ by calligraphic vs. strict geometry.
- **Single-family pair (expert shortcut)** — Variable typeface at extreme weight + optical size differences. Mona Sans 800 @ 64px beside 400 @ 16px reads as a pair with guaranteed harmony.

Rules:
1. Never pair two typefaces from the same classification at similar weights.
2. One font is dominant (display/heading), the other subordinate (body/UI).
3. Mood must align — playful rounded geometric beside austere transitional serif creates cognitive dissonance even when technically "correct."
4. Pick fonts with ≥5 weights — fewer signals lower foundry investment.

### High-Signal Fonts

**Elevating choices:**
- **Söhne** (Klim Type, paid) — Swiss grotesque with digital refinement. High craft. Used by Linear, Figma.
- **GT America** (Grilli Type, paid) — Bridges American gothic and European grotesque. Versatile.
- **Neue Montreal** (Pangram Pangram, free) — Contemporary fashion/tech crossover feel.
- **Geist / Geist Mono** (Vercel, free) — Swiss-inspired. Excellent for developer products.
- **Mona Sans** (GitHub, free, variable) — 24 styles. Pairs with Hubot Sans for code.
- **Satoshi** (Fontshare, free) — Geometric-humanist hybrid. Popular in SaaS.
- **Instrument Serif** (Instrument, free) — High-contrast serif display face. Luxurious.
- **Fraunces** (Google Fonts, free, variable) — Decorative serif with optical sizing.
- **Bricolage Grotesque** (Google Fonts, free, variable) — Playful grotesque with slight quirk.
- **Redaction** (Titus Kaphar, free) — Photocopied-feel serif; editorial/literary.
- **JetBrains Mono / Commit Mono / Berkeley Mono** — Monospace with character.

**Avoid as defaults:**
- **Inter** — Ubiquitous. Fine font, but signals "no decision made."
- **Space Grotesk** — Anthropic's own docs flag this: "NEVER converge on Space Grotesk."
- **Poppins** — Circular geometric, lacks optical refinement. Overused.
- **Roboto** — Android default; signals absence of design attention.
- **Lato** — Clean but invisible.
- **Raleway** — Fashion display font misused as body for a decade.
- **Arial / Times / system-ui** — System fallbacks; signal absence of design.

### Line-Height Rules by Use

- **Body text:** 1.4-1.6 × font size (Butterick: 120-145% of point size)
- **Headings / display:** 1.0-1.2 × font size (tighter because readers scan)
- **UI labels / one-liners:** 1.0-1.25 × font size
- **Captions / dense data:** 1.3 × font size

### Letter-Spacing Rules by Context

- **Body text:** 0em (default). Never add positive tracking to body.
- **ALL CAPS / small caps:** +0.05em to +0.12em. Uppercase was designed for mixed case setting.
- **Display headings >48px:** -0.02em to -0.04em. Large type at default tracking looks loose and amateur.
- **UI labels 10-13px:** +0.01em to +0.02em for legibility at small sizes.
- **Monospaced code:** 0em or slight negative (-0.01em) to prevent runaway line widths.

### Font Loading Performance Stack

```css
/* 1. font-display: swap eliminates FOIT */
@font-face {
  font-family: 'YourFont';
  src: url('your-font.woff2') format('woff2');
  font-display: swap;
  /* 2. size-adjust to match fallback metrics and eliminate FOUT jump */
  size-adjust: 100%;
  ascent-override: 90%;
  descent-override: 22%;
  line-gap-override: 0%;
}
```

```html
<!-- 3. Preload critical fonts (1-2 above-fold weights only) -->
<link rel="preload" href="/fonts/your-font.woff2" as="font" type="font/woff2" crossorigin>
```

- WOFF2 only — best compression, universal support in 2025
- Variable fonts merge multiple weights into one file
- `font-optical-sizing: auto` for variable fonts with `opsz` axis

---

## Color

### OKLCH Reference

OKLCH (Björn Ottosson, 2020) has three axes:
- **L** — perceived lightness, 0-1
- **C** — chroma (~0-0.37 for sRGB)
- **H** — hue, 0-360°

Key practical rules:
- All backgrounds with L ≥ 0.87 have good contrast with black text
- sRGB maximum safe chroma across all hues: below 0.37
- For neutral grays: chroma 0.005-0.01, any hue (imperceptible but cohesive)

### 9-Step OKLCH Palette Generation

```
Lightness progression: 0.97 → 0.89 → 0.80 → 0.71 → 0.60 → 0.49 → 0.38 → 0.25 → 0.12
Chroma curve:          0.02 → 0.08 → 0.14 → 0.20 → 0.25 → 0.27 → 0.22 → 0.14 → 0.04
```

Chroma peaks at midtones (step 6 at ~0.27), drops to ~0.02-0.04 at extremes. Change only hue for variant palettes:
- Success: hue ~150°
- Warning: hue ~80°
- Error: hue ~20°
- Info: hue ~230°

For neutrals: identical lightness steps, chroma fixed at 0.01, hue = brand hue.

### Tinted Neutrals

```css
/* Warm neutral (slightly amber) */
--surface: oklch(0.97 0.01 60);

/* Cool neutral (slightly blue) */
--surface: oklch(0.97 0.01 250);

/* Brand-hinted neutral (teal product) */
--surface: oklch(0.97 0.01 200);
```

At chroma ~0.01 the tint is invisible per-pixel but creates subconscious cohesion. At 0.03+ the tint becomes perceptible. At 0.07+ it reads as an intentionally tinted surface.

### "Never Gray on Colored" Fix

Pick a text color with the same hue as the background, lower saturation/chroma, adjust lightness for contrast ratio:

```css
/* Dark blue hero */
--hero-bg: oklch(0.25 0.15 240);
/* Muted text on hero — NOT gray */
--hero-muted: oklch(0.72 0.04 240);  /* same hue, desaturated, lighter */
```

This rule extends to icons, borders, dividers, and placeholder text.

### Dark Mode Elevation System

Four-tier lightness system:

```css
:root {
  /* Light mode */
  --surface-0: oklch(0.99 0.005 240);  /* deepest/page bg */
  --surface-1: oklch(0.97 0.005 240);  /* cards, panels */
  --surface-2: oklch(0.95 0.005 240);  /* nested cards */
  --surface-3: oklch(0.92 0.005 240);  /* modals, tooltips */
}

@media (prefers-color-scheme: dark) {
  :root {
    --surface-0: oklch(0.12 0.01 240);  /* deepest */
    --surface-1: oklch(0.16 0.01 240);  /* cards */
    --surface-2: oklch(0.20 0.01 240);  /* nested */
    --surface-3: oklch(0.24 0.01 240);  /* modals */
  }
}
```

Each step is ~0.04L apart. Shadows are invisible in dark mode — elevation must come from lightness.

**Dark mode accent desaturation:** Reduce chroma by 10-15% and increase lightness by 5-8% vs. light mode. Fully saturated colors on dark backgrounds cause simultaneous contrast vibration.

### Color Harmony Reference

- **Monochromatic** — Single hue across levels. Maximum cohesion, minimum tension. Luxury brands, document UIs.
- **Analogous** (≤60° apart) — Natural, low-tension. Organic and editorial contexts.
- **Complementary** (~180° apart) — High contrast. Use sparingly: primary + one accent as complement.
- **Triadic** (~120° apart) — Vibrant. Risk of chaos without strict proportion discipline.
- **Split-complementary** — Base color + two hues flanking its complement. Professional compromise.

---

## Spacing

### 8pt Grid

Base scale: 4, 8, 12, 16, 20, 24, 32, 40, 48, 64, 80, 96, 128px

- 8pt for layout-level spacing (margins, section gaps, container padding)
- 4pt half-steps for internal component spacing (padding within buttons, icon-to-label gaps)
- Map to semantic names (xs, sm, md, lg, xl, 2xl) — code references `gap-md`, not `gap-[24px]`

### Internal ≤ External Rule

Space inside a component (padding) should equal or be less than the space outside it (margin). When internal > external, the component seems to float free from its group rather than belonging to it.

### Optical vs. Mathematical Alignment

Mathematical centering produces visually uncentered results because visual weight is not uniform:

- **Play icon (triangle) in circular button:** Shift 1-2px right of mathematical center. The triangle's visual mass anchors left.
- **Glyph in circular container:** Shift up by 2-3% of container height. The eye anchors to cap height, not descender.
- **Square vs. circle in same bounding box:** Circle has ~20% less visual weight than equal-size square. At equal math size, circle needs ~5-10% scale-up to read equal.
- **Text with descenders (g, p, y) in vertically centered container:** Add 2-3% extra top padding.
- **Large display headings:** Pull to -0.02em to -0.04em letter-spacing; default 0em at 64px+ looks loose.

---

## Motion

### Easing Function Cheatsheet

```css
/* Use ease-out for entrances — feels responsive and natural */
--ease-out-quart: cubic-bezier(0.25, 1, 0.5, 1);     /* default for product UI */
--ease-out-expo:  cubic-bezier(0.19, 1, 0.22, 1);    /* large spatial transitions */

/* Use ease-in-out for elements repositioning without entering/exiting */
--ease-in-out-quart: cubic-bezier(0.76, 0, 0.24, 1); /* accordions, morphs */

/* AVOID — avoid these for product UI */
/* ease-in — starts slow, ends fast, feels laggy */
/* cubic-bezier with overshoot (bounce) — dated, amateur feel */
/* cubic-bezier with elastic — same */
```

**Spring animations** (Framer Motion / React Spring) are superior to cubic-bezier for elements users directly manipulate (drag, swipe, pull-to-refresh) because springs naturally handle interruption via velocity carry-forward.

### Duration Tiers

| Use | Duration | Notes |
|-----|----------|-------|
| Micro-interactions (hover, focus ring, button press) | 100-150ms | <100ms is imperceptible |
| Component enter/exit (tooltip, dropdown, popover) | 150-250ms | Long enough to feel intentional |
| Page-level transitions (modal, sheet, overlay) | 250-350ms | Rushing large elements looks cheap |
| Large spatial transitions (full-screen menu, route change) | 300-500ms | Must be user-initiated |
| Decorative / ambient (hero loops, backgrounds) | 600ms-4s | Watched, not waited for |

Emil Kowalski's rule: no interactive animation should exceed 300-400ms. When in doubt, halve your current duration.

### Stagger Rules

- Maximum stagger interval: 20-30ms per item. At 50ms+ it feels like a slideshow.
- Stagger direction matches reading order (top-to-bottom, left-to-right).
- Only stagger semantically related elements (list items, grid cards).
- Never stagger more than ~8 elements (total cascade becomes too long).

### What to Animate

**GPU-accelerated (free):**
- `transform: translateX/Y/Z()`
- `transform: scale()`
- `transform: rotate()`
- `opacity`
- `filter: blur/brightness` (composited but expensive)

**CPU-expensive (avoid):**
- `width`, `height` — triggers layout + paint per frame
- `top`, `right`, `bottom`, `left` — triggers layout
- `padding`, `margin` — triggers layout
- `font-size` — triggers layout + paint
- `border-radius` on large elements — painting cost is extreme

### Never-Animate Rule

**Never animate keyboard-triggered actions.** Users press shortcuts hundreds of times. An animated "Cmd+K opens command palette" becomes an obstacle by the 10th use. Keyboard actions should be instant.

### Reduced Motion Baseline

```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

More nuanced approach: preserve functional transitions (focus ring appearance, state changes) but suppress decorative motion.

---

## Depth and Shadows

### Multi-Layer Shadow Doubling Formula

Tobias Ahlin's formula — 5 layers, Y and blur double each step, 12% opacity each:

```css
box-shadow:
  0 1px 1px rgba(0,0,0,0.12),
  0 2px 2px rgba(0,0,0,0.12),
  0 4px 4px rgba(0,0,0,0.12),
  0 8px 8px rgba(0,0,0,0.12),
  0 16px 16px rgba(0,0,0,0.12);
```

Opacity adjustment by layer count: 4 layers at 15%, 5 layers at 12%, 6 layers at 11%.

### Colored Shadows (Josh W. Comeau Pattern)

Pure black shadows produce a "grey wash" that disconnects from surface. Match the shadow hue to the background hue:

```css
:root {
  --shadow-color: 220deg 60% 50%;  /* dominant background hue */
}

.card-low {
  box-shadow: 0.5px 1px 1px hsl(var(--shadow-color) / 0.7);
}

.card-medium {
  box-shadow:
    1px 2px 2px hsl(var(--shadow-color) / 0.333),
    2px 4px 4px hsl(var(--shadow-color) / 0.333),
    3px 6px 6px hsl(var(--shadow-color) / 0.333);
}

.card-high {
  box-shadow:
    1px 2px 2px hsl(var(--shadow-color) / 0.2),
    2px 4px 4px hsl(var(--shadow-color) / 0.2),
    4px 8px 8px hsl(var(--shadow-color) / 0.2),
    8px 16px 16px hsl(var(--shadow-color) / 0.2),
    16px 32px 32px hsl(var(--shadow-color) / 0.2);
}
```

### Light Source Convention

- All shadows on a page cast in one direction
- Convention: light from slightly above and left
- Vertical offset ≈ 2× horizontal offset (1px h, 2px v)
- Mixed shadow directions destroy physical coherence

### Flat vs. Elevated Decision

**Flat (no shadows):**
- Minimal/modern brand voice
- Dark mode (use lightness elevation)
- High-density data UIs
- Mobile contexts (shadows are expensive)

**Elevated (shadows):**
- Light mode with overlapping surfaces
- Consumer products where tactile quality signal matters
- Floating UI (modals, dropdowns, tooltips)

**2025 modern alternative:** Depth via background color tiers + subtle border + slight `backdrop-filter: blur(8px) saturate(150%)` — renders better in dark mode than box-shadows.

---

## The 20 Load-Bearing Rules

The quality-lever rules. Each applied correctly moves output from "engineer-built" to "designer-quality":

1. Never use gray text on colored surfaces — match hue.
2. Negative letter-spacing (-0.02em to -0.04em) for display type above 40px.
3. OKLCH over HSL for all palette work.
4. Tinted neutrals at chroma 0.005-0.01.
5. Choose fonts with ≥5 weights.
6. Multi-layer shadows with the doubling formula (12% opacity × 5 layers).
7. Dark mode via lightness steps, not shadow intensity.
8. `ease-out-quart` `cubic-bezier(0.25, 1, 0.5, 1)` for enter animations.
9. Animate only transform and opacity.
10. Duration max 300ms for interactive animations.
11. 8pt grid for layout spacing, 4pt half-steps for internal component spacing.
12. Optical centering, not mathematical — icons, circles, text with descenders need 1-3px adjustments.
13. Letter-space ALL CAPS by +0.05-0.12em.
14. Line-height 1.4-1.6 body, 1.0-1.2 headings.
15. Internal ≤ external spacing rule.
16. `font-display: swap` + preload for critical fonts.
17. Add more whitespace than feels right — start generous.
18. Single light source for all shadows.
19. Stagger enter animations ≤20ms apart, max 8 items.
20. Desaturate accent colors 10-15% for dark mode.
