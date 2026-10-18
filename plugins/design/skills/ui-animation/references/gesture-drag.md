# Gesture and Drag Animations

Patterns for drag, swipe, and gesture interactions where the user directly manipulates elements.

## Contents
- [Momentum-based dismissal](#momentum-based-dismissal)
- [Boundary damping](#boundary-damping)
- [Pointer capture](#pointer-capture)
- [Multi-touch protection](#multi-touch-protection)
- [Friction vs hard stops](#friction-vs-hard-stops)
- [Swipe-to-dismiss pattern](#swipe-to-dismiss-pattern)
- [Grab from the current value](#grab-from-the-current-value)
- [Direction lock](#direction-lock)
- [Velocity handoff](#velocity-handoff)
- [Momentum projection](#momentum-projection)

## Momentum-based dismissal

Don't require dragging past a distance threshold. Calculate velocity at release — a quick flick should be enough to dismiss.

```ts
function onPointerUp(e: PointerEvent) {
  const timeTaken = Date.now() - dragStartTime;
  const velocity = Math.abs(swipeAmount) / timeTaken;

  if (Math.abs(swipeAmount) >= SWIPE_THRESHOLD || velocity > 0.11) {
    dismiss();
  } else {
    snapBack();
  }
}
```

Use velocity > 0.11 as a reasonable default threshold. Combine with a minimum distance threshold (e.g. 20px) to prevent accidental dismissals.

## Boundary damping

When a user drags past the natural boundary (e.g. pulling a drawer up when already at top), apply damping. The more they drag, the less the element moves.

```ts
function applyDamping(offset: number, max: number): number {
  return max * (1 - Math.exp(-offset / max));
}

// Usage: as offset grows, movement diminishes
const dampedOffset = applyDamping(rawOffset, 200);
```

Things in real life don't suddenly stop — they slow down first. Friction instead of hard stops always feels more natural.

Apple's rubber-band curve, the iOS overscroll feel, scales the resistance to the element's size:

```ts
// constant 0.55 matches iOS; dimension is the element's size on that axis
function rubberband(overshoot: number, dimension: number, constant = 0.55): number {
  return (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));
}
```

## Pointer capture

Once dragging starts, capture all pointer events on the element. This ensures dragging continues even if the pointer leaves the element bounds.

```ts
function onPointerDown(e: PointerEvent) {
  (e.target as HTMLElement).setPointerCapture(e.pointerId);
  isDragging = true;
}

function onPointerUp(e: PointerEvent) {
  (e.target as HTMLElement).releasePointerCapture(e.pointerId);
  isDragging = false;
}
```

Always use `setPointerCapture` — without it, fast swipes escape the element and the drag breaks.

## Multi-touch protection

Ignore additional touch points after the initial drag begins. Without this, switching fingers mid-drag causes the element to jump.

```ts
let activeTouchId: number | null = null;

function onPointerDown(e: PointerEvent) {
  if (activeTouchId !== null) return; // Ignore additional touches
  activeTouchId = e.pointerId;
  // Start drag...
}

function onPointerUp(e: PointerEvent) {
  if (e.pointerId !== activeTouchId) return;
  activeTouchId = null;
  // End drag...
}
```

## Friction vs hard stops

Instead of preventing drag past a boundary, allow it with increasing friction:

```ts
function applyFriction(delta: number, isAtBoundary: boolean): number {
  if (!isAtBoundary) return delta;
  return delta * 0.3; // 30% of movement at boundary
}
```

Hard stops feel broken — users expect physics. Apply friction for scroll containers, sliders, and drawers.

## Swipe-to-dismiss pattern

Combine velocity, distance, and direction for a complete swipe gesture:

```ts
function handleSwipeEnd(direction: "left" | "right", distance: number, velocity: number) {
  const shouldDismiss = distance > THRESHOLD || velocity > 0.11;

  if (shouldDismiss) {
    // Animate out in swipe direction with remaining momentum
    animateOut(direction, velocity);
  } else {
    // Spring back to origin
    springBack();
  }
}
```

The exit animation should continue in the swipe direction with momentum — snapping to a different direction feels wrong.

## Grab from the current value

A user must be able to grab a moving element mid-flight and reverse it. Never lock input while a transition runs. On grab, read the element's live on-screen position and start the drag from there, keeping the offset from where the finger landed. Starting from the target value, or snapping the element's centre to the pointer, makes it jump.

```ts
function onPointerDown(e: PointerEvent) {
  el.setPointerCapture(e.pointerId);
  const live = new DOMMatrix(getComputedStyle(el).transform).m42; // current translateY, mid-animation
  grabOffset = e.clientY - live;
  animation?.stop();
}
```

In Motion, a motion value already holds the live value; `y.get()` on grab is the same idea.

## Direction lock

Require about 10px of movement before committing to an axis, then track 1:1. Without that threshold a horizontal swipe inside a vertical scroller steals the scroll, and the bug looks like broken scrolling rather than a gesture problem. On touch surfaces also set `touch-action` to the axes the browser keeps (`pan-y` on a horizontal carousel, `none` only on an element that owns every axis).

## Velocity handoff

When the finger lifts, the settle animation continues at the finger's exact velocity, so there is no seam between dragging and animating. This one detail most separates fluid from fine. Track the last few `pointermove` positions with timestamps to get the release velocity, then pass it to the spring:

```ts
animate(el, { y: target }, { type: "spring", bounce: 0.2, duration: 0.4, velocity: releaseVelocityPxPerSec });
```

Some spring APIs want relative velocity instead: `releaseVelocity / (target - current)`.

## Momentum projection

Choose the snap target from where the gesture was going, not from where the finger let go. Project the resting point with Apple's deceleration formula, snap to the nearest point to that projection, then hand off velocity. A short fast flick then commits, and a long slow drag does not.

```ts
// decelerationRate 0.998 = normal scroll feel, 0.99 = snappier
function project(velocityPxPerSec: number, decelerationRate = 0.998): number {
  return ((velocityPxPerSec / 1000) * decelerationRate) / (1 - decelerationRate);
}

const target = nearestSnapPoint(current + project(releaseVelocity));
```

Use the sign of the velocity, not the position, to decide between reversing and committing. This is the exponential-decay form Apple ships, not the textbook `v²/2a`.

Credit: adapted from emilkowalski/skills skills/apple-design/SKILL.md and skills/animate/RECIPES.md @ 2d22863 (MIT).
