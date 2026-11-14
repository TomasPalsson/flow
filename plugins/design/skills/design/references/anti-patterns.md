---
name: anti-patterns
description: Complete catalog of AI-specific tells (first and second order, visual, copy and motion), classical UI, accessibility, and performance anti-patterns. Loaded in Phase 5 for the five-second tell sweep, and by the evaluator.
---

# Anti-Patterns — The Complete Catalog

Load this reference in Phase 5 for the tell sweep (every build), and when the evaluator has flagged issues that need specific anti-pattern identification.

---

## AI-Specific Anti-Patterns — The Dead Giveaways

These appear together as a syndrome, not individually as problems. The cluster is the AI slop fingerprint.

### AP-1: `bg-indigo-500` / `from-indigo-500 to-purple-600`
The canonical AI fingerprint. Adam Wathan publicly apologized in August 2025 for making Tailwind UI use `bg-indigo-500` as default — "this caused every AI-generated interface on Earth to turn purple."

**Why it's bad:** Instant "this was made by AI" recognition undermines any brand identity.

**Fix:** Use actual brand color. If the brand has none, pick ANYTHING except indigo/purple/violet. Named hex codes read as intentional: `#0070F3` (Vercel) > `bg-indigo-500`.

### AP-2: Inter as Default Typeface
Body, headings, and labels all in Inter with no explicit font choice. Inter is fine — as an explicit choice. As default, it signals "I did not make a typographic decision."

**Fix:** Explicit font choice with pairing. "Use DM Sans for body, Fraunces for display headings." Name both fonts explicitly.

### AP-3: Centered Hero + 3-Column Feature Grid
The most statistically common landing page in LLM training data (SaaS marketing 2018-2023). Signals no product thinking — the pattern is associated with generic marketing content.

**Fix:** Start from content, not layout template. What is the actual primary action? Let the answer dictate structure.

### AP-4: `rounded-2xl` Uniformly
Cards, buttons, inputs, modals, images, and containers all with the same heavy corner radius.

**Why it's bad:** Corner radius communicates hierarchy. When everything has the same radius, there's no differentiation.

**Fix:** Tiered scale — inputs 4px, buttons 6-8px, cards 10-12px. Reserve `rounded-full` for avatars and pills only.

### AP-5: `shadow-lg` as Universal Elevation
Every card, modal, dropdown gets the same `box-shadow`. Nothing occupies different depth.

**Fix:** Define elevation tiers. Many modern design systems (Stripe, Linear, Vercel) have abandoned drop shadows in favor of borders + background contrast.

### AP-6: Glassmorphism Everywhere
`backdrop-filter: blur(10px)` on navigation, cards, modals, and tooltips. Frosted glass stacked on frosted glass.

**Why it's bad:** Expensive to render (compositing per frame = jank on lower-end hardware). Creates unpredictable contrast as page scrolls. NN/g identifies "text readability problems" as the primary glassmorphism failure.

**Fix:** Reserve backdrop-blur for max 1-2 elements (navbar + possibly one modal). Test contrast with multiple backgrounds. Use `will-change: transform`.

### AP-7: Heroicons Unmodified at Same Size
Every feature card, sidebar item, and button uses the same Heroicon at 24x24 with default stroke weight.

**Fix:** Establish size/color rules. 20px for inline text icons, 24px for list items, 32-40px for feature highlights. Color contextually. For marketing-facing work, use Lucide, Phosphor, or custom SVGs.

### AP-8: Emoji as Functional Icons
Feature lists using 🚀 ⚡ 🔒 ✅.

**Why it's bad:** Renders inconsistently across OS. Screen readers announce them as names ("rocket emoji"). Scale poorly. Signals casual personal project.

**Fix:** SVG icons with explicit sizing and color.

### AP-9: AI Marketing Copy Vocabulary
"Revolutionize," "unlock," "seamless," "game changer," "the future of X," "transform your workflow," "say goodbye to," "empower your team," "cutting-edge," "next-level," "scale without limits," "build the future."

**Why it's bad:** Zero information content. "Revolutionize your workflow" teaches nothing about what the product does. These phrases are so associated with AI slop that they signal low effort.

**Fix:** Replace every instance with a concrete claim. Not "seamless integration" but "connects to Slack in under 2 minutes." Not "unlock your potential" but "cut review time from 3 hours to 20 minutes."

