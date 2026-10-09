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
cat >src/money.py <<'PY'
def cents_to_decimal(cents):
    return "%d.%02d" % (cents // 100, cents % 100)
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
cat >tests/__init__.py <<'PY'
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
cat >tests/test_money.py <<'PY'
import unittest

from src.money import cents_to_decimal


class TestCentsToDecimal(unittest.TestCase):
    def test_pads_cents(self):
        self.assertEqual(cents_to_decimal(1205), "12.05")
PY
git add -A
git commit -q -m "base: ordersbook list/show"
export GIT_AUTHOR_DATE="2026-09-20T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-20T10:00:00+00:00"
mkdir -p .specs/001-order-csv-export
cat >.specs/001-order-csv-export/PREP.md <<'MD'
# Prep — Order CSV export
Gathered: 2026-09-20 · Questions: 6 of 12 · Route: dispatch · Status: ready for spec

## Decisions
- D-01 The export is RFC 4180 CSV: comma delimiter, CRLF line endings, a field containing a comma, a double quote or a newline is quoted, and an embedded double quote is doubled. — user, Q1
- D-02 No new dependencies; the standard library only. — user, Q2
- D-03 An export holds at most 10,000 rows. A larger export is refused with a clear error and writes nothing. — user, Q3
- D-04 Columns are id, customer, total, status, in that order, with a header row; total is dollars with two decimals (12.50), not cents. — user, Q4
- D-05 The entry point is `ordersbook export <orders.json> --out <file.csv>`, with an optional `--status <s>` filter. — user, Q5
## Not this
- No streaming or chunked export for more than 10,000 rows: out of scope, the refusal in D-03 is the whole answer.
- No XLSX, JSON or PDF output.
- No scheduled or emailed exports.
## Discretion
- Wording of the refusal message.
- Column header capitalisation.
## Assumptions
- A-01 Support staff open the file in Excel or Numbers — evidence: none — confidence: medium — confirmed Q1
- A-02 Real order files stay well under 2,000 rows today — evidence: none — confidence: low — unconfirmed
- A-03 The existing cents_to_decimal helper renders the total column — evidence: src/money.py:1 — confidence: high — confirmed Q4
## Verify
- Run `ordersbook export sample.json --out out.csv` on a file holding a customer named `Smith, "Bob"` and open out.csv in a spreadsheet: one row, one cell for the name; `python3 -m unittest discover -s tests` is green.
## Open
- Q: should an empty result still write a header-only file? → deferred to spec
MD
printf '001-order-csv-export\n' >.specs/.current
git add -A
git commit -q -m "prep: order csv export"
