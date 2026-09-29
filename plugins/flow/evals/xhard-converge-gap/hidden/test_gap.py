import unittest
from datetime import date, timedelta

from perks.expiry import live_balance
from perks.models import Entry

TODAY = date(2026, 9, 29)


def earned(days_ago, points):
    return Entry(TODAY - timedelta(days=days_ago), points)


class TestLiveBalanceHidden(unittest.TestCase):
    def test_recent_entries_count(self):
        self.assertEqual(live_balance([earned(1, 40), earned(200, 60)], TODAY), 100)

    def test_entry_exactly_365_days_old_still_counts(self):
        self.assertEqual(live_balance([earned(365, 25)], TODAY), 25)

    def test_entry_366_days_old_has_lapsed(self):
        self.assertEqual(live_balance([earned(366, 25), earned(10, 5)], TODAY), 5)

    def test_entry_earned_today_counts(self):
        self.assertEqual(live_balance([earned(0, 7)], TODAY), 7)

    def test_nothing_earned_is_zero(self):
        self.assertEqual(live_balance([], TODAY), 0)

    def test_input_is_left_alone(self):
        entries = [earned(400, 9), earned(3, 1)]
        live_balance(entries, TODAY)
        self.assertEqual(len(entries), 2)


if __name__ == "__main__":
    unittest.main()
