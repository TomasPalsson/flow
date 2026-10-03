#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q -b flow/low-stock-digest
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare TASKS.md byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app/support app/reports tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >app/support/__init__.py
: >app/reports/__init__.py
: >tests/__init__.py
cat >app/models.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Item:
    sku: int
    name: str
    qty: int

    def __post_init__(self):
        if self.sku <= 0:
            raise ValueError("sku must be positive")
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if self.qty < 0:
            raise ValueError("qty must not be negative")
PY
cat >app/support/text.py <<'PY'
def ellipsize(text, limit):
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"


def squash_spaces(text):
    return " ".join(text.split())
PY
cat >app/support/numbers.py <<'PY'
def clamp(value, low, high):
    return max(low, min(high, value))
PY
cat >app/reports/summary.py <<'PY'
def summarize(items):
    total = sum(item.qty for item in items)
    return {"skus": len(items), "units": total}
PY
cat >app/reports/digest.py <<'PY'
def build_digest(items, threshold):
    raise NotImplementedError("the digest is built in a later wave")
PY
cat >app/cli.py <<'PY'
import sys

from app.models import Item
from app.reports.summary import summarize


def main(argv=None):
    items = [Item(1, "Widget", 40), Item(2, "Gasket", 3)]
    stats = summarize(items)
    sys.stdout.write("%d skus, %d units\n" % (stats["skus"], stats["units"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
cat >tests/test_summary.py <<'PY'
import unittest

from app.models import Item
from app.reports.summary import summarize


class TestSummarize(unittest.TestCase):
    def test_summarize_counts_skus_and_units(self):
        items = [Item(1, "Widget", 4), Item(2, "Gasket", 6)]
        self.assertEqual(summarize(items), {"skus": 2, "units": 10})
PY
cat >tests/test_text.py <<'PY'
import unittest

from app.support.text import ellipsize


class TestEllipsize(unittest.TestCase):
    def test_text_within_limit_comes_back_as_is(self):
        self.assertEqual(ellipsize("abc", 5), "abc")
PY
cat >README.md <<'MD'
# stockroom

Inventory reports for the warehouse team.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: stockroom skeleton"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-low-stock-digest
printf '001-low-stock-digest\n' >.specs/.current
cat >.specs/001-low-stock-digest/spec.md <<'MD'
# Spec — Low-stock digest

Ops want a digest of items that are running low, printed as shelf labels.

## Requirements
- R1: `low_stock(items, threshold)` in `app/reports/low_stock.py` returns a list of the
  items whose `qty` is strictly below `threshold`, fewest units first, ties broken by name.
- R2: `shelf_label(item, width=24)` in `app/reports/labels.py` returns
  `<sku zero-padded to 5 digits> <name>`, with the name cut to `width` characters
  (ending in an ellipsis when it was cut).
- R3: `build_digest(items, threshold)` in `app/reports/digest.py` returns one shelf label
  per low-stock item, one per line.

## Acceptance
- A1: only items strictly below the threshold appear, ordered fewest first, ties by name.
- A2: a long name is cut to the width with a trailing ellipsis; a short name is untouched.
- A3: the digest lists one shelf label per low-stock item.
MD
cat >.specs/001-low-stock-digest/TASKS.md <<TASKS
# Tasks — Low-stock digest
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given items with varied qty, when low_stock(items, 5) runs, then only items below 5 come back, fewest first, ties by name | T001 | test_low_stock |
| B2 (P0) | Given an item with a long name, when shelf_label(item, 12) runs, then the name is cut to 12 characters ending in an ellipsis | T002 | test_labels |
| B3 (P1) | Given items, when build_digest runs, then it lists one shelf label per low-stock item | T003 | test_digest |

## Phase 1 — Digest
Goal: ops can print a low-stock digest of shelf labels.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 [P] low_stock filter (B1) — files: app/reports/low_stock.py, tests/test_low_stock.py — verify: \`python3 -m unittest tests.test_low_stock\`
- [ ] T002 [P] shelf_label (B2) — files: app/reports/labels.py, tests/test_labels.py — verify: \`python3 -m unittest tests.test_labels\`
- [ ] T003 build_digest (B3) — files: app/reports/digest.py, tests/test_digest.py — verify: \`python3 -m unittest tests.test_digest\` — after: T001, T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: low-stock digest, approved"
