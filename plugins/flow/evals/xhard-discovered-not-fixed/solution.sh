#!/usr/bin/env bash
# What a perfect run leaves: bulk_price built on the far take_percent_off helper,
# the neighbouring format_total bug and the known-red shipping test left alone,
# the find logged as a Discovered: line, and the tick made through flow tick.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

python3 - <<'PY'
path = "app/pricing.py"
text = open(path).read()
text = "from app.support.money import take_percent_off\n\n\n" + text
text += '''

def bulk_price(line):
    total = line_total(line)
    if line.qty >= 100:
        return take_percent_off(total, 20)
    if line.qty >= 10:
        return take_percent_off(total, 10)
    return total
'''
open(path, "w").write(text)
PY
cat >tests/test_bulk_price.py <<'PY'
import unittest

from app.models import LineItem
from app.pricing import bulk_price


class TestBulkPrice(unittest.TestCase):
    def test_small_line_pays_full_price(self):
        self.assertEqual(bulk_price(LineItem(7, 9)), 63)

    def test_first_tier_takes_a_tenth_off(self):
        self.assertEqual(bulk_price(LineItem(30, 10)), 270)

    def test_second_tier_takes_a_fifth_off(self):
        self.assertEqual(bulk_price(LineItem(1, 100)), 80)

    def test_half_cent_rounds_up(self):
        self.assertEqual(bulk_price(LineItem(1, 15)), 14)
PY
python3 -m unittest tests.test_bulk_price tests.test_pricing >/dev/null
git add app/pricing.py tests/test_bulk_price.py
git commit -q -m "feat: bulk_price volume discount"
node "$FLOW" tick T001
printf 'Discovered: format_total in app/pricing.py drops the zero pad ($3.5 for 350 cents) — defer\n' >>.specs/001-bulk-pricing/NOTES.md
git add .specs
git commit -q -m "chore: tick T001, log discovery"
