# Animation Decision Framework

Before writing any animation code, answer these five questions in order.

## 1. Should this animate at all?

**How often will users see this animation?**

| Frequency | Examples | Decision |
|---|---|---|
| 100+ times/day | Keyboard shortcuts, command palette toggle | No animation. Ever. |
| Tens of times/day | Hover effects, list navigation | Remove or drastically reduce |
| Occasional | Modals, drawers, toasts | Standard animation |
| Rare / first-time | Onboarding, feedback forms, celebrations | Can add delight |

Never animate keyboard-initiated actions. They repeat hundreds of times daily — animation makes them feel slow and disconnected.

**Fixed-size lists:** when a list has a known maximum size, pad it to a constant slot count with invisible fillers. Nothing below the list moves when items come and go, so there is no layout shift to animate and no morph to write.

## 2. What is the purpose?

Answer "why does this animate?" before writing code.

| Purpose | Description | Example |
|---|---|---|
| **Feedback** | Confirms user action was received | Button scale on press, toggle state |
| **Orientation** | Shows spatial relationship | Drawer slides from edge, menu scales from trigger |
| **Continuity** | Preserves context across state changes | Page transitions, layout shifts |
| **Delight** | Adds personality (use sparingly) | Stagger reveals, spring overshoot |
| **Preventing a jarring change** | Bridges content that would otherwise teleport | Accordion opening, a list item appearing |
| **Explanation** | Shows how something works | Marketing or onboarding demo only |

If the purpose is just "it looks cool" and the user will see it often, don't animate.

Name the purpose in one of these words before writing code. If no word fits, the right amount of code is zero, and saying so is a good result. Delight is allowed only at the rare / first-time frequency tier.

**Function check.** Data the user is reading or acting on does not move for style. A decorative mouse-tracking tilt suits a marketing hero; on a chart in a banking dashboard it makes the numbers harder to read, so no animation is better.

**The removal test.** Ask: would the user notice, or miss something, if this animation were gone? If not, delete it. Deleting is the first fix to reach for in any review.

**State holds what is true; visuals derive from it.** Store the fact (pressed, open, progress from 0 to 1), then derive scale, opacity and offset from it by interpolation or a CSS rule keyed on the state. Never store the visual value itself. One source of truth means an interrupted or reversed animation lands correctly, and there are no two values to keep in sync.

```tsx
// fact in state, visuals derived from it
const progress = useMotionValue(0)            // 0 = closed, 1 = open
const y = useTransform(progress, [0, 1], [24, 0])
const opacity = useTransform(progress, [0, 1], [0, 1])
```

## 3. What easing should it use?

Follow this decision tree:

- **Entering the viewport?** → enter curve: `cubic-bezier(0.22, 1, 0.36, 1)`
- **Exiting the viewport?** → same curve, shorter duration
- **Sliding in from an edge (drawer, panel)?** → move curve: `cubic-bezier(0.25, 1, 0.5, 1)`
- **Repositioning or morphing an element that stays on screen (tab indicator, list reorder, A to B)?** → ease-in-out: `cubic-bezier(0.77, 0, 0.175, 1)`. It starts and settles gently, so it reads as one object travelling; an ease-out start makes an element the user is already looking at lurch.
- **Simple hover (color/opacity)?** → `200ms ease`
- **Needs physics feel?** → spring
- **Direct manipulation (drag)?** → no easing, follow the pointer
- **Constant motion (marquee, spinner) or a progress fill?** → `linear`. Progress should not ease.

Use custom easing curves. Never `ease-in` for UI: it starts slow, which delays the exact moment the user is watching, so a 200ms `ease-in` dropdown feels slower than a 200ms `ease-out` one.

**Spring or tween.** If a finger or pointer drives the motion, or the user can reverse it mid-flight, use a spring: it carries velocity through an interruption. Everything else uses a tween with the curves above.

**Extend the project's tokens.** If the codebase already has `--ease-*` or a duration scale, use it and add missing curves to it. A second, parallel set of near-identical curves is a defect, not a choice.

**Easing resources:** [easing.dev](https://easing.dev/) and [easings.co](https://easings.co/) for stronger custom variants.

## 4. How fast should it be?

| Element | Duration |
|---|---|
| Button press feedback | 100–160ms |
| Tooltips, small popovers | 125–200ms |
| Dropdowns, selects | 150–250ms |
| Modals, drawers | 200–350ms |
| Page transitions | 250–400ms |
| Illustrative / marketing | Up to 1000ms |

**Rule: keep routine UI animation under 300ms.**

### Perceived performance

Animation speed changes perceived performance:

- A fast-spinning spinner makes loading feel faster (same load time, different perception)
- `ease-out` at 200ms _feels_ faster than `ease-in` at 200ms because the user sees immediate movement
- Instant tooltips after the first one is open (skip delay + skip animation) make the toolbar feel faster

### Asymmetric timing

Enter can be slightly slower than exit. Example: hold-to-delete uses 2s linear on press, 200ms ease-out on release.

```css
/* Release: fast */
.overlay {
  transition: clip-path 200ms ease-out;
}

/* Press: slow and deliberate */
.button:active .overlay {
  transition: clip-path 2s linear;
}
```

Exit along the path it entered. A toast that slides up from the bottom leaves through the bottom; a popover that grew from its trigger shrinks back into it. Only the timing changes on exit, never the direction, which is what makes swipe-to-dismiss feel obvious.

## 5. Which tool? The cheapest that works

Walk down the table and stop at the first row that fits:

| Need | Tool |
|---|---|
| Hover, press, color, a state toggled by a class or attribute | CSS transition |
| Entry animation on mount with no JS state | CSS `@starting-style` |
| Predetermined motion that must stay smooth while the page loads or hydrates | CSS animation (runs off the main thread) |
| Programmatic control without a dependency | WAAPI (`element.animate()`) |
| Springs, layout animations, exit animations, gesture-driven values | Motion (`motion/react`) |

Do not install a motion library for a fade.

**A component, not an animation.** When the request is really a component, use a maintained primitive instead of hand-rolling motion and focus handling around a `<div>`: dialogs, popovers, menus and selects from the project's headless library (Base UI or Radix); toasts from Sonner; a command menu from cmdk; animated numbers from NumberFlow rather than re-rendering text. If the project already uses a competitor, keep it.

Credit: adapted from vercel-labs/agent-skills skills/react-view-transitions/references/patterns.md and skills/react-native-skills/rules/state-ground-truth.md @ 063bee9 (MIT).

Credit: adapted from emilkowalski/skills skills/animate/SKILL.md, skills/find-animation-opportunities/SKILL.md and skills/pick-ui-library/SKILL.md @ 2d22863 (MIT).
