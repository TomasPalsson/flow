---
name: vary
description: 'Design frontend UI that is specific to THIS project and different every run: read the project into a fact dossier, write grounded concepts, and let an external roll (scripts/roll.mjs) assign a concept, technique, visual world, skeleton, palette seed and fonts; then build the concept''s treatment (the client''s photography, product UI, typography, a data visual, a pattern, a drawn scene or a plain, usable layout), usability first. Custom graphics come from the design:graphics skill. A mechanical craft floor (scripts/check.mjs) and a separate evaluator subagent judge distinctiveness and contract-keeping. Use WHENEVER building, redesigning, mocking up or restyling any UI (landing page, marketing site, dashboard, docs, portfolio, app screen, component set, email) and whenever the user says make it look good, not generic, not AI slop, something different, surprise me, or complains that designs look the same. Also for "another direction", "re-roll", "safer", "bolder". Not for backend-only work or pure copy edits.'
user-invocable: true
argument-hint: "[brief] [--mode persuade|operate|read|experience] [--reroll] [--safer|--bolder|--canon]"
---

# vary — design that is assigned, not chosen

Claude's design output collapses to a mode: indigo, Inter, centred hero, three cards. Told to avoid those, it collapses to the next mode: cream + serif + terracotta, or near-black + one neon, Space Grotesk, bento + glass. The cause is not a lack of ideas. The model derives seven varied directions and then argmax-picks the same one every time; asking it to "choose differently" reverted in 27 of 30 measured runs. Naming things to avoid makes it worse: a named font or hex gets *more* activation, not less.

Four things fix this, and this skill is built around them:

1. **An external roll assigns the direction.** `scripts/roll.mjs` picks concept → signature device → world → skeleton → colour strategy → palette seed → fonts, each conditioned on the last, from the project's concepts and the catalogs in `data/`. Claude executes the assignment. It does not pick from a menu.
2. **Variety must move on two axes.** A new palette on the same centred-hero skeleton is the same design. The roll moves the skeleton (archetype) and the lineage (world) together; skin follows.
3. **The roll picks among grounded options.** Concepts come from the project's own facts, and worlds are filtered by its sector. Randomness then buys variety without buying irrelevance.
4. **The signature is the one idea that makes this project recognisable.** Every build carries one, taken from the project's facts or assets: type, layout, colour, the client's own photography, the real product UI, data, motion or graphics. A palette and fonts over generic blocks is not a design.

Priority, always: **usability first** (the visitor completes the task, finds things, reads and acts, on a phone, with a keyboard), **then a creative direction specific to this project**. No look is the default and a drawing is one option among many. Plain is right for dense tools or when the client asks; a business, brand or event homepage needs one memorable idea and the small custom details that make it this client's own. Usable and uninspired is a failure too.

Then: commit fully, guard later. Craft rules are loaded only *after* the contract is written, because guardrails mixed into the brief measurably hedge the result. Review is done by a separate identity auditing the build against its own contract, because self-review rubber-stamps.

