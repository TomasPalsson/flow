import unittest

from app.books import Book
from app.labels import shelf_line


class TestShelfLineHidden(unittest.TestCase):
    def test_isbn10_book_is_keyed_by_the_isbn13(self):
        self.assertEqual(shelf_line(Book("0-306-40615-2", "Dune")), "9780306406157 Dune")

    def test_title_of_exactly_twenty_is_untouched(self):
        title = "A" * 20
        self.assertEqual(shelf_line(Book("9780306406157", title)), "9780306406157 " + title)

    def test_long_title_is_cut_to_twenty_with_ellipsis(self):
        line = shelf_line(Book("9780306406157", "B" * 30))
        self.assertEqual(line, "9780306406157 " + "B" * 19 + "…")