### AP-10: `max-w-7xl mx-auto` on Every Section
Perfectly uniform page width creates visual monotony — sections feel interchangeable.

**Fix:** Vary container widths by content type. Prose at `max-w-2xl` (60-70 characters per line), feature grids at `max-w-5xl`, marketing heroes full-bleed. The variation creates rhythm.

---

## Second-order tells (2025-2026)

Told to avoid indigo and Inter, generated pages converge on a second set of defaults. A design-literate visitor now spots these as fast as the first set. The test is the **five-second look**: what would someone who has seen a thousand generated pages call out before reading a word? Each item below is a tell when it is the template talking; it is fine when the content demands it (a pricing table with three tiers because there are three plans is content, not a tell). Sweep for them in Phase 5 and either remove each one or name the content that requires it.

**Surface and colour**
- T1. The "editorial" default: warm cream or beige ground, high-contrast serif display, terracotta or olive accent.
- T2. The "dev tool" default: near-black ground with one neon accent (acid green, electric lime, cyan), mono labels.
- T3. Gradient mesh, aurora or blurred colour blobs behind the hero; grain or noise overlay over everything; dotted or square grid pattern behind the hero.
- T4. Glass navigation bar plus glass cards.
- T5. One accent colour used for everything (links, icons, tags, borders, highlights) so nothing is more important than anything else.

**Type and labels**
- T6. An italic serif word dropped into a sans-serif headline for "personality".
- T7. Mono, uppercase, letter-spaced micro-labels above every section, often with brackets, slashes or numbers (`[ 01 ]`, `// FEATURES`, `01 — Process`).
- T8. A rounded pill "eyebrow" above the h1 ("New", "Now in beta", a sparkle).
- T9. Giant faded section numbers or a giant decorative year, or numbered steps where nothing cross-references the numbers.
- T9c. Costume data: texture or marks that imitate the trade's instruments (graph paper, sprocket holes, a staircase of markers, a seismograph line) without encoding any real value. Decoration dressed as data; if it looks like a chart, it must be one.
- T9a. The two-tone headline: the first sentence in ink, the second in a muted grey or the accent ("Back up Postgres to any second. Test the restore every night.").
- T9b. Display tracking pulled so tight that word spaces close up ("Back up" reads "Backup"); stop at about -0.03em and check the word gaps at the largest size.

**Chrome**
- T0. The template top bar: wordmark left, a cluster of text links right, a bordered or filled button at the far right, a hairline underneath, about 64px tall, carrying nothing of this client. And its partner, the template footer: brand and address left, link columns right. They read identical across any two themes.

**Components and layout**
- T10. Identical cards: icon in a tinted rounded square, bold title, two lines of grey text, 1px border, the same radius, three or six of them.
- T11. Bento grid of mismatched tiles that holds no more information than a list would.
- T12. The stat strip: three big numbers with tiny captions ("99.9% uptime", "10k+ users") — invented, or true but irrelevant.
- T13. Logo wall ("Trusted by teams at") with greyed logos, and a testimonial carousel with avatars.
- T13a. Generated flourishes: a rotated rubber stamp ("BOOKED", "APPROVED") on the confirmation, initials in tinted tiles standing in for real people, a lightning bolt for "fastest" or "first available", a sparkle for anything new.
- T14. Left-border accent callouts and check-mark feature lists as the main content device.
- T15. The default page sequence: hero, logos, three features, "How it works" 1-2-3, testimonials, three-tier pricing with a highlighted middle, FAQ accordion, "Ready to get started?" band, four-column footer.
- T16. Every section the same width, centred, with the same vertical padding: no rhythm.
- T16a. The same section-head layout on every section (h2 left, lede paragraph right, bottom-aligned; or eyebrow, h2, lede, centred): the template's rhythm showing through.
- T16b. The dev-tool hero object: a dark rounded "terminal" card with traffic-light dots or brew/curl tabs and a Copy button, floating with a heavy shadow on a light page. When the install command matters, set it in the page's own material instead.

