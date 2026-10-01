---
name: graphics
description: Step 3a of vary (Phase 3b of design). The playbook for custom, subject-specific graphics written in code: how to derive one signature device from the dossier, the art-engine architecture, a technique catalog with a working code pattern per technique, banned forms, budgets, accessibility, and the art-brief, gallery and screenshot-critique loop that must pass before any UI page code.
---

# Graphics: draw the subject

The graphics are the identity. A palette and fonts over CSS blocks is not a design. Every build carries one **signature device** drawn from the subject, shown at three scales, built from dossier facts. The roll assigned the technique; this file says how to execute it. The two client sites that set the bar did it this way: ara-bar drew every dish and its own building as seeded SVG; hitataekni drew its air handling unit as a cutaway and traced its products into drafting-sheet line art. The patterns below are those engines' real methods, generalised: feed them the subject's own facts, because a pattern copied with placeholder data looks generic (a navy slab with a gold blob). Section 0b is the bar. The patterns teach techniques, not motifs: never draw a pizza, a carton, a storefront or an air-handling unit unless it is THIS client's subject — take the method (projection, char spots, zoned fills, tracing, dimension lines) and point it at the nouns in this dossier.

## 0. Derive the device from the subject

1. Pull 5-10 nouns from the dossier facts: place, material, mechanism, product, history.
2. Find the ONE primitive they share: a contour, a stroke, a ring, a tile, a sheet, an ink layer.
3. Make it carry data, seeded from real values: menu toppings, DN ranges, founding year, hours.
4. Place it at **3 scales**: hero, section divider, micro (icon, bullet, empty state, cursor).
5. One device, one texture, one motion rule.

Test: *"Could this graphic only belong to this business?"* If a competitor could ship it, redraw it from a fact they do not have.

| Project | Device | Data it carries |
|---|---|---|
| ara-bar | procedural pizzas | topping lists from `menu.ts` (`pizza/specs.ts`) |
| ara-bar | storefront scene | the real signage and phone number |
| hitataekni | air-handling-unit cutaway | real parts cross-referenced to the shop's categories |
| hitataekni | traced Belimo line art | real spec rows (DN range, voltage) in the dimension labels |
| hitataekni | air ribbons through an Icelandic apartment block | the company's process |
## 0b. What cool looks like (the bar to aim at)

Ten signature devices from the two benchmark sites. "Built" is what exists in their code; "carry" is how the same idea scales where the code did not (marked as such). Aim for this density of specificity: every picture is a function of a fact the competitor does not have.

| # | Device | What was drawn | From which fact | Three scales |
|---|---|---|---|---|
| 1 | ara-bar pizzas | Top-down pies with leopard-char crust and scorched rim, overlapping melted-cheese blobs with sauce between, zoned toppings (the four-cheese pizza has four wavy quarters), a lifted slice with cheese strands (`lift: true`) | The topping list of each dish in `menu.ts` | Hero: the lifted slice. Divider: the pizza as a rising sun over hills, 24-wedge sunburst. Micro: the 96px thumb with fewer, bolder toppings |
| 2 | ara-bar storefront | The real building at dusk and night: navy corrugated cladding with a string-light wire, a dusk gradient sky of glowing bands and cloud lenses, a drip-edged snow ridge, a crest and gold "ARA" pinned with `textLength` over a "RESTAURANT" ribbon, "554 3050" on a second sign and the door, pendant bulbs, faceless diners at tables, glass shine, paving slabs and a street lamp with a halo | The client's own photo of the premises | Hero: the whole scene. Divider: the ridge strip with the sky cut away by string surgery. Micro (carry): the sign alone as a sticker |
| 3 | ara-bar takeaway carton | Oblique-projection box with lid, receipt with zig-zag edge, squashed-ellipse "ARA" sticker, cast shadow, two tapered steam wisps | The real take-away service | Hero: the cart or confirmation page. Divider (carry): the corrugated wall as a repeated strip. Micro: the sticker as the basket icon |
| 4 | ara-bar oven | Brick dome in running bond, fire-glow clamped inside the mouth, five flames and an ember scatter, a peel in perspective, a woodpile with offset tree rings | The wood-fired oven in the room | Hero: the oven glow. Divider (carry): a row of flames. Micro: one flame as a bullet |
| 5 | hitataekni cutaway | Air handling unit in section A-A: heat wheel with honeycomb rings and 16 spokes, pleated filter, coil, backward-curved fan, hatched casing, scale bar, eleven numbered callouts | Real parts = the shop's product categories (the parts list links into the shop) | Hero: sheet 00 (`sheet()` in section d draws the frame, zone markers, title block, leader callouts, flow labels and the L/H dimensions around a `unit()`). Divider: the hatched wall strip with the scale bar. Micro: one numbered callout circle or one part as a nav glyph |
| 6 | hitataekni traced line art | Belimo products edge-traced from the scraped photos (warranty roundel painted out first), white line on blue, dimension lines at the traced bounds | Spec rows: `DN 15-25`, `2-VEGA`, voltages | Hero: the cover sheet, a traced rooftop unit drafted in over 1.1s with zone markers A-F and 1-8. Plate: each product. Micro (carry): a small mask in a cart line |
| 7 | hitataekni air ribbons | A flat-roofed Icelandic block with snow on the parapet and lit windows; a tapered blue fresh-air ribbon in, a grey stale one out | The company's trade (air through a building) | Hero: spread 1 of the picture book. Divider: the ribbon alone as a swash that draws on scroll. Micro (carry): a ribbon tick as a list marker |
| 8 | hitataekni filter clogging | A filter bed that fills from the bottom with specks, "Manudur 1 to 12" from a typed CSS integer counter | The filter-subscription interval it sells | Hero: the pinned spread. Divider (carry): the bed as a progress bar. Micro: the counter digit |
| 9 | hitataekni hood section | A kitchen-hood duct in section, grease built up as perpendicular hatch ticks along the walls, dimensions "6 MAN." and "3-5 AR" | The duct-cleaning service intervals | Hero: the service sheet. Divider (carry): the tick row. Micro: a single tick-lined pipe icon |
| 10 | hitataekni title block | A drawing-sheet title block that behaves like one: sheet counter updates as plates cross the viewport middle, founding year 1963, emergency number, address, margin ruler | The firm's own details | Hero (carry): the cover. Divider: the margin ruler. Micro: the sheet counter chip |

What these have in common, and what a review should check:

1. **The picture is a function of a fact.** Remove the logo and the hero still says whose it is.
2. **One drawing, three scales**, from the same function, not three different pieces of clip art.
3. **Authored imperfection**: wobble, misregistration, char spots, grease ticks; reproducible from a seed.
4. **A restriction that is tested**: six inks and no opacity, or strokes only on one blue.
5. **Objects with a job**: the cart is a guest check or a ticket, the callout opens the product page, the gauge is the explanation of what the company sells.
6. **Craft the template skips**: a mask for the badge baked into the photo, hand-patched glyphs for the content language, a finished state for narrow and reduced-motion, a text equivalent.

The hero must pass the scene bar (S1-S3 in the vary Step 3a, composed per §1b): a full-bleed scene or sheet, 5+ subject objects, 3+ depth layers, one light, headline set into it, 2+ facts drawn in it. A single icon, a bare grid, a lone diagram in a framed box or a text-only hero is a FAIL for persuade.

If your hero could be mistaken for a stock illustration or a gradient blob with a gold shape on it, it is below the bar: redraw it from a fact.

## 1. Art-engine architecture

- **Plain functions that return SVG strings.** No DOM, so the engine runs in Bun, Node and the browser, and a test can render it. Pages inline the string, or a build script writes `.svg` files.
- **Seeded PRNG keyed per item**: `rng("pizza:" + id)`. Never `Math.random` in art (a re-render must be identical; `check.mjs` warns on it).
- **Draw once, style many (the swatch bridge).** A drawing never contains a colour. It names swatches (`crust`, `sauce`, `shadow`) and calls `shape(S, d, 'sauce')`. A **style object** `S = { name, palette, outline, wobble, shade, misregister }` maps every name to an ink hex for one world: `ink` is warm line and hatch, `litho` is flat fills with offset shadows and no outline, `press` snaps the line palette to six inks. `shape()` writes a **literal** `fill="#hex"` plus `data-sw="sauce"`, so the ink-set test, `[fill="#hex"]` selectors and `[data-sw]` selectors all work. Never write `fill="var(--x)"` in a drawing: attribute selectors cannot see through it, and a test cannot check it. CSS variables stay for page chrome; the picture's colours come from the style object.
- **Leave composition markers** in the output (the first path is always the sky) so pages can cut a scene apart by string surgery, as ara-bar's poster strips the storefront's sky with `svg.indexOf('<path d="M-10 ')`.
- **No `<clipPath>`/`<filter>` ids in drawings** when many SVGs are inlined on one page: ids collide. Clip by sampling (`hatchIn` below takes an `inside(x, y)` predicate) or namespace ids with the item key.
- **Hand-made on purpose, reproducibly.** Imperfection is authored: wobble from the seeded PRNG, 3px misregistration, char spots, a rotation of -0.4 degrees. It is the same on every load.

File layout the art brief should name: `art/core.js` (kit below), `art/scene.js` (building, carton, ribbons), `art/pizza.js` (or one file per subject family), `art/print.js` (ink sets and snapping), `art/draft.js` (strokes-only drafting kit and sheet), `art/wellformed.js` (test helper), `trace.mjs` (build-time, run by hand or from a package script), `art/art.test.js`, `art/draft.test.js`, `art-gallery.html`.

Core kit (tested; paste into `art/core.js`). `STYLES` holds two worlds so the same drawing can be re-inked; add yours next to them and keep the swatch names stable:

```js
// art/core.js: the seeded engine. Plain functions returning SVG strings: no DOM, runs in Bun, Node and the browser.
const fnv = s => { let x = 2166136261; for (const c of s) { x ^= c.charCodeAt(0); x = Math.imul(x, 16777619) } return x >>> 0 };
const mulberry = a => () => { a |= 0; a = a + 0x6D2B79F5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a);
  t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296 };
export const rng = key => mulberry(fnv(key));            // same key, same drawing, every render
export const f = n => +n.toFixed(1);
export const rr = (r, a, b) => a + r() * (b - a);         // uniform in [a, b)

// ---- paths ----------------------------------------------------------------------------------
export const poly = p => `M${p.map(q => `${f(q[0])} ${f(q[1])}`).join('L')}Z`;
export function smoothClosed(p) {                          // closed Catmull-Rom through points
  const n = p.length; let d = `M${f(p[0][0])} ${f(p[0][1])}`;
  for (let i = 0; i < n; i++) {
    const a = p[(i - 1 + n) % n], b = p[i], c = p[(i + 1) % n], e = p[(i + 2) % n];
    d += `C${f(b[0] + (c[0] - a[0]) / 6)} ${f(b[1] + (c[1] - a[1]) / 6)} ${f(c[0] - (e[0] - b[0]) / 6)} ${f(c[1] - (e[1] - b[1]) / 6)} ${f(c[0])} ${f(c[1])}`;
  }
  return d + 'Z';
}
export function blob(cx, cy, rx, ry, r, jitter = .12, n = 9, rot = 0) {   // hand-wobbled ellipse
  const p = [];
  for (let i = 0; i < n; i++) { const a = rot + i / n * Math.PI * 2, k = 1 + (r() * 2 - 1) * jitter;
    p.push([cx + Math.cos(a) * rx * k, cy + Math.sin(a) * ry * k]) }
  return smoothClosed(p);
}
export function wobbleLine(x1, y1, x2, y2, r, amp = 1.5, seg = 8) {      // hand-wobbled straight line
  let d = `M${f(x1)} ${f(y1)}`;
  for (let i = 1; i <= seg; i++) { const t = i / seg;
    d += `L${f(x1 + (x2 - x1) * t + (r() - .5) * amp * 2)} ${f(y1 + (y2 - y1) * t + (r() - .5) * amp * 2)}` }
  return d;
}
export const bez = (p0, p1, p2, p3, n = 16) => Array.from({ length: n }, (_, i) => { const t = i / (n - 1), u = 1 - t;
  return [0, 1].map(k => u * u * u * p0[k] + 3 * u * u * t * p1[k] + 3 * u * t * t * p2[k] + t * t * t * p3[k]) });
// Centre line -> closed outline that swells in the middle and ends in points: steam, air ribbons, brush strokes, smoke.
export function taper(center, wmax, power = .8) {
  const n = center.length, L = [], R = [];
  center.forEach(([x, y], i) => {
    const a = center[Math.max(0, i - 1)], b = center[Math.min(n - 1, i + 1)], dx = b[0] - a[0], dy = b[1] - a[1], l = Math.hypot(dx, dy) || 1;
    const w = wmax / 2 * Math.pow(Math.sin(Math.PI * i / (n - 1)), power);
    L.push([x - dy / l * w, y + dx / l * w]); R.push([x + dy / l * w, y - dx / l * w]);
  });
  return poly([...L, ...R.reverse()]);
}
// Hatching clipped by a predicate, not a clipPath: no ids, so many SVGs inline on one page without collisions.
export function hatchIn(inside, [x0, y0, x1, y1], deg = 45, gap = 4, step = 2) {
  const a = deg * Math.PI / 180, dx = Math.cos(a), dy = Math.sin(a), cx = (x0 + x1) / 2, cy = (y0 + y1) / 2, R = Math.hypot(x1 - x0, y1 - y0) / 2 + 2;
  let d = '';
  for (let s = -R; s <= R; s += gap) { let start = null, prev;
    for (let t = -R; t <= R + step; t += step) {
      const x = cx - dy * s + dx * t, y = cy + dx * s + dy * t, ok = t <= R && x >= x0 && x <= x1 && y >= y0 && y <= y1 && inside(x, y);
      if (ok && !start) start = [x, y];
      if (!ok && start) { if (Math.hypot(prev[0] - start[0], prev[1] - start[1]) > 3) d += `M${f(start[0])} ${f(start[1])}L${f(prev[0])} ${f(prev[1])}`; start = null }
      prev = [x, y];
    } }
  return d;
}
export const torn = (seed, amp = 2.2, steps = 28) => { const r = rng('torn:' + seed), pts = [];   // CSS clip-path polygon
  for (let i = 0; i <= steps; i++) pts.push(`${f(i / steps * 100)}% ${f(r() * amp)}%`);
  return `polygon(${[...pts, '100% 100%', '0% 100%'].join(',')})` };
// Poisson-ish scatter inside a predicate: toppings, stars, specks. Rejects points closer than minD.
export function scatter(r, n, inside, minD, [x0, y0, x1, y1] = [-100, -100, 100, 100], tries = 400) {
  const out = [];
  while (out.length < n && tries--) { const x = rr(r, x0, x1), y = rr(r, y0, y1);
    if (inside(x, y) && out.every(q => Math.hypot(q[0] - x, q[1] - y) >= minD)) out.push([x, y]) }
  return out;
}

// ---- the swatch / style bridge --------------------------------------------------------------
// Drawings never contain a colour. They name swatches ('dough', 'sauce', 'shadow'); a STYLE maps names to ink hexes,
// plus how the world draws: { name, palette, outline: {color, width} | null, wobble, shade: 'hatch' | 'flat' | 'none', misregister }.
// shape() writes a literal fill (so [fill="#hex"] selectors, the ink-set test and print CSS all work) AND data-sw="name".
export function shape(S, d, sw, { shadow, line = true, extra = '' } = {}) {
  const P = S.palette, ln = S.outline && line ? ` stroke="${S.outline.color}" stroke-width="${S.outline.width}" stroke-linejoin="round"` : '';
  const under = shadow && S.shade === 'flat' ? `<path d="${d}" fill="${P[shadow]}" data-sw="${shadow}" transform="translate(${S.misregister} ${S.misregister})"/>` : '';
  return `${under}<path d="${d}" fill="${P[sw]}" data-sw="${sw}"${ln}${extra ? ' ' + extra : ''}/>`;
}
export const strokeSw = (S, d, sw, w = 1.4) => `<path d="${d}" fill="none" stroke="${S.palette[sw]}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round" data-sw="${sw}"/>`;
export const shade = (S, d) => S.shade === 'hatch' && d ? strokeSw(S, d, 'ink', (S.outline?.width ?? 2) * .4) : '';   // hatching exists only in line worlds
export const svg = (vb, body, title = '', cls = '') =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}" ${title ? `role="img" aria-label="${title.replace(/"/g, '&quot;')}"` : 'aria-hidden="true" focusable="false"'}${cls ? ` class="${cls}"` : ''}>${body}</svg>`;

// Two styles for the same drawings. 'ink' = warm line-and-hatch; 'litho' = flat fills, offset shadows, no outline, no opacity.
const base = { paper: '#f4ead2', ink: '#2a1d14', shadow: '#c9b48a' };
export const STYLES = {
  ink:   { name: 'ink', outline: { color: '#2a1d14', width: 2 }, wobble: 1, shade: 'hatch', misregister: 0,
    palette: { ...base, crust: '#d9a95c', crustDark: '#a8702f', sauce: '#b8402a', cheese: '#f1d27a', cheeseDark: '#c99a3b', pepperoni: '#a8322a', fleck: '#6e1d18',
      olive: '#3c3a1d', basil: '#4f8a3c', bacon: '#c8745a', wood: '#7a5230', woodDark: '#4e3320', box: '#d8b988', boxDark: '#a98a5c', wall: '#e8dcc0', wallDark: '#6a5a46', steam: '#f4ead2',
      skyDark: '#4b4a72', sky: '#b9677a', skyLow: '#e0925f', sun: '#f7d98f', ridge: '#7a6283', cladding: '#2e3c58', rib: '#1a2338', gold: '#d9a82e', glass: '#f3c76a', glow: '#fbe9b0', snow: '#fbf6e8',
      air: '#3f86b3', stale: '#8f8a80', screen: '#3a5a6e' } },
  litho: { name: 'litho', outline: null, wobble: .6, shade: 'flat', misregister: 3,
    palette: { paper: '#f4ead2', ink: '#1d2a4a', shadow: '#1d2a4a', crust: '#ffc417', crustDark: '#e0643f', sauce: '#e0643f', cheese: '#f4ead2', cheeseDark: '#e0643f', pepperoni: '#e0643f', fleck: '#1d2a4a',
      olive: '#1d2a4a', basil: '#4a8a5a', bacon: '#e0643f', wood: '#ffc417', woodDark: '#1d2a4a', box: '#e0643f', boxDark: '#1d2a4a', wall: '#f4ead2', wallDark: '#1d2a4a', steam: '#f4ead2',
      skyDark: '#1d2a4a', sky: '#5fb0cf', skyLow: '#e0643f', sun: '#ffc417', ridge: '#4a8a5a', cladding: '#1d2a4a', rib: '#5fb0cf', gold: '#ffc417', glass: '#ffc417', glow: '#f4ead2', snow: '#f4ead2',
      air: '#5fb0cf', stale: '#f4ead2', screen: '#4a8a5a' } },
};
export const inkSet = S => new Set(Object.values(S.palette));
// Point-in-polygon: the `inside` predicate for hatchIn over any face.
export const inPoly = p => (x, y) => { let c = false;
  for (let i = 0, j = p.length - 1; i < p.length; j = i++) if ((p[i][1] > y) !== (p[j][1] > y) && x < (p[j][0] - p[i][0]) * (y - p[i][1]) / (p[j][1] - p[i][1]) + p[i][0]) c = !c;
  return c };
