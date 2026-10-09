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

mkdir -p tally/support tests sample
cat >.gitignore <<'GI'
__pycache__/
*.pyc
GI

# --- commit 1: shared helpers -----------------------------------------------------
cat >tally/__init__.py <<'PY'
PY
cat >tally/support/__init__.py <<'PY'
PY
cat >tally/support/pad.py <<'PY'
def fit(text: str, width: int, align: str = "left") -> str:
    text = text[:width]
    return text.rjust(width) if align == "right" else text.ljust(width)
PY
cat >tally/support/money.py <<'PY'
def dollars(cents: int) -> str:
    return f"${cents / 100:,.2f}"
PY
cat >tests/__init__.py <<'PY'
PY
cat >tests/test_pad.py <<'PY'
import unittest

from tally.support.pad import fit


class TestFit(unittest.TestCase):
    def test_fit_pads_left_aligned_by_default(self):
        self.assertEqual(fit("ab", 4), "ab  ")

    def test_fit_right_aligns_on_request(self):
        self.assertEqual(fit("ab", 4, "right"), "  ab")

    def test_fit_truncates_to_width(self):
        self.assertEqual(fit("abcdef", 3), "abc")
PY
cat >tests/test_money.py <<'PY'
import unittest

from tally.support.money import dollars


class TestDollars(unittest.TestCase):
    def test_dollars_groups_thousands(self):
        self.assertEqual(dollars(140975), "$1,409.75")

    def test_dollars_pads_cents(self):
        self.assertEqual(dollars(450), "$4.50")
PY
cat >pyproject.toml <<'TOML'
[project]
name = "tally"
version = "0.2.0"
dependencies = []
TOML
cat >README.md <<'MD'
# tally

A small expense ledger for the terminal. Expenses live in a CSV file with the
header `date,category,amount_cents`.

- Run tests: `python3 -m unittest discover -s tests -v`
- Try it: `python3 -m tally list --file sample/expenses.csv`
- No new dependencies: the standard library only.
- Layout: `tally/models.py` (validated records), `tally/store.py` (CSV
  loading), `tally/support/` (shared text and money helpers), `tally/cli.py`.
MD
git add -A
git commit -q -m "support: fit and dollars helpers"

# --- commit 2: validated model and CSV store ---------------------------------------
cat >tally/models.py <<'PY'
from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True)
class Expense:
    day: str
    category: str
    amount_cents: int

    def __post_init__(self):
        date.fromisoformat(self.day)
        if not self.category.strip():
            raise ValueError("category must not be blank")
        if not isinstance(self.amount_cents, int) or self.amount_cents <= 0:
            raise ValueError("amount_cents must be a positive integer")
PY
cat >tally/store.py <<'PY'
import csv

from tally.models import Expense


def load_expenses(path):
    with open(path, newline="") as source:
        return [
            Expense(row["date"], row["category"], int(row["amount_cents"]))
            for row in csv.DictReader(source)
        ]
PY
cat >sample/expenses.csv <<'CSV'
date,category,amount_cents
2026-08-03,groceries,4250
2026-08-09,transport,1800
2026-08-15,groceries,12075
2026-09-01,rent,120000
2026-09-02,transport,2400
2026-09-04,coffee,450
CSV
cat >tests/test_models.py <<'PY'
import unittest

from tally.models import Expense


class TestExpense(unittest.TestCase):
    def test_expense_rejects_a_bad_date(self):
        with self.assertRaises(ValueError):
            Expense("2026-13-01", "rent", 100)

    def test_expense_rejects_a_blank_category(self):
        with self.assertRaises(ValueError):
            Expense("2026-08-01", "  ", 100)

    def test_expense_rejects_a_non_positive_amount(self):
        with self.assertRaises(ValueError):
            Expense("2026-08-01", "rent", 0)
PY
cat >tests/test_store.py <<'PY'
import os
import tempfile
import unittest

from tally.store import load_expenses


class TestLoadExpenses(unittest.TestCase):
    def test_load_expenses_reads_every_row(self):
        with tempfile.TemporaryDirectory() as folder:
            path = os.path.join(folder, "e.csv")
            with open(path, "w") as sink:
                sink.write("date,category,amount_cents\n2026-08-03,groceries,4250\n")
            rows = load_expenses(path)
        self.assertEqual([(r.day, r.category, r.amount_cents) for r in rows], [("2026-08-03", "groceries", 4250)])
PY
git add -A
git commit -q -m "models: validated Expense and CSV store"

# --- commit 3: the CLI with the list command ---------------------------------------
cat >tally/cli.py <<'PY'
import argparse
import sys

