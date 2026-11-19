---
name: design
description: 'Design process: UX and usability first, then fit to the client''s real content, then a project-specific look with none of the AI-made tells (indigo, Inter, centred hero + 3 cards, cream + serif, mono eyebrow labels, "Build the future of X"). Ships the feel layer: every control answers hover, press and focus, changes are explained by small tiered transitions, one authored interaction, no scroll fade-ups or idle loops; verified by driving the page in a browser (scripts/probe.mjs). Use when generating, building, improving, polishing, critiquing or evaluating any UI or frontend, or when asked for microinteractions, transitions or polish. Phases: understand → UX (Nielsen) → direction → execute with interaction layer → graphics → polish and tell sweep → feel pass → external evaluator. Keywords: UI, UX, landing page, dashboard, not AI slop, microinteractions, design review. For a brand-new page that should differ between runs, prefer `vary`; use `design` for critique, audits, polish, or by name.'
user-invocable: true
argument-hint: "[target description]"
---

# Design Excellence

Left alone, Claude's design output collapses to the centre of its training data: indigo, Inter, a centred hero over three cards, `rounded-2xl`, "Build the future of X". This skill is the counterforce. Priority order: UX and usability first (the user finishes their task, on a phone, with assistive tech), then fit to the client's real content, then a look of its own. Running through all three is **feel**: every build ships the interaction layer and is judged by using it, not by looking at it. Each phase has a gate, and the output is graded by a separate skeptical evaluator, never by the builder.

## The Process

Each phase has a gate. Do not skip gates.

```
Phase 1:  UNDERSTAND  → purpose, users, primary task, existing system, constraints
           operate surface (app screen, admin, settings, dashboard, tool)? → the Operate surfaces checklist is mandatory
Phase 2:  ARCHITECT   → apply UX principles with priority ordering
Phase 3:  DIRECTION   → dossier, concept, the one signature idea
Phase 3b: SPEC        → design spec: tokens and every piece of chrome decided from the concept, before code
Phase 4:  EXECUTE     → craft numbers, not defaults; the interaction layer (references/microinteractions.md)
Phase 4b: GRAPHICS    → graphics check; design:graphics when the page needs custom art
Phase 5:  POLISH      → details that separate ship from shipped; the five-second tell sweep
Phase 5b: FEEL        → drive the page in a browser; scripts/probe.mjs has no FAIL
Phase 6:  EVALUATE    → separate subagent grades the output, by using it
```

## Operate surfaces — the mandatory checklist

An operate surface is a screen someone works in rather than one that persuades them: an app screen, admin, settings, dashboard, table, editor, extension popup or internal tool. It is usually in extend mode (Phase 3 skipped), and that is exactly where builds come out flat: few icons, every option shown at once, menus that are tiny text lists. On an operate surface this checklist is the Phase 4 brief, and the evaluator scores it as O1-O5.

- **O1 Icons.** Find the project's icon set first (an icons module, or lucide, heroicons, phosphor, tabler or material-symbols in the manifest); with none, add one standard library (Lucide). Every nav item, primary and row action, status and empty state gets an icon beside its label: one set, one stroke, one size per context (16px in rows and menus, 20px in nav). Icon-only only for close, more, search and in-table edit, each with `aria-label` and a tooltip. Never emoji.
- **O2 Progressive disclosure.** The first view shows the primary task and whatever needs action now; nothing else competes. Per region: one primary button and at most two secondary; the rest goes into a `⋯` overflow menu (per row on tables). Advanced or rarely changed settings collapse under a labelled disclosure; details open in a drawer, side panel or expandable row, not a page of fields; long forms group into titled sections. Destructive actions sit last in their menu and confirm.
- **O3 Menus and popovers.** Never a tiny text list. Items are 32-36px tall on desktop and 44px on touch, the menu at least 180px wide and wide enough that no label wraps, 4-6px container padding and 8-12px item padding. Each item gets an icon and a label, with a shortcut or hint right-aligned when there is one. Groups are separated by a divider or a small group label; the selected item carries a check; the destructive item is last, separated, in the danger colour. The menu is anchored to its trigger, flips at viewport edges, closes on Esc and outside click, moves with the arrow keys and returns focus to the trigger. On a phone, a menu of more than 5 items or anything holding a form becomes a bottom sheet.
- **O4 States.** Loading uses a skeleton shaped like the content (a spinner only inside a button); empty has an icon, one line and the action that fills it; an error says what happened and offers a retry; a disabled control says why (tooltip or helper text); a save confirms where the eye already is.
- **O5 Structure and density.** The page header is title, one line of context and the primary action at the right. Tables have a sticky header, right-aligned numbers, row hover and a visible selected state; related controls are grouped on the 8pt grid; the existing components are reused, and a menu, drawer or disclosure the repo lacks is built once as a shared component.

