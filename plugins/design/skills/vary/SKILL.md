---
name: vary
description: Design frontend UI that is specific to THIS project and different every run: read the project into a fact dossier, write grounded concepts, and let an external roll (scripts/roll.mjs) assign a concept, a signature-graphic technique, a fitting visual world, a skeleton, a palette seed and fonts; then draw custom graphics of the subject (SVG illustration, traced line art, mechanism diagrams, generative patterns) before building. The catalogs hold 47 worlds, 18 archetypes, 120 hue-balanced seeds and 160+ verified faces; the model commits fully, a mechanical craft floor (scripts/check.mjs) and a separate evaluator subagent judge distinctiveness and contract-keeping. Use WHENEVER building, redesigning, mocking up or restyling any UI — landing page, marketing site, dashboard, admin, docs, portfolio, app screen, component set, email, artifact — and whenever the user says design, UI, frontend, make it look good, not generic, not AI slop, something different, new vibe, new palette, new fonts, surprise me, bold, distinctive, or complains that designs look the same. Also use for "give me another direction", "re-roll", "safer", "bolder", "play it straight". Not for backend-only work or pure copy edits.
user-invocable: true
argument-hint: "[brief] [--mode persuade|operate|read|experience] [--reroll] [--safer|--bolder|--canon]"
---

# vary — design that is assigned, not chosen

Claude's design output collapses to a mode: indigo, Inter, centred hero, three cards. Told to avoid those, it collapses to the next mode: cream + serif + terracotta, or near-black + one neon, Space Grotesk, bento + glass. The cause is not a lack of ideas. The model derives seven varied directions and then argmax-picks the same one every time; asking it to "choose differently" reverted in 27 of 30 measured runs. Naming things to avoid makes it worse: a named font or hex gets *more* activation, not less.

Four things fix this, and this skill is built around them:

1. **An external roll assigns the direction.** `scripts/roll.mjs` picks concept → signature device → world → skeleton → colour strategy → palette seed → fonts, each conditioned on the last, from the project's concepts and the catalogs in `data/`. Claude executes the assignment. It does not pick from a menu.
2. **Variety must move on two axes.** A new palette on the same centred-hero skeleton is the same design. The roll moves the skeleton (archetype) and the lineage (world) together; skin follows.
3. **The roll picks among grounded options.** Concepts come from the project's own facts, and worlds are filtered by its sector. Randomness then buys variety without buying irrelevance.
4. **The graphics are the identity.** Every build carries a signature device drawn from the subject. A palette and fonts over CSS blocks is not a design.

Then: commit fully, guard later. Craft rules are loaded only *after* the contract is written, because guardrails mixed into the brief measurably hedge the result. Review is done by a separate identity auditing the build against its own contract, because self-review rubber-stamps.

