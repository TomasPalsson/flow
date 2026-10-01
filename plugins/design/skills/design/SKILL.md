---
name: design
description: Five-phase design process that escapes AI-slop defaults (bg-indigo-500, Inter, centered hero + 3-column grid, rounded-2xl uniformly, shadow-lg uniformly, "Build the future of X" copy). Use whenever generating, building, mocking up, improving, refining, polishing, critiquing, or evaluating any UI, frontend, or visual design. Phases: aesthetic commitment → UX architecture (Nielsen's 10, priority-ordered) → craft execution (OKLCH palettes, ease-out-quart cubic-bezier, tiered radius/shadow, ≥5-weight typography) → polish sweep → external skepticism-tuned evaluator subagent. Keywords: design, UI, UX, frontend, landing page, dashboard, component, form, modal, navbar, card, marketing page, SaaS, admin, portfolio, mobile app, build this, make this look good, not generic, not AI slop, production quality, best design, Nielsen heuristics, UX audit, design review, critique. For a brand-new site or page where looks should differ between runs, prefer `vary` (it assigns the direction); use `design` for critique, audits, polish, or when the user invokes it by name. Both start from the project dossier and draw custom graphics.
user-invocable: true
argument-hint: "[target description]"
---

# Design Excellence

Claude's default design output is not neutral. Without intervention, it collapses to the statistical center of its training distribution: `bg-indigo-500`, Inter font, centered hero + 3-column feature grid, `rounded-2xl`, `shadow-lg`, "Build the future of X" copy. Anthropic calls this "distributional convergence" in their own documentation. Users call it "AI slop." The Adam Wathan apology of August 2025 — "I'm sorry for making every button in Tailwind UI use bg-indigo-500... this caused every AI-generated interface on Earth to turn purple" — is the origin story.

This skill is the counterforce. Five phases, each with a gate. The final phase hands the output to a SEPARATE skepticism-tuned evaluator subagent because Anthropic's own harness research documented that Claude "confidently praises the work — even when, to a human observer, the quality is obviously mediocre." Self-critique is broken for creative work. External calibrated evaluation is not.

## The Process

Five phases. Each has a gate. Do not skip gates.

```
Phase 1: THINK        → commit to aesthetic direction before any code
Phase 2: ARCHITECT    → apply UX principles with priority ordering
Phase 3: EXECUTE      → craft numbers, not defaults
Phase 4: POLISH       → details that separate ship from shipped
Phase 5: EVALUATE     → separate subagent grades the output
```

---

## Phase 1 — Think

Before writing any code, answer these in your head (or out loud if the scope is large):

1. **Purpose.** What problem does this interface solve? Who uses it? What's the single thing they need to do most?
2. **Dossier.** Follow `../vary/references/dossier.md` and write `.vary/dossier.json`.
3. **Concept.** Write 4-7 concepts per `../vary/references/concepts.md`, then run `node <VARY>/scripts/roll.mjs --mode <m> --dossier .vary/dossier.json --concepts .vary/concepts.json --sector <s> --concept-only --project <repo-root>` (`<VARY>` is the sibling `vary` skill directory: this skill's "Base directory for this skill" path with the last segment `design` replaced by `vary`, or `${CLAUDE_PLUGIN_ROOT}/skills/vary` when set; substitute it literally. Never search the filesystem (`find`, `ls ~`) for the scripts and never run a copy under `~/.claude/plugins` or `~/.claude/skills` unless it IS that directory; if `<VARY>/scripts/roll.mjs` is missing, stop and say so. `--project` is required) and commit to the concept and device it prints. This keeps variety in `design` without a world roll. Choose the mode of the surface built first (home or landing page: usually `persuade`; app, dashboard, checkout: `operate`; docs and articles: `read`; portfolio or gallery: `experience`); later surfaces reuse the contract. Choose the sector a customer would file the business under; when torn between two, take the one whose worlds list fits the concept hints better and note it. Here no world is dealt, so a `--lock concept=<id> --reroll n` only re-deals the device.
4. **Signature graphic.** Name the device, the facts it encodes and its three placements.
5. **Constraints.** Framework, performance budget, accessibility targets, device context, brand system if one exists.

**Gate:** You can state the concept in one sentence, cite the three facts it rests on, and name the signature graphic and where it appears. If you cannot, you will default to AI slop.

**Critical move — motivate the constraint, don't just state it.** Tell yourself: "the user will feel this is AI-generated slop if it has purple gradients and Inter — they want this to feel crafted." Motivated constraints outperform bare prohibitions.

---

## Phase 2 — Architect

Before visual decisions, make UX decisions. Visual polish on a broken flow is lipstick on a pig.

**Tier 1 — non-negotiable foundations (every design must satisfy these):**

- **H2 Match the real world.** No jargon, no HTTP status codes, no database field names as labels, no system-oriented language. Every label, error, and CTA must be in the user's vocabulary.
- **H1 System status.** Every interactive state must exist: loading, success, error, empty, disabled. Not "happy path only." If the design has no empty state, it has a bug.
- **H9 Error recovery.** Every error message must say what happened, why, and what to do. "Something went wrong" is a failure. "Your card was declined — check the billing address below or try a different card" is correct.
- **H5 Error prevention.** Use constraints to make errors impossible, not confirmations to catch them. Disable submit until required fields are filled. Use date pickers, not free-text dates.
- **Contrast + keyboard.** WCAG AA: 4.5:1 for body text, 3:1 for large text and UI components. Every interactive element keyboard-accessible. Focus-visible rings are mandatory — `:focus-visible` outline with 3:1 contrast.

**Tier 2 — high leverage, routinely missed:**

- **Fitts's Law.** Touch targets 44-48px (WCAG 2.2 minimum is 24×24 — that's a floor, not a target). Primary CTAs at the natural end of attention flow. Related actions grouped spatially.
- **Proximity is information architecture.** Whitespace creates grouping without color or shape. "Make it more compact" usually means "make it harder to understand."
- **Jakob's Law.** Users spend most of their time on other sites. Default to platform conventions; justify every deviation with a proportionally larger benefit. Creativity goes into content, brand, and copy — NOT into reinventing navigation, forms, or error handling.
- **H8 Minimalism via progressive disclosure.** Not sparse — purposeful. Every element earns its place. Hide advanced options behind "Advanced" toggles.
- **H4 Consistency.** Same action = same label, same color, same position across the product. Internal consistency beats external when they conflict.

**Gate:** Before drawing anything, name the primary task, the touch target minimum, the empty/error/loading states you will design, and the single focal element per screen.

For deeper UX reference when stuck on a specific decision, load [references/ux-principles.md](references/ux-principles.md) — **Do NOT load** unless you are actively resolving a Tier 1 or Tier 2 concern and need the expert nuance beyond the summary above.

---

## Phase 3 — Execute

This is where craft numbers matter more than principles. The difference between "engineer-built" and "designer-quality" UI lives in specific values experts apply automatically.

**The NEVER-defaults — override all of these with intent:**

| Default | What Claude does | What you do instead |
|---------|------------------|---------------------|
| Font | Inter, Roboto, Arial, system-ui, Space Grotesk | A face chosen for the concept's trade, era or lettering heritage, with at least 5 weights, verified to render the content language's glyphs. Do not reuse the face from your last project. |
| Primary color | `bg-indigo-500`, purple, `from-indigo-500 to-purple-600` | Any hue EXCEPT indigo/purple, unless the brand legitimately requires it. Use OKLCH for definition. |
| Background | Pure white / `bg-gray-50` | Tinted neutral at chroma 0.005-0.01 in the brand hue, OR a material texture that the concept's artefact actually has (paper fibre, wood grain, brushed metal, blueprint grid). See graphics.md §2h. |
| Layout | Centered everything, 3-column feature grid, Hero→Features→CTA invariant | Asymmetric composition with intentional tension. Start from content, not template. |
| Radius | `rounded-2xl` on everything uniformly | Tiered scale: inputs 4px, buttons 6-8px, cards 10-12px, `rounded-full` reserved for avatars/pills |
| Shadow | `shadow-lg` on every card | Tiered elevation. Multi-layer shadows with doubling formula. Match shadow hue to background hue (never pure black). |
| Motion | Nothing, or AOS fade-in-up on everything, bounce/elastic easing | `ease-out-quart cubic-bezier(0.25, 1, 0.5, 1)` for enters. 150-300ms for interactive, 250-350ms for modal. Animate only transform/opacity. |
| Copy | "Build the future of X," "Scale without limits," "Empower your team" | Concrete claims with specific verbs, numbers, outcomes. "Cut review time from 3 hours to 20 minutes." |

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

**Motion execution rules:**

- **Ease-out-quart** `cubic-bezier(0.25, 1, 0.5, 1)` for entrances. **Never bounce or elastic** — they feel dated.
- **Duration:** 100-150ms micro-interactions (hover, focus), 150-250ms component (tooltip, dropdown), 250-350ms modal, 300-500ms spatial/route changes. When in doubt, halve your current duration.
- **Animate only `transform` and `opacity`.** Never `width`, `height`, `top`, `left`, `margin`, `padding` — they trigger layout recalculation on every frame and cause jank.
- **Never animate keyboard-triggered actions.** A user who hits Cmd+K 100 times a day will experience the animation as an obstacle, not delight.
- **Stagger ≤20ms per item, max 8 items.**
- `@media (prefers-reduced-motion: reduce)` is mandatory, not optional.

**Depth execution rules:**

- **Multi-layer shadows** with Tobias Ahlin's doubling formula: 5 layers, Y and blur double each step, 12% opacity per layer. Never single `box-shadow` except for subtle focus rings.
- **Match shadow hue to background hue** at low saturation/lightness. Pure black shadows (`rgba(0,0,0,n)`) produce a washed-out grey that disconnects from the surface.
- **Single light source direction** across the entire page (slightly down-right by convention). Mixed directions destroy physical coherence.
- **Dark mode has no shadows** — use the lightness elevation system instead.

For the complete craft reference with additional rules and CSS patterns, **load [references/visual-craft.md](references/visual-craft.md) ONLY when you need a specific number not covered above** (e.g., modular scale ratios, specific easing curves beyond quart, shadow color formulas for dark-mode floating panels). **Do NOT load** if the above rules are sufficient.

**Gate:** Your output has explicit typography choices (by name), an explicit color approach (OKLCH values or named palette), a spacing scale, an easing function, and at least three designed states (not just happy path).

---

## Phase 3b — Author the graphics

Read `../vary/references/graphics.md` (§0b the benchmark, §1b "Composing a scene" the method) and run its §7 art-brief → gallery → screenshot critique loop (two rounds, then build: hero first, plates second; a shipped page with good art beats a perfect gallery and no page) before building pages. The art must meet the scene bar:

- **Hero scene (S1).** For persuade and experience: **edge to edge, no frame (G1).** The hero scene spans the full viewport width at desktop and phone (at least 95%, touching both edges): no HTML box, card, polaroid, frame or page margin around it (a border drawn inside the art, such as a blueprint sheet's, is part of the art). Judges: "full-bleed scene, not a framed picture". For persuade and experience surfaces the first viewport is a full-bleed illustrated scene or sheet: the drawing covers at least 55% of the first viewport at 1440x900 and 45% at 390x844, composed of at least 5 distinct subject objects from the dossier across at least 3 depth layers (environment, main subject, foreground detail or people). The brand or headline is set INTO the scene (sign, label, title block, painted lettering), not floated beside a boxed picture, and at least 2 real dossier facts are drawn inside the art (phone on the sign, founding year in a title block, hours on a door card). Operate and read surfaces: the device may sit at plate scale, with at least one full-width plate.
- **Richness floor (S2).** Filled shapes, one consistent light source (lit and shaded faces, cast shadows), texture (grain, hatching, halftone, paper), people or traces of use where the business has them, 4-7 inks. A single icon, bare grid, lone diagram in a framed box or decorative blob fails the hero.
- **Art all the way down (S3).** Every section below the fold carries its own drawn plate at real size (at least 40% of the section's width (never under a third — the gate fails plates under 35%) and 280px tall at desktop, never thumbnail-only, and fully rendered with the same finish pass as the hero: gradient, glow, grain, at least 3 value steps; never a thin, small, pale line diagram in a tinted box), drawn from that section's facts; a catalogue, menu or services list draws EACH item (the art is a function of the item record). A section that is only cards, text or a form fails unless it is the contact block. Plus micro-scale icons, bullets and dividers in the same hand.
- **Finish (S4, G2).** `graphics.md` §1d and its Depth recipe (flat fills with thin uniform strokes read as clip art): a value plan (one key light, one glow, brightest value on the focal fact), at least 3 value steps per material, grain at 3-8%, no empty region over 20% of the hero.
- **Type in the art (S5, G3).** No frosted, translucent or SOLID card, chip row or SaaS button pair over the hero art: an opaque headline container covering more than 6% of the art area fails (judges: "a headline card floats over the art, covering it"). Headline, phone, hours and the primary action are painted onto drawn surfaces inside the svg (sign, plate, title block, chalkboard, ticket, label; §1b has the worked example of a sign that is a real link).
- **Objects and body composition (S7).** Every drawn object has a real silhouette (a train has bogies, windows and a roof line; a book has spine, boards and headband; never a box standing for a thing), at least 3 value steps, and people have a posture or gesture and a cast shadow (`graphics.md` §1e). No two consecutive sections share a layout skeleton: the art brief assigns one of six per section (full-bleed plate with caption; catalogue of drawn items; process strip of 3-5 drawn steps; map or plan; big quote over art; ticket, label or form drawn as an object), and every section plate is a drawing of that section's subject, never a labelled box with words in it. Each fact (price list, hours, address) appears once in the page body; the footer may repeat contact details only.
- **Headline on the fold.** The first viewport always carries the business name AND a one-line value proposition, painted on a drawn surface in the scene (sign, board, title block, ticket): never omitted, never on a floating card.
- **No collisions (S6).** Every label, callout and sign text is fully visible at both viewports: no overlap with drawn objects or other labels.
- **Art crew (after the art brief).** Read `../vary/references/art-crew.md`. Dispatch illustrator subagents IN PARALLEL with the Agent tool: one for the hero scene and one per section plate (cap 6), each handed ONLY the art-brief path, its plate's row (subject, facts, skeleton, size), the style object and core kit paths, and `art-crew.md`. Each builds its plate module, renders it at real size, critiques its own screenshot against the richness bar (objects not boxes, posture, shared ground and light, 3+ values, texture, facts in the art), fixes, and returns the module path and final PNG path. The lead integrates and does not redraw; without the Agent tool the lead draws the plates itself in the same order.

Each critique round compares the gallery screenshot against S1-S3 and the §0b benchmark descriptions and lists what is missing (objects, layers, light, texture, facts-in-art, coverage). **Gate:** the signature device renders at hero, divider and micro scale, the hero scene is composed whole, and every critique item from round 2 is closed.

---

## Phase 4 — Polish

Polish is the last step, not the first. Do not polish work that is not functionally complete. An expert polishing a design does not walk through a labeled checklist — they scan with a trained eye for specific failure modes that an untrained eye misses. Transfer that trained-eye by interrogating the design with these questions, not by marching through a sequence.

**Ask yourself: where does mathematical alignment lie to me?**

Because mathematical alignment produces visually misaligned results when elements have uneven visual weight. A play icon (triangle) in a circular button reads as left-shifted when mathematically centered — its visual mass anchors left, so shift 1-2px right. A glyph in a circular container reads as sitting too low — the eye anchors to cap height, not descender, so shift up 2-3% of container height. Text with descenders (g, p, y) in vertically centered containers reads low for the same reason — add 2-3% extra top padding. A circle at 40×40 carries ~20% less visual weight than a square at 40×40, so at equal math size the circle needs ~5-10% scale-up to read equal. Display headings above ~40px at default letter-spacing look loose and amateur — pull to -0.02em to -0.04em. If you did not ask this question, you shipped with silent visual noise.

**Ask yourself: can a user glancing at every button label for 0.5 seconds tell what will happen?**

Because users do not read buttons — they scan for outcome words. `OK` / `Cancel` is a scanning failure: both labels are generic and users pick one arbitrarily. Every button that contains `OK`, `Submit`, `Yes`, `No`, `Continue`, or `Click here` is a scanning failure that must be rewritten with the specific outcome: `Delete Account` / `Keep Account`, `Send invoice` / `Save draft`, `Create account` / `Sign in instead`. Extend the same test to copy: does every headline and CTA communicate a concrete outcome, or does it trade in the AI vocabulary that signals low effort on first read (*revolutionize, unlock, seamless, game-changing, cutting-edge, next-level, the future of, empower your, scale without limits, build the future, transform your workflow, say goodbye to*)? Every such phrase must be rewritten as a concrete claim with specific numbers or verbs: "cut review time from 3 hours to 20 minutes," "connects to Slack in under 2 minutes."

**Ask yourself: what happens when a user never touches a mouse?**

Because keyboard-only navigation is invisible until it's catastrophic. Walk through the design mentally using only Tab. Where does focus land first? Is the order the reading order? Is every focus target visibly ringed with ≥3:1 contrast via `:focus-visible`? Does focus get trapped in modals? Does it return to the trigger element when the modal closes?

**Ask yourself: for every interactive element, which of the nine states can I actually describe right now?** Default, hover, focus-visible, active, disabled, loading, error, success, empty — can you picture each one concretely for every button, input, and link on the screen? Any state you cannot immediately describe does not exist. Missing states are not edge cases; they are core flows the first-pass generation skipped because the happy path was sufficient. This is the #1 source of "it looked good in the mockup but broke in production."

**Ask yourself: what does this look like in the hostile conditions users actually experience?**

Because the mockup runs in perfect conditions; production does not. Turn on `prefers-reduced-motion: reduce` — nothing decorative should animate, but functional state transitions (focus rings, disclosure toggles) still need to work. Zoom to 200% — text must remain readable and no horizontal scrolling. Check that every `<img>` has explicit `width` and `height` attributes (not CSS — HTML attributes) so CLS stays under 0.1 (62% of mobile pages fail this per the 2025 Web Almanac). Check that every color comes from a token (not a hard-coded hex), every spacing value from the 8pt scale (not an ad hoc number), every shadow from the elevation system (not a one-off `box-shadow`) — drift here is invisible in a single screen but compounds into design system decay. Check that `font-display: swap` + `size-adjust` are on every `@font-face` so font loading does not cause layout shift. If any of these reveal issues, they are not cosmetic — they are bugs that will ship.

**Craft-bug rules (Polish checklist).** Content is visible with no JS-triggered reveal (an element may animate in only from a visible state); no full-viewport overlay or backdrop left on the page; nothing in the hero is cropped by the nav or the viewport edge; every dial, axis or scale is monotonic and labelled with real values; every callout leader ends on its object.

**Critic before shipping (Phase 4b).** Spawn a FRESH subagent (Agent tool) with the desktop and phone fold and full-page screenshots, the dossier facts, and the critic prompt and rubric from `../vary/references/art-crew.md` section 5 (specificity, graphics, craft, wow, each 1-10; `graphics.md` §0b anchors at 9-10, "pill figures / boxes for objects / template sections / clipped text / dead space" at 4-5). It returns scores and the 5 highest-impact fixes; apply them and re-run a new critic; stop at mean 7.5 or more or after 2 critic rounds, logging open items in NOTES.md. After applying fixes, re-run `check.mjs` and the fold check and refresh the evaluator JSON before Phase 5; record the last critic mean in NOTES.md. Critic rounds sit outside the art budget and may be skipped when time is short.

**Gate:** You cannot answer "I'm not sure" to any of the four questions above and consider the design polished. If you can't answer, you have not actually run the check.

For the complete anti-pattern catalog with additional classical/accessibility/performance failure modes, **load [references/anti-patterns.md](references/anti-patterns.md) before shipping a high-stakes design** (landing page, flagship feature, public marketing, customer-facing flow). **Do NOT load** for internal tools or prototypes where the four questions above are sufficient.

---

## Phase 5 — Evaluate

**Do NOT load [`references/evaluation-rubric.md`](references/evaluation-rubric.md) yourself.** That file belongs to the evaluator subagent. If you load it, you contaminate the generator/evaluator separation that makes Phase 5 effective — the criteria that grade the design would also shape your generation, and Anthropic's own harness research documents that this collapses the quality signal. The evaluator subagent reads the rubric; you read only `evaluator-prompt.md` to understand what the subagent will do.

**This phase is mandatory for any design the user will actually ship.** It is skippable only for throwaway prototypes or sketches where the user explicitly said "just something quick."

**To run the evaluator:**

1. **Collect the design output.** If it is a file you created, note the absolute file path. If it is a rendered component in a conversation, save it to a temp file first so you can pass a path rather than a massive string.
2. **Read [`evaluator-prompt.md`](evaluator-prompt.md)** — this is the complete prompt template for the subagent. Do not paraphrase it; you will copy it verbatim.
3. **Spawn a subagent** using the Agent tool with `subagent_type: "general-purpose"`, `model: "sonnet"`, and `mode: "bypassPermissions"` (so the subagent can read the rubric file without permission prompts). The task prompt is: the full content of `evaluator-prompt.md`, followed by a clear delimiter (`\n\n---\n\nDESIGN TO EVALUATE:\n\n`), followed by the absolute file path(s) of the design output with an explicit instruction that the subagent should Read each file in full. Also pass `.vary/dossier.json`, `.vary/art-brief.md`, `.vary/critique-r2.json` and the gallery and page screenshots. For short designs (<200 lines), you may inline the source instead of passing a path.
4. **The evaluator returns a structured report** with: per-dimension scores (Usability, Composition, Color+Type, Interaction, Accessibility, Microcopy, Project specificity), a weighted composite, specific violations with severity, and prioritized fixes.
5. **Iterate based on score:**
   - Composite ≥ 4.0 (B grade or better) → SHIP.
   - Composite 3.0-3.9 (C) → apply the top 3 fixes and re-spawn a NEW evaluator (fresh context, no memory of prior iteration).
   - Composite < 3.0 (D/F) → return to Phase 2 or Phase 3 depending on which dimensions scored lowest. Usability/Interaction failures point back to Phase 2. Composition/Color/Typography failures point back to Phase 3.
   - Project specificity dimension score ≤2 (whatever the composite) → return to Phase 1.

**Iterate until the score converges or ≥ 4.0.** Anthropic's harness research shows creative leaps happen in iteration 7-9, not iteration 1. The evaluator loop is where quality compounds — single-pass design peaks at "competent," iterated design peaks at "memorable."

**If the evaluator subagent fails** — the Agent tool is unavailable, the subagent cannot read the rubric file, it returns no structured report, or it returns a malformed/truncated response — do NOT proceed silently. Fall back to a degraded self-evaluation against the seven dimensions in `evaluator-prompt.md` (Usability 20%, Composition 15%, Color+Type 15%, Interaction 15%, Accessibility 10%, Microcopy 5%, Project specificity 20%), applying the bias mitigations from that file explicitly (evidence-first, sequential dimensions, negative-first framing, "cannot determine" for items not assessable). Report the result to the user AS a self-evaluation — not as a subagent evaluation — and note that the quality signal is lower fidelity because the generator/evaluator separation is broken. Ask the user whether to ship the self-evaluated result or retry the subagent.

---

## The NEVER List

Explicit, non-negotiable. These are not guidelines — these are the landmines that signal AI-generated work the moment a trained eye sees them.

- **Never use `bg-indigo-500`, `text-indigo-600`, or `from-indigo-500 to-purple-600`** unless the brand legitimately requires indigo. This is the signature of AI output.
- **Never default to Inter, Roboto, Arial, system-ui, or Space Grotesk.** Even when the user says "clean sans-serif," pick something with character.
- **Never apply `rounded-2xl` uniformly** to buttons, cards, inputs, and containers. Tier the radius scale.
- **Never apply `shadow-lg` uniformly** as the universal elevation signal. When every element has the same shadow, the metaphor of elevation breaks — nothing is actually elevated relative to anything else, and the spatial information the shadow was supposed to carry disappears. Tier the shadow system with multi-layer shadows.
- **Never use glassmorphism (`backdrop-filter: blur()`) on more than one or two layers per page.** It destroys contrast and tanks performance.
- **Never write "Build the future of X," "Scale without limits," "Empower your team," "Revolutionize your workflow," "Unlock the power of Y," "Seamless integration," "Cutting-edge," "Game-changing," "Next-level."** Replace every one with a concrete claim with specific numbers or verbs.
- **Never use emoji as functional icons.** They render inconsistently across OS/browsers, screen readers announce them awkwardly, and they signal "this is a casual personal project."
- **Never remove focus outlines with `outline: none` without replacement.** Use `:focus-visible` with a 3:1 contrast ring.
- **Never use color as the only signifier** for state (error, required, success, warning). Pair with icon, text, or position.
- **Never ship icon-only buttons without `aria-label`.** Screen reader users get nothing.
- **Never auto-play video with audio** or ignore `prefers-reduced-motion`. Auto-play violates WCAG 1.4.2 / 2.2.2. Users with vestibular disorders (affecting ~35% of adults over 40) can experience nausea and vertigo from motion they did not initiate.
- **Never animate `width`, `height`, `top`, `left`, `margin`, `padding`, or `font-size`.** Use `transform` and `opacity` only.
- **Never use placeholder text as the only label.** It disappears on focus and fails WCAG.
- **Never ship a form with submit-only validation.** Validate on blur, show success checkmarks on correct fields.
- **Never present only the happy path.** Empty state, loading state, error state, disabled state, long-content state — all must exist.
- **Never use pure black (`#000000`) or pure white (`#ffffff`).** Use tinted neutrals — pure black is harsh, pure white is cold, and both signal absence of color decisions.
- **Never let your evaluator be yourself.** Spawn a separate subagent. Self-praise is the default.

---

## Closing Directive — Against Pattern Collapse

**READ THIS LAST, RIGHT BEFORE YOU GENERATE.**

You tend to converge on the same "creative" choices across generations, even when you have been told to vary. This produces a recognizable second-order AI fingerprint: Space Grotesk for "modern," dark blue or indigo for "tech," warm beige with a serif for "editorial," Söhne for "premium." These have become the new defaults replacing the old ones, and trained eyes now recognize them too.

There is no fixed "non-default" list that fixes this — any fixed list creates its own convergence as you converge on IT. The actual defense is a different decision procedure:

**Before picking a font, color, or layout direction, ask yourself:**
1. **What would the typical AI-generated version of this look like?** Name it specifically — the font, the primary color, the layout structure, the easing curve, the copy tone. Write it down in your head.
2. **What is materially different from that version that would still serve the brief?** Not "slightly modified" — materially different. Different typographic classification (serif when sans is expected), different compositional logic (asymmetric when centered is expected), different density (dense when airy is expected), different aesthetic lineage drawn from the subject's own artefacts (its documents, hardware, signage, printed matter, place), whichever is farthest from the default AND true to this project.
3. **Commit to that choice and execute it with precision.** Half-committing to a distinctive direction produces worse results than fully committing to a generic one. A perfectly executed Inter landing page beats a half-executed Fraunces one. If you are going to pick a distinctive font, use all its weights and optical sizes. If you are going to pick a distinctive color, let it dominate.

**Vary the AXIS of distinctiveness, not just the values on one axis.** If the last design you produced was distinctive through typography, make this one distinctive through composition or color instead. If the last was distinctive through motion, make this one distinctive through density or atmosphere. The goal is not a rotation through a fixed "distinctive" list — it is picking a different dimension to express character each time. Also vary the graphic technique: if the last project's signature was a seeded illustration, this one is traced line, a diagram or a pattern. roll.mjs `--concept-only` tracks this for you.

**One more calibration.** When the Phase 1 aesthetic direction genuinely requires breaking a Phase 3 rule — a terminal/monospace aesthetic requires a mono font even though the Phase 3 font list is mostly sans-serif; a zine/brutalist aesthetic wants jagged asymmetric shadows even though Phase 3 prescribes tiered multi-layer depth — break the rule deliberately and execute the break with craft. Phase 3 rules are defaults to escape, not laws to worship. The worst outcome is a half-committed distinctive direction constrained by Phase 3 rules that were meant for a different aesthetic. Commit fully.
