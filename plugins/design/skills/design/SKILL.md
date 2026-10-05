---
name: design
description: Design process that puts UX and usability first (task, findability, hierarchy, accessibility, phone), then fit to the client's real content, then a creative, project-specific look that escapes AI-slop defaults (bg-indigo-500, Inter, centered hero + 3-column grid, uniform rounded-2xl and shadow-lg, "Build the future of X" copy). Use whenever generating, building, mocking up, improving, refining, polishing, critiquing, or evaluating any UI, frontend, or visual design. Phases: understand → UX architecture (Nielsen's 10, priority-ordered) → direction (dossier, concept, signature idea) → craft execution (OKLCH palettes, ease-out-quart, tiered radius/shadow, ≥5-weight typography) → graphics check → polish sweep → external skepticism-tuned evaluator subagent. Custom graphics (icons, illustrations, brand objects) come from `design:graphics` when the page needs them. Keywords: design, UI, UX, frontend, landing page, dashboard, component, form, modal, navbar, card, marketing page, SaaS, admin, portfolio, mobile app, build this, make this look good, not generic, not AI slop, production quality, best design, Nielsen heuristics, UX audit, design review, critique. For a brand-new site or page where looks should differ between runs, prefer `vary` (it assigns the direction); use `design` for critique, audits, polish, or when the user invokes it by name.
user-invocable: true
argument-hint: "[target description]"
---

# Design Excellence

Claude's default design output is not neutral. Without intervention, it collapses to the statistical center of its training distribution: `bg-indigo-500`, Inter font, centered hero + 3-column feature grid, `rounded-2xl`, `shadow-lg`, "Build the future of X" copy. Anthropic calls this "distributional convergence" in their own documentation. Users call it "AI slop." The Adam Wathan apology of August 2025 — "I'm sorry for making every button in Tailwind UI use bg-indigo-500... this caused every AI-generated interface on Earth to turn purple" — is the origin story.

This skill is the counterforce. Priority order: first UX and usability (the user finishes their task, finds things, can read and operate it on a phone, with assistive tech), then fit to the client's real content, then creativity and variety. Each phase has a gate. The final phase hands the output to a SEPARATE skepticism-tuned evaluator subagent because Anthropic's own harness research documented that Claude "confidently praises the work — even when, to a human observer, the quality is obviously mediocre." Self-critique is broken for creative work. External calibrated evaluation is not.

## The Process

Each phase has a gate. Do not skip gates.

```
Phase 1:  UNDERSTAND  → purpose, users, primary task, existing system, constraints
Phase 2:  ARCHITECT   → apply UX principles with priority ordering
Phase 3:  DIRECTION   → dossier, concept, the one signature idea
Phase 4:  EXECUTE     → craft numbers, not defaults
Phase 4b: GRAPHICS    → graphics check; design:graphics when the page needs custom art
Phase 5:  POLISH      → details that separate ship from shipped
Phase 6:  EVALUATE    → separate subagent grades the output
```

---

## Phase 1 — Understand

Before writing any code, answer these in your head (or out loud if the scope is large):

1. **Purpose and users.** What problem does this interface solve? Who uses it, on what device, in what mood? What is the single thing they need to do most (the primary task)?
2. **Existing system (extend mode).** If the repo already has a visual system (DESIGN.md, a token or theme file, styled shared components, or existing pages that share one palette and type), read `../vary/references/extend-mode.md` and follow it for everything below: it decides what still rolls, and shared files stay append-only. This holds for a whole new page in an existing site too, not only for a section. A component, section, critique, polish or audit inside an existing surface: read the surface, write no dossier and run no roll; skip Phase 3 and carry on at Phase 4.
3. **Constraints.** Framework, performance budget, accessibility targets, device context, brand system if one exists, and any user directives in their own words.

**Gate:** You can state the primary task and the user in one sentence. For a component, critique, polish or audit: you can name the surface's existing system and the one thing you will change.

**Critical move: motivate the constraint, don't just state it.** Tell yourself: "the user will feel this is AI-generated slop if it has purple gradients and Inter. They want this to feel crafted, and they want to finish their task." Motivated constraints outperform bare prohibitions.

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

On operate surfaces Jakob's law governs controls: nav, forms and errors keep platform conventions and are skinned through tokens, not re-invented in the world's material.

