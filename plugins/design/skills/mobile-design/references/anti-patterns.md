---
name: mobile-anti-patterns
description: The mobile and React Native / Expo failure catalog — web-paradigm transplants, iOS-only effects with no Android fallback, RN API landmines (shadow, elevation, ScrollView, keyboard), safe-area blindness, accessibility omissions, navigation and performance traps. Load before shipping any cross-platform screen. Complements the web /design anti-patterns (which this does not repeat).
---

# Mobile Design Anti-Patterns

These are mobile/RN/Expo-specific. The web slop items (indigo, Inter, uniform rounded-2xl, shadow-lg everywhere, glassmorphism overuse) live in `/design`'s own anti-patterns reference and are not repeated here. Each item: the mistake, why it is wrong, the correct alternative.

## Top 5 landmines (fix before any cross-platform ship)
1. **iOS-only native effect, no Android fallback (CRITICAL).** A design built around `expo-blur`/glass renders as a flat opaque fill on most Android — no warning, no error, the whole look collapses. Design the Android surface first (solid hue-correct fill at the blur's target opacity); add blur as an iOS-only enhancement. Generalizes to SF Symbols (`expo-symbols`), vibrancy, any platform-conditional effect.
2. **iOS shadow without Android elevation.** `shadowColor/Offset/Opacity/Radius` are silently ignored on Android. Every elevated card looks flat. Always pair with `elevation` via `Platform.select`.
3. **Missing `KeyboardAvoidingView`.** The submit button hides under the iOS keyboard; users cannot finish the form. Invisible in the iOS simulator (no software keyboard by default). Wrap forms; on Android set `windowSoftInputMode=adjustResize`.
4. **Safe-area blindness.** Hardcoded `paddingTop`/`bottom:0` puts content under the Dynamic Island and home indicator. Device-specific, invisible until a physical device. Use `useSafeAreaInsets()`.
5. **`ScrollView` for a large/dynamic list.** It mounts every child at once — mount jank and memory pressure on mid-range Android. Use `FlatList`/`FlashList`.

## Web paradigm transplanted to mobile
- **Hover as the affordance.** Touch has no hover; the feature is invisible to 100% of users. Use `onPressIn/Out` feedback, `onLongPress` for secondary, and make affordances visible by default.
- **Tap targets < 44pt/48dp.** Miss-rate rises ~3x. A 24pt icon needs a 44pt hit area via `hitSlop` or `minWidth/minHeight`.
- **Desktop density / multi-column tables / sidebars** on a 360-390pt canvas. Convert tables to stacked cards, sidebars to bottom sheets/drawers, min row height 44-56pt.
- **Primary action at the top.** Out of thumb reach. Bottom, inside the safe area.

## React Native API landmines
- **`elevation` + `overflow:'hidden'` + `borderRadius`** -> Android shadow disappears. Separate shadow layer from clipped content layer.
- **Text without `numberOfLines`** -> unbounded user strings blow up card/list layouts and break `FlatList` height assumptions. Set `numberOfLines` + `ellipsizeMode`; design for the worst-case string.
- **`Image` without explicit dimensions / `resizeMode`** -> 0x0 then jump (CLS) and distorted aspect. Set size or aspect container; prefer `expo-image`.
- **Hardcoded absolute positions** (`top:320`) -> right on one device, broken on another. Flex or percentage of `useWindowDimensions()`.
- **gesture-handler / Reanimated version mismatch** -> gestures silently dead or Metro errors. Install via `npx expo install`; confirm the Reanimated Babel plugin.
- **Modal ignoring safe area** -> RN `Modal` renders outside the inset tree; re-apply `SafeAreaView`/insets inside.

## Expo-specific
- **Expo Go SDK mismatch** -> project SDK newer than the installed Expo Go fails to load ("requires a newer/older Expo Go"). Use a dev build (`expo-dev-client`) for anything past a matched demo; document the required SDK.
- **Native module without its config plugin** -> works in Expo Go (pre-bundled) but crashes / returns undefined in a dev/EAS build. Add the plugin to `app.json`; `expo prebuild`; test in a dev build, not Expo Go.
- **`require()` with a dynamic path** -> Metro cannot resolve it statically; asset missing in production. Use static `require()` or an explicit map.

## Accessibility on mobile
- **No `accessibilityLabel` / `accessibilityRole`** -> VoiceOver/TalkBack announce nothing useful on icon buttons. Add both; `accessibilityHint` for non-obvious consequences.
- **`accessibilityState` hardcoded** -> screen-reader users cannot tell a toggle's state. Drive it from state (`{ checked, expanded }`).
- **Focus order broken by absolute positioning** -> screen readers traverse tree order, not visual order (WCAG 2.4.3). Manage with `accessible`/`importantForAccessibility` or `setAccessibilityFocus`.
- **`allowFontScaling={false}` globally** to "fix" layout -> overrides the user's text-size setting (WCAG 1.4.4). Design for ~2x scale; cap with `maxFontSizeMultiplier`.
- **Ignoring `useColorScheme`** -> light-only app looks broken in dark mode against dark system chrome.

## Navigation
- **>5 bottom tabs** -> iOS forces a "More" overflow; targets shrink below 44pt. Max 5.
- **Hamburger hiding primary nav** -> ~50% task-completion drop vs visible nav; near-zero discoverability. Tab bar for 3-5 primary; drawer only for secondary utilities.
- **Hijacking system back / not handling `BackHandler`** -> app exits to home instead of navigating up; over-consumed swipes conflict with system swipe-back. Use the navigator's back integration; close modals on back.

## Performance jank
- **Animating layout props** (`width/height/top/left/margin/padding`) -> per-frame layout pass / bridge calls; drops frames on mid-range Android. Animate `transform`/`opacity` only; replace height-expand with `scaleY`.
- **Frequent context updates feeding list items** -> N re-renders per tick. Split contexts by update frequency; `React.memo`/`useMemo` list items; Reanimated shared values or selective store subscriptions for high-frequency state.
- **Blocking the JS thread** with heavy sync work during interaction -> dropped frames, dropped touches. Defer with `InteractionManager.runAfterInteractions()`; move heavy work off-thread.

## Cross-device edge cases
iPad/tablet (768-1366pt) needs explicit breakpoints (RN has no media queries — use `useWindowDimensions`). Android foldables change viewport on unfold — dimensions must be reactive, not read once. Landscape breaks hardcoded heights. RTL (Arabic/Hebrew) needs `start`/`end` not `left`/`right`. Low-end Android (Go, 1-2GB RAM) runs 5-10x slower — virtualize and keep item renderers light.
