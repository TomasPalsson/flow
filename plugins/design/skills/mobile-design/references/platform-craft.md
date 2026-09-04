---
name: platform-craft
description: iOS HIG vs Android Material 3 divergence table and decision frameworks, plus the full React Native / Expo translation of web design craft (color, shadow, typography, spacing, motion, images, token architecture). Load the Platform Divergence section in Phase 2 for a nav/modal/component decision; load the RN/Expo Craft section in Phase 3 for a specific number or API.
---

# Platform Craft — iOS/Android Divergence + RN/Expo Translation

This reference has two halves. **Platform Divergence** (Phase 2) is where iOS and Android genuinely differ and a wrong choice reads as a ported app. **RN/Expo Craft** (Phase 3) translates the web design numbers into React Native, where CSS does not exist.

---

# Part 1 — Platform Divergence (iOS HIG vs Material 3)

Rule: a product-branded app may unify its language; a utility or system-integrated app pays a real cost when it violates platform convention, because users have *embodied* these patterns from every other app. The pragmatic middle (native nav/gestures/modals + brand-consistent buttons/cards/type/color) is correct for most RN apps.

## Navigation
| Concern | iOS (HIG) | Android (Material 3) |
|---|---|---|
| Global nav | Bottom tab bar, 3-5 items | Bottom navigation bar, 3-5 items; nav drawer only for >5 secondary |
| Deep nav | Push/stack | Back stack via NavController |
| Back | Nav-bar back button + left-edge swipe-back (system) | System back gesture / hardware back; predictive back (Android 13+) |
| Title | Centered (or left on iOS 17+); large title collapses on scroll | Left-aligned top app bar; collapsing toolbar |

The Android back button is **not** a detail. If the user is in a modal/sheet and presses back, it must close the sheet, not exit the app. The iOS left-edge swipe-back is a system gesture — do not disable it, and do not place a horizontal swipe control near the left edge that conflicts with it.

## Action placement
- iOS: a top-right nav-bar action ("Done"/"Save") is **only** for dismissing a modal sheet. For main flows, primary actions go at the bottom.
- Android: FAB at bottom-right for the primary create action; bottom-anchored buttons otherwise.

## Modals vs bottom sheets
- Contextual/supplementary -> **bottom sheet** (iOS `.sheet`, Material bottom sheet); swipe-down to dismiss; sheet content needs `paddingBottom: insets.bottom`.
- Decision gate (delete/cancel, yes/no) -> **centered alert** — the one centered pattern native to both.
- Full task flow -> push a new screen, not a modal.
- A centered content overlay (web "dialog") on a native screen reads as a port. RN's `Modal` renders OUTSIDE the safe-area tree — re-apply `SafeAreaView`/insets inside it.

## Components
- **Switch vs checkbox:** iOS uses a switch for binary settings (checkboxes rare, list-selection only). Android uses a switch for settings and a checkbox for multi-select. Using the wrong one reads as a port.
- **Pickers:** iOS wheel/drum or `.graphical` calendar; Android Material date dialog. Both full-screen or sheet — never an inline web `<input type=date>` equivalent.
- **Segmented control** (iOS) vs **chips/tabs** (Android) for inline switching.

## Gestures expected as vocabulary (absence is felt)
Swipe-to-delete on list rows; pull-to-refresh on any feed (users try it whether or not it exists — if absent they assume the list is stale); swipe-down to dismiss sheets; long-press for context menu; pinch-to-zoom on images.

## Haptics (enhancement only, never the sole feedback)
Selection (light) on picker/tab/slider movement; impact (light/medium/heavy) on definitive actions; success/warning/error notification haptics on async completion. Never haptic on every tap or on scroll. `expo-haptics`. ~30-40% of users may get no haptic (disabled/Android fragmentation) — every action still needs full visual feedback.

