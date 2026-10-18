# Animation Review Format

## Before/After/Why table

Use a markdown table. One row per issue.

| Before | After | Why |
|---|---|---|
| `transition: all 300ms` | `transition: transform 200ms ease-out` | Specify exact properties; avoid `all` |
| `transform: scale(0)` | `transform: scale(0.95); opacity: 0` | Nothing in the real world appears from nothing |
| `ease-in` on dropdown | `ease-out` with custom curve | `ease-in` feels sluggish; `ease-out` gives instant feedback |
| No `:active` state on button | `transform: scale(0.97)` on `:active` | Buttons must feel responsive to press |
| `transform-origin: center` on popover | `transform-origin: var(--radix-popover-content-transform-origin)` | Popovers scale from trigger (modals stay centered) |

## Review checklist

| Issue | Fix |
|---|---|
| `transition: all` | Target specific properties |
| Layout property animated (`width`, `height`, `top`, `left`) | Switch to `transform` and `opacity` |
| `ease-in` on UI entrance | Use enter easing: `cubic-bezier(0.22, 1, 0.36, 1)` |
| Permanent `will-change` | Toggle during animation only |
| `scale(0)` start | Use `scale(0.85–0.95)` with `opacity: 0` |
| No touch device guard on hover | Add `@media (hover: hover) and (pointer: fine)` |
| Symmetric enter/exit timing | Make exit 20–30% faster than enter |
| CSS variable drag animation | Use `transform` directly on the element |
| Missing `setPointerCapture` on drag | Add pointer capture for reliable tracking |
| Motion `x`/`y` mixed with a handwritten `transform` | Pick one transform owner for the element |
| Animation on keyboard action | Remove animation entirely |
| Duration > 300ms on UI element | Reduce to 150–250ms |
| Keyframes on rapidly-triggered element | Use CSS transitions for interruptibility |
| Hard cut between views sharing elements | Add shared-element transition; animate persistent components in place |
| Contextual overlay enters from centre | Set `transform-origin` to trigger; animate outward from source element |
| Elements all appear at once | Add stagger delay (30–50ms between items) |
| Movement with no `prefers-reduced-motion` path | Gentler variant: keep opacity/color, drop movement |
| Built-in `ease`/`ease-out` on a deliberate entrance | Strong custom curve, e.g. `cubic-bezier(0.22, 1, 0.36, 1)` |
| Motion `x`/`y` shorthands on motion that plays during navigation or loading | Full `transform` string |
| Press-and-release or hold with symmetric timing | Slow the deliberate phase, snap the response |

## Fix order

Prefer earlier moves over later ones when proposing fixes:

1. **Delete it**: high frequency, keyboard-triggered, or no nameable purpose.
2. **Reduce it**: shorter, smaller transform, fewer properties.
3. **Fix the easing**: `ease-in` → enter curve; a strong custom curve over a built-in one.
4. **Fix the origin**: `transform-origin` at the trigger; `scale(0)` → `scale(0.95)` + opacity.
5. **Make it interruptible**: keyframes → transitions; a spring for gesture-driven motion.
6. **Move it to the compositor**: layout properties → `transform`/`opacity`.
7. **Asymmetric timing**: slow the deliberate phase, snap the system's response.
8. **Polish**: blur-masked crossfade, stagger, `@starting-style`.
9. **Accessibility and cohesion**: reduced motion, hover gating, match the product's personality.

## Verdict

Group the commentary after the table by impact, highest first, and omit empty groups: feel-breaking regressions, motion that should be removed, performance, interruptibility and timing, origin and cohesion, accessibility. Cite `file:line`. Close with one decision:

- **Block**: any feel-breaking regression, animation on a keyboard or 100+/day action, `scale(0)` or `ease-in` on UI, or a layout-property animation with an easy compositor fix.
- **Approve**: none of the above, durations and easing in bounds, interruptibility handled where needed, reduced motion respected.

When feel cannot be judged from code (a crossfade, a spring's bounce), say so and name the check instead of guessing a value.

## Auditing a whole codebase

When asked to "improve the animations" across an app rather than review one diff:

1. **Recon.** Note the motion library, the component library, existing `--ease-*`/duration tokens (fixes extend them) and the product's personality. Grep for `transition`, `animation`, `@keyframes`, `motion.`, `animate={`, `useSpring`, `ease-in`, `transition: all`, `scale(0)`, `prefers-reduced-motion`, `transform-origin`.
2. **Frequency map.** Sort the animated surfaces into 100+/day, tens/day, occasional and rare. Frequency sets severity.
3. **Vet.** Re-read every finding at its `file:line` before reporting it, and drop exemptions (a centered modal, a long duration on a marketing page) and documented deliberate choices.
4. **Rank** in one table by leverage: HIGH is feel-breaking (wrong easing on UI, animation on keyboard or high-frequency actions, dropped frames, `scale(0)`); MEDIUM is noticeably off (wrong origin, non-interruptible dynamic UI, missing reduced motion); LOW is polish (stagger, token consolidation). List 2-4 missed opportunities separately, using [opportunities.md](opportunities.md).
5. **Fix specs.** When fixes go to another agent, each spec inlines the file path, the current code, the exact target values (curve, duration, spring config), the scope boundary, and a feel check ("spam the toggle: it never restarts from zero"; "Rendering panel, reduced motion on: movement drops, opacity stays").

## Component design principles

- **Good defaults over options.** Most users never customise. The default easing, timing, and design should be excellent out of the box.
- **Transitions over keyframes for dynamic UI.** Elements added rapidly (toasts, list items) need interruptible animations. Keyframes restart from zero on interruption; transitions retarget smoothly.
- **Cohesion.** The animation style should match the component's personality. A playful component can be bouncier. A professional dashboard should be crisp and fast.
- **Invisible edge cases.** Pause timers when the tab is hidden. Fill gaps between stacked elements with pseudo-elements to maintain hover state. Capture pointer events during drag.

## Debugging animations

- **Slow motion:** Temporarily increase duration to 2–5x or use the browser animation inspector. Check colour timing, easing, and transform-origin.
- **Frame-by-frame:** Step through in Chrome DevTools Animations panel to reveal timing issues between coordinated properties.
- **Real devices:** For touch interactions (drawers, swipe gestures), test on physical devices. The Xcode Simulator works but real hardware is better for gesture testing.
- **Review next day:** You notice imperfections with fresh eyes that you missed during development.

Credit: adapted from emilkowalski/skills skills/review-animations/SKILL.md and skills/improve-animations/SKILL.md @ 2d22863 (MIT).
