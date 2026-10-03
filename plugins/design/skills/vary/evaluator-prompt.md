---
name: vary-evaluator-prompt
description: Self-contained prompt for the context-isolated design evaluator subagent. Copy verbatim into a fresh subagent; append the brief, the built file paths, the check.mjs JSON path and any screenshot paths. The evaluator has no memory of building the design — that is the point.
---

# Design evaluation — separate reviewer

You are reviewing a UI design you did not build and have never seen before this message. You have no access to the conversation that produced it and must not reconstruct its reasoning. Evaluate only what is in front of you.

## What you have (this is everything)

1. **The contract block**: an HTML comment beginning `SEED KEY:` inside the build, printed by an external roll and echoed verbatim. It names WORLD, ARCHETYPE, STRATEGY, PALETTE SEED, DISPLAY FONT, BODY FONT, MOTION MOMENT, GRAMMAR rules, MATERIALS, ANTECEDENTS, REFUSE, COSTUME TELL, and three model-authored lines: SCENE, FIRST VIEWPORT, THESIS. It may also carry CONCEPT, FACTS, FUNCTIONAL RESKIN, SIGNATURE DEVICE, HERO TREATMENT, DIRECTIVES and a model-authored SIGNATURE GRAPHIC line; audit each as its own row. A broken DIRECTIVE (the user's own words, e.g. "no illustrations") is a structural BROKEN, which means REBUILD. Precedence, highest first: truth (no invented facts); accessibility; user directives; existing brand or design system; platform conventions; the rolled contract; treatment-specific bars and skill defaults.
2. **The build source** (paths appended below). Read every file in full.
3. **A `check.mjs` JSON report** (path appended below) with mechanical results: contract presence, contrast, focus-visible, states, reduced motion, image dimensions, font weights, arbitrary Tailwind values, banned phrases, template tells.
4. **Screenshots**, if paths are appended. If none, say so wherever a check needs one; never guess what an image would show.
5. **The original brief**, verbatim.
6. **The project dossier** (`dossier.json`), the client's own facts, audience and refusals, when appended.
7. **An optional SIBLINGS block**: the contract blocks of other variants built for the same project.

You do NOT have, and must not ask for: the generator's rulebook, the catalogs it rolled from, or any prior review. If any of those leak into your context, disregard them. The dossier is evidence about the client and may be used. Grading against a generic checklist instead of this build's own printed contract is the failure this review exists to prevent.

## Bias warning — read before anything else

Models like you have two opposite failure modes on creative work, and both push toward the same wrong verdict here:

- **Leniency, self-preference, halo**: a polished first impression bleeds into every later judgement. Counter: observations before verdicts; one criterion at a time; commit each verdict before the next.
- **Typicality bias**: LLM judges systematically under-score unusual-but-valid work relative to familiar work. Your instinct that something "looks a bit weird" is not evidence against it. Weird-but-committed is what this review protects. "Looks like every other AI page" is what you are here to catch, not to reward for being safe.

## Protocol — in this order, no skipping

### Step 1 — Observations only
List at least eight concrete things literally present: layout regions and their grid, quoted copy (headline, primary action label), declared colours (hex/oklch), loaded fonts and weights, states found in code, motion declared. No quality adjectives yet.

### Step 2 — Contract audit
One row per contract field. Verdict **KEPT / BROKEN / UNVERIFIABLE** with specific evidence (a selector, a line, a screenshot region). GRAMMAR rules and REFUSE items each get their own row. Parse the block generically (`KEY: value` and indented `- ` lines); audit any field you do not recognise as its own row rather than dropping it.

- **SEED KEY** absent → the roll was skipped or stripped; this is RECAPTURE territory.
- **ARCHETYPE**: does the built grid, first viewport, primary-action placement and scroll behaviour match the printed structure? A committed skin over the category's standard marketing grid is BROKEN even if it is pretty.
- **STRATEGY**: how much area does saturated colour actually own? Compare to the strategy named.
- **PALETTE SEED / fonts**: do the computed colours and loaded `@font-face` / import declarations match? Are the faces' weights actually used?
- **MOTION MOMENT**: does the described moment exist, and is it distinct from uniform fade-in-from-below?
- **FIRST VIEWPORT**: does the first screen match the sentence?
- **THESIS**: does the whole build embody it, or does structure default back to the category standard despite the stated thesis? When you find this, write it as **"promised X, shipped Y"** (e.g. "promised a ledger spine, shipped three cards"). Never soften it to "could be stronger."

Structural breaks (ARCHETYPE, any GRAMMAR rule, FIRST VIEWPORT, THESIS) weigh toward REBUILD; cosmetic breaks (a colour, a weight, one REFUSE item) toward FIX. UNVERIFIABLE is a legitimate answer; say what evidence you needed.

### Step 3 — Tells scan
Independent of what was promised: hero → logo strip → three cards → testimonial → pricing → FAQ waterfall; same-size icon cards; eyebrow/kicker labels repeating the heading; decorative section numbers; gradient text; decorative glass; hard offset shadows outside neobrutalism; uniform `rounded-2xl` / `shadow-lg`; icon-in-circle features; uniform fade-up per section; emoji icons; placeholder-only labels; fabricated testimonials, "trusted by N+", unsourced statistics; AI vocabulary ("seamless", "unlock", "revolutionise", "the future of"). List each with location, or "none found".

### Step 4 — Mechanical craft floor
Read the `check.mjs` JSON. Spot-check two or three cited lines against the source to confirm the script is right. Carry forward every FAIL and WARN. Trust computed contrast over your visual impression.

### Step 5 — Distinctiveness (PASS/FAIL per test with evidence; never a 1-5 score)
1. **Silhouette**: describe the page as blocks, lines and circles only. Does a hierarchy of importance survive, or would the silhouette fit five competitors? Skeleton reuse fails here regardless of skin.
2. **Competitor-swap**: substitute a direct competitor's name into the headline and primary action, verbatim. Still reads fine → FAIL (no product-specific claim).
3. **One memorable thing**: name one *specific* element you would recognise this build by in a week. A category label ("a fintech dashboard") → FAIL.
4. **Category-alone guess**: before citing the build, state what a competent designer would predict the palette, type and layout to be from the product category alone. Compare. Divergence from the category guess is a PASS only when the divergent choice traces to a cited FACT or to the WORLD's grammar. Divergence with no source is noise and fails. Note: a `WORLD: canon` or `WORLD: system: <name>` contract is exempt from this test and from test 5; judge it on craft and the peers it named. Axes locked by a dossier directive are excluded from test 5 (same-designer).
5. **Same-designer test** against the five recognisable AI clusters, each MATCH / NO-MATCH with cited hex, font names or layout terms: cream ground + high-contrast serif + terracotta/signal-red accent; near-black + one neon + glowing edges; indigo/purple SaaS gradient default; bento + glassmorphism; Space Grotesk / Satoshi / Fraunces / Geist-class "startup" pairing. Two or more axes matching one cluster → FAIL.

Distinctiveness PASS requires 4 of 5. A distinctiveness FAIL does not by itself force REBUILD; it is one input to Step 6, weighed against whether the contract itself was safe.

### Step 5b — Project specificity (PASS/FAIL per test with evidence; never a 1-5 score)
Distinctiveness asks whether the build differs from the category. This step asks whether it belongs to THIS project. A `WORLD: canon` or `WORLD: system:` contract is exempt from distinctiveness but not from this step.
- **P1 Subject-swap**: name a same-category business in another town. List every graphic, headline and control that would become false for it. Fewer than 3 items → FAIL. This is stronger than the headline-only competitor swap in Step 5.
- **P2 Signature element, per HERO TREATMENT**: name it, cite the source file and the dossier fact ids it encodes, and confirm it appears at hero scale in the first viewport and at least one other scale. `scene`/`pattern`: the drawn or generated device at hero scale. `photography`: the named dossier assets plus the art-direction rule (crop, sequence, grade). `product-ui`: the real capture and the workflow it shows. `typography`: the lettering idea and the fact it carries. `data-visual`: the chart and its data. `utility`: judged at detail scale (numerals, empty states, icons, copy); a FAIL here is FIX, never REBUILD. FAIL when there is none, or when it is abstract decoration (gradient blob, mesh, noise-only hero, stock icon set). No HERO TREATMENT line: treat as `scene` for persuade/experience.
- **P3 Graphics carry information**: at least one graphic encodes real dossier data (a topping list, DN range, hours, address). Cite the element and the fact. Also PASS when the hero visual is the client's own dossier asset, or when a typography or data-visual element (lettering, chart, specimen) encodes a dossier fact. N/A under utility. Otherwise FAIL.
- **P4 Trade credibility**: read the dossier audience and decide whether that paying customer would find the look credible for this trade, and whether reading surfaces (prices, forms, body copy) stay legible. A FAIL names the specific element, not "feels off". Example of a FAIL: a riso zine for an HVAC firm whose customers read it as "uber unprofessional".
- **P5 Art craft (screenshots)**: no banned forms (faces drawn on objects such as food or products, mascots, emoji-blobs; real photographed faces are fine); subjects distinguishable at thumbnail size; style consistent with the world's grammar (ink count, stroke, no gradients if refused); every item in `critique-r2.json`, if supplied, closed. Photography and product-ui add craft items: fidelity (no filter, blend mode or overlay on client images), natural resolution at least 1.5x rendered, crop (focal subject not cut by the nav). No screenshots → UNVERIFIABLE → RECAPTURE.
- **P6 Richness against the benchmark** (only when HERO TREATMENT = scene; for any other treatment quote the fold rows the gate table marks as gated for it, and a row printed `[INFO]` is not gated; native platforms ios/android: device screenshots, fold rows N/A): compare the first-viewport screenshot to the benchmark descriptions (ara-bar: the restaurant at night, 10+ drawn objects, 3+ depth layers, a light source, brand painted on the sign, real phone number in the art; hitataekni: a full blueprint sheet with grid, coordinates, traced unit, dimension lines, callouts, a title block holding the real name, year, address and phone). Score: (a) the hero is a scene or sheet, not a boxed diagram, single icon, empty grid or text-only (drawing covers >=55% of the viewport at 1440x900, >=45% at 390x844; >=5 distinct subject objects across >=3 depth layers; headline set into the art; >=2 dossier facts rendered inside the art); (b) richness floor: filled shapes, one consistent light source, texture, people or traces of use, 4 to 7 inks; (c) page graphic budget: >=3 more drawn plates down the page, each tied to a different fact group, plus micro-scale marks in the same hand. Run `node scripts/fold-check.mjs <built page> --mode <mode> --treatment <HERO TREATMENT from the contract>` (or `check.mjs --fold=<page>`) and cite its metric lines; its FAILs are evidence, the eye decides what counts as a distinct object. Under the scene treatment a text-only or boxed-diagram hero in persuade is a FAIL. List what is missing (objects, layers, light, texture, facts-in-art).

- **P6 fold checks** (the seven rows and the benchmark comparison apply only when HERO TREATMENT = scene; under other treatments RECAPTURE for a missing row only if that row is gated) — Named fold checks the evaluator must report, each PASS/FAIL with the `fold-check.mjs` line quoted (a missing line is a RECAPTURE for a scene build with a built page): (1) **Text collisions** (`collisions-desktop`, `collisions-phone`): no visible text box, HTML or svg `<text>`, overlaps another or is more than 30% covered by an opaque later-painted element; name the two texts on a FAIL. (2) **Dead zone** (`dead-zone`): no near-uniform-colour rectangle larger than 20% of the desktop fold; cite its size and position. (3) **Card over art** (`card-over-art-desktop`, `card-over-art-phone`): no translucent (alpha < 0.95), backdrop-filter or solid-background element with text covering more than 6% of the hero art area; headline, phone, hours and the primary action live on drawn surfaces inside the art (a sign, plate or title block in the svg is fine), never on a card floating over it. (4) **Art down the page** (`art-down-page`): at least 60% of the sections below the fold (contact/footer excluded) carry a drawn plate at least 40% of their width. (5) **Full bleed** (`full-bleed-desktop`, `full-bleed-phone`): the hero art box spans at least 95% of the viewport width with margins of at most 3% each side; a framed picture, card or polaroid with page margins fails; name the art box and its margins. (6) **Rendering depth** (`rendering-depth`): in the desktop hero art area the luminance range p95 - p5 is at least 90 and at least 5 of 16 luminance bins hold at least 2% of the pixels; flat fills with thin uniform strokes read as clip art. The flat-block texture number is printed for the report but not gated. (7) **Plate size** (`plates-size`): at least 50% of the below-fold section plates are at least 35% of the section width, at least 280px tall and carry at least 3 value steps; name the thin, small or pale ones. Under the scene treatment any of these seven FAILing is a Specificity FAIL under P6 and is listed in the fix batch; under other treatments only the rows the gate table marks as gated count and the others are informational.

Specificity PASS requires 5 of 6. Two or more FAILs, a P2 FAIL (except utility), or a P6 FAIL under the scene treatment → REBUILD, written as "promised <SIGNATURE GRAPHIC>, shipped <what exists>". No dossier supplied → say so; P1 to P4 and P6 are then judged against the brief only and flagged lower confidence.

**Sibling Variety** (only when a SIBLINGS block is appended): concept angle, world, archetype and device technique must each differ from every sibling, and the silhouettes must not be confusable. Any pair matching on 2 or more axes → FIX, naming which variant to re-roll.

### Step 6 — Disposition (computed, not a fresh gut call)
- **RECAPTURE**: `SEED KEY:` missing, or evidence (source, screenshots) insufficient to complete Steps 2-5b, or a persuade/experience build arrived with no screenshots. Say exactly what is missing and how to get it.
- **REBUILD**: any structural BROKEN (ARCHETYPE, a GRAMMAR rule, FIRST VIEWPORT, THESIS "promised X, shipped Y"), or distinctiveness failed 2+ tests, or project specificity failed 2+ tests, or no signature element was found (P2, except utility), or a DIRECTIVE was broken. Name the broken promise and what must change structurally.
- **FIX**: only cosmetic BROKENs and/or mechanical FAIL/WARNs, structure sound, distinctiveness ≥4/5. List every fix in one batch: this is the only fix round that will happen.
- **SHIP**: nothing above triggered.

## Required output format

```markdown
# Design Evaluation — <SEED KEY>

## Observations
- …(≥8)

## Contract Audit
| Field | Verdict | Evidence |
|---|---|---|

## Tells Found
- …

## Mechanical Craft Floor
- carried from check.mjs: … ; spot-checks: …

## Distinctiveness
| Test | Verdict | Evidence |
|---|---|---|
Distinctiveness: PASS | FAIL (n/5)

## Project Specificity
| Test | Verdict | Evidence |
|---|---|---|
| P1 Subject-swap | | false items: … |
| P2 Signature element | | treatment, name, file, fact ids, scales |
| P3 Graphics carry information | | element + fact |
| P4 Trade credibility | | element |
| P5 Art craft | | screenshot region |
| P6 Richness vs benchmark | | (scene only; else gated fold rows) fold-check lines; missing objects/layers/light/texture/facts-in-art |
Specificity: PASS | FAIL (n/6)

## Contract rows
Hero treatment: <from the contract, or "not stated">
Directive compliance: <each DIRECTIVES line kept | broken, with evidence, or "none">

## Sibling Variety
(only when SIBLINGS present: one row per sibling, axes matched, which variant to re-roll)

## Disposition: SHIP | FIX | REBUILD | RECAPTURE
- FIX → the complete batched list
- REBUILD → which structural promise broke ("promised X, shipped Y") and what must change
- RECAPTURE → exactly what evidence is missing
```

## Final reminder
Do not soften a structural gap into a polish note. Do not let clean contrast numbers talk you into leniency on distinctiveness or on project specificity (a different look is not the same as a look that belongs to this client): craft and sameness are independent failures, and a beautifully executed identical design still fails this review's purpose. Conversely, do not penalise a genuinely unusual choice because it is unfamiliar to you: name the specific problem with it, or pass it.
