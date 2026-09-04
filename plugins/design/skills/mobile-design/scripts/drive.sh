#!/usr/bin/env bash
# drive.sh — drive the running app over adb to reach states a static screenshot
# misses (open a sheet, scroll, focus an input, navigate). Use tap coordinates
# from ui-dump.sh, never eyeballed pixels.
#
# Usage:
#   ./drive.sh tap <x> <y>
#   ./drive.sh swipe <x1> <y1> <x2> <y2> [duration_ms=300]
#   ./drive.sh scroll up|down [amount_px=700]      (swipes around screen center)
#   ./drive.sh type "<text>"                       (spaces auto-escaped)
#   ./drive.sh key back|home|recents|enter|del|menu
#   ./drive.sh reload                              (opens dev menu; press r in Metro too)
set -euo pipefail

ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"
if ! { [ -x "$ADB" ] && "$ADB" get-state >/dev/null 2>&1; }; then
  echo "ERROR: no adb device. (iOS sim taps need 'idb ui tap'.)" >&2
  exit 1
fi

cmd="${1:-}"; shift || true
case "$cmd" in
  tap)    "$ADB" shell input tap "$1" "$2" ;;
  swipe)  "$ADB" shell input swipe "$1" "$2" "$3" "$4" "${5:-300}" ;;
  scroll)
    read -r w h < <("$ADB" shell wm size | awk '{print $NF}' | tr 'x' ' ')
    cx=$(( w / 2 )); mid=$(( h / 2 )); amt="${2:-700}"
    if [ "${1:-down}" = "up" ]; then
      "$ADB" shell input swipe "$cx" "$(( mid - amt/2 ))" "$cx" "$(( mid + amt/2 ))" 300
    else
      "$ADB" shell input swipe "$cx" "$(( mid + amt/2 ))" "$cx" "$(( mid - amt/2 ))" 300
    fi ;;
  type)   "$ADB" shell input text "${1// /%s}" ;;
  key)
    case "${1:-}" in
      back) k=4;; home) k=3;; recents) k=187;; enter) k=66;; del) k=67;; menu) k=82;;
      *) echo "unknown key: ${1:-}  (back|home|recents|enter|del|menu)" >&2; exit 1;;
    esac
    "$ADB" shell input keyevent "$k" ;;
  reload) "$ADB" shell input keyevent 82; echo "dev menu opened — tap Reload, or press r in Metro" ;;
  *) echo "usage: drive.sh {tap|swipe|scroll|type|key|reload} ..." >&2; exit 1 ;;
esac
