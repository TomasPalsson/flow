#!/usr/bin/env bash
# ui-dump.sh — pull the live uiautomator view hierarchy and print every tappable
# element with its center tap-coordinates and dp size (<48dp flagged).
#
# Usage: ./ui-dump.sh [out.xml]        (default /tmp/ui.xml)
#        ADB=/path/to/adb ./ui-dump.sh
set -euo pipefail

OUT="${1:-/tmp/ui.xml}"
ADB="${ADB:-$(command -v adb || echo /opt/homebrew/share/android-commandlinetools/platform-tools/adb)}"

if ! { [ -x "$ADB" ] && "$ADB" get-state >/dev/null 2>&1; }; then
  echo "ERROR: no adb device. uiautomator dump is Android-only." >&2
  echo "  (iOS: use Xcode's Accessibility Inspector for hit-area overlay.)" >&2
  exit 1
fi

# --compressed guards against truncation on deep React Native trees.
"$ADB" shell uiautomator dump --compressed /sdcard/_ui.xml >/dev/null 2>&1 \
  || "$ADB" shell uiautomator dump /sdcard/_ui.xml >/dev/null
"$ADB" pull /sdcard/_ui.xml "$OUT" >/dev/null
"$ADB" shell rm /sdcard/_ui.xml

DPI="$("$ADB" shell wm density | awk '{print $NF}' | tr -d '\r')"
exec python3 "$(dirname "$0")/ui-dump.py" "$OUT" "${DPI:-480}"
