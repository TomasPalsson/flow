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
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every scaffold run produce the same shas, so a
# postcheck can compare a finished tree against a regenerated pristine one.
N=0
commit() {
	N=$((N + 1))
	local when
	when=$(printf '2026-09-%02dT10:00:00Z' $((10 + N)))
	GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when git commit -q -m "$1"
}

# ---- base commit: a cart library with money formatting ---------------------------
mkdir -p cartcalc tests
printf '__pycache__/\n*.pyc\n.specs/.next-call-count\n' >.gitignore
cat >README.md <<'MD'
# cartcalc

Cart arithmetic in integer cents.

Run tests: `python3 -m unittest discover -s tests -v`
MD
cat >pyproject.toml <<'TOML'
# Tests: python3 -m unittest discover -s tests -v
[project]
name = "cartcalc"
version = "0.0.0"
dependencies = []
TOML
: >cartcalc/__init__.py
: >tests/__init__.py
cat >cartcalc/lines.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Line:
    name: str
    unit_cents: int
    qty: int = 1

    def __post_init__(self):
        if self.unit_cents < 0:
            raise ValueError("unit_cents must not be negative")
        if self.qty < 1:
            raise ValueError("qty must be at least 1")

    @property
    def total_cents(self):
        return self.unit_cents * self.qty
PY
cat >cartcalc/money.py <<'PY'
def cents_str(cents):
    return "$%d.%02d" % (cents // 100, cents % 100)
PY
cat >tests/test_lines.py <<'PY'
import unittest

from cartcalc.lines import Line


class TestLine(unittest.TestCase):
    def test_line_total_multiplies_quantity(self):
        self.assertEqual(Line("pen", 150, 3).total_cents, 450)

    def test_zero_quantity_is_rejected(self):
        with self.assertRaises(ValueError):
            Line("pen", 150, 0)
PY
git add -A
commit "base: cartcalc lines and money formatting"
BASE=$(git rev-parse --short HEAD)

# ---- T001: percent discount ---------------------------------------------------------
cat >cartcalc/pricing.py <<'PY'
def discount_cents(subtotal_cents, percent):
    return (subtotal_cents * percent + 50) // 100
PY
cat >tests/test_pricing.py <<'PY'
import unittest

from cartcalc.pricing import discount_cents


class TestPricing(unittest.TestCase):
    def test_whole_cent_discount(self):
        self.assertEqual(discount_cents(1000, 10), 100)

    def test_half_cent_rounds_up(self):
        self.assertEqual(discount_cents(250, 5), 13)
PY
git add -A
commit "feat: percent discount rounded half up"
S1=$(git rev-parse --short HEAD)

# ---- T002: discounted cart total -------------------------------------------------------
cat >cartcalc/cart.py <<'PY'
from cartcalc.pricing import discount_cents


def total_cents(lines, percent=0):
    subtotal = sum(line.total_cents for line in lines)
    return subtotal - discount_cents(subtotal, percent)
PY
cat >tests/test_cart.py <<'PY'
import unittest

from cartcalc.cart import total_cents
from cartcalc.lines import Line


class TestCart(unittest.TestCase):
    def test_total_without_discount(self):
        self.assertEqual(total_cents([Line("pen", 150, 2), Line("ink", 400)]), 700)

    def test_total_with_ten_percent(self):
        self.assertEqual(total_cents([Line("pen", 150, 2), Line("ink", 400)], 10), 630)
PY
git add -A
commit "feat: cart total with a percent discount"
S2=$(git rev-parse --short HEAD)

# ---- the feature dir: approved, built, gated, verified by a human ------------------------
D=.specs/001-cart-discount
mkdir -p "$D/verify"
printf '001-cart-discount\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Cart discount

**Created**: 2026-09-12 · **Route**: dispatch

## TL;DR

**Problem**: Sales quotes a percent discount by calculator and the cents drift.

**Solution**: `total_cents(lines, percent)` returns the discounted total in integer cents; a half cent always rounds up.

**Who it's for**: Sales staff building quotes.

## 2. Scope

### 2.2 Non-goals

- No stacked discounts, no per-line discounts.

## 6. Launch criteria

- [ ] AC1: 10 percent off 1000 cents is 100 cents.
- [ ] AC2: a half-cent discount rounds up (5 percent of 250 cents is 13 cents).
- [ ] AC3: `total_cents` subtracts the discount from the line subtotal.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Cart discount
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-12 by user
Verified: 2026-09-14 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a subtotal and a percent, when I ask for the discount, then a half cent rounds up | T001 | test_half_cent_rounds_up |
| B2 (P0) | Given lines and a percent, when I total the cart, then the discount comes off the subtotal | T002 | test_total_with_ten_percent |

## Phase 1 — Discounted totals
Goal: sales can total a cart with a percent discount in integer cents.
Independent test: \`python3 -m unittest tests.test_cart\` — green with money formatting untouched.
- [x] T001 Percent discount rounded half up (B1) — files: cartcalc/pricing.py, tests/test_pricing.py — verify: \`python3 -m unittest tests.test_pricing\` — done: $S1
- [x] T002 Discounted cart total (B2) — files: cartcalc/cart.py, tests/test_cart.py — verify: \`python3 -m unittest tests.test_cart\` — after: T001 — done: $S2

## Gates
- [x] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\` — done: $S2
- [x] G002 branch review clean — files: . — verify: \`flow pass\` — done: $S2
MD
NO_COLOR=1 python3 -m unittest discover -s tests 2>&1 | sed 's/ in [0-9.]*s$/ in 0.001s/' >"$D/verify/test-run.txt"
find . -name __pycache__ -type d -prune -exec rm -rf {} +
git add -A
commit "chore: feature dir for cart discount, gates and evidence"
PASS_SHA=$(git rev-parse --short HEAD)
cat >"$D/PASS-$PASS_SHA.md" <<MD
# PASS-$PASS_SHA

| Gate | Command | Exit |
|------|---------|------|
| G001 | python3 -m unittest discover -s tests | 0 |
| G002 | whole-branch review of Base..HEAD | 0 |
MD
git add -A
commit "chore: PASS for $PASS_SHA"

# ---- after verification: a "simplification" lands, then a docs commit ----------------------
cat >cartcalc/pricing.py <<'PY'
def discount_cents(subtotal_cents, percent):
    return round(subtotal_cents * percent / 100)
PY
git add cartcalc/pricing.py
commit "refactor: drop the integer rounding trick in discount_cents"
cat >>README.md <<'MD'

## Rounding

A discount that lands on a half cent rounds up, matching the accountants' sheet.
MD
git add README.md
commit "docs: note the rounding rule"
