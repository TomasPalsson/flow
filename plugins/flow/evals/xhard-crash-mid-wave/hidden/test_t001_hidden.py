import unittest

from app.isbn import normalize_isbn


class TestNormalizeIsbnHidden(unittest.TestCase):
    def test_spaces_and_hyphens_are_stripped(self):
        self.assertEqual(normalize_isbn("978 0 306 40615 7"), "9780306406157")

    def test_isbn10_plain(self):
        self.assertEqual(normalize_isbn("0306406152"), "9780306406157")

    def test_isbn10_with_hyphens_and_x_check_digit(self):
        self.assertEqual(normalize_isbn("0-8044-2957-X"), "9780804429573")
