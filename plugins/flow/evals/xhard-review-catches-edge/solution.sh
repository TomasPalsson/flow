#!/usr/bin/env bash
# What a perfect run leaves on disk: the half-open range built through the far
# as_calendar_day helper, a test that pins the end boundary, one commit for T001,
# ticked through flow tick. No gates, no PASS, no Verified:.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

cat >inn/desk/window.py <<'PY'
from inn.support.clock import as_calendar_day


def bookings_in_range(bookings, start, end):
    first, last = as_calendar_day(start), as_calendar_day(end)
    return [b for b in bookings if first <= as_calendar_day(b.checkin) < last]
PY
cat >tests/test_window.py <<'PY'
import unittest
from datetime import datetime

from inn.desk.window import bookings_in_range
from inn.models import Booking


def booking(day, hour=9):
    return Booking("guest-%d" % day, datetime(2026, 3, day, hour, 0))


class TestWindow(unittest.TestCase):
    def test_bookings_inside_the_range_come_back(self):
        bookings = [booking(2), booking(5), booking(12)]
        found = bookings_in_range(bookings, "2026-03-01", "2026-03-08")
        self.assertEqual([b.guest for b in found], ["guest-2", "guest-5"])

    def test_check_in_on_start_is_in(self):
        self.assertEqual(len(bookings_in_range([booking(3, 0)], "2026-03-03", "2026-03-10")), 1)

    def test_check_in_on_end_is_out_at_any_time(self):
        bookings = [booking(10, 0), booking(10, 23)]
        self.assertEqual(bookings_in_range(bookings, "2026-03-03", "2026-03-10"), [])

    def test_start_equal_to_end_is_empty(self):
        self.assertEqual(bookings_in_range([booking(5)], "2026-03-05", "2026-03-05"), [])
PY
python3 -m unittest tests.test_window >/dev/null 2>&1
git add inn/desk/window.py tests/test_window.py
git commit -q -m "feat: bookings_in_range with a half-open date range"

node "$FLOW" tick T001
git add .specs
git commit -q -m "chore: tick T001"
