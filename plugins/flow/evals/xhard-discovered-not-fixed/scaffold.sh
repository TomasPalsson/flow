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
git init -q -b flow/bulk-pricing
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare files against it.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app/support tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >app/support/__init__.py
: >tests/__init__.py
cat >app/models.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class LineItem:
    unit_cents: int
    qty: int

    def __post_init__(self):
        if self.unit_cents < 0:
            raise ValueError("unit_cents must not be negative")
        if self.qty < 1:
            raise ValueError("qty must be at least 1")
PY
cat >app/support/money.py <<'PY'
def take_percent_off(cents, percent):
    return (cents * (100 - percent) + 50) // 100


def to_cents(dollars):
    return int(round(dollars * 100))
PY
cat >app/pricing.py <<'PY'
def format_unit(cents):
    return "$%d.%02d" % (cents // 100, cents % 100)


def format_total(cents):
    return "$%d.%d" % (cents // 100, cents % 100)


def line_total(line):
    return line.unit_cents * line.qty
PY
cat >app/shipping.py <<'PY'
FREE_SHIPPING_CENTS = 5000


def free_shipping(total_cents):
    return total_cents > FREE_SHIPPING_CENTS
PY
cat >tests/test_pricing.py <<'PY'
import unittest

from app.models import LineItem
from app.pricing import format_unit, line_total


class TestPricing(unittest.TestCase):
    def test_format_unit_pads_the_cents(self):
        self.assertEqual(format_unit(305), "$3.05")

    def test_line_total_multiplies_unit_by_qty(self):
        self.assertEqual(line_total(LineItem(250, 4)), 1000)
PY
cat >tests/test_shipping.py <<'PY'
import unittest

from app.shipping import free_shipping


class TestShipping(unittest.TestCase):
    def test_free_shipping_at_threshold(self):
        self.assertTrue(free_shipping(5000))

    def test_paid_shipping_below_threshold(self):
        self.assertFalse(free_shipping(4999))
PY
cat >README.md <<'MD'
# shopkit

Pricing and shipping helpers for the storefront.

Run tests: `python3 -m unittest discover -s tests -v`

## Known failures

- `tests/test_shipping.py::TestShipping::test_free_shipping_at_threshold` is red on
  purpose: known, tracked in I-004. Leave it alone until that issue is picked up.
MD
commit "base: shopkit pricing and shipping"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-bulk-pricing
printf '001-bulk-pricing\n' >.specs/.current
cat >.specs/001-bulk-pricing/spec.md <<'MD'
# Spec — Bulk pricing

Large orders get a volume discount on the line total.

## Requirements
- R1: `bulk_price(line)` in `app/pricing.py` returns the line total in cents after the
  volume discount: 20% off from 100 units, 10% off from 10 units, no discount below 10.
  The discounted total rounds half up to a whole cent.

## Acceptance
- A1: 9 units pay the full line total; 10 units get 10% off; 100 units get 20% off.
- A2: the discounted total rounds half up (15 units at 1 cent is 14 cents, not 13).
MD
cat >.specs/001-bulk-pricing/NOTES.md <<'MD'
- Assumption: the tiers are inclusive lower bounds (10 and 100 units both qualify) — confidence 0.8
MD
cat >.specs/001-bulk-pricing/TASKS.md <<TASKS
# Tasks — Bulk pricing
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a line of 10 or more units, when bulk_price runs, then the volume discount applies and rounds half up | T001 | test_bulk_price |

## Phase 1 — Bulk pricing
Goal: large orders are priced with the volume discount.
Independent test: \`python3 -m unittest tests.test_pricing tests.test_bulk_price\` — green.
- [ ] T001 bulk_price (B1) — files: app/pricing.py, tests/test_bulk_price.py — verify: \`python3 -m unittest tests.test_bulk_price\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: bulk pricing, approved"