## Typography on device
- iOS system font SF Pro (Text <=19pt / Display >=20pt, auto-switched) — access by leaving `fontFamily` unset.
- Android Roboto default; custom fonts are more culturally accepted on Android.
- Material 3 type scale (sp): Display Large 57 / Headline Medium 28 / Title Large 22 / Body Large 16 (+0.5 tracking) / Label Medium 12 Medium (+0.5).
- Body floor 16pt/16sp; 17pt preferred on iOS. Web 14px body reads small at arm's length.

## Dark mode + OLED
Dark mode is OS-driven (`useColorScheme()`), required since iOS 13 / Android 10. The `/design` "never pure black" rule has a mobile exception: **true black `#000` is acceptable and power-saving as the dark-mode page background on OLED** (most flagships). But reduce chroma of bright accent text on OLED dark backgrounds by 15-25% — full-saturation colors halate (bloom) on OLED.

## Decision frameworks
- **Native vs unified:** native when the app integrates with OS features or targets one platform; unified when brand consistency outranks convention and you cannot maintain two component sets; middle path otherwise.
- **Bottom sheet vs alert vs push:** supplementary content -> sheet; decision before continuing -> alert; full task -> push.
- **Edge cases:** react-navigation's built-in tab bar already insets for the home indicator — adding `insets.bottom` again double-pads. `onPressIn` (finger-down) feels ~50-80ms faster than `onPress` for immediate UI; keep `onPress` for navigation/destructive to avoid accidental swipe triggers. Set Android `windowSoftInputMode=adjustResize` (not `adjustPan`, which slides the tab bar up with the keyboard). Audit every `numberOfLines={1}` against large Dynamic Type — it truncates critical content.

---

# Part 2 — RN/Expo Craft Translation

The `/design` principles hold; the implementation differs. Confirmed RN-documented behavior unless flagged version-gated.