**Copy**
- T17. Em-dash rhythm: more than about seven per 600 words, or one in most headlines.
- T18. "Not X. Just Y." / "No X. No Y. Just Z." and fragment triplets ("Fast. Private. Yours.").
- T19. "Everything you need to…", "Built for teams who…", "Designed for…", "…in seconds", "…that just works".
- T19a. Aphorism headlines: a quotable maxim where a claim should be ("A backup you have never restored is a guess", "Good coffee takes time"). One may be earned; a page of them is a model talking.
- T19b. Copy that describes the interface instead of the subject ("Four short steps. Your choices fill in the card as you go.", "Scroll to explore", "Here's how it works").
- T20. Section titles that are only labels in the default order ("Features", "How it works", "Pricing", "FAQ") and a "Get started" / "Learn more" button pair.
- T21. Invented specifics: numbers, customers, quotes or logos that are not in the brief.

**Motion** (detail and replacements in `references/microinteractions.md` §7)
- T22. Fade-up on scroll for every section; staggered card reveals.
- T23. Hover lift and shadow on cards that do nothing when clicked.
- T24. Animated gradients, floating blobs, glow pulse on the CTA, shimmer sweep, spinning gradient borders.
- T25. Typewriter or rotating-word headline; count-up numbers; marquee logo strip.
- T26. Custom cursor, cursor spotlight, magnetic buttons, 3D tilt cards, parallax layers.
- T27. One `transition: all .3s ease` on everything; controls that do not answer press at all.

**The inverse failure.** Removing every tell can leave a page with nothing in it. The goal is not absence but replacement by something that belongs to this client: their real numbers, their trade's artefacts, their place, their product's own interface, their words.

---

## Classical UI Anti-Patterns

### Dark Patterns (Prohibited)

**Confirmshaming** — Opt-out buttons phrased to shame. "No thanks, I prefer to pay full price." Creates negative brand association the moment recognition kicks in. Fix: neutral language.

**Forced Continuity** — Free trial ends and billing begins without warning. Cancellation is buried. EU/US prosecute this. Fix: send clear reminders; make cancellation as easy as sign-up.

**Hidden Costs** — Final checkout significantly higher than advertised. Baymard Institute: unexpected costs are the #1 reason for cart abandonment (48%). Fix: show total cost as early as possible.

**Roach Motel** — Easy to subscribe, nearly impossible to cancel. Creates hostile users who leave negative reviews. Fix: cancel in the same number of steps as sign-up.

**Privacy Zuckering** — Deliberately complex privacy settings exhausting users into maximum data collection. GDPR/CCPA prosecute this. Fix: plain-language consent; default to minimum; "reject all" as prominent as "accept all."

### Progressive Disclosure Failures

**Hiding critical info:** Pricing buried. Error states not explained. Required fields not shown until submission. Essential warnings in fine print.
Fix: Surface all decision-relevant information BEFORE the decision point.

**Dumping everything at once:** Settings panels with 40 options visible. Onboarding that explains every feature before users have used any.
Fix: Show defaults, hide advanced behind toggle. Reveal features as users demonstrate readiness.

### Form Validation Anti-Patterns

**Submit-only validation** — All errors appear only after submit. User filled out 12 fields, one was wrong, and now must find the error. Baymard: single validation errors significantly increase form abandonment.
Fix: Validate on blur (field loses focus). Success checkmarks on correct completion. Reserve submit-time validation for cross-field errors only.

**Error as red border only** — Invalid field gets a red border, no message. Fails colorblind users (8% of men). Doesn't explain what was wrong.
Fix: Colored border + inline error message below field. Include icon. "Enter a valid email address (e.g., name@example.com)" not "Invalid email."

**Placeholder as label** — No visible label; placeholder IS the label and disappears on type.
Fix: Visible label above input. If space is critical, floating labels — but know they have their own issues.

**Required field ambiguity** — Some required, some not, no indicator.
Fix: Mark required fields explicitly. Or: if most are required, mark only optional ones.

### Modal Abuse

Modals used for: long-form info, navigation, multi-step flows, content users will want to reference while doing other things, or page-load pop-ups.

**Why bad:** Modals are interruptions. They work for destructive confirmations because the interruption is justified. They fail for everything else — block context needed for the decision, impossible to link to, poor on mobile.

**Fix:** Modals are for destructive/irreversible confirmation ONLY. Drawers/sheets for settings. Inline expansion for detail. Separate pages for multi-step flows. No on-page-load modals until user demonstrates intent.

### Loading State Failures

