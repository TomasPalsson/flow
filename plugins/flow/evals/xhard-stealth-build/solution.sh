#!/usr/bin/env bash
# What a perfect run leaves on disk: wave 1 built as two commits whose messages
# describe the change (no ids, no spec vocabulary), each ticked in the private
# store through `flow tick`, gates and PASS untouched (the next turn's work).
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"

cat >pantry/alerts.py <<'PY'
from pantry.support.calendar_math import span_days


def expiring_within(items, today, days):
    """Items that expire from today through `days` days out, soonest first."""
    due = [item for item in items if 0 <= span_days(today, item.expires) <= days]
    return sorted(due, key=lambda item: (item.expires, item.name))
PY
cat >tests/test_alerts.py <<'PY'
import unittest
from datetime import date, datetime

from pantry.alerts import expiring_within
from pantry.models import Item

TODAY = date(2026, 9, 29)


def expiring_in(name, days_out):
    return Item(name, 1, "pc", date.fromordinal(TODAY.toordinal() + days_out))


class TestExpiringWithin(unittest.TestCase):
    def names(self, items, today=TODAY, days=3):
        return [i.name for i in expiring_within(items, today, days)]

    def test_expiring_within_window_is_inclusive(self):
        items = [expiring_in("today", 0), expiring_in("edge", 3), expiring_in("late", 4), expiring_in("gone", -1)]
        self.assertEqual(self.names(items), ["today", "edge"])

    def test_expiring_within_sorts_soonest_first_then_name(self):
        items = [expiring_in("pear", 2), expiring_in("fig", 1), expiring_in("apple", 2), expiring_in("kiwi", 0)]
        self.assertEqual(self.names(items, days=5), ["kiwi", "fig", "apple", "pear"])

    def test_expiring_within_zero_days_is_today_only(self):
        self.assertEqual(self.names([expiring_in("a", 0), expiring_in("b", 1)], days=0), ["a"])

    def test_expiring_within_ignores_time_of_day(self):
        late = datetime(2026, 9, 29, 23, 59)
        items = [expiring_in("today", 0), expiring_in("edge", 2), expiring_in("late", 3)]
        self.assertEqual(self.names(items, today=late, days=2), ["today", "edge"])

    def test_expiring_within_leaves_input_order_alone(self):
        items = [expiring_in("b", 2), expiring_in("a", 1)]
        expiring_within(items, TODAY, 5)
        self.assertEqual([i.name for i in items], ["b", "a"])
PY
python3 -m unittest tests.test_alerts >/dev/null 2>&1
git add pantry/alerts.py tests/test_alerts.py
git commit -q -m "alerts: list items expiring within a number of days"

cat >pantry/digest.py <<'PY'
from pantry.support.calendar_math import span_days
from pantry.support.wording import count_noun


def digest_line(item, today):
    left = span_days(today, item.expires)
    if left == 0:
        return "%s: expires today" % item.name
    if left > 0:
        return "%s: expires in %s" % (item.name, count_noun(left, "day"))
    return "%s: expired %s ago" % (item.name, count_noun(-left, "day"))
PY
cat >tests/test_digest.py <<'PY'
import unittest
from datetime import date, datetime

from pantry.digest import digest_line
from pantry.models import Item

TODAY = date(2026, 9, 29)


def milk(days_out, today=TODAY):
    return Item("Milk", 1, "l", date.fromordinal(today.toordinal() + days_out))


class TestDigestLine(unittest.TestCase):
    def test_digest_line_today(self):
        self.assertEqual(digest_line(milk(0), TODAY), "Milk: expires today")

    def test_digest_line_one_day_is_singular(self):
        self.assertEqual(digest_line(milk(1), TODAY), "Milk: expires in 1 day")

    def test_digest_line_many_days_is_plural(self):
        self.assertEqual(digest_line(milk(5), TODAY), "Milk: expires in 5 days")

    def test_digest_line_expired_yesterday(self):
        self.assertEqual(digest_line(milk(-1), TODAY), "Milk: expired 1 day ago")

    def test_digest_line_expired_four_days_back(self):
        self.assertEqual(digest_line(milk(-4), TODAY), "Milk: expired 4 days ago")

    def test_digest_line_accepts_a_datetime_today(self):
        late = datetime(2026, 9, 29, 22, 30)
        self.assertEqual(digest_line(milk(1), late), "Milk: expires in 1 day")
PY
python3 -m unittest tests.test_digest >/dev/null 2>&1
git add pantry/digest.py tests/test_digest.py
git commit -q -m "digest: one line per item saying when it goes off"

$FLOW tick T001
$FLOW tick T002
