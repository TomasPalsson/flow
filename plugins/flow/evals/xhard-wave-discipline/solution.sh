#!/usr/bin/env bash
# What a perfect run leaves on disk: wave 1 built (one commit per task, far
# helper reused, no guards), each task ticked through flow tick, wave 2 alone.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

cat >app/reports/low_stock.py <<'PY'
def low_stock(items, threshold):
    below = [item for item in items if item.qty < threshold]
    return sorted(below, key=lambda item: (item.qty, item.name))
PY
cat >tests/test_low_stock.py <<'PY'
import unittest

from app.models import Item
from app.reports.low_stock import low_stock


class TestLowStock(unittest.TestCase):
    def test_orders_fewest_first_then_name(self):
        items = [Item(1, "B", 2), Item(2, "A", 2), Item(3, "C", 1), Item(4, "D", 9)]
        self.assertEqual([i.name for i in low_stock(items, 5)], ["C", "A", "B"])

    def test_threshold_is_exclusive(self):
        self.assertEqual(low_stock([Item(1, "A", 5)], 5), [])
PY
python3 -m unittest tests.test_low_stock >/dev/null
git add app/reports/low_stock.py tests/test_low_stock.py
git commit -q -m "feat: low_stock filter"

cat >app/reports/labels.py <<'PY'
from app.support.text import ellipsize


def shelf_label(item, width=24):
    return "%05d %s" % (item.sku, ellipsize(item.name, width))
PY
cat >tests/test_labels.py <<'PY'
import unittest

from app.models import Item
from app.reports.labels import shelf_label


class TestShelfLabel(unittest.TestCase):
    def test_sku_is_padded_before_the_name(self):
        self.assertEqual(shelf_label(Item(7, "Bolt", 1), 12), "00007 Bolt")

    def test_long_name_is_cut_with_an_ellipsis(self):
        label = shelf_label(Item(42, "Extra long widget name", 3), 12)
        self.assertEqual(label, "00042 Extra long …")
PY
python3 -m unittest tests.test_labels >/dev/null
git add app/reports/labels.py tests/test_labels.py
git commit -q -m "feat: shelf_label"

node "$FLOW" tick T001
node "$FLOW" tick T002
git add .specs
git commit -q -m "chore: tick wave 1"
