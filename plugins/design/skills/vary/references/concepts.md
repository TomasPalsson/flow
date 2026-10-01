---
name: concepts
description: Step 0b of vary and design. How to turn the dossier into 4-7 grounded concepts (each the site as a physical thing from this trade or place, each a different angle on the business), written to .vary/concepts.json for roll.mjs to pick from. Includes the physical-object method and worked examples from two client sites.
---

# Concepts: the site as a thing from this trade

A concept is a one-sentence idea in which the site **is** a physical thing from this business's own world. The roll picks one of your concepts, so write every one as if it will win.

- ARA (pizzeria and sports bar): "the site IS that room at night, a paper menu on a dark wooden table."
- Hitatækni (HVAC shop): the shop as a set of engineering drawing sheets.
- Hitatækni, a different roll: a picture book about where a building's air goes.

## 1. Method

**a) List the business's halves.** Who uses it, when, and for what. ARA: the cozy evening room, the family's Friday take-away, the sports bar on match night, the street-corner pride of a neighbourhood landmark. Each half is a different angle. Four concepts that are four palettes of one half are not four angles.

**b) Apply the physical-object method to each half.** Ask: *what would this be as a physical artefact, and what did that world look like before the web?*

1. **Name three real antecedents, not one.** The first is the cliché (bank → vault; fitness → gym poster; dashboard → glass cards). The good answer lives at #2 or #3.
2. **Extract a constraint, not a texture.** A ledger is not "beige and lined"; it forces every figure to reconcile in a paired column. A cockpit panel is flush, not floating. A rulebook numbers things because they are cross-referenced. The constraint becomes a layout rule.
3. **Include graphic traditions, not only objects**: the notation, publications, identity programmes, data graphics and interfaces this audience reads daily (a surveyor's field book, a racing programme, a broadcast lower-third, a pharmacy label, a shipping manifest).
4. Reject any antecedent that is the category's standard page or its predictable opposite.

**c) Prefer the trade's own documents and hardware**: datasheet, drawing sheet, guest check, kitchen ticket, price tag, route card, work order, handbill. The dossier's `artefacts` list is the pool.

**d) Re-skin the functional objects.** Cart, confirmation, timetable, nav, buttons, empty and error states each become an object of the concept: ARA's cart is a guest-check pad and its confirmation a kitchen ticket on a rail; hitataekni D's buttons are corner-tick drafting symbols and its nav is bracketed. This is `functional_reskin`, and it is where a concept stops being a wallpaper.

**e) Pick devices and worlds.** Each concept offers 2-3 signature graphic devices from the technique list in `graphics.md` §2, naming what each would draw from which facts, and 2-3 `world_hints` whose grammar fits the artefact. The roll picks one; write all of them at full strength.

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
[{"id":"kvold","name":"Kvöld á ARA","angle":"the room on a dark evening",
  "antecedent":"paper menu on a wooden table; waiter's guest check",
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
| `devices` | at least 2; `technique` is one of: seeded-illustration, procedural-subject, traced-line, mechanism-diagram, annotated-photo, scroll-scene, data-diagram, material-texture, print-process, typographic, generative-pattern, shader |
| `world_hints` | required, 2-3 existing world ids (`roll.mjs` exits 2 with fewer than 2), never one whose `avoid_sectors` includes the dossier's sector. Take ids from `data/worlds.json` (the one permitted read of it: ids, names, sectors, `avoid_sectors` only) |
| `memorable` | the one element someone will remember |
| `p` | optional, 0-1; logged only, never used to drop a concept |

## 3. Rules

- **4 to 7 concepts**, each with a distinct angle.
- At least 3 facts each, and at least one fact must be visible in the device.
- None may be the category's standard page or its predictable opposite.
- At most one concept may use the business's name as its metaphor.
- Spread the devices: not every concept leads with an illustration engine. Mix drawn, traced, diagrammatic, textural and typographic devices so the roll has real range.
- Every concept names 2-3 `world_hints`: worlds whose grammar suits the trade artefact. They define the pool the roll draws the world from (with worlds listing the sector) and are weighted 8x; at least one must list the concept's `temperament` or `roll.mjs` exits 2. Hints must fit the audience mood: no Bauhaus primaries for a calm clinic, no sunburst ticket for a quiet service. The roll still picks, you do not.
- Write every concept as if it will win. Never leave a weak "safe" concept as a decoy.
- **Test for each:** "Would this concept still be true for the competitor down the street?" If yes, rewrite it around a fact only this client has.
- A concept must not require anything the dossier refuses (`refuse`), or content it lacks.

## 4. Worked examples

| Client | Concept (angle) | Rests on facts like |
|---|---|---|
| ARA A "Kvöld á ARA" | the site is the room at night: paper menu on a dark wooden table, hand-inked dishes; cart is a guest-check pad, confirmation a kitchen ticket | dark October evenings in Kópavogur; Edison bulbs and oven glow; the real menu lines and prices |
| ARA B "Heimsækið Búðakór" | the neighbourhood pizzeria sold as a 1950s travel destination: litho poster, "Farseðill" ticket as cart, boarding pass as confirmation | family on a sofa deciding on Friday; the real building at dusk; the Esja-like ridge; pizza as the rising sun |
| ARA C "Boltinn & barinn" | letterpress match-night handbills; the sports-bar half of the business | real beer and wine prices; open to 01:00 Fri and Sat; the big screen; real photos as one-ink halftones |
| ARA D "Hverfisstaðurinn" | Nordic daylight diner for the neighbourhood: deals as hanging price tags with string | turquoise booths in the real photo; deal prices 8.600 / 5.500 / 6.000 / 3.600 / 2.800; a verbatim review about regular take-away |
| Hitatækni A "Loftið í húsinu" | picture book about where a building's air goes, each spread ending on the product that does the job | air handling in Icelandic apartment blocks; filter change monthly; hitaveita water through valves; sensors at 19-21 °C; since 1963 |
| Hitatækni B "Tækniblað" | the shop as an HVAC datasheet binder: ruled grid, mono data, size ruler | Belimo ranges with DN sizes; sheet numbers from brand and position |
| Hitatækni C "Spec-sheet" | 1980s Japanese component brochure, brushed aluminium, one signal colour, a model code as big as the name | Belimo actuators as machined units; brand blue; Swegon rooftop unit spec labels |
| Hitatækni D "Teikning" | the shop as engineering drawing sheets: blue plates, dimension lines, a title block, spec tables on vellum | air handling documented as drawings; a heat wheel, damper, coil, valve, filter; real DN and voltage spec rows |

Same client, four angles: variants of one client use one dossier and one concepts file, and `--reroll 0..N-1` deals a different concept each round.
