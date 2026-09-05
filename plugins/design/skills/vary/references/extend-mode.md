---
name: extend-mode
description: What to do when the repo already has a visual system (DESIGN.md, tokens, a themed Tailwind config, styled shared components) or the task is a section/component inside an established surface. No world roll; distinctiveness moves into details. Load from Step 0 when such evidence exists.
---

# Extend mode

Visual authority is evidence, not a filename. A missing DESIGN.md does not make a project greenfield: a coherent identity already in code (tokens, a themed config, consistent components across pages) is the strongest possible lock. A local addition inherits its surface; it never becomes a new identity exercise.

## 1. Detect

Look for, in this order: `DESIGN.md` or `design.md`; a token file (`tokens.*`, `theme.*`, CSS custom properties on `:root` with brand colours); a Tailwind/Panda/vanilla-extract theme with non-default colours or fonts; a `components/ui` folder with styled primitives; existing pages sharing one palette and type. Two or more agreeing sources = an established world. One weak source (default shadcn with no custom tokens) = incomplete brand: preserve confirmed assets, then expand with the user.

## 2. What still rolls, what does not

| Situation | Roll? | Command |
|---|---|---|
| New component / section / state inside an existing page | No | — |
| New whole page inside an established system | Skeleton only | `node roll.mjs --mode <m> --lock display=<id> --lock body=<id> --lock palette=#<brand>`; if the system's fonts are not catalog ids, run `--canon` for the skeleton and keep the system's faces |
| Redesign explicitly requested ("replace the look") | Yes, full roll | Treat the old look as evidence of what the subject is, not authority over what it becomes; replace DESIGN.md at the end from the built result |
| Incomplete brand (a logo and one hex) | Yes, with locks | `--lock palette=#hex`; the roll supplies world, skeleton and type |

Never split the difference: polish on a discarded look, or a new identity smuggled into one component, are both failures.

## 3. Where distinctiveness lives when the system is fixed

The system owns palette, type and components. The page still has to be designed:

- **Skeleton**: the archetype is a free axis. A docs page in an existing system can be an index-list or a broadsheet; a settings page can be card-less tables. Pick from `data/archetypes.json` by the surface's mode; do not default to the system's other pages' skeleton unless consistency is the explicit brief.
- **Spacing rhythm and density** tuned to this page's content, inside the token scale.
- **The one authored motion moment**, in the system's easing.
- **States**: empty, error, loading and success screens designed for this page's real cases, in the system's vocabulary.
- **Browser surfaces**: selection, caret, focus ring, scrollbar, tabular numerals, underline offset — themed from the system's tokens if the system forgot them.
- **Copy** that only this product could say; buttons that name outcomes.
- **Numerals and data typography** where the page carries figures.

Then Step 3 onward of SKILL.md applies unchanged (build fully, `check.mjs`, separate evaluation). The evaluator receives a contract block written by hand in the same field order, with WORLD set to `system: <name>` and GRAMMAR listing the system's own rules as found in code.

## 4. Recording

On a redesign or a new world, DESIGN.md is written **after** the build, from what was actually shipped (tokens as used, faces as loaded, the archetype as built). A rulebook written before the build gets defended against reality instead of describing it. Ordinary extensions do not rewrite DESIGN.md. Never write `.vary/recent.json` into version control (roll.mjs gitignores it).
