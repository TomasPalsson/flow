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
git init -q -b flow/orders-export
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare it byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >tests/__init__.py
cat >app/orders.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Order:
    order_id: int
    customer: str
    total_cents: int

    def __post_init__(self):
        if self.order_id <= 0:
            raise ValueError("order_id must be positive")
        if not self.customer.strip():
            raise ValueError("customer must not be blank")
        if self.total_cents < 0:
            raise ValueError("total_cents must not be negative")
PY
cat >app/csv_util.py <<'PY'
def join_row(cells):
    return ",".join(str(cell) for cell in cells)
PY
cat >app/report.py <<'PY'
from app.orders import Order


def order_totals(orders):
    return {o.order_id: o.total_cents for o in orders}


def sample_orders():
    return [Order(1, "Ada Lovelace", 4200), Order(2, "Grace Hopper", 1999)]
PY
cat >tests/test_report.py <<'PY'
import unittest

from app.orders import Order
from app.report import order_totals


class TestOrderTotals(unittest.TestCase):
    def test_totals_are_keyed_by_order_id(self):
        orders = [Order(1, "Ada", 500), Order(2, "Grace", 250)]
        self.assertEqual(order_totals(orders), {1: 500, 2: 250})
PY
cat >README.md <<'MD'
# orders-tool

Order reporting for the finance team.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: orders reporting skeleton"
BASE=$(git rev-parse --short HEAD)

cat >>README.md <<'MD'

## Data

Orders are read from the finance warehouse; amounts are integer cents.
MD
commit "docs: describe the order data"
DOCSHA=$(git rev-parse --short HEAD)

mkdir -p .specs/001-orders-export
printf '001-orders-export\n' >.specs/.current
cat >.specs/001-orders-export/spec.md <<'MD'
# Spec — Orders export

Finance wants the order list as a CSV they can open in a spreadsheet.

## Requirements
- R1: `quote_cell(text)` in `app/csv_escape.py` quotes a cell per RFC 4180 (wrap in double
  quotes and double any inner quote when the cell holds a comma, quote or newline).
- R2: `export_orders(orders)` in `app/export_cmd.py` returns the CSV text: a header row
  `order_id,customer,total_cents` then one row per order, cells quoted with `quote_cell`.

## Acceptance
- A1: a customer named `Smith, John` survives a round trip through a CSV reader.
- A2: the header row is always present, even for no orders.
MD
cat >.specs/001-orders-export/TASKS.md <<TASKS
# Tasks — Orders export
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a cell with a comma, when quote_cell runs, then it is wrapped in quotes | T001 | test_csv_escape |
| B2 (P0) | Given orders, when export_orders runs, then a header and one row per order come back | T002 | test_export_cmd |

## Phase 1 — Export
Goal: finance can export orders as CSV.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [x] T001 RFC 4180 cell quoting (B1) — files: app/csv_escape.py, tests/test_csv_escape.py — verify: \`python3 -m unittest tests.test_csv_escape\` — done: $DOCSHA
- [ ] T002 export_orders (B2) — files: app/export_cmd.py, tests/test_export_cmd.py — verify: \`python3 -m unittest tests.test_export_cmd\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: orders export, approved"
