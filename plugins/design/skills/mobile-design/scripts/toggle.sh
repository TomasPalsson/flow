#!/usr/bin/env bash
# toggle.sh — flip device theme / font scale / reduce-motion to stress-test a
# design from the CLI, then re-screenshot. Always reset when done.
#
# Usage:
#   ./toggle.sh dark | light
#   ./toggle.sh font <scale>        e.g. 1.3 (large Dynamic Type), 1.0 to reset
#   ./toggle.sh reduce-motion on|off
#   ./toggle.sh reset               restore light, font 1.0, animations on
set -euo pipefail

ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"
IS_IOS=0
if ! { [ -x "$ADB" ] && "$ADB" get-state >/dev/null 2>&1; }; then
  if command -v xcrun >/dev/null 2>&1 && xcrun simctl list devices 2>/dev/null | grep -q Booted; then
    IS_IOS=1
  else
    echo "ERROR: no adb device and no booted iOS simulator." >&2; exit 1
  fi
fi

case "${1:-}" in
  dark|light)
    if [ "$IS_IOS" = 1 ]; then xcrun simctl ui booted appearance "$1"
    else "$ADB" shell "cmd uimode night $([ "$1" = dark ] && echo yes || echo no)"; fi
    sleep 0.8; echo "appearance -> $1" ;;
  font)
    scale="${2:?usage: toggle.sh font <scale>}"
    if [ "$IS_IOS" = 1 ]; then
      case "$scale" in 1.0|1) sz=medium;; 1.3) sz=extra-large;; *) sz=accessibility-extra-large;; esac
      xcrun simctl ui booted contentSize "$sz"; echo "iOS contentSize -> $sz"
    else
      "$ADB" shell settings put system font_scale "$scale"; sleep 0.5
      echo "font_scale -> $scale (applies on next activity resume)"
    fi ;;
  reduce-motion)
    [ "$IS_IOS" = 1 ] && { echo "set Settings>Accessibility>Motion on the sim manually"; exit 0; }
    v=$([ "${2:-on}" = on ] && echo 0 || echo 1)
    for s in animator_duration_scale transition_animation_scale window_animation_scale; do
      "$ADB" shell settings put global "$s" "$v"
    done; echo "reduce-motion -> ${2:-on}" ;;
  reset)
    if [ "$IS_IOS" = 1 ]; then
      xcrun simctl ui booted appearance light; xcrun simctl ui booted contentSize medium
    else
      "$ADB" shell "cmd uimode night no"
      "$ADB" shell settings put system font_scale 1.0
      for s in animator_duration_scale transition_animation_scale window_animation_scale; do
        "$ADB" shell settings put global "$s" 1
      done
    fi; echo "reset: light, font 1.0, animations on" ;;
  *) echo "usage: toggle.sh {dark|light|font <scale>|reduce-motion on|off|reset}" >&2; exit 1 ;;
esac