(The measurements above come from Impeccable's instrumented v4 campaign, impeccable.style/research, and from NeurIPS 2025 work on ironic negation, arXiv 2511.12381. The research trail for this skill is in its forge workspace.)

---

## Step 0 — Read the project, then the surface

Load [`references/dossier.md`](references/dossier.md) and write `.vary/dossier.json` before anything else. Facts come from the repo, the client's live site and the assets given. Nothing is invented.

Then settle these in one short block (write them; they feed the roll):

- **Mode** of *this surface*: `persuade` (visitor decides and acts: landing, pricing, campaign), `operate` (completes a task: app, dashboard, settings, forms, checkout), `read` (understands: docs, articles, changelog), `experience` (is inside the work: portfolio, gallery). A dev tool's landing page is persuade; a fashion house's docs are read. Mode gates how bold the roll may be. Operate and read surfaces get quiet worlds and conventional skeletons; their distinctiveness lives in details.
- **Platform**: `web`, `ios`, `android`. Phones exclude pointer-dependent skeletons. ios/android: call the Skill tool with "design:mobile-design" for the platform layer (skip quietly when absent). The contract goes as a `/* ... */` block at the top of the root component. Evidence is device screenshots; fold-check does not apply.
- **Locks** — anything the user or the repo has already decided: brand hex (`--lock palette=#…`), a required font, required scripts (`--scripts latin,cyrillic`), no webfonts (email, React Native → `--no-webfonts`), longevity (`--longevity campaign` allows fast-decaying looks). A brief that pins an aesthetic ("make it Bauhaus", "keep our brand") beats the roll: `--lock world=bauhaus`.
- **Directives**: anything the user says about the look ("no illustrations", "black and white", "use our photos", "minimal") goes verbatim into `dossier.directives` with the locks it implies. Directives outrank this skill's defaults and gates; only truth, accessibility and usability outrank them.

  | Directive | Locks / effect |
  |---|---|
  | no illustrations | `treatment=typography`, or photography/product-ui if assets exist; do not call the graphics skill |
  | black and white | `strategy=ink-on-paper` and no accent (build-craft tint rules suspended) |
  | Swiss | `world=swiss-international` |
  | use our photos | `treatment=photography` |
  | minimal, quiet, luxurious | `treatment=typography`, or `photography` when photos exist (dead-zone and depth are INFO there); devices `photo-direction` or `typographic` only (no annotated photos, leader lines, frames or ornament) |
  | keep our brand | extend mode |

- **Precedence** (the one place it is written; both evaluators repeat it). When rules collide, the higher item wins: 1. Truth: no invented facts. 2. Accessibility and usability: contrast, keyboard, focus, reduced motion, text equivalents, findability, task completion. 3. User directives (`dossier.directives`). 4. Existing brand or design system (extend mode). 5. Platform conventions (ios/android; operate Jakob's law). 6. The rolled contract. 7. Skill defaults.
- **Existing design system?** If the repo has `DESIGN.md`, a token file, a Tailwind theme with custom colours, or styled shared components, this is **extend mode**: read [`references/extend-mode.md`](references/extend-mode.md) and follow it instead of Step 1. A component or section inside an established surface always inherits that surface. Never turn a local addition into a new identity.
- **Sector**: one id from the controlled list, taken from the dossier's `sector`. It filters the world pool. Pick the one a customer would file the business under (a pizzeria with a bar is `food-drink`). When torn between two, decide the tie after Step 0b (take the one whose worlds list fits the concept hints better), note the choice in the dossier, and write the final sector into `dossier.sector`, which must equal `--sector`.
- **Multi-surface clients**: the roll's mode is the mode of the surface built first (usually the home or landing page, so `persuade`). Later surfaces reuse the contract and take their own archetype.
- **Scene sentence**: who uses this, where, under what light. This decides light or dark, not the category (`--scene light|dark` once decided).

Ask the user at most one round of two or three questions, and only for facts that change the work (the real proof/content available, audience, what must not change). Never ask for CSS values or an aesthetic lane.

## Step 0b — Concepts

Read [`references/concepts.md`](references/concepts.md) and write 4-7 concepts to `.vary/concepts.json`. Each concept takes a different angle on the business: a different audience moment, half of the trade, time of day or artefact. Each cites at least 3 fact ids, names the trade artefact it borrows, re-skins the functional objects (cart, confirmation, nav), names 2-3 `world_hints` (the one permitted read of `data/worlds.json`: take ids, names, sectors and `avoid_sectors` only, never use it to choose the final world), and offers 2-3 signature devices from the technique list. Each concept names a `treatment` (pattern, photography, product-ui, typography, data-visual, utility, scene). The concepts spread across at least three different treatments and none is the default; a plain, very usable direction is a legitimate concept (real clients often pick it). When the dossier has usable photos or a product UI, at least one concept uses `photography` or `product-ui`. Concepts must differ in treatment and composition, not only in subject (`references/concepts.md` §3). Write them all at full strength: the roll, not you, picks one.

Then run the idea check in [`references/concepts.md`](references/concepts.md) §3b: a fresh creative-director subagent scores every concept, and only concepts at 7 or above go to the roll.

## Step 1 — Roll

```bash
node <VARY>/scripts/roll.mjs --mode <mode> --platform <platform> [--scene light|dark] \
  --dossier .vary/dossier.json --concepts .vary/concepts.json --sector <id> \
  [--scripts latin,cyrillic] [--lock palette=#hex] [--lock world=<id>] [--no-webfonts] \
  [--longevity long|campaign] --project <repo-root>
```

`<VARY>` is this skill's own directory: the absolute path on the "Base directory for this skill" line Claude Code printed when this skill loaded (or `${CLAUDE_PLUGIN_ROOT}/skills/vary` when that variable is set). Substitute it literally in every command. **Never search the filesystem (`find`, `ls ~`) for the scripts, and never run a copy under `~/.claude/plugins` or `~/.claude/skills` unless that path IS the base directory.** If `<VARY>/scripts/roll.mjs` is not there, stop and say so. `--project` is required. It points the anti-repeat memory at the repo (last 3 picks per axis demoted there, angles included; last 8 globally), so the same font or world does not come back next session.

**The assignment is unrefusable.** Writing any UI markup, styling or component code before the roll has run and its comment block is pasted into the artifact is a contract violation. Apart from the `world_hints` read in Step 0b, do not read the catalog files to pick something yourself: that is the exact failure this skill exists to remove.

**Re-roll on the model's own initiative only for named grounds**: a `[FAIL]` coherence row that a single-field lock cannot fix; a script the font lacks; the world cannot carry the SIGNATURE DEVICE; or the user vetoes the world for this trade. "This doesn't feel right for the category" is not grounds; that is the argmax talking. The **user** may re-roll freely: `--from <key> --reroll 1` (then 2, 3…). Steering: `--register safer` (slow-decay worlds, quiet strategies) or `--register bolder` (experience-grade worlds) on a re-roll. `--canon` is the standing exit: the category standard, played straight, at full craft; never recommend it, always allow it. After two consecutive re-rolls, ask what quality is missing rather than rolling a third time.

When the **user** rejects a world as wrong for the trade, record it in the dossier's `refuse`. Re-roll with every Step 1 flag repeated plus `--from <key> --lock concept=<id> --reroll n+1`, optionally with `--register safer` (a deliberate quiet bias, so use it only when the user wants calmer): `--lock concept=<id>` keeps the concept and re-deals only the world and device, the right veto when the user rejected the world, not the idea. After two misses, print three previews with the same flags, `--from <key> --lock concept=<id> --reroll n+1`, then `n+2`, `n+3`, each with `--json --no-memory` so previews do not write to the anti-repeat memory, and let the **user** pick. You never pick.

## Step 2 — Contract

Paste the printed `<!-- … -->` block **verbatim** as the first child of `<body>` in the root layout (never inside a slotted child component; some compilers strip those). Then fill the four model-authored lines:

- **SCENE**: the one sentence from Step 0.
- **FIRST VIEWPORT**: what is where, at what scale, where the primary action sits. Derived from the ARCHETYPE plus the CONCEPT; the signature element is visible in it at hero scale (utility: the primary object of the tool), and the first screen announces the concept, not a shop listing.
- **THESIS**: the one idea this surface owns, and the category-default arrangement it refuses. If it reads like a mood ("clean, confident"), it is not decided yet.
- **SIGNATURE GRAPHIC** (the signature element; the contract key keeps this name): what is drawn, shown or set, which FACTS it encodes, how it renders (engine/file), and its three placements.

CONCEPT supplies thesis, materials, the memorable element and the functional reskin. WORLD supplies grammar, skeleton, type and motion. FACTS win every conflict; clarity beats all three.

## Step 3a — Graphics check

Run this before any UI code. Call the graphics skill when the page has at least one of:

1. **Icons**: the nav, categories, features or states need icons and a consistent custom set adds identity or clarity beyond a standard library (a standard library such as Lucide is fine on operate surfaces when it fits).
2. **Explanation**: a process, mechanism, place, route or data the user must understand reads faster drawn (steps, diagram, map, chart form).
3. **States**: empty, error, success or onboarding screens that a small illustration makes friendlier or clearer.
4. **Brand objects**: functional reskin objects that make the site what it is (price tags, coupons, tickets, stamps, labels, cards drawn as the trade's own artefacts).
5. **Imagery**: hero or section imagery when the client has no usable photos or product UI and the concept calls for drawn art (spot illustrations, objects, a pattern, or a scene only when the concept needs one). A business that sells physical things and has no photos gets a drawing of each product.
6. The user asked for illustrations, cartoons, icons or drawings.

Do not call it when: a directive forbids illustrations; the surface is a dense tool (dashboard, admin, docs) where a standard icon library covers the icons; or photos or the product UI already carry the page's character and nothing else needs drawing.

**Character is a job too.** On a persuade or experience page for a business, brand or event, small custom graphics that make the site recognisably this client's are a brand job, not decoration: icons for the facts people scan (care, hours, steps, features), a small drawing per product, service or category, brand objects drawn as the trade's own artefacts, and art where there are no photos. Lean towards calling the graphics skill there; a page with no custom graphics at all must have another clear signature (photography, the product UI, a strong typographic or data idea). Usability still comes first: graphics never replace a label, slow a task or push content below the fold.

When it applies, write `.vary/graphics-brief.md`:

- **Project**: one line; the audience and the mood they need.
- **Page system**: the rolled palette tokens (hex), the fonts, the radius and stroke feel, light or dark, and any directives. On extend mode, say to match the existing art and its bans.
- **Assets**: one row each: `id`, `kind` (icon-set | spot | hero | section | diagram | map | object | pattern), what it shows, which dossier facts it carries, the UX job it does (why the user is better off with it), size and aspect, placement.
- **Output dir**: `assets/art/` by default.

Then invoke `Skill(design:graphics, args: ".vary/graphics-brief.md")`. It returns the files (SVG, or JS modules rendering SVG) and `assets/art/GRAPHICS.md` with each asset's file, size, alt text (or `aria-hidden` for decoration) and placement. Integrate them as returned, with that alt text; do not redraw. The graphics skill runs its own critique, so Step 4b does not repeat it.

Short notes for the other treatments, written to `.vary/visual-brief.md` when useful:

- `photography`: which dossier asset goes where, with the crop rule, sequence and grade. Photos ship unaltered unless the world or a directive says otherwise, and carry the page: no frames or ornament around them, no drawn stand-ins for products. Identifiable real people are never redrawn. Described-but-missing photos become full-size tonal plates (`references/build-craft.md` §6 item 19).
- `product-ui`: rebuild or capture the real workflow with real data and its states (DPR-2 captures; callouts allowed).
- `typography`: a type specimen at hero size with the content language's glyphs, plus the fact the lettering carries.
- `data-visual`: the chart spec, its dossier data and a text equivalent.
- `utility`: the primary object of the tool; skip to Step 3.
- `pattern`: a generated or drawn field that encodes a fact; never a plain decoration.
- `scene`: a drawn scene, only when the concept calls for it; it comes from the graphics skill like any other drawing.

Rules for every treatment:

- **Headline on the first screen.** A real `<h1>` (the name or the promise), a one-line value proposition in the client's real words and the primary action (a link or button with visible text) on persuade and experience; the page title and the primary object on operate and read. Never only svg `<text>`, never omitted.
- **Mood fit.** State the audience's mood need in one line (children: bright, safe, daytime; bereavement: calm, quiet, dignified; B2B lab: precise, trustworthy). If the concept or world breaks it, re-roll with `--lock concept=<id>` before building.
- **No collisions.** Every label, callout and text is fully visible at both viewports, with no overlap.
- **Phone width and no meta copy** as in Step 3 and `build-craft.md` §6.

## Step 3 — Build, fully committed

**Section plan (before any page code).** Write `.vary/section-plan.md`: one row per section, top to bottom, with (1) the section's job for the user, (2) whether the concept's idea helps that job and how (the care tag on each product, the theme in the speaker specimens, the data story in the main chart), or "not here" when it would only decorate, (3) which content lives here (each piece of content in exactly one section), and (4) its layout skeleton, different from its neighbours. A section that is only the category's default cards with nothing of this client in it gets one specific detail. Build from this plan.

Read [`references/build-craft.md`](references/build-craft.md) in full now, not earlier. It holds palette composition from the seed, type loading, motion, states, browser surfaces and the craft floor. It is loaded after the contract on purpose.

While building:

- **Borrow the skeleton, not the clothes.** Structure comes from the ARCHETYPE and the world's GRAMMAR. A committed surface over the category's standard marketing grid is the most common failure and the hardest to see.
- **Full commitment beats a hedged half.** A perfectly executed conventional page beats a half-executed distinctive one; a fully executed distinctive one beats both. Use all the weights of the assigned faces. Let the colour strategy own the page area it claims.
- **One authored motion moment** (the MOTION MOMENT line). Nothing else animates on entrance.
- **Real content.** Content comes from the dossier verbatim (menu, prices, hours, specs, quotes with source). Demo values are flagged as demo. Never invent prices, customers, testimonials, statistics or capabilities.
- **Every control in the world's material** (persuade/experience): nav, buttons, chips, cart and confirmation follow FUNCTIONAL RESKIN. A default underline nav or flat pill button reads as vibe-coded. Operate surfaces keep platform conventions for nav, forms and errors and skin them through tokens.
- **Decorative fields stay off the reading.** Reading, prices and forms sit on a high-contrast field.
- **Usability before flourish.** The primary task is findable in seconds on a phone; navigation, hierarchy and legibility are checked before any decorative choice.
- **Verify glyphs** for the content language (for example þ ð Á Í) by rendering the hero copy; swap or patch a face that fails.
- **Effort clusters where the content matters.** Everything equally detailed means nothing is important.
- When the world's grammar conflicts with a craft-floor rule, the grammar wins on aesthetics and the floor wins on accessibility, states and keyboard.

Build the whole thing, then inspect once in a batched round (desktop and mobile together), fix everything that round shows in one batch, and stop polishing.

## Step 4 — Mechanical check

```bash
node <VARY>/scripts/check.mjs <built files or dir> --json
```

Before running it, check the content by eye: **each fact (price list, hours, address, offer) appears once in the page body**; the footer may repeat contact details only. A primary action may repeat (a donation ask, ticket prices in the hero and the form); mark intentional repeats `data-repeat-ok`, the evaluator audits them. Any other repeated price list is a duplication bug: keep the one with the best container and delete the other.

Craft-bug rules (check by eye and in the screenshots before the gate): content is visible with no JS-triggered reveal (an element may animate in only from a visible state, never from opacity 0 that a script must clear); no full-viewport overlay or backdrop left on the page; nothing in the hero is cropped by the nav or the viewport edge; every dial, axis or scale is monotonic and labelled with real values; every callout leader ends on its object.

Fix every `FAIL` in one batch (contract present, contrast, focus-visible, 9 states, reduced motion, image dimensions, font weights, arbitrary Tailwind values, AI vocabulary and em-dash density, template tells, and the project checks: concept-contract, facts-in-build, and, for scene, pattern and data-visual treatments only, bespoke-graphics, seeded-art, svg-a11y; for any other treatment those three are INFO, not FAIL, and a bespoke-graphics FAIL on a typography, photography, product-ui or utility build is not fixed by adding art). A user directive outranks any check row (precedence item 3): never add an illustration to satisfy a check against a "no illustrations" directive. Never satisfy a check by loosening it. Keep the JSON: the evaluator reads it.

**Whole-page check (before the critic).** Spawn a FRESH subagent (Agent tool, `model: opus`) with the full-page screenshots at desktop and phone, `.vary/section-plan.md` and the one-sentence concept. It scrolls top to bottom and reports, per section: (1) **repetition**: the same content shown more than once (a lineup in the hero, the programme and the speaker list; a list of counters as map, legend and table) or the same motif stamped on elements that do not need it (download buttons, weekday bars, every card); (2) **dead sections**: a section where the page falls back to the category's default cards with nothing of this client in it; (3) a **stock metaphor** that has replaced the most subject-specific element. Fix in that order: cut repetition first (each piece of content appears once, in the section whose job it is; a motif stays where it does a job), then give the weakest dead section one specific detail, then restore the subject-specific element. Re-shoot once. Usability fixes win any conflict.

## Step 4b — Critic before shipping

Spawn a FRESH subagent (Agent tool) with the desktop and phone fold and full-page screenshots, the dossier facts and the contract. It judges the built page on usability first (can the visitor do the main task, find things, read, use it on a phone and by keyboard), then fit to the client and creativity, each 1-10, and returns scores and the 5 highest-impact fixes. It does not compare against any named example site. Graphics already ran their own critique inside `design:graphics`; the page critic only checks how they are placed and whether they earn their place. The lead applies the fixes and re-runs a new critic; stop when the mean is 7.5 or more or after 2 critic rounds, logging open items in NOTES.md. After applying fixes, re-run `check.mjs` and the fold check and refresh the evaluator JSON before Step 5; record the last critic mean in NOTES.md. Critic rounds may be skipped when time is short.

**Blocking craft fails.** Before Step 5 or shipping, these fold-check rows must be PASS: collisions, clipped-text, hidden-content, stray-overlay, duplicate-content, page-overflow (nothing wider than the viewport at 1440 or 390 unless inside its own scroll container), meta-copy (no designer or scaffold language in visible text; exempt with data-meta-ok), headline-on-fold (operate/read: title-on-fold), plus headline-in-scene when the contract's treatment is scene (the check's `BLOCKING:` line lists any that fail). They are cheap to fix and the time budget never excuses them. Coverage, depth and plate-size may ship as logged open items (`NOTES.md`) if time runs out.

## Step 5 — Separate evaluation

Mandatory for anything the user will ship; skippable only when the user said "just something quick".

1. Read [`evaluator-prompt.md`](evaluator-prompt.md) and copy it **verbatim** into a new subagent (`general-purpose`, `model: sonnet`, `mode: bypassPermissions`). Append: the original brief, the absolute paths of the built files, the path of the `check.mjs` JSON, `.vary/dossier.json`, `.vary/graphics-brief.md` and `assets/art/GRAPHICS.md` (only if the graphics check called the graphics skill), plus the page screenshots (`npx agent-browser` or the browser MCP). Screenshots are **required** for persuade and experience (ios/android: device screenshots); without them the evaluator returns RECAPTURE. Optionally append `SIBLINGS:` with the contract blocks of other variants for the same project.
2. The dossier and graphics brief are project evidence, not generator rules. Pass them. Still withhold this SKILL.md, the references, the catalogs, and any of the generating conversation. The evaluator audits the build against its own contract block and tests distinctiveness; feeding it the generator's rules collapses that separation.
3. Dispositions are closed: **SHIP / FIX / REBUILD / RECAPTURE**. FIX gets exactly one batched round, re-checked by the evaluator, not by the builder. REBUILD means a structural promise broke (skeleton, a grammar rule, thesis vs execution): return to Step 3 with the same contract. RECAPTURE means the evidence was bad (contract stripped, no source): fix the evidence, not the design.
4. The builder never marks its own SHIP. If no subagent tool exists, run `check.mjs`, re-read only the contract and source in a fresh turn, cap the outcome at FIX, and tell the user an independent review did not happen.

Report to the user: the SEED KEY (so the roll is reproducible), the concept name and signature device, the world and skeleton in one line, the disposition, and the re-roll command.

Then list what the user can steer, taken from the printed contract (THESIS, SIGNATURE GRAPHIC, WORLD) so no new choice is invented for the list:

- **Safe (category baseline):** 2-3 choices in this build that any peer in the category would also make.
- **Risks (this build's own face):** 2-3 departures from the category, each with what it gains and what it costs.
- Steer with `--register safer|bolder` or `--lock concept=<id>`.

Credit: adapted from garrytan/gstack design-consultation/sections/proposal-and-preview.md.tmpl @ 5b9b837 (MIT).

---

## Decision table

| Situation | Do |
|---|---|
| Repo has DESIGN.md / tokens / themed components | Extend mode (`references/extend-mode.md`); no world roll |
| New section or component inside an existing surface | Inherit the surface; no roll at all |
| User pins an aesthetic, era, font or palette | `--lock …`; the brief wins over any catalog warning |
| User directive about the look ("no illustrations", "B&W") | `dossier.directives`; outranks the bars |
| Page needs icons, illustrations, diagrams or brand objects | Graphics check (Step 3a) |
| Client supplies photography | `photography` concept |
| SaaS with a real product | `product-ui` concept |
| Dashboard or docs | `utility`, no graphics brief unless the check calls for icons or empty states |
| Native platform (ios/android) | `mobile-design` + device screenshots |
| User says "safer" / "bolder" while a roll is open | `--from <key> --reroll n --register safer|bolder` |
| User says "just do the normal thing" | `--canon`; ask for 2-3 peer products; their craft is the bar |
| Operate surface (dashboard, settings, checkout) | Mode `operate`: quiet worlds, conventional skeleton, distinctiveness in details |
| Any new project | Dossier + concepts (Step 0-0b); a thin category simply has more `artefact` and `place` facts |
| Client has a live site | Scrape copy and media into the dossier; throttle; Wayback fallback |
| N variants for one client | One dossier, one concepts file, one key, `--reroll 0..N-1`; concepts and worlds are excluded per round |
| User vetoes a world for the trade | Record in dossier.refuse, `--register safer`; after 2 misses show 3 previews to the user |
| Needs Cyrillic/Greek/Vietnamese body text | `--scripts latin,cyrillic` (filters the font pool before rolling) |
| Email / RN / no webfonts | `--no-webfonts` (system stack; hierarchy from weight and size) |
| Coherence row FAIL | Lock the failing axis and re-run; never proceed on a known-bad assignment |
| `roll.mjs` cannot load data | Stop and report; never fall back to picking by taste |

## What breaks this skill

- **Choosing among options.** Presenting three directions and picking one, or "picking the boldest", reinstates the argmax. The roll assigns; the user may steer. Writing several concepts is required. Choosing among them is not yours.
- **Subject-blind direction**: rolling without concepts on a new project.
- **No headline on the fold.** No real `<h1>`, only svg text, no value proposition or action (persuade/experience), or no page title (operate/read).
- **Wrong mood for the audience.** A concept or world that breaks the audience's mood need (bright primary shapes for a funeral home, a gloomy night street for a children's clinic, a murky page for a friendly accountant) is a critic FAIL; re-roll with `--lock concept=<id>` before building further.
- **One look every time.** The same idea, style or graphic across projects. Variety comes from the roll and from each project's own facts.
- **Decoration with no user job.** Art, icons or ornament that help nobody find, understand or trust anything.
- **Graphics are made by `design:graphics`.** Objects drawn as boxes, people as blobs, or a lead redrawing the returned files by hand: send the asset back through the graphics skill.
- **Hunting for scripts.** Searching the filesystem for `roll.mjs` or running the installed plugin's copy instead of the base directory.
- **Invented facts**: a number, quote or customer not in the dossier.
- **Guardrails inside the brief.** Loading `build-craft.md` before the contract, or writing "be bold but not too bold", produces the hedged 65% page.
- **Naming replacements.** Writing "use Satoshi or Geist instead of Inter" anywhere creates the next default. Fonts come from the roll.
- **Skin-only variety.** New font and palette on the category's standard grid. The evaluator's silhouette test exists to catch this; do not argue with it.
- **Randomness on an operate surface.** A maximalist checkout is worse than a plain one. The mode gate is not optional.
- **Independent axes.** Picking a palette from one list and a style from another produces dark style + light palette contradictions. Everything is conditioned on the world.
- **Overriding a user directive.** Illustrating after "no illustrations", adding colour after "black and white".
- **Transforming client photos or redrawing real people** when the treatment is photography.
- **Self-certification.** The thread that built it may not ship it.
- **Premium by effect.** Gradient text, decorative glass, uniform `rounded-2xl` and `shadow-lg` signal a template, not craft. Weight, size, position and material carry hierarchy.
