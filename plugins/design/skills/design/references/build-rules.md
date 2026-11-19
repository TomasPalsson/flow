---
name: design-build-rules
description: The craft numbers, polish questions and anti-convergence procedure behind design SKILL.md Phases 4, 5 and the Closing Directive. Loaded by the builder at Phase 4 (§1), on the first polish pass (§2) and right before generating (§3).
---

# Build rules

## §1 Craft numbers (Phase 4)

**Typography execution rules:**

- Line-height: **1.4-1.6 for body**, **1.0-1.2 for headings**, 1.0-1.25 for UI labels. Engineers default to 1.5 everywhere — that makes headings look like paragraphs.
- Letter-spacing: **-0.02em to -0.04em for display type above 40px** (default tracking at large sizes looks amateur). **+0.05em to +0.12em for ALL CAPS** (uppercase was designed for mixed case and needs tracking to breathe).
- Choose typefaces with **≥5 weights** — fewer weights signals low foundry investment.
- `font-display: swap` + preload 1-2 critical weights + WOFF2 only + variable fonts when available.

**Color execution rules:**

- **OKLCH, not HSL.** HSL lightness is not perceptually uniform — a blue-500 and yellow-500 look dramatically different at the same HSL values. OKLCH fixes this.
- **Tinted neutrals at chroma 0.005-0.01** toward the brand hue. The tint is invisible per-pixel but creates subconscious cohesion.
- **NEVER gray text on colored backgrounds.** Use a hue-matched desaturated shade of the background. Example: on a dark blue hero, muted text is `hsl(220, 40%, 65%)`, not gray.
- **Dark mode via lightness elevation, not shadows.** Four-tier lightness system: `oklch(0.12/0.16/0.20/0.24 0.01 H)`. Desaturate accents 10-15% (simultaneous contrast causes vibration otherwise). Never pure black.

**Spacing execution rules:**

- **8pt grid** for all layout spacing. 4pt half-steps only for internal component spacing (padding within buttons, icon-to-label gaps).
- **Internal ≤ external** — component padding should be ≤ the space between components. When internal > external, grouping breaks.
- Whitespace is information architecture, not wasted space.
- Default generous, reduce only when content demands density.

**Depth execution rules:**

- **Multi-layer shadows** with Tobias Ahlin's doubling formula: 5 layers, Y and blur double each step, 12% opacity per layer. Never single `box-shadow` except for subtle focus rings.
- **Match shadow hue to background hue** at low saturation/lightness. Pure black shadows (`rgba(0,0,0,n)`) produce a washed-out grey that disconnects from the surface.
- **Single light source direction** across the entire page (slightly down-right by convention). Mixed directions destroy physical coherence.
- **Dark mode has no shadows** — use the lightness elevation system instead.

For the complete craft reference with additional rules and CSS patterns, **load [references/visual-craft.md](references/visual-craft.md) ONLY when you need a specific number not covered above** (e.g., modular scale ratios, specific easing curves beyond quart, shadow color formulas for dark-mode floating panels). **Do NOT load** if the above rules are sufficient.

## §2 Polish questions and what each catches (Phase 5)

**Ask yourself: what would someone who has seen a thousand generated pages clock in five seconds?**

Because removing indigo and Inter only moves the page to the next default: cream and a serif with a terracotta accent, near-black with one neon, an italic serif word in a sans headline, mono uppercase labels over every section, a pill above the h1, identical icon-in-a-square cards, a stat strip, a logo wall, the hero → features → how it works → testimonials → pricing → FAQ → "Ready to get started?" sequence, em-dash rhythm, "Not X. Just Y." Hand the sweep to a fresh Haiku subagent (see Orchestration) with the screenshots and the "Second-order tells" list (T0-T27) in [references/anti-patterns.md](references/anti-patterns.md); it returns each tell with its element. Each tell found is either removed and replaced by something that belongs to this client (their numbers, artefacts, place, product UI, words), or kept with one line naming the content that requires it. Removing a tell without a replacement leaves a hole; fill it. Then the brand-swap test: hide the top bar and look at the first screen; if it could belong to another brand in the same category, it is not done.

**Ask yourself: where does mathematical alignment lie to me?**

Because mathematical alignment produces visually misaligned results when elements have uneven visual weight. A play icon (triangle) in a circular button reads as left-shifted when mathematically centered — its visual mass anchors left, so shift 1-2px right. A glyph in a circular container reads as sitting too low — the eye anchors to cap height, not descender, so shift up 2-3% of container height. Text with descenders (g, p, y) in vertically centered containers reads low for the same reason — add 2-3% extra top padding. A circle at 40×40 carries ~20% less visual weight than a square at 40×40, so at equal math size the circle needs ~5-10% scale-up to read equal. Display headings above ~40px at default letter-spacing look loose and amateur — pull to -0.02em to -0.04em. If you did not ask this question, you shipped with silent visual noise.

**Ask yourself: can a user glancing at every button label for 0.5 seconds tell what will happen?**

