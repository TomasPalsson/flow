---
name: graphics
description: 'Draws custom graphics for websites and apps as code: icon sets, custom icons, spot illustrations, cartoons and mascots, hero or section art, drawings, SVG art, diagrams, maps, patterns, infographic art, empty-state illustrations, and brand objects (price tags, coupons, tickets, stamps, labels drawn as the trade''s own artefacts). Picks a different illustration style every project, checks each asset at real size and delivers SVG files with alt text. Use when the user says "make me an icon set", "draw a cartoon of...", "illustrate this", "make it less generic with graphics". The design and vary skills call it when a page needs custom graphics. Not for photo editing or raster image generation.'
user-invocable: true
argument-hint: "[brief file or what to draw]"
---

# Graphics

Custom drawings made in code (SVG, or small JS modules that render SVG) that make a site or app clearer and more recognisably its own.

## Priority order

1. **UX job first.** Every asset names the job it does for the user or the brand: an icon that speeds up scanning, a diagram that explains a process, a map that shows where, an empty-state drawing that says what to do next, a price tag or coupon that is the real container for the price. An asset with no job is cut, not polished.
2. **Fit to the client's real facts.** Draw their things, their words, their numbers. Never invent facts.
3. **Creativity and variety.** A different look every project, chosen from the style catalog and fitted to the page's tokens. No default look.

## Input: the brief

Callers pass `.vary/graphics-brief.md`, written as:

- **Project**: one line; the audience and the mood they need.
- **Page system**: palette tokens (hex), fonts, radius and stroke feel, light or dark, and any user directives ("no illustrations" means no request is made at all; if you are invoked anyway, stop and say so).
- **Assets**: one row each: `id`, `kind` (icon-set | spot | hero | section | diagram | map | object | pattern), what it shows, which facts it carries, the UX job, size and aspect, placement.
- **Output dir** (default `assets/art/`).

Invoked directly by a user with no brief: write the brief yourself from the request and the repo. If a site exists, read its tokens and fonts (CSS variables, the Tailwind config, the theme file) and any existing art. If the request is a single asset, one row is enough. State the assumptions you made in the summary.

## Step 1: Style

```
node <GRAPHICS>/scripts/pick-style.mjs --mood <words> --kinds <kinds> --project <repo-root>
```

`<GRAPHICS>` is this skill's own directory: the absolute path on the "Base directory for this skill" line Claude Code printed when this skill loaded (or `${CLAUDE_PLUGIN_ROOT}/skills/graphics` when that variable is set). Substitute it literally. **Never search the filesystem for the script.** If `<GRAPHICS>/scripts/pick-style.mjs` is missing, stop and say so. `--mood` takes the brief's mood words (playful, calm, technical, premium, warm, bold, editorial, kids, civic, natural, nostalgic); `--kinds` takes the asset kinds from the brief. Add `--from <key> --reroll <n>` to replay or re-deal.

It prints one style from `data/styles.json`. Commit to it. Rules:

- The caller's palette tokens and fonts override the style's default palette; the style supplies the drawing language (stroke, fill, shading, texture, simplification), not the colours.
- A user directive ("flat and friendly", "like a woodcut") or an existing site's drawing style overrides the pick: use `--lock style=<id>`, or if no catalog entry matches, describe the directive's style yourself. In extend mode, copy what is there, its bans included: if the existing art has no gradients, blur or shadows, neither does the new art.
- If the style fights the page (a neon-on-dark style on a pale calm site), re-roll rather than force it.

Write a one-page style sheet `.vary/graphics-style.md`: style id; palette swatches taken from the page tokens (named, with hex); stroke weight; corner treatment; shading rule; texture rule; how people and objects are simplified; what is banned. Every asset follows this sheet.

## Step 2: Draw

- **Small jobs** (an icon set, or 1-3 assets): the lead draws them itself.
- **Bigger jobs**: dispatch illustrator subagents in parallel, one per asset or asset family, capped at 6, as described in `references/art-crew.md`.
- **Schematic diagrams** (architecture, AWS, flowchart, sequence, state, ER, timeline, chart forms): draw them with the `design:diagram` skill's rules (`<GRAPHICS>/../diagram/SKILL.md`), skinned with this style sheet's palette and fonts. Drawn mechanisms (cutaways, exploded products), maps and infographic art stay here.
- Engine, kit and technique catalog: `references/graphics.md`. Icon sets: `references/icons.md`. Read only the sections you need.
- Draw from the facts in the brief (names, numbers, places) and name each object's parts so it has a real silhouette, not a box.
- A brand object only shows information the brief gives. A field the facts cannot fill is left off the object, never drawn empty.
- Objects the trade already has (a price tag, a coupon, a ticket, a stamp, a label, a receipt) are drawn as that object, and can be the real container for the real text, which stays live HTML text when it must be read, copied or clicked.

## Step 3: Check

1. Render every asset at its real sizes (desktop and phone; icons at 16, 24 and 32px, 1x and 2x) with Playwright, `rsvg-convert` or the browser MCP. **Read the PNGs.** Fix what is wrong: clipped text, collisions, boxes standing for objects, details lost at size. When fixing, refine, don't add: sharpen the shape, spacing and labels already drawn before adding a new element.
2. Run one critic subagent per `references/art-crew.md` section 5 on the renders. Apply its fixes. Stop at a mean of 7.5 or after 2 critic rounds. If no subagent tool exists, score yourself against the same rubric and say the independent critic did not run.

## Step 4: Deliver

- Files in the output dir (default `assets/art/`): SVG files, a sprite for icon sets, or JS modules rendering SVG, plus a preview sheet for sets.
- `assets/art/GRAPHICS.md`: one row per asset with file, size, alt text (or `aria-hidden` for decoration), and placement. Include the style id and the style sheet path, and any `open:` items from the critic.
- Return a short summary to the caller: files, the style picked and why, anything the caller must do to integrate. The caller integrates; this skill does not edit the page.

## Accessibility and performance

- Alt text, or `aria-hidden="true"` for decoration. Meaningful inline SVG gets `role="img"` and `<title>`. Icon-only controls get an `aria-label` on the control.
- No meaning by colour alone; contrast of informative lines and any lettering is checked (4.5:1 for text, 3:1 for graphics).
- Animated art respects `prefers-reduced-motion` and shows its finished state without JS.
- Keep each SVG small (aim under 30KB for a spot, under 100KB for a hero); generate repeated art from code, not copies.
- Inlined SVGs carry no colliding ids (`<clipPath>`, `<filter>`, gradients): namespace them or avoid them. Use `currentColor` for icons.
- Text a user must read stays live text, not paths.

## What breaks this skill

- One default look: the same style, scene or palette project after project.
- Decoration with no job.
- A style that fights the page's tokens, or colours invented outside them.
- Boxes standing for objects; inconsistent strokes or corners in one set.
- Drawings with invented facts (numbers, names, places, certifications).
- Making the full-bleed scene the default; a scene is one option, chosen only when the concept needs it.
- Ignoring a "no illustrations" directive, or redrawing real photos and product screens the page already carries.