```

The torn edge: set `clip-path: var(--torn)` from `torn(seed)`, with a lighter back plate behind it and a `drop-shadow` filter on the wrapper.

## 1b. Composing a scene

The hero of a persuade or experience page is a **scene**, not an object: ara-bar's is the restaurant at night, hitataekni's is a whole blueprint sheet. Both are 10+ drawn objects, 3+ depth layers and one light source, with the brand set into the picture. Generalise the method to this dossier's place, never the motifs.

**Layer order** (paint back to front; each layer is a function returning SVG, all seeded):

1. **Sky / backdrop**: gradient bands or flat strips, stars or paper tone, a horizon. (Sheet: grid, border, zone markers.)
2. **Architecture / landscape**: ridge, skyline, building facade, wall, cladding with rib hatching. (Sheet: the traced or drafted subject.)
3. **Subject**: the thing the business is, drawn large and lit: the oven, the unit, the shopfront, the workbench.
4. **People and props**: faceless silhouettes at tables, tools in use, a match on the screen, steam, a street lamp, parts on a shelf; traces of use where people are not allowed.
5. **Lighting overlay**: warm window glow, a halo round the lamp, a cast shadow under every object, a darkened edge vignette. One light source; lit faces and shaded faces share one direction.
6. **Lettering**: sign, ribbon, painted wall text, title block. Real dossier strings only.

**Headline into the scene.** The brand or headline is the scene's own lettering (the sign over the door, painted wall type, a title block). When the page headline must be live text, set it over a quiet zone of the scene (sky, wall, empty sheet area) and keep that zone flat. **Readable over art**: put a plate behind copy (a darker band, a card of the scene's own material) or put the copy on the scene's own board or sign; measure contrast over the darkest and lightest pixel under the text, not the average. Body copy and prices never sit directly on detail.

**Facts in the art.** Draw at least two dossier strings inside the picture: the phone number painted on the sign, the founding year and address in the title block, hours on a door card, the real product names on shelf labels.

**Skeleton**: seeded layers, a style object, objects at three depths, a light. Adapt the nouns to the dossier; this one is deliberately generic. It is the **minimum**, not the target: add the dossier's own props (the TV, the shelf, the product) until the checklist below passes. Swatches it uses (`ground`, `cladding`, `rib`, `glass`, `wallDark`, `gold`, `glow`, `ink`, sky tones) must exist in the style's palette.

```js
// art/scene.js: compose a hero scene. Every layer is a pure function of (S, r, W, H); S is a style object from core.js.
import { rng, rr, blob, hatchIn, inPoly, scatter, shape, strokeSw, svg, f } from './core.js';

const sky = (S, r, W, H) => {                         // layer 1: first element is always the sky (composition marker)
  const bands = [0, .25, .5, .72].map((t, i) => `<rect x="-10" y="${f(H * t)}" width="${W + 20}" height="${f(H * .3)}" fill="${S.palette[['skyDark', 'sky', 'skyLow', 'sun'][i]]}" data-sw="sky"/>`).join('');
  const stars = scatter(r, 40, (x, y) => y < H * .3, W / 60, [0, 0, W, H * .3]).map(([x, y]) => `<circle cx="${f(x)}" cy="${f(y)}" r="${f(rr(r, W / 1200, W / 500))}" fill="${S.palette.glow}"/>`).join('');
  return bands + stars;
};
const ridge = (S, r, W, H) => {                       // layer 2: far landscape, lit side + hatched shade side
  const pts = Array.from({ length: 14 }, (_, i) => [i / 13 * W, H * (.34 + rr(r, -.07, .07) - Math.sin(i / 13 * Math.PI) * .08)]);
  const outline = [[0, H * .5], ...pts, [W, H * .5]];
  return shape(S, `M${outline.map(p => p.map(f).join(' ')).join('L')}Z`, 'ridge')
    + strokeSw(S, hatchIn(inPoly(outline), [0, 0, W, H * .5], 60, W / 120, 3), 'ink', W / 700);
};
const facade = (S, r, W, H) => {                      // layers 2-3: the building the business lives in, with lit windows, a sign plate and a ground band
  const y0 = H * .5, y1 = H * .88; let out = shape(S, `M0 ${f(y1)}H${W}V${H}H0Z`, 'ground');   // ground band with its own tone
  out += shape(S, `M0 ${f(y0)}H${W}V${f(y1)}H0Z`, 'cladding');
  for (let x = 0; x < W; x += W / 90) out += `<path d="M${f(x)} ${f(y0)}V${f(y1)}" stroke="${S.palette.rib}" stroke-width="${f(W / 700)}"/>`;   // corrugation
  out += shape(S, `M0 ${f(y1)}H${W}v${f(H * .02)}H0Z`, 'wallDark', { line: false });   // cast shadow of the building on the ground
  const n = 5, ww = W / n;
  for (let i = 0; i < n; i++) {
    const x = i * ww + 12, w = ww - 24;
    out += shape(S, `M${f(x)} ${f(H * .66)}h${f(w)}v${f(H * .2)}h${f(-w)}Z`, 'glass');   // lit windows
    out += shape(S, `M${f(x)} ${f(H * .66)}h${f(w)}v${f(H * .015)}h${f(-w)}Z`, 'wallDark', { line: false });   // lintel shadow
    out += `<circle cx="${f(x + w / 2)}" cy="${f(H * .69)}" r="${f(W / 200)}" fill="${S.palette.gold}" data-sw="gold"/>`;   // pendant bulb
  }
  return out;
};
const sign = (S, W, H) => shape(S, `M${f(W * .22)} ${f(H * .4)}H${f(W * .78)}V${f(H * .56)}H${f(W * .22)}Z`, 'wallDark', { shadow: 'ink' });   // plate behind the lettering, so copy never sits on detail
const lamp = (S, W, H) => {                            // prop at the foreground depth: street lamp with its own light pool
  const x = W * .93, y = H * .88;
  return shape(S, `M${f(x - 3)} ${f(y)}V${f(H * .5)}h6V${f(y)}Z`, 'wallDark')
    + shape(S, `M${f(x - W / 60)} ${f(H * .5)}h${f(W / 30)}l${f(-W / 200)} ${f(-H * .03)}h${f(-W / 40 + W / 100)}Z`, 'wallDark')
    + `<circle cx="${f(x)}" cy="${f(H * .5 - 4)}" r="${f(W / 160)}" fill="${S.palette.glow}" data-sw="glow"/>`
    + `<ellipse cx="${f(x)}" cy="${f(y + H * .02)}" rx="${f(W / 20)}" ry="${f(H * .012)}" fill="${S.palette.glow}" opacity=".35"/>`;
};
const people = (S, r, W, H) => Array.from({ length: 4 }, (_, i) => {   // layer 4: faceless silhouettes at depth, each with a cast shadow
  const x = W * (.12 + i * .24 + rr(r, -.02, .02)), y = H * .88, s = W / 40;
  return `<ellipse cx="${f(x + s)}" cy="${f(y + 4)}" rx="${f(s * 1.6)}" ry="${f(s * .3)}" fill="${S.palette.ink}" opacity=".4"/>`   // cast shadow, offset away from the light
    + shape(S, `M${f(x - s * .9)} ${f(y)}L${f(x - s * .6)} ${f(y - s * 2.6)}Q${f(x)} ${f(y - s * 3.1)} ${f(x + s * .6)} ${f(y - s * 2.6)}L${f(x + s * .9)} ${f(y)}Z`, 'wallDark')   // torso
    + shape(S, blob(x, y - s * 3.5, s * .55, s * .65, r, .05), 'wallDark');   // head
}).join('');
const glow = (S, W, H) => S.shade === 'flat' ? '' :   // layer 5: light overlay (flat/litho worlds forbid gradients: use offset shadow shapes instead)
  `<radialGradient id="glow-${S.name}" cx=".5" cy=".75" r=".6"><stop offset="0" stop-color="${S.palette.glow}" stop-opacity=".45"/><stop offset="1" stop-color="${S.palette.glow}" stop-opacity="0"/></radialGradient><rect width="${W}" height="${H}" fill="url(#glow-${S.name})"/>`;
const lettering = (S, W, H, facts) =>                  // layer 6: real strings from the dossier, pinned with textLength
  `<text x="${W / 2}" y="${f(H * .5)}" text-anchor="middle" font-size="${f(W / 9)}" textLength="${f(W / 4)}" fill="${S.palette.gold}" data-sw="gold">${facts.name}</text>`
  + `<text x="${W / 2}" y="${f(H * .54)}" text-anchor="middle" font-size="${f(W / 36)}" fill="${S.palette.gold}">${facts.phone}</text>`;

export function heroScene(S, facts, { W = 1440, H = 900 } = {}) {
  const r = rng('scene:' + facts.id);                  // one seed; layers draw from it in a fixed order
  return svg(`0 0 ${W} ${H}`, [sky(S, r, W, H), ridge(S, r, W, H), facade(S, r, W, H), sign(S, W, H), lamp(S, W, H), people(S, r, W, H), glow(S, W, H), lettering(S, W, H, facts)].join(''), facts.alt);
}
// Mobile: call heroScene(S, facts, { W: 780, H: 900 }) with the same seed and fewer, larger objects, not a scaled-down desktop.
```

**Checklist for the gallery's whole-scene render**: at least 5 distinct objects counted aloud; at least 3 depth layers; one visible light source with cast shadows; texture on at least two surfaces (hatching, grain, halftone, paper); people or traces of use; at least 2 dossier facts legible inside the art; covers at least 55% of the 1440x900 first viewport (45% at 390x844); the §1d finish pass is applied (value plan, 3 value steps per material, grain, no empty region over 20% of the hero); every label, callout and sign text is fully visible (collision rule in §7). Fail any and the round is not closed.

**Lettering on a scene surface that stays legible and clickable (worked example).** The headline, phone, hours and primary action live ON a drawn surface (sign, ticket, chalkboard, title block, label), never on a frosted card, chip row or button pair laid over the art. Wrap the drawn sign in the real control, so the picture is the button:

```html
<a class="sign" href="tel:+3545550123" aria-label="Call Hitataekni: 555 0123">
  <svg viewBox="0 0 640 220" role="img" aria-labelledby="sign-t" width="640" height="220">
    <title id="sign-t">Hitataekni, repairs. Phone 555 0123</title>
    <rect x="4" y="4" width="632" height="212" rx="10" fill="#1d1a16"/>              <!-- sign board: solid, so contrast is measured on a known ground -->
    <rect x="4" y="4" width="632" height="38" rx="10" fill="#2c2720"/>               <!-- lit top plane: value step 2 -->
    <text x="320" y="130" text-anchor="middle" font-size="84" textLength="560" lengthAdjust="spacingAndGlyphs" fill="#f2c14e">HITATAEKNI</text>
    <text x="320" y="186" text-anchor="middle" font-size="34" fill="#f6e7c1">555 0123</text>
  </svg>
</a>
<style>
  .sign { display: block; width: min(46vw, 640px); }                 /* sits at a fixed place in the scene layout */
  @media (max-width: 600px) { .sign { width: min(88vw, 640px); } }  /* phones: the smallest painted letter must render >= 14px */
  .sign:hover svg rect:first-child { filter: brightness(1.12); }
  .sign:focus-visible { outline: 3px solid var(--focus); outline-offset: 4px; border-radius: 12px; }
  .sign svg { display: block; width: 100%; height: auto; }
</style>
```

Rules: lettering against its board is at least 4.5:1 (7:1 for the primary action); the `<a>` carries an accessible name that repeats the lettering; nothing drawn (pipe, lamp, person, steam) overlaps a glyph, so keep a clear margin of one letter-height around the text in the art; the sign is at least 44px tall on a phone; if the scene is a background `<svg>`, place the `<a>` as a sibling positioned over the sign with percentages that match the sign's rectangle, and keep the lettering in live text so it scales and is selectable.

## 1c. Scale up

A scene is drawn at 1000-1500 units wide, so line weights, hatch gaps, label sizes and stipple dots scale with the canvas. Never a 1px hairline on a 1400px canvas.

- Derive every stroke from the width: outline `W / 450` to `W / 300`, hatch lines `W / 700`, hatch gap `W / 120`, dimension lines `W / 600`, label text `W / 90` minimum for small print and `W / 9` to `W / 6` for painted lettering.
- Prefer filled shapes to strokes for large objects; strokes are for edges, hatching and dimension lines.
- Mobile gets its own composition at its own proportions (fewer, larger objects), not the desktop SVG scaled down.
- Use `vector-effect: non-scaling-stroke` only for deliberate hairlines (a grid), never for the subject.
- Plates that resize use the `--k` pattern in "Scaling line weight with the plate" below.

## 1d. Finish pass (applied in the art loop, after the objects are drawn)

Flat single-tone vectors read as clip-art. The benchmarks win on value structure: lit windows against a night sky, a gold sign, grain, a blueprint grid with a title block. Run this pass on the hero and on every plate before the critique screenshot.

1. **Value plan.** Decide the light before shading: time of day, ONE key light (direction), ONE glow source (window, lamp, oven mouth, screen). Lit planes face the key light, shaded planes the other way, cast shadows fall away from it. The brightest value on the plate goes to the focal fact (the sign, the product, the price tag); everything else sits at least two steps darker. Squint test: blur the screenshot, the focal fact must still be the brightest spot.
2. **No flat muddy fills.** Every material (wall, roof, cloth, wood, metal, figure) has at least 3 value steps from the palette: lit, mid, shade, plus an edge or cast shadow. Hatching on one brown is not three steps. Never fill a large area with a single mid-value brown or grey.
3. **Grain / texture overlay** over the whole plate (feTurbulence with its contrast stretched, or a tiled noise pattern), so flat fills carry paper or film tooth. Check it, do not assume it: on a flat fill in the screenshot the pixel standard deviation must be at least 3/255 (a 6% unstretched turbulence measures under 1 — invisible).
4. **No dead zone.** No empty region larger than 20% of the hero area (an empty floor, an empty right third, a blank sky): fill it with environment (more street, a counter, shelves, people, reflections) or move and rescale the subject until it fills the frame.

```js
// art/finish.js: value plan + glow + grain, appended after the drawing and BEFORE the lettering layer (sign text, phone,
// title block): the finish must not lift or tint the letters — draw them last, on their own solid plate.
// Centre the glow on the focal fact (the sign, the product), never on an empty floor.
export const plan = { key: { x: .72, y: .18 }, glow: { x: .5, y: .62, r: .55 } };   // light direction + glow centre (move it onto the focal fact), fractions of W/H

export const finish = (S, W, H, id) => `
  <defs>
    <radialGradient id="glow-${id}" cx="${plan.glow.x}" cy="${plan.glow.y}" r="${plan.glow.r}">
      <stop offset="0" stop-color="${S.palette.glow}" stop-opacity=".5"/>
      <stop offset="1" stop-color="${S.palette.glow}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="vig-${id}" x1="0" y1="0" x2="0" y2="1">               <!-- darken the edges so the focal fact is the brightest value -->
      <stop offset="0" stop-color="${S.palette.ink}" stop-opacity=".35"/>
      <stop offset=".35" stop-color="${S.palette.ink}" stop-opacity="0"/>
      <stop offset=".7" stop-color="${S.palette.ink}" stop-opacity="0"/>
      <stop offset="1" stop-color="${S.palette.ink}" stop-opacity=".45"/>
    </linearGradient>
    <filter id="grain-${id}" x="0" y="0" width="100%" height="100%">
      <feTurbulence type="fractalNoise" baseFrequency=".8" numOctaves="2" seed="7" result="n"/>
      <feColorMatrix in="n" type="saturate" values="0" result="g"/>
      <feComponentTransfer in="g"><feFuncR type="linear" slope="2.4" intercept="-.7"/><feFuncG type="linear" slope="2.4" intercept="-.7"/><feFuncB type="linear" slope="2.4" intercept="-.7"/></feComponentTransfer>   <!-- stretch the noise so it reads -->
    </filter>
  </defs>
  <rect width="${W}" height="${H}" fill="url(#glow-${id})" style="mix-blend-mode:screen"/>
  <rect width="${W}" height="${H}" fill="url(#vig-${id})"/>
  <rect width="${W}" height="${H}" filter="url(#grain-${id})" opacity=".14" style="mix-blend-mode:soft-light"/>`;
