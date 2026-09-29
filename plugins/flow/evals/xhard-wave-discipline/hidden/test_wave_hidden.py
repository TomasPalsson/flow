import unittest

from app.models import Item
from app.reports.labels import shelf_label
from app.reports.low_stock import low_stock


class TestLowStockHidden(unittest.TestCase):
    def test_strictly_below_threshold_fewest_first_ties_by_name(self):
        items = [
            Item(1, "Widget", 4),
            Item(2, "Anvil", 4),
            Item(3, "Bolt", 5),
            Item(4, "Cog", 0),
            Item(5, "Drill", 9),
        ]
        got = [i.name for i in low_stock(items, 5)]
        self.assertEqual(got, ["Cog", "Anvil", "Widget"])

    def test_returns_a_list_and_leaves_input_alone(self):
        items = [Item(1, "B", 2), Item(2, "A", 1)]
        result = low_stock(items, 10)
        self.assertIsInstance(result, list)
        self.assertEqual([i.name for i in items], ["B", "A"])

    def test_empty_and_zero_threshold(self):
        self.assertEqual(low_stock([], 5), [])
        self.assertEqual(low_stock([Item(1, "A", 0)], 0), [])


class TestShelfLabelHidden(unittest.TestCase):
    def test_short_name_untouched_and_sku_padded(self):
        self.assertEqual(shelf_label(Item(7, "Bolt", 1), 12), "00007 Bolt")

    def test_long_name_cut_with_the_project_ellipsis(self):
        label = shelf_label(Item(42, "Extra long widget name", 3), 12)
        self.assertEqual(label, "00042 Extra long …")

    def test_name_exactly_at_width_is_untouched(self):
        self.assertEqual(shelf_label(Item(1, "abcdefghij", 1), 10), "00001 abcdefghij")

    def test_default_width_is_24(self):
        name = "x" * 30
        label = shelf_label(Item(1, name, 1))
        self.assertEqual(label, "00001 " + "x" * 23 + "…")


if __name__ == "__main__":
    unittest.main()
