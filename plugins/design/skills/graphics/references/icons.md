# Icons: drawing a custom set that works

An icon exists to be recognised in under a second at a small size. Identity comes second, and only where meaning stays obvious. A standard library is the right answer when it fits (operate surfaces, extend mode with an existing icon system); draw a custom set when it adds identity or clarity the library cannot.

## 1. Decide the set first

- List every icon the page needs and the job of each (nav item, category, feature, state, action). Cut icons that only decorate.
- Name the meaning of each in one word ("home", "search", "delivery"). If you cannot, it does not need an icon.
- Use the metaphor users already know: house for home, magnifier for search, cog for settings, bag or cart for basket, envelope for mail, bell for notifications. Do not reinvent standard UI icons; a brand flavour belongs on the non-standard ones (a category, a product, a feature) and on small details such as end caps and corners.
- Keep the family small and finished: 8-24 icons drawn well beat 60 drawn thinly.

## 2. One system for the whole set

| Rule | Default | Notes |
|---|---|---|
| Grid | 24 x 24 viewBox, 2px padding, live area 20 x 20 | 16, 20, 32 variants scale from this grid |
| Style | One stroke weight (1.5 or 2px at 24) OR one fill style | Never mix outline and solid in one set, except for a deliberate active state |
| Corners | One radius (0, 1, 2px or round) | Same inside and outside corners |
| Line caps and joins | One choice (round or square or butt) | Set once on the group |
| Detail | Max 3-4 shapes per icon | Remove anything that is not readable at 16px |
| Optical balance | Circles about 20px, squares about 18px, tall shapes full height | Equal visual weight, not equal bounding boxes |
| Colour | `currentColor` | Icons follow text colour, tokens and dark mode; a second tone uses `currentColor` with `opacity` only if the style allows it |

The style sheet decides the quirk: squared ends for technical, round ends for friendly, cut corners for stone or industrial, a double line for editorial. Apply it to every icon or to none.

## 3. Draw

1. Draw on the grid with `fill="none" stroke="currentColor" stroke-width="2"` (or the set's weight), `stroke-linecap` and `stroke-linejoin` on the root.
2. Snap points to whole or half pixels so 1x renders are crisp: strokes of 2px centre on integer coordinates, strokes of 1px or odd widths on .5.
3. Keep strokes optically even: where two lines meet, check the junction is not heavier than a single line.
4. Use a gap of at least 2px between parallel lines.
5. Convert text to paths or avoid text in icons.
6. Test at 16, 20, 24 and 32px, at 1x and 2x. If it fails at 16, simplify, or ship a 16px variant of that icon only.

## 4. Use and accessibility

- Navigation: always a visible label beside the icon. Icon-only is for universally known actions (close, search, menu) in toolbars.
- Icon-only buttons and links need an accessible name: `aria-label="Search"` on the control, with the SVG `aria-hidden="true"`. An icon next to a label is `aria-hidden="true"`.
- Targets are at least 44 x 44px on touch (padding around a 24px icon is fine).
- Never carry meaning by colour alone (a red or green icon needs a shape difference or a label). Contrast of an informative icon against its background is at least 3:1.
- State changes (selected, disabled) change more than colour: weight, fill or a mark.

## 5. Deliver

- Either one SVG sprite (`<symbol id="i-name" viewBox="0 0 24 24">` per icon, referenced with `<use href="#i-name">`) or individual files `icon-<name>.svg`. A sprite inlined into a page uses unique ids and no `<clipPath>`/`<filter>` ids; individual files suit img tags and build pipelines.
- Icons carry no hard-coded colour; the page sets `color`.
- A preview sheet `icons-preview.html` (and a PNG): every icon at 16, 24 and 32px, on light and dark backgrounds, with its name. Render it at 1x and 2x, Read the PNGs, fix, and only then deliver.
- List each icon in `assets/art/GRAPHICS.md` with its file or symbol id, the label or `aria-label` to use, and where it is placed.

## 6. Mistakes to catch in the preview

- Two weights or two corner radii in one set.
- An icon that fills more of the box than its neighbours.
- A custom metaphor for a standard action.
- A detail that disappears at 16px.
- Icons that need a legend to be understood.
- Fixed colours that break in dark mode.

## 7. Optical sizing and variants

- Draw at 24. For 16px use, remove inner detail and keep the live area 12px; ship a 16px variant of an icon that fails the test.
- For 32px and larger, keep the stroke weight deliberate: a 2px stroke on a 48px icon looks thin next to bold text.
- A selected or active state may switch outline to solid inside the same shape; draw both from one outline so they stay in register.
- Align the icon with text by visual centre (the x-height centre), not the line box.

## 8. Brand flavour without losing meaning

- Flavour lives in details that do not change the metaphor: end caps, corner radius, one signature cut or notch, a second tone on one part.
- Test with someone who has not seen the set: show the icon without its label and ask what it does. If the answer is wrong, revert to the standard metaphor.
- Never use a mascot, logo or product photo as a nav icon.