// Worlds that forbid gradients or opacity (litho, flat): replace the glow with an offset lighter shape, the vignette with a darker
// border band, and the grain with a hatch or halftone pattern in an existing ink. Still three value steps per material.
```

Critique additions for this pass: name the light source, point at the brightest value and say whether it is the focal fact, count value steps on the two largest materials, and measure the largest empty region as a percentage of the hero.

### Depth recipe (the numbers the fold gate measures)

Measured on the desktop screenshot of the art area (hero, and each plate on its own box). Judges fail "flat fills with thin uniform strokes" as clip art; the benchmarks have glow, texture, gradient skies and hatch used as shading.

| Measure | Target | How to hit it in SVG |
|---|---|---|
| Value range (luminance p95 minus p5, 0-255) | at least 90 | A real dark and a real light in the same frame: night sky or deep shade against a lit window, sign or lamp glow |
| Value steps (of 16 luminance bins, bins holding at least 2% of pixels) | at least 5 (a plate: at least 3) | 3-5 value ramps per material (lit, mid, shade, edge, cast shadow); a gradient sky; a glow disc; a vignette |
| Texture (mean local std-dev, 8x8 blocks, flattest 30% of blocks) | reported, not gated (a smooth gradient sky is legitimately flat); aim for 2 or more over flat fills | Grain from the finish pass, stretched so it reads; hatch used as SHADING on the shaded face, never as the fill; paper or halftone tooth |

The targets are the gate's thresholds (`TH` in `fold-check.mjs`), and the gate prints the three numbers. Flat worlds (litho, flat) forbid gradients and opacity: use the §1d substitutes (offset lighter shape for the glow, border band for the vignette, hatch or halftone in an existing ink for the grain) and meet the same numbers with those. Recipe: (1) gradient sky or backdrop, never a flat rect; (2) 3-5 stops per material, light from the one key; (3) one glow with `mix-blend-mode:screen` on the focal fact; (4) grain over everything; (5) hatch lines follow the form and darken one face; (6) strokes vary in weight (heavier at the shaded edge), never one uniform hairline.

## 2. Technique catalog

These ids match the roll's `TECHNIQUES`. Each entry: when it fits, a working pattern, the motif to take from the subject, and the performance and accessibility notes. Whatever the technique, ship a finished static state (no JS, no animation).

### a. `seeded-illustration`: flat-shape scenes of the real place or object

Fits: a hero scene of the actual building, room, landscape or product; spot illustrations; process scenes. This is the ara-bar engine's real method, not a sketch of it: layered flat shapes, a limited ink set, oblique-projection objects, shading as hatching clipped by geometry, tapered strokes, and every detail taken from a fact. Copied as-is the patterns below look plain; what makes them specific is what you feed them (the real sign, the real phone number, which windows are lit, which cheese is on which quarter).

```js
import { rng, rr, blob, poly, bez, taper, hatchIn, inPoly, scatter, shape, strokeSw, shade, svg, f, STYLES } from './core.js';

// ---- oblique projection: one affine map turns a flat plan into a lid, a wall or a floor ---------
// plane(O, U, V) maps plan (u, v) to the screen with origin O and basis vectors U, V. Use it for lids and labels
// (SVG transform), and pt(u, v) for polygon corners, so every face of the object shares one projection.
export const plane = (O, U, V) => ({ m: `matrix(${U[0]} ${U[1]} ${V[0]} ${V[1]} ${O[0]} ${O[1]})`, pt: (u, v) => [O[0] + u * U[0] + v * V[0], O[1] + u * U[1] + v * V[1]] });
const rect = (x, y, w, h) => poly([[x, y], [x + w, y], [x + w, y + h], [x, y + h]]);
const open = (p, close = false) => 'M' + p.map(q => `${f(q[0])} ${f(q[1])}`).join('L') + (close ? 'Z' : '');
// Text with a PINNED width (textLength): a fallback font cannot change the layout. Swatch-named, so it is re-inked like every other shape.
const txt = (S, x, y, s, size, sw, { anchor = 'middle', len, weight = 700, mono = false } = {}) =>
  `<text x="${f(x)}" y="${f(y)}" text-anchor="${anchor}"${len ? ` textLength="${len}" lengthAdjust="spacingAndGlyphs"` : ''} font-family="${mono ? 'monospace' : 'Georgia,serif'}" font-weight="${weight}" font-size="${size}" fill="${S.palette[sw]}" data-sw="${sw}">${s}</text>`;
const veil = (S, d, sw, op) => S.shade === 'flat' ? '' : `<path d="${d}" fill="${S.palette[sw]}" data-sw="${sw}" opacity="${op}"/>`;   // tone: line worlds only; flat worlds use hard shapes

// A labelled carton, drawn from three numbers and a real label: a pizza box, a parts crate, a sample bag, a parcel.
export function carton({ w = 175, d = 125, h = 36, label = 'ARA', sub = '', key = 'box' } = {}, S = STYLES.ink) {
  const r = rng('carton:' + key), top = plane([50, 170], [1, -.257], [1, .4]);       // lid plane: U runs right and up, V runs down and right
  const A = top.pt(0, 0), B = top.pt(w, 0), C = top.pt(w, d), D = top.pt(0, d), dn = (p, k = h) => [p[0], p[1] + k];
  const lerp = (p, q, t) => [p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t];
  let o = shape(S, rect(0, 0, 400, 205), 'cladding', { line: false });                                  // dark backdrop: the steam must read against it
  o += shape(S, rect(0, 205, 400, 155), 'wood', { line: false });
  o += shape(S, poly([dn(A), dn(D), [dn(D)[0] + 14, dn(D)[1] + 10], [dn(C)[0] + 22, dn(C)[1] + 6], dn(C)]), 'shadow', { line: false });  // cast shadow
  o += shape(S, poly([A, D, dn(D), dn(A)]), 'boxDark') + shape(S, poly([D, C, dn(C), dn(D)]), 'boxDark', { shadow: 'shadow' });            // two visible walls
  o += shade(S, hatchIn(inPoly([A, D, dn(D), dn(A)]), [A[0], A[1], D[0], dn(D)[1]], 75, 4.5));                                       // hatch the shaded wall
  const ribs = (p, q) => Array.from({ length: 9 }, (_, i) => { const e = lerp(p, q, (i + 1) / 10); return `M${f(e[0])} ${f(e[1] + 8)}V${f(e[1] + h - 3)}` }).join('');
  o += strokeSw(S, ribs(A, D) + ribs(D, C), S.shade === 'flat' ? 'box' : 'ink', 1);                                                       // corrugated wall ribs
  o += shape(S, poly([dn(A, 12), dn(D, 12), dn(D, 17), dn(A, 17)]), 'shadow', { line: false });                                            // lid lip shadow
  o += shape(S, poly([A, B, C, D]), 'box');                                                                                                // lid
  o += `<g transform="${top.m}"><path d="M9 9H${w - 9}V${d - 9}H9Z" fill="none" stroke="${S.palette.boxDark}" stroke-width="1.6" data-sw="boxDark"/></g>`;   // lid panel line
  // sticker: a squashed ellipse carrying the real name, rotated, sitting on the lid
  o += `<g transform="translate(200 172) rotate(-14) scale(1 .6)">${shape(S, blob(0, 0, 50, 44, r, .02, 14), 'paper', { shadow: 'shadow' })}`
    + txt(S, 0, 10, label, 31, 'sauce') + (sub ? txt(S, 0, 24, sub, 5, 'sauce') : '') + '</g>';
  // receipt: clipped to the FRONT wall edge, hangs down the wall with a zig-zag tear at the bottom
  const E = lerp(D, C, .66);
  o += `<g transform="translate(${f(E[0])} ${f(E[1])}) rotate(-6)">${shape(S, 'M-15 2H15V52L10 57L5 52L0 57L-5 52L-10 57L-15 52Z', 'paper', { shadow: 'shadow' })}`
    + strokeSw(S, 'M-9 14H9M-9 23H9M-9 32H5M-9 41H7', 'boxDark', 1.3) + '</g>';
  // steam: two short tapered wisps rising from the vent slots, paper on navy
  for (const [p, w2] of [[[[122, 165], [112, 148], [132, 134], [118, 112]], 4.4], [[[130, 164], [138, 150], [124, 138], [136, 122]], 3.4]])
    o += shape(S, taper(bez(...p, 18), w2, .7), 'steam', { line: false });
  return svg('0 0 400 360', o, `${label} carton`);
}

// ---- a real building at dusk: sky bands, snow ridge, cladding, sign, glass, pendants, street, lamp --------------------
// The FIRST path is the sky (starts with "M-10 "): a page can cut it away by string surgery (svg.indexOf('<path d="M-10 ')).
const wavy = (y, amp, r) => { let d = `M-20 ${y}`; for (let x = -20; x < 1220; x += 110) d += `Q${x + 55} ${f(y + rr(r, -amp, amp))} ${x + 110} ${f(y + rr(r, -amp, amp) * .4)}`; return d + 'V320H-20Z' };
const RIDGE = [[-10, 240], [110, 220], [240, 204], [330, 168], [420, 202], [468, 162], [560, 154], [650, 204], [742, 146], [832, 170], [930, 196], [1040, 212], [1210, 228]];
function diner(S, x, b, r, lean = 0, glass = false) {                       // faceless: head, shoulders, nothing else
  const hd = rr(r, 9, 12);
  let o = shape(S, `M${x - 21} ${b}Q${x - 19 + lean} ${b - 36} ${x + lean} ${b - 36}Q${x + 19 + lean} ${b - 36} ${x + 21} ${b}Z`, 'woodDark', { line: false })
    + shape(S, blob(x + lean * 1.4, b - 48, hd * .85, hd, r, .05, 7), 'woodDark', { line: false });
  return glass ? o + shape(S, poly([[x + 22, b - 26], [x + 31, b - 26], [x + 29, b - 8], [x + 24, b - 8]]), 'sun', { line: false }) : o;
}
export function storefront(key, { sign = 'ARA', sub = 'RESTAURANT', phone = '554 3050', night = false } = {}, S = STYLES.ink) {
  const r = rng('store:' + key), P = S.palette, flat = S.shade === 'flat', sw = sign.length * 106;
  let o = shape(S, 'M-10 -10H1210V810H-10Z', 'skyDark', { line: false });                                        // marker: first path = sky
  if (night) for (const [x, y] of scatter(r, 60, () => true, 24, [10, 10, 1190, 200])) o += shape(S, blob(x, y, 1.6, 1.6, r, .2, 5), 'paper', { line: false });
  else {
    for (const [sw2, y, a] of [['sky', 56, 6], ['skyLow', 116, 7], ['sun', 168, 6], ['glow', 208, 5]]) o += shape(S, wavy(y, a, r), sw2, { line: false });   // dusk bands, dark to bright
    for (const [cx, cy, cw, c] of [[230, 86, 120, 'skyLow'], [880, 134, 140, 'sun'], [560, 176, 110, 'glow'], [1040, 70, 90, 'sky'], [120, 158, 80, 'sun']])   // glowing cloud lenses
      o += shape(S, `M${cx - cw} ${cy}Q${cx - cw * .4} ${cy - 9} ${cx} ${cy - 4}Q${cx + cw * .5} ${cy - 10} ${cx + cw} ${cy}Q${cx + cw * .5} ${cy + 7} ${cx} ${cy + 4}Q${cx - cw * .5} ${cy + 8} ${cx - cw} ${cy}Z`, c, { line: false });
  }
  // ridge with drip-edged snow: the snowline is knotted, with two sharp tongues running down into the gullies
  const top = RIDGE.map(([x, y]) => [x, y + rr(r, -3, 3)]);
  o += shape(S, poly([...top, [1210, 300], [-10, 300]]), 'ridge');
  const ry = x => { for (let i = 0; i < top.length - 1; i++) { const [x0, y0] = top[i], [x1, y1] = top[i + 1]; if (x >= x0 && x <= x1) return y0 + (y1 - y0) * (x - x0) / (x1 - x0) } return 240 };
  for (const [px] of [...top].sort((a, b) => a[1] - b[1]).slice(0, 3)) {
    const xa = px - 100, xb = px + 100, tongues = [0, 1].map(i => [xa + (xb - xa) * (.3 + .4 * i) + rr(r, -15, 15), rr(r, 6, 11), rr(r, 8, 12)]), knots = Array.from({ length: 30 }, () => rr(r, -2.4, 2.4));
    const up = [], lo = [];
    for (let x = xa; x <= xb; x += 2) { const t = ry(x), u = (x - xa) / 8, i = Math.floor(u); let b = ry(px) + 44 + knots[i] + (knots[i + 1] - knots[i]) * (u - i);
      for (const [g, L, wd] of tongues) if (Math.abs(x - g) < wd) b += L * (1 - Math.abs(x - g) / wd);
      if (b > t + .6) { up.push([x, t]); lo.push([x, b]) } }
    if (up.length < 3) continue;
    const cap = [...up, ...lo.reverse()];
    o += shape(S, poly(cap), 'snow', { line: false }) + shade(S, hatchIn((x, y) => x > px + 3 && inPoly(cap)(x, y), [px, 140, xb, 215], 70, 4.5));
  }
  // facade: roof lip, corrugated cladding (vertical ribs), shadow under the lip, string lights on a sagging wire
  o += shape(S, rect(-10, 250, 1220, 24), 'ink', { line: false }) + shape(S, rect(-10, 274, 1220, 240), 'cladding', { line: false });
  o += strokeSw(S, Array.from({ length: 55 }, (_, i) => `M${6 + i * 22} 278V508`).join(''), 'rib', 1.2) + shade(S, hatchIn(() => true, [-10, 274, 1210, 298], 60, 3.4));
  o += strokeSw(S, 'M0 280' + Array.from({ length: 15 }, (_, i) => `Q${40 + i * 80} 290 ${80 + i * 80} 280`).join(''), 'ink', 1.2);
  for (let x = 40; x < 1200; x += 80) o += shape(S, blob(x, 288, 3.4, 4, r, .05, 6), 'glow', { line: false });
  // sign: crest, gold name with an offset shadow, ribbon under it, the phone number as a second sign
  o += shape(S, blob(603, 311, 33, 33, r, .01, 14), 'sauce', { line: false }) + shape(S, blob(600, 308, 33, 33, r, .01, 14), 'gold') + shape(S, blob(600, 308, 28, 28, r, .01, 14), 'cladding', { line: false })
    + shape(S, poly([[587, 313], [586, 297], [593, 304], [600, 293], [607, 304], [614, 297], [613, 313]]), 'gold', { line: false }) + strokeSw(S, 'M600 312V325M594 312V317Q600 321 606 317V312', 'gold', 2.4);
  o += txt(S, 605, 457, sign, 134, flat ? 'sauce' : 'ink', { len: sw }) + txt(S, 600, 452, sign, 134, 'gold', { len: sw });
  o += shape(S, poly([[432, 478], [468, 478], [468, 506], [432, 506], [446, 492]]), 'skyLow') + shape(S, poly([[768, 478], [732, 478], [732, 506], [768, 506], [754, 492]]), 'skyLow')
    + shape(S, rect(456, 470, 288, 32), 'gold') + strokeSw(S, 'M462 475H738M462 497H738', 'cladding', 1.2) + txt(S, 600, 492, sub, 17, 'cladding', { len: 248 });
  o += shape(S, rect(900, 372, 250, 62), 'cladding', { shadow: 'sauce' }) + txt(S, 1145, 421, phone, 50, 'gold', { anchor: 'end', len: 232, weight: 400, mono: true });
  // glass front: frame, warm room, floor, TV, pendants on thin cords, diners at tables, reflections, mullions, door
  o += shape(S, rect(50, 512, 1100, 192), 'wallDark') + shape(S, rect(60, 522, 1080, 170), 'glass', { line: false }) + shape(S, rect(60, 666, 1080, 26), 'skyLow', { line: false });
  o += shade(S, hatchIn(() => true, [60, 522, 1140, 538], 60, 3.2)) + shade(S, hatchIn(() => true, [60, 668, 1140, 692], 60, 4.5));
  o += shape(S, rect(786, 566, 168, 92), 'wallDark', { line: false }) + shape(S, rect(791, 571, 158, 82), 'screen', { line: false });
  for (let i = 0; i < 12; i++) o += shape(S, blob(805 + rr(r, 0, 130), 580 + rr(r, 0, 66), 2.6, 2.6, r, .1, 5), i % 2 ? 'sauce' : 'gold', { line: false });
  for (const [x, len] of [[100, 44], [365, 66], [690, 44], [760, 72], [975, 52], [1110, 70]]) { const y = 522 + len;       // pendant: cord, cap, glowing bulb
    o += strokeSw(S, `M${x} 522V${y}`, 'wallDark', 1.4) + shape(S, rect(x - 3, y, 6, 7), 'wallDark', { line: false })
      + shape(S, `M${x - 2.5} ${y + 7}C${x - 2.5} ${y + 11} ${x - 10} ${y + 14} ${x - 10} ${y + 22}A10 10 0 0 0 ${x + 10} ${y + 22}C${x + 10} ${y + 14} ${x + 2.5} ${y + 11} ${x + 2.5} ${y + 7}Z`, 'glow') }
  for (const [tx, n] of [[262, 2], [430, 2], [1060, 2]]) {                                                                   // each table: its own diners, leans and a raised glass
    o += diner(S, tx - 26, 650, r, rr(r, -5, 5)) + diner(S, tx + 28, 650, r, rr(r, -5, 5), n > 1 && r() < .7)
      + shape(S, rect(tx - 36, 628, 72, 6), 'ink', { line: false }) + strokeSw(S, `M${tx} 634V690`, 'ink', 3) + shape(S, poly([[tx - 8, 618], [tx, 618], [tx - 1, 628], [tx - 7, 628]]), 'sun', { line: false }) }
  for (const [x, wd] of [[110, 40], [640, 60]]) o += shape(S, poly([[x, 522], [x + wd, 522], [x + wd - 50, 692], [x - 50 , 692]]), 'paper', { line: false, extra: flat ? '' : 'opacity=".16"' });   // glass shine
  for (const x of [195, 330, 465, 735, 870, 1005]) o += shape(S, rect(x - 3, 522, 6, 170), 'wallDark', { line: false });
  o += shape(S, rect(60, 556, 1080, 4), 'wallDark', { line: false }) + shape(S, rect(555, 522, 90, 170), 'wallDark', { line: false }) + shape(S, rect(562, 530, 76, 162), 'glass', { line: false })
    + strokeSw(S, 'M587 600V650M613 600V650', 'wallDark', 3.5) + shape(S, rect(530, 527, 140, 25), 'wallDark') + txt(S, 600, 546, phone, 19, 'gold', { len: 112, weight: 400, mono: true });
  // street: kerb, light spilling from each glass bay, paving slabs, shade between the light
  o += shape(S, rect(0, 704, 1200, 96), 'skyDark', { line: false }) + shape(S, rect(-10, 704, 1220, 10), 'wall');
  for (const [x0, x1] of [[80, 310], [350, 540], [660, 850], [890, 1120]]) { const sp = y => (y - 714) * .12, trap = (a, b) => poly([[x0 - sp(a), a], [x1 + sp(a), a], [x1 + sp(b), b], [x0 - sp(b), b]]);
    o += flat ? shape(S, trap(714, 750), 'glow', { line: false }) + shape(S, trap(757, 764), 'glow', { line: false }) + shape(S, trap(771, 775), 'glow', { line: false }) : veil(S, trap(714, 790), 'glow', .2) }
  o += strokeSw(S, 'M0 740H1200M0 770H1200' + Array.from({ length: 14 }, (_, k) => `M${k * 96 + 10} 715L${k * 96 - 60 + (k % 2) * 40} 800`).join(''), flat ? 'sky' : 'wall', 1.2);
  // street lamp with a halo (rings in flat worlds, tone in line worlds)
  const lp = flat ? 'sun' : 'woodDark';                                                                           // the post must read against the cladding
  o += shape(S, rect(134, 190, 12, 524), lp) + shape(S, rect(127, 690, 26, 26), lp) + strokeSw(S, 'M140 214C140 150 158 138 188 146', lp, 8);
  o += flat ? strokeSw(S, 'M160 180a30 30 0 1 0 60 0a30 30 0 1 0 -60 0', 'sun', 3) + strokeSw(S, 'M174 180a16 16 0 1 0 32 0a16 16 0 1 0 -32 0', 'sun', 3) : veil(S, 'M190 180m-46 0a46 46 0 1 0 92 0a46 46 0 1 0 -92 0', 'glow', .12) + veil(S, 'M190 180m-24 0a24 24 0 1 0 48 0a24 24 0 1 0 -48 0', 'glow', .22);
  o += shape(S, 'M177 175Q190 192 203 175Z', 'glow') + shape(S, 'M168 176C170 158 178 148 190 147C202 148 210 158 212 176Z', flat ? 'ink' : 'woodDark', { shadow: 'sauce' });
  return svg('0 0 1200 800', o, `${sign} storefront ${night ? 'at night' : 'at dusk'}`);
}

