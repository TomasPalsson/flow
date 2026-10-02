# Art crew and critic

One session that plans, draws every plate, builds and polishes produces thin art and template sections below the fold. The benchmarks came from a dedicated art process with many look-and-fix rounds. This file splits that process: illustrator subagents draw the plates in parallel (Step 3a), a fresh critic scores the built page (Step 4b). `graphics.md` is the engine; this file is the dispatch, the checklists and the rubric.

## 1. Dispatch (Step 3a, after the art brief)

Dispatch only for treatment = scene (pattern: the lead draws, no crew). Use the Agent tool (`subagent_type: general-purpose`, `model: sonnet`, `mode: bypassPermissions`), all illustrators in ONE message so they run in parallel: one for the hero scene, one per section plate, capped at 6 (merge the smallest plates into one illustrator beyond that). Each illustrator is handed ONLY:

- the absolute path of `.vary/art-brief.md`;
- its plate's row from the brief (subject, fact ids and facts, skeleton, size at desktop and phone, objects-table rows);
- the absolute paths of the style object file and the core kit (`art/styles.js`, `art/core.js`), and of `art/finish.js` and `art/objects.js` (the lead creates both before dispatch; illustrators import them, never edit them);
- the path of this file, and the output path `art/<plate>.js` it owns. Besides that file it may write only scratch renders (a harness html or script and PNGs) under `.vary/art-shots/<plate>/`, named `desktop.png` and `phone.png` at the real plate sizes from its row.

The lead does not redraw. It integrates what comes back. If the Agent tool is unavailable, the lead draws the plates itself in the same order (hero, plates, micro) and runs section 3 on each.

## 2. Illustrator brief (copy, fill the braces)

```
You are an illustrator on a design team. Draw ONE plate: {PLATE NAME}.
Read: {ART_BRIEF_PATH}, {CORE_PATH}, {STYLE_PATH}, {FINISH_PATH}, {OBJECTS_PATH}, and {ART_CREW_ABS_PATH} section 3.
Your row: {SUBJECT / FACTS / SKELETON / SIZES}.
Write {OUT_PATH} and scratch files under {SHOTS_DIR} only: {OUT_PATH} is a pure function (S, r, W, H) -> svg string, seeded, colours only via swatch names from the style object.
Shared with the other plates (do not change): ground line at {GROUND_Y}% of plate height, key light from {LIGHT_DIR}, glow {GLOW_SOURCE}, grain {GRAIN}, the style object swatches. The lead fills these from the brief's shared plate frame.
Loop: render at real size ({W}x{H} desktop and phone) with Playwright (or rsvg-convert) to {SHOTS_DIR}/desktop.png and phone.png, Read the PNGs, run the checklist, list what is wrong in concrete terms, fix, re-render. Do 2 render-and-fix rounds (3 for the hero plate) and stop within about 20 minutes; a finished plate beats a perfect one.
Return: the module path, the final PNG path(s), the checklist with pass/fail per line, and any open item. Do not touch any other file.
```

## 3. Self-critique checklist (every render)

1. Objects, not boxes: each object has a real silhouette and its parts (roof line, bogies, spine, headband), never a box or pill standing for a thing.
2. Posture: every person has a stance or gesture, a cast shadow, hands doing something; no pill figures.
3. Shared ground and light: objects stand on one ground line, cast shadows fall the same way, one key light and one glow; nothing floats.
4. Values: at least 3 steps per material, the brightest value on the focal fact.
5. Texture: grain 3-8%, hatching, halftone or paper; no flat fills with thin uniform strokes.
6. Facts in the art: the plate's dossier facts are drawn or lettered in it (numbers, names, dates).
7. No dead space: no empty region over 20%; no tool or prop without context (a surface, a hand, a trace of use).
8. Craft: no text clipped by the svg edge, no label over an object, every dial, axis or scale monotonic with real labelled values, every callout leader ends on its object.
9. Size: the plate is at the size in the brief (at least 40% of section width, 280px tall).

## 4. Integration rules (lead)

- One shared ground line and one light direction across all plates; the brief's shared plate frame (graphics.md §7 step 1, item 10) fixes both and the lead rejects a plate that breaks them.
- Plate sizes come from the brief; do not rescale a plate to fit a layout, change the layout.
- Plates are composed unchanged. A needed fix goes back to the same illustrator (or is a one-line swatch or size edit); the lead does not redraw.
- Re-render the gallery once with every plate together and read it once, apply one fix pass, then start page code.

## 5. Critic (Step 4b)

A FRESH subagent (Agent tool, `general-purpose`, `model: sonnet`), never the builder, never one that saw the generating conversation. Give it the audience mood need line from the art brief (fills {MOOD_NEED}) and the contract's hero treatment (fills {TREATMENT}), plus: desktop and phone fold screenshots, desktop and phone full-page screenshots (absolute paths), the `.vary/dossier.json` facts, and the prompt below. Withhold SKILL.md and the other references.

```
You are a hard design judge. Read the screenshots at {PATHS} and the facts at {DOSSIER}. Score each 1-10:
- specificity: is every picture a function of this client's own facts, or could it be any client's?
- graphics: the signature visual, judged against the {TREATMENT} bar (scene: richness and finish of the drawings; otherwise the matching `graphics.md` §9-§12 checklist).
- craft: collisions, clipping, overlays, hidden content, scales, callouts.
- mood: does the concept, world and palette fit the audience's mood need ({MOOD_NEED} from the art brief, e.g. children: bright, safe, daytime; bereavement: calm, quiet, dignified; B2B lab: precise, trustworthy)? A world that breaks it scores mood 1-3 and is a FAIL regardless of the other scores.
- headline: is there a real headline, value line and action in the fold (scene: on a drawn surface)?
- wow: would a stranger remember it?
Anchors show the quality level, not the subject matter: a client from a different domain is judged against the same level of detail, not against pizza or air handlers. 9-10: for scene, {PASTE the "What was drawn" text of graphics.md §0b rows 1, 2, 5 and 7}; for other treatments, {PASTE the matching graphics.md §9-§12 bar and checklist}. 4-5: pill figures; boxes standing for objects; template sections (scene only: card left, table right, pill CTA, divider, repeated); text clipped by the nav, viewport or svg edge; dead space; a dark overlay left over the hero; a hero missing in the full-page shot.
Judge only what the screenshots show; quote what you see. "mean" is the arithmetic mean of the four scores specificity, graphics, craft, wow (mood is reported separately) to one decimal. If an image is unreadable, return {"error":"unreadable: <path>"} instead of guessing. Return JSON: {"specificity":n,"graphics":n,"craft":n,"wow":n,"mood":n,"mood_fail":bool,"mean":n,"fixes":[5 items, highest impact first, each naming the element and the concrete change]}.
```

Mood FAIL: if `mood_fail` is true the lead stops building on this world, re-rolls with `--lock concept=<id>` (a concept that serves the mood) and rebuilds before any other fix. Blocking craft fails (fold-check rows collisions, clipped-text, hidden-content, stray-overlay, duplicate-content, page-overflow, meta-copy, headline-on-fold (title-on-fold for operate/read), plus headline-in-scene for scene only) must be PASS before shipping; the time budget never excuses them.

Loop: the lead applies the 5 fixes (plates go back to their illustrator), rebuilds, re-shoots, and spawns a NEW critic. Stop when the mean is 7.5 or more, or after 2 critic rounds. Open items go into NOTES.md as `critic: open — <item>`; the page ships. If no subagent tool exists, the lead scores itself against the same rubric, caps the outcome at FIX, and says the independent critic did not run.
