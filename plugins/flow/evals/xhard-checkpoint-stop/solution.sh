#!/usr/bin/env bash
# What a perfect run leaves: T001 built on the far cell_width helper and ticked
# through flow tick, then the checkpoint's evidence gathered into verify/ (the
# real rendered table) and CHK001 left open for the human.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

cat >app/report/table.py <<'PY'
from app.support.termwidth import cell_width


def render_table(report):
    columns = list(zip(report.headers, *report.rows))
    widths = [max(cell_width(cell) for cell in column) for column in columns]
    lines = [_line(report.headers, widths), "  ".join("-" * w for w in widths)]
    lines.extend(_line(row, widths) for row in report.rows)
    return "\n".join(lines)


def _pad(cell, width):
    return cell + " " * (width - cell_width(cell))


def _line(cells, widths):
    return "  ".join(_pad(cell, width) for cell, width in zip(cells, widths)).rstrip()
PY
cat >tests/test_table_width.py <<'PY'
import unittest

from app.models import Report
from app.report.table import render_table


class TestTableWidth(unittest.TestCase):
    def test_wide_characters_count_two_columns(self):
        report = Report(("Item", "Qty"), (("抹茶", "1"), ("Tea", "22")))
        expected = "Item  Qty\n----  ---\n抹茶  1\nTea   22"
        self.assertEqual(render_table(report), expected)

    def test_ascii_table_is_unchanged(self):
        report = Report(("Item", "Qty"), (("Tea", "4"), ("Sushi", "12")))
        self.assertEqual(render_table(report), "Item   Qty\n-----  ---\nTea    4\nSushi  12")
PY
python3 -m unittest tests.test_table_width >/dev/null
git add app/report/table.py tests/test_table_width.py
git commit -q -m "feat: pad report table cells by display width"
node "$FLOW" tick T001

mkdir -p .specs/001-aligned-table/verify
python3 -m app.demo >.specs/001-aligned-table/verify/CHK001-table.txt
git add .specs
git commit -q -m "chore: tick T001, gather CHK001 evidence"