// ---- air ribbons: tapered strokes that thread through a building ---------------------------------
// flows = [{ path: [p0,p1,p2,p3, ...], sw: 'air', width: 22, z: 'back' | 'front' }]. Each ribbon is a centre line fattened by taper(), so it swells and
// ends in points. `path` chains cubic segments (4 points, 7, 10 ...). Chevrons along the ribbon show the direction of flow.
const chain = path => { const pts = []; for (let i = 0; i + 3 < path.length; i += 3) pts.push(...bez(path[i], path[i + 1], path[i + 2], path[i + 3], 18).slice(i ? 1 : 0)); return pts };
export function ribbons(flows, S = STYLES.ink) {
  return flows.map(({ path, sw, width = 20 }) => { const c = chain(path); let o = shape(S, taper(c, width, .6), sw);
    for (const t of [.3, .5, .7]) { const i = Math.floor(c.length * t), [x, y] = c[i], a = Math.atan2(c[i + 1][1] - c[i - 1][1], c[i + 1][0] - c[i - 1][0]), k = width * .22, q = (da, l) => [x + Math.cos(a + da) * l, y + Math.sin(a + da) * l];
      o += strokeSw(S, open([q(2.5, k), [x + Math.cos(a) * k * .6, y + Math.sin(a) * k * .6], q(-2.5, k)]), 'paper', 1.6) }
    return o }).join('');
}
// A flat-roofed apartment block: lit windows come from data (lit = Set of 'floor,col'), with frames, curtains, balconies, a stairwell with a door, a roof vent, a snow parapet.
// Returns { body, vent } so the caller can layer ribbons behind it and in front of it; `vent` is where a stale-air ribbon starts.
export function block(key, { floors = 4, cols = 4, lit = new Set(), x = 170, y = 110, w = 330, h = 250 } = {}, S = STYLES.ink) {
  const r = rng('block:' + key), dk = S.shade === 'flat' ? 'sky' : 'wallDark', sw = 46, cw = (w - sw) / cols, fh = h / floors, mid = Math.floor(cols / 2), cx = j => x + j * cw + (j >= mid ? sw : 0);
  let o = shape(S, rect(x, y, w, h), 'wall') + shape(S, rect(x - 8, y - 12, w + 16, 12), 'ink', { line: false });
  o += shape(S, `M${x - 8} ${y - 12}Q${x + 40} ${y - 30} ${x + 90} ${y - 12}Q${x + 150} ${y - 34} ${x + 210} ${y - 12}Q${x + 270} ${y - 28} ${x + w + 8} ${y - 12}Z`, 'snow', { line: false });
  const vx = x + w * .8; o += shape(S, rect(vx, y - 40, 22, 28), dk) + shape(S, poly([[vx - 4, y - 40], [vx + 26, y - 40], [vx + 18, y - 48], [vx + 4, y - 48]]), 'ink', { line: false });   // roof vent
  const sx = x + mid * cw;                                                                                                // stairwell: tall slim windows at half-floor steps
  o += shape(S, rect(sx, y, sw, h), dk, { line: false });
  for (let i = 0; i < floors; i++) o += shape(S, rect(sx + 14, y + i * fh + 14 + (i % 2) * 8, sw - 28, fh - 32), i % 2 ? 'glass' : 'cladding', { line: false });
  for (let i = 0; i < floors; i++) for (let j = 0; j < cols; j++) {
    const ox = cx(j) + 10, oy = y + i * fh + 12, ww = cw - 20, hh = fh - 26, on = lit.has(`${i},${j}`);
    o += shape(S, rect(ox - 3, oy - 3, ww + 6, hh + 6), 'wallDark', { line: false }) + shape(S, rect(ox, oy, ww, hh), on ? 'glass' : 'cladding', { line: false });
    if (on && r() < .6) o += shape(S, poly([[ox, oy], [ox + ww * .4, oy], [ox, oy + hh * .7]]), 'sauce', { line: false });                    // a curtain, drawn back
    o += strokeSw(S, `M${ox + ww / 2} ${oy}V${oy + hh}M${ox} ${oy + hh * .45}H${ox + ww}`, 'wallDark', 2);
    if (i > 0 && r() < .4) o += shape(S, rect(ox - 6, oy + hh + 3, ww + 12, 5), 'wallDark', { line: false }) + strokeSw(S, Array.from({ length: 6 }, (_, k) => `M${f(ox - 4 + k * (ww + 8) / 5)} ${oy + hh - 4}V${oy + hh + 3}`).join(''), 'wallDark', 1.4);   // balcony
  }
  o += shape(S, rect(sx + 10, y + h - 46, sw - 20, 46), S.shade === 'flat' ? 'skyLow' : 'woodDark') + shape(S, rect(sx + 4, y + h - 52, sw - 8, 6), 'ink', { line: false }) + shape(S, blob(sx + sw / 2, y + h - 58, 4, 4, r, .05, 6), 'glow', { line: false });   // door, canopy, lamp
  o += shape(S, rect(x - 8, y + h, w + 16, 12), dk, { line: false }) + shade(S, hatchIn(px => px > x + w - 40, [x, y, x + w, y + h], 60, 6));
  return { body: o, vent: [vx + 11, y - 48] };
}
// The finished picture: ribbons behind the facade, the block, ribbons in front. The ribbon colours are their own swatches ('air', 'stale'),
// chosen to differ from the wall, so the flow is the loudest thing on the page.
export function blockScene(key, opts = {}, S = STYLES.ink) {
  const r = rng('scene:' + key), b = block(key, opts, S), [vx, vy] = b.vent;
  const flows = opts.flows ?? [
    { path: [[-30, 290], [150, 380], [470, 170], [680, 300]], sw: 'air', width: 22, z: 'back' },        // passes BEHIND the facade: seen on both sides, hidden across the block
    { path: [[-20, 70], [90, 60], [100, 190], [210, 205]], sw: 'air', width: 18, z: 'front' },          // fresh air swoops in FRONT of the upper floors to a window
    { path: [[vx, vy], [vx - 30, 10], [520, 20], [680, 10]], sw: 'stale', width: 16, z: 'front' }];      // stale air leaves the roof vent
  let o = shape(S, 'M-10 -10H650V430H-10Z', 'skyDark', { line: false });
  for (const [px, py] of scatter(r, 28, () => true, 30, [10, 10, 630, 100])) o += shape(S, blob(px, py, 1.5, 1.5, r, .2, 5), 'paper', { line: false });
  o += shape(S, rect(-10, 372, 660, 60), S.shade === 'flat' ? 'ridge' : 'wallDark', { line: false });
  o += ribbons(flows.filter(q => q.z === 'back'), S) + b.body + ribbons(flows.filter(q => q.z !== 'back'), S);
  return svg('0 0 640 420', o, 'Air ribbons through an apartment block');
}
```

How to adapt each function to another subject:

- **`plane(O, U, V)` and `carton`.** One affine map per face makes lids, labels and floors share a projection: `pt(u, v)` for polygon corners, `m` for an SVG `transform` that lays flat artwork (a receipt, a sticker, a label with the real name) onto the face. The same trick draws a parts crate, a sample bag, a parcel, a book. Keep a cast shadow on the ground, a lip shadow under the lid and hatching on the shaded wall; those three cues are what make it read as an object.
- **`storefront`.** The recipe, in the order it is painted: sky as the FIRST path (dusk bands from dark to bright plus glowing cloud lenses, or stars at night), a ridge whose snowline is knotted with two drip tongues running into the gullies, a roof lip, cladding drawn as vertical ribs with a string-light wire sagging under the lip, a crest, the sign pinned with `textLength` over an offset shadow, a ribbon under it (`sub`), the phone number as a second sign, a glass front (pendants on cords, TV, faceless diners each with their own lean, a raised glass, glass shine), a door plate repeating the number, a street with light spilling from each bay and paving slabs, and a street lamp with a halo (rings in flat worlds, tone in line worlds). Swap the ridge for the real horizon, the sign for the real sign, the diners' count for the real seating. Faceless silhouettes only: head, shoulders, a table, a glass.
- **`block`, `ribbons` and `blockScene`.** A building whose lit windows come from data (`lit`: which units, which hours): framed windows with a seeded curtain here and a balcony there, a stairwell strip with half-floor windows and a lit door under a canopy, a roof vent and a snow parapet. `ribbons()` fattens a centre line with `taper()` so it swells and ends in points, and puts chevrons along it for the direction of flow. The ribbon inks are their OWN swatches (`air` is a saturated blue, `stale` a grey), chosen to differ from the wall, so the flow is the loudest thing on the page; a ribbon in the wall colour reads as a crack. Layering is the point: `blockScene` draws the ribbons with `z: 'back'` first, then the block, then `z: 'front'`, so one ribbon passes BEHIND the facade (seen on both sides, hidden across the block), one swoops in FRONT of the upper floors to a window, and the stale one leaves the roof vent. Replace `flows` with your own `{ path, sw, width, z }` list: air, water, a delivery route, a flow of orders. Chain 4, 7 or 10 bezier points to make a ribbon curl.
- **Textures that are marks, not noise.** Char spots, rim highlights, brick coursing in running bond, tree rings, snow caps: a few uneven shapes seeded from the item, placed where the material would show them.

Motif: signage text, the phone number, the real facade, the real horizon. Silhouettes of people have no faces. Ship the three scales: a full scene (hero), a cropped strip of it, such as the ridge with the sky cut away (divider), the sign or sticker alone (micro).

### b. `procedural-subject`: models generated from data

Fits: any catalogue where each item is different (menu, parts, plans, rooms). The drawing is a function of the item's record, so a new item is drawn without new art. The ara-bar pizzas work this way: the topping list in `specs.ts` is transcribed from `menu.ts`, so each dish on the page is the dish on the menu.

```js
import { rng, rr, blob, poly, bez, taper, scatter, shape, strokeSw, shade, hatchIn, svg, f, STYLES } from './core.js';

// One topping = one small drawing. Rules learned in critique: no eyes (flecks spread evenly), no open arcs that read as a smile.
const TOP = {
  pepperoni: (S, r) => shape(S, blob(0, 0, 10, 10, r, .035, 12), 'pepperoni', { shadow: 'shadow' })
    + (S.shade === 'hatch' ? `<path d="${blob(.9, 1, 7.4, 7.4, r, .06, 9)}" fill="${S.palette.fleck}" data-sw="fleck" opacity=".16"/>` : '')   // dished centre: a tone, so line worlds only
    + Array.from({ length: 6 }, (_, i) => { const a = i * 2.4 + rr(r, 0, 6), d = 2.5 + 5.5 * Math.sqrt((i + .5) / 6), k = rr(r, .6, 1);
      return `<path d="${poly([[-k, -k * .3], [k * .6, -k * .8], [k, k * .5], [-k * .2, k * .7]].map(([x, y]) => [x + Math.cos(a) * d, y + Math.sin(a) * d]))}" fill="${S.palette.fleck}" data-sw="fleck"/>` }).join(''),
  olive: (S, r) => shape(S, blob(0, 0, 4.6, 3.4, r, .06, 8), 'olive') + shape(S, blob(.4, .2, 1.5, 1, r, .1, 6), 'paper', { line: false }),
  basil: (S, r) => shape(S, 'M-9 0Q-4-8 9 0Q-4 8-9 0Z', 'basil') + strokeSw(S, 'M-8 0L7 0', 'ink', 1),
  bacon: (S, r) => { const ph = rr(r, 0, 6), w = (x, k) => Math.sin(x * .45 + ph + k), top = [], bot = [];
    for (let i = 0; i <= 6; i++) { const x = -10 + i * 20 / 6; top.push([x, w(x, 0) - 3.6]); bot.unshift([x, w(x, 1.3) + 3.6]) }
    return shape(S, poly([...top, ...bot]), 'bacon') },
};
// Zones: a topping may be restricted to a region. 'quad:i' = one of four wavy-bounded quarters (a four-cheese), 'ring:a-b' = a radius band.
const zone = (z, R) => {
  if (!z) return () => true;
  const [kind, arg] = z.split(':');
  if (kind === 'quad') return (x, y) => { const a = Math.atan2(y, x) + Math.PI + .35 + .28 * Math.sin(Math.hypot(x, y) / 9);
    return ((Math.floor(a / (Math.PI / 2)) % 4) + 4) % 4 === +arg };
  const [a, b] = arg.split('-').map(Number);
  return (x, y) => { const d = Math.hypot(x, y) / R; return d >= a && d <= b };
};
const TAU = Math.PI * 2;

