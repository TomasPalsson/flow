---
name: mobile-motion
description: Building motion in React Native and Expo (Reanimated 4, Gesture Handler, Expo Router, expo-haptics) - whether to animate, the cheapest tool, which properties, spring or timing, keeping motion off the JS thread, press feedback, haptics, reduced motion, and recipes for sheets, swipe rows, headers, lists, keyboard, tabs and screen transitions. Load in Phase 3 when the screen animates.
---

# Motion In React Native And Expo

Three things change on mobile. There is no hover, so every hover affordance moves to press, position or nothing. There are two runtimes: React and app logic run on the RN runtime, worklets run every frame on the UI runtime, and an animation that touches the RN runtime stutters the moment the app does anything else. And the finger is on the element, so interruption and velocity handoff are the baseline, not polish.

## 1. Should it animate?

| Frequency | Decision |
|---|---|
| 100+ times a day: tab switches, keyboard open/close, scrolling, settings toggles | No animation; platform default or nothing |
| Tens of times a day: press feedback, row selection | Near-imperceptible only, under 150ms |
| Occasional: sheets, modals, toasts, onboarding steps | Standard animation |
| Rare: success, empty-state art, celebration | Where delight belongs |

**Tabs never slide.** Tabs are peers; sliding implies a depth that is not there, and the user pays for it dozens of times a session. `animation: 'none'`.

Then name the purpose in one word (feedback, spatial consistency, state indication, preventing a jarring change, explanation, delight at the rare tier only). No word, no animation.

## 2. The cheapest tool

| Need | Tool |
|---|---|
| A state-driven change with no gesture (press, toggle, colour) | Reanimated CSS transition (`transitionProperty` in the style) |
| A loop, multi-stage, or on-mount animation | Reanimated CSS animation (`animationName` keyframes) |
| Mount, unmount, list reflow | Layout animations (`entering`, `exiting`, `itemLayoutAnimation`) |
| Anything a finger touches or derived from scroll | `useSharedValue` + `Gesture` + `useAnimatedStyle` |
| Screen to screen | Native stack options in Expo Router; never hand-rolled |
| A sheet that is its own screen | `presentation: 'formSheet'` |
| Tab bar | `NativeTabs` from `expo-router/unstable-native-tabs` |
| Context menu, press-and-hold preview (iOS) | `Link.Menu` / `Link.Preview` |
| Large title that collapses on scroll (iOS) | `headerLargeTitleEnabled` on the native stack |
| Pull to refresh | `RefreshControl` |
| UI that follows the keyboard | `react-native-keyboard-controller` |
| Illustration or celebration | Lottie, never for UI state |

A shared value is for continuous or interruptible values only. A press scale is a CSS transition; a drag is a shared value. Install with `npx expo install <package>` so versions match the SDK.

## 3. Properties

- `transform` and `opacity` are free. `width`, `height`, `margin`, `padding`, `flex`, `top`, `left` and `gap` re-run layout for the node and its siblings every frame. The one exception is an absolutely positioned element with no children (a tab pill, a progress fill), where animating `width` keeps the corner radius that `scaleX` would smear.
- Never `scale(0)`; start at `0.95` with `opacity: 0`.
- `transform` is an array and order matters: `[{ translateY }, { scale }]` scales after moving.
- Never animate Android `elevation` or `BlurView` intensity; both re-render every frame. Crossfade the opacity of a static layer.
- Percentages work in `translate`: `translateY('100%')` moves a sheet by its own height.

## 4. Spring or timing

If a finger was involved, use a spring: it carries velocity through an interruption. Use Reanimated's designer parameters:

| Interaction | Config |
|---|---|
| Default settle, no overshoot | `{ duration: 400, dampingRatio: 1 }` |
| Snap back after a drag | `{ duration: 400, dampingRatio: 0.8, velocity }` |
| Sheet, drawer | `{ duration: 300, dampingRatio: 0.8, velocity }` |
| Must not pass a hard edge | add `overshootClamping: true` |

