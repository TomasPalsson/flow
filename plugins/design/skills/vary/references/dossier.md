---
name: dossier
description: Step 0 of vary and design. How to read a project (repo, the client's live site, supplied assets) into .vary/dossier.json, a list of sourced facts with ids that concepts, graphics and the evaluator all cite. Load before anything else; nothing is invented.
---

# Dossier: read the project before designing it

Every later step cites this file. Concepts cite fact ids, graphics are seeded from fact values, and the evaluator checks the build against it. A thin dossier makes a generic site, so the work here is reading, not writing.

## 1. Sources, in this order

1. **Repo content.** README, data or CMS fixtures, i18n strings, existing pages, `assets/`, `public/`. If a data module already exists (`menu.ts`, `company.ts`, `catalog.json`), read it whole.
2. **The client's live site.** Page text, plus the media library. If the product store is thin, pull the uploads folder instead (hitataekni: the WooCommerce store held 1 product, the media library held 172 images and 37 PDFs). Save page copy as plain text files next to the images.
   - Throttle downloads: 1-2 requests at a time with a pause. A parallel burst got the origin firewall to ban the client. On a ban, fall back to the Wayback Machine (`web.archive.org/web/<ts>id_/<url>`).
3. **Assets the user supplies**: logo, photos, PDFs, brand sheet. Look at each image (Read it) and note what it shows.
4. **Public reviews**, quoted verbatim with the source and date.
5. **The user's memory files** for standing preferences ("no staff portraits", "no underline nav"). They go in `refuse`.

Look at the place too: signage, the building, the room, the climate, the light. Photographs and reviews carry these facts; write them as `place` and `material` facts.

## 2. Schema of `.vary/dossier.json`

```json
{"project":"ARA","subject":"neighbourhood pizzeria and sports bar, Búðakór, Kópavogur","sector":"food-drink",
 "audience":["families ordering take-away on Friday","match-night regulars"],
 "place":{"city":"Kópavogur","climate":"dark winters","light":"Edison bulbs, oven glow","landmarks":["Esja-like ridge"]},
 "language":{"code":"is","glyphs":"þðÞÐÁÍÓÚÝÆÖ"},
 "brand":{"name":"ARA","hex":["#..."],"logo":"assets/scraped/logo.png","signage":"gold serif ARA on navy cladding, 554 3050"},
 "facts":[{"id":"F1","kind":"product","text":"Formaggi — fjórir ostar …","source":"ararestaurant.is/matsedill"},
          {"id":"F2","kind":"price","text":"Pizza Margarita 2.790 kr.","source":"ararestaurant.is/matsedill","demo":false}],
 "assets":[{"path":"shared/img/basar.webp","kind":"photo","usable":true,"notes":"turquoise booths"}],
 "artefacts":["paper menu","guest-check pad","kitchen ticket rail","match-night handbill"],
 "refuse":["no status strip","no staff portraits"],
 "directives":[{"text":"plain, black and white, no illustrations, Swiss style","source":"user brief","locks":["treatment=typography","world=swiss-international","strategy=ink-on-paper"]}],
 "product":{"app_path":"apps/web"}}
```

- `sector` is exactly one id from the SECTORS enum that `roll.mjs` accepts: food-drink, hospitality-travel, retail-ecommerce, trades-construction, industrial-hardware, engineering-technical, healthcare-clinical, finance-insurance, legal-public, kids-education, culture-arts, music-events-nightlife, fashion-beauty-luxury, sports-fitness, media-publishing, dev-tools, enterprise-saas, nature-outdoor, maritime-logistics, nonprofit-activism, wellness, gaming.
- `facts[].id` is `F1`, `F2`, ... and unique. These ids are what `concepts.json` cites and what `roll.mjs` resolves.
- `facts[].kind` is one of: `product`, `price`, `hours`, `place`, `process`, `history`, `quote`, `material`, `artefact`, `person`, `feature`, `metric`, `entity`, `workflow`, `spec`, `event`. The roll counts distinct kinds, not this enum, so the list is guidance.
- `facts[].source` is a URL, file path or "user brief". `demo: true` marks a value that is placeholder, not the client's.
- `language.glyphs` lists the non-ASCII letters the content needs; Step 3 verifies the font against it.
- `assets[].kind` is `photo`, `screenshot`, `logo` or `headshot` (plus others as needed). `notes` records consent for identifiable people and "show unaltered" for identity assets (headshots, logos, product screens).
- `directives[]` holds what the user said about the look, verbatim (`text`), its `source` and the `locks` it implies as `key=value` strings; `roll.mjs` merges them into its locks and they outrank skill defaults. `signature_fact` is the id of the one fact only this client has and a stranger would remember (a place, an object, a ritual), picked before any concept is written; concepts must show it in the hero. `product.app_path` points at the runnable app when product UI is a hero candidate; `product.screens` lists screens the brief describes ("a rota grid, colour by shift") when there is no app or screenshot, and grounds a `product-ui` concept that rebuilds them in HTML.
- `refuse` collects user vetoes and standing rules, and grows when the user rejects a world for the trade.

## 3. Minimums

- At least **12 facts**, at least **4 kinds**, at least **3 artefacts** (the trade's own documents and hardware: datasheet, guest check, route card, price tag).
- Every fact has a `source`.
- `roll.mjs --dossier` enforces these: a `facts` array must exist, at least 12 facts, at least 4 distinct `kind`s, a `source` on every fact, and `dossier.sector` equal to `--sector` when both are given. It exits 2 with the failing rule otherwise.
- If the minimums cannot be met, ask the one question round from SKILL.md (the real proof and content available), then stop. Never pad with plausible-sounding facts.

## 4. Rules

- **Text is verbatim.** Menu lines, spec rows, hours, quotes: copy them exactly, in the client's language. Demo prices carry `"demo": true`.
- **Never invent** customers, testimonials, statistics, capabilities or dates (hitataekni spec: "never invent customers, testimonials or statistics"; ara-bar: "Real content only (no inventing)").
- **Facts are small and checkable.** One fact is one claim with one source: "Open Fri-Sat until 01:00", "Belimo valve DN 15-25". Split a paragraph into several facts.
- **Content lands in the build as a data module** (`content.ts`, `company.ts`, `menu.ts`) holding the dossier values, so pages and graphics are generated from the same source (ara-bar `shared/menu.ts`, hitataekni `shared/company.ts`). `check.mjs` then finds the cited facts in the build.
- **Photos are material, not decoration.** Record which assets are usable and what each shows; `graphics.md` §2 says how to transform them. Mark any with a baked-in badge or watermark in `notes`.
- **People.** Staff or owner portraits only when the dossier says the client wants them.
- Write the file once the sources are read, and keep it small enough for the evaluator to read.
