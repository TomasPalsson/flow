import unittest
from datetime import date, datetime

from inn.desk.window import bookings_in_range
from inn.models import Booking


def at(day, hour=0, minute=0):
    return Booking("g%d-%02d%02d" % (day, hour, minute), datetime(2026, 3, day, hour, minute))


def guests(found):
    return [b.guest for b in found]


class TestBookingsInRangeHidden(unittest.TestCase):
    def test_middle_of_the_range_comes_back_in_the_order_given(self):
        bookings = [at(6, 9), at(2, 9), at(4, 9), at(20, 9)]
        self.assertEqual(guests(bookings_in_range(bookings, "2026-03-01", "2026-03-08")),
                         ["g6-0900", "g2-0900", "g4-0900"])

    def test_check_in_on_start_is_in_at_any_time_of_day(self):
        bookings = [at(3, 0, 0), at(3, 15, 30), at(3, 23, 59)]
        self.assertEqual(len(bookings_in_range(bookings, "2026-03-03", "2026-03-10")), 3)

    def test_check_in_on_end_is_out_at_any_time_of_day(self):
        bookings = [at(10, 0, 0), at(10, 9, 0), at(10, 23, 59)]
        self.assertEqual(bookings_in_range(bookings, "2026-03-03", "2026-03-10"), [])

    def test_last_minute_of_the_day_before_end_is_in(self):
        found = bookings_in_range([at(9, 23, 59)], "2026-03-03", "2026-03-10")
        self.assertEqual(guests(found), ["g9-2359"])

    def test_start_equal_to_end_is_empty(self):
        self.assertEqual(bookings_in_range([at(5, 12)], "2026-03-05", "2026-03-05"), [])

    def test_empty_input_is_empty(self):
        self.assertEqual(bookings_in_range([], "2026-03-01", "2026-03-08"), [])

    def test_range_given_as_dates(self):
        bookings = [at(3, 8), at(10, 8)]
        found = bookings_in_range(bookings, date(2026, 3, 3), date(2026, 3, 10))
        self.assertEqual(guests(found), ["g3-0800"])

    def test_start_after_end_is_empty(self):
        self.assertEqual(bookings_in_range([at(5, 12)], "2026-03-08", "2026-03-01"), [])

    def test_input_list_is_left_alone(self):
        bookings = [at(6, 9), at(2, 9)]
        bookings_in_range(bookings, "2026-03-01", "2026-03-08")
        self.assertEqual(guests(bookings), ["g6-0900", "g2-0900"])


if __name__ == "__main__":
    unittest.main()
