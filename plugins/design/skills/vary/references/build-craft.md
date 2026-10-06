---
name: build-craft
description: Loaded AFTER the contract is written and BEFORE any UI code. How to compose the palette around the assigned seed, load and set the assigned type, execute the skeleton, author the one motion moment, cover states and browser surfaces, and pass the craft floor. Not for planning; not for the evaluator.
---

# Build craft

When a user directive collides with any rule here, the directive wins except on accessibility.

The contract decided *what*. This file is *how*, at the level a design director checks. Commit to the world first; every rule below is a floor, not a brake. When a rule and the world's grammar collide, the grammar wins on aesthetics and the floor wins on accessibility, states and keyboard.

## 1. Palette from the seed

The seed is one OKLCH anchor with a role hint. Compose five roles around it: **ground, surface, ink, primary, accent** (plus muted and border derived from ink/ground). The STRATEGY line says how much area colour may own:

| Strategy | What it means on the page | Numbers to hold |
|---|---|---|
| restrained | neutrals; the accent touches ≤10% of area (links, one CTA, small icons) | ground L 0.97-1.0 or 0.06-0.12; accent C 0.12-0.20 |
| committed | one saturated colour carries 30-60% of visual weight as fields (nav, hero, whole sections) | primary C 0.14-0.23; if L>0.78 cap C 0.18; text on it per `text on it` |
| full-palette | 3-4 named roles, each owning regions; hues ≥40° apart or ≥0.25 L apart; one leads by area | supporting roles pull to C 0.05-0.10 |
| drenched | the surface IS the colour (campaign/experience only) | bg C 0.06-0.15 at L 0.35-0.55 or 0.85-0.95; ink at the far end |
| duotone | exactly two hues: one structure, one signal; semantic colours decided up front | Δhue ≥60° or a hard L split |
| two-field-split | two ground colours dividing the page; each field gets its own ink/muted/border; the seam is a designed edge | fields differ ≥0.35 L |
| ink-on-paper | true ink on paper (or one tinted stock) + exactly one confident accent | paper L 0.96-1.0 C ≤0.02; ink L 0.08-0.15; accent C 0.15-0.24 |
| dark-with-warm-light | dark neutral base; warm light sources are the only saturated colour | bg L 0.06-0.14; light L 0.65-0.80 C 0.12-0.20 H 30-70 |
| high-key-pastel | almost everything light and soft; ink must still be dark | surfaces L 0.88-0.97 C 0.02-0.08; ink L 0.20-0.30 |
| acid-hi-vis | very high chroma on true black or white; never as body text | accent C ≥0.22 (or the hue's ceiling); no mid-greys anywhere near it |
| muted-earth | low chroma organic hues; vary WHICH earth leads (ochre, clay, moss, slate), never always terracotta | C 0.02-0.09 |
| primary-triad | red/yellow/blue confidence; one dominates by area (60%+) | yellow cannot be dark and saturated; do not force equal L |
| jewel-tones | deep saturated hues on dark or rich ground | L 0.30-0.45, C 0.14-0.20; check each hue's ceiling (greens clip early) |
| monochrome-tonal | one hue as a 5-9 step ramp; semantics by icon/shape or one deliberate break | ramp steps ~0.08-0.12 L; C peaks mid-ramp, tapers at both ends |

Rules that hold under every strategy:

- **Tint the neutrals** toward the seed hue (C 0.005-0.02). Pure grey reads as un-designed (unless a directive or the brand specifies pure black/white). Over ~C 0.03 it stops being neutral.
- **Text on colour is never grey.** Derive it from the field's hue at the far end of L. On saturated mid-luminance fills (L 0.42-0.78, C ≥0.08) use white, even where the maths permits dark: saturated colours look brighter than they measure (Helmholtz-Kohlrausch).
- **Gamut is a default engine.** Blue/purple tolerate the widest chroma across L; yellow cannot be dark and saturated; cyan caps near C 0.145. Check every hue's ceiling at its L before committing a number, or the palette drifts toward purple on its own.
- **Dark mode is its own system.** Base L 0.08-0.12 with a faint tint, never `#000` (unless a directive or the brand specifies pure black/white). Elevation by +3-6% L per tier (5 tiers to about L 0.28), not shadows. Desaturate accents by hue: warm −10-15%, cool −20-30%; yellow shifts toward amber instead of desaturating.
- **Contrast**: WCAG 2 as the legal floor (4.5:1 body, 3:1 large and UI); on coloured fields and dark mode aim for APCA Lc ≥75 body, ≥60 UI, ≥45 large headlines. `check.mjs` computes the literal pairs; variable cascades need a screenshot.
- Every colour is a token; no raw hex in components.

## 2. Type

Load exactly what the contract names.

```html
<!-- Google -->    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
                   <link href="https://fonts.googleapis.com/css2?family=…&display=swap" rel="stylesheet">
<!-- Fontshare --> <link href="https://api.fontshare.com/v2/css?f[]=<slug>@<weights>&display=swap" rel="stylesheet">
<!-- Self-host --> @font-face { font-family: 'X'; src: url(x.woff2) format('woff2'); font-weight: 100 900; font-display: swap; }
                   @font-face { font-family: 'X Fallback'; src: local('Arial'); size-adjust: 104%; ascent-override: 92%; }
```

- Preload the one or two weights above the fold; `font-display: swap` plus a `size-adjust`ed fallback so the swap does not shift layout.
- Use the weights the face ships; never faux-bold or synthesised italics. If the world says one family, hierarchy comes from weight, size, case and position.
- `font-optical-sizing: auto` on any face with an `opsz` axis; set a variable face's axes on purpose (a variable font at its default instance is a static font with a listicle smell).
- Sizes: fluid display with `clamp()`; body fixed and tested (16-18px web). Line-height 1.0-1.2 display, 1.4-1.6 body. Tracking −0.02 to −0.04em above ~40px; +0.05 to +0.12em for small caps or all-caps labels.
- Measure 45-75ch (`max-width` in `ch`); 35-45ch in dense columns. `text-wrap: balance` on headlines, `text-wrap: pretty` on paragraphs. `font-variant-numeric: tabular-nums` in any column of figures. `hanging-punctuation: first` where supported.
- Mono is for code, data and measurement, not for "technical" flavour.
- System stack is a legitimate choice for operate surfaces (and the only one with `--no-webfonts`); it is still subject to every rule above.

## 3. Skeleton and space

- Build the ARCHETYPE's structure literally (its `grid`, first viewport, primary-action placement, scroll behaviour, and its mobile fallback as printed). Do not let the category's hero → three cards → CTA sequence reappear under the skin.
- 8pt spacing scale; 4pt half-steps only inside components. Internal padding ≤ the space between components, or grouping breaks.
- Radius and shadow are tiered or absent, never one value everywhere. Shadows, when the world allows them, are multi-layer, tinted toward the ground hue, from one light direction. Dark mode has no shadows.
- Hierarchy through weight, size and position before colour. A label above a heading must carry information the heading cannot (a route, a category colour), or it goes.
- Numbering exists only when something cross-references it.

## 4. Motion

- Exactly the MOTION MOMENT from the contract, in its easing envelope. Nothing else animates on entrance; no per-section fade-up; no stagger on lists longer than 8.
- Interactive feedback: 100-150ms hover/focus, 150-250ms components, 250-350ms modals. Ease-out from an already-visible default; the world's `forbidden` list stands.
- Animate transform and opacity; blur, clip-path, mask and shadow are allowed when they stay smooth. Never width, height, top, left, margin, padding, font-size.
- Never animate keyboard-triggered actions a user repeats all day.
- `@media (prefers-reduced-motion: reduce)` removes decorative motion and keeps functional state changes; scroll-driven content must exist statically and in order.

## 5. States, copy, and the parts nobody draws

- Nine states for every interactive element and every view (hover is N/A on touch-only platforms): default, hover, focus-visible, active, disabled, loading, error, success, empty. A state you cannot describe does not exist. Empty and error states are designed screens, not a sentence in grey.
- `:focus-visible` ring at ≥3:1 against its surroundings, distinct from hover; tab order equals reading order; focus trapped in modals and returned on close.
- Touch targets ≥44px; colour is never the only signifier.
- **Browser surfaces (web only)**: `::selection`, `caret-color`, scrollbar colours, underline offset/thickness, form control accent, the focus ring. These ship with browser defaults that belong to no design; theming them is the cheapest signal that the page was built rather than assembled.
- Copy: buttons name their outcome ("Send invoice", not "Submit"); errors say what happened and what to do. Run the competitor-swap test on the headline: if it still reads true with a rival's name, it made no claim. No "seamless", "unlock", "revolutionise", "the future of", "trusted by 10,000+". Em dashes: fewer than 7 per 600 words.
- Every `<img>` has `width` and `height` (or `aspect-ratio`); `loading="lazy"` below the fold; photos in a scene or pattern treatment transformed into the world's material (multiplied onto paper, greyscaled, edge-traced, one-ink halftone); under photography or product-ui, and for identity assets (headshots, partner logos, product screens), the image ships faithfully with art direction by crop, sequence, size and grade only (`../../graphics/references/graphics.md` §2o); drawings come from the graphics skill (`design:graphics`, Step 3a) where no photo exists; no emoji as icons; one icon system, one stroke weight.

## 6. Craft floor — verify on the built result

Run these together in one inspection round on the real render (desktop and mobile), then `check.mjs`:

1. Contrast numbers pass on every literal pair; coloured fields carry hue-derived text.
2. Type: measure inside 45-75ch, display tracking negative, no synthesised weights, real copy at every breakpoint without overflow.
3. Spacing: tight inside groups, generous between; more space above a heading than below it.
4. Depth: tiered or absent; single light source; no zero-offset coloured halos.
5. Motion: one authored moment, ease-out, reduced-motion honoured.
6. States: all nine present and reachable; keyboard walk completes; focus visible everywhere.
7. Browser surfaces themed.
8. Copy: outcome-named controls, product-specific claims, zero AI vocabulary.
9. Every brief requirement present and findable within seconds.
10. The signature idea (type, layout, colour, photography, product UI, data, motion or graphics) is visible in the first viewport and again at one other scale.
11. Graphics, when the graphics check called for them: integrated as returned from `design:graphics` with the alt text from `GRAPHICS.md`, each doing the job its brief row named; decorative ones are `aria-hidden`.
12. Type over images or drawings: no frosted, translucent or blurred card, chip row or SaaS button pair over hero imagery; text sits on a surface that gives 4.5:1.
13. Collisions and dead zones at 1440x900 and 390x844: every text is fully visible with no overlap with another text or an object; no empty region that does nothing.
14. No duplicated content: each fact (price list, hours, address, offer) appears once in the page body; the footer may repeat contact details only. Exempt: amounts inside a `<form>`, anything marked `data-repeat-ok`, and `pre`/`code` blocks. Section skeletons differ from one section to the next (for example a full-width image, a catalogue, a process strip, a map or plan, a quote, a ticket or label as an object).
15. Headline on the fold: the first viewport carries a real `<h1>` (the business name or the promise), a one-line value proposition and the primary action (persuade/experience; on operate and read the page title and the primary object), never svg-only text, never omitted.
16. Time: the page ships. Inspect once, fix in one batch; do not reopen the art loop during the build.
16b. The element the brief cannot do without (every treatment): name it in NOTES.md before building (the trend a supervisor asked for, the safety line on every onboarding screen, the photos that must carry the page, the install command) and build it first, at full strength. A required element that is missing, faked or reduced to a note fails the build.
16c. Loudest equals most important (every treatment): the element with the most visual weight (size, colour, position) is the one the user most needs: the problem right now on a dashboard (never a routine next departure), the product itself on a SaaS hero (never a stat card), the install command on a docs home, the safety line in a health app. Alert colour and the biggest type go there and nowhere else.
16d. Body copy is set in a text face (every treatment): the display face is for display sizes only; paragraphs, table cells, captions and form labels use a face built for reading at 16-18px (never an extended, wide-tracked, condensed or monospace display face for prose; mono only for code and figures). Captions stay at 13px or more at 4.5:1. Nav text over a photo or gradient sits on a scrim or a solid bar that gives 4.5:1.
17. Phone width (every treatment): at 390px nothing scrolls the page sideways and nothing is clipped. Wide grids and tables scroll inside their own container or reflow into a list; the header at 390px is one row of at most 64px (brand plus a menu button or at most three short links), so the nav never eats the fold; text keeps a 16px side gutter; device frames shown side by side stack.
18. The client's page only (every treatment): no designer notes in the build. No reference codes, "signature device" or "motion" labels, design-review annotations, keys explaining how to read the page, or internal tags. A chart's text equivalent is a real table or visually hidden, captioned in the client's words.
19. (photography) The photos carry the page: the hero photo is full-bleed or fills at least 60% of the first viewport; no frames, hatching, stitched borders or ornament around photos; products appear as photo slots, never as drawn stand-ins. When photos are described but not supplied, render each slot at its final size and crop as a quiet neutral frame (one flat tone from the palette's ground, no gradient, no fake shadow, no drawn object) with the file name and the client's description set inside it as a visible caption ("hero.jpg · the Oriel tote on a stone bench, morning light"), so the client sees exactly which photo goes where and the layout is right the moment the file lands.
20. (product-ui, data-visual, utility) Native conventions and honest data: app screens use the platform's own controls (iOS: a full-width primary button above the home indicator, a standard nav bar); a dashboard plots only data the dossier has, except when the brief itself is a mock with sample data and asks for a view the data does not cover (a 4-hour trend): then build that view with sample values consistent with every given number, labelled "sample data" in the chart caption, never skipped and never replaced by a "will plot here" note; status colour stays calm (one alert colour, on the problem only, not full-width slabs); the first screen answers the user's first question without scrolling. Charts show the answer, not just the data: if the user asks "how did this year compare", plot the difference or percentage change, not only two near-parallel lines; mark the periods the story is about (a season, an outage). On a data surface the signature idea comes from the data's own story (what is surprising or specific in these numbers), never a costume borrowed from an unrelated artefact. Signed values diverge from a zero line (a negative change points the other way); one chart uses one unit (never pin a daily record on a monthly-total chart).
21. The first screen answers the visitor's top question (every treatment): for a shop or venue, open-now status, today's hours and the address (or the one fact the dossier says visitors come for); for a product, what it is and the primary action. A showpiece (a big drawing, a tag, a hero image) shares the first screen with those facts and never pushes them below the fold at 1440x900 or 390x844.
22. Products are shown (every treatment): a business that sells physical things shows them, as the client's photos or, with no photos, a drawing of each item from the graphics skill. A product list of names alone fails on a persuade page.
23. Brand objects carry real content (every treatment): a drawn tag, coupon, ticket or label only shows information the dossier has. A field the facts cannot fill is left off the object, never shown empty: an empty form on a product reads as a bug. A value the facts do not give (a care setting, a spec, a time) is either left off or labelled on the page as an example ("example, confirm in store"), never shown as fact; it may not drive a filter or calculation unless labelled. When a stated fact and the data disagree (a stated 34% where the monthly figures give 36%), show the data and say on the page that it differs from the stated figure; never override a fact silently.
24. Phone navigation (every treatment): more than three nav links at 390px go behind a labelled menu button; a nav row that scrolls sideways or cuts off a label fails.
25. The idea where it does a job (every treatment): the concept's idea leads the first screen and returns only in the sections where it helps the user (the care tag on each product, the theme in the speaker specimens, the data story in the main chart). Each piece of content appears once, in the section whose job it is; never repeat a list to carry the idea, and never stamp the motif on elements that do not need it (buttons, generic bars, every card). Keep the most subject-specific element rather than trading it for a broader metaphor any brand could use.
26. Time-aware content (every treatment): compare every date in the facts with today. A past event gets a post-event state (no booking, 'next edition' instead), stale counts ('212 sold as of 1 December') are dated or dropped, and opening status uses the real clock.
27. Place questions get a place (every treatment): when users ask where (my street, the venue, the shop, the counters), show the places as a map, plan or route from the graphics skill, linked to the details; a list of names alone is not an answer.
28. Show the subject (every treatment): a business with a visible subject (plants, food, a place, a product, the letters a type event is about) shows it at hero scale on the first screen, as the client's photos or art from the graphics skill, unless a directive asks for type only. Product drawings sit at real size (at least 200px wide on desktop, filled shapes with weight), never as icon-sized sketches.

## 7. Refuse — the category defaults this world did not choose

These are defaults, not bans: the contract's grammar can earn any of them back explicitly. Reaching for one when the axis was free means no decision was made; rewrite the element rather than soften it.

- Same-size icon-plus-heading-plus-text cards as page structure; nested cards.
- The hero-metric template (big number, small label, sparkline) (persuade/experience; an operate surface may use a KPI summary).
- Eyebrow/kicker labels that repeat what the heading says.
- Gradient text; glass as decoration; a coloured left border thicker than 1px as a callout; hard offset block shadows outside a world that is actually neobrutalist.
- Mono as costume; a system display face as the display voice of an own-world page; emoji or Unicode glyphs as icons.
- Light or dark chosen by category instead of by the scene sentence.
- Abstract decoration with no job (gradient blob, mesh, noise-only hero). If a page needs imagery and has no photos, ask the graphics skill for art that does a job; a clean page with no imagery at all is also a valid choice. An operate surface uses one consistent icon library unless a custom set adds clarity.
- The waterfall: hero → logo strip → three features → testimonial → pricing → FAQ → CTA.
