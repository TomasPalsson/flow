---
name: vary
description: Design frontend UI that is specific to THIS project and different every run: read the project into a fact dossier, write grounded concepts, and let an external roll (scripts/roll.mjs) assign a concept, a signature-graphic technique, a fitting visual world, a skeleton, a palette seed and fonts; then build the concept's hero treatment (drawn scene, the client's photography, product UI, typography, data visual or pattern). The catalogs hold 47 worlds, 18 archetypes, 120 hue-balanced seeds and 160+ verified faces; the model commits fully, a mechanical craft floor (scripts/check.mjs) and a separate evaluator subagent judge distinctiveness and contract-keeping. Use WHENEVER building, redesigning, mocking up or restyling any UI — landing page, marketing site, dashboard, admin, docs, portfolio, app screen, component set, email, artifact — and whenever the user says design, UI, frontend, make it look good, not generic, not AI slop, something different, new vibe, new palette, new fonts, surprise me, bold, distinctive, or complains that designs look the same. Also use for "give me another direction", "re-roll", "safer", "bolder", "play it straight". Not for backend-only work or pure copy edits.
user-invocable: true
argument-hint: "[brief] [--mode persuade|operate|read|experience] [--reroll] [--safer|--bolder|--canon]"
---

# vary — design that is assigned, not chosen

Claude's design output collapses to a mode: indigo, Inter, centred hero, three cards. Told to avoid those, it collapses to the next mode: cream + serif + terracotta, or near-black + one neon, Space Grotesk, bento + glass. The cause is not a lack of ideas. The model derives seven varied directions and then argmax-picks the same one every time; asking it to "choose differently" reverted in 27 of 30 measured runs. Naming things to avoid makes it worse: a named font or hex gets *more* activation, not less.

Four things fix this, and this skill is built around them:

1. **An external roll assigns the direction.** `scripts/roll.mjs` picks concept → signature device → world → skeleton → colour strategy → palette seed → fonts, each conditioned on the last, from the project's concepts and the catalogs in `data/`. Claude executes the assignment. It does not pick from a menu.
2. **Variety must move on two axes.** A new palette on the same centred-hero skeleton is the same design. The roll moves the skeleton (archetype) and the lineage (world) together; skin follows.
3. **The roll picks among grounded options.** Concepts come from the project's own facts, and worlds are filtered by its sector. Randomness then buys variety without buying irrelevance.
4. **The signature is specific to the subject.** Every build carries one signature element taken from the project's facts or assets: a drawing, the client's own photographs, the real product, a typographic system or a data form. A palette and fonts over generic blocks is not a design.

Then: commit fully, guard later. Craft rules are loaded only *after* the contract is written, because guardrails mixed into the brief measurably hedge the result. Review is done by a separate identity auditing the build against its own contract, because self-review rubber-stamps.

