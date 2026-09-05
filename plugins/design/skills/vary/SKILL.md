---
name: vary
description: Design frontend UI that looks different every run and still looks designed. An external dice roll (scripts/roll.mjs) ASSIGNS a visual world, page skeleton, colour strategy, OKLCH palette seed and two verified free fonts from catalogs of 47 worlds, 18 archetypes, 120 hue-balanced seeds and 160+ verified faces; the model commits fully, a mechanical craft floor (scripts/check.mjs) and a separate evaluator subagent judge distinctiveness and contract-keeping. Use WHENEVER building, redesigning, mocking up or restyling any UI — landing page, marketing site, dashboard, admin, docs, portfolio, app screen, component set, email, artifact — and whenever the user says design, UI, frontend, make it look good, not generic, not AI slop, something different, new vibe, new palette, new fonts, surprise me, bold, distinctive, or complains that designs look the same. Also use for "give me another direction", "re-roll", "safer", "bolder", "play it straight". Not for backend-only work or pure copy edits.
user-invocable: true
argument-hint: "[brief] [--mode persuade|operate|read|experience] [--reroll] [--safer|--bolder|--canon]"
---

# vary — design that is assigned, not chosen

Claude's design output collapses to a mode: indigo, Inter, centred hero, three cards. Told to avoid those, it collapses to the next mode: cream + serif + terracotta, or near-black + one neon, Space Grotesk, bento + glass. The cause is not a lack of ideas. The model derives seven varied directions and then argmax-picks the same one every time; asking it to "choose differently" reverted in 27 of 30 measured runs. Naming things to avoid makes it worse: a named font or hex gets *more* activation, not less.

Two things fix this, and this skill is built around them:

1. **An external roll assigns the direction.** `scripts/roll.mjs` picks world → skeleton → colour strategy → palette seed → fonts, each conditioned on the last, from catalogs in `data/`. Claude executes the assignment. It does not pick from a menu.
2. **Variety must move on two axes.** A new palette on the same centred-hero skeleton is the same design. The roll moves the skeleton (archetype) and the lineage (world) together; skin follows.

Then: commit fully, guard later. Craft rules are loaded only *after* the contract is written, because guardrails mixed into the brief measurably hedge the result. Review is done by a separate identity auditing the build against its own contract, because self-review rubber-stamps.

