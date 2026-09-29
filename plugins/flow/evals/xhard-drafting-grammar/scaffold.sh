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
# Fixed dates make every sha reproducible, so a postcheck can compare a
# finished tree against a freshly scaffolded one.
export GIT_AUTHOR_DATE="2026-09-01T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-01T10:00:00+00:00"
mkdir -p src tests
cat >README.md <<'MD'
# stockroom

Inventory CLI for the warehouse team.

Run tests: `python3 -m unittest discover -s tests -v`

Items live in a JSON array (`STOCKROOM_DATA`, default `items.json`); `store.py`
is the only reader.
MD
cat >src/__init__.py <<'PY'
PY
cat >src/models.py <<'PY'
from dataclasses import dataclass


@dataclass
class Item:
    sku: str
    name: str
    qty: int
PY
cat >src/config.py <<'PY'
import os


def data_path(env=None):
    env = os.environ if env is None else env
    return env.get("STOCKROOM_DATA", "items.json")
PY
cat >src/store.py <<'PY'
import json

from src.models import Item


def load_items(path):
    with open(path) as fh:
        raw = json.load(fh)
    return [Item(**row) for row in raw]
PY
cat >src/format.py <<'PY'
def render_table(headers, rows):
    cells = [list(map(str, headers))] + [list(map(str, row)) for row in rows]
    widths = [max(len(row[i]) for row in cells) for i in range(len(headers))]
    lines = []
    for row in cells:
        lines.append("  ".join(cell.ljust(width) for cell, width in zip(row, widths)).rstrip())
    return "\n".join(lines)
PY
cat >src/reports.py <<'PY'
def stock_summary(items):
    total = sum(item.qty for item in items)
    return {"skus": len(items), "units": total}
PY
cat >src/cli.py <<'PY'
import argparse

from src.config import data_path
from src.format import render_table
from src.reports import stock_summary
from src.store import load_items


def build_parser():
    parser = argparse.ArgumentParser(prog="stockroom")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list", help="print every item")
    sub.add_parser("summary", help="print totals")
    return parser


def main(argv=None):
    args = build_parser().parse_args(argv)
    items = load_items(data_path())
    if args.command == "list":
        print(render_table(["sku", "name", "qty"], [[i.sku, i.name, i.qty] for i in items]))
    else:
        summary = stock_summary(items)
        print("%d skus, %d units" % (summary["skus"], summary["units"]))


if __name__ == "__main__":
    main()
PY
cat >tests/__init__.py <<'PY'
PY
cat >tests/test_reports.py <<'PY'
import unittest

from src.models import Item
from src.reports import stock_summary


class TestStockSummary(unittest.TestCase):
    def test_counts_skus_and_units(self):
        items = [Item("A1", "bolt", 3), Item("B2", "nut", 4)]
        self.assertEqual(stock_summary(items), {"skus": 2, "units": 7})
PY
cat >tests/test_config.py <<'PY'
import unittest

from src.config import data_path


class TestDataPath(unittest.TestCase):
    def test_default_and_override(self):
        self.assertEqual(data_path({}), "items.json")
        self.assertEqual(data_path({"STOCKROOM_DATA": "x.json"}), "x.json")
PY
cat >tests/test_cli.py <<'PY'
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from io import StringIO
from unittest import mock

from src.cli import main


class TestCli(unittest.TestCase):
    def test_list_prints_every_item(self):
        rows = [{"sku": "A1", "name": "bolt", "qty": 3}]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "items.json")
            with open(path, "w") as fh:
                json.dump(rows, fh)
            out = StringIO()
            with mock.patch.dict(os.environ, {"STOCKROOM_DATA": path}), redirect_stdout(out):
                main(["list"])
        self.assertIn("bolt", out.getvalue())
PY
git add -A
git commit -q -m "base: stockroom list/summary"
export GIT_AUTHOR_DATE="2026-09-25T10:00:00+00:00" GIT_COMMITTER_DATE="2026-09-25T10:00:00+00:00"
mkdir -p .specs/001-low-stock-report
cat >.specs/001-low-stock-report/spec.md <<'MD'
# Spec: Low-stock report

**Created**: 2026-09-25 · **Route**: dispatch

## TL;DR

**Problem**: The warehouse team finds out an item ran out when a picker walks to an empty shelf.

**Solution**: `stockroom low-stock` prints the items running low, worst first, so the morning reorder takes one look.

**Who it's for**: Warehouse leads who place the daily reorder.

**MVP cut line**: every acceptance criterion in §5 ships.

**Key decision**: "Low" is a plain quantity threshold, not a forecast.

## 1. Context

### 1.1 Problem statement

Reorders are placed from memory and from `stockroom list`, which shows every
item in file order. Nobody scans 400 rows for the short ones.

**Current workaround**: eyeball `stockroom list` for small numbers.

## 2. Scope

### 2.1 In scope

- A low-stock report over the existing item file.
- A configurable threshold.

### 2.2 Non-goals

- No demand forecasting or reorder-point maths.
- No writes: the report never edits the item file.
- No email or notification.

## 5. Acceptance criteria

| ID | Criterion |
|----|-----------|
| AC-1 | `low_stock(items, threshold)` returns the items whose qty is below the threshold, sorted by qty ascending and then by sku. |
| AC-2 | The default threshold is 5. `STOCKROOM_LOW_STOCK` overrides it; a value that is not a whole number is rejected with a `ConfigError` naming the variable. |
| AC-3 | Each reported row carries a status: `OUT` when qty is 0, `LOW` otherwise. |
| AC-4 | `stockroom low-stock [--threshold N]` prints the report with the same table renderer `list` uses; `--threshold` beats the environment. |
| AC-5 | A warehouse lead reads the printed table on an 80-column terminal, with the longest product name in the data, and the columns line up without wrapping. (Needs a human's eyes.) |

## 7. Assumptions

- Quantities are whole numbers, never negative. Confidence: high.
- The item file stays under 10,000 rows. Confidence: medium.
MD
printf '001-low-stock-report\n' >.specs/.current
git add -A
git commit -q -m "spec: low-stock report"
