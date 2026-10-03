import unittest
from unittest import mock

from shopkit.labels import total_label
from shopkit.models import LineItem, Order
from shopkit.pricing import order_total_cents, tax_cents


def order(cents, tax_bp, qty=1):
    return Order((LineItem("Thing", cents, qty),), tax_bp=tax_bp)


class TestTotalLabel(unittest.TestCase):
    def test_spec_examples(self):
        self.assertEqual(total_label(order(1050, 500)), "Total: $11.03 (incl. tax $0.53)")
        self.assertEqual(total_label(order(1000, 0)), "Total: $10.00 (incl. tax $0.00)")

    def test_large_and_multi_quantity_orders(self):
        self.assertEqual(total_label(order(123456, 0)), "Total: $1234.56 (incl. tax $0.00)")
        self.assertEqual(total_label(order(199, 825, qty=3)), "Total: $6.46 (incl. tax $0.49)")

    def test_label_agrees_with_pricing_for_many_orders(self):
        for cents in (10, 30, 50, 70, 250, 999, 1050, 4321):
            for tax_bp in (0, 250, 500, 825, 1000):
                with self.subTest(cents=cents, tax_bp=tax_bp):
                    o = order(cents, tax_bp)
                    want = "Total: $%d.%02d (incl. tax $%d.%02d)" % (
                        order_total_cents(o) // 100, order_total_cents(o) % 100,
                        tax_cents(o) // 100, tax_cents(o) % 100)
                    self.assertEqual(total_label(o), want)


class TestReusesUsdHelper(unittest.TestCase):
    def test_label_goes_through_usd(self):
        with mock.patch("shopkit.labels.usd", side_effect=lambda cents: "<%d>" % cents):
            self.assertEqual(total_label(order(1050, 500)), "Total: <1103> (incl. tax <53>)")


class TestTaxRoundsHalfUp(unittest.TestCase):
    def test_every_half_cent_goes_up(self):
        cases = {(10, 500): 1, (30, 500): 2, (50, 500): 3, (70, 500): 4, (1050, 500): 53, (450, 500): 23}
        for (cents, tax_bp), want in cases.items():
            with self.subTest(cents=cents, tax_bp=tax_bp):
                self.assertEqual(tax_cents(order(cents, tax_bp)), want)

    def test_exact_amounts_are_unchanged(self):
        self.assertEqual(tax_cents(order(1000, 1000)), 100)
        self.assertEqual(tax_cents(order(1000, 0)), 0)
        self.assertEqual(tax_cents(order(9, 500)), 0)


class TestModelsStillValidate(unittest.TestCase):
    def test_bad_input_is_still_rejected_at_construction(self):
        with self.assertRaises(ValueError):
            LineItem("Thing", 100, 0)
        with self.assertRaises(ValueError):
            Order((), 0)


if __name__ == "__main__":
    unittest.main()
