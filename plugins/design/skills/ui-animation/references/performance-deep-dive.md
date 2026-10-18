# Performance Deep Dive

Advanced performance guidance beyond the quick rules in SKILL.md.

## Contents
- [Symptom table](#symptom-table)
- [Frame budget and property cost](#frame-budget-and-property-cost)
- [CSS vs JS animations](#css-vs-js-animations)
- [Web Animations API (WAAPI)](#web-animations-api-waapi)
- [CSS variables inheritance trap](#css-variables-inheritance-trap)
- [Motion transform ownership](#motion-transform-ownership)
- [Pause looping animations off-screen](#pause-looping-animations-off-screen)
- [Compositing layers and will-change](#compositing-layers-and-will-change)
- [Fix shaky 1px shifts](#fix-shaky-1px-shifts)
- [React: don't animate through state](#react-dont-animate-through-state)
- [Diagnosis order](#diagnosis-order)

## Symptom table

Match what the user sees, then read the matching section.

| Problem | Fix |
|---|---|
| Animation stutters | Animate `transform`/`opacity`, not `width`/`height`/`top`/`margin` |
| Shadow animation is choppy | Animate `filter: drop-shadow()` instead of `box-shadow` |
| Jank only during navigation or loading | Move the animation to CSS or WAAPI so it runs off the main thread |
| Motion `x`/`y` drops frames on a busy page | Animate the full `transform` string |
| Hand-rolled animation drops frames in React | Write to `ref.current.style` or a motion value, not state |
| Drag gets laggier as the list grows | Stop driving it through an inherited CSS variable; set `transform` directly |
| Long list scrolls slowly | Virtualize: render only the visible rows |
| Blur transition lags, especially in Safari | Keep animated `blur()` under 20px; 2-5px is enough to soften a crossfade |
| Unexpected properties animate | Replace `transition: all` with explicit properties |
| Element shifts 1px when motion starts or ends | `will-change: transform`, only once you see it |

## Frame budget and property cost

60fps gives the browser 16.7ms per frame; on a 120Hz screen, now most phones and many laptops, it is 8ms. Design against the smaller number, and judge on a mid-range phone, not the development laptop: a fast machine hides almost every problem below.

| Tier | Properties | Cost |
|---|---|---|
| Composite only | `transform`, `opacity` (current Chrome and Firefox also composite `filter`, `clip-path`, `background-color`; test those across browsers) | Cheapest |
| Paint + composite | `box-shadow`, `border-radius`, `color` | A redraw every frame |
| Layout + paint + composite | `width`, `height`, `padding`, `margin`, `top`, `left`, `border-width` | Most expensive; one growing element moves everything around it |

Swap down a tier: `width`/`height`/`padding` → `scale()`; `top`/`left`/`margin` → `translate()`; `display`/`visibility` → `opacity`; `box-shadow` → `filter: drop-shadow(...)`. The shadow swap is the one people miss: an animated `box-shadow` looks harmless but repaints the element every frame. A layout animation may look fine on your machine, but a `scale()` that looks the same cannot regress on a slower device, so pick the one with no downside. Layout properties also move the wrong things: animating a sidebar's `margin-left` re-lays-out the whole dashboard beside it every frame; `translateX` does not.

## CSS vs JS animations

| Approach | Driver | Interruptible | Best for |
|---|---|---|---|
| CSS transitions | Browser/compositor for transform/opacity | Yes (retargets) | Predetermined state changes |
| CSS keyframes | Browser/compositor when properties allow it | No (restarts from zero) | Looping, predetermined sequences |
| WAAPI (`el.animate()`) | Browser animation engine | Yes (cancel/reverse) | Dynamic values with imperative control |
| Motion values (`x`, `y`, `style`) | Motion DOM renderer, no React re-renders | Yes | React gestures, drag, coordinated UI |
| JS (`requestAnimationFrame`) | Main thread | Yes (manual) | Complex choreography, physics |

**Rule: CSS transitions > WAAPI > CSS keyframes > JS.** Under load (page navigation, heavy rendering), CSS animations stay smooth while JS animations drop frames.

## Web Animations API (WAAPI)

JavaScript control with CSS performance. Hardware-accelerated, interruptible, promise-based.

```ts
const animation = element.animate(
  [
    { transform: "translateY(100%)", opacity: 0 },
    { transform: "translateY(0)", opacity: 1 },
  ],
  {
    duration: 300,
    easing: "cubic-bezier(0.22, 1, 0.36, 1)",
    fill: "forwards",
  }
);

// Cancel or reverse at any time
animation.reverse();
await animation.finished;
```

## CSS variables inheritance trap

Changing a CSS variable on a parent recalculates styles for **all children**. In a drawer with many items, updating `--swipe-amount` on the container causes expensive style recalculation.

```ts
// Bad: triggers recalc on all children
element.style.setProperty("--swipe-amount", `${distance}px`);

// Good: only affects this element
element.style.transform = `translateY(${distance}px)`;
```

Exception: `@property` with `inherits: false` avoids the cascade, but browser support is limited.

## Motion transform ownership

Motion's `x`/`y` values are first-class APIs for single-axis movement and drag. They update without React re-renders and are the default choice for gesture-heavy components.

```tsx
const x = useMotionValue(0);

// Idiomatic Motion API for drag and axis movement
<motion.div drag="x" style={{ x }} />

// Use one handwritten transform string when you need to author
// multiple transform functions together or interop with non-Motion code
<motion.div animate={{ transform: "translateX(100px) rotate(4deg)" }} />
```

Do not mix Motion `x`/`y` props with a separate handwritten `transform` string on the same element. Pick one transform owner.

**When the main thread is busy, use the string form.** Motion's `x`/`y`/`scale`/`rotate` shorthands are implemented with CSS variables, and animated CSS variables are not hardware-accelerated, so they run on the main thread. Keep the shorthands by default because they read better, but switch to `animate={{ transform: "translateX(100px)" }}` for motion that plays during navigation, data fetching or hydration. Vercel's dashboard tab indicator used a shared layout animation that dropped frames exactly while the next page loaded; moving it to a CSS animation fixed it.

Acceleration is something the browser may grant, not a guarantee. Keep `translateY(100%)` for elements of unknown size even where a browser declines to accelerate percentages; correctness beats a best-effort optimization.

## Pause looping animations off-screen

Looping animations consume GPU resources even when not visible.

```ts
"use client";
import { useEffect, useRef } from "react";

export function usePauseOffscreen<T extends HTMLElement>() {
  const ref = useRef<T | null>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    const io = new IntersectionObserver(([entry]) => {
      el.style.animationPlayState = entry.isIntersecting ? "running" : "paused";
    });
    io.observe(el);
    return () => io.disconnect();
  }, []);
  return ref;
}
```

## Compositing layers and will-change

`will-change` creates a new compositor layer — this has a memory cost.

- Only promote during animation, remove after
- Only for `transform` and `opacity`
- Too many layers is worse than no promotion

```css
.animating { will-change: transform, opacity; }
```

Toggle the class on animation start, remove on `transitionend` or `animationend`.

## Fix shaky 1px shifts

Elements can shift by 1px at animation start/end due to GPU/CPU handoff. Apply `will-change: transform` during the animation (not permanently) to keep compositing on the GPU throughout.

Add `will-change` only once you have seen the shift or measured dropped frames. Browsers already promote elements that animate `transform` or `opacity`, so on the common path it does nothing except cost GPU memory. Put it on the animating element, never on `*` or a large container. Where it does earn its place is an expensive paint such as a large blurred element; keep that layer small.

## React: don't animate through state

Animation libraries animate outside React's render cycle. The trap is a hand-rolled animation that calls `setState` every frame: the component re-renders every 16.7ms and the render alone blows the budget.

```tsx
// drops frames: one re-render per frame
setY(nextY);

// smooth: no re-render
ref.current!.style.transform = `translateY(${nextY}px)`;
// or with a motion value: y.set(nextY)
```

Look for state updates inside `requestAnimationFrame`, `pointermove`, `scroll` and drag handlers.

## Diagnosis order

Name the cause before changing code; "added `will-change`, seems smoother" is not a diagnosis. Work down this list, ordered by how often each one is the cause:

1. Which properties animate? Layout properties first, then `box-shadow` and `border-radius`, which do not look like layout. Expand `transition: all` and Motion shorthands into what they really animate.
2. Does the jank coincide with the page being busy (navigation, fetching, hydration, a long task)? Move it to CSS or WAAPI.
3. Is React re-rendering per frame?
4. Does it get worse as content grows? An inherited CSS variable, or too many nodes animating at once.
5. Is a CSS variable animated at all, directly or through Motion's shorthands?
6. Any animated `blur()` above 20px?
7. Still shifting or stuttering? Now add `will-change: transform`.

Confirm with a recording, not by feel: the DevTools Performance panel for dropped frames and long tasks, profiled on a real mid-range phone over remote debugging. Desktop CPU throttling models a slow CPU, not a weak GPU or a small memory budget. Report each finding as element and `file:line`, the cause from this list, before and after, and whether it was verified from code or needs a device recording.

Credit: adapted from emilkowalski/skills skills/animation-performance/SKILL.md and performance-cheatsheet.md @ 2d22863 (MIT).