from tally.store import load_expenses
from tally.support.money import dollars
from tally.support.pad import fit


def render_listing(expenses):
    lines = []
    for expense in expenses:
        amount = fit(dollars(expense.amount_cents), 10, "right")
        lines.append(f"{fit(expense.day, 10)}  {fit(expense.category, 12)}  {amount}")
    return "\n".join(lines)


def main(argv=None, out=None, err=None):
    out = out or sys.stdout
    err = err or sys.stderr
    parser = argparse.ArgumentParser(prog="tally")
    commands = parser.add_subparsers(dest="command", required=True)
    listing = commands.add_parser("list")
    listing.add_argument("--file", required=True)
    args = parser.parse_args(argv)
    if args.command == "list":
        out.write(render_listing(load_expenses(args.file)) + "\n")
    return 0
PY
cat >tally/__main__.py <<'PY'
from tally.cli import main

raise SystemExit(main())
PY
cat >tests/test_cli_list.py <<'PY'
import io
import unittest

from tally.cli import main


class TestListCommand(unittest.TestCase):
    def test_list_prints_one_line_per_expense(self):
        out = io.StringIO()
        self.assertEqual(main(["list", "--file", "sample/expenses.csv"], out), 0)
        lines = out.getvalue().splitlines()
        self.assertEqual(len(lines), 6)
        self.assertEqual(lines[0], "2026-08-03  groceries         $42.50")
PY
git add -A
git commit -q -m "cli: list command"

# --- commit 4: the spec the user already wrote (no TASKS.md yet: drafting) ----------
mkdir -p .specs/001-tally-summary
cat >.specs/001-tally-summary/spec.md <<'MD'
# Spec: Category summary

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

> Read this block. If it answers your question, stop here.

**Problem**: Reading a month of expenses line by line to find where the money went is slow.
**Solution**: `tally summary` prints one row per category with a count and a total, biggest first, plus a TOTAL row.
**Who it's for**: The person who keeps the ledger and reviews it at month end.
**MVP cut line**: everything tagged `MUST` in §4.1 ships.
**Key decision**: The summary is a table in the terminal, reusing the same text and money helpers as `tally list`.

## 1. Context

### 1.1 Problem statement

The ledger holds hundreds of rows. The reviewer adds them up by hand per category.

**Current workaround**: `tally list` piped into a spreadsheet.

### 1.2 Roles

| Role | What they do | Key characteristic |
|------|--------------|--------------------|
| Reviewer | Runs `tally summary` at month end | Reads the table in a terminal |

## 2. Scope

### 2.1 In scope

- A `summary` command: `tally summary --file <csv> [--month YYYY-MM]`.

### 2.2 Non-goals

- No new dependencies, no colour, no CSV or JSON output, no change to `tally list`.
- No currency other than dollars.

## 4. Requirements

### 4.1 Functional requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| AC-01 | MUST | The reviewer MUST get one row per category with its expense count and its total, formatted like `tally list` formats money | test on `sample/expenses.csv` |
| AC-02 | MUST | Rows MUST be sorted by total descending, ties by category name ascending, followed by one `TOTAL` row with the overall count and total | test with a tie |
| AC-03 | MUST | `--month YYYY-MM` MUST keep only that month's expenses. A month that is not exactly `YYYY-MM` with a month between 01 and 12 (for example `2026-13`, `August`, `2026-8` or `2026-08-01`) MUST print `invalid month: <text>` on stderr, print nothing on stdout, and exit 2 | test both paths |
| AC-04 | MUST | With no expenses to summarise (empty file, or a month with none), the command MUST print `No expenses.` and exit 0 | test both cases |
| AC-05 | MUST | The reviewer MUST see the summary table's columns line up in a terminal | a human looks at the rendered table |

### 4.2 Table layout

Columns are `Category` (left-aligned), `Count` (right-aligned), `Total` (right-aligned). Every column is as wide as its widest cell, header and `TOTAL` row included. Columns are separated by two spaces and lines carry no trailing spaces.

For `sample/expenses.csv`:

```
Category   Count      Total
rent           1  $1,200.00
groceries      2    $163.25
transport      2     $42.00
coffee         1      $4.50
TOTAL          6  $1,409.75
```

## 6. Launch criteria

- [ ] Every AC-01..AC-04 has a passing test; AC-05 has evidence a human has seen.
- [ ] `tally list` output is byte-identical to before.

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The month is taken from the expense's ISO date | High | A month filter that matches the wrong rows |
MD
printf '001-tally-summary\n' >.specs/.current
git add .specs/001-tally-summary/spec.md
git commit -q -m "specs: category summary spec"
