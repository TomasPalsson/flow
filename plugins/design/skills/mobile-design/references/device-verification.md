---
name: device-verification
description: The full device-driven verification reference — exact adb and iOS-simulator command recipes (screenshot, view-hierarchy/tap-target measurement, input driving, theme and font-scale toggles), the multi-display screenshot gotcha, what an LLM can and cannot judge from a screenshot, and the build-vs-vision checklist. MANDATORY read before running any device command in Phase 4. The scripts in scripts/ are the fast path; this is the ground truth and the fallback.
---

# Device Verification Reference

Goal: a closed loop — **build -> screenshot (light+dark) -> read & critique vs the design vision -> edit -> reload -> re-screenshot -> confirm**. The agent never guesses whether padding changed or a target is reachable; it sees the rendered pixels and reads exact tap bounds from the live hierarchy.

All adb recipes below were verified live on a physical Samsung (1080x2640, 480dpi, multi-display). Assume:
```bash
ADB=/opt/homebrew/share/android-commandlinetools/platform-tools/adb   # or wherever adb lives; `which adb`
```

## 0. Reach the device
```bash
$ADB devices                 # must show "device", not "unauthorized" (accept the on-device RSA prompt)
$ADB -s <SERIAL> ...         # disambiguate when more than one is connected
```
iOS: `xcrun simctl list devices | grep Booted` to confirm a booted simulator.

## 1. Screenshot — THE GOTCHA
`adb exec-out screencap -p > out.png` **corrupts the PNG on multi-display devices**: a `[Warning] Multiple displays...` line is injected at byte 0 (check with `xxd out.png | head -1` — you want `89 50 4e 47`, the PNG magic, not `[Warning]`). `exec-out` merges stderr into stdout.

**Always use the device-file-then-pull method:**
```bash
$ADB shell screencap -p /sdcard/s.png && $ADB pull /sdcard/s.png ./light.png && $ADB shell rm /sdcard/s.png
```
Dark mode: toggle, wait ~0.8s to settle, capture, toggle back (see section 5). Foldable/multi-display: get the numeric id from `adb shell "dumpsys SurfaceFlinger --display-id"` and pass `screencap -d <id>`.

iOS simulator (no gotcha, writes straight to host):
```bash
xcrun simctl io booted screenshot ./light.png
```

## 2. Measure exact tap targets (do not eyeball pixels)
```bash
$ADB shell uiautomator dump /sdcard/ui.xml && $ADB pull /sdcard/ui.xml ./ui.xml && $ADB shell rm /sdcard/ui.xml
```
Each `node` has `bounds="[x1,y1][x2,y2]"`, `text`, `content-desc`, `resource-id`, `clickable`. Center = `((x1+x2)/2,(y1+y2)/2)` — use that to drive. Size in dp = `px * 160 / dpi`; flag anything < 48dp. `scripts/ui-dump.sh` does the dump+parse and prints `tap CX CY | WxH dp | label` with a `!! <48dp` flag. An LLM cannot reliably estimate pixel coords from an image; this is ground truth. (RN trees run 15+ levels deep; `uiautomator dump --compressed` if it truncates.)

## 3. Drive the UI
```bash
$ADB shell input tap <x> <y>                         # coords from section 2, not from a screenshot
$ADB shell input swipe <x1> <y1> <x2> <y2> [ms]      # scroll = vertical swipe; swipe-to-delete = horizontal
$ADB shell input text "Hello%sWorld"                 # space=%s, @=%40; single-quote and pre-escape special chars
$ADB shell input keyevent 4    # BACK   (3=HOME, 187=RECENTS, 66=ENTER, 67=DEL, 61=TAB, 82=dev menu)
$ADB shell am start -n <package>/.MainActivity       # relaunch; package e.g. com.anonymous.<app> (dev build) or host.exp.exponent (Expo Go)
```
Reload JS: Metro `r`, or keyevent 82 then tap Reload, or relaunch the activity. iOS sim tap automation needs `idb` (`brew install idb-companion`, `idb ui tap x y`) — `simctl` has no tap; otherwise drive iOS by hand and use it mainly for screenshots/theme.