// item = { id, rich?: true (fewer cheese blobs, more sauce showing), lift?: true (pull one slice out on cheese strands), cut?: 8 (cut lines),
//          toppings: [{ k: 'pepperoni', n: 9, zone?: 'ring:.2-.8' }] }   <- transcribed from the real menu
// The pie is built from ONE radial function rad(angle), so a lifted wedge and the body it left share exactly the same edge.
export function pizza(item, S = STYLES.ink, size = 'hero') {
  const r = rng('pizza:' + item.id), R = 90, thumb = size === 'thumb', lift = item.lift && !thumb, k = S.wobble;
  const ph = [rr(r, 0, TAU), rr(r, 0, TAU), rr(r, 0, TAU)];
  const rad = a => R * (1 + .018 * k * (Math.sin(3 * a + ph[0]) + .6 * Math.sin(7 * a + ph[1]) + .4 * Math.sin(13 * a + ph[2])));   // puffed, uneven rim
  const pts = (m, a0, a1) => { const p = []; for (let a = a0; a < a1 + .001; a += .05) p.push([Math.cos(a) * rad(a) * m, Math.sin(a) * rad(a) * m]); return p };
  const rs = (R - 14) / R, rc = R - 22;
  const mid = -.9, half = .4, w0 = mid - half, w1 = mid + half;                        // the lifted slice: a 46-degree wedge, upper right
  const side = (x, y, m) => { if (!lift) return 'main'; let d = Math.atan2(y, x) - mid; d = Math.atan2(Math.sin(d), Math.cos(d));
    const e = Math.atan2(m, Math.max(Math.hypot(x, y), m)); return Math.abs(d) < half - e ? 'wedge' : Math.abs(d) > half + e ? 'main' : 'edge' };
  const out = { main: '', wedge: '' };
  // 1. body: crust, hatch band, scorch arcs, leopard char, sauce. Built once per piece (the main body, or the wedge) from the shared rad().
  const chars = Array.from({ length: thumb ? 9 : 24 }, () => ({ a: rr(r, 0, TAU), d: R - rr(r, 3, 10), s: rr(r, 1.4, 4.6), dark: r() < .35 }));
  const scorch = [[rr(r, 0, TAU), rr(r, .3, .9)], [rr(r, 0, TAU), rr(r, .3, .8)], [rr(r, 0, TAU), rr(r, .2, .6)]];
  const body = (a0, a1) => {
    let o = shape(S, poly([[0, 0], ...pts(1, a0, a1)]), 'crust', { shadow: 'shadow' });
    if (!thumb) o += shade(S, hatchIn((x, y) => { const a = (Math.atan2(y, x) + TAU - a0 % TAU) % TAU + a0 % TAU, h = Math.hypot(x, y);   // inside this piece only
      return h > rs * R - 2 && h < R - 3 && x + y > 20 && a >= a0 && a <= a1 }, [-R, -R, R, R], 135, 5));
    for (const [a, len] of scorch) { const A = Math.max(a, a0 + .02), B = Math.min(a + len, a1 - .02);         // scorched edge: a dark arc hugging the rim
      if (B > A) o += strokeSw(S, 'M' + pts(.965, A, B).map(q => `${f(q[0])} ${f(q[1])}`).join('L'), 'crustDark', 5) }
    for (const c of chars) { if (c.a < a0 || c.a > a1) continue; const x = Math.cos(c.a) * c.d, y = Math.sin(c.a) * c.d;
      o += shape(S, blob(x, y, c.s, c.s * .7, r, .3, 6, c.a), c.dark ? 'fleck' : 'crustDark', { line: false }) }
    return o + shape(S, poly([[0, 0], ...pts(rs, a0, a1)]), 'sauce');
  };
  out.main = lift ? body(w1, w0 + TAU) : body(0, TAU);
  if (lift) out.wedge = body(w0, w1);
  // 2. cheese: overlapping melted blobs (never one slab) with sauce showing between them, plus a few blisters
  const cheese = scatter(r, thumb ? 8 : item.rich ? 11 : 17, (x, y) => Math.hypot(x, y) < rc - 6 && side(x, y, 16) !== 'edge', thumb ? 17 : 15, [-R, -R, R, R], 1500);
  for (const [x, y] of cheese) { const q = rr(r, 12, 18), to = side(x, y, 0);
    out[to] += shape(S, blob(x, y, q, q * .84, r, .2, 9), 'cheese', { shadow: 'cheeseDark' });
    if (!thumb && r() < .5) out[to] += shape(S, blob(x + rr(r, -5, 5), y + rr(r, -4, 4), rr(r, 1.6, 3), rr(r, 1.2, 2.4), r, .2, 6), 'cheeseDark', { line: false }) }
  // 3. toppings: one shared `placed` list across kinds, so an olive never sits on a pepperoni; fewer and bolder at thumb size
  const placed = [];
  for (const t of item.toppings) {
    const n = thumb ? Math.ceil(t.n / 3) : t.n, big = thumb ? 1.4 : 1, z = zone(t.zone, R), gap = thumb ? 19 : { pepperoni: 22, olive: 13, basil: 14, bacon: 20 }[t.k] ?? 14;
    for (const [x, y] of scatter(r, n, (x, y) => Math.hypot(x, y) < rc - 4 && z(x, y) && side(x, y, 11) !== 'edge' && placed.every(q => Math.hypot(q[0] - x, q[1] - y) > gap), gap, [-R, -R, R, R], 1500)) {
      placed.push([x, y]);
      out[side(x, y, 0)] += `<g transform="translate(${f(x)} ${f(y)}) rotate(${f(rr(r, 0, 360))}) scale(${big})">${TOP[t.k](S, r)}</g>`;
    }
  }
  let o = out.main;
  if (item.cut && !lift) o += strokeSw(S, Array.from({ length: item.cut }, (_, i) => { const a = (i + .5) * TAU / item.cut; return `M0 0L${f(Math.cos(a) * rad(a) * .985)} ${f(Math.sin(a) * rad(a) * .985)}` }).join(''), 'shadow', 1.6);
  if (lift) {                                                       // 4. the lifted slice pivots about the centre; cheese strands bridge the gap
    const th = 9 * Math.PI / 180, dx = Math.cos(mid) * 30, dy = Math.sin(mid) * 30;
    const T = ([x, y]) => [x * Math.cos(th) - y * Math.sin(th) + dx, x * Math.sin(th) + y * Math.cos(th) + dy];
    o += shape(S, poly([[2, 4], ...pts(1, w0, w1).map(([x, y]) => [x + 2, y + 5])].map(T)), 'shadow', { line: false });
    for (const [a, m, sag] of [[w1, .3, 12], [w1, .55, 16], [w1, .78, 10], [w0, .62, 14]]) { const p0 = [Math.cos(a) * rad(a) * m, Math.sin(a) * rad(a) * m], p1 = T(p0);
      o += shape(S, taper(bez(p0, [p0[0] + (p1[0] - p0[0]) * .3, p0[1] + sag], [p0[0] + (p1[0] - p0[0]) * .7, p1[1] + sag * .6], p1, 14), 3.4, .5), 'cheese', { shadow: 'cheeseDark', line: false }) }
    o += `<g transform="translate(${f(dx)} ${f(dy)}) rotate(9)">${out.wedge}</g>`;
  }
  return svg(lift ? '-105 -125 230 230' : '-100 -100 200 200', o, '', `pizza pizza--${size}`);
}
```

What the craft is (keep these when you swap the subject):

- **Layered construction, back to front**: cast shadow, body, hatch shading on the side away from the light, scorch arcs and char spots only where the material chars (the rim), the sauce, the cheese as overlapping blobs (17 by default; `rich` uses 11 so more sauce shows) with blisters, then the toppings. The cheese is never one slab.
- **One radial function builds every piece.** `rad(angle)` draws the puffed, uneven rim; the body and a lifted wedge are both polygons built from it, so they share an edge exactly. `lift: true` pulls a 46-degree slice out, pivoted about the centre with a shadow, and bridges the gap with four tapered cheese strands; `cut: 8` draws cut lines. Toppings and cheese are assigned to the wedge or the body by angle, and anything straddling the cut is rejected, so nothing hangs in the gap. The lifted slice is the hero shot; the whole pie is the divider; the thumb is the micro scale.
- **Distinct inks for distinct materials.** In `litho`, crust is yellow, cheese is paper, sauce is coral and char is navy; if crust and cheese share an ink they merge into one blob. The test fails when they do.
- **Zoned fills.** A topping may be restricted to a zone: `quad:i` gives four wavy-bounded quarters (a four-cheese pizza with each cheese in its own quarter), `ring:a-b` a radius band. Zones turn a list in the data into a visible structure.
- **Spacing across kinds.** One `placed` list is shared by every topping so nothing stacks.
- **Rules from critique** (they were caught in review): fat flecks spread evenly so a pepperoni never gets "eyes"; olives have an off-centre hole, not an open arc that reads as a smile; every shape is a closed blob.
- **Two sizes from one function.** `thumb` uses a third of the toppings at 1.4x and no hatching so it stays distinguishable at 96px.

Motif: the topping list, the layers of a burger (`layers: ['patty', 'cheese', 'lettuce', 'sauce']` plus a dome and a tilt), the DN size read from a product label (a filter drawing that reads W x H out of "592x592" and sizes itself, a heater that reads its kW). For a non-food catalogue the same skeleton holds: body shape from the record, parts placed in zones, marks that carry the record's fields.

### c. `traced-line`: build-time edge detection of real photos

Fits: any subject with real product photos; turns pasted catalogue photos into one-colour drafting line art. Run once at build time; the page ships a mask PNG per photo and a `bounds.json`. This is the hitataekni `design-d/scripts/trace.ts` pipeline, generalised.

Pipeline: greyscale, **paint out baked-in junk first** (warranty roundel, floor reflection, watermark: set those regions to the background value so they never produce edges), gaussian blur, Sobel gradient, non-maximum suppression (edges one pixel wide), hysteresis (a weak edge survives only when connected to a strong one), despeckle, dilate, bounding box. Every stage is a pure function on typed arrays, so it runs and tests without an image library; only `main()` needs `sharp`.

```js
// trace.mjs: build-time. Photo -> white-line RGBA PNG on transparent + bounds.json. Run: node trace.mjs
// Pipeline: grey -> mask baked-in junk -> gaussian blur -> Sobel + non-max suppression -> hysteresis -> despeckle -> dilate -> bbox.
// The stages are pure functions on Float32Array/Uint8Array so they run (and test) without an image library; only main() needs `sharp`.
export function gaussian(src, w, h) {                       // separable 5-tap binomial blur
  const k = [1, 4, 6, 4, 1], tmp = new Float32Array(src.length), out = new Float32Array(src.length), cl = (v, m) => Math.min(m - 1, Math.max(0, v));
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { let s = 0; for (let i = -2; i <= 2; i++) s += k[i + 2] * src[y * w + cl(x + i, w)]; tmp[y * w + x] = s / 16 }
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) { let s = 0; for (let i = -2; i <= 2; i++) s += k[i + 2] * tmp[cl(y + i, h) * w + x]; out[y * w + x] = s / 16 }
  return out;
}
export function sobelNms(g, w, h) {                         // gradient magnitude, thinned to 1px along the gradient direction
  const m = new Float32Array(g.length), dir = new Uint8Array(g.length), out = new Float32Array(g.length), O = [[1, 0], [1, 1], [0, 1], [-1, 1]];
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) { const i = y * w + x;
    const gx = -g[i - w - 1] - 2 * g[i - 1] - g[i + w - 1] + g[i - w + 1] + 2 * g[i + 1] + g[i + w + 1];
    const gy = -g[i - w - 1] - 2 * g[i - w] - g[i - w + 1] + g[i + w - 1] + 2 * g[i + w] + g[i + w + 1];
    m[i] = Math.hypot(gx, gy); const d = ((Math.atan2(gy, gx) * 180 / Math.PI) % 180 + 180) % 180;
    dir[i] = d < 22.5 || d >= 157.5 ? 0 : d < 67.5 ? 1 : d < 112.5 ? 2 : 3 }
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) { const i = y * w + x, [dx, dy] = O[dir[i]];
    if (m[i] >= m[i + dy * w + dx] && m[i] >= m[i - dy * w - dx]) out[i] = m[i] }
  return out;
}
export function hysteresis(mag, w, h, lo, hi) {             // Canny: a weak edge survives only when connected to a strong one
  const out = new Uint8Array(mag.length), st = [];
  for (let i = 0; i < mag.length; i++) if (mag[i] >= hi) { out[i] = 1; st.push(i) }
  while (st.length) { const i = st.pop();
    for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) { const j = i + dy * w + dx;
      if (j >= 0 && j < mag.length && !out[j] && mag[j] >= lo) { out[j] = 1; st.push(j) } } }
  return out;
}
export function despeckle(mask, w, h, min = 1) {            // keep a pixel only when >= min of its 8 neighbours are set
  const out = new Uint8Array(mask.length);
  for (let y = 1; y < h - 1; y++) for (let x = 1; x < w - 1; x++) { const i = y * w + x; if (!mask[i]) continue;
    let n = 0; for (let dy = -1; dy <= 1; dy++) for (let dx = -1; dx <= 1; dx++) if ((dx || dy) && mask[i + dy * w + dx]) n++;
    if (n >= min) out[i] = 1 }
  return out;
}
export function dilate(mask, w, h) {                        // 2x2 grow: 1px lines become a legible stroke
  const out = new Uint8Array(mask.length);
  for (let y = 0; y < h - 1; y++) for (let x = 0; x < w - 1; x++) { const i = y * w + x; if (mask[i] || mask[i + 1] || mask[i + w] || mask[i + w + 1]) out[i] = 1 }
  return out;
}
export function bbox(mask, w, h) {                          // [x0, y0, x1, y1, h] of the drawn pixels: where dimension lines attach
  let x0 = w, y0 = h, x1 = 0, y1 = 0;
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (mask[y * w + x]) { x0 = Math.min(x0, x); x1 = Math.max(x1, x); y0 = Math.min(y0, y); y1 = Math.max(y1, y) }
  return [x0, y0, x1, y1, h];
}
// opts: hi (strong threshold; lo = 0.4 hi), blank: [[x0,y0,x1,y1] in fractions] regions painted background BEFORE edge detection
// (a "5-year warranty" roundel, a floor reflection), keep: [x0,y0,x1,y1] fractions outside which edges are dropped, thick: dilate twice.
export function trace(grey, w, h, { hi = 120, blank = [], keep, thick = false, bg = 255 } = {}) {
  const g = Float32Array.from(grey);
  for (const [a, b, c, d] of blank) for (let y = Math.floor(b * h); y < Math.min(h, Math.ceil(d * h)); y++) for (let x = Math.floor(a * w); x < Math.min(w, Math.ceil(c * w)); x++) g[y * w + x] = bg;
  let mask = despeckle(hysteresis(sobelNms(gaussian(g, w, h), w, h), w, h, hi * .4, hi), w, h, 1);
  if (keep) { const [a, b, c, d] = keep; for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) if (x < a * w || x > c * w || y < b * h || y > d * h) mask[y * w + x] = 0; mask = despeckle(mask, w, h, 2) }
  mask = dilate(mask, w, h); if (thick) mask = dilate(mask, w, h);
  return { mask, bounds: bbox(mask, w, h) };
}
export const toRGBA = (mask, w, h) => { const o = Buffer.alloc(w * h * 4); for (let i = 0; i < mask.length; i++) { o[i * 4] = o[i * 4 + 1] = o[i * 4 + 2] = 255; o[i * 4 + 3] = mask[i] ? 255 : 0 } return o };

// ---- CLI: node trace.mjs  (needs `npm i -D sharp`) ----
const FILES = { 'valve-dn25': { src: 'scraped/valve-dn25.jpg', hi: 120, blank: [[.76, .7, 1, 1], [0, .84, 1, 1]] } };   // per-photo tuning lives here
async function main() {
  const sharp = (await import('sharp')).default, { writeFile } = await import('node:fs/promises'), bounds = {};
  for (const [name, { src, ...o }] of Object.entries(FILES)) {
    const { data, info } = await sharp(src).resize({ width: 1200 }).greyscale().raw().toBuffer({ resolveWithObject: true });
    const { mask, bounds: b } = trace(data, info.width, info.height, o); bounds[name] = b;
    await sharp(toRGBA(mask, info.width, info.height), { raw: { width: info.width, height: info.height, channels: 4 } }).png({ compressionLevel: 9 }).toFile(`public/art/${name}.png`);
  }
  await writeFile('src/art/bounds.json', JSON.stringify(bounds, null, 1) + '\n');
}
if (import.meta.url === `file://${process.argv[1]}`) await main();
```

Tuning: `hi` is the strong threshold (lower it for pale products, raise it for busy backgrounds); `keep` drops edges outside a box (use it for a hero render with sky and roof deck); `thick` dilates twice for a cover-size line. Keep per-photo values in `FILES`, not in the pipeline. Look at every output over the real background colour and re-tune; also paint closure strokes by hand where a panel vanishes in the photo's shadow.

Show it as a coloured mask, so the line colour stays a token:

```css
.trace { background: var(--line); -webkit-mask: var(--src) center / contain no-repeat; mask: var(--src) center / contain no-repeat; }
```
```html
<div class="trace" style="--src:url(/art/valve-dn25.png);aspect-ratio:4/3" role="img" aria-label="Belimo valve DN 25, line drawing"></div>
```

Pair it with real numbers: dimension lines at the traced bounds, labels copied from spec rows (`DN 15-25`), never invented. The `dim()` and `traceDims()` helpers are in `art/draft.js` (section d); `traceDims(bounds[name], { h: 'DN 15-25', v: '2-VEGA' })` puts a horizontal span under the object and a vertical span beside it, each with extension lines, arrowheads and a label, in the page's line colour. Perf: the PNG is one small mask per product. The whole drafting plate (the mask, the dimensions, the title block) draws in with the `pathLength` line-draw variant in section f.

### d. `mechanism-diagram`: cutaways and exploded views with callouts

Fits: products with parts, processes with steps (an air handling unit, a filter swap, a roof build-up, a lock). Plain SVG from a parts array: each part is a real drawn mechanism, not a labelled box; numbered callouts, a section cut with hatching, a scale bar, dimension lines, and a parts list cross-referenced to products or categories. The hitataekni cutaway is built exactly like this: wheel with honeycomb rings and 16 spokes, zig-zag pleated filter, coil with tube ends, backward-curved fan, eleven callouts, section A-A.

```js
import { f, hatchIn, inPoly } from './core.js';

// Drafting kit: strokes only, one colour (`currentColor` / var(--line)), numbers copied from real spec rows.
export const polar = (cx, cy, r, deg) => [cx + r * Math.cos(deg * Math.PI / 180), cy + r * Math.sin(deg * Math.PI / 180)];
export const spokes = (cx, cy, r0, r1, n, off = 0) => Array.from({ length: n }, (_, i) => { const [x0, y0] = polar(cx, cy, r0, off + i * 360 / n), [x1, y1] = polar(cx, cy, r1, off + i * 360 / n); return `M${f(x0)} ${f(y0)}L${f(x1)} ${f(y1)}` }).join('');
export const ring = (cx, cy, r) => `M${cx - r} ${cy}a${r} ${r} 0 1 0 ${2 * r} 0a${r} ${r} 0 1 0 ${-2 * r} 0`;
// backward-curved fan blades: each is a quarter-arc from the hub to the rim, bent against the rotation
export const blades = (cx, cy, r0, r1, n) => Array.from({ length: n }, (_, i) => { const a = i * 360 / n, [x0, y0] = polar(cx, cy, r0, a), [x1, y1] = polar(cx, cy, r1, a + 38);
  return `M${f(x0)} ${f(y0)}Q${f(polar(cx, cy, (r0 + r1) / 2, a - 10)[0])} ${f(polar(cx, cy, (r0 + r1) / 2, a - 10)[1])} ${f(x1)} ${f(y1)}` }).join('');
export const zigzag = (x, y, w, h, n) => `M${x} ${y + h}` + Array.from({ length: n }, (_, i) => `L${f(x + (i + .5) * w / n)} ${y}L${f(x + (i + 1) * w / n)} ${y + h}`).join('');
// perpendicular ticks along a wall: grease build-up, ruler marks, scale bars
export const ticks = (x0, y0, x1, y1, n, len = 6) => { const dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy), nx = -dy / L * len, ny = dx / L * len;
  return Array.from({ length: n }, (_, i) => { const t = (i + .5) / n; return `M${f(x0 + dx * t)} ${f(y0 + dy * t)}l${f(nx)} ${f(ny)}` }).join('') };

const T = (x, y, s, o = {}) => `<text x="${f(x)}" y="${f(y)}" ${o.anchor ? `text-anchor="${o.anchor}" ` : ''}${o.rot ? `transform="rotate(${o.rot} ${f(x)} ${f(y)})" ` : ''}fill="currentColor" stroke="none" font-family="monospace" font-size="${o.size ?? 13}">${s}</text>`;

