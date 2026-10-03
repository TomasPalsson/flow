import unittest

from app.models import LineItem
from app.pricing import bulk_price


class TestBulkPriceHidden(unittest.TestCase):
    def test_below_ten_units_pay_full_price(self):
        self.assertEqual(bulk_price(LineItem(7, 9)), 63)

    def test_ten_units_get_ten_percent_off(self):
        self.assertEqual(bulk_price(LineItem(30, 10)), 270)

    def test_ninety_nine_units_are_still_the_ten_percent_tier(self):
        self.assertEqual(bulk_price(LineItem(2, 99)), 178)

    def test_hundred_units_get_twenty_percent_off(self):
        self.assertEqual(bulk_price(LineItem(1, 100)), 80)
        self.assertEqual(bulk_price(LineItem(100, 100)), 8000)

    def test_discounted_total_rounds_half_up(self):
        self.assertEqual(bulk_price(LineItem(1, 15)), 14)

    def test_returns_whole_cents(self):
        self.assertIsInstance(bulk_price(LineItem(3, 33)), int)


if __name__ == "__main__":
    unittest.main()
