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
git init -q -b flow/cell-formats
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare TASKS.md byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p cells/support cells/report cells/fmt tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >cells/__init__.py
: >cells/support/__init__.py
: >cells/report/__init__.py
: >cells/fmt/__init__.py
: >tests/__init__.py
cat >cells/support/layout.py <<'PY'
def fit_right(text, width):
    if len(text) > width:
        return "…" + text[len(text) - width + 1:]
    return text.rjust(width)
PY
cat >cells/support/numbers.py <<'PY'
def clamp(value, low, high):
    return max(low, min(high, value))
PY
cat >cells/support/text.py <<'PY'
def squash_spaces(text):
    return " ".join(text.split())
PY
cat >cells/report/table.py <<'PY'
from cells.support.layout import fit_right


def render_row(cells, width):
    return " | ".join(fit_right(str(cell), width) for cell in cells)
PY
cat >cells/fmt/row.py <<'PY'
def format_row(record):
    raise NotImplementedError("the row is built in wave 2")
PY
cat >cells/cli.py <<'PY'
import sys

from cells.report.table import render_row


def main(argv=None):
    sys.stdout.write(render_row(["name", "total"], 8) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
cat >tests/test_layout.py <<'PY'
import unittest

from cells.support.layout import fit_right


class TestFitRight(unittest.TestCase):
    def test_short_text_is_padded_on_the_left(self):
        self.assertEqual(fit_right("ab", 5), "   ab")
PY
cat >tests/test_table.py <<'PY'
import unittest

from cells.report.table import render_row


class TestTable(unittest.TestCase):
    def test_cells_are_joined_with_a_bar(self):
        self.assertEqual(render_row(["a", "bb"], 3), "  a |  bb")
PY
cat >README.md <<'MD'
# cells

Fixed-width report cells for the finance dashboard.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: cells skeleton with the table report"
BASE=$(git rev-parse --short HEAD)

D=.specs/001-cell-formats
mkdir -p "$D"
printf '001-cell-formats\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Cell formats

**Created**: 2026-09-20 · **Route**: bounded

## TL;DR

**Problem**: The dashboard prints raw numbers; finance wants money, percentages, durations and file sizes formatted the way the printed report does.

**Solution**: Four cell formatters and one row builder that joins them.

**Who it's for**: The finance team reading the dashboard.

## Non-goals

- No locale support, no currencies other than dollars, no colour.

## Requirements

- R0: Every formatter returns a fixed-width cell: right-aligned, and when the text is wider than the cell it is cut on the left and marked with a leading ellipsis, exactly as the table report already prints its cells.
- R1: `format_money(cents, width=12)` in `cells/fmt/money.py`: `$`, dollars grouped by thousands, a dot, two digits of cents. A negative amount is `-$12,340.50`.
- R2: `format_percent(ratio, width=8)` in `cells/fmt/percent.py`: the ratio as a percentage with one decimal, `0.125` is `12.5%`.
- R3: `format_duration(seconds, width=10)` in `cells/fmt/duration.py`: under a minute `45s`; under an hour `12m 05s`; from an hour up `1h 05m` (the seconds are dropped). Minutes and seconds after the first unit are two digits.
- R4: `format_size(size_bytes, width=10)` in `cells/fmt/filesize.py`: under 1024 it is `512 B`; from there one decimal in units of 1024: `1.5 KB`, `1.0 MB`, `5.0 GB` (GB is the largest unit).
- R5: `format_row(record)` in `cells/fmt/row.py` joins the four cells of a record (`amount_cents`, `share`, `elapsed_s`, `size_bytes`) with ` | `, each at its default width.

## Launch criteria

- [ ] A1: `format_money(123456)` is `$1,234.56` right-aligned in 12 columns; `-5` cents is `-$0.05`.
- [ ] A2: `format_percent(0.125)` is `12.5%`; `1` is `100.0%`.
- [ ] A3: 45 s is `45s`, 725 s is `12m 05s`, 3900 s is `1h 05m`.
- [ ] A4: 512 bytes is `512 B`, 1536 is `1.5 KB`.
- [ ] A5: a cell wider than its width is cut on the left with a leading ellipsis, in every formatter.
- [ ] A6: `format_row` joins the four default-width cells with ` | `.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Cell formats
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-21 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given cents, when format_money runs, then a grouped dollar amount fits the cell | T001 | test_money |
| B2 (P0) | Given a ratio, when format_percent runs, then one-decimal percent fits the cell | T002 | test_percent |
| B3 (P0) | Given seconds, when format_duration runs, then the two-unit duration fits the cell | T003 | test_duration |
| B4 (P0) | Given bytes, when format_size runs, then the 1024-based size fits the cell | T004 | test_filesize |
| B5 (P1) | Given a record, when format_row runs, then the four cells are joined with a bar | T005 | test_row |

## Phase 1 — Cells
Goal: finance sees money, shares, durations and sizes as report-ready cells, and a whole record as one row.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 [P] Money cell (B1) — files: cells/fmt/money.py, tests/test_money.py — verify: \`python3 -m unittest tests.test_money\`
- [ ] T002 [P] Percent cell (B2) — files: cells/fmt/percent.py, tests/test_percent.py — verify: \`python3 -m unittest tests.test_percent\`
- [ ] T003 [P] Duration cell (B3) — files: cells/fmt/duration.py, tests/test_duration.py — verify: \`python3 -m unittest tests.test_duration\`
- [ ] T004 [P] File size cell (B4) — files: cells/fmt/filesize.py, tests/test_filesize.py — verify: \`python3 -m unittest tests.test_filesize\`
- [ ] T005 Record row (B5) — files: cells/fmt/row.py, tests/test_row.py — verify: \`python3 -m unittest tests.test_row\` — after: T001, T002, T003, T004

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
commit "plan: cell formats, approved"
