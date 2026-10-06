---
name: concepts
description: Step 0b of vary and design. How to turn the dossier into 4-7 grounded concepts (each the site as a physical thing from this trade or place, each a different angle on the business), written to .vary/concepts.json for roll.mjs to pick from. Includes the physical-object method and neutral worked examples across very different clients and treatments.
---

# Concepts: the site as a thing from this trade, or the client's own pictures, product or numbers

A concept is the site as a thing from this trade, or this client's own pictures, product or numbers set with a point of view. It is a one-sentence idea in which the site **is** that thing. The roll picks one of your concepts, so write every one as if it will win.

- A pizzeria: the site IS the paper menu on a dark table.
- An HVAC supplier: the shop as a set of engineering drawing sheets.
- A hardware chain: a plain, fast product grid with one clear search. A plain usable concept is as valid as any other.

## 1. Method

**a) List the business's halves.** Who uses it, when, and for what. A pizzeria with a bar: the cosy evening room, the family's Friday take-away, the sports bar on match night, the street-corner pride of a neighbourhood landmark. Each half is a different angle. Four concepts that are four palettes of one half are not four angles.

**b) Apply the physical-object method to each half.** Ask: *what would this be as a physical artefact, and what did that world look like before the web?*

1. **Name three real antecedents, not one.** The first is the cliché (bank → vault; fitness → gym poster; dashboard → glass cards). The good answer lives at #2 or #3.
2. **Extract a constraint, not a texture.** A ledger is not "beige and lined"; it forces every figure to reconcile in a paired column. A cockpit panel is flush, not floating. A rulebook numbers things because they are cross-referenced. The constraint becomes a layout rule.
3. **Include graphic traditions, not only objects**: the notation, publications, identity programmes, data graphics and interfaces this audience reads daily (a surveyor's field book, a racing programme, a broadcast lower-third, a pharmacy label, a shipping manifest).
4. Reject any antecedent that is the category's standard page or its predictable opposite.

**c) Prefer the trade's own documents and hardware**: datasheet, drawing sheet, guest check, kitchen ticket, price tag, route card, work order, handbill. The dossier's `artefacts` list is the pool.

**d) Re-skin the functional objects.** Re-skin functional objects on persuade/experience surfaces; operate surfaces keep conventional controls. Cart, confirmation, timetable, nav, buttons, empty and error states each become an object of the concept: a pizzeria's cart is a guest-check pad and its confirmation a kitchen ticket on a rail; a surveyor's buttons are corner-tick drafting symbols and its nav is bracketed. Objects like these are drawn by the graphics skill (`../../graphics/references/graphics.md`). This is `functional_reskin`, and it is where a concept stops being a wallpaper.

**e) Pick devices and worlds.** Each concept offers 2-3 signature graphic devices from the technique list in `../../graphics/references/graphics.md` §2, naming what each would draw from which facts, and 2-3 `world_hints` whose grammar fits the artefact. The roll picks one; write all of them at full strength.

Worked method on thin categories:

| Subject | Cliché to skip | Better antecedents | Constraint extracted |
|---|---|---|---|
| SaaS monitoring dashboard | glass KPI cards | control-room gauge panel; ship's bridge cluster; household electricity meter | gauges with tick-marked ranges, flush console grid, colour only for signal state |
| Invoicing tool | fintech blue + gradient button | double-entry ledger; carbon-copy invoice pad; rubber date stamp | hairline-ruled rows, right-aligned tabular amounts, a stub region for totals, stamped status |
| Dev-tool docs | three feature tiles over a sidebar tree | aircraft maintenance manual; board-game rulebook; lab notebook | numbered callouts cross-referenced from prose; flat numbered index instead of a nested tree |
| Fitness app | hero photo + "Start your journey" | boxing-gym chalk round timer; flip-digit scoreboard; coach's logbook | flip-digit counters, a dated ledger spine for history, no progress rings |

A thin category simply has more `artefact` and `place` facts in the dossier and fewer `product` facts.

## 2. Schema of `.vary/concepts.json`

A JSON array. `roll.mjs --concepts` validates it and exits 2 on any failure below.

```json
[{"id":"kvold","name":"Evening at the pizzeria","angle":"the room on a dark evening",
  "antecedent":"paper menu on a wooden table; waiter's guest check",
  "treatment":"scene",
  "facts":["F1","F7","F12"],
  "temperament":"nocturnal-social","audience_mood":"hungry, social, evening: warm, loud-ish, convivial",
  "functional_reskin":"cart = guest-check pad; confirmation = kitchen ticket on a rail",
  "devices":[{"technique":"procedural-subject","what":"every pizza drawn from its menu topping list"},
             {"technique":"material-texture","what":"deckled paper, wood grain, ruled check"}],
  "world_hints":["letterpress-wood-type","vintage-analog","mid-century-travel-poster"],
  "memorable":"the menu lying on the table","p":0.35}]
```

