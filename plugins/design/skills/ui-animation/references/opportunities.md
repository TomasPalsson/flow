# Finding Animation Opportunities

Load this when the request is "make this feel alive", "add animations to this page" or "what could animate here?" with no specific element named. The job is a filter as much as a finder: expect to reject most candidates, because an interface people use every day needs less motion, not more.

## The gate

Every candidate passes all four questions, in order. Record the answers; they go in the report.

1. **Frequency.** 100+ times a day (keyboard shortcuts, command palette, core navigation): reject. Tens of times a day (hover, list navigation, frequent toggles): reject, or near-imperceptible motion only. Occasional (modals, drawers, toasts, settings): eligible. Rare or first-time (onboarding, empty states, success, celebration): eligible, and the only place delight belongs.
2. **Purpose.** Name it in one word from [decision-framework.md](decision-framework.md) (feedback, orientation, continuity, preventing a jarring change, explanation, delight). No word, no animation.
3. **Speed.** It works inside the duration budgets (routine UI under 300ms). A moment that only works as a slow, showy animation fails.
4. **Function.** Data the user reads or acts on does not move for style.

## Where to hunt

Each seam is a known class of real opportunity:

| Seam | What to look for | Suggested motion |
|---|---|---|
| Feedback gaps | Pressable elements with no `:active` state | `transform: scale(0.97)` on `:active`, `transition: transform 160ms` with the enter curve |
| Slip-prone destructive action | A delete confirmed by a plain click | Hold-to-confirm fill ([clip-path-techniques.md](clip-path-techniques.md)): 2s linear on press, 200ms ease-out on release |
| Teleporting state | Conditional renders (`{isOpen && ...}`), `display: none` toggles, accordions that snap open | Fade plus `scale(0.95-0.97)` from `opacity: 0`, never `scale(0)`; `@starting-style` for entry without JS |
| Missing spatial story | Panels, popovers and menus with no link to their trigger; sheets that exit a different way than they entered | `transform-origin` at the trigger (modals stay centered); exit along the entry path; `translateY(100%)` rather than hard-coded pixels |
| Group entrances | A grid or list that pops in at once on a page seen occasionally | 30-50ms stagger, never blocking interaction |
| Gesture seams | Draggable or swipeable elements that snap with no physics | Spring settle, velocity-based dismissal, rubber-banding ([gesture-drag.md](gesture-drag.md)) |
| Delight budget | First-run, empty, success and completion moments rendered flat | The one place a longer beat or a small overshoot is welcome |

Useful sweeps: grep for `{isOpen &&`, `display: none` toggles, `onClick` on elements with no `:active` or `transition` style, `<details>` and accordion markup, drag handlers, `.map(` over entering lists, and empty-state or success components.

## Report

Cap it at 5-7 suggestions for a whole app, fewer for one view, ordered by leverage rather than by how fun they are to build. One row each:

| # | Location | Today | Purpose | Frequency | Suggested motion |
|---|---|---|---|---|---|
| 1 | `Toast.tsx:41` | New toasts appear instantly | Preventing a jarring change | Occasional | `@starting-style` from `opacity: 0; translateY(100%)`, 220ms enter curve, exit the same edge |

Every "Suggested motion" cell names exact properties, curve and duration, plus reduced-motion handling and hover gating where they apply.

Then list 2-5 **rejected candidates**, each with the gate question that killed it, for example: `CommandMenu.tsx:12`, palette open and close: rejected, keyboard-initiated and used 100+ times a day. This list is what separates a filter from a wishlist. If nothing survives the gate, say so plainly; that is a good result.

Credit: adapted from emilkowalski/skills skills/find-animation-opportunities/SKILL.md @ 2d22863 (MIT).