// Dimension line: extension lines from the object's edge, an arrow-headed span, a label from a spec row.
//   axis 'h': measures a..b along x, the line sits at y=at, extension lines start at y=from.  axis 'v' is the same turned 90 degrees.
export function dim({ axis = 'h', a, b, at, from, label, head = 14 }) {
  const dir = Math.sign(at - from) || 1, past = at + dir * 8, mid = (a + b) / 2, hh = head * .4;
  return axis === 'h'
    ? `<g class="dim"><path d="M${a} ${from}V${past}M${b} ${from}V${past}M${a} ${at}H${b}M${a + head} ${at - hh}L${a} ${at}L${a + head} ${at + hh}M${b - head} ${at - hh}L${b} ${at}L${b - head} ${at + hh}"/>${T(mid, at - 8, label, { anchor: 'middle' })}</g>`
    : `<g class="dim"><path d="M${from} ${a}H${past}M${from} ${b}H${past}M${at} ${a}V${b}M${at - hh} ${a + head}L${at} ${a}L${at + hh} ${a + head}M${at - hh} ${b - head}L${at} ${b}L${at + hh} ${b - head}"/>${T(at - 8, mid, label, { anchor: 'middle', rot: -90 })}</g>`;
}
// Dimension a traced object from its bounds.json entry [x0, y0, x1, y1, h]: horizontal span under it, vertical span beside it.
export const traceDims = ([x0, y0, x1, y1], { h, v }, gap = 26) => dim({ axis: 'h', a: x0, b: x1, at: y1 + gap, from: y1 + 2, label: h }) + dim({ axis: 'v', a: y0, b: y1, at: x1 + gap, from: x1 + 2, label: v });

// Honeycomb: flat-topped hexagons on a grid, kept when their centre lies inside the ring r0..r1. A heat-recovery wheel, a filter media, a core.
export const honeycomb = (cx, cy, r0, r1, c = 7.5) => { let d = '';
  for (let i = -Math.ceil(r1 / (1.5 * c)); i <= Math.ceil(r1 / (1.5 * c)); i++) for (let j = -Math.ceil(r1 / (1.73 * c)) - 1; j <= Math.ceil(r1 / (1.73 * c)) + 1; j++) {
    const x = i * 1.5 * c, y = (j + (i & 1) * .5) * Math.sqrt(3) * c, h = Math.hypot(x, y); if (h < r0 || h > r1 - c * .6) continue;
    d += 'M' + Array.from({ length: 6 }, (_, k) => polar(cx + x, cy + y, c * .94, k * 60).map(f).join(' ')).join('L') + 'Z' }
  return d };

// Air handling unit, section A-A. PARTS come from the dossier: each part is a real product category.
// unitBody() returns the markup alone (so sheet() can place it); unit() wraps it as a standalone <svg>.
export function unitBody(PARTS, { w = 760, title = 'Section A-A', scale = '1 m' } = {}) {
  const x0 = 24, y0 = 40, x1 = x0 + w - 48, y1 = y0 + 200, cy = (y0 + y1) / 2, step = (x1 - x0) / PARTS.length;
  const casing = `<rect x="${x0}" y="${y0}" width="${x1 - x0}" height="${y1 - y0}"/><rect x="${x0 + 8}" y="${y0 + 8}" width="${x1 - x0 - 16}" height="${y1 - y0 - 16}"/>`;
  // the cut wall, hatched: hatchIn() returns PATH DATA, so it must be wrapped in a <path>; bare, it prints as stray text inside the svg
  const cut = [[x0, y0, x1, y0 + 8], [x0, y1 - 8, x1, y1]].map(([a, b, c, d]) => `<path d="${hatchIn(inPoly([[a, b], [c, b], [c, d], [a, d]]), [a, b, c, d], 45, 4)}" stroke-width="1"/>`).join('');
  const bays = PARTS.map((p, i) => { const cx = x0 + step * (i + .5);
    return `<g>${i ? `<path d="M${x0 + step * i} ${y0 + 8}V${y1 - 8}" stroke-dasharray="22 5 4 5"/>` : ''}${p.draw(cx, cy, step)}`
      + `<circle cx="${f(cx)}" cy="${y1 + 36}" r="12"/>${T(cx, y1 + 40, p.n, { anchor: 'middle', size: 12 })}${T(cx, y1 + 62, p.label, { anchor: 'middle', size: 10 })}<path d="M${f(cx)} ${y1 + 24}V${y1}" stroke-dasharray="3 3"/></g>` }).join('');
  const sb = `<path d="M${x0} ${y1 + 78}h100M${x0} ${y1 + 72}v12M${x0 + 100} ${y1 + 72}v12M${x0 + 50} ${y1 + 78}v6"/>${T(x0 + 50, y1 + 100, scale, { anchor: 'middle', size: 11 })}`;
  const air = `<path d="M${x0 - 16} ${cy}H${x0 + 6}M${x1 - 6} ${cy}H${x1 + 16}M${x0 - 4} ${cy - 6}L${x0 + 6} ${cy}L${x0 - 4} ${cy + 6}M${x1 + 10} ${cy - 6}L${x1 + 16} ${cy}L${x1 + 10} ${cy + 6}" stroke-dasharray="14 4"/>`;
  return { body: casing + cut + air + bays + sb + T(x1, y1 + 100, title, { anchor: 'end' }), box: { x0, y0, x1, y1, cy } };
}
export function unit(PARTS, { w = 760, h = 330, ...o } = {}) {
  const title = o.title ?? 'Section A-A';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h + 20}" fill="none" stroke="currentColor" stroke-width="1.5" role="img" aria-labelledby="unit-t"><title id="unit-t">${title}, ${PARTS.length} numbered parts: ${PARTS.map(p => p.label).join(', ')}</title>${unitBody(PARTS, { w, ...o }).body}</svg>`;
}

// A drawing SHEET: double border, zone markers (A-F across, 1-8 down), a faint grid, the unit with its dimensions and flow labels, extra leader callouts,
// and a title block fed by facts. Everything is strokes + text in currentColor, so the page sets one colour (and one background) for the whole plate.
//   opts: { name, rows: [[key, value] x up to 3], flow: { in, out }, dimL, dimH, notes: [{ n, label, at: [x, y] in unit coordinates, label at: [tx, ty] }] }
export function sheet(PARTS, { w = 1100, h = 640, name = 'Section A-A', rows = [], flow, dimL, dimH, notes = [], zones = [6, 8], scale = '1 m' } = {}) {
  const [zx, zy] = zones, X0 = 30, Y0 = 30, X1 = w - 30, Y1 = h - 30, ox = 130, oy = 120, u = unitBody(PARTS, { title: name, scale }), { x0, y0, x1, y1, cy } = u.box;
  let g = `<rect x="8" y="8" width="${w - 16}" height="${h - 16}"/><rect x="${X0}" y="${Y0}" width="${X1 - X0}" height="${Y1 - Y0}"/>`;
  let zm = '';                                                                                // zone markers in the border band
  for (let i = 0; i < zx; i++) { const x = X0 + (i + .5) * (X1 - X0) / zx; zm += T(x, 24, 'ABCDEFGHIJ'[i], { anchor: 'middle', size: 11 }) + T(x, h - 14, 'ABCDEFGHIJ'[i], { anchor: 'middle', size: 11 }); if (i) g += `<path d="M${X0 + i * (X1 - X0) / zx} 8V${Y0}M${X0 + i * (X1 - X0) / zx} ${Y1}V${h - 8}"/>` }
  for (let j = 0; j < zy; j++) { const y = Y0 + (j + .5) * (Y1 - Y0) / zy; zm += T(19, y + 4, j + 1, { anchor: 'middle', size: 11 }) + T(w - 19, y + 4, j + 1, { anchor: 'middle', size: 11 }); if (j) g += `<path d="M8 ${Y0 + j * (Y1 - Y0) / zy}H${X0}M${X1} ${Y0 + j * (Y1 - Y0) / zy}H${w - 8}"/>` }
  let grid = ''; for (let x = X0 + 20; x < X1; x += 20) grid += `M${x} ${Y0}V${Y1}`; for (let y = Y0 + 20; y < Y1; y += 20) grid += `M${X0} ${y}H${X1}`;
  g = `<path d="${grid}" stroke-width=".4" opacity=".22"/>` + g + zm;
  g += `<g transform="translate(${ox} ${oy})">${u.body}`;
  for (const { n, label, at: [ax, ay], to: [tx, ty] } of notes)                                  // leader callouts: a dot on the part, a leader, a numbered circle and a label
    g += `<circle cx="${ax}" cy="${ay}" r="2.5" fill="currentColor"/><path d="M${ax} ${ay}L${tx} ${ty}"/><circle cx="${tx}" cy="${ty - 4}" r="11"/>${T(tx, ty, n, { anchor: 'middle', size: 12 })}${T(tx + 16, ty, label, { size: 11 })}`;
  g += '</g>';
  if (flow) g += T(ox + x0 - 22, oy + cy - 12, flow.in, { anchor: 'end', size: 11 }) + T(ox + x1 + 22, oy + cy - 12, flow.out, { size: 11 });
  if (dimL) g += dim({ axis: 'h', a: ox + x0, b: ox + x1, at: oy + y0 - 34, from: oy + y0 - 4, label: dimL });                   // overall length over the casing
  if (dimH) g += dim({ axis: 'v', a: oy + y0, b: oy + y1, at: w - 80, from: ox + x1 + 20, label: dimH });                          // overall height, right of the unit
  const tb = rows.slice(0, 3), th = 28 * (tb.length + 1), bx = X1 - 330, by = Y1 - th;                                           // title block, bottom right, fed by facts
  g += `<rect x="${bx}" y="${by}" width="330" height="${th}"/><path d="M${bx + 110} ${by + 28}V${Y1}${tb.map((_, i) => `M${bx} ${by + 28 * (i + 1)}H${X1}`).join('')}"/>${T(bx + 8, by + 19, name, { size: 14 })}`;
  tb.forEach(([k, v], i) => { g += T(bx + 8, by + 28 * (i + 1) + 18, k, { size: 9 }) + T(bx + 118, by + 28 * (i + 1) + 19, v, { size: 12 }) });
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" fill="none" stroke="currentColor" stroke-width="1.5" role="img" aria-labelledby="sheet-t"><title id="sheet-t">${name}: ${PARTS.map(p => `${p.n} ${p.label}`).join(', ')}</title>${g}</svg>`;
}

// Each part is 3-6 primitives, and its silhouette must differ from every other part at 96px.
const wheel = (cx, cy, s) => { const R = Math.min(s * .46, 56), c = f(cx), y = f(cy);
  return `<circle cx="${c}" cy="${y}" r="${R}"/><circle cx="${c}" cy="${y}" r="${R - 4}"/><path d="${honeycomb(cx, cy, R * .3, R - 4, 6.5)}" stroke-width=".9"/><circle cx="${c}" cy="${y}" r="${f(R * .3)}"/><circle cx="${c}" cy="${y}" r="4"/><path d="${spokes(cx, cy, 4, R * .3, 16)}" stroke-width=".9"/><path d="M${f(cx + R + 6)} ${f(cy - 10)}a${R + 6} ${R + 6} 0 0 1 -9 18l-7 -9m7 9l9 -3"/>` };
export const PARTS_DEMO = [
  { n: 1, label: 'Damper', draw: (cx, cy) => `<rect x="${cx - 26}" y="${cy - 74}" width="52" height="148"/>` + Array.from({ length: 7 }, (_, i) => `<path d="M${cx - 22} ${cy - 62 + i * 21}L${cx + 22} ${cy - 50 + i * 21}"/><circle cx="${cx}" cy="${cy - 56 + i * 21}" r="2"/>`).join('') },
  { n: 2, label: 'Filter', draw: (cx, cy) => `<rect x="${cx - 24}" y="${cy - 74}" width="48" height="148"/><path d="M${cx - 20} ${cy - 66}` + Array.from({ length: 14 }, (_, i) => `L${cx + (i % 2 ? -20 : 20)} ${cy - 56 + i * 10}`).join('') + '"/>' },
  { n: 3, label: 'Heat wheel', draw: (cx, cy, s) => wheel(cx, cy, s) },
  { n: 4, label: 'Coil', draw: (cx, cy) => `<rect x="${cx - 26}" y="${cy - 74}" width="52" height="148"/>` + Array.from({ length: 9 }, (_, i) => `<path d="M${cx - 26} ${cy - 66 + i * 16.5}h52"/><circle cx="${cx - 16}" cy="${cy - 66 + i * 16.5}" r="2.5"/><circle cx="${cx + 16}" cy="${cy - 66 + i * 16.5}" r="2.5"/>`).join('') },
  { n: 5, label: 'Fan', draw: (cx, cy, s) => `<circle cx="${f(cx)}" cy="${f(cy)}" r="${f(s * .42)}"/><circle cx="${f(cx)}" cy="${f(cy)}" r="9"/><path d="${blades(cx, cy, 9, s * .42, 9)}"/>` },
  { n: 6, label: 'Silencer', draw: (cx, cy) => [-30, -10, 10, 30].map(o => `<rect x="${cx + o - 5}" y="${cy - 70}" width="10" height="140"/><path d="${ticks(cx + o - 5, cy - 66, cx + o - 5, cy + 66, 9, 5)}" stroke-width=".9"/>`).join('') },
];
export const SHEET_DEMO = {
  name: 'Section A-A', rows: [['VERKEFNI', 'Loftræsing 3. hæð'], ['MKV', '1:20'], ['DAGS', '1963-2025']], flow: { in: 'ÚTILOFT', out: 'FRÁLOFT' }, dimL: 'L = 4 200', dimH: 'H = 1 300',
  notes: [{ n: 7, label: 'Casing, 50 mm', at: [170, 234], to: [170, 324] }, { n: 8, label: 'Drain DN 25', at: [410, 234], to: [410, 324] }],
};
```

How to use it:

- **One bay per part.** `PARTS` comes from the dossier: each part is a real product category with a `draw(cx, cy, bayWidth)` that returns strokes. Compose `draw` from the helpers (`polar`, `spokes`, `ring`, `blades`, `zigzag`, `ticks`); a new part is 3-6 primitives, and its silhouette must differ from every other part at 96px (a heat wheel is not a fan).
- **Drafting conventions carry the credibility**: double-line casing with a hatched wall section, dash-dot centre-lines (`22 5 4 5`), airflow arrows on dashes, a scale bar, a title with the section name, numbers in circles with a leader.
- **`sheet(PARTS, opts)` makes it a drawing sheet**: a double border, zone markers (A-F across, 1-8 down), a faint grid, the unit with its overall `L`/`H` dimensions through `dim()`, flow labels at both ends of the dashed airflow, extra numbered leader callouts (`notes`: a dot on the part, a leader, a circled number and a label), and a title block (`rows`: key and value pairs such as the project, the scale `1:20`, the year) fed by dossier facts. Everything is strokes and text in `currentColor`. The heat wheel is a real honeycomb (`honeycomb()` keeps hexagon cells inside a ring) with 16 spokes in the hub, and the hatched casing wall is `<path>` elements: `hatchIn()` returns path data, never markup, so always wrap it. `draft.test.js` fails if path data is printed as text.
- **Dimensions are data.** `dim({ axis, a, b, at, from, label })` draws extension lines from the object's edge, an arrow-headed span and a mono label. The label is copied from a spec row (a DN range, a voltage, a service interval such as "6 MAN."), never invented.
- **Other subjects**: a hood section with grease build-up drawn as `ticks()` along the walls; an exploded filter swap with numbered steps; a roof build-up with each layer a hatched band; a lock with its pins in bays.

The `<ol>` of parts is the text equivalent and the way into the shop:

```html
<ol class="parts"><li><a href="/vorur/siur">1. Sía</a></li><li><a href="/vorur/hitahjol">2. Hitahjól</a></li></ol>
```

Use `currentColor` (the page sets `color: var(--line)` on the plate) so the drawing is one token, strokes only, and no fill can break the blueprint grammar.

### e. `annotated-photo`: leader callouts glued to a real photo

Fits: products photographed whole (a rooftop unit, a machine, a building) where the parts named in the spec rows are visible. Callouts are an overlay in percent coordinates, so they stay on the part at any width.

```html
<figure class="stage" style="--w:1600;--h:1000">
  <img src="/img/swegon.webp" width="1600" height="1000" alt="Swegon rooftop unit">
  <svg viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
    <path d="M62 38 L80 18" class="lead"/>        <!-- point on the part -> label anchor -->
  </svg>
  <a class="tag" style="left:80%;top:18%" href="#heat-recovery">Heat recovery</a>
</figure>
```
```css
.stage { position: relative; aspect-ratio: 1600 / 1000 }
.stage img, .stage svg { position: absolute; inset: 0; width: 100%; height: 100% }
.lead { fill: none; stroke: var(--ink); stroke-width: 1.5; vector-effect: non-scaling-stroke }
.tag { position: absolute; translate: 0 -100%; font: 600 .75rem var(--mono) }
```

Map image pixels to percent in one helper (`px / imgW * 100`) so coordinates come from the photo, not by eye. Label text comes from the product's own spec labels. A white casing line under the ink line keeps it readable over any pixel.

### f. `scroll-scene`: one variable drives a drawn explanation

Fits: a process or journey the company explains (air through a building, a filter clogging over twelve months, a route). One `--p` (0-1) per pinned section, written by one listener; every part of the scene reads it.

```js
// one rAF listener, passive; writes --p (0-1) on each .spread. Narrow screens and reduced motion get the FINISHED state, not a pinned scene.
const spreads = [...document.querySelectorAll('.spread')], flat = matchMedia('(max-width: 720px), (prefers-reduced-motion: reduce)');
let ticking = false;
const update = () => { ticking = false; for (const s of spreads) {
  if (flat.matches) { s.style.setProperty('--p', 1); continue }
  const b = s.getBoundingClientRect(), p = Math.min(1, Math.max(0, -b.top / (b.height - innerHeight)));
  s.style.setProperty('--p', p.toFixed(3)); } };
