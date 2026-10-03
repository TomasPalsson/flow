import unittest
from datetime import date

from src.invoices import Invoice


class TestDueDateBehaviour(unittest.TestCase):
    def test_weekday_due_date_is_plain_addition(self):
        # 2026-09-01 is a Tuesday; +30 days is Thursday 2026-10-01.
        invoice = Invoice("H-1", date(2026, 9, 1), 30, 100)
        self.assertEqual(invoice.due_date, date(2026, 10, 1))

    def test_saturday_rolls_to_monday(self):
        invoice = Invoice("H-2", date(2026, 9, 3), 30, 100)  # +30 = Sat 2026-10-03
        self.assertEqual(invoice.due_date, date(2026, 10, 5))

    def test_sunday_rolls_to_monday(self):
        invoice = Invoice("H-3", date(2026, 9, 4), 30, 100)  # +30 = Sun 2026-10-04
        self.assertEqual(invoice.due_date, date(2026, 10, 5))

    def test_due_date_is_a_property_not_a_method(self):
        self.assertIsInstance(Invoice.__dict__["due_date"], property)

    def test_terms_guard_still_comes_from_post_init(self):
        with self.assertRaises(ValueError):
            Invoice("H-4", date(2026, 9, 1), 0, 100)


class TestWaveDiscipline(unittest.TestCase):
    def test_later_tasks_are_not_built_yet(self):
        self.assertFalse(hasattr(Invoice, "is_overdue"), "T002 belongs to wave 2")
