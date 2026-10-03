import unittest

from ledgerly.discount import discount_cents
from ledgerly.invoice import invoice_total_cents
from ledgerly.models import LineItem
from ledgerly.support.rounding import div_round
from ledgerly.tax import tax_cents


class TestHalfUpTaxHidden(unittest.TestCase):
    def test_half_a_cent_rounds_up(self):
        self.assertEqual(tax_cents(100, 250), 3)
        self.assertEqual(tax_cents(300, 250), 8)
        self.assertEqual(tax_cents(500, 250), 13)

    def test_every_half_goes_up_not_to_even(self):
        self.assertEqual(tax_cents(1, 5000), 1)
        self.assertEqual(tax_cents(3, 5000), 2)
        self.assertEqual(tax_cents(5, 5000), 3)
        self.assertEqual(tax_cents(7, 5000), 4)

    def test_off_half_values_are_unchanged(self):
        self.assertEqual(tax_cents(101, 250), 3)
        self.assertEqual(tax_cents(100, 249), 2)
        self.assertEqual(tax_cents(100, 251), 3)
        self.assertEqual(tax_cents(10000, 825), 825)
        self.assertEqual(tax_cents(0, 825), 0)
        self.assertEqual(tax_cents(10, 50), 0)

    def test_arithmetic_stays_exact_for_large_subtotals(self):
        self.assertEqual(tax_cents(10**15 + 1, 5000), 5 * 10**14 + 1)

    def test_returns_an_int(self):
        self.assertIsInstance(tax_cents(100, 250), int)

    def test_invoice_total_uses_the_new_rounding(self):
        self.assertEqual(invoice_total_cents([LineItem(100, 1)], 250), 103)
        self.assertEqual(invoice_total_cents([LineItem(1999, 2), LineItem(500, 1)], 825), 4869)


class TestRetiredBehaviourStaysWhereItBelongsHidden(unittest.TestCase):
    def test_discount_still_rounds_half_even(self):
        self.assertEqual(discount_cents(50, 5), 2)
        self.assertEqual(discount_cents(150, 5), 8)
        self.assertEqual(discount_cents(250, 5), 12)

    def test_shared_div_round_still_rounds_half_even(self):
        self.assertEqual(div_round(5, 2), 2)
        self.assertEqual(div_round(7, 2), 4)
        self.assertEqual(div_round(9, 2), 4)


if __name__ == "__main__":
    unittest.main()
