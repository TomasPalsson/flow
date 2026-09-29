import unittest

from parcelly.parcel import Parcel
from parcelly.rates import quote_cents
from parcelly.tiers import tier_for


class TestInclusiveUpperBounds(unittest.TestCase):
    def test_tier_edges(self):
        cases = {1: "light", 999: "light", 1000: "light", 1001: "medium",
                 4999: "medium", 5000: "medium", 5001: "heavy", 20000: "heavy"}
        for grams, want in cases.items():
            with self.subTest(grams=grams):
                self.assertEqual(tier_for(grams), want)

    def test_quotes_at_both_edges(self):
        self.assertEqual(quote_cents(Parcel(1000, "national")), 600)
        self.assertEqual(quote_cents(Parcel(5000, "remote")), 1150)
        self.assertEqual(quote_cents(Parcel(5001, "local")), 1500)

    def test_parcel_still_validates_itself(self):
        with self.assertRaises(ValueError):
            Parcel(0)
        with self.assertRaises(ValueError):
            Parcel(100, "moon")


if __name__ == "__main__":
    unittest.main()
