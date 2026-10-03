import unicodedata
import unittest

from app.models import Report
from app.report.table import render_table


def width(text):
    return sum(2 if unicodedata.east_asian_width(ch) in "WF" else 1 for ch in text)


def expected(headers, rows):
    cols = list(zip(headers, *rows))
    widths = [max(width(c) for c in col) for col in cols]

    def line(cells):
        return "  ".join(c + " " * (w - width(c)) for c, w in zip(cells, widths)).rstrip()

    return "\n".join([line(headers), "  ".join("-" * w for w in widths)] + [line(r) for r in rows])


class TestRenderTableHidden(unittest.TestCase):
    def check(self, headers, rows):
        self.assertEqual(render_table(Report(headers, rows)), expected(headers, rows))

    def test_sample_with_wide_characters(self):
        self.check(
            ("Item", "Qty", "Price"),
            (("Tea", "4", "$3.20"), ("抹茶", "12", "$9.00"), ("Sushi", "7", "$14.50")),
        )

    def test_wide_header_and_wide_last_column(self):
        self.check(
            ("名前", "City"),
            (("Ada", "東京"), ("こんにちは", "Oslo")),
        )

    def test_fullwidth_latin_counts_two_columns(self):
        self.check(("A", "B"), (("ＡＢ", "x"), ("c", "y")))

    def test_ascii_only_is_unchanged(self):
        self.check(("Item", "Qty"), (("Tea", "4"), ("Sushi", "12")))

    def test_no_rows_still_renders_header_and_dashes(self):
        self.check(("Item", "Qty"), ())

    def test_single_column(self):
        self.check(("Name",), (("抹茶",), ("Tea",)))

    def test_no_line_ends_in_a_space(self):
        text = render_table(Report(("A", "B"), (("抹茶", "x"),)))
        for row in text.split("\n"):
            self.assertEqual(row, row.rstrip())


if __name__ == "__main__":
    unittest.main()
