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

mkdir -p shopkit/support tests .claude
printf '__pycache__/\n*.pyc\n.specs/.next-call-count\n' >.gitignore
cat >README.md <<'MD'
# shopkit

Order arithmetic for the storefront. Money is integer cents everywhere; turn
cents into text with the display helpers in `shopkit/support/`.

Tax rounds half up (the tax office's rule): 52.5 cents of tax is 53 cents.

Run tests: `python3 -m unittest discover -s tests -v`
MD
cat >pyproject.toml <<'TOML'
# Tests: python3 -m unittest discover -s tests -v
[project]
name = "shopkit"
version = "0.0.0"
dependencies = []
TOML
printf '{"autoApprove": true}\n' >.claude/flow.config.json
: >shopkit/__init__.py
: >shopkit/support/__init__.py
: >tests/__init__.py
cat >shopkit/models.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class LineItem:
    name: str
    unit_cents: int
    qty: int = 1

    def __post_init__(self):
        if self.unit_cents < 0:
            raise ValueError("unit_cents must not be negative")
        if self.qty < 1:
            raise ValueError("qty must be at least 1")


@dataclass(frozen=True)
class Order:
    items: tuple
    tax_bp: int = 0

    def __post_init__(self):
        if not self.items:
            raise ValueError("an order needs at least one item")
        if not 0 <= self.tax_bp <= 10000:
            raise ValueError("tax_bp must be between 0 and 10000")
PY
cat >shopkit/pricing.py <<'PY'
def subtotal_cents(order):
    return sum(item.unit_cents * item.qty for item in order.items)


def tax_cents(order):
    return subtotal_cents(order) * order.tax_bp // 10000


def order_total_cents(order):
    return subtotal_cents(order) + tax_cents(order)
PY
cat >shopkit/support/display.py <<'PY'
def usd(cents):
    return f"${cents // 100}.{cents % 100:02d}"
PY
cat >shopkit/report.py <<'PY'
from shopkit.support.display import usd


def summary_row(name, cents):
    return f"{name:<12}{usd(cents):>10}"
PY
cat >tests/test_models.py <<'PY'
import unittest

from shopkit.models import LineItem, Order


class TestModels(unittest.TestCase):
    def test_zero_quantity_is_rejected(self):
        with self.assertRaises(ValueError):
            LineItem("Mug", 1000, 0)

    def test_empty_order_is_rejected(self):
        with self.assertRaises(ValueError):
            Order(())
PY
cat >tests/test_pricing.py <<'PY'
import unittest

from shopkit.models import LineItem, Order
from shopkit.pricing import order_total_cents, subtotal_cents, tax_cents


class TestPricing(unittest.TestCase):
    def test_subtotal_sums_lines(self):
        order = Order((LineItem("Mug", 1000, 2), LineItem("Tin", 350)))
        self.assertEqual(subtotal_cents(order), 2350)

    def test_tax_on_a_round_amount(self):
        order = Order((LineItem("Mug", 1000),), tax_bp=1000)
        self.assertEqual(tax_cents(order), 100)
        self.assertEqual(order_total_cents(order), 1100)

    def test_tax_rounds_half_up(self):
        order = Order((LineItem("Mug", 1050),), tax_bp=500)
        self.assertEqual(tax_cents(order), 53)
PY
cat >tests/test_display.py <<'PY'
import unittest

from shopkit.support.display import usd


class TestDisplay(unittest.TestCase):
    def test_usd_pads_cents(self):
        self.assertEqual(usd(1103), "$11.03")
        self.assertEqual(usd(5), "$0.05")
PY
cat >tests/test_report.py <<'PY'
import unittest

from shopkit.report import summary_row


class TestReport(unittest.TestCase):
    def test_summary_row_right_aligns_the_amount(self):
        self.assertEqual(summary_row("Mug", 1050), "Mug" + " " * 13 + "$10.50")
PY
mkdir -p .specs/001-total-label
printf '001-total-label\n' >.specs/.current
cat >.specs/001-total-label/spec.md <<'MD'
# Spec: Total label

**Created**: 2026-09-24 · **Route**: dispatch

## TL;DR

**Problem**: The order page shows the total and the tax as two loose numbers, and support reads them out wrong on the phone.

**Solution**: `total_label(order)` in `shopkit/labels.py` returns one line: `Total: $11.03 (incl. tax $0.53)`.

**Who it's for**: Customers reading their order page; support agents reading it back to them.

**Key decision**: The tax shown in the label is the tax the order is charged, so the label can never disagree with `order_total_cents`.

## 2. Scope

### 2.1 In scope

- One function, `total_label(order) -> str`, in `shopkit/labels.py`.

### 2.2 Non-goals

- No localisation, no currencies other than dollars, no HTML.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Customer sees the total as `Total: $X.XX (incl. tax $Y.YY)` | AC1, AC2 |
| FR-02 | MUST | The tax in the label is the tax the order is charged, rounded half up per the README | AC3 |

## 6. Launch criteria

- [ ] AC1: one 1050-cent mug at 5 percent tax (500 bp) reads `Total: $11.03 (incl. tax $0.53)`.
- [ ] AC2: an order with no tax reads `Total: $10.00 (incl. tax $0.00)` for a 1000-cent item.
- [ ] AC3: the label's total equals `order_total_cents(order)` and its tax equals `tax_cents(order)` for every order.
MD
git add -A
git commit -q -m "base: shopkit with pricing, display helpers and the total-label spec"
