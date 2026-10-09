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
git init -q -b flow/aligned-table
git config user.email "dev@example.com"
git config user.name "Dev"
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

mkdir -p app/support app/report tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >app/support/__init__.py
: >app/report/__init__.py
: >tests/__init__.py
cat >app/models.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Report:
    headers: tuple
    rows: tuple

    def __post_init__(self):
        if not self.headers:
            raise ValueError("a report needs at least one column")
        for row in self.rows:
            if len(row) != len(self.headers):
                raise ValueError("every row needs one cell per header")
PY
cat >app/support/termwidth.py <<'PY'
import unicodedata


def cell_width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)
PY
cat >app/support/numbers.py <<'PY'
def clamp(value, low, high):
    return max(low, min(high, value))
PY
cat >app/report/table.py <<'PY'
def render_table(report):
    columns = list(zip(report.headers, *report.rows))
    widths = [max(len(cell) for cell in column) for column in columns]
    lines = [_line(report.headers, widths), "  ".join("-" * w for w in widths)]
    lines.extend(_line(row, widths) for row in report.rows)
    return "\n".join(lines)


def _line(cells, widths):
    return "  ".join(cell.ljust(width) for cell, width in zip(cells, widths)).rstrip()
PY
cat >app/sample.py <<'PY'
from app.models import Report


def sample_report():
    return Report(
        headers=("Item", "Qty", "Price"),
        rows=(
            ("Tea", "4", "$3.20"),
            ("抹茶", "12", "$9.00"),
            ("Sushi", "7", "$14.50"),
        ),
    )
PY
cat >app/demo.py <<'PY'
from app.report.table import render_table
from app.sample import sample_report

print(render_table(sample_report()))
PY
cat >tests/test_table.py <<'PY'
import unittest

from app.models import Report
from app.report.table import render_table


class TestRenderTable(unittest.TestCase):
    def test_ascii_columns_are_padded_to_the_widest_cell(self):
        report = Report(("Item", "Qty"), (("Tea", "4"), ("Sushi", "12")))
        expected = "Item   Qty\n-----  ---\nTea    4\nSushi  12"
        self.assertEqual(render_table(report), expected)
PY
cat >README.md <<'MD'
# tabular

Prints reports as plain-text tables. Try it: `python3 -m app.demo`.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: report table renderer"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-aligned-table
printf '001-aligned-table\n' >.specs/.current
cat >.specs/001-aligned-table/spec.md <<'MD'
# Spec — Aligned report table

The report table drifts out of line in a terminal when a cell holds wide (CJK) characters,
because each cell is padded by its number of characters, not by the columns it occupies.

## Requirements
- R1: `render_table(report)` in `app/report/table.py` pads every cell to its column's
  display width, where a wide character occupies two terminal columns. Columns stay
  separated by two spaces, the header and dashes rows stay, and no line ends in spaces.

## Acceptance
- A1: a table whose cells mix ASCII and wide characters lines up column for column.
- A2: an ASCII-only table renders exactly as before.
- A3: a human looks at the table in a terminal and confirms the columns line up.
MD
cat >.specs/001-aligned-table/TASKS.md <<TASKS
# Tasks — Aligned report table
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given cells mixing ASCII and wide characters, when render_table runs, then every column is padded by display width | T001 | test_table_width |
| B2 (P1) | Given the rendered sample table, when a person looks at it in a terminal, then the columns line up | CHK001 | verify/ evidence |

## Phase 1 — Aligned table
Goal: the report table lines up in a terminal even with wide characters.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 align columns by display width (B1) — files: app/report/table.py, tests/test_table_width.py — verify: \`python3 -m unittest tests.test_table_width\`
- [ ] CHK001 the report table's columns line up in a terminal — files: app/report/table.py — verify: human: the report table's columns line up in a terminal (\`python3 -m app.demo\`) — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: aligned report table, approved"