Because users do not read buttons — they scan for outcome words. `OK` / `Cancel` is a scanning failure: both labels are generic and users pick one arbitrarily. Every button that contains `OK`, `Submit`, `Yes`, `No`, `Continue`, or `Click here` is a scanning failure that must be rewritten with the specific outcome: `Delete Account` / `Keep Account`, `Send invoice` / `Save draft`, `Create account` / `Sign in instead`. Extend the same test to copy: does every headline and CTA communicate a concrete outcome, or does it trade in the AI vocabulary that signals low effort on first read (*revolutionize, unlock, seamless, game-changing, cutting-edge, next-level, the future of, empower your, scale without limits, build the future, transform your workflow, say goodbye to*)? Every such phrase must be rewritten as a concrete claim with specific numbers or verbs: "cut review time from 3 hours to 20 minutes," "connects to Slack in under 2 minutes."

**Ask yourself: what happens when a user never touches a mouse?**

Because keyboard-only navigation is invisible until it's catastrophic. Walk through the design mentally using only Tab. Where does focus land first? Is the order the reading order? Is every focus target visibly ringed with ≥3:1 contrast via `:focus-visible`? Does focus get trapped in modals? Does it return to the trigger element when the modal closes?

**Ask yourself: what does this look like in the hostile conditions users actually experience?**

Because the mockup runs in perfect conditions; production does not. Turn on `prefers-reduced-motion: reduce` — nothing decorative should animate, but functional state transitions (focus rings, disclosure toggles) still need to work. Zoom to 200% — text must remain readable and no horizontal scrolling. Check that every `<img>` has explicit `width` and `height` attributes (not CSS — HTML attributes) so CLS stays under 0.1 (62% of mobile pages fail this per the 2025 Web Almanac). Check that every color comes from a token (not a hard-coded hex), every spacing value from the 8pt scale (not an ad hoc number), every shadow from the elevation system (not a one-off `box-shadow`) — drift here is invisible in a single screen but compounds into design system decay. Check that `font-display: swap` + `size-adjust` are on every `@font-face` so font loading does not cause layout shift. If any of these reveal issues, they are not cosmetic — they are bugs that will ship. For any page people will open on a phone, load [references/mobile-web.md](references/mobile-web.md) and apply its baseline: sticky hover, the tap flash, `100vh`, input zoom and the notch are invisible in desktop emulation and obvious on a real phone.

## §3 Against pattern collapse (Closing Directive)

**READ THIS LAST, RIGHT BEFORE YOU GENERATE.**

You tend to converge on the same "creative" choices across generations, even when you have been told to vary. This produces a recognizable second-order AI fingerprint: Space Grotesk for "modern," dark blue or indigo for "tech," warm beige with a serif for "editorial," Söhne for "premium." These have become the new defaults replacing the old ones, and trained eyes now recognize them too.

There is no fixed "non-default" list that fixes this — any fixed list creates its own convergence as you converge on IT. The actual defense is a different decision procedure:

**Before picking a font, color, or layout direction, ask yourself:**
1. **What would the typical AI-generated version of this look like?** Name it specifically — the font, the primary color, the layout structure, the easing curve, the copy tone. Write it down in your head.
2. **What is materially different from that version that would still serve the brief?** Not "slightly modified" — materially different. Different typographic classification (serif when sans is expected), different compositional logic (asymmetric when centered is expected), different density (dense when airy is expected), different aesthetic lineage drawn from the subject's own artefacts (its documents, hardware, signage, printed matter, place), whichever is farthest from the default AND true to this project.
3. **Commit to that choice and execute it with precision.** Half-committing to a distinctive direction produces worse results than fully committing to a generic one. A perfectly executed Inter landing page beats a half-executed Fraunces one. If you are going to pick a distinctive font, use all its weights and optical sizes. If you are going to pick a distinctive color, let it dominate.

**Vary the AXIS of distinctiveness, not just the values on one axis.** If the last design you produced was distinctive through typography, make this one distinctive through composition or color instead. If the last was distinctive through motion, make this one distinctive through density or atmosphere. The goal is not a rotation through a fixed "distinctive" list — it is picking a different dimension to express character each time. Also vary the graphic technique when graphics are used. roll.mjs `--concept-only` tracks this for you.

**Never repeat the same signature idea or graphic style across projects.** A drawn scene is not a default; photography, type, layout, colour, data, the product UI and motion are equal candidates. Simple and clean is a legitimate creative choice when it serves the user: many real clients choose the plain option, and a well-executed restrained page beats an over-decorated one.

**One more calibration.** When the Phase 3 direction genuinely requires breaking a Phase 4 rule — a terminal/monospace aesthetic requires a mono font even though the Phase 4 font list is mostly sans-serif; a zine/brutalist aesthetic wants jagged asymmetric shadows even though Phase 4 prescribes tiered multi-layer depth — break the rule deliberately and execute the break with craft. Phase 4 rules are defaults to escape, not laws to worship. The worst outcome is a half-committed distinctive direction constrained by Phase 4 rules that were meant for a different aesthetic. Commit fully.
