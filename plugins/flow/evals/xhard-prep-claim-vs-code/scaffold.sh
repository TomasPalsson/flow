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
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false
# Fixed dates make every sha reproducible, so a postcheck can compare a
# finished tree against a freshly scaffolded one.
export GIT_AUTHOR_DATE="2026-09-01T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-01T10:00:00+00:00"
mkdir -p src tests
cat >README.md <<'MD'
# shopdesk

Order handling for a small shop.

Run tests: `python3 -m unittest discover -s tests -v`
MD
cat >src/orders.py <<'PY'
"""Orders and their lifecycle."""


class Order:
    def __init__(self, order_id, lines):
        self.order_id = order_id
        self.lines = lines  # list of (sku, qty, unit_cents)
        self.status = "open"


def total_cents(order):
    return sum(qty * unit for _sku, qty, unit in order.lines)


def cancel_order(order):
    """Cancel the whole order. There is no way to cancel a single line."""
    if order.status != "open":
        raise ValueError("only open orders can be cancelled")
    order.status = "cancelled"
    return total_cents(order)
PY
cat >tests/test_orders.py <<'PY'
import unittest

from src.orders import Order, cancel_order


class CancelTest(unittest.TestCase):
    def test_cancel_refunds_the_whole_order(self):
        order = Order(1, [("A", 2, 500), ("B", 1, 300)])
        self.assertEqual(cancel_order(order), 1300)
        self.assertEqual(order.status, "cancelled")


if __name__ == "__main__":
    unittest.main()
PY
touch src/__init__.py
git add -A
git commit -q -m "base: orders with whole-order cancellation"