(The measurements above come from Impeccable's instrumented v4 campaign, impeccable.style/research, and from NeurIPS 2025 work on ironic negation, arXiv 2511.12381. The research trail for this skill is in its forge workspace.)

---

## Step 0 — Read the project, then the surface

Load [`references/dossier.md`](references/dossier.md) and write `.vary/dossier.json` before anything else. Facts come from the repo, the client's live site and the assets given. Nothing is invented.

Then settle these in one short block (write them; they feed the roll):

- **Mode** of *this surface*: `persuade` (visitor decides and acts: landing, pricing, campaign), `operate` (completes a task: app, dashboard, settings, forms, checkout), `read` (understands: docs, articles, changelog), `experience` (is inside the work: portfolio, gallery). A dev tool's landing page is persuade; a fashion house's docs are read. Mode gates how bold the roll may be. Operate and read surfaces get quiet worlds and conventional skeletons; their distinctiveness lives in details.
- **Platform**: `web`, `ios`, `android`. Phones exclude pointer-dependent skeletons. ios/android: load the `mobile-design` skill for the platform layer. The contract goes as a `/* ... */` block at the top of the root component. Evidence is device screenshots; fold-check does not apply.
- **Locks** — anything the user or the repo has already decided: brand hex (`--lock palette=#…`), a required font, required scripts (`--scripts latin,cyrillic`), no webfonts (email, React Native → `--no-webfonts`), longevity (`--longevity campaign` allows fast-decaying looks). A brief that pins an aesthetic ("make it Bauhaus", "keep our brand") beats the roll: `--lock world=bauhaus`.
- **Directives**: anything the user says about the look ("no illustrations", "black and white", "use our photos", "minimal") goes verbatim into `dossier.directives` with the locks it implies. Directives outrank this skill's defaults, bars and gates; only truth and accessibility outrank them.

  | Directive | Locks / effect |
  |---|---|
  | no illustrations | `treatment=typography`, or photography/product-ui if assets exist |
  | black and white | `strategy=ink-on-paper` and no accent (build-craft tint rules suspended) |
  | Swiss | `world=swiss-international` |
  | use our photos | `treatment=photography` |
  | minimal | `treatment=typography`, or `photography` when photos exist (dead-zone and depth are INFO there); never `scene` unless the user also asks for drawings |
  | keep our brand | extend mode |

- **Precedence** (the one place it is written; both evaluators repeat it). When rules collide, the higher item wins: 1. Truth: no invented facts. 2. Accessibility: contrast, keyboard, focus, reduced motion, text equivalents. 3. User directives (`dossier.directives`). 4. Existing brand or design system (extend mode). 5. Platform conventions (ios/android; operate Jakob's law). 6. The rolled contract. 7. Treatment-specific bars and skill defaults.
- **Existing design system?** If the repo has `DESIGN.md`, a token file, a Tailwind theme with custom colours, or styled shared components, this is **extend mode**: read [`references/extend-mode.md`](references/extend-mode.md) and follow it instead of Step 1. A component or section inside an established surface always inherits that surface. Never turn a local addition into a new identity.
- **Sector**: one id from the controlled list, taken from the dossier's `sector`. It filters the world pool. Pick the one a customer would file the business under (a pizzeria with a bar is `food-drink`). When torn between two, decide the tie after Step 0b (take the one whose worlds list fits the concept hints better), note the choice in the dossier, and write the final sector into `dossier.sector`, which must equal `--sector`.
- **Multi-surface clients**: the roll's mode is the mode of the surface built first (usually the home or landing page, so `persuade`). Later surfaces reuse the contract and take their own archetype.
- **Scene sentence**: who uses this, where, under what light. This decides light or dark, not the category (`--scene light|dark` once decided).

Ask the user at most one round of two or three questions, and only for facts that change the work (the real proof/content available, audience, what must not change). Never ask for CSS values or an aesthetic lane.

## Step 0b — Concepts

Read [`references/concepts.md`](references/concepts.md) and write 4-7 concepts to `.vary/concepts.json`. Each concept takes a different angle on the business: a different audience moment, half of the trade, time of day or artefact. Each cites at least 3 fact ids, names the trade artefact it borrows, re-skins the functional objects (cart, confirmation, nav), names 2-3 `world_hints` (the one permitted read of `data/worlds.json`: take ids, names, sectors and `avoid_sectors` only, never use it to choose the final world), and offers 2-3 signature devices from the technique list. Each concept names a `treatment` (scene, pattern, photography, product-ui, typography, data-visual, utility). Pick treatments by signal, scene by default (`references/concepts.md` §3): a small business, place or service with no photos, no product UI and no style directive gets `scene` concepts (at most one `pattern`). When the dossier has usable photos or a product UI, at least one concept uses `photography` or `product-ui`, and at least two treatments appear across the file. Write them all at full strength: the roll, not you, picks one.

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

## Step 3a — Signature visual first

Route by the contract's `HERO TREATMENT`:

- `scene`: the scene bar below, the art crew and two critique rounds.
- `pattern`: art brief + gallery, one critique round, no crew. S1 coverage and full-bleed apply; the S2 people/objects clauses do not.
- `photography`: write `.vary/visual-brief.md` listing which dossier asset goes where, with the crop rule, sequence and grade. Photos ship unaltered unless the world or a directive says otherwise. Identifiable real people are never redrawn. The photos carry the page: no frames or ornament around them, no drawn stand-ins for products, and described-but-missing photos become full-size tonal plates (`references/build-craft.md` §6 item 19).
- `product-ui`: a capture list (which workflow, which real data, which states), DPR-2 captures, callouts allowed.
- `typography`: a type specimen at hero size with the content language's glyphs, plus the fact the lettering carries.
- `data-visual`: the chart spec, its dossier data and a text equivalent.
- `utility`: skip to Step 3.

The bars for the non-scene treatments are `graphics.md` §9-§12.

### Scene bar (treatment = scene only)

Read [`references/graphics.md`](references/graphics.md) in full (§0b is the benchmark, §1b "Composing a scene" is the method). Write `.vary/art-brief.md` from its template. The brief must list every subject from the dossier that gets drawn, the engine, the style object, the banned forms, and the sizes (hero and thumb). The art meets this **scene bar**, which the brief must plan for and the critique must check:

- **S1 (scene) Hero scene.** For `persuade` and `experience`: **edge to edge, no frame (G1).** The hero scene spans the full viewport width at desktop and phone (at least 95%, touching both edges): no HTML box, card, polaroid, frame or page margin around it (a border drawn inside the art, such as a blueprint sheet's, is part of the art). Judges: "full-bleed scene, not a framed picture". For `persuade` and `experience` modes the first viewport is a full-bleed illustrated scene (or sheet): the drawing covers at least 55% of the first viewport at 1440x900 and 45% at 390x844, made of at least 5 distinct subject objects from the dossier across at least 3 depth layers (background/environment, main subject, foreground detail or people). The brand or headline is set INTO the scene (a sign, label, title block, painted lettering), not floated beside a boxed picture. **The first viewport always carries a real HTML `<h1>` (the business name or the promise), a one-line value proposition (what they do, for whom, in the client's real words from the dossier) and the primary action (a link or button with visible text), positioned ON a drawn surface of the scene: absolutely positioned over the sign, board or title-block area the art leaves empty for it and styled as that surface's lettering (`graphics.md` §1b has the pattern). It is painted-in and real text at once. Never only svg `<text>` (the fold check fails "no visible h1"), never a floating card, never omitted.** At least 2 real dossier facts are rendered inside the art itself (a phone number on the sign, the founding year in a title block, opening hours on a door card).
- **S2 (scene) Richness floor** for every scene and plate: filled shapes (not hairlines on an empty field), one consistent light source (lit and shaded faces, cast shadows), texture (grain, hatching, halftone, paper), people or traces of use where the business has them, a palette of 4-7 inks. A single icon, a bare grid, a lone diagram in a framed box or a decorative blob FAILS the hero.
- **S3 (scene) Art all the way down.** Every section below the fold carries its own drawn plate at real size (at least 40% of the section's width (never under a third — the gate fails plates under 35%) and 280px tall at desktop, never thumbnail-only, and fully rendered with the same finish pass as the hero: gradient, glow, grain, at least 3 value steps; never a thin, small, pale line diagram in a tinted box, which judges read as "monochrome line drawings in tinted boxes"), drawn from that section's facts (place, product or menu, process, people or history); a catalogue, menu or services list draws EACH item (the art is a function of the item record). A section that is only cards, text or a form fails unless it is the contact block. Plus the micro scale (icons, bullets, dividers drawn in the same hand).
- **S4 (scene) Finish (G2).** Apply `graphics.md` §1d ("Depth recipe" has the numbers; flat fills with thin uniform strokes read as clip art): a value plan (one key light, one glow, the brightest value on the focal fact), at least 3 value steps per material, grain at 3-8%, and no empty region over 20% of the hero.
- **S5 (scene) Type in the art (G3).** No frosted, translucent or SOLID card, chip row or SaaS button pair over the hero art: an opaque headline container covering more than 6% of the art area fails (judges: "a headline card floats over the art, covering it"). The headline is a real `<h1>` and the primary action a real link or button, set over a drawn surface (sign, plate, title block, chalkboard, ticket, label) as in the §1b pattern; phone and hours may be painted in the svg. Text on a surface that is part of the drawing is fine; a headline that exists only as svg `<text>` fails the fold check.
- **S7 (scene) Objects and body composition.** (a) Every drawn object has a real silhouette (a train has bogies, windows and a roof line; a book has spine, boards and headband; never a box standing for a thing), at least 3 value steps, and people have a posture or gesture and a cast shadow (`graphics.md` §1e has a carriage and a bound book built from the kit). (b) No two consecutive sections share a layout skeleton. The brief assigns one of six per section: full-bleed plate with caption; catalogue of drawn items; process strip of 3-5 drawn steps; map or plan; big quote over art; ticket, label or form drawn as an object (`graphics.md` §7). At least half the sections below the fold are full-width drawn plates (full-bleed plate with caption, catalogue of drawn items, process strip, map or plan, quote over art); "a card with a small drawing" counts as the card skeleton and appears at most twice per page. Copy left with a small boxed diagram right, repeated, is the failure. (c) Every section plate is a drawing of that section's subject, never a labelled box with words in it. (d) Identity assets (headshots, sponsor or partner logos, client photos of people, product screenshots) are shown unaltered and are exempt from "draw each item". Data sections (schedule, pricing table, comparison, code) are exempt from plates.
- **S8 Mood fit (every treatment).** The art brief states the audience's mood need in one line (children: bright, safe, daytime; bereavement: calm, quiet, dignified; B2B lab: precise, trustworthy) and the chosen concept and world must serve it. If the critic finds they break it, re-roll the world with `--lock concept=<id>` before building further.
- **S6 No collisions (every treatment).** Every label, callout and sign text is fully visible at both viewports: no overlap with drawn objects or other labels.

**Art crew (scene only; Step 3a, after the brief).** Read [`references/art-crew.md`](references/art-crew.md). Dispatch illustrator subagents IN PARALLEL with the Agent tool: one for the hero scene and one per section plate (cap 6), each handed ONLY the art-brief path, its plate's row (subject, facts, skeleton, size), the style object and core kit paths, and `art-crew.md`. Each builds its plate module, renders it at real size, critiques its own screenshot against the richness bar (objects not boxes, posture, shared ground and light, 3+ values, texture, facts in the art), fixes, and returns the module path and final PNG path. The lead integrates and does not redraw. If the Agent tool is unavailable, the lead draws the plates itself in the same order. The lead then builds the gallery and runs the two critique rounds below on the integrated result.

Build the art module and an `art-gallery.html` that renders every subject at both sizes, plus the hero scene composed whole at 1440x900 and 390x844. Screenshot it and read the screenshots. Write concrete critique (what reads wrong, not "could be better"). **Each critique round compares the gallery screenshot against S1-S3 explicitly and against the §0b benchmark descriptions in `graphics.md`, and lists what is missing: objects (count vs 5), layers (vs 3), light, value steps, grain, empty zones (vs 20%), facts-in-art, coverage, a plate per section below the fold, text collisions.** Fix it. Do two rounds, no more (with the art crew the illustrators' own rounds are the plate pass and your gallery review is one read plus one fix): the art loop has a time budget (hero first, plates second, then build; a shipped page with good art beats a perfect gallery and no page). Write a style-rule test for the world's constraint (for example "litho: no opacity, no gradients"). Under the scene treatment, no UI page code until round 2 passes.

## Step 3 — Build, fully committed

Read [`references/build-craft.md`](references/build-craft.md) in full now, not earlier. It holds palette composition from the seed, type loading, motion, states, browser surfaces and the craft floor. It is loaded after the contract on purpose.

While building:

- **Borrow the skeleton, not the clothes.** Structure comes from the ARCHETYPE and the world's GRAMMAR. A committed surface over the category's standard marketing grid is the most common failure and the hardest to see.
- **Full commitment beats a hedged half.** A perfectly executed conventional page beats a half-executed distinctive one; a fully executed distinctive one beats both. Use all the weights of the assigned faces. Let the colour strategy own the page area it claims.
- **One authored motion moment** (the MOTION MOMENT line). Nothing else animates on entrance.
- **Real content.** Content comes from the dossier verbatim (menu, prices, hours, specs, quotes with source). Demo values are flagged as demo. Never invent prices, customers, testimonials, statistics or capabilities.
- **Every control in the world's material** (persuade/experience): nav, buttons, chips, cart and confirmation follow FUNCTIONAL RESKIN. A default underline nav or flat pill button reads as vibe-coded. Operate surfaces keep platform conventions for nav, forms and errors and skin them through tokens.
- **Decorative fields stay on graphic plates.** Reading, prices and forms sit on a high-contrast field.
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

Fix every `FAIL` in one batch (contract present, contrast, focus-visible, 9 states, reduced motion, image dimensions, font weights, arbitrary Tailwind values, AI vocabulary and em-dash density, template tells, and the project checks: concept-contract, facts-in-build, and, for scene, pattern and data-visual treatments only, bespoke-graphics, seeded-art, svg-a11y; for any other treatment those three are INFO, not FAIL, and until check.mjs routes by treatment a bespoke-graphics FAIL on a typography, photography, product-ui or utility build is expected and is not fixed by adding art). A user directive outranks any check row (precedence item 3): never add an illustration to satisfy a check against a "no illustrations" directive. Never satisfy a check by loosening it. Keep the JSON: the evaluator reads it.

## Step 4b — Critic before shipping

Spawn a FRESH subagent (Agent tool) with the desktop and phone fold and full-page screenshots, the dossier facts and the critic prompt and rubric from [`references/art-crew.md`](references/art-crew.md) section 5, with `{TREATMENT}` filled from the contract (specificity, signature visual, craft, wow, each 1-10; anchors from `graphics.md` §0b at 9-10 for scene and the §9-§12 bars otherwise; "pill figures / boxes for objects / template sections / clipped text / dead space" at 4-5). It returns scores and the 5 highest-impact fixes. The lead applies the fixes (plates go back to their illustrator) and re-runs a new critic; stop when the mean is 7.5 or more or after 2 critic rounds, logging open items in NOTES.md. After applying fixes, re-run `check.mjs` and the fold check and refresh the evaluator JSON before Step 5; record the last critic mean in NOTES.md. Critic rounds sit outside the art budget and may be skipped when time is short.

**Blocking craft fails.** Before Step 5 or shipping, these fold-check rows must be PASS: collisions, clipped-text, hidden-content, stray-overlay, duplicate-content, headline-on-fold (operate/read: title-on-fold), plus headline-in-scene for the scene treatment only (the check's `BLOCKING:` line lists any that fail). They are cheap to fix and the time budget never excuses them. Coverage, depth and plate-size may ship as logged open items (`NOTES.md`) if time runs out.

## Step 5 — Separate evaluation

Mandatory for anything the user will ship; skippable only when the user said "just something quick".

1. Read [`evaluator-prompt.md`](evaluator-prompt.md) and copy it **verbatim** into a new subagent (`general-purpose`, `model: sonnet`, `mode: bypassPermissions`). Append: the original brief, the absolute paths of the built files, the path of the `check.mjs` JSON, `.vary/dossier.json`, `.vary/art-brief.md`, `.vary/critique-r2.json` (the round-2 art critique) and the gallery screenshots (these three only if the treatment produced them; photography, typography and utility builds have none), plus the page screenshots (`npx agent-browser` or the browser MCP). Screenshots are **required** for persuade and experience (ios/android: device screenshots); without them the evaluator returns RECAPTURE. Optionally append `SIBLINGS:` with the contract blocks of other variants for the same project.
2. The dossier, art brief and critique are project evidence, not generator rules. Pass them. Still withhold this SKILL.md, the references, the catalogs, and any of the generating conversation. The evaluator audits the build against its own contract block and tests distinctiveness; feeding it the generator's rules collapses that separation.
3. Dispositions are closed: **SHIP / FIX / REBUILD / RECAPTURE**. FIX gets exactly one batched round, re-checked by the evaluator, not by the builder. REBUILD means a structural promise broke (skeleton, a grammar rule, thesis vs execution): return to Step 3 with the same contract. RECAPTURE means the evidence was bad (contract stripped, no source): fix the evidence, not the design.
4. The builder never marks its own SHIP. If no subagent tool exists, run `check.mjs`, re-read only the contract and source in a fresh turn, cap the outcome at FIX, and tell the user an independent review did not happen.

Report to the user: the SEED KEY (so the roll is reproducible), the concept name and signature device, the world and skeleton in one line, the disposition, and the re-roll command.

---

## Decision table

| Situation | Do |
|---|---|
| Repo has DESIGN.md / tokens / themed components | Extend mode (`references/extend-mode.md`); no world roll |
| New section or component inside an existing surface | Inherit the surface; no roll at all |
| User pins an aesthetic, era, font or palette | `--lock …`; the brief wins over any catalog warning |
| User directive about the look ("no illustrations", "B&W") | `dossier.directives`; outranks the bars |
| Client supplies photography | `photography` concept |
| SaaS with a real product | `product-ui` concept |
| Dashboard or docs | `utility`, no art brief |
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
- **Art that stops at the fold (scene treatment).** One hero, then text, cards and a form. Every section carries its own plate (S3).
- **A UI card over the art (scene treatment).** A frosted card, chip row or button pair laid over the hero (S5).
- **Template body (scene treatment).** After a good hero, every section repeats copy left and a small boxed line diagram right, price lists appear twice, plates are labelled boxes. Assign a different skeleton to each section (S7).
- **No headline on the fold.** (scene: over a drawn surface) No real `<h1>` over a drawn surface, only svg text, no value proposition or action, or a stock card floating over the art (S1, S5).
- **Wrong mood for the audience.** A concept or world that breaks the audience's mood need (bright primary shapes for a funeral home, a gloomy night street for a children's clinic, a murky page for a friendly accountant) is a critic FAIL; re-roll with `--lock concept=<id>` before building further (S8).
- **Boxes for objects (scene treatment).** A train, drawer or book drawn as a rectangle, a person as a blob (S7a).
- **A thin hero (scene treatment).** One icon, one diagram in a framed box, a bare grid or a text-only first screen on a persuade surface. The benchmark heroes are whole scenes or sheets (S1-S3).
- **Hunting for scripts.** Searching the filesystem for `roll.mjs` or running the installed plugin's copy instead of the base directory.
- **Decoration instead of drawing (scene treatment)**: blobs, gradient meshes or noise-only heroes where a drawing of the subject belongs.
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
