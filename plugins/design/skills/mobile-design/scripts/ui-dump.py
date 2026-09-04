#!/usr/bin/env python3
"""ui-dump.py — parse a uiautomator XML hierarchy into a list of tappable
elements with their center coordinates (for `adb shell input tap CX CY`) and
size in dp, flagging anything below the 48dp touch-target minimum.

Usage: ui-dump.py <ui.xml> [dpi]      (dpi default 480; dp = px * 160 / dpi)

Reading exact bounds beats eyeballing pixel coordinates from a screenshot.
"""
import re
import sys
import xml.etree.ElementTree as ET


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: ui-dump.py <ui.xml> [dpi]", file=sys.stderr)
        return 2
    path = sys.argv[1]
    dpi = int(sys.argv[2]) if len(sys.argv) > 2 else 480

    try:
        tree = ET.parse(path)
    except (ET.ParseError, FileNotFoundError) as e:
        print(f"ERROR: cannot parse {path}: {e}", file=sys.stderr)
        return 1

    print(f"{'TAP (cx cy)':>14}  {'SIZE dp':>9}  LABEL")
    print("-" * 64)
    count = 0
    for node in tree.getroot().iter("node"):
        if node.get("clickable") != "true" and node.get("long-clickable") != "true":
            continue
        pts = re.findall(r"\[(\d+),(\d+)\]", node.get("bounds", ""))
        if len(pts) != 2:
            continue
        (x1, y1), (x2, y2) = ((int(a), int(b)) for a, b in pts)
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        w_dp = round((x2 - x1) * 160 / dpi)
        h_dp = round((y2 - y1) * 160 / dpi)
        label = (
            node.get("text")
            or node.get("content-desc")
            or node.get("resource-id", "").split("/")[-1]
            or "?"
        )
        flag = "  !! <48dp" if (w_dp < 48 or h_dp < 48) else ""
        print(f"  tap {cx:>4} {cy:>4}  {w_dp:>3}x{h_dp:<3}dp  {label[:48]}{flag}")
        count += 1

    print(f"\n{count} clickable elements"
          + ("  (>= one below 48dp — see !! flags)" if count else ""))
    if count == 0:
        print("note: 0 clickable nodes — the hierarchy may be mid-transition, "
              "or RN views lack accessible/clickable flags. Re-dump, or add "
              "accessibilityLabel props for a readable tree.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
