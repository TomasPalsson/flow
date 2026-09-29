import unittest
from datetime import date, datetime

from pantry.alerts import expiring_within
from pantry.digest import digest_line
from pantry.models import Item

TODAY = date(2026, 9, 29)


def item(name, days_out, today=TODAY):
    return Item(name, 1, "pc", date.fromordinal(today.toordinal() + days_out))


class TestExpiringWithin(unittest.TestCase):
    def test_window_is_inclusive_at_both_ends(self):
        items = [item("today", 0), item("edge", 3), item("late", 4), item("gone", -1)]
        got = [i.name for i in expiring_within(items, TODAY, 3)]
        self.assertEqual(got, ["today", "edge"])

    def test_soonest_first_then_by_name(self):
        items = [item("pear", 2), item("fig", 1), item("apple", 2), item("kiwi", 0)]
        got = [i.name for i in expiring_within(items, TODAY, 5)]
        self.assertEqual(got, ["kiwi", "fig", "apple", "pear"])

    def test_zero_days_keeps_only_today(self):
        items = [item("a", 0), item("b", 1)]
        self.assertEqual([i.name for i in expiring_within(items, TODAY, 0)], ["a"])

    def test_datetime_today_counts_calendar_days(self):
        late = datetime(2026, 9, 29, 23, 59)
        items = [item("today", 0), item("edge", 2), item("late", 3)]
        got = [i.name for i in expiring_within(items, late, 2)]
        self.assertEqual(got, ["today", "edge"])

    def test_nothing_in_nothing_out(self):
        self.assertEqual(list(expiring_within([], TODAY, 7)), [])

    def test_input_is_not_reordered(self):
        items = [item("b", 2), item("a", 1)]
        expiring_within(items, TODAY, 5)
        self.assertEqual([i.name for i in items], ["b", "a"])


class TestDigestLine(unittest.TestCase):
    def test_today(self):
        self.assertEqual(digest_line(item("Milk", 0), TODAY), "Milk: expires today")

    def test_one_day(self):
        self.assertEqual(digest_line(item("Milk", 1), TODAY), "Milk: expires in 1 day")

    def test_many_days(self):
        self.assertEqual(digest_line(item("Milk", 5), TODAY), "Milk: expires in 5 days")

    def test_expired_one_day(self):
        self.assertEqual(digest_line(item("Milk", -1), TODAY), "Milk: expired 1 day ago")

    def test_expired_many_days(self):
        self.assertEqual(digest_line(item("Milk", -4), TODAY), "Milk: expired 4 days ago")

    def test_datetime_today(self):
        late = datetime(2026, 9, 29, 22, 30)
        self.assertEqual(digest_line(item("Rice", 1), late), "Rice: expires in 1 day")
        self.assertEqual(digest_line(item("Rice", 0), late), "Rice: expires today")


if __name__ == "__main__":
    unittest.main()
