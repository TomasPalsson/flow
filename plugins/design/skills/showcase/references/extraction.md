# Design Extraction Reference

Use these stack-specific paths to locate design tokens, then run frequency analysis to confirm what's actually used vs. merely declared. Start with Layer 1 (config files) and work down only as needed.

---

## Stack-Specific Extraction Paths

### React / Next.js (App Router)

| Priority | File | What to look for |
|----------|------|-----------------|
| 1 | `app/globals.css` | `:root {}` CSS variables, `@theme` block (Tailwind 4), `@font-face` |
| 2 | `tailwind.config.ts` / `.js` | `theme.extend.colors`, `.borderRadius`, `.spacing`, `.fontFamily` |
| 3 | `components.json` (shadcn) | `baseColor`, `tailwind.cssVariables`, `style` |
| 4 | `components/ui/button.tsx` | Primary color usage, hover treatment, border-radius, padding |
| 5 | `next.config.js` or layout.tsx | `next/font` imports — definitive font choices |
| 6 | `lib/utils.ts` | `cn()` utility confirms Tailwind + CVA project |

### React / Vite + Tailwind

| Priority | File | What to look for |
|----------|------|-----------------|
| 1 | `src/index.css` or `src/main.css` | CSS variables, font imports |
| 2 | `tailwind.config.js` | Same as Next.js |
| 3 | `src/styles/theme.ts` | Theme object if using CSS-in-JS alongside Tailwind |
| 4 | `src/App.tsx` | ThemeProvider wrapper — the object it receives IS the design system |

### styled-components / Emotion (CSS-in-JS)

| Priority | File | What to look for |
|----------|------|-----------------|
| 1 | `src/theme.ts` or `src/styles/theme.ts` | `DefaultTheme` object — colors, spacing, typography, radii, shadows |
| 2 | `src/App.tsx` root | `ThemeProvider` — the passed theme object |
| 3 | `src/styles/GlobalStyles.ts` | `createGlobalStyle` — global CSS injections |
| 4 | `styled.d.ts` | TypeScript interface shows the SHAPE of the design system |

### Vue 3 + Vite

| Priority | File | What to look for |
|----------|------|-----------------|
| 1 | `src/assets/main.css` | Global styles, CSS custom properties |
| 2 | `vuetify.ts` plugin config | `theme.themes.light.colors` (Vuetify projects) |
| 3 | `app.config.ts` | `ui.primary`, `ui.gray` (Nuxt UI projects) |
| 4 | `.vue` SFC scoped styles | `:deep()` usage signals fighting the design system |

### Plain HTML/CSS

| Priority | File | What to look for |
|----------|------|-----------------|
| 1 | `styles.css` / `main.css` / `style.css` | `:root {}` custom properties |
| 2 | First `@import` in main CSS | Design system files imported first (variables, typography) |
| 3 | Naming patterns | BEM (`.card__header`), SMACSS (`.l-sidebar`), OOCSS |

### Tailwind 3 vs Tailwind 4 Detection

- **Tailwind 3**: `tailwind.config.js` exists with `theme.extend`. Tokens in JS.
- **Tailwind 4**: No config file. `@import "tailwindcss"` in CSS with `@theme {}` block. Tokens in CSS.
- Signal: if `tailwind.config.js` is absent but there's `@import "tailwindcss"`, it's v4.

---

## Frequency Analysis Commands

Run these to find the project's actual design patterns (not just what's declared):

```bash
# Most used border-radius values
grep -roh 'rounded-[a-z0-9]*' src/ | sort | uniq -c | sort -rn | head -10

# Most used shadow values
grep -roh 'shadow-[a-z0-9]*' src/ | sort | uniq -c | sort -rn | head -10

# Most used gap/spacing values
grep -roh 'gap-[0-9]*' src/ | sort | uniq -c | sort -rn | head -10

# Most used padding values
grep -roh 'p[xy]-[0-9]*' src/ | sort | uniq -c | sort -rn | head -10

# Most used text sizes
grep -roh 'text-[a-z0-9]*' src/ | sort | uniq -c | sort -rn | head -10

# Most used background colors
grep -roh 'bg-[a-z0-9-]*' src/ | sort | uniq -c | sort -rn | head -10

# Arbitrary values (escaped the token system — often the most important)
grep -roh '\[[^]]*\]' src/ --include='*.tsx' --include='*.jsx' | sort | uniq -c | sort -rn | head -20
```

For non-Tailwind projects:
```bash
# Extract all CSS custom property definitions
grep -roh '--[a-z-]*:[^;]*' src/ styles/ | sort | uniq -c | sort -rn

# Find font-family declarations
grep -rh 'font-family' src/ styles/ | sort | uniq -c | sort -rn

# Find max-width constraints (critical hidden token)
grep -roh 'max-w-[a-z0-9]*\|max-width:[^;]*' src/ | sort | uniq -c | sort -rn
```

---

## Typography Ratio Reference

Compute from h1-h4 font sizes to identify design philosophy:

| Ratio | Name | Feel | Common in |
|-------|------|------|-----------|
| 1.200 | Minor Third | Dense, compact | Enterprise dashboards, data apps |
| 1.250 | Major Third | Balanced | SaaS products, admin panels |
| 1.333 | Perfect Fourth | Clear hierarchy | Content sites, documentation |
| 1.500 | Perfect Fifth | Bold hierarchy | Marketing pages, landing pages |
| 1.618 | Golden Ratio | Dramatic | Hero-heavy, editorial sites |

## Border-Radius Personality Map

| Value | CSS | Feel |
|-------|-----|------|
| 0-2px | `rounded-none` / `rounded-sm` | Sharp, technical, government/financial |
| 4px | `rounded` | Conservative modern, default SaaS |
| 6-8px | `rounded-md` / `rounded-lg` | Friendly, polished, most SaaS 2023-2025 |
| 12-16px | `rounded-xl` / `rounded-2xl` | Consumer, mobile-influenced, warm |
| 24px+ | `rounded-3xl` | Playful, youth-focused, deliberate statement |

**Key**: Consistency across a project matters as much as the value. If cards use `rounded-lg` but buttons use `rounded-md`, that's a deliberate radius scale — replicate it, don't "fix" it.

## Shadow Depth Philosophy

| Pattern | Meaning |
|---------|---------|
| No shadows, borders only | Flat design; clean, structured |
| `shadow-sm` only | Subtle elevation; modern (Notion, Linear) |
| `shadow-md` cards, `shadow-lg` modals | Traditional depth hierarchy |
| Colored shadows | High-design, marketing/landing pages |

## Font Personality Quick Reference

| Font(s) | Signals |
|---------|---------|
| Inter, Geist | Neutral, developer-facing SaaS |
| DM Sans, Plus Jakarta Sans, Outfit | Friendly, product-focused, consumer |
| Bricolage Grotesque, Cabinet Grotesk | Opinionated, design-conscious startup |
| Georgia, Lora, Merriweather | Content-first, long-form reading |
| System font stack | Performance-conscious, utilitarian |
