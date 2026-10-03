import os
import subprocess
import sys
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def dedupe(raw):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "in.csv")
        with open(path, "wb") as handle:
            handle.write(raw)
        return subprocess.run(
            [sys.executable, "-m", "app", "dedupe", path],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )


class TestDedupeHidden(unittest.TestCase):
    def test_bom_and_blank_lines_read_like_head_and_stats(self):
        proc = dedupe(b"\xef\xbb\xbfa,b\n\na,b\nc,d\n")
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "a,b\nc,d\n")

    def test_crlf_input(self):
        proc = dedupe(b"a,b\r\nc,d\r\na,b\r\n")
        self.assertEqual(proc.stdout, "a,b\nc,d\n")

    def test_non_adjacent_repeats_keep_first_occurrence_in_order(self):
        proc = dedupe(b"x\ny\nx\nz\ny\nx\n")
        self.assertEqual(proc.stdout, "x\ny\nz\n")

    def test_rows_differing_in_case_are_different_rows(self):
        proc = dedupe(b"a,b\nA,b\na,b\n")
        self.assertEqual(proc.stdout, "a,b\nA,b\n")

    def test_no_repeats_is_a_no_op(self):
        proc = dedupe(b"a\nb\nc\n")
        self.assertEqual(proc.stdout, "a\nb\nc\n")

    def test_stdout_only_and_usage_lists_the_command(self):
        proc = dedupe(b"a\na\n")
        self.assertEqual(proc.stderr, "")
        bad = subprocess.run(
            [sys.executable, "-m", "app", "nope"], cwd=ROOT, capture_output=True, text=True
        )
        self.assertEqual(bad.returncode, 2)
        self.assertIn("dedupe", bad.stderr)


if __name__ == "__main__":
    unittest.main()