(The measurements above come from Impeccable's instrumented v4 campaign, impeccable.style/research, and from NeurIPS 2025 work on ironic negation, arXiv 2511.12381. The research trail for this skill is in its forge workspace.)

---

## Step 0 — Read the surface, not the product

Before rolling, settle these in one short block (write them; they feed the roll):

- **Mode** of *this surface*: `persuade` (visitor decides and acts: landing, pricing, campaign), `operate` (completes a task: app, dashboard, settings, forms, checkout), `read` (understands: docs, articles, changelog), `experience` (is inside the work: portfolio, gallery). A dev tool's landing page is persuade; a fashion house's docs are read. Mode gates how bold the roll may be. Operate and read surfaces get quiet worlds and conventional skeletons; their distinctiveness lives in details.
- **Platform**: `web`, `ios`, `android`. Phones exclude pointer-dependent skeletons.
- **Locks** — anything the user or the repo has already decided: brand hex (`--lock palette=#…`), a required font, required scripts (`--scripts latin,cyrillic`), no webfonts (email, React Native → `--no-webfonts`), longevity (`--longevity campaign` allows fast-decaying looks). A brief that pins an aesthetic ("make it Bauhaus", "keep our brand") beats the roll: `--lock world=bauhaus`.
- **Existing design system?** If the repo has `DESIGN.md`, a token file, a Tailwind theme with custom colours, or styled shared components, this is **extend mode**: **MANDATORY — read [`references/extend-mode.md`](references/extend-mode.md)** and follow it instead of Step 1. A component or section inside an established surface always inherits that surface. Never turn a local addition into a new identity.
- **Scene sentence**: who uses this, where, under what light. This decides light or dark, not the category (`--scene light|dark` once decided).
- **Thin category?** If the subject has little cultural material of its own (SRE tooling, invoicing, generic B2B), **read [`references/thin-domain.md`](references/thin-domain.md)** before rolling: it produces a `--grounded` candidates file.

Ask the user at most one round of two or three questions, and only for facts that change the work (audience, the real proof/content available, what must not change). Never ask for CSS values or an aesthetic lane.

## Step 1 — Roll

```bash
node <skill-dir>/scripts/roll.mjs --mode <mode> --platform <platform> [--scene light|dark] \
  [--scripts latin,cyrillic] [--lock palette=#hex] [--lock world=<id>] [--no-webfonts] \
  [--longevity long|campaign] [--project <repo-root>] [--grounded candidates.json]
```

`<skill-dir>` is this skill's directory. `--project` points the anti-repeat memory at the repo (last 3 picks per axis demoted there; last 8 globally), so the same font or world does not come back next session.

**The assignment is unrefusable.** Writing any UI markup, styling or component code before the roll has run and its comment block is pasted into the artifact is a contract violation. Do not read the catalog files to pick something yourself: that is the exact failure this skill exists to remove.

**Re-roll on the model's own initiative only for named factual grounds**: the roll printed a `[FAIL]` coherence row that a single-field lock cannot fix; the assigned font lacks a script the brief needs; the world's `avoid_for` names this exact audience. "This doesn't feel right for the category" is not grounds; that is the argmax talking. The **user** may re-roll freely: `--from <key> --reroll 1` (then 2, 3…). Steering: `--register safer` (slow-decay worlds, quiet strategies) or `--register bolder` (experience-grade worlds) on a re-roll. `--canon` is the standing exit: the category standard, played straight, at full craft; never recommend it, always allow it. After two consecutive re-rolls, ask what quality is missing rather than rolling a third time.

## Step 2 — Contract

Paste the printed `<!-- … -->` block **verbatim** as the first child of `<body>` in the root layout (never inside a slotted child component; some compilers strip those). Then fill the three model-authored lines:

- **SCENE**: the one sentence from Step 0.
- **FIRST VIEWPORT**: what is where, at what scale, where the primary action sits — derived from the ARCHETYPE line, not from the category's usual hero.
- **THESIS**: the one idea this surface owns, and the category-default arrangement it refuses. If it reads like a mood ("clean, confident"), it is not decided yet.

The GROUNDED ANTECEDENT line (thin-domain runs only) supplies material and thesis; the WORLD supplies grammar and skeleton; product facts win every conflict.

## Step 3 — Build, fully committed

**MANDATORY — READ ENTIRE FILE NOW, not earlier:** [`references/build-craft.md`](references/build-craft.md). It holds palette composition from the seed, type loading, motion, states, browser surfaces and the craft floor. It is loaded after the contract on purpose.

While building:

- **Borrow the skeleton, not the clothes.** Structure comes from the ARCHETYPE and the world's GRAMMAR. A committed surface over the category's standard marketing grid is the most common failure and the hardest to see.
- **Full commitment beats a hedged half.** A perfectly executed conventional page beats a half-executed distinctive one; a fully executed distinctive one beats both. Use all the weights of the assigned faces. Let the colour strategy own the page area it claims.
- **One authored motion moment** (the MOTION MOMENT line). Nothing else animates on entrance.
- **Real content.** Author illustrative material at full fidelity and label it synthetic where a visitor could mistake it; never invent prices, customers, testimonials, statistics or capabilities.
- **Effort clusters where the content matters.** Everything equally detailed means nothing is important.
- When the world's grammar conflicts with a craft-floor rule, the grammar wins on aesthetics and the floor wins on accessibility, states and keyboard.

Build the whole thing, then inspect once in a batched round (desktop and mobile together), fix everything that round shows in one batch, and stop polishing.

## Step 4 — Mechanical check

```bash
node <skill-dir>/scripts/check.mjs <built files or dir> --json
```

Fix every `FAIL` in one batch (contract present, contrast, focus-visible, 9 states, reduced motion, image dimensions, font weights, arbitrary Tailwind values, AI vocabulary and em-dash density, template tells). Never satisfy a check by loosening it. Keep the JSON: the evaluator reads it.

## Step 5 — Separate evaluation

Mandatory for anything the user will ship; skippable only when the user said "just something quick".

1. Read [`evaluator-prompt.md`](evaluator-prompt.md) and copy it **verbatim** into a new subagent (`general-purpose`, `model: sonnet`, `mode: bypassPermissions`). Append: the original brief, the absolute paths of the built files, the path of the `check.mjs` JSON, and screenshot paths if any (`npx agent-browser` or the browser MCP when available; otherwise say none).
2. Do **not** pass this SKILL.md, the references, the catalogs, or any of the generating conversation. The evaluator audits the build against its own contract block and tests distinctiveness; feeding it the generator's rules collapses that separation.
3. Dispositions are closed: **SHIP / FIX / REBUILD / RECAPTURE**. FIX gets exactly one batched round, re-checked by the evaluator, not by the builder. REBUILD means a structural promise broke (skeleton, a grammar rule, thesis vs execution): return to Step 3 with the same contract. RECAPTURE means the evidence was bad (contract stripped, no source): fix the evidence, not the design.
4. The builder never marks its own SHIP. If no subagent tool exists, run `check.mjs`, re-read only the contract and source in a fresh turn, cap the outcome at FIX, and tell the user an independent review did not happen.

Report to the user: the SEED KEY (so the roll is reproducible), the world and skeleton in one line, the disposition, and the re-roll command.

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
| Thin category | `references/thin-domain.md` → `--grounded` |
| Needs Cyrillic/Greek/Vietnamese body text | `--scripts latin,cyrillic` (filters the font pool before rolling) |
| Email / RN / no webfonts | `--no-webfonts` (system stack; hierarchy from weight and size) |
| Coherence row FAIL | Lock the failing axis and re-run; never proceed on a known-bad assignment |
| `roll.mjs` cannot load data | Stop and report; never fall back to picking by taste |

## What breaks this skill

- **Choosing among options.** Presenting three directions and picking one, or "picking the boldest", reinstates the argmax. The roll assigns; the user may steer.
- **Guardrails inside the brief.** Loading `build-craft.md` before the contract, or writing "be bold but not too bold", produces the hedged 65% page.
- **Naming replacements.** Writing "use Satoshi or Geist instead of Inter" anywhere creates the next default. Fonts come from the roll.
- **Skin-only variety.** New font and palette on the category's standard grid. The evaluator's silhouette test exists to catch this; do not argue with it.
- **Randomness on an operate surface.** A maximalist checkout is worse than a plain one. The mode gate is not optional.
- **Independent axes.** Picking a palette from one list and a style from another produces dark style + light palette contradictions. Everything is conditioned on the world.
- **Self-certification.** The thread that built it may not ship it.
- **Premium by effect.** Gradient text, decorative glass, uniform `rounded-2xl` and `shadow-lg` signal a template, not craft. Weight, size, position and material carry hierarchy.
