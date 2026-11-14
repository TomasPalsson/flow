# What people read as "AI-made" in websites (2026-11-14)

Two research passes (Sonnet subagents, web search and fetch) checked the design skill's tell catalogue (`plugins/design/skills/design/references/anti-patterns.md`) against what practitioners and published sources say. Counts are the number of sources read that name the tell, not a population measure; several practitioner sources are agency or vendor blogs that cite each other.

## Strongest evidence

- **Generated UI reads as conventional, not unusable.** 92 participants rating AI prototypes (authorship not disclosed, UEQ-S): usability positive, hedonic neutral to negative; "Conventional/Inventive" -0.4 to -1.0 on 9 of 10 prototypes. Static prototypes, student raters. https://arxiv.org/pdf/2605.15124
- **Generated UIs converge across tools.** 120 interfaces, 5 tools, 24 tasks, a Design Homogeneity Index (visual similarity, colour distance, layout tree-edit distance): layout and look converge, colour varies most. About 25% of stated design rationales are not implemented ("design theater"). Preprint. https://arxiv.org/pdf/2607.22928
- **Without visual specs, every tool gives one generic look** (NN/g on Bolt, Claude, Figma Make, v0, Lovable, Replit, UX Pilot, Stitch): clean sans, bright accent, soft grey ground, coloured status tags, simple cards; "flat and interchangeable". https://www.nngroup.com/articles/ai-prototyping/
- **Vendor guidance names the tells concretely.** OpenAI: cards by default and nested cards, pill soup, stat strips, floating badges, hero crowded with stats or schedules, a first viewport that "could belong to another brand once the nav is removed", gradient or orb backgrounds, fake 3D, split heroes, design commentary left in the UI, purple / cream / slate / espresso palettes, dashboards where none is needed, ornamental motion. https://developers.openai.com/blog/designing-delightful-frontends-with-gpt-5-4 · Anthropic: distributional convergence; Inter, Roboto, Arial, Open Sans, Lato, Space Grotesk, purple on white. https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics
- **Measured at scale on Show HN** (1,590 pages, deterministic CSS/DOM checks): purple CTAs ~10.7%, three identical icon cards, badge above a centred h1, Inter, emoji icons, coloured left borders, stat rows, 1-2-3 steps; tells are only reliable in clusters (5-10% false positives). https://adriankrebs.ch/blog/design-slop/
- **No study measures a trust or conversion effect of looking AI-made.** The defensible claim is "perceived as less original"; the catalogue's earlier "readers classify as low-effort" had no measured backing.

## Most-named tells (practitioner sources)

Purple/indigo gradient (9+), three identical icon cards (8), buzzword hero copy (8), Inter (7), emoji icons (6), gradients and coloured glows everywhere (5), badge above a centred hero (4), soft shadow + heavy radius + glass on every card (4), coloured left/top borders (3), all-caps micro-labels (3), the cream-serif-terracotta and near-black-neon replacements (3), scroll fade-ins and scroll-jacking (3), shadcn defaults left untouched (3), pulsing "Live" badges and status dots (2-3), cards nested in cards (2), hover that does nothing (2), invented numbers (2). Sources: Krebs (above); https://codemyspec.com/blog/vibe-coded-websites-look-the-same; https://www.thefountaininstitute.com/blog/signs-vibe-coded-ui; https://www.utsubo.com/blog/built-with-ai-trust-signals-2026; https://robotsonpayroll.substack.com/p/how-to-avoid-that-vibe-coded-look; https://www.925studios.co/blog/ai-slop-design-tells; https://superdesign.dev/blog/fix-generic-ai-landing-page; https://noqta.tn/en/blog/ai-design-slop-overused-ui-patterns-fix-2026; YC design review https://rosetta.to/u/ycombinator/design-experts-review-vibe-coded-websites

## Nuance

- A single tell is not a verdict; clusters are (Krebs, Utsubo, 925). Inter or indigo are tells when nobody chose them.
- Some sameness is defensible: B2B buyers and procurement want familiar; internal tools need no creative statement (HN discussion https://hn.svelte.dev/item/46179202).
- Regenerating gives a different average page; fix section by section (Noqta, 925).

## What reads as human-made

Real proof (product screenshots, named people, real photos, dates); claims only this product could make, with real numbers; one deliberate asymmetry; a palette tied to the business and written down; motion tied to feedback; manual QA of every interaction on a phone.

## Folded into the skill

Catalogue additions T0a (extended to any decorative status dot), T3b coloured glows, T8a pill soup and floating badges, T10b cards nested in cards, T12a operational data crowding the first screen, T13b synthetic imagery, T15a dashboard chrome on non-dashboards and landing chrome on app screens, T16c sections that look like different tools, T19c hedging and stock openers, T19d copy that echoes the brief or describes the build, T23b essential actions hidden behind hover; the brand-swap test (hide the nav: could the first screen belong to another brand?); "design theater" (every spec decision must be visible in the CSS); the evidence note on AP-9. `probe.mjs` adds coloured-glow, nested-card and typeface-count warnings.