addEventListener('scroll', () => { if (!ticking) { ticking = true; requestAnimationFrame(update) } }, { passive: true });
addEventListener('resize', update); flat.addEventListener('change', update);
document.documentElement.classList.add('scenes'); update();
```
```css
@property --n { syntax: '<integer>'; inherits: true; initial-value: 1 }
/* the default IS the finished state: no JS, narrow, print and reduced motion all see it */
.spread__stage { --p: 1; --n: calc(1 + var(--p) * 11) }
.ribbon { stroke-dasharray: 1; stroke-dashoffset: calc(1 - var(--p)) }              /* <path pathLength="1"> */
.clog   { transform-origin: bottom; transform: scaleY(var(--p)) }
.needle { transform: rotate(calc(-84deg + var(--p) * 84deg)) }
.month::after { counter-reset: n var(--n); content: counter(n) }
/* motion is the enhancement: pin only on wide screens, with JS, when motion is allowed */
@media (min-width: 721px) and (prefers-reduced-motion: no-preference) {
  .scenes .spread { height: 300svh }
  .scenes .spread__stage { position: sticky; top: 0; height: 100svh }
}
/* progressive enhancement: no JS, off-main-thread */
@supports (animation-timeline: view()) { @media (prefers-reduced-motion: no-preference) {
  .reveal { animation: rise linear both; animation-timeline: view(); animation-range: entry 0% cover 40% } } }
