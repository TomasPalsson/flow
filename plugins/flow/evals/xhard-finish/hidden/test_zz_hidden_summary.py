import io
import os
import tempfile
import unittest

from tally.cli import main

SAMPLE = "sample/expenses.csv"

FULL = (
    "Category   Count      Total\n"
    "rent           1  $1,200.00\n"
    "groceries      2    $163.25\n"
    "transport      2     $42.00\n"
    "coffee         1      $4.50\n"
    "TOTAL          6  $1,409.75\n"
)

AUGUST = (
    "Category   Count    Total\n"
    "groceries      2  $163.25\n"
    "transport      1   $18.00\n"
    "TOTAL          3  $181.25\n"
)


def run(*argv):
    out, err = io.StringIO(), io.StringIO()
    code = main(list(argv), out, err)
    return code, out.getvalue(), err.getvalue()


def write_csv(rows):
    folder = tempfile.mkdtemp()
    path = os.path.join(folder, "e.csv")
    with open(path, "w") as sink:
        sink.write("date,category,amount_cents\n" + "".join(rows))
    return path


class HiddenSummary(unittest.TestCase):
    def test_summary_table_matches_the_spec_example(self):
        self.assertEqual(run("summary", "--file", SAMPLE), (0, FULL, ""))

    def test_month_filter_keeps_only_that_month(self):
        self.assertEqual(run("summary", "--file", SAMPLE, "--month", "2026-08"), (0, AUGUST, ""))

    def test_ties_sort_by_category_name(self):
        path = write_csv(["2026-08-01,beta,500\n", "2026-08-02,alpha,500\n", "2026-08-03,zulu,900\n"])
        lines = run("summary", "--file", path)[1].splitlines()
        self.assertEqual([line.split()[0] for line in lines], ["Category", "zulu", "alpha", "beta", "TOTAL"])

    def test_no_line_has_trailing_spaces(self):
        for line in run("summary", "--file", SAMPLE)[1].splitlines():
            self.assertEqual(line, line.rstrip())

    def test_wide_totals_widen_the_column(self):
        path = write_csv(["2026-08-01,rent,123456789\n"])
        code, out, _ = run("summary", "--file", path)
        self.assertEqual(code, 0)
        widths = {len(line) for line in out.splitlines()}
        self.assertEqual(len(widths), 1)

    def test_malformed_month_exits_2_with_message_and_no_stdout(self):
        for bad in ("2026-13", "August", "2026-8", "2026-08-01"):
            code, out, err = run("summary", "--file", SAMPLE, "--month", bad)
            self.assertEqual((code, out), (2, ""), bad)
            self.assertIn("invalid month: " + bad, err)

    def test_empty_file_prints_no_expenses(self):
        self.assertEqual(run("summary", "--file", write_csv([])), (0, "No expenses.\n", ""))

    def test_month_with_no_rows_prints_no_expenses(self):
        self.assertEqual(run("summary", "--file", SAMPLE, "--month", "2025-01"), (0, "No expenses.\n", ""))

    def test_list_command_output_is_unchanged(self):
        code, out, _ = run("list", "--file", SAMPLE)
        self.assertEqual(code, 0)
        self.assertEqual(out.splitlines()[0], "2026-08-03  groceries         $42.50")
        self.assertEqual(len(out.splitlines()), 6)
