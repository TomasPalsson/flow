---
name: mobile-design
description: Mobile-native design for React Native/Expo and iOS/Android — the mobile layer the web /design skill lacks. Use when designing, building, reviewing, fixing, or evaluating any mobile app UI, screen, component, or flow; when a screen "looks bad on my phone"; when a glass/blur effect "renders flat on Android"; or to verify a build on a real device. Covers thumb-zone ergonomics, dynamic safe-area insets, iOS HIG vs Material 3 divergence, the iOS-only-effect-flat-on-Android trap, React Native craft (lineHeight/letterSpacing/shadow/elevation), and a device-driven adb loop that screenshots and drives the running app to confirm it matches the vision. Keywords - mobile design, app design, React Native, Expo, iOS, Android, tab bar, bottom sheet, safe area, notch, touch target, dark mode, native feel, not a web port, screenshot the app on device.
user-invocable: true
argument-hint: "[screen or app to design / review, optionally a device target]"
---

# Mobile Design

Mobile design has two failure attractors, not one. The first is **AI-slop** — the web design skill (`/design`) already fights this (indigo-500, Inter, uniform rounded-2xl, shadow-lg everywhere). The second is unique to mobile: the **web port** — a desktop layout shrunk to a phone, with top-anchored buttons the thumb cannot reach, content jammed under the notch, hover affordances that do not exist on touch, centered modals where a bottom sheet belongs, and a glass effect that looks designed on iOS and dead on Android. A screen can fully escape slop and still be an uncanny web port. This skill fights the second attractor while reusing `/design` for the first.

**Reuse, do not duplicate.** Everything `/design` teaches about OKLCH palettes, tiered radius/shadow as a *principle*, ease-out-quart, Nielsen heuristics, microcopy, and the separate-evaluator discipline still applies. Invoke the `/design` skill (or read its SKILL.md from your skills directory) for that shared foundation. This skill is the **mobile delta** layered on top — and it changes the *implementation* of nearly every craft rule, because React Native is not CSS.

**No emojis.** Not in the UI (emoji as functional icons render inconsistently, are announced awkwardly by VoiceOver/TalkBack, and signal a casual project — use a real icon set), and not in code, comments, or output produced under this skill.

## The Process

Five phases, each with a gate. Same spine as `/design`, mobile-ized, with a device-verification phase inserted before evaluation — because on mobile, "looks right in my head" and "looks right on the device" diverge constantly.

```
Phase 1: THINK          commit to aesthetic AND platform stance
Phase 2: ARCHITECT      ergonomics + platform conventions before visuals
Phase 3: EXECUTE        translate craft into React Native reality
Phase 4: BUILD & VERIFY screenshot and drive the real device; match build to vision
Phase 5: EVALUATE       separate subagent scores against the mobile rubric
```

---

## Phase 1 — Think

Do everything Phase 1 of `/design` asks (purpose, tone, one memorable element, constraints). Then add the two mobile-only commitments:

1. **Platform stance.** Pick one and state it: **platform-native** (feels like part of iOS / part of Android — diverge per OS), **unified brand** (same everywhere, brand over convention), or the **pragmatic middle** (native navigation/gestures/modals; brand-consistent buttons/cards/color/type). The middle path is correct for most React Native apps. This choice governs a hundred later decisions — make it now.
2. **Target devices and the verification plan.** Which OS, which devices, light AND dark, smallest supported width (iPhone SE 320pt, a 360dp Android). If a device or emulator is connected, you will verify on it in Phase 4 — note that now.

**Gate:** You can state the aesthetic direction in one sentence, name one memorable element, AND name the platform stance and the device(s) you will verify on.

---

## Phase 2 — Architect

Do Phase 2 of `/design` (Nielsen tiers, focal element, states). Then make the mobile architecture decisions that visuals cannot fix later:

- **Bottom-gravity.** The thumb's comfortable arc covers roughly the bottom 40-60% of a tall phone; the top ~30% is hard-reach. Primary actions (submit, confirm, primary CTA) go at the **bottom**, inside the safe area. Top bars are for navigation (back, title, cancel), not task completion. Any action tapped more than twice per session must be reachable one-handed.
- **Navigation = platform convention.** 3-5 destinations: bottom tab bar (both platforms). More: push/stack with a drawer for secondary utilities. Never hide primary navigation in a hamburger. Honor the Android system back / predictive-back and the iOS left-edge swipe-back — intercepting them wrong (exiting the app instead of closing a sheet) is a P0 bug.
- **Modals are bottom sheets, not centered dialogs.** Contextual/supplementary content -> bottom sheet (swipe-down to dismiss). A decision gate (delete/cancel) -> centered alert (the one centered pattern native on both). A full task -> push a new screen. Centered content overlays read as "ported web UI."
- **Touch targets and spacing.** 44x44pt minimum (iOS) / 48x48dp (Android). The WCAG 24px floor is a legal minimum, not a target. A 24pt icon needs a 44pt hit area (`hitSlop`). 8pt+ gap between adjacent targets' hit areas.
- **Design the dynamic states mobile adds:** pressed/active feedback (there is no hover on touch — absence makes a tap feel dead), pull-to-refresh, swipe-row actions, keyboard-open layout, empty/loading/error. Dark mode is not a state you may skip — it is an OS setting users have on.

**Gate:** Before any visuals, name the primary task, where its action sits (bottom), the navigation pattern, the modal pattern, the touch-target minimum, and the fact that you will design light AND dark.

For the full iOS-HIG-vs-Material-3 divergence table and the platform decision frameworks, **load [`references/platform-craft.md`](references/platform-craft.md) — read the "Platform Divergence" section** when resolving a specific nav/modal/component/picker decision. Do NOT load for an obvious choice.

---

## Phase 3 — Execute

Apply `/design` Phase 3 craft (typography numbers, color approach, spacing scale, motion easing, depth). But **the implementation is not CSS** — React Native breaks several rules silently. The five that cause the most regressions:

| `/design` says | React Native reality | What you must do |
|----------------|----------------------|------------------|
| `line-height: 1.5` (multiplier) | `lineHeight` is an **absolute dp** value. `lineHeight: 1.5` renders 1.5dp and text overlaps. | Compute `lineHeight: Math.round(fontSize * ratio)` in the theme. |
| `letter-spacing: -0.03em` (scales) | `letterSpacing` is **absolute px**, does not scale with size. | Compute `letterSpacing: fontSize * -0.03` per type style. |
| multi-layer `box-shadow`, colored | iOS uses `shadow*` props; **Android ignores them entirely** and honors only `elevation`. | `Platform.select({ ios: {shadowColor/Offset/Opacity/Radius}, android: {elevation} })`. Never ship iOS shadow alone. |
| `oklch(...)` | RN accepts only hex/rgb/hsl; no OKLCH; chroma >~0.20 clips to sRGB. | Author in OKLCH, convert to hex into a theme token at design time; keep chroma <= 0.20. |
| `env(safe-area-inset-*)`, `font-display: swap` | No CSS env(); no font-display. | `useSafeAreaInsets()` for insets; hold the splash via `expo-font` `useFonts` until fonts load. |

Plus the mobile craft musts: build a **theme token object** (colors light+dark via `useColorScheme`, spacing on the 8pt grid, radii tiered, pre-computed type styles, a `Platform.select` elevation scale); use `FlatList`/`FlashList` for any list over ~20 items (never `ScrollView`); animate only `transform`/`opacity` with **Reanimated** (UI-thread, 60/120fps) not the JS-thread `Animated`; `expo-image` with `contentFit` and a blurhash placeholder for images; respect `allowFontScaling` (never disable it on body/labels). Watch the Android trap: `elevation` + `overflow:'hidden'` + `borderRadius` drops the shadow — choose two.

