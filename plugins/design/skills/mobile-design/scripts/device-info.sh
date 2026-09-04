#!/usr/bin/env bash
# device-info.sh — print the connected device's resolution, density, dp width,
# Android version, and foreground app. Confirms a device is reachable and gives
# the numbers Phase 4 verification needs (dp width drives layout math).
#
# Usage: ./device-info.sh        (ADB=/path/to/adb to override)
set -euo pipefail

ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"

if [ -x "$ADB" ] && "$ADB" get-state >/dev/null 2>&1; then
  size="$("$ADB" shell wm size | awk '{print $NF}' | tr -d '\r')"
  density="$("$ADB" shell wm density | awk '{print $NF}' | tr -d '\r')"
  px_w="${size%x*}"
  dp_w=$(( px_w * 160 / density ))
  android="$("$ADB" shell getprop ro.build.version.release | tr -d '\r')"
  focus="$("$ADB" shell "dumpsys window | grep mCurrentFocus" 2>/dev/null | head -1 | xargs || true)"
  printf 'Platform   : Android %s\n' "$android"
  printf 'Resolution : %s px\n' "$size"
  printf 'Density    : %s dpi\n' "$density"
  printf 'Width      : %s px = %s dp\n' "$px_w" "$dp_w"
  printf 'Foreground : %s\n' "$focus"
elif command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices 2>/dev/null | grep -q Booted; then
  echo "Platform   : iOS Simulator"
  xcrun simctl list devices | grep Booted | sed 's/^[[:space:]]*/Device     : /'
else
  echo "ERROR: no adb device and no booted iOS simulator." >&2
  exit 1
fi
