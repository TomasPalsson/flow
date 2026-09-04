#!/usr/bin/env bash
# shot.sh — capture light + dark screenshots of the foreground app.
# Android (adb) primary; falls back to iOS simulator (xcrun simctl) if no adb device.
# Uses the device-file-then-pull method: `adb exec-out screencap` corrupts the PNG
# on multi-display phones (a "[Warning] Multiple displays" line leaks into stdout).
#
# Usage: ./shot.sh [output_dir]        (default ./screenshots)
#        ADB=/path/to/adb ./shot.sh    (override adb location)
set -euo pipefail

OUT="${1:-./screenshots}"
mkdir -p "$OUT"

ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"

android_capture() {
  local name="$1"
  "$ADB" shell screencap -p /sdcard/_shot.png
  "$ADB" pull /sdcard/_shot.png "$OUT/$name.png" >/dev/null
  "$ADB" shell rm /sdcard/_shot.png
  echo "  saved $OUT/$name.png"
}

if [ -x "$ADB" ] && "$ADB" get-state >/dev/null 2>&1; then
  echo "==> Android device via adb"
  echo "--> light"
  "$ADB" shell "cmd uimode night no" >/dev/null 2>&1 || true; sleep 0.8
  android_capture light
  echo "--> dark"
  "$ADB" shell "cmd uimode night yes" >/dev/null 2>&1 || true; sleep 0.8
  android_capture dark
  "$ADB" shell "cmd uimode night no" >/dev/null 2>&1 || true
  echo "done: $OUT/light.png  $OUT/dark.png"
elif command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices 2>/dev/null | grep -q Booted; then
  echo "==> iOS simulator via simctl"
  xcrun simctl ui booted appearance light >/dev/null 2>&1 || true; sleep 0.6
  xcrun simctl io booted screenshot "$OUT/light.png" && echo "  saved $OUT/light.png"
  xcrun simctl ui booted appearance dark  >/dev/null 2>&1 || true; sleep 0.6
  xcrun simctl io booted screenshot "$OUT/dark.png"  && echo "  saved $OUT/dark.png"
  xcrun simctl ui booted appearance light >/dev/null 2>&1 || true
  echo "done: $OUT/light.png  $OUT/dark.png"
else
  echo "ERROR: no Android adb device and no booted iOS simulator found." >&2
  echo "  Android: plug in a device, enable USB debugging, run 'adb devices'." >&2
  echo "  iOS: boot a simulator (xcrun simctl boot '<name>')." >&2
  exit 1
fi
