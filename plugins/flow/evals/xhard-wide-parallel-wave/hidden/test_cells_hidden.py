import unittest

from cells.fmt.duration import format_duration
from cells.fmt.filesize import format_size
from cells.fmt.money import format_money
from cells.fmt.percent import format_percent


class TestMoneyHidden(unittest.TestCase):
    def test_grouped_dollars_right_aligned_in_the_default_width(self):
        self.assertEqual(format_money(123456), "$1,234.56".rjust(12))

    def test_small_and_negative_amounts(self):
        self.assertEqual(format_money(5, 6), " $0.05")
        self.assertEqual(format_money(-5, 8), "  -$0.05")
        self.assertEqual(format_money(-1234050, 11), "-$12,340.50")

    def test_millions_group_twice(self):
        self.assertEqual(format_money(123456789, 15), "  $1,234,567.89")

    def test_wide_cell_is_cut_on_the_left_with_an_ellipsis(self):
        self.assertEqual(format_money(123456, 6), "…34.56")


class TestPercentHidden(unittest.TestCase):
    def test_one_decimal(self):
        self.assertEqual(format_percent(0.125), "12.5%".rjust(8))
        self.assertEqual(format_percent(1), "100.0%".rjust(8))
        self.assertEqual(format_percent(0), "0.0%".rjust(8))

    def test_wide_cell_is_cut_on_the_left_with_an_ellipsis(self):
        self.assertEqual(format_percent(0.125, 4), "….5%")


class TestDurationHidden(unittest.TestCase):
    def test_the_three_shapes(self):
        self.assertEqual(format_duration(45), "45s".rjust(10))
        self.assertEqual(format_duration(725), "12m 05s".rjust(10))
        self.assertEqual(format_duration(3900), "1h 05m".rjust(10))

    def test_unit_edges(self):
        self.assertEqual(format_duration(0, 3), " 0s")
        self.assertEqual(format_duration(59, 3), "59s")
        self.assertEqual(format_duration(60, 6), "1m 00s")
        self.assertEqual(format_duration(3599, 7), "59m 59s")
        self.assertEqual(format_duration(3600, 6), "1h 00m")

    def test_seconds_are_dropped_from_an_hour_up(self):
        self.assertEqual(format_duration(7325, 6), "2h 02m")

    def test_wide_cell_is_cut_on_the_left_with_an_ellipsis(self):
        self.assertEqual(format_duration(725, 5), "… 05s")


class TestSizeHidden(unittest.TestCase):
    def test_bytes_and_units(self):
        self.assertEqual(format_size(512), "512 B".rjust(10))
        self.assertEqual(format_size(1023, 8), "1023 B".rjust(8))
        self.assertEqual(format_size(1024), "1.0 KB".rjust(10))
        self.assertEqual(format_size(1536), "1.5 KB".rjust(10))
        self.assertEqual(format_size(1048576), "1.0 MB".rjust(10))
        self.assertEqual(format_size(5 * 1024 ** 3), "5.0 GB".rjust(10))

    def test_gb_is_the_largest_unit(self):
        self.assertEqual(format_size(2048 * 1024 ** 3, 11), "2048.0 GB".rjust(11))

    def test_wide_cell_is_cut_on_the_left_with_an_ellipsis(self):
        self.assertEqual(format_size(1536, 4), "… KB")


if __name__ == "__main__":
    unittest.main()