**No feedback** — Button clicked, nothing happens for 3 seconds. Users click again (double submit). Perceived wait time is 2-3× longer without feedback.
Fix: Every action button enters loading state within 100ms of click. Disable during loading.

**Full-page spinner** — Entire content replaced with spinner.
Fix: Skeleton screens for content. Optimistic UI for user actions.

### Empty State Failures

Blank white area with no message, icon, or guidance.
**Why bad:** Communicates "the product is broken" before "no data yet." First-time users experience cognitive abandonment.
**Fix:** Empty states need (1) explanation ("No messages yet"), (2) next action ("Send your first message →"), (3) optionally sample data or preview.

---

## Accessibility Anti-Patterns

### A-1: `outline: none` Without Replacement
The "aesthetic" justification: focus rings look ugly. WCAG 2.4.7 requires focus visibility. WebAIM Million 2024 found this is one of the most common violations.

**Fix:**
```css
button:focus-visible {
  outline: 2px solid var(--focus-ring);
  outline-offset: 2px;
}
```
Use `:focus-visible` so mouse users don't see the ring (clicks already communicate intent) but keyboard users do. WCAG 2.2 requires 3:1 contrast on focus indicators.

### A-2: Color as Only Signifier
Errors only in red. Status only color-coded. Red-green colorblindness (deuteranopia) affects 8% of men. A red-border-only error is invisible to 1 in 12 male users.
**Fix:** Pair color with icon, text, or position. Charts need pattern fills or labels.

