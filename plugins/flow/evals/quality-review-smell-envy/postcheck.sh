#!/usr/bin/env bash
set -u
[ -f review-out.md ] || { echo "postcheck: review-out.md missing"; exit 1; }
grep -qi 'possible Feature Envy' review-out.md || { echo "postcheck: no 'possible Feature Envy' in the review"; exit 1; }
# The text between "Verified:" and "Could be smaller:" is the blocking list; a structure smell must not sit there.
VERIFIED=$(awk 'tolower($0) ~ /verified:/{f=1; next} tolower($0) ~ /could be smaller:/{f=0} f' review-out.md)
if printf '%s' "$VERIFIED" | grep -qi 'envy'; then echo "postcheck: Feature Envy is in the blocking list"; exit 1; fi
if ! awk 'tolower($0) ~ /could be smaller:/{f=1} f' review-out.md | grep -qi 'envy'; then echo "postcheck: Feature Envy is not under 'Could be smaller:'"; exit 1; fi
