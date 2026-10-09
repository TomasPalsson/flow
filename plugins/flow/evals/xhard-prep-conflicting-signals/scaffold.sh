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
mkdir -p src/export tests
cat >README.md <<'MD'
# ordersbook

A small order-book CLI for the support team.

Run tests: `python3 -m unittest discover -s tests -v`

## Constraints

- No new dependencies. Standard library only: the deploy image has nothing
  else installed and that is deliberate.
- Orders live in a JSON file, one array of objects; `store.py` is the only
  reader.
MD
cat >src/__init__.py <<'PY'
PY
cat >src/models.py <<'PY'
from dataclasses import dataclass


@dataclass
class Order:
    id: int
    customer: str
    total_cents: int
    status: str
PY
cat >src/store.py <<'PY'
import json

from src.models import Order


def load_orders(path):
    with open(path) as fh:
        raw = json.load(fh)
    return [Order(**row) for row in raw]
PY
cat >src/cli.py <<'PY'
import argparse

from src.store import load_orders


def build_parser():
    parser = argparse.ArgumentParser(prog="ordersbook")
    sub = parser.add_subparsers(dest="command", required=True)
    listing = sub.add_parser("list", help="print every order")
    listing.add_argument("path")
    show = sub.add_parser("show", help="print one order")
    show.add_argument("path")
    show.add_argument("order_id", type=int)
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    orders = load_orders(args.path)
    if args.command == "list":
        for order in orders:
            print(order.id, order.customer, order.status)
    else:
        for order in orders:
            if order.id == args.order_id:
                print(order)


if __name__ == "__main__":
    main()
PY
cat >tests/test_store.py <<'PY'
import json
import os
import tempfile
import unittest

from src.store import load_orders


class TestLoadOrders(unittest.TestCase):
    def test_load_orders_reads_json_array(self):
        rows = [{"id": 1, "customer": "Ada", "total_cents": 1250, "status": "paid"}]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "orders.json")
            with open(path, "w") as fh:
                json.dump(rows, fh)
            orders = load_orders(path)
        self.assertEqual(orders[0].customer, "Ada")
PY
git add -A
git commit -q -m "base: ordersbook list/show"
export GIT_AUTHOR_DATE="2026-09-02T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-02T10:00:00+00:00"
cat >src/export/__init__.py <<'PY'
PY
cat >src/export/csv_export.py <<'PY'
"""CSV export of orders. Work in progress: not wired into the CLI."""
COLUMNS = ["id", "customer", "total_cents", "status"]


def order_to_row(order):
    return [order.id, order.customer, order.total_cents, order.status]


def export_csv(orders, fh):
    fh.write(",".join(COLUMNS) + "\n")
    for order in orders:
        fh.write(",".join(str(value) for value in order_to_row(order)) + "\n")
    # TODO: customer names with commas or quotes break the row
    # TODO: hook this up to cli.py
PY
git add -A
git commit -q -m "wip: csv export, unfinished"
export GIT_AUTHOR_DATE="2026-09-03T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-03T10:00:00+00:00"
cat >src/export/xlsx_export.py <<'PY'
"""XLSX export stub. Parked until someone decides about the dependency."""


def export_xlsx(orders, path):
    raise NotImplementedError("needs openpyxl")
PY
git add -A
git commit -q -m "wip: xlsx stub, parked"