**Gate:** for each region, write which actions are visible and which sit behind disclosure, and name the icon set and the sizes used.

---

## Orchestration: who checks what, on which model

Review is done by subagents, never by the builder grading itself, and each job runs on the cheapest model that does it well. Mechanical checks are scripts; checklist work goes to Haiku; rubric judgement to Sonnet; taste calls to Opus.

| Job | Phase | Runs as | Gets (paths, not pasted content) | Returns |
|---|---|---|---|---|
| Probe, fold check, font draw | 3b, 5, 5b | script, no model | page path | PASS/FAIL rows |
| Idea check (creative director) | 3 | subagent, `model: "opus"` | dossier, concepts | a score per concept, ≤150 words |
| Spec sameness review | 3b gate | subagent, `model: "sonnet"` | design spec, dossier | chrome rows still at the template default, ≤200 words |
| Feel driver | 5b | subagent, `model: "haiku"` | page path, `microinteractions.md` §9 checklist, probe command | dead spots, rough transitions, choreography failures, each with what it did and saw, ≤250 words, screenshot paths |
| Tell sweep | 5 | subagent, `model: "haiku"` | screenshots, `anti-patterns.md` T0-T27 | each tell found with its element, ≤200 words |
| Whole-page check | 4c | subagent, `model: "sonnet"` | full-page screenshots, spec section plan | per-section findings |
| Evaluator | 6 | subagent, `model: "sonnet"` | `evaluator-prompt.md`, page, probe output, spec | the structured report |
| Final harsh review | after SHIP, flagship work only | subagent, `model: "opus"` | page, brief | five fixes |