## 4. Device facts for design math
```bash
$ADB shell wm size      # Physical size: 1080x2640
$ADB shell wm density   # Physical density: 480  -> dp width = 1080*160/480 = 360dp
$ADB shell "dumpsys window | grep mCurrentFocus"   # confirm the foreground screen
```
`scripts/device-info.sh` prints all of this at once.

## 5. Theme + accessibility toggles (test both themes and large text from the CLI)
```bash
$ADB shell "cmd uimode night yes"   # dark   (wait ~0.8s before screenshot)
$ADB shell "cmd uimode night no"    # light
$ADB shell settings put system font_scale 1.3      # large Dynamic Type (applies on next activity resume; ~0.5s)
$ADB shell settings put system font_scale 1.0      # reset
$ADB shell settings put global window_animation_scale 0    # reduce motion (also animator_/transition_); reset to 1
```
iOS sim: `xcrun simctl ui booted appearance dark|light`, `xcrun simctl ui booted contentSize extra-large|medium`. `scripts/toggle.sh` wraps these.

## Verification methodology — what an LLM can and cannot judge

**CAN judge from a screenshot (reliably):** layout/columns/overflow/clipping; safe-area compliance (content under status bar/notch/home indicator — one of the most reliable checks); gross contrast failures (white-on-light, dark-on-dark); whether the brand color/background tint is present; platform feel (native vs web port); dark-mode gross failures (invisible text, white flash); state coverage (is this the empty/error/loading screen?); typography family (serif/sans/mono); whether a target *looks* tappably large.

**CANNOT judge from a screenshot — use the alternative:**
| Cannot determine | Use instead |
|---|---|
| Exact target size in pt/dp | `uiautomator` bounds (section 2) |
| Marginal contrast (3.8 vs 4.5:1) | contrast checker on the tokens |
| Animation smoothness / jank | code inspection of animated props; `adb shell screenrecord /sdcard/v.mp4 --time-limit 5` |
| Keyboard avoidance | live device: focus an input, screenshot with keyboard up |
| VoiceOver/TalkBack order | on-device screen-reader traversal |
| Haptics | manual note vs the Phase 3 haptic intent |

## Build-vs-vision checklist (apply to every light+dark screenshot pair)
```
[ ] Safe areas: nothing under status bar / notch / Dynamic Island / home indicator / gesture bar
[ ] Primary action sits in the bottom thumb zone, above the safe-area inset
[ ] Touch targets look >= 44pt (confirm suspects with uiautomator bounds)
[ ] Color + spacing match the Phase 3 tokens (no accidental pure white/black, no spacing drift)
[ ] Platform-native components (tab bar / bottom sheet, not centered modal; no web scrollbar/tap-highlight)
[ ] Native effect intended (glass/blur) renders as real blur, NOT a flat fill (check Android specifically)
[ ] Dark mode: dark surface, text legible, CTA prominent, semantic colors intact, icons visible
[ ] Large text (font_scale 1.3): no truncation, no overflow, no collapsed layout
[ ] State coverage: empty/loading/error screenshots exist and are not blank voids
[ ] No clipped/overflowing text
```
Verdict per screen: STRONG (all pass) / PARTIAL (minor, non-safe-area) / DIVERGED (any safe-area, touch-target, or nav-pattern fail) — and fix DIVERGED before trusting any evaluation score.

Optional regression diff when a reference PNG exists: `compare -metric AE reference.png current.png diff.png` (ImageMagick; AE=0 is identical).

## Gotchas
- `exec-out screencap` corrupts PNG on multi-display — use shell+pull.
- `cmd uimode night` needs ~0.8s settle; `font_scale` applies on next activity resume (~0.5s or cycle the activity).
- `input text` chokes on `& | ' "` — single-quote and pre-escape; `%s` for space.
- Multiple devices -> always `-s <SERIAL>`.
- `uiautomator dump` may need `--compressed` on deep RN trees; add `accessibilityLabel` props for readable hierarchy.
- iOS sim has no `simctl` tap — use `idb` or drive by hand.