Bounce only when the gesture carried momentum. Everything without a finger uses timing; the built-in easings are weak, so use these (the ease-out matches the web skill's enter curve):

```js
const EASE_OUT = Easing.bezier(0.23, 1, 0.32, 1);     // entering or exiting
const EASE_IN_OUT = Easing.bezier(0.77, 0, 0.175, 1); // moving on screen
const EASE_SHEET = Easing.bezier(0.32, 0.72, 0, 1);   // iOS sheet curve
```

Never `Easing.in(...)` on UI. Durations: press 100-150ms, toggle or chip 150-200ms, sheet a ~300ms spring, screen transitions the platform default. Match the platform for navigation, beat it everywhere else.

## 5. Keep it off the JS thread

- Never `setState` from a gesture or scroll handler; one React render per frame is the biggest cause of RN jank.
- Never call back to the RN runtime inside `onUpdate` or a scroll handler. `scheduleOnRN(fn, ...args)` from `react-native-worklets` (the Reanimated 4 replacement for `runOnJS`) belongs in `onEnd`, or in a `useAnimatedReaction` that fires when a value crosses a threshold.
- Never read or write a shared value during render. Use `.get()` / `.set()` in worklets, handlers and effects; that is the form the React Compiler can see through.
- A function called from a worklet needs `'worklet'` as its first line, or it throws on device while working in the debugger.
- Wrap gestures in `useMemo`; rebuilding one each render can drop a drag mid-flight. Build layout-animation builders at module scope or in `useMemo`.

## 6. Press, haptics, reduced motion

- Feedback on press-in, commit on press-out. `scale: 0.97` over 100-150ms on every pressable. 44×44pt minimum target (48dp on Android): add `hitSlop` rather than growing the visual, and `pressRetentionOffset` so a drifting finger does not cancel. In a custom-designed app, the same scale on both platforms is more coherent than an Android-only ripple.
- Haptics: `selectionAsync()` when a value ticks past a step; `impactAsync(Light)` when something snaps home or a detent catches; `impactAsync(Medium)` for a heavy landing or destructive action; `notificationAsync(Success | Error)` for outcomes. Fire on the same frame as the visual, once per user action, never on scroll or per frame, and never as the only feedback, since many users have haptics off.
- Reduced motion: `useReducedMotion()`, or `reduceMotion: ReduceMotion.System` per animation. Keep opacity and colour changes, drop translation, scale, parallax and overshoot; screen transitions become `animation: 'fade'`. Text scales with the user's setting, so never animate to a hard-coded height: measure with `onLayout` or animate a transform.

## 7. Setup that silently breaks motion

- Reanimated 4 needs `react-native-worklets` and the New Architecture. In Expo, `babel-preset-expo` configures the worklets Babel plugin; a bare RN project adds it manually, last in the list.
- `GestureHandlerRootView` must wrap the app (the root `_layout` in Expo Router), or gestures do nothing with no error.
- On ProMotion iPhones, confirm `CADisableMinimumFrameDurationOnPhone: true` in `ios.infoPlist`; without it animations cap at 60fps. Then the budget is 8ms per frame.
- Judge feel in a release build on the slowest supported device. Expo Go and dev builds hide exactly the problems you are looking for.

## Recipes

Two worklets used everywhere:

```js
// Where a flick would come to rest (Apple's exponential decay)
function project(velocity, decelerationRate = 0.998) {
  'worklet';
  return ((velocity / 1000) * decelerationRate) / (1 - decelerationRate);
}

// Resistance past an edge
function rubberband(overshoot, dimension, constant = 0.55) {
  'worklet';
  return (overshoot * dimension * constant) / (dimension + constant * Math.abs(overshoot));
}
```

**Drag-to-dismiss sheet** (only when the sheet must live inside a screen; otherwise `formSheet`):

```jsx
const pan = useMemo(() => Gesture.Pan()
  .activeOffsetY([-10, 10])                         // require intent before committing
  .onStart(() => { context.set(translateY.get()); }) // grab mid-animation from where it is
  .onUpdate((e) => {
    const next = context.get() + e.translationY;
    translateY.set(next >= 0 ? next : rubberband(next, HEIGHT));
  })
  .onEnd((e) => {
    if (translateY.get() + project(e.velocityY) > HEIGHT * 0.4) {
      translateY.set(withSpring(HEIGHT, { duration: 300, dampingRatio: 1, velocity: e.velocityY, overshootClamping: true },
        (finished) => { if (finished) scheduleOnRN(onClose); }));
    } else {
      translateY.set(withSpring(0, { duration: 300, dampingRatio: 0.8, velocity: e.velocityY }));
      scheduleOnRN(Haptics.impactAsync, Haptics.ImpactFeedbackStyle.Light);
    }
  }), [onClose]);
```

Velocity decides, not distance: a quick flick dismisses after a few pixels. Derive the backdrop from the same value: `opacity: interpolate(translateY.get(), [0, HEIGHT], [1, 0], Extrapolation.CLAMP)`.

**Swipe-to-delete row.** Use `ReanimatedSwipeable` when the row reveals action buttons. Build the pan yourself only for swipe-to-commit, and declare the axis with `.activeOffsetX([-10, 10])`, or it steals the list's vertical scroll. Let the list close the gap with `itemLayoutAnimation={LinearTransition.duration(200)}` defined at module scope.

**Collapsing header.** Never animate the header's `height`; that re-lays-out everything below on every scroll frame. Fix the container height, translate and fade the content inside it, and always pass `Extrapolation.CLAMP`, or the values keep going past the range and the title reappears inverted.

**List entrances.** Stagger 30-80ms with a memoized `FadeInDown.duration(250).delay(index * 40)`. Never put `entering` on rows of a `FlatList` or `FlashList`: rows are recycled, so the animation re-fires as they scroll back in and the list flickers.

**Keyboard-synced UI.** `useReanimatedKeyboardAnimation()` from `react-native-keyboard-controller`, with `KeyboardProvider` at the root. Never `Keyboard.addListener` plus a timing animation: the event arrives after the keyboard has started moving, so any duration lags or leads it.

**Tab or segmented indicator.** Measure each tab once with `onLayout`, then animate `translateX` and `width` with `EASE_IN_OUT` over 250ms (the pill is absolute and childless, so `width` is allowed). Fire `selectionAsync()` on the press, not when the pill lands.

**Screen transitions.**

| Navigation | Option |
|---|---|
| Deeper into a hierarchy | `animation: 'default'` |
| A self-contained task the user can abandon | `presentation: 'modal'` |
| A short interruption (picker, filter, share) | `presentation: 'formSheet'` with detents |
| Between tabs | `animation: 'none'` |
| Reduced motion | `animation: 'fade'` |

Set `animationMatchesGesture: true` with any custom `animation`, so the iOS back swipe reverses it under the finger. Android caps form-sheet detents at three, shows no grabber, and cannot host native headers or nested stacks in a form sheet; `fitToContents` needs explicitly sized content.

**Toast.** Enter with `FadeInDown.duration(300).easing(EASE_OUT)`, exit the same edge about 20% faster, positioned at `insets.bottom + 16`. The 300ms cap holds: a toast is uninvited, so it should be quieter than motion the user asked for.

**Fire once at a threshold.** Compare on the UI thread with `useAnimatedReaction` and call `scheduleOnRN` only when the boolean flips, so a pull-to-refresh arms with one haptic instead of 60 calls a second.

## Never ship

| Never | Instead |
|---|---|
| `PanResponder`, or core `Animated` for anything a finger touches | `Gesture.Pan()` with Reanimated |
| `setState` in a gesture or scroll handler | Shared value + `useAnimatedStyle` |
| `runOnJS`, or `scheduleOnRN` per frame | `scheduleOnRN` in `onEnd` or at a threshold |
| A screen transition rebuilt in JS, or sliding tabs | Native stack `animation`; `'none'` between tabs |
| `entering` on a virtualized row | Animate the container, or `itemLayoutAnimation` |
| A distance-only dismissal threshold | Velocity or distance, via `project()` |
| A haptic per frame, or as the only feedback | One per commit, always with a visual |
| Judging feel in Expo Go or the simulator | Release build, slowest supported device |

When you finish, name what needs a feel check on the device: flick it, interrupt it mid-flight, reverse it, and run it on the slowest Android available.

Credit: adapted from emilkowalski/skills skills/animate-expo/SKILL.md and skills/animate-expo/RECIPES.md @ 2d22863 (MIT).