- Spawn the feel driver, tell sweep and whole-page check **in parallel** once the build exists; fix from the merged list, then run the evaluator once.
- Every subagent prompt ends with its return shape and word limit; screenshots at `deviceScaleFactor: 1`; pass file paths, never page source or images inline.
- Re-run only the checks whose inputs changed. A second evaluator round happens only when the first misses the SHIP gate.
- **Running as a worker** (a subagent building one task for `/flow:next` or another orchestrator): build, run the scripts (probe, fold check) and fix their FAIL rows, then stop. Spawn no evaluator or other review job and never review your own work, not even "code-only": your caller runs [Review mode](#review-mode) on the served page. End the report with how to serve the page (command and URL, or the file path) and the probe outdir.

---

## Review mode

`design:design review <url|path> [--record <path>]` reviews a page someone else built (an orchestrator after a worker's task, or a user asking for a design review). It never edits the page and never reviews from code alone.

1. **Serve it.** The target must open in a browser: a URL that answers, or a static file opened as `file://`. If nothing is serving, start the project's dev server (the `run` skill finds it) and wait for it to answer. No page, no review: say so and stop.
2. **Probe.** `node <this skill's directory>/scripts/probe.mjs <url> <outdir>`; with `--record`, the outdir is `<record dir>/<ID>-probe` beside the record.
3. **Drive and sweep, in parallel:** the feel driver, the tell sweep and, for a whole page, the whole-page check (see Orchestration), each handed the URL and the probe screenshots.
4. **Evaluate.** Run Phase 6 exactly: `evaluator-prompt.md` verbatim, `model: "sonnet"`, given the URL, the probe output, the drive notes and the brief or task description; on an operate surface say so, so it scores O1-O5.
5. **Record.** Write the record file (or print it without `--record`):

```
Verdict: SHIP | REVISE
Probe: <outdir>
Evaluator: composite X.XX, lowest <dimension> X.X
Fixes:
- <fix, element, why> (top fixes first, from the probe FAIL/WARN rows, the drive and the evaluator)
```

SHIP is the Phase 6 gate (composite and floors) with no probe FAIL row; anything else is REVISE. The caller sends the fixes back to the builder and runs review mode again on the fixed page.

---

## Phase 1 — Understand

Before writing any code, answer these in your head (or out loud if the scope is large):

1. **Purpose and users.** What problem does this interface solve? Who uses it, on what device, in what mood? What is the single thing they need to do most (the primary task)?
2. **Existing system (extend mode).** If the repo already has a visual system (DESIGN.md, a token or theme file, styled shared components, or existing pages that share one palette and type), read `../vary/references/extend-mode.md` and follow it for everything below: it decides what still rolls, and shared files stay append-only. This holds for a whole new page in an existing site too, not only for a section. A component, section, critique, polish or audit inside an existing surface: read the surface, write no dossier and run no roll; skip Phase 3 and carry on at Phase 4. On an operate surface the [Operate surfaces checklist](#operate-surfaces--the-mandatory-checklist) is the Phase 4 brief.
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
- **H8 Minimalism via progressive disclosure.** Not sparse — purposeful. Every element earns its place; advanced options sit behind a disclosure (on an operate surface, O2 sets the rules).
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
   - Native platform (ios/android): call the Skill tool with "design:mobile-design" for the platform layer (skip quietly when absent); evidence is device screenshots.

   Simple and clean is a legitimate choice when the client asks for it or the surface is a dense tool; for a business, brand or event homepage, clean is the floor, not the goal: give it one memorable idea and the small custom details that make it this client's own. Usable and uninspired is a failure too.

Before running the roll, run the idea check in `../vary/references/concepts.md` §3b: a fresh creative-director subagent scores every concept, and only concepts at 7 or above go to the roll.

**Genericity probe.** Before the gate, name any part of the direction that a different client's brief would also produce, then ask: would a similar brief land here? revise that part and say why.

Credit: adapted from anthropics/skills skills/frontend-design/SKILL.md @ dbd4588 (Apache-2.0).

**Gate:** You can state the concept in one sentence, cite the three facts it rests on, and name the signature idea and where it appears. If you cannot, you will default to AI slop.

---

## Phase 3b — Design spec

Before any page code, write the design spec: load [references/design-spec.md](references/design-spec.md) and fill it into `.vary/design-spec.md` (or `DESIGN.md` in a repo that keeps one). It holds the tokens, the voice, every piece of chrome (top bar, footer, actions, section heads, containers, cards, fields, feedback, the signature interaction), the section plan and the interaction inventory.

The reason is sameness. Left undecided, the chrome comes out the same on every project whatever the theme: wordmark left and links right with a bordered button at the far edge, a big h2 left with its lede right, one centred column, brand-and-columns footer. For each chrome item the spec names that template default and says what this build does instead and which fact or artefact it comes from. Usability keeps the placement conventions (brand top-left, nav at the top, menu on phone); the concept decides what the chrome carries, its material, geometry and behaviour.

In extend mode the existing system is the spec: read it, add only what the new surface needs, and never restyle shared chrome.

Then a fresh Sonnet subagent reads the spec and the dossier and names any chrome row still at the template default (see Orchestration); revise those rows.

**Gate:** every chrome row has its Default / This build / States lines, the `:root` token block is complete, the section plan and interaction inventory are filled, and the sameness check (§7) names five shared-by-default things and how each differs here or why it stays.

---

## Phase 4 — Execute

**Build from the spec.** Copy its token block into `:root` verbatim, build the chrome as specified, then the sections in its plan order. When the build needs a decision the spec lacks, write it into the spec first. (Inside an existing surface with no spec phase, write a short section plan instead: with (1) the section's job for the user, (2) whether the concept's idea helps that job and how (the care tag on each product, the theme in the speaker specimens, the data story in the main chart), or "not here" when it would only decorate, (3) which content lives here (each piece of content in exactly one section), and (4) its layout skeleton, different from its neighbours. A section that is only the category's default cards with nothing of this client in it gets one specific detail. Build from this plan.)

This is where craft numbers matter more than principles. The difference between "engineer-built" and "designer-quality" UI lives in specific values experts apply automatically.

**The NEVER-defaults — override all of these with intent:**

| Default | What Claude does | What you do instead |
|---------|------------------|---------------------|
| Font | Inter, Roboto, Arial, system-ui, Space Grotesk, or the next layer of favourites once those are banned | Unless the brand, a directive or the platform fixes the face, run `node <this skill's directory>/scripts/font-draw.mjs --scripts <content scripts, e.g. latin,latin-ext> [--source google]` and choose from its shortlist by fit to the concept's trade, era or lettering heritage; say why in one line. Never reach past the shortlist for a face from memory (memory is where the convergence lives). At least 5 weights unless it is a display-only face; verify the content language's glyphs render. Mono only for literal code, commands or tabular data, never for labels. |
| Primary color | `bg-indigo-500`, purple, `from-indigo-500 to-purple-600` | Any hue EXCEPT indigo/purple, unless the brand legitimately requires it. Use OKLCH for definition. |
| Background | Pure white / `bg-gray-50` | Tinted neutral at chroma 0.005-0.01 in the brand hue, OR a material texture that the concept's artefact actually has (paper fibre, wood grain, brushed metal, blueprint grid). |
| Layout | Centered everything, 3-column feature grid, Hero→Features→CTA invariant | Asymmetric composition with intentional tension. Start from content, not template. |
| Radius | `rounded-2xl` on everything uniformly | Tiered scale: inputs 4px, buttons 6-8px, cards 10-12px, `rounded-full` reserved for avatars/pills |
| Shadow | `shadow-lg` on every card | Tiered elevation. Multi-layer shadows with doubling formula. Match shadow hue to background hue (never pure black). |
| Motion | Dead controls, or AOS fade-in-up on everything, `transition: all .3s`, hover lift on every card, bounce easing | Every control answers hover, press and focus; changes explained in place; tiered `--dur-*`/`--ease-*` tokens; one authored moment on a rare action; nothing moves on scroll or at rest. |
| Copy | "Build the future of X," "Scale without limits," "Empower your team" | Concrete claims with specific verbs, numbers, outcomes. "Cut review time from 3 hours to 20 minutes." |

**Craft numbers.** Load [references/build-rules.md](references/build-rules.md) §1 now: the typography, colour, spacing and depth numbers (line-height and tracking per size, OKLCH and tinted neutrals, the 8pt grid and internal ≤ external, layered shadows). They are what separates designer-quality from engineer-built.

**The interaction layer (every build with a control on it).** Load [references/microinteractions.md](references/microinteractions.md) now; it is not optional. It holds the motion tokens, the frequency ladder, the interaction floor (a recipe and the required states for each control type), browser-surface finishing, the signature interaction, page-load and scroll rules, and the motion that reads as AI-made. Then:

- **Inventory first.** The interaction inventory lives in the spec (§6; for a component, at the top of the file): every control type on the page → its states (default, hover, focus-visible, active, disabled, loading, error, success, empty, as they apply) → what moves or changes, with which token. Every value that changes (price, count, total, step, availability) gets a row too: how the user notices the change.
- **Tokens, not literals.** Durations and curves come from the `--ease-*` and `--dur-*` tokens; exits faster than enters; one duration for everything is a tell.
- **Answer every touch.** Hover (pointer only, inside `@media (hover: hover)`), press (`:active`, scale .96-.98 on buttons), a designed `:focus-visible` ring, and in-place acknowledgement of actions (Added, Copied, Booked; a count that bumps; a toast in an `aria-live` region). Values that change crossfade or slide, in tabular figures. Overlays grow from their trigger. Steps enter from the direction of travel and move focus.
- **One authored moment.** One rare action gets a small signature interaction drawn from the client's trade (microinteractions.md §5). Never on hover, never on scroll.
- **Quiet everywhere else.** At most one CSS-only load moment on the first screen; no scroll-reveal of body content; no idle loops; transform and opacity only (the `grid-template-rows` disclosure is the one sanctioned exception); never animate keyboard-triggered actions; reduced motion ships with the animation.
- When the page needs gestures, drag, springs, shared-element or route transitions, call the Skill tool with "design:ui-animation" for those parts.

**Gate:** Your output has explicit typography choices (by name), an explicit color approach (OKLCH values or named palette), a spacing scale, the motion tokens, an interaction inventory with every control type and every changing value covered, the signature interaction named, and at least three designed states (not just happy path).

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

## Phase 4c — Whole-page check

**Whole-page check (before the critic).** Spawn a FRESH subagent (Agent tool, `model: "sonnet"`) with the full-page screenshots at desktop and phone, `.vary/design-spec.md` (its section plan) and the one-sentence concept. It scrolls top to bottom and reports, per section: (1) **repetition**: the same content shown more than once (a lineup in the hero, the programme and the speaker list; a list of counters as map, legend and table) or the same motif stamped on elements that do not need it (download buttons, weekday bars, every card); (2) **dead sections**: a section where the page falls back to the category's default cards with nothing of this client in it; (3) a **stock metaphor** that has replaced the most subject-specific element. Fix in that order: cut repetition first (each piece of content appears once, in the section whose job it is; a motif stays where it does a job), then give the weakest dead section one specific detail, then restore the subject-specific element. Re-shoot once. Usability fixes win any conflict.

---

## Phase 5 — Polish

Polish is the last step, not the first. Do not polish work that is not functionally complete. An expert polishing a design does not walk through a labeled checklist — they scan with a trained eye for specific failure modes that an untrained eye misses. Transfer that trained eye by interrogating the design with these questions, not by marching through a sequence; [references/build-rules.md](references/build-rules.md) §2 holds what each question catches. Read it on the first polish pass.

**Ask yourself: what would someone who has seen a thousand generated pages clock in five seconds?**

**Ask yourself: where does mathematical alignment lie to me?**

**Ask yourself: can a user glancing at every button label for 0.5 seconds tell what will happen?**

**Ask yourself: what happens when a user never touches a mouse?**

**Ask yourself: for every interactive element, which of the nine states can I actually describe right now?** Default, hover, focus-visible, active, disabled, loading, error, success, empty — can you picture each one concretely for every button, input, and link on the screen? Any state you cannot immediately describe does not exist. Missing states are not edge cases; they are core flows the first-pass generation skipped because the happy path was sufficient. This is the #1 source of "it looked good in the mockup but broke in production."

**Ask yourself: what does this look like in the hostile conditions users actually experience?**

**Craft-bug rules (Polish checklist).** Content is visible with no JS-triggered reveal (an element may animate in only from a visible state); no full-viewport overlay or backdrop left on the page; nothing in the hero is cropped by the nav or the viewport edge; every dial, axis or scale is monotonic and labelled with real values; every callout leader ends on its object.

**Blocking craft fails (all treatments).**

- **Headline on the first screen.** Persuade and experience: a real HTML `<h1>` (business name or the promise), a one-line value proposition and the primary action (link or button with visible text); never only svg `<text>`, never omitted. Operate and read: a visible `<h1>` or page title.
- **Mood fit.** State the audience's mood need (children: bright, safe, daytime; bereavement: calm, quiet, dignified; B2B lab: precise, trustworthy); a concept that breaks it is re-rolled with `--lock concept=<id>` before building further.
- **No collisions, no clipped text.** Every label, callout and text is fully visible at both viewports: no overlap with objects or other labels.
- **Page overflow, meta-copy, duplicate content.** Nothing wider than the viewport at 1440 or 390 unless inside its own scroll container; no designer or scaffold language in visible text (exempt with `data-meta-ok`); each fact appears once in the body (the footer may repeat contact details); intentional repeats are marked `data-repeat-ok`.
- **Phone width, native and honest.** `../vary/references/build-craft.md` §6 items 17-28 (show the subject at hero scale, the idea where it does a job with no repetition, time-aware content, place questions get a map, first screen answers the top question, products shown, brand objects carry real content, phone nav behind a menu button past three links): nothing scrolls sideways or clips at 390px; no designer notes or design keys on the page; photos carry a photography page; app screens use native controls and dashboards plot only real data.

Run the fold check as `node <VARY>/scripts/fold-check.mjs <page> --mode <m> --treatment <t>`, where `<t>` is the treatment the contract names. The rows collisions, clipped-text, hidden-content, stray-overlay, duplicate-content, page-overflow, meta-copy and headline-on-fold (operate/read: title-on-fold) must be PASS; the time budget never excuses them. Rows printed `[INFO]` are not gated. After fixes, re-run `check.mjs` and the fold check and refresh the evaluator JSON before Phase 6. User DIRECTIVES outrank every bar here: a directive such as "no illustrations" or "plain black and white" is never answered with added art.

**Gate:** You cannot answer "I'm not sure" to any of the questions above and consider the design polished. If you can't answer, you have not actually run the check.

The same file holds the classical, accessibility and performance anti-patterns; on a high-stakes design (landing page, flagship feature, public marketing, customer-facing flow) run its pre-ship checklists too.

---

## Phase 5b — Feel

A screenshot cannot show whether a page feels built. Drive it.

1. **Probe.** Run `node <this skill's directory>/scripts/probe.mjs <page> <outdir>` (Chromium and Playwright; set `NODE_PATH` to the folder holding `playwright` if it is not found). It hovers, presses and tabs every control, scrolls the page, reloads under reduced motion, and prints PASS/FAIL/WARN rows: hover, press and focus coverage, `transition: all`, layout-property transitions, content hidden after load, scroll-reveal, idle loops, hover on non-clickable blocks, console errors, phone overflow, slop copy, gradient text, emoji icons, single-duration timing, default fonts, indigo actions, eyebrow pill, em-dash density. Every FAIL is fixed; every WARN is fixed or gets one line of reason.
2. **Drive the primary task** (the feel driver: a fresh Haiku subagent, see Orchestration, covering steps 2-5 and returning what it did and saw) with Playwright at 1440 and 390: hover each control, press and hold, release outside, tab through, run the task end to end, trigger each error and the success. Note any control or changing value with no feedback (a dead spot) and fix it.
3. **Watch it slowed.** Set CDP `Animation.setPlaybackRate` to 0.1 and screenshot mid-transition for the signature interaction and one per-task interaction: no jump at start or end, no two things moving on different curves, nothing entering from the wrong origin.
4. **Interrupt it.** Hover in and out fast, toggle twice fast, double-click the main action: transitions retarget, nothing double-submits.
5. **Reduced motion.** Repeat step 2 with `reducedMotion: 'reduce'`: every state change still visible, nothing travelling.
6. **Against the spec.** Hold the screenshots next to `.vary/design-spec.md`: each chrome item matches its "This build" line (a top bar that came out as the template is a FAIL whatever the probe says), every decision the spec states is visible in the CSS (a measured quarter of stated design rationales in generated UI never reach the build), each changing value has its inventory row, and `token-discipline` shows no literal values bypassing the tokens.

**Gate:** `probe.mjs` exits 0, each WARN has a fix or a reason, and you can list each control type with what it does on hover, press, focus and success. Pass the probe output and your drive notes to Phase 6.

---

## Phase 6 — Evaluate

**Do NOT load [`references/evaluation-rubric.md`](references/evaluation-rubric.md) yourself.** It belongs to the evaluator: if its criteria shape the build, the grade stops measuring anything. Read only `evaluator-prompt.md`.

**This phase is mandatory for any design the user will actually ship.** It is skippable only for throwaway prototypes or sketches where the user explicitly said "just something quick."

**To run the evaluator:**

1. **Collect the design output.** If it is a file you created, note the absolute file path. If it is a rendered component in a conversation, save it to a temp file first so you can pass a path rather than a massive string.
2. **Read [`evaluator-prompt.md`](evaluator-prompt.md)** — this is the complete prompt template for the subagent. Do not paraphrase it; you will copy it verbatim.
3. **Spawn a subagent** using the Agent tool with `subagent_type: "general-purpose"`, `model: "sonnet"`, and `mode: "bypassPermissions"` (so the subagent can read the rubric file without permission prompts). The task prompt is: the full content of `evaluator-prompt.md`, followed by a clear delimiter (`\n\n---\n\nDESIGN TO EVALUATE:\n\n`), followed by the absolute file path(s) of the design output with an explicit instruction that the subagent should Read each file in full. Also pass `.vary/dossier.json` when it exists, the page screenshots, `assets/art/GRAPHICS.md` when graphics were made, the fold-check output produced with `--treatment <t>`, and the `probe.mjs` output and drive notes from Phase 5b. The evaluator scores Interaction and feel by driving the page itself. For short designs (<200 lines), you may inline the source instead of passing a path.
4. **The evaluator returns a structured report** with: per-dimension scores (Usability, Interaction and feel, Accessibility, Microcopy, Composition, Color+Type, Project specificity and creativity), a weighted composite, specific violations with severity, and prioritized fixes.
5. **Iterate based on score:**
   - Composite ≥ 4.0 AND Usability, Interaction and feel, and Accessibility each ≥ 3.5 AND no dimension ≤ 2 → SHIP. The report's "Lowest dimension" line is the floor check: a strong composite does not hide a weak accessibility score.
   - Composite ≥ 4.0 but a floor missed → apply the top fixes for the lowest dimension and re-spawn a NEW evaluator.
   - Composite 3.0-3.9 (C) → apply the top 3 fixes and re-spawn a NEW evaluator (fresh context, no memory of prior iteration).
   - Composite < 3.0 (D/F) → return to Phase 2 or Phase 4 depending on which dimensions scored lowest. Usability/Interaction/Accessibility failures point back to Phase 2. Composition/Color/Typography failures point back to Phase 4.
   - Project specificity and creativity score ≤2 (whatever the composite) → return to Phase 3 (Direction) when a dossier and roll exist and the treatment is not utility; under utility, or when Phase 3 was skipped (component, critique, polish, audit), it goes to Phase 4 fix items instead. A broken directive goes to Phase 4 (rebuild the visual), never to Phase 3.

Credit: adapted from garrytan/gstack plan-design-review/sections/review-sections.md.tmpl @ 5b9b837 (MIT).

**Iterate until the work clears the SHIP gate (composite and floors) or the score stops moving.** Quality compounds in the evaluator loop, not in the first pass.

**If the evaluator subagent fails** (no Agent tool, it cannot read the rubric, or the report is missing or malformed), retry once with a fresh subagent. If it fails again, say "evaluator not run" and why; never claim SHIP. A self-evaluation against `evaluator-prompt.md`'s seven dimensions may be offered only when the user asks for one, labelled as a self-evaluation.

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
- **Never animate `width`, `height`, `top`, `left`, `margin`, `padding`, or `font-size`.** Use `transform` and `opacity` only (the `grid-template-rows` disclosure is the one exception).
- **Never ship a control that does not answer touch.** Every button, link, card link, input, toggle and tab changes on hover (pointer devices), on press and on keyboard focus; every action is acknowledged in place.
- **Never ship the motion tells:** fade-up on scroll for body content, staggered card reveals, hover lift on things that are not clickable, `transition: all`, one duration for everything, floating blobs, animated gradients, glow pulses, shimmer sweeps, typewriter or rotating headlines, count-up numbers, custom cursors, magnetic or tilting elements, parallax, bounce on UI, loops that never stop.
- **Never use placeholder text as the only label.** It disappears on focus and fails WCAG.
- **Never ship a form with submit-only validation.** Validate on blur, show success checkmarks on correct fields.
- **Never present only the happy path.** Empty state, loading state, error state, disabled state, long-content state — all must exist.
- **Never use pure black (`#000000`) or pure white (`#ffffff`).** Use tinted neutrals — pure black is harsh, pure white is cold, and both signal absence of color decisions, unless a directive or the brand specifies it.
- **Never let your evaluator be yourself.** Spawn a separate subagent. Self-praise is the default.

---

## Closing Directive — Against Pattern Collapse

Right before you generate: name what the typical AI-made version of this would look like (font, colour, layout, easing, copy tone), choose something materially different that still serves the brief, and commit to it fully. Vary the axis of distinctiveness between projects, never repeat a signature idea, and break a Phase 4 rule only when the direction needs it, saying why. The full procedure is [references/build-rules.md](references/build-rules.md) §3.
