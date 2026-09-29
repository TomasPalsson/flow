import unittest

from cartcalc.cart import total_cents
from cartcalc.lines import Line
from cartcalc.pricing import discount_cents


class TestHalfCentsRoundUp(unittest.TestCase):
    def test_every_half_cent_goes_up(self):
        cases = {(10, 5): 1, (30, 5): 2, (50, 5): 3, (70, 5): 4, (250, 5): 13, (450, 5): 23}
        for (subtotal, percent), want in cases.items():
            with self.subTest(subtotal=subtotal, percent=percent):
                self.assertEqual(discount_cents(subtotal, percent), want)

    def test_exact_and_sub_half_cases_are_unchanged(self):
        self.assertEqual(discount_cents(1000, 10), 100)
        self.assertEqual(discount_cents(0, 25), 0)
        self.assertEqual(discount_cents(9, 5), 0)
        self.assertEqual(discount_cents(999, 100), 999)

    def test_cart_total_uses_the_rounded_discount(self):
        self.assertEqual(total_cents([Line("cap", 250)], 5), 237)
        self.assertEqual(total_cents([Line("cap", 50)], 5), 47)


if __name__ == "__main__":
    unittest.main()
