#!/usr/bin/env bash
# What a perfect converge pass leaves on disk: the gates were run (green), the
# whole-branch review found nothing, the converge pass saw that spec criterion A3
# has no task, and APPENDED T004 for it. No PASS file (the tree misses A3), no
# gate ticked, nothing built, no Verified:.
set -euo pipefail
SPEC=.specs/001-loyalty-points

python3 -m unittest discover -s tests >/dev/null 2>&1
python3 - "$SPEC/TASKS.md" <<'PY'
import sys

path = sys.argv[1]
text = open(path, encoding="utf-8").read()
row = (
    "- [ ] T004 Expiry of old points (A3) — files: perks/expiry.py, tests/test_expiry.py"
    " — verify: `python3 -m unittest tests.test_expiry` — after: T003\n"
)
marker = "\n## Gates\n"
assert marker in text
head, tail = text.split(marker, 1)
head = head.rstrip("\n") + "\n" + row
open(path, "w", encoding="utf-8").write(head + marker + tail)
PY
git add "$SPEC/TASKS.md"
git commit -q -m "plan: append T004 for the unmet expiry criterion"