| Field | Rule |
|---|---|
| `id` | unique, short, lowercase |
| `name` | what the concept is called in the contract |
| `angle` | a distinct audience moment, half of the trade, time of day or artefact; unique across the file (case-insensitive) |
| `antecedent` | the trade artefact it borrows |
| `temperament` | required, one of: heritage-craft, warm-domestic, civic-calm, technical-precise, playful-bright, natural-raw, nocturnal-social, avant-garde. The business's own register as the dossier shows it (a Victorian bindery is heritage-craft, a remote geothermal pool natural-raw), not the style you would like to use. `roll.mjs` removes every world whose `temperaments` exclude it, before the sector and hint narrowing; the wildcard never widens temperament |
| `audience_mood` | the mood the audience needs from this page, read from the dossier (children's dentist: bright, safe, daytime; funeral home: calm, quiet, dignified; B2B lab: precise, trustworthy; fish auction: cold, brisk, practical). The `temperament` must serve it, and a world that breaks it is a re-roll (`--lock concept=<id>`) |
| `facts` | at least 3 ids that exist in `dossier.facts[].id`; at least one is visible in the device |
| `functional_reskin` | non-empty: cart, confirmation, nav, buttons in the concept's material |
| `treatment` | one of scene, pattern, photography, product-ui, typography, data-visual, utility; optional (otherwise derived from the dealt device); photography needs a usable photo asset, product-ui a screenshot or app path |
| `devices` | at least 2 for scene/pattern, 1 for the other treatments, 0 for utility; `technique` is one of: seeded-illustration, procedural-subject, traced-line, mechanism-diagram, annotated-photo, photo-direction, product-capture, scroll-scene, data-diagram, material-texture, print-process, typographic, generative-pattern, shader. With a `treatment` other than typography or utility, at least one device maps to it (photo-direction/annotated-photo to photography, product-capture to product-ui) |
| `world_hints` | required, 2-3 existing world ids (`roll.mjs` exits 2 with fewer than 2), never one whose `avoid_sectors` includes the dossier's sector. Take ids from `data/worlds.json` (the one permitted read of it: ids, names, sectors, `avoid_sectors` only) |
| `memorable` | the one element someone will remember |
| `p` | optional, 0-1; logged only, never used to drop a concept |

## 3. Rules

- **4 to 7 concepts**, each with a distinct angle.
- At least 3 facts each, and at least one fact must be visible in the device.
- None may be the category's standard page or its predictable opposite, unless a directive or `--canon` asks for it.
- At most one concept may use the business's name as its metaphor.
- **Concepts must differ in treatment and composition, not only in subject.** Spread them across at least three treatments; none is the default. Two concepts with the same layout and different topics are one concept.
- **A plain, very usable direction is a legitimate concept for tools, dense catalogues or when the client asks; on a business homepage it still needs a memorable idea.** A clear product grid, a quiet document page or a straight form can be the concept; real clients often pick it. Usability comes first, creativity second, and neither needs a drawing.
- **Treatment follows the project, not a habit.** Choose treatments the content and the audience can use: supplied photos (`photography`), a real product UI (`product-ui`; a software landing page is `product-ui` even with no screenshots: record each screen the brief describes in `dossier.product.screens` and rebuild it in HTML from the facts, with real names and numbers, which `roll.mjs` accepts as grounding), figures (`data-visual`), words (`typography`), a task tool (`utility`), or drawn work (`pattern`, `scene`) when the client has no photos or product and the concept calls for it. A directive (SKILL.md directive table) binds every concept. Under a non-drawn treatment no concept replaces the genre's native form with a drawn conceit. Drawn concepts are produced by the graphics skill (`../../graphics/references/graphics.md`).
- Spread the devices: not every concept leads with an illustration engine. Mix drawn, traced, diagrammatic, textural, photographic and typographic devices so the roll has real range.
- Every concept names 2-3 `world_hints`: worlds whose grammar suits the trade artefact. They define the pool the roll draws the world from (with worlds listing the sector) and are weighted 8x; at least one must list the concept's `temperament` or `roll.mjs` exits 2. Hints must fit the audience mood: no Bauhaus primaries for a calm clinic, no sunburst ticket for a quiet service. The roll still picks, you do not.
- Write every concept as if it will win. Never leave a weak "safe" concept as a decoy.
- **Test for each:** "Would this concept still be true for the competitor down the street?" If yes, rewrite it around a fact only this client has.
- **The signature fact leads.** Every concept's hero shows the dossier's `signature_fact` (the one thing only this client has: the 1868 wool office and its cast-iron sample drawers, the reference kilogram on its isolated plinth, the night-sky ceiling of a clinic called the Moon) or the client's own place, product or people. A concept built on the client's customers, an adjacent trade or a pun on the name (a market stall for an accountant whose clients trade at a market, a circus tent for a clinic, saws for a funeral director who was once a joiner) fails; so does a concept that breaks the audience mood.
- A concept must not require anything the dossier refuses (`refuse`), or content it lacks.

## 3b. Idea check (before the roll)

The roll picks among the concepts, so a weak concept can win. Before rolling, spawn a FRESH subagent (Agent tool, `model: opus`) as a creative director. Hand it `.vary/dossier.json`, `.vary/concepts.json`, the surface's mode and the primary task, and nothing from this skill. It scores every concept 1-10 on:

- **Only this client**: swap in a competitor's name; if the concept still works, it scores low. The idea must come from the client's own world (their artefact, place, process, product or data story), never a costume from an unrelated one (a bus timetable for a cycling dashboard, a circus for a clinic).
- **Memorable**: can a visitor describe it in one sentence tomorrow?
- **Past the genre default**: the first idea anyone in this genre would have (a specimen sheet for a type conference, an official statistics report for a data dashboard, a chalkboard for a shop) is a costume of the genre, not of the subject. It scores 6 at most unless it is pushed somewhere only this client could go (the cycling data as streets and movement, the type theme as real signage that travels). Prefer the subject's own world (its places, motion, materials, people, rituals) over the genre's.
- **Serves the main task**: it makes the primary job clearer or faster (finding a plant, reading the trend, booking a ticket); a concept that hides the task behind a gimmick scores low.
- **Honest**: it runs on facts the dossier has; it needs no invented content.
- **Buildable at quality** in this session (a concept that needs photos the client lacks, or art the time budget cannot reach, scores low).

The mean of the five is the concept score. Drop every concept under 7; rewrite the dropped ones once along the director's notes and re-score them; roll only among concepts at 7 or above (at least 3; if fewer survive, write new ones until 3 do). Record the scores in `.vary/concepts.json` (`idea_score`, `idea_notes`). The roll still picks; the director never chooses the winner.

## 4. Worked examples

Fictional clients, deliberately far apart in treatment. Each one shows how the idea rests on facts and how the first screen serves the visitor.

| Client | Concept (angle) | Treatment | Rests on facts like |
|---|---|---|---|
| Hardware chain, 40 stores | "The aisle sign": a plain, fast product grid, big search, stock by store, aisle-sign lettering for categories | `utility` (a plain usable page) | real category list; stock-by-store field; opening hours per store; price per unit |
| Boutique law firm | "The typeset opinion": a typographic page where a case citation set at hero size is the signature | `typography` | founding year; practice areas; a verbatim published ruling citation |
| Fashion label with its own campaign photography | "The contact sheet": the client's frames shown unaltered as a contact sheet; crop and sequence are the signature | `photography` | usable photo assets; collection names; season dates |
| Public transport timetable app | "The departure board": a live-style board, delay in the only alert colour, a dated history ledger | `data-visual` | real routes; headways; punctuality figures |
| Neighbourhood bakery with a deals page | "The price tag": deals as hanging price tags and a punched loyalty card, drawn as the shop's own objects | `pattern` with brand objects (graphics skill) | deal prices; opening hours; the shop's string-tied bags |
| Children's dentist | "The tooth fairy's map": a friendly drawn map of the clinic visit in four steps, bright, daytime | `scene` (graphics skill) | the four steps of a visit; the waiting-room ceiling mural; opening hours |
| Release-notes SaaS | "The release ledger": the real changelog and the capture of the workflow it ships, set as a ledger | `product-ui` | real app screens; the named workflow; version dates |
| Swiss studio (directive: no illustrations) | "The studio's own lettering": a grid of project names carrying the founding year | `typography` | project list; directive `treatment=typography`; the studio's name and city |

Same client, several angles: variants of one client use one dossier and one concepts file, and `--reroll 0..N-1` deals a different concept each round.