(The measurements above come from Impeccable's instrumented v4 campaign, impeccable.style/research, and from NeurIPS 2025 work on ironic negation, arXiv 2511.12381. The research trail for this skill is in its forge workspace.)

---

## Step 0 — Read the project, then the surface

Load [`references/dossier.md`](references/dossier.md) and write `.vary/dossier.json` before anything else. Facts come from the repo, the client's live site and the assets given. Nothing is invented.

Then settle these in one short block (write them; they feed the roll):

- **Mode** of *this surface*: `persuade` (visitor decides and acts: landing, pricing, campaign), `operate` (completes a task: app, dashboard, settings, forms, checkout), `read` (understands: docs, articles, changelog), `experience` (is inside the work: portfolio, gallery). A dev tool's landing page is persuade; a fashion house's docs are read. Mode gates how bold the roll may be. Operate and read surfaces get quiet worlds and conventional skeletons; their distinctiveness lives in details.
- **Platform**: `web`, `ios`, `android`. Phones exclude pointer-dependent skeletons.
- **Locks** — anything the user or the repo has already decided: brand hex (`--lock palette=#…`), a required font, required scripts (`--scripts latin,cyrillic`), no webfonts (email, React Native → `--no-webfonts`), longevity (`--longevity campaign` allows fast-decaying looks). A brief that pins an aesthetic ("make it Bauhaus", "keep our brand") beats the roll: `--lock world=bauhaus`.
- **Existing design system?** If the repo has `DESIGN.md`, a token file, a Tailwind theme with custom colours, or styled shared components, this is **extend mode**: read [`references/extend-mode.md`](references/extend-mode.md) and follow it instead of Step 1. A component or section inside an established surface always inherits that surface. Never turn a local addition into a new identity.
- **Sector**: one id from the controlled list, taken from the dossier's `sector`. It filters the world pool. Pick the one a customer would file the business under (a pizzeria with a bar is `food-drink`). When torn between two, decide the tie after Step 0b (take the one whose worlds list fits the concept hints better), note the choice in the dossier, and write the final sector into `dossier.sector`, which must equal `--sector`.
- **Multi-surface clients**: the roll's mode is the mode of the surface built first (usually the home or landing page, so `persuade`). Later surfaces reuse the contract and take their own archetype.
- **Scene sentence**: who uses this, where, under what light. This decides light or dark, not the category (`--scene light|dark` once decided).

Ask the user at most one round of two or three questions, and only for facts that change the work (the real proof/content available, audience, what must not change). Never ask for CSS values or an aesthetic lane.

## Step 0b — Concepts

Read [`references/concepts.md`](references/concepts.md) and write 4-7 concepts to `.vary/concepts.json`. Each concept takes a different angle on the business: a different audience moment, half of the trade, time of day or artefact. Each cites at least 3 fact ids, names the trade artefact it borrows, re-skins the functional objects (cart, confirmation, nav), names 2-3 `world_hints` (the one permitted read of `data/worlds.json`: take ids, names, sectors and `avoid_sectors` only, never use it to choose the final world), and offers 2-3 signature devices from the technique list. Write them all at full strength: the roll, not you, picks one.

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
- **FIRST VIEWPORT**: what is where, at what scale, where the primary action sits. Derived from the ARCHETYPE plus the CONCEPT; the signature device is visible in it at hero scale, and the first screen announces the concept, not a shop listing.
- **THESIS**: the one idea this surface owns, and the category-default arrangement it refuses. If it reads like a mood ("clean, confident"), it is not decided yet.
- **SIGNATURE GRAPHIC**: what is drawn, which FACTS it encodes, how it renders (engine/file), and its three placements.

CONCEPT supplies thesis, materials, the memorable element and the functional reskin. WORLD supplies grammar, skeleton, type and motion. FACTS win every conflict; clarity beats all three.

## Step 3a — Art first

Read [`references/graphics.md`](references/graphics.md) in full (§0b is the benchmark, §1b "Composing a scene" is the method). Write `.vary/art-brief.md` from its template. The brief must list every subject from the dossier that gets drawn, the engine, the style object, the banned forms, and the sizes (hero and thumb). The art meets this **scene bar**, which the brief must plan for and the critique must check:

- **S1 Hero scene.** For `persuade` and `experience` modes the first viewport is a full-bleed illustrated scene (or sheet): the drawing covers at least 55% of the first viewport at 1440x900 and 45% at 390x844, made of at least 5 distinct subject objects from the dossier across at least 3 depth layers (background/environment, main subject, foreground detail or people). The brand or headline is set INTO the scene (a sign, label, title block, painted lettering), not floated beside a boxed picture. At least 2 real dossier facts are rendered inside the art itself (a phone number on the sign, the founding year in a title block, opening hours on a door card). `operate` and `read` modes: the device may sit at plate scale, but with at least one full-width plate.
- **S2 Richness floor** for every scene and plate: filled shapes (not hairlines on an empty field), one consistent light source (lit and shaded faces, cast shadows), texture (grain, hatching, halftone, paper), people or traces of use where the business has them, a palette of 4-7 inks. A single icon, a bare grid, a lone diagram in a framed box or a decorative blob FAILS the hero.
- **S3 Art all the way down.** Every section below the fold carries its own drawn plate at real size (at least 40% of the section's width, never thumbnail-only), drawn from that section's facts (place, product or menu, process, people or history); a catalogue, menu or services list draws EACH item (the art is a function of the item record). A section that is only cards, text or a form fails unless it is the contact block. Plus the micro scale (icons, bullets, dividers drawn in the same hand).
- **S4 Finish.** Apply `graphics.md` §1d: a value plan (one key light, one glow, the brightest value on the focal fact), at least 3 value steps per material, grain at 3-8%, and no empty region over 20% of the hero.
- **S5 Type in the art.** No frosted or translucent card, chip row or SaaS button pair over the hero art. Headline, phone, hours and the primary action are painted onto in-scene surfaces (sign, plate, title block, chalkboard, ticket, label; the worked example in §1b makes the sign a real `<a>`) or sit on a solid band that is part of the composition.
- **S6 No collisions.** Every label, callout and sign text is fully visible at both viewports: no overlap with drawn objects or other labels.

Build the art module and an `art-gallery.html` that renders every subject at both sizes, plus the hero scene composed whole at 1440x900 and 390x844. Screenshot it and read the screenshots. Write concrete critique (what reads wrong, not "could be better"). **Each critique round compares the gallery screenshot against S1-S3 explicitly and against the §0b benchmark descriptions in `graphics.md`, and lists what is missing: objects (count vs 5), layers (vs 3), light, value steps, grain, empty zones (vs 20%), facts-in-art, coverage, a plate per section below the fold, text collisions.** Fix it. Do two rounds, no more: the art loop has a time budget (hero first, plates second, then build; a shipped page with good art beats a perfect gallery and no page). Write a style-rule test for the world's constraint (for example "litho: no opacity, no gradients"). No UI page code until round 2 passes.

## Step 3 — Build, fully committed

Read [`references/build-craft.md`](references/build-craft.md) in full now, not earlier. It holds palette composition from the seed, type loading, motion, states, browser surfaces and the craft floor. It is loaded after the contract on purpose.

While building:

- **Borrow the skeleton, not the clothes.** Structure comes from the ARCHETYPE and the world's GRAMMAR. A committed surface over the category's standard marketing grid is the most common failure and the hardest to see.
- **Full commitment beats a hedged half.** A perfectly executed conventional page beats a half-executed distinctive one; a fully executed distinctive one beats both. Use all the weights of the assigned faces. Let the colour strategy own the page area it claims.
- **One authored motion moment** (the MOTION MOMENT line). Nothing else animates on entrance.
- **Real content.** Content comes from the dossier verbatim (menu, prices, hours, specs, quotes with source). Demo values are flagged as demo. Never invent prices, customers, testimonials, statistics or capabilities.
- **Every control in the world's material**: nav, buttons, chips, cart and confirmation follow FUNCTIONAL RESKIN. A default underline nav or flat pill button reads as vibe-coded.
- **Decorative fields stay on graphic plates.** Reading, prices and forms sit on a high-contrast field.
- **Verify glyphs** for the content language (for example þ ð Á Í) by rendering the hero copy; swap or patch a face that fails.
- **Effort clusters where the content matters.** Everything equally detailed means nothing is important.
- When the world's grammar conflicts with a craft-floor rule, the grammar wins on aesthetics and the floor wins on accessibility, states and keyboard.

Build the whole thing, then inspect once in a batched round (desktop and mobile together), fix everything that round shows in one batch, and stop polishing.

## Step 4 — Mechanical check

```bash
node <VARY>/scripts/check.mjs <built files or dir> --json
```

Fix every `FAIL` in one batch (contract present, contrast, focus-visible, 9 states, reduced motion, image dimensions, font weights, arbitrary Tailwind values, AI vocabulary and em-dash density, template tells, and the project checks: concept-contract, facts-in-build, bespoke-graphics, seeded-art, svg-a11y). Never satisfy a check by loosening it. Keep the JSON: the evaluator reads it.

## Step 5 — Separate evaluation

Mandatory for anything the user will ship; skippable only when the user said "just something quick".

1. Read [`evaluator-prompt.md`](evaluator-prompt.md) and copy it **verbatim** into a new subagent (`general-purpose`, `model: sonnet`, `mode: bypassPermissions`). Append: the original brief, the absolute paths of the built files, the path of the `check.mjs` JSON, `.vary/dossier.json`, `.vary/art-brief.md`, `.vary/critique-r2.json` (the round-2 art critique), the gallery screenshots and the page screenshots (`npx agent-browser` or the browser MCP). Screenshots are **required** for persuade and experience; without them the evaluator returns RECAPTURE. Optionally append `SIBLINGS:` with the contract blocks of other variants for the same project.
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
- **Art that stops at the fold.** One hero, then text, cards and a form. Every section carries its own plate (S3).
- **A UI card over the art.** A frosted card, chip row or button pair laid over the hero (S5).
- **A thin hero.** One icon, one diagram in a framed box, a bare grid or a text-only first screen on a persuade surface. The benchmark heroes are whole scenes or sheets (S1-S3).
- **Hunting for scripts.** Searching the filesystem for `roll.mjs` or running the installed plugin's copy instead of the base directory.
- **Decoration instead of drawing**: blobs, gradient meshes or noise-only heroes where a drawing of the subject belongs.
- **Invented facts**: a number, quote or customer not in the dossier.
- **Guardrails inside the brief.** Loading `build-craft.md` before the contract, or writing "be bold but not too bold", produces the hedged 65% page.
- **Naming replacements.** Writing "use Satoshi or Geist instead of Inter" anywhere creates the next default. Fonts come from the roll.
- **Skin-only variety.** New font and palette on the category's standard grid. The evaluator's silhouette test exists to catch this; do not argue with it.
- **Randomness on an operate surface.** A maximalist checkout is worse than a plain one. The mode gate is not optional.
- **Independent axes.** Picking a palette from one list and a style from another produces dark style + light palette contradictions. Everything is conditioned on the world.
- **Self-certification.** The thread that built it may not ship it.
- **Premium by effect.** Gradient text, decorative glass, uniform `rounded-2xl` and `shadow-lg` signal a template, not craft. Weight, size, position and material carry hierarchy.