### A-3: Icon-Only Buttons Without `aria-label`
Toolbar of icon buttons, no visible labels. Screen readers announce nothing.
**Fix:** `<button aria-label="Delete item">`. Better: visible labels where space allows. Tooltips not sufficient (don't work on touch).

### A-4: Low-Contrast "Aesthetic" Text
Gray-on-white (`#999` on white). Designer thought it looked "sophisticated." WCAG AA requires 4.5:1 for body text, 3:1 for large. WebAIM Million 2024: low contrast is the #1 a11y violation, present on 83.6% of websites.
**Fix:** Body text minimum `#767676` on white (4.54:1). Preferably darker.

### A-5: Disabled State Indistinguishable from Enabled
Users click and nothing happens. Users with motor impairments disproportionately frustrated.
**Fix:** Visibly distinct (≥40% opacity reduction + tooltip explaining why). Or: leave enabled and surface contextual error.

### A-6: Auto-Playing Media
Hero video auto-playing, animated GIF demos, auto-advancing carousels. Violates WCAG 1.4.2 (audio control) and 2.2.2 (pause for motion >5s). Users with vestibular disorders experience nausea.
**Fix:** `autoplay muted loop` + pause control for background video. No auto-play for audio content. Carousels without auto-advance.

### A-7: Animations Ignoring `prefers-reduced-motion`
Vestibular disorders affect ~35% of adults over 40. WCAG 2.2.2 requires mechanisms to pause motion.
**Fix:**
```css
@media (prefers-reduced-motion: reduce) {
  *, *::before, *::after {
    animation-duration: 0.01ms !important;
    transition-duration: 0.01ms !important;
    scroll-behavior: auto !important;
  }
}
```

---

## Performance Anti-Patterns

### P-1: Cumulative Layout Shift (CLS)
Images, ads, embeds without explicit `width`/`height`. Content pushes down as images load, users click wrong things. 2025 Web Almanac: 62% of mobile pages have at least one image without dimensions.
**Fix:** Always set `width` and `height` attributes. Use `aspect-ratio` in CSS. Reserve space for dynamic content. `font-display: swap` + `size-adjust`.

### P-2: Animating Layout Properties
Animating `width`, `height`, `margin`, `top`, `left`, etc. triggers layout recalculation per frame — "layout thrashing." Causes dropped frames on low-end hardware.
**Fix:** Use `transform` and `opacity` exclusively. GPU-composited, never trigger layout. Replace `height: 0 → auto` with `transform: scaleY(0 → 1)` with `transform-origin: top`.

### P-3: FOIT (Flash of Invisible Text)
Custom fonts loading with default browser behavior. Blank text areas for 0-3 seconds.
**Fix:** `font-display: swap` on all `@font-face`. Preload critical fonts. Use `size-adjust` to calibrate fallback metrics.

### P-4: No Loading Priority Hints
Hero image loads after below-fold content. Above-fold skeleton. Poor LCP.
**Fix:** `fetchpriority="high"` on hero. `loading="lazy"` on below-fold. Preload critical CSS/fonts. Defer non-critical JS. `<link rel="preconnect">` for third-party domains.

### P-5: Wrong-theme flash
The light theme paints first, then flips to dark after hydration, because the theme is read from storage in `useEffect`. Dark-mode users see a white flash on every load.
**Fix:** Put a blocking inline `<script>` in `<head>` that sets the `html` class or `data-theme` from `localStorage`, falling back to `prefers-color-scheme`, before first paint. Add `suppressHydrationWarning` on `<html>` (the script changes the attribute the server rendered). Set `color-scheme` (CSS or `<meta name="color-scheme">`) so native controls and the canvas match.

Credit: adapted from vercel-labs/agent-skills skills/react-best-practices/rules/rendering-hydration-no-flicker.md @ 063bee9 (MIT).

---

## Top 15 "Instant Fail" Anti-Patterns

Ranked by combination of user damage and signal clarity. If any appear, professional quality assessment immediately degrades.

| # | Anti-Pattern | Instant Signal |
|---|---|---|
| 1 | `outline: none` without replacement | Keyboard accessibility destroyed |
| 2 | Purple gradient + Inter + 3-column grid | Unmistakable AI default |
| 3 | Color-only error indicators | 1 in 12 male users cannot see the error |
| 4 | Placeholder-as-label in forms | Memory failure + WCAG violation |
| 5 | No loading state on actions | Users double-submit, assume broken |
| 6 | Hidden costs at checkout | #1 cause of cart abandonment |
| 7 | Animating height/width | Visible jank on any device |
| 8 | Images without width/height | Layout shift moves click targets |
| 9 | Glassmorphism on multiple stacked layers | Text becomes unreadable |
| 10 | Auto-playing video with motion | Vestibular disorder trigger |
| 11 | Icon-only buttons without aria-label | Screen reader announces nothing |
| 12 | FOIT (no `font-display: swap`) | Blank text for 2-3 seconds |
| 13 | Empty state with no CTA | First-time users have no next action |
| 14 | AI marketing vocabulary | Readers classify as low-effort |
| 15 | Submit-only form validation | Single-field errors require full re-read |

---

## Pre-Ship Scan Checklists

### AI-Slop Scan
- [ ] No `bg-indigo-500` / `bg-purple-500` / `from-indigo-500 to-purple-600` without brand justification
- [ ] Font is not Inter / Space Grotesk / Roboto / Arial by default
- [ ] Layout designed from content, not from hero+grid template
- [ ] Corner radius varies by component type
- [ ] Shadows tiered (multi-layer with doubling formula), not uniform `shadow-lg`
- [ ] No glassmorphism on more than one UI layer
- [ ] Icons have accessible names
- [ ] No emoji as functional icons
- [ ] Headlines contain ZERO AI vocabulary (revolutionary, seamless, unlock, game-changing, etc.)
- [ ] Copy has specific numbers / concrete claims
- [ ] Five-second look: every second-order tell (T0-T27) removed or justified by content in one line
- [ ] `scripts/probe.mjs` has no FAIL row

### Accessibility Scan
- [ ] Focus-visible states on all interactive elements (3:1+ contrast)
- [ ] All errors have text, not just color
- [ ] All forms have visible labels (not placeholder-only)
- [ ] `prefers-reduced-motion` respected
- [ ] All icon-only buttons have `aria-label`
- [ ] No auto-playing media without controls
- [ ] Minimum body text contrast 4.5:1
- [ ] Minimum large text contrast 3:1
- [ ] Touch targets ≥ 44×44px
- [ ] Keyboard navigation works throughout
- [ ] Heading hierarchy logical (no skipped levels)

### Performance Scan
- [ ] All images have explicit `width`/`height`
- [ ] Hero image has `fetchpriority="high"`
- [ ] All below-fold images have `loading="lazy"`
- [ ] Fonts use `font-display: swap`
- [ ] All transitions use `transform`/`opacity`, not layout properties
- [ ] No `backdrop-filter: blur()` on multiple stacked layers
- [ ] Critical fonts preloaded
- [ ] Third-party domains preconnected