**The iOS-only-effect trap (read this — it is the most common mobile design catastrophe).** Any native effect that exists only on iOS — `expo-blur`/glass/liquid-glass, `expo-symbols` SF Symbols, vibrancy — falls back to a **flat opaque fill on most Android devices with no warning**. A design built *around* glass renders dead on Android. Design the Android surface first (a solid, hue-correct fill at the blur's target opacity), then add blur as a `Platform.OS === 'ios'` enhancement — never as the load-bearing structure. Verify on a real Android device in Phase 4.

**Gate:** Can you articulate how every visual layer renders on Android specifically — the shadow, the blur, the font weight, the elevation under a rounded clip? If you cannot picture the Android rendering of each layer, you have not finished Phase 3; you have an iOS design that will surprise you on the other platform. (Concretely this means: a theme token object with light+dark colors, pre-computed `lineHeight`/`letterSpacing`, a `Platform.select` shadow scale, virtualized lists, UI-thread motion, and no native effect without a cross-platform fallback.)

For the complete RN/Expo craft translation (font loading, gesture-handler/Reanimated setup, version-gated `boxShadow`/`gap`, P3, DPR images, token architecture), **load [`references/platform-craft.md`](references/platform-craft.md) — read the "RN/Expo Craft" section** when you need a specific number or API. For the full failure catalog, **load [`references/anti-patterns.md`](references/anti-patterns.md) before shipping any cross-platform (iOS + Android) screen.** Do NOT load for early planning, a single-platform-only app where the cross-platform traps do not apply, or when the five rules above already cover your case.

---

## Phase 4 — Build & Verify on Device

This phase has no web equivalent and is the skill's core. After building, you do not guess whether it looks right — you **see and drive the real running app** and check it against the Phase 1-3 vision. Skip this only if no device/emulator is reachable (then say so explicitly and fall back to code inspection).

**MANDATORY — READ ENTIRE FILE:** Load [`references/device-verification.md`](references/device-verification.md) before running any device command. It has the exact adb/iOS-sim recipes, the multi-display screenshot gotcha, and the verification checklist. The scripts below are the fast path; the reference is the ground truth and the fallback.

The loop:

1. **Reach the device.** `scripts/device-info.sh` confirms a device is connected and prints resolution/density/dp width and the foreground app. (Android: adb. iOS: simulator via `xcrun simctl`.)
2. **Screenshot light AND dark.** `scripts/shot.sh ./screenshots` captures both (it toggles dark mode, waits, and uses the device-file-then-pull method — `adb exec-out screencap` corrupts the PNG on multi-display phones). Capture the populated state, and separately the empty/loading/error states.
3. **Read the screenshots as images** and critique against the Phase 1-3 intent using the checklist in the reference: safe areas respected? primary action in thumb reach? touch targets look >=44pt? color/spacing match the tokens? platform-native components? dark mode correct (no white flash, no invisible text)? any flat fallback where a native effect was intended? text clipped?
4. **Verify exact tap targets and measurements** when a target looks small: `scripts/ui-dump.sh` lists every clickable element with its center coords and size in dp, flagging anything under 48dp. Use these coordinates to drive — never eyeball pixels from a screenshot.
5. **Drive real flows** with `scripts/drive.sh` (tap / swipe / type / key / back / reload) to reach states a static screenshot misses — open the sheet, scroll the list, focus an input to check keyboard avoidance, navigate a tab.
6. **Stress it:** `scripts/toggle.sh font 1.3` (large Dynamic Type) and re-shoot to catch truncation/overflow; `scripts/toggle.sh reduce-motion on` to confirm motion degrades gracefully.
7. **Edit code -> reload -> re-shoot** and compare before/after until the build matches the vision. Keep the light+dark pair for the PR.

**Gate:** You have looked at an actual rendered screenshot (light and dark) of the screen, confirmed safe areas / thumb reach / touch targets / dark mode against the checklist, and fixed every divergence from the Phase 1-3 intent — or you have explicitly stated no device was reachable and you verified by code inspection instead.

---

## Phase 5 — Evaluate

Same discipline as `/design` Phase 5: a **separate, skepticism-tuned subagent** scores the design, because self-praise is the default and the generator cannot grade itself. The mobile evaluator differs in two ways — it scores a **9-dimension mobile rubric** (adds Platform-Nativeness, Ergonomics/Touch-Targets, Safe-Area to the web six), and it receives the **device screenshots from Phase 4** so it can verdict the **vision match** (does the rendered build look like the intent), not just the design in the abstract.

This phase is mandatory for any screen the user will actually ship. Skip it only for a throwaway prototype or a quick one-off iteration where the user explicitly said "just something rough" — say that you skipped it and why.

**Do NOT load [`references/evaluation-rubric.md`](references/evaluation-rubric.md) yourself** — it belongs to the evaluator subagent. Loading it contaminates the generator/evaluator separation. You read only [`evaluator-prompt.md`](evaluator-prompt.md) to understand what the subagent does.

To run it:
1. Collect the design output (file paths) and the Phase 4 screenshot paths (light, dark, and any state/device variants).
2. Read [`evaluator-prompt.md`](evaluator-prompt.md) and copy it verbatim — then **substitute the `<SKILL_DIR>` placeholder with this skill's real absolute directory path** (the folder containing this SKILL.md) so the subagent can actually find `references/evaluation-rubric.md`. Skipping this substitution makes the subagent read nothing and return an unanchored score — it breaks the generator/evaluator separation silently.
3. Spawn a subagent: `subagent_type: "general-purpose"`, `model: "sonnet"`, `mode: "bypassPermissions"`. Task = the full (substituted) evaluator prompt, then a delimiter, then the design intent (your Phase 1-3 commitments) and the absolute screenshot paths with an instruction to Read each PNG as an image.
4. The evaluator returns per-dimension scores (1-5), a weighted composite, a STRONG/PARTIAL/DIVERGED vision-match verdict, violations with severity, and a prioritized fix list.
5. Iterate: composite **>= 4.0 -> ship**; 3.5-3.9 -> apply top 3 fixes, re-spawn a **fresh** evaluator (no prior-score anchoring); < 3.5 -> the lowest dimension routes you back (Safe-Area/Ergonomics -> Phase 3/4 implementation; Platform-Nativeness -> Phase 1 stance or Phase 3; Usability -> Phase 2). A DIVERGED vision-match means fix the build-vs-intent gap before trusting any score. Cap at 4 loops, then escalate to the user.

**If the subagent is unavailable**, fall back to a self-evaluation against the rubric, label it explicitly as a lower-fidelity self-eval (the generator/evaluator separation is broken), and tell the user.

---

## The Mobile NEVER List

Reinforces, does not replace, the `/design` NEVER list. These are the mobile-specific landmines a trained eye catches instantly.

- **NEVER anchor a primary action at the top of a tall screen.** It is out of thumb reach. Bottom, inside the safe area.
- **NEVER hardcode safe-area padding** (`paddingTop: 44`, `bottom: 0`). Use `useSafeAreaInsets()` — every device differs.
- **NEVER ship an iOS shadow (`shadowColor/Offset/Opacity/Radius`) without an Android `elevation`.** The card looks flat on Android, silently.
- **NEVER build a design around an iOS-only native effect (blur/glass/SF Symbols) without a designed Android fallback.** It renders as a flat fill and the whole look collapses.
- **NEVER write `lineHeight` as a multiplier or `letterSpacing` as em in React Native.** Both are absolute; text overlaps or mis-tracks.
- **NEVER use `ScrollView` for a long or dynamic list.** It mounts every row; use `FlatList`/`FlashList`.
- **NEVER rely on hover for any affordance**, and never ship a tappable with no pressed feedback.
- **NEVER skip dark mode** — it is an OS setting, not a feature. Define light+dark tokens; never hardcode colors in leaf components.
- **NEVER omit `KeyboardAvoidingView`** on a form — the submit button hides under the keyboard (invisible in the iOS simulator).
- **NEVER leave Android on `windowSoftInputMode="adjustPan"`** — it slides the whole screen (and the tab bar) up with the keyboard. Set `adjustResize` so the layout reflows instead.
- **NEVER ship an interactive element without `accessibilityLabel` + `accessibilityRole`** — VoiceOver/TalkBack users get nothing.
- **NEVER set `allowFontScaling={false}` on body or label text** — it overrides the user's accessibility setting (WCAG 1.4.4).
- **NEVER use more than 5 bottom tabs**, and never hide primary navigation behind a hamburger.
- **NEVER ship a screen you have not looked at rendered on a device (or honestly noted you could not).** Phase 4 is not optional polish.
- **NEVER use an emoji as a functional icon.** Use a cross-platform icon set (Lucide, Phosphor, Material).

---

## Closing Directive

Apply the `/design` closing directive against pattern collapse — then add the mobile test. Before you call a screen done, ask: *if I handed this phone to someone and they used it one-handed on the train, in dark mode, with large text, on Android — does it still work?* If you have not actually checked that on a device in Phase 4, you have not finished. The web port hides in exactly the conditions the mockup never runs in.