**Precedence (highest first):** 1 truth (no invented facts); 2 accessibility and usability; 3 user directives (`dossier.directives`, or the user's own words in this request when no dossier exists); 4 existing brand or design system (extend mode); 5 platform conventions (ios/android, operate Jakob's law); 6 the rolled contract; 7 skill defaults.

**Gate:** Before drawing anything, name the primary task, the touch target minimum, the empty/error/loading states you will design, and the single focal element per screen.

For deeper UX reference when stuck on a specific decision, load [references/ux-principles.md](references/ux-principles.md). **Do NOT load** unless you are actively resolving a Tier 1 or Tier 2 concern and need the expert nuance beyond the summary above.

---

## Phase 3 — Direction

New surface or redesign only; inside an existing system skip this phase (extend mode).

1. **Dossier.** Follow `../vary/references/dossier.md` and write `.vary/dossier.json`: the client's real facts, audience, refusals and directives. Never invent facts.
2. **Concepts and roll.** Write 4-7 concepts per `../vary/references/concepts.md`, then run `node <VARY>/scripts/roll.mjs --mode <m> --dossier .vary/dossier.json --concepts .vary/concepts.json --sector <s> --concept-only --project <repo-root>` (`<VARY>` is the sibling `vary` skill directory: this skill's "Base directory for this skill" path with the last segment `design` replaced by `vary`, or `${CLAUDE_PLUGIN_ROOT}/skills/vary` when set; substitute it literally. Never search the filesystem (`find`, `ls ~`) for the scripts and never run a copy under `~/.claude/plugins` or `~/.claude/skills` unless it IS that directory; if `<VARY>/scripts/roll.mjs` is missing, stop and say so. `--project` is required) and commit to the concept and device it prints. This keeps variety in `design` without a world roll. Choose the mode of the surface built first (home or landing page: usually `persuade`; app, dashboard, checkout: `operate`; docs and articles: `read`; portfolio or gallery: `experience`); later surfaces reuse the contract. Choose the sector a customer would file the business under; when torn between two, take the one whose worlds list fits the concept hints better and note it. Here no world is dealt, so a `--lock concept=<id> --reroll n` only re-deals the device.
3. **Signature idea.** Name the one idea that makes this project recognisable, the dossier facts it rests on, and where it appears (three placements). It can be type, layout, colour, photography, the product UI, data, motion or graphics. No treatment is the default; pick the one that serves this client and this audience. Options, each with its rule:
   - `photography`: the client's photos carry the page, shipped unaltered (no filter, frame or ornament); identifiable real people are never redrawn; described-but-missing photos become full-size tonal plates (`../vary/references/build-craft.md` §6 item 19).
   - `product-ui`: the product's own interface rebuilt with real data, real states and DPR-2 captures; callouts allowed.
   - `typography`: lettering at display size in the content language's glyphs, tied to a fact the lettering carries.
   - `data-visual`: a chart or table drawn from the dossier's real data, with a text equivalent.
   - `utility`: the tool or document itself is the first screen; no art.
   - `pattern`: a generated or drawn pattern from the trade's own artefacts.
   - `scene`: a drawn scene, only when the concept calls for it and the client has no better material; never chosen by default.
   - Native platform (ios/android): hand the platform layer to the `mobile-design` skill; evidence is device screenshots.

   Simple and clean is a legitimate choice when the client asks for it or the surface is a dense tool; for a business, brand or event homepage, clean is the floor, not the goal: give it one memorable idea and the small custom details that make it this client's own. Usable and uninspired is a failure too.

Before running the roll, run the idea check in `../vary/references/concepts.md` §3b: a fresh creative-director subagent scores every concept, and only concepts at 7 or above go to the roll.

**Gate:** You can state the concept in one sentence, cite the three facts it rests on, and name the signature idea and where it appears. If you cannot, you will default to AI slop.

---

## Phase 4 — Execute

**Section plan (before any page code).** Write `.vary/section-plan.md`: one row per section, top to bottom, with (1) the section's job for the user, (2) how the signature idea shows up there at full strength, in a way that does the job (the care tag on each product, the theme in the programme slots, the data story in the detail view), and (3) its layout skeleton, different from its neighbours. "Standard cards", "a list" or "a table" are allowed only for dense data, legal text or forms, and even then carry one detail of the idea. A section whose row says the idea does not appear is redesigned before it is built. Build from this plan.

This is where craft numbers matter more than principles. The difference between "engineer-built" and "designer-quality" UI lives in specific values experts apply automatically.

**The NEVER-defaults — override all of these with intent:**

| Default | What Claude does | What you do instead |
|---------|------------------|---------------------|
| Font | Inter, Roboto, Arial, system-ui, Space Grotesk | A face chosen for the concept's trade, era or lettering heritage, with at least 5 weights, verified to render the content language's glyphs. Do not reuse the face from your last project. |
| Primary color | `bg-indigo-500`, purple, `from-indigo-500 to-purple-600` | Any hue EXCEPT indigo/purple, unless the brand legitimately requires it. Use OKLCH for definition. |
| Background | Pure white / `bg-gray-50` | Tinted neutral at chroma 0.005-0.01 in the brand hue, OR a material texture that the concept's artefact actually has (paper fibre, wood grain, brushed metal, blueprint grid). |
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

## Phase 4b — Graphics check

Custom graphics serve the user and the brand. Call the `design:graphics` skill when the page has at least one of:

1. **Icons:** the nav, categories, features or states need icons and a consistent custom set adds identity or clarity beyond a standard library (a standard library such as Lucide is fine on operate surfaces when it fits).
2. **Explanation:** a process, mechanism, place, route or data the user must understand reads faster drawn (steps, diagram, map, chart form).
3. **States:** empty, error, success or onboarding screens that a small illustration makes friendlier or clearer.
4. **Brand objects:** functional reskin objects that make the site what it is (price tags, coupons, tickets, stamps, labels, cards drawn as the trade's own artefacts).
5. **Imagery:** hero or section imagery when the client has no usable photos or product UI and the concept calls for drawn art (spot illustrations, objects, a scene, a pattern; never a scene by default). A business that sells physical things and has no photos gets a drawing of each product.
6. **The user asked** for illustrations, cartoons, icons or drawings.

Do not call it when: a directive forbids illustrations; the surface is a dense tool (dashboard, admin, docs) where a standard icon library covers the icons; or photos or the product UI already carry the page's character and nothing else needs drawing.

**Character is a job too.** On a persuade or experience page for a business, brand or event, small custom graphics that make the site recognisably this client's are a brand job, not decoration: icons for the facts people scan (care, hours, steps, features), a small drawing per product, service or category, brand objects drawn as the trade's own artefacts, and art where there are no photos. Lean towards calling the graphics skill there; a page with no custom graphics at all must have another clear signature (photography, the product UI, a strong typographic or data idea). Usability still comes first: graphics never replace a label, slow a task or push content below the fold.

When it applies, write `.vary/graphics-brief.md`:

- **Project:** one line; the audience and the mood they need.
- **Page system:** palette tokens (hex), fonts, radius and stroke feel, light or dark, and any user directives.
- **Assets:** one row each: `id`, `kind` (icon-set | spot | hero | section | diagram | map | object | pattern), what it shows, which dossier facts it carries, the UX job it does (why a user is better off with it), size or aspect, placement.
- **Output dir:** default `assets/art/`.

Then invoke `Skill(design:graphics, args: ".vary/graphics-brief.md")`. It returns the files (SVG, or JS modules rendering SVG) and `assets/art/GRAPHICS.md` with each asset's file, size, alt text (or `aria-hidden` for decoration) and placement. Integrate the files and use that alt text; never redraw them. The graphics skill's own method lives in `../graphics/references/graphics.md` and `../graphics/references/art-crew.md`; this skill does not load it.

**Gate:** The graphics check is answered (called, with the returned files integrated, or not called with the reason), and every graphic on the page has a UX or brand job.

---

## Phase 4c — Carry-through

**Carry-through check (before the critic).** Spawn a FRESH subagent (Agent tool, `model: opus`) with the full-page screenshots at desktop and phone, `.vary/section-plan.md` and the one-sentence concept. It scrolls the page top to bottom and answers, per section: is the idea present and doing a job here, or has the page fallen back to the category's default cards and lists? It names the weakest section and the concrete change that would carry the idea into it, and flags repetition (the same content shown twice to carry the idea) and a broad metaphor that has replaced the most subject-specific element; both are failures to fix, not ways to carry the idea. Rebuild that section (and any other it flags as "idea absent"), then re-shoot. One round; usability fixes still win any conflict.

---

## Phase 5 — Polish

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

**Blocking craft fails (all treatments).**

- **Headline on the first screen.** Persuade and experience: a real HTML `<h1>` (business name or the promise), a one-line value proposition and the primary action (link or button with visible text); never only svg `<text>`, never omitted. Operate and read: a visible `<h1>` or page title.
- **Mood fit.** State the audience's mood need (children: bright, safe, daytime; bereavement: calm, quiet, dignified; B2B lab: precise, trustworthy); a concept that breaks it is re-rolled with `--lock concept=<id>` before building further.
- **No collisions, no clipped text.** Every label, callout and text is fully visible at both viewports: no overlap with objects or other labels.
- **Page overflow, meta-copy, duplicate content.** Nothing wider than the viewport at 1440 or 390 unless inside its own scroll container; no designer or scaffold language in visible text (exempt with `data-meta-ok`); each fact appears once in the body (the footer may repeat contact details); intentional repeats are marked `data-repeat-ok`.
- **Phone width, native and honest.** `../vary/references/build-craft.md` §6 items 17-28 (show the subject at hero scale, the signature carries the page, time-aware content, place questions get a map, first screen answers the top question, products shown, brand objects carry real content, phone nav behind a menu button past three links): nothing scrolls sideways or clips at 390px; no designer notes or design keys on the page; photos carry a photography page; app screens use native controls and dashboards plot only real data.

Run the fold check as `node <VARY>/scripts/fold-check.mjs <page> --mode <m> --treatment <t>`, where `<t>` is the treatment the contract names. The rows collisions, clipped-text, hidden-content, stray-overlay, duplicate-content, page-overflow, meta-copy and headline-on-fold (operate/read: title-on-fold) must be PASS; the time budget never excuses them. Rows printed `[INFO]` are not gated. After fixes, re-run `check.mjs` and the fold check and refresh the evaluator JSON before Phase 6. User DIRECTIVES outrank every bar here: a directive such as "no illustrations" or "plain black and white" is never answered with added art.

**Gate:** You cannot answer "I'm not sure" to any of the four questions above and consider the design polished. If you can't answer, you have not actually run the check.

For the complete anti-pattern catalog with additional classical/accessibility/performance failure modes, **load [references/anti-patterns.md](references/anti-patterns.md) before shipping a high-stakes design** (landing page, flagship feature, public marketing, customer-facing flow). **Do NOT load** for internal tools or prototypes where the four questions above are sufficient.

---

## Phase 6 — Evaluate

**Do NOT load [`references/evaluation-rubric.md`](references/evaluation-rubric.md) yourself.** That file belongs to the evaluator subagent. If you load it, you contaminate the generator/evaluator separation that makes Phase 6 effective — the criteria that grade the design would also shape your generation, and Anthropic's own harness research documents that this collapses the quality signal. The evaluator subagent reads the rubric; you read only `evaluator-prompt.md` to understand what the subagent will do.

**This phase is mandatory for any design the user will actually ship.** It is skippable only for throwaway prototypes or sketches where the user explicitly said "just something quick."

**To run the evaluator:**

1. **Collect the design output.** If it is a file you created, note the absolute file path. If it is a rendered component in a conversation, save it to a temp file first so you can pass a path rather than a massive string.
2. **Read [`evaluator-prompt.md`](evaluator-prompt.md)** — this is the complete prompt template for the subagent. Do not paraphrase it; you will copy it verbatim.
3. **Spawn a subagent** using the Agent tool with `subagent_type: "general-purpose"`, `model: "sonnet"`, and `mode: "bypassPermissions"` (so the subagent can read the rubric file without permission prompts). The task prompt is: the full content of `evaluator-prompt.md`, followed by a clear delimiter (`\n\n---\n\nDESIGN TO EVALUATE:\n\n`), followed by the absolute file path(s) of the design output with an explicit instruction that the subagent should Read each file in full. Also pass `.vary/dossier.json` when it exists, the page screenshots, `assets/art/GRAPHICS.md` when graphics were made, and the fold-check output produced with `--treatment <t>`. For short designs (<200 lines), you may inline the source instead of passing a path.
4. **The evaluator returns a structured report** with: per-dimension scores (Usability, Interaction, Accessibility, Microcopy, Composition, Color+Type, Project specificity and creativity), a weighted composite, specific violations with severity, and prioritized fixes.
5. **Iterate based on score:**
   - Composite ≥ 4.0 (B grade or better) → SHIP.
   - Composite 3.0-3.9 (C) → apply the top 3 fixes and re-spawn a NEW evaluator (fresh context, no memory of prior iteration).
   - Composite < 3.0 (D/F) → return to Phase 2 or Phase 4 depending on which dimensions scored lowest. Usability/Interaction/Accessibility failures point back to Phase 2. Composition/Color/Typography failures point back to Phase 4.
   - Project specificity and creativity score ≤2 (whatever the composite) → return to Phase 3 (Direction) when a dossier and roll exist and the treatment is not utility; under utility, or when Phase 3 was skipped (component, critique, polish, audit), it goes to Phase 4 fix items instead. A broken directive goes to Phase 4 (rebuild the visual), never to Phase 3.

**Iterate until the score converges or ≥ 4.0.** Anthropic's harness research shows creative leaps happen in iteration 7-9, not iteration 1. The evaluator loop is where quality compounds — single-pass design peaks at "competent," iterated design peaks at "memorable."

**If the evaluator subagent fails** — the Agent tool is unavailable, the subagent cannot read the rubric file, it returns no structured report, or it returns a malformed/truncated response — do NOT proceed silently. Fall back to a degraded self-evaluation against the seven dimensions in `evaluator-prompt.md` (Usability 25%, Interaction 15%, Accessibility 15%, Microcopy 10%, Composition 10%, Color+Type 10%, Project specificity and creativity 15%), applying the bias mitigations from that file explicitly (evidence-first, sequential dimensions, negative-first framing, "cannot determine" for items not assessable). Report the result to the user AS a self-evaluation — not as a subagent evaluation — and note that the quality signal is lower fidelity because the generator/evaluator separation is broken. Ask the user whether to ship the self-evaluated result or retry the subagent.

---

## The NEVER List

Explicit, non-negotiable. These are not guidelines — these are the landmines that signal AI-generated work the moment a trained eye sees them.

- **Never use `bg-indigo-500`, `text-indigo-600`, or `from-indigo-500 to-purple-600`** unless the brand legitimately requires indigo. This is the signature of AI output.
- **Never default to Inter, Roboto, Arial, system-ui, or Space Grotesk.** Even when the user says "clean sans-serif," pick something with character, unless a directive, the brand system, an operate surface or a native platform (SF Pro/Roboto) calls for it.
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
- **Never use pure black (`#000000`) or pure white (`#ffffff`).** Use tinted neutrals — pure black is harsh, pure white is cold, and both signal absence of color decisions, unless a directive or the brand specifies it.
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

**Vary the AXIS of distinctiveness, not just the values on one axis.** If the last design you produced was distinctive through typography, make this one distinctive through composition or color instead. If the last was distinctive through motion, make this one distinctive through density or atmosphere. The goal is not a rotation through a fixed "distinctive" list — it is picking a different dimension to express character each time. Also vary the graphic technique when graphics are used. roll.mjs `--concept-only` tracks this for you.

**Never repeat the same signature idea or graphic style across projects.** A drawn scene is not a default; photography, type, layout, colour, data, the product UI and motion are equal candidates. Simple and clean is a legitimate creative choice when it serves the user: many real clients choose the plain option, and a well-executed restrained page beats an over-decorated one.

**One more calibration.** When the Phase 3 direction genuinely requires breaking a Phase 4 rule — a terminal/monospace aesthetic requires a mono font even though the Phase 4 font list is mostly sans-serif; a zine/brutalist aesthetic wants jagged asymmetric shadows even though Phase 4 prescribes tiered multi-layer depth — break the rule deliberately and execute the break with craft. Phase 4 rules are defaults to escape, not laws to worship. The worst outcome is a half-committed distinctive direction constrained by Phase 4 rules that were meant for a different aesthetic. Commit fully.