@keyframes rise { from { opacity: 0; transform: translateY(24px) } to { opacity: 1; transform: none } }
```

Animate `stroke-dashoffset`, `transform`, `opacity` and `@property` counters only. Reduced motion and narrow screens show the **finished** state (`--p: 1`, unpinned). Never hide content until it animates in. Motif: the scene is the explanation of what the company sells; each spread ends on the product that does that job. Forbidden as the hero in `operate` mode (section 3).

Line-draw variant (drafting in): `<path pathLength="1" class="draft" style="--delay:calc(var(--d) * 40ms)">` with `.plate:not(.is-drafted) .draft{stroke-dasharray:1 2;stroke-dashoffset:1}` and `.is-drafted .draft{transition:stroke-dashoffset 420ms linear var(--delay)}`; set `--d` from each stroke's distance to the title-block corner, add `is-drafted` once from an `IntersectionObserver`.

### Scaling line weight with the plate (applies to f, c, d)

When a drawing scales (a plate at 360px and at 1200px), set `--k` from a ResizeObserver (`plate.style.setProperty('--k', width/1000)`) and use `stroke-width: calc(1.5px / var(--k))` and label sizes in the same variable, so strokes and labels stay legible.

### h. `material-texture`: the surface the artefact is made of

Fits: any concept whose antecedent is a physical thing (paper menu, wooden table, brushed plate, blueprint, gouache). The texture is the material, never a generic noise overlay.

```css
/* fine paper grain: data-URI feTurbulence on a pseudo-element */
.paper::after { content: ""; position: absolute; inset: 0; pointer-events: none; opacity: .06; mix-blend-mode: multiply;
  background: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='200' height='200'><filter id='n'><feTurbulence type='fractalNoise' baseFrequency='.8' numOctaves='2' stitchTiles='stitch'/></filter><rect width='100%' height='100%' filter='url(%23n)'/></svg>") }
/* wood grain: noise stretched along one axis */
.wood { background: url("data:image/svg+xml;utf8,<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600'><filter id='w'><feTurbulence type='fractalNoise' baseFrequency='0.0001 0.22' numOctaves='3'/><feColorMatrix values='0 0 0 0 .25  0 0 0 0 .14  0 0 0 0 .06  0 0 0 .5 0'/></filter><rect width='100%' height='100%' filter='url(%23w)'/></svg>"), var(--wood-base) }
/* brushed metal, no image: noise + streaks */
.brushed { background: repeating-linear-gradient(90deg, rgb(255 255 255 / .06) 0 1px, rgb(0 0 0 / .05) 1px 3px), var(--metal) }
/* blueprint grid: 16px minor, 80px major */
.grid { background:
  linear-gradient(var(--line-major) 1px, transparent 1px) 0 0 / 80px 80px,
  linear-gradient(90deg, var(--line-major) 1px, transparent 1px) 0 0 / 80px 80px,
  linear-gradient(var(--line-minor) 1px, transparent 1px) 0 0 / 16px 16px,
  linear-gradient(90deg, var(--line-minor) 1px, transparent 1px) 0 0 / 16px 16px, var(--blue) }
/* perforated ticket edge: semicircle mask */
.ticket { mask: radial-gradient(circle 6px at 0 50%, #0000 98%, #000) left / 51% 20px repeat-y,
                radial-gradient(circle 6px at 100% 50%, #0000 98%, #000) right / 51% 20px repeat-y }
```

```html
<!-- gouache edge: displacement roughens the shape, speckle and streaks come from a second noise -->
<svg width="0" height="0"><filter id="grain"><feTurbulence baseFrequency=".02" numOctaves="2" seed="3"/><feDisplacementMap in="SourceGraphic" scale="5"/></filter></svg>
```

Torn or deckled edges: `clip-path: var(--torn)` set from `torn(seed)` in §1, with a lighter back plate behind it and a `drop-shadow` filter on the wrapper for a lifted look. Pick the texture that matches the material (fine paper grain, coarse concrete, brushed aluminium).

Perf: a live filter is per-pixel; use the data-URI on a pseudo-element or a pre-rendered 256-512px tile, restrict it to sections, and **never animate the filter**. Opacity: 2-4% subtle, 5-8% visible, 10-15% strong. Measure text contrast over the texture.

### i. `print-process`: the constraint of the ink is the style

Fits: litho posters, letterpress handbills, risograph, one-ink halftones. The restriction is the identity: a fixed ink set, no gradients, no opacity, shadows as offset flat ink.

```js
// art/print.js: a print-process world = a fixed ink set. Every swatch of the base palette snaps to its nearest ink.
import { STYLES } from './core.js';
export const INKS = ['#5fb0cf', '#ffc417', '#e0643f', '#1d2a4a', '#f4ead2', '#4a8a5a'];        // sky, yellow, coral, navy, paper, green: "six inks, nothing else"
const rgb = h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16));
const dist = (a, b) => Math.hypot(...rgb(a).map((v, i) => v - rgb(b)[i]));
export const nearest = (hex, inks = INKS) => inks.reduce((m, c) => dist(c, hex) < dist(m, hex) ? c : m);
// One drawing, a third world: the line palette snapped to the inks, flat fills, offset shadows, no outline.
export const press = { ...STYLES.litho, name: 'press', palette: Object.fromEntries(Object.entries(STYLES.ink.palette).map(([k, v]) => [k, nearest(v)])) };
```
```css
/* halftone from one gradient */
.halftone { background: radial-gradient(circle, var(--ink) 30%, transparent 31%) 0 0 / 8px 8px }
/* ink-by-ink load. Drawings carry literal fills AND data-sw names, so either selector works (never var() fills: they break both) */
.poster [data-sw="sky"]    { animation: ink .5s both }
.poster [data-sw="cheese"] { animation: ink .5s 200ms both }
.poster [fill="#e0643f"]   { animation: ink .5s 400ms both }      /* by ink hex: the same press, third plate */
@keyframes ink { from { opacity: 0 } to { opacity: 1 } }
@media (prefers-reduced-motion: reduce) { .poster [data-sw], .poster [fill] { animation: none } }
```

The misregistration shadow is already in `shape()` (`shadow: 'shadow'` offsets the same path by `S.misregister`, flat worlds only), so a litho drawing needs no extra code. Add a third world by mapping the same swatch names to the six inks with `nearest()`, as `press` does above: the poster, the letterpress handbill and the match-night flyer can then be one set of drawings.

**Enforce the constraint with a test** (this is the style-rule test the art brief names): render every subject at every size and assert no opacity, no gradient, no filter and every colour in the ink set; also assert determinism and that swatch names and hexes agree. A test that passes on a drawing with a stray `opacity` is a test that does not bite: check it fails when you add one. The same goes for the markup itself: `wellFormed()` (in `art/wellformed.js`) rejects unbalanced tags and any text node outside `<text>`, which is how a path-data string pasted into an SVG (the drafting-kit hatch bug) is caught; the test file proves it bites by feeding it that exact mistake. Run it over every subject at every size.

```js
// art/wellformed.js: a small well-formedness check for the SVG strings the engine returns (no XML library needed).
// Balanced tags, quoted attributes, and NO bare text outside <text>/<title>: a path-data string pasted into the markup is exactly such a text
// node, and a renderer silently draws nothing for it.
import assert from 'node:assert/strict';
export function wellFormed(svg) {
  const stack = [], re = /<(\/?)([a-zA-Z][\w-]*)((?:\s+[\w:-]+="[^"]*")*)\s*(\/?)>|([^<]+)/gy; let m, pos = 0;
  while (pos < svg.length) { re.lastIndex = pos; m = re.exec(svg); if (!m) throw new Error('malformed markup near: ' + svg.slice(pos, pos + 60)); pos = re.lastIndex;
    if (m[5] !== undefined) { if (m[5].trim() && !['text', 'title'].includes(stack.at(-1))) throw new Error('stray text node: ' + m[5].slice(0, 60)); continue }
    if (m[4]) continue;
    if (m[1]) { if (stack.pop() !== m[2]) throw new Error('unbalanced </' + m[2] + '>') } else stack.push(m[2]) }
  assert.deepEqual(stack, [], 'unclosed tags');
  return true;
}
```

```js
// art/art.test.js: the constraint is the style, so enforce it. Run: bun test  (or: node --test)
import test from 'node:test';
import assert from 'node:assert/strict';
import { STYLES, inkSet } from './core.js';
import { pizza } from './pizza.js';
import { INKS, press } from './print.js';
import { carton, storefront, block, blockScene, ribbons } from './scene.js';
import { wellFormed } from './wellformed.js';

const item = { id: 'diavola', toppings: [{ k: 'pepperoni', n: 9 }, { k: 'olive', n: 8 }, { k: 'basil', n: 4 }] };
const doc = s => s.startsWith('<svg') ? s : `<svg>${s}</svg>`;   // block() returns bare markup
const SUBJECTS = {                                   // every subject the art brief lists, at every size it ships
  'pizza hero': S => pizza(item, S, 'hero'),
  'pizza lifted slice': S => pizza({ ...item, lift: true }, S, 'hero'),
  'pizza thumb': S => pizza({ ...item, toppings: item.toppings.slice(0, 2) }, S, 'thumb'),
  carton: S => carton({ label: 'ARA' }, S),
  storefront: S => storefront('ara', {}, S),
  'storefront night': S => storefront('ara', { night: true }, S),
  block: S => block('b', { lit: new Set(['0,1']) }, S).body + ribbons([{ path: [[0, 0], [50, 0], [50, 90], [100, 90]], sw: 'air', width: 12 }], S),
  'block scene': S => blockScene('b', { lit: new Set(['0,1', '2,2']) }, S),
};

test('wellFormed bites: it rejects stray path data and unclosed tags', () => {
  assert.throws(() => wellFormed('<svg><g>M10 10L20 20</g></svg>'), /stray text/);
  assert.throws(() => wellFormed('<svg><g></svg>'), /unbalanced/);
  assert.ok(wellFormed('<svg><text x="1">M ok</text><path d="M0 0"/></svg>'));
});

for (const [name, draw] of Object.entries(SUBJECTS)) {
  for (const S of [STYLES.ink, STYLES.litho]) test(`${S.name} ${name}: well-formed, no stray text`, () => wellFormed(doc(draw(S))));
  test(`litho ${name}: only the ink set, no opacity, no gradients, no filters`, () => {
    const out = draw(STYLES.litho), inks = inkSet(STYLES.litho);
    assert.doesNotMatch(out, /opacity|gradient|filter|<image/i);
    for (const [, hex] of out.matchAll(/(?:fill|stroke)="(#[0-9a-fA-F]{6})"/g)) assert.ok(inks.has(hex), `${hex} is not an ink`);
  });
  test(`${name}: same key, same drawing`, () => assert.equal(draw(STYLES.ink), draw(STYLES.ink)));
  test(`${name}: every drawn colour carries its swatch name`, () => {
    const out = draw(STYLES.ink);
    for (const [, hex, sw] of out.matchAll(/fill="(#[0-9a-fA-F]{6})"[^>]*?data-sw="(\w+)"/g)) assert.equal(STYLES.ink.palette[sw], hex);
  });
}
test('press: every swatch snaps to one of the six inks', () => {
  for (const hex of Object.values(press.palette)) assert.ok(INKS.includes(hex), hex);
  assert.doesNotMatch(carton({}, press), /opacity|gradient/);
});
test('draw once, style many: at equal wobble the litho shapes are a subset of the ink shapes', () => {
  const d = S => new Set([...pizza({ id: 'x', toppings: [{ k: 'olive', n: 4 }] }, S).matchAll(/ d="([^"]+)"/g)].map(m => m[1]));
  const ink = d(STYLES.ink); for (const g of d({ ...STYLES.litho, wobble: STYLES.ink.wobble })) assert.ok(ink.has(g));
});

// ---- the drawings are what they claim to be (each assertion fails on the generic version) ----
const count = (s, re) => (s.match(re) ?? []).length;
test('pizza: melted cheese is many overlapping blobs with char on the crust; crust and cheese are different inks in litho', () => {
  const p = pizza(item, STYLES.ink);
  assert.ok(count(p, /data-sw="cheese"/g) >= 12);
  assert.ok(count(p, /data-sw="crustDark"/g) + count(p, /data-sw="fleck"/g) >= 20, 'char spots');
  assert.notEqual(STYLES.litho.palette.crust, STYLES.litho.palette.cheese);
});
test('pizza: a lifted slice adds a second group and cheese strands; the thumb never lifts', () => {
  assert.match(pizza({ ...item, lift: true }, STYLES.ink), /<g transform="translate\([-\d.]+ [-\d.]+\) rotate\(9\)">/);
  assert.doesNotMatch(pizza(item, STYLES.ink), /rotate\(9\)/);
  assert.doesNotMatch(pizza({ ...item, lift: true }, STYLES.ink, 'thumb'), /rotate\(9\)/);
});
test('storefront: first path is the sky; sign, sub-ribbon, phone sign, cladding ribs, lamp and snow are all drawn', () => {
  const s = storefront('ara', { sign: 'ARA', phone: '554 3050' }, STYLES.ink);
  assert.ok(s.includes('<path d="M-10 -10') && s.indexOf('<path d="M-10 -10') < s.indexOf('data-sw="ridge"'));
  for (const t of ['>ARA<', '>RESTAURANT<', '>554 3050<']) assert.ok(s.includes(t), t);
  assert.match(s, /textLength="318"/);
  assert.ok(count(s, /data-sw="rib"/g) >= 1 && count(s, /data-sw="snow"/g) >= 3 && count(s, /data-sw="sun"/g) >= 5);
});
test('ribbons: the ribbon ink differs from the wall ink, and a back ribbon is drawn before the facade, a front one after', () => {
  for (const S of [STYLES.ink, STYLES.litho]) { assert.notEqual(S.palette.air, S.palette.wall); assert.notEqual(S.palette.air, S.palette.skyDark) }
  const s = blockScene('b', {}, STYLES.ink), air = [...s.matchAll(/data-sw="air"/g)].map(m => m.index), wall = s.indexOf('data-sw="wall"');
  assert.ok(air.some(i => i < wall) && air.some(i => i > wall), 'air ribbon both behind and in front of the facade');
  assert.match(s, /data-sw="stale"/);
});
```

```js
// art/draft.test.js: the drafting kit draws what it claims. Run: node --test
import test from 'node:test';
import assert from 'node:assert/strict';
import { unit, sheet, honeycomb, dim, PARTS_DEMO, SHEET_DEMO } from './draft.js';
import { wellFormed } from './wellformed.js';

test('unit: the hatched casing is real <path> elements, not path data printed as text', () => {
  const s = unit(PARTS_DEMO);
  assert.ok(wellFormed(s));
  assert.doesNotMatch(s, />\s*M[\d.-]+[\s,][^<]*</, 'a text node that starts with M is stray path data');
  assert.ok((s.match(/<path d="M[\d.]+ [\d.]+L[\d.]+ [\d.]+M/g) ?? []).length >= 2, 'hatch paths exist (top wall and bottom wall)');
});
test('unit: the honeycomb heat wheel has dozens of hexagonal cells, all inside the wheel', () => {
  const d = honeycomb(0, 0, 10, 50, 7);
  assert.ok((d.match(/Z/g) ?? []).length >= 30);
  for (const [, x, y] of d.matchAll(/M(-?[\d.]+) (-?[\d.]+)/g)) assert.ok(Math.hypot(+x, +y) < 52, 'cell outside the wheel');
});
test('sheet: border, zone markers A-F and 1-8, title block from facts, leader callouts, dimensions and flow labels', () => {
  const s = sheet(PARTS_DEMO, SHEET_DEMO);
  assert.ok(wellFormed(s));
  for (const t of ['A', 'F', '1', '8', 'VERKEFNI', 'MKV', '1:20', 'L = 4 200', 'H = 1 300', 'ÚTILOFT', 'FRÁLOFT', 'Casing, 50 mm', 'Heat wheel']) assert.ok(s.includes(`>${t}<`), t);
  assert.equal((s.match(/>[A-F]</g) ?? []).length, 12, 'six letters on top and bottom');
  assert.equal((s.match(/>[1-8]</g) ?? []).length >= 16, true, 'eight numbers on left and right');
  assert.doesNotMatch(s, />\s*M[\d.-]+[\s,][^<]*</);
});
test('sheet: only the title block fed by facts changes with the facts', () => {
  const a = sheet(PARTS_DEMO, SHEET_DEMO), b = sheet(PARTS_DEMO, { ...SHEET_DEMO, rows: [['VERKEFNI', 'Eldhúsháfur'], ['MKV', '1:10'], ['DAGS', '2025']] });
  assert.notEqual(a, b); assert.ok(b.includes('>Eldhúsháfur<') && !a.includes('Eldhúsháfur'));
});
test('dim: extension lines, two arrowheads and a label from the spec row', () => {
  const s = dim({ axis: 'h', a: 0, b: 100, at: 40, from: 10, label: 'DN 15-25' });
  assert.ok(s.includes('>DN 15-25<')); assert.equal((s.match(/L/g) ?? []).length >= 4, true);
});
```

Photos become one-ink halftones (see o).

### j. `typographic`: the trade's own lettering as the picture

Fits: subjects with strong lettering heritage and no imagery (a founding year, a route number, a ledger, signage, a stamp). Keep real text real.

```html
<svg viewBox="0 0 600 200" role="img" aria-label="Founded 1963">
  <defs><path id="arc" d="M30 170 Q300 -40 570 170"/></defs>
  <text font-family="var(--display)" font-size="40" letter-spacing=".08em" fill="var(--ink)"><textPath href="#arc" startOffset="50%" text-anchor="middle">HITATÆKNI · SÍÐAN</textPath></text>
</svg>
```
```css
.year { font: 800 clamp(8rem, 28vw, 24rem)/.8 var(--display); color: transparent; -webkit-text-stroke: 2px var(--ink); font-variation-settings: "wght" 800 }
.fill-pattern { background: var(--pattern) 0 0/12px 12px; -webkit-background-clip: text; background-clip: text; color: transparent }
```

A giant numeral, a word repeated as texture, text on a path. Do not split into per-letter spans without `aria-label` on the parent. Verify the face's glyphs for the content language (§6).

### k. `generative-pattern`: a mark or tile grid seeded by real values

Fits: per-item, per-section or per-person art that is reproducible and unique (a mark per SKU, a divider per section, a fabric or tile pattern from names). Generate once at build time.

```js
import { rng } from './core.js';
export function sunburst(key, { wedges = 24, r = 600, core = 'var(--yellow)' } = {}) {
  const rnd = rng('sun:' + key), start = rnd() * 15;          // each section: its own tilt
  const w = 360 / wedges;
  const d = Array.from({ length: wedges / 2 }, (_, i) => { const a0 = (start + i * 2 * w) * Math.PI / 180, a1 = a0 + w * Math.PI / 180;
    return `M0 0L${(r * Math.cos(a0)).toFixed(1)} ${(r * Math.sin(a0)).toFixed(1)}L${(r * Math.cos(a1)).toFixed(1)} ${(r * Math.sin(a1)).toFixed(1)}Z` }).join('');
  return `<svg viewBox="${-r} ${-r / 2} ${2 * r} ${r / 2}" aria-hidden="true" preserveAspectRatio="xMidYMax slice"><path d="${d}" fill="var(--ray)"/><circle r="60" fill="${core}"/></svg>`;
}
// perpendicular ticks along a path or wall: grease hatch, rulers, scale bars
export const ticks = (x0, y0, x1, y1, n, len = 6) => {
  const dx = x1 - x0, dy = y1 - y0, L = Math.hypot(dx, dy), nx = -dy / L * len, ny = dx / L * len;
  return Array.from({ length: n }, (_, i) => { const t = (i + .5) / n, x = x0 + dx * t, y = y0 + dy * t;
    return `M${x.toFixed(1)} ${y.toFixed(1)}l${nx.toFixed(1)} ${ny.toFixed(1)}` }).join('') };
```

Seed with real facts (name, coordinates, founding year, SKU): ring counts map to years, angle to wind direction, tick count to the DN size. Never use `Math.random`; never encode information only in the pattern.

### l. `data-diagram`: a bespoke chart form from real data

Fits: when the subject has numbers or structure (hours, ranges, histories, comparisons). The chart IS the illustration, and a default bar chart is not.

```js
// radial opening-hours clock from hours data: 0-24h ring, open spans as arcs, Fri/Sat run past midnight
const hours = [{ day: 'Fös', open: 11, close: 25 }];                 // 25 = 01:00 next day, as in the dossier
const arc = (r, a0, a1) => { const p = a => [r * Math.cos((a - 90) * Math.PI / 180), r * Math.sin((a - 90) * Math.PI / 180)];
  const [x0, y0] = p(a0), [x1, y1] = p(a1); return `M${x0.toFixed(1)} ${y0.toFixed(1)}A${r} ${r} 0 ${a1 - a0 > 180 ? 1 : 0} 1 ${x1.toFixed(1)} ${y1.toFixed(1)}` };
export const clock = hours.map((h, i) => `<path d="${arc(40 + i * 8, h.open * 15, h.close * 15)}" stroke="var(--ink)" stroke-width="5" fill="none"/>`).join('');
```

Also: a gauge from polar arcs and ticks; a departure-board timetable with today's row highlighted; a strata, tide or ticker-tape form. Always ship a text or table equivalent (`<table>` visually hidden, or the real hours list beside it). For colour, legend and axis rules defer to the dataviz guidance.

### m. `shader`: only when the shader is the device

Fits: a subject whose material is flowing or reactive (water, heat, aurora, ink, dither, terrain). Not a decoration for a business that does not move.

```js
// shader.js: one full-screen triangle, a noise field. Every GL call that can fail is checked, so a bad driver degrades to the CSS fallback.
const c = document.querySelector('canvas.field'), gl = c.getContext('webgl', { antialias: false, powerPreference: 'low-power' });
const still = matchMedia('(prefers-reduced-motion: reduce)');
function program(vs, fs) {
  const sh = (type, src) => { const o = gl.createShader(type); gl.shaderSource(o, src); gl.compileShader(o);
    if (!gl.getShaderParameter(o, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(o)); return o };
  const p = gl.createProgram(); gl.attachShader(p, sh(gl.VERTEX_SHADER, vs)); gl.attachShader(p, sh(gl.FRAGMENT_SHADER, fs));
  gl.bindAttribLocation(p, 0, 'a');                                   // bind BEFORE linking: location 0 is then guaranteed, not driver luck
  gl.linkProgram(p); if (!gl.getProgramParameter(p, gl.LINK_STATUS)) throw new Error(gl.getProgramInfoLog(p)); return p;
}
try {
  if (!gl) throw new Error('no webgl');
  const p = program('attribute vec2 a;void main(){gl_Position=vec4(a,0,1);}',
    `precision mediump float;uniform vec2 r;uniform float t;
     float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
     float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+1.),f.x),f.y);}
     void main(){vec2 u=gl_FragCoord.xy/r*vec2(r.x/r.y,1.)*3.;float v=n(u+t*.05)*.6+n(u*2.-t*.03)*.4;
       gl_FragColor=vec4(mix(vec3(.04,.1,.14),vec3(.2,.55,.6),smoothstep(.35,.75,v)),1.);}`);
  gl.useProgram(p);
  gl.bindBuffer(gl.ARRAY_BUFFER, gl.createBuffer()); gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
  gl.enableVertexAttribArray(0); gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  const R = gl.getUniformLocation(p, 'r'), T = gl.getUniformLocation(p, 't');
  let on = true, raf = 0, t0 = 0;
  const draw = t => { gl.uniform1f(T, t / 1000); gl.drawArrays(gl.TRIANGLES, 0, 3) };
  const frame = t => { raf = 0; if (!on || still.matches) return; draw(t); raf = requestAnimationFrame(frame) };
  const size = () => { const k = Math.min(devicePixelRatio, 2) * .75; c.width = c.clientWidth * k; c.height = c.clientHeight * k;
    gl.viewport(0, 0, c.width, c.height); gl.uniform2f(R, c.width, c.height);
    draw(t0);                                                           // resizing clears the canvas: ALWAYS redraw, also in reduced-motion mode
    if (!still.matches && !raf) raf = requestAnimationFrame(frame) };
  new IntersectionObserver(([e]) => { on = e.isIntersecting; if (on && !still.matches && !raf) raf = requestAnimationFrame(frame) }).observe(c);
  new ResizeObserver(size).observe(c);                                  // also fires once on observe(): that is the first paint
  still.addEventListener('change', size);                               // user flips reduced motion: stop, or restart, and repaint
  c.addEventListener('webglcontextlost', e => { e.preventDefault(); cancelAnimationFrame(raf); raf = 0 });
  c.addEventListener('webglcontextrestored', () => location.reload());  // simplest correct recovery for a single-program page
} catch (err) { c.hidden = true; console.warn('shader off, CSS fallback shown:', err.message) }   // .field-wrap already paints the static fallback
```

The checks matter: `getShaderParameter(COMPILE_STATUS)` and `LINK_STATUS` turn a silent black canvas into an error with the driver's log, and the catch shows the CSS fallback; `bindAttribLocation` before `linkProgram` guarantees attribute 0; a resize clears the canvas, so `size()` always redraws (otherwise a reduced-motion user, who gets one still frame and no animation loop, sees a blank canvas after rotating the phone); the reduced-motion media query is also listened to, so flipping the setting repaints or restarts correctly.

Render at 0.5-1x resolution, cap DPR at 2, pause off-screen, `aria-hidden="true"`, no text inside the canvas, give the section a static CSS fallback (`.field-wrap { background: <the still colours> }`), and check text contrast against the **brightest and darkest frames**. Use a library (OGL, Three.js) only if the device needs more than a quad. **Forbidden at hero scale in operate and read modes** (see section 3).

### n. Custom icon set (always, at micro scale)

Every project ships its own icons, not a library. 24-unit grid, one stroke width, `currentColor`, one quirk drawn from the subject (squared ends for engineering, brushed ends for craft, cut corners for stone), as a `<symbol>` sprite.

```html
<svg width="0" height="0" style="position:absolute" aria-hidden="true">
  <symbol id="i-valve" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="square">
    <path d="M3 17h18M12 17V8M8 8h8M6 12l12 5"/></symbol>
</svg>
<button><svg width="20" height="20" aria-hidden="true"><use href="#i-valve"/></svg>Panta varahlut</button>
```

Icon-only buttons need a text label (`aria-label` or visually hidden text). Compute drawn icons from primitives where you can (a football from a hexagon ring).

### o. Photos transformed, not pasted

Real photos are material. Never place a raw photo on the page.

```css
.cutout { mix-blend-mode: multiply }                                           /* white-ground cut-out onto painted paper */
.mono-plate img { filter: grayscale(1) contrast(1.05); mix-blend-mode: multiply }   /* one-signal-colour rule */
.warm img { filter: sepia(.55) saturate(1.6) hue-rotate(-6deg) }               /* match the illustrations */
.pinned { padding: 8px 8px 22px; background: var(--paper); transform: rotate(var(--tilt, 1.2deg)) }   /* pinned print */
```

Crop or clip baked-in badges and watermarks (`object-position`, a `clip-path`, or paint them out before tracing). Where there is no photo, draw it with a technique above; where a photo must stay, make it a one-ink halftone (`mix-blend-mode: multiply` over a `.halftone`), a greyscale plate or a traced line.

## 3. Lead-device tables

Subject type to lead device:

| Subject type | Lead device | Support |
|---|---|---|
| Place / travel | Traced SVG silhouette or contour lines, seeded | Grain, scroll-drawn route |
| Craft / material | Grain, texture, CSS surface pattern | Typographic numerals, custom icons |
| Tech / product | Shader or generative field, diagram of the real mechanism | Icon set, mono type |
| History / institution | Typographic illustration, data timeline | Halftone, stamp CSS art |
| Data-heavy | Bespoke data diagram | Seeded marks |

World to natural execution (guides execution only; the roll already picked the technique):

| World | Natural technique |
|---|---|
| blueprint | traced-line + mechanism-diagram |
| childrens-book | seeded-illustration + scroll-scene |
| mid-century-travel-poster | print-process |
| industrial-datasheet | annotated-photo |
| letterpress-wood-type | typographic + print-process |
| cartographic | generative contour (generative-pattern) |
| japanese-consumer-electronics-80s | material-texture + annotated-photo |
| risograph-zine, punk-zine, newsprint-tabloid | print-process (halftone, misregistration) |
| nautical-chart, field-guide-naturalist | seeded-illustration + data-diagram |
| apothecary-label, illuminated-manuscript | typographic + material-texture |
| board-game-rulebook, video-game-menu | mechanism-diagram + generative-pattern |
| scientific-journal, pharmaceutical-clinical | data-diagram + mechanism-diagram |
| transit-signage, wayfinding-aicher | typographic + generative-pattern (pictograms on a grid) |
| terminal-hacker, aviation-hud, trading-floor | data-diagram (live readouts); shader only if it is the device |
| swiss-international, bauhaus, de-stijl, constructivist, op-art, art-deco-geometric | generative-pattern (grid, geometry as the mark) |
| mid-century-corporate, dieter-rams-braun, scandinavian-functionalism | mechanism-diagram (clean product line art) + material-texture |
| vintage-analog, grunge-carson, brutalist-web, neo-brutalism | material-texture + typographic |
| museum-gallery, editorial-newspaper, japanese-editorial, luxury-fashion-editorial | annotated-photo + typographic (restrained) |
| sports-broadcast, memphis, y2k-frutiger-aero, psychedelic | generative-pattern or shader (when the world is the energy) |

For any world not listed, read its grammar and materials and apply the same rule: take the physical thing its antecedent is made of and draw it.

### Hero-forbidden devices per mode

The roll refuses these techniques as the **hero** device (they stay allowed at plate, divider or micro scale). It mirrors `HERO_FORBIDDEN` in `scripts/roll.mjs`:

| Mode | Forbidden as hero | Why |
|---|---|---|
| `operate` | `shader`, `scroll-scene` | people are doing a task: no live canvas, no pinned scroll story between them and the form |
| `read` | `shader` | long reading: a moving field fights the text |
| `persuade`, `experience` | none | the hero may carry the full device |

If every device a concept offers is forbidden for the mode, the roll keeps the concept and notes it: draw the device at plate and micro scale and open the page with a static drawing. When you hand-pick a device (a reroll or a veto), apply the same table.

## 4. Banned forms and the owner test

- No faces on food (a pepperoni that reads as a smiling face, breadsticks that look like fingers were both caught in critique), no kawaii, no mascots, no emoji-blobs.
- No stock icon libraries as the identity.
- No generic gradient blobs, meshes or noise-only heroes where a drawing of the subject belongs.
- No AI-image look.
- Staff or owner portraits only if the dossier allows them.

Test: *"Would the owner print this on their menu, van or datasheet?"* If not, redraw.

## 5. Budget and performance

- One hero device, one texture, one motion moment, under about 100KB excluding photos.
- Never animate filters. Pre-render heavy textures as tiles.
- Generate SVG once at build or load; draw canvas once unless it animates; cap DPR at 2.
- Seeded everything: a render must be identical every load.

## 6. Accessibility

- Decorative SVG gets `aria-hidden="true"`. Meaningful SVG gets `role="img"` plus `<title>` (and `aria-labelledby`), tested in context.
- Diagrams get a text or table equivalent; never encode information only in a pattern.
- Reduced motion shows the final state; narrow screens too. Nothing is hidden until it animates.
- Contrast is measured over the texture and the worst frame. Decorative saturated fields stay on graphic plates; reading, prices and forms sit on a high-contrast field.
- **Verify glyphs** for the content language: render the hero copy with the assigned face and look for fallback boxes or misleading shapes (þ ð Á Í Ö). Swap or patch a face that fails, and pin which weights ship.

## 7. Art brief, gallery and critique loop (before any UI page code)

1. **Write `.vary/art-brief.md`** with these sections:
   1. Subjects: an exhaustive list from the dossier, each with its fact ids.
   2. Engine and file layout (`art/core.js`, `art/<subject>.js`, `art/styles.js`, `art/art.test.js`).
   3. Style object(s), one per world.
   4. Banned forms (§4 plus the world's refuse list).
   5. Sizes: hero, and thumb at 96px.
   6. The style-rule test to write (for litho: "no opacity, no gradients, only the six inks").
   7. The 3 placements of the device: hero, divider, micro.
2. **Build the art module** and `art-gallery.html` rendering every subject at both sizes. Write the style-rule test and run it.
3. **Screenshot the gallery** with Playwright, `npx agent-browser` or the browser MCP, and **Read the PNGs**. Look; do not assume.
4. **Write `.vary/critique-r1.json`** as `[{"subject","problem","fix"}]` plus a 1-10 score per group. Problems are concrete ("pepperoni reads as a smiling face", "the heat wheel is indistinguishable from the fan at 96px"), never "could be better".
5. **Fix, re-render, re-screenshot, write `critique-r2.json`.** Two rounds, then build. Items still open after round 2 go into NOTES.md as `art: open — <item>` and the page ships; never start a third round.
6. No UI page code until round 2 passes.

**Art all the way down (rule).** Every section below the fold carries its own drawn plate at real size: at least 40% of that section's width (never under a third — the gate fails plates under 35%) and 280px tall at desktop, never thumbnail-only, fully rendered with the §1d finish pass and at least 3 value steps (not a thin pale line diagram in a tinted box), drawn from that section's own facts (place, product, process, people, history). A catalogue, menu or services list draws EACH item: the art engine is a function of the item record (§1), so every row or card gets its own drawing from its own fields. A section that is only cards, text or a form is a failure unless it is the contact block (or the footer). The art brief lists one plate per section.

**Collision rule (every critique round, both viewports).** Every label, callout and sign text must be fully visible: no overlap with a drawn object, another label or a UI element; no object cutting through lettering ('REPAI_RERS'); no callout hidden behind a prop; no grey smear at the scene edge. Check the 1440x900 and the 390x844 screenshots separately, zoomed on each text; list every collision as a "reads as the wrong thing" item and fix it before the round closes.

**Time budget.** The art loop is capped: two critique rounds, then build. Order: hero first, plates second (one pass each, reusing the engine and the finish pass), micro icons last. If the gallery has been rendered 6 times, stop critiquing and build the page with the art you have; a shipped page with good art beats a perfect gallery and no page. Never start a third round to polish a plate.

## 8. Generated raster images

Only for photographic material code cannot draw, and only when `impeccable/scripts/generate-image.mjs` has a key. Label it synthetic in the dossier and transform it per §2o. Code-drawn art is preferred; a generated image is never the signature device.
