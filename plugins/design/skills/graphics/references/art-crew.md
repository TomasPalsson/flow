# Art crew and critic

One session that plans, draws every asset and polishes them produces thin, uneven art. For bigger jobs this file splits the work: illustrator subagents draw assets in parallel (Step 2 of the skill), a fresh critic scores the rendered set (Step 3). `graphics.md` is the engine; this file is the dispatch, the checklists and the rubric. It applies to any graphics job: an icon set, spot illustrations, section art, a hero, diagrams, maps, patterns or brand objects.

## 1. Dispatch

Small jobs (an icon set, or 1-3 assets) are drawn by the lead; no crew. Bigger jobs use the Agent tool (`subagent_type: general-purpose`, `model: sonnet`, `mode: bypassPermissions`), all illustrators in ONE message so they run in parallel: one per asset or asset family (an icon set is one family), capped at 6 (merge the smallest assets into one illustrator beyond that). Each illustrator is handed ONLY:

- the absolute paths of `.vary/graphics-brief.md` and `.vary/graphics-style.md`;
- its asset's row from the brief (id, kind, subject, facts, UX job, size at desktop and phone, placement) and, where the asset has objects, its objects-table rows;
- the absolute paths of the shared kit files (`art/styles.js`, `art/core.js`, and `art/finish.js` / `art/objects.js` if the lead created them; illustrators import them, never edit them);
- the path of this file, and the output path it owns (`art/<asset>.js` or `assets/art/<asset>.svg`). Besides that file it may write only scratch renders under `.vary/art-shots/<asset>/`, named `desktop.png` and `phone.png` at the real sizes from its row.

The lead does not redraw. It integrates what comes back. If the Agent tool is unavailable, the lead draws the assets itself in order of UX weight and runs section 3 on each.

## 2. Illustrator brief (copy, fill the braces)

```
You are an illustrator on a design team. Draw ONE asset: {ASSET NAME}.
Read: {BRIEF_PATH}, {STYLE_SHEET_PATH}, {KIT_PATHS}, and {ART_CREW_ABS_PATH} section 3.
Your row: {KIND / SUBJECT / FACTS / UX JOB / SIZES}.
Write {OUT_PATH} and scratch files under {SHOTS_DIR} only. Colours come from the style sheet's swatches (the page tokens), never invented.
Shared with the other assets (do not change): {SHARED_RULES: stroke weight, corner treatment, shading rule, light direction and ground line where the style uses them}.
Loop: render at real size ({W}x{H} desktop and phone) with Playwright (or rsvg-convert) to {SHOTS_DIR}/desktop.png and phone.png, Read the PNGs, run the checklist, list what is wrong in concrete terms, fix, re-render. Do 2 render-and-fix rounds (3 for the most important asset) and stop within about 20 minutes; a finished asset beats a perfect one.
Return: the output path, the final PNG path(s), the checklist with pass/fail per line, and any open item. Do not touch any other file.
```

## 3. Self-critique checklist (every render)

1. UX job: the asset does the job named in its row at its real size (an icon is clear at 24px, a diagram is readable on a phone, a state illustration says what happened).
2. Objects, not boxes: each object has a real silhouette and its parts, never a box or pill standing for a thing (fill it black and look).
3. Style sheet: stroke weight, corners, shading and texture follow the sheet; the colours are the page tokens; nothing the style bans.
4. Set consistency: next to the other assets it reads as one hand (same grid, weight, level of detail).
5. Values (shaded styles only): at least 3 steps per material, the brightest value on the focal part; one light direction.
6. Facts: the row's facts are drawn or lettered correctly; nothing invented.
7. Craft: no text clipped by the SVG edge, no label over an object, scales and axes monotonic and labelled, every callout leader ends on its object, no id collisions.
8. Space: no dead region over 20% in a hero or section piece; no prop without context.
9. Size: the asset is at the size in the brief.
10. Accessibility: alt text or aria-hidden decided, no meaning by colour alone, contrast of any lettering at least 4.5:1.

## 4. Integration rules (lead)

- One style sheet across all assets; the lead rejects an asset that breaks it.
- Sizes come from the brief; do not rescale an asset to fit a layout, report that the layout should change.
- Assets are composed unchanged. A needed fix goes back to the same illustrator (or is a one-line swatch or size edit); the lead does not redraw.
- Render the gallery once with every asset together and read it once, apply one fix pass, then run the critic.

## 5. Critic

A FRESH subagent (Agent tool, `general-purpose`, `model: sonnet`), never the drawer, never one that saw the generating conversation. Give it the asset renders (absolute paths, desktop and phone, plus each icon at 16/24/32px where relevant), the style sheet, the brief's asset rows and the client's facts. Withhold SKILL.md and the other references.

```
You are a hard art director. Read the renders at {PATHS}, the style sheet at {STYLE_SHEET} and the brief at {BRIEF}. Judge each asset and the set. Score each 1-10:
- ux_job: does each asset do the job named in its row, clear at its real size, readable on a phone, accessible (contrast, no meaning by colour alone)?
- consistency: do the assets follow the style sheet and the page tokens, and read as one hand?
- craft: silhouettes not boxes, clean geometry, even strokes, value steps where the style uses them, no collisions, clipping or stray overlap.
- fit: is every picture a function of this client's own facts, or could it be any client's? Is anything invented?
- variety: does it avoid the default look (generic clip-art, the same scene and palette every project)? Does the style suit the audience's mood?
Anchors describe quality, not subject matter; judge a client from any domain against the same level of detail. 9-10: a stranger could tell what the business is from the art; every asset clearly in one hand; crisp at 24px for icons; each asset's job is obvious. 7-8: solid and consistent with one or two weak assets. 4-5: generic clip-art, boxes standing for objects, inconsistent strokes or corner radii, clipped text, decoration with no job. 1-3: unreadable at size, contradicts the brief, or invents facts.
Judge only what the renders show; quote what you see. "mean" is the arithmetic mean of ux_job, consistency, craft, fit, variety to one decimal. If an image is unreadable, return {"error":"unreadable: <path>"} instead of guessing. Return JSON: {"ux_job":n,"consistency":n,"craft":n,"fit":n,"variety":n,"mean":n,"fixes":[up to 5 items, highest impact first, each naming the asset and the concrete change]}.
```

Loop: the lead applies the fixes (assets go back to their illustrator), re-renders, and spawns a NEW critic. Stop when the mean is 7.5 or more, or after 2 critic rounds. Open items go into `assets/art/GRAPHICS.md` as `open: <item>`; the assets ship. If no subagent tool exists, the lead scores itself against the same rubric and says the independent critic did not run.