## Color
RN accepts hex/rgb/rgba/hsl only — **no `oklch()`**. Author palettes in OKLCH, convert to hex into a theme token at design time. Keep chroma <= 0.20 (RN's pipeline is sRGB-clamped; higher clips even on P3 hardware). Tinted neutrals and "never gray text on colored bg" still apply. Light/dark via `useColorScheme()`; for larger apps wrap in a theme context to avoid threading the hook everywhere.

## Shadow / Elevation (the biggest divergence)
- iOS: `shadowColor` (brand-hued dark, never pure black), `shadowOffset`, `shadowOpacity`, `shadowRadius`. Multi-layer requires stacking transparent wrapper Views.
- Android: only `elevation` (integer). Ignores all `shadow*` props. Pre-API-28 the color is system grey and unchangeable. `elevation` also sets z-order (overrides JSX order) and clips to bounds.
```ts
export const elevation = {
  low:    Platform.select({ ios: { shadowColor:'#0c2340', shadowOffset:{width:0,height:1}, shadowOpacity:0.12, shadowRadius:2 },  android: { elevation:2 } }),
  medium: Platform.select({ ios: { shadowColor:'#0c2340', shadowOffset:{width:0,height:4}, shadowOpacity:0.14, shadowRadius:8 },  android: { elevation:6 } }),
  high:   Platform.select({ ios: { shadowColor:'#0c2340', shadowOffset:{width:0,height:8}, shadowOpacity:0.16, shadowRadius:16 }, android: { elevation:12 } }),
};
```
- **[VERSION-GATED RN 0.76+ New Arch / Expo SDK 52+]** a `boxShadow` string prop accepts CSS-like multi-layer syntax on both platforms — verify New Arch is enabled before relying on it.
- Dark mode: no shadows; use four-tier lightness surfaces (~4% L steps, e.g. `#0d111a -> #141b26 -> #1b2538 -> #222f45`).
- **Trap:** `elevation` + `overflow:'hidden'` + `borderRadius` on Android drops the shadow (overflow clips the shadow canvas). Separate the shadow layer (parent, elevation, no overflow) from the clipped content layer.

## Radius
`borderRadius` and per-corner props work 1:1; tiered scale (inputs 4 / buttons 6-8 / cards 10-12 / pill full) applies. `overflow:'hidden'` costs a compositing layer on Android — use intentionally.

## Typography (three semantic breaks — memorize)
- `lineHeight` is **absolute dp**, not a multiplier. `lineHeight: 1.5` -> 1.5dp -> overlap. Use `Math.round(fontSize * ratio)`.
- `letterSpacing` is **absolute px**, not em. Compute `fontSize * emValue` per style.
- No `font-display: swap`. Hold the native splash via `expo-font` `useFonts` + `SplashScreen.preventAutoHideAsync()` until fonts load.
- `fontWeight: '600'` silently falls back to `'700'` on Android if no 600-weight file is loaded. Load every weight you use.
- `allowFontScaling` defaults true (good) — disable only on decorative display numbers, never body/labels. Cap one-off display with `maxFontSizeMultiplier`.

## Spacing
8pt grid applies directly (RN units are already dp). **[VERSION-GATED RN 0.71+ / Expo SDK 49+]** `gap`/`rowGap`/`columnGap` in flexbox; before that, margins on children. Insets via `useSafeAreaInsets()` from `react-native-safe-area-context` (more reliable than RN's built-in `SafeAreaView`, especially on Android). Use `useWindowDimensions()` (reactive) not `Dimensions.get()` (snapshot) for responsive/rotation/foldable layout.

## Motion
Two systems — pick correctly. **Reanimated 3** worklets run on the UI thread (60/120fps, gesture-coupling) — the production standard. Built-in `Animated` runs on the JS thread and janks under load (mitigate with `useNativeDriver: true`, which only works for transform/opacity). `Easing.bezier(0.25, 1, 0.5, 1)` mirrors ease-out-quart. Animate only `transform`/`opacity` (same as web; mechanism is worse on RN). Spring physics (`withSpring`) for gesture-coupled/interruptible motion — it carries velocity, a fixed bezier looks wrong when interrupted. Reduced motion: `AccessibilityInfo.isReduceMotionEnabled()` (async; init false, update on effect) or Reanimated's `ReduceMotion.System`. Do not override platform navigation transitions unless the aesthetic demands it. Reanimated 3 needs its Babel plugin in `babel.config.js` — without it animations silently do nothing; install with `npx expo install react-native-reanimated react-native-gesture-handler` so versions match the SDK.

## Layout
Flexbox only (no Grid). Defaults differ from web: `flexDirection: 'column'`, `flexShrink: 0`. 2-column grid = `flexWrap:'wrap'` + `width:'48%'`.

## Images
`expo-image` over built-in `Image` — disk+memory cache, blurhash placeholder, `contentFit`, `transition`. Built-in `Image` has no disk cache on Android (re-fetches every mount). Request DPR-scaled remote URLs (`PixelRatio.get()` is 2-3); static assets use `@2x`/`@3x` (Metro auto-resolves). Always set explicit dimensions or an aspect-ratio container + `resizeMode`/`contentFit` to avoid layout shift.

## Token / theme architecture
`StyleSheet.create` is not optional — it passes style IDs to native instead of recreating objects each render. Pre-compute all `lineHeight`/`letterSpacing` in the theme (not raw ratios/em). Use `.ios.tsx`/`.android.tsx` files for significantly divergent components (TabBar, pickers); `Platform.select` for minor tweaks.
```ts
export const theme = {
  colors: { /* light + dark token sets */ },
  space:  { 1:4, 2:8, 3:12, 4:16, 6:24, 8:32, 10:40, 12:48 },
  radii:  { input:4, button:8, card:12, pill:9999 },
  type: {
    body:     { fontSize:16, lineHeight:24, letterSpacing:0,     fontWeight:'400' as const },
    heading1: { fontSize:32, lineHeight:37, letterSpacing:-0.96, fontWeight:'700' as const },
    label:    { fontSize:12, lineHeight:15, letterSpacing:0.96,  textTransform:'uppercase' as const },
  },
  elevation,
} as const;
```
