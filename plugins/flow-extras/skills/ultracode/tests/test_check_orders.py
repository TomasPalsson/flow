"""Tests for scripts/check-orders. Run: python3 -I test_check_orders.py"""
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "..", "scripts", "check-orders")

SPEC = """# SPEC: demo

## Objective
x

## Standing orders
<!-- comment -->
1. Never touch the lockfile.
2. Report test counts in every
   summary, not just pass or fail.

## Rules for every agent
- be careful
"""

ORDER1 = "1. Never touch the lockfile."
ORDER2 = "2. Report test counts in every summary, not just pass or fail."


def run(spec_text, prompts):
    with tempfile.TemporaryDirectory() as d:
        spec = os.path.join(d, "SPEC.md")
        pdir = os.path.join(d, "prompts")
        os.mkdir(pdir)
        with open(spec, "w") as f:
            f.write(spec_text)
        for name, text in prompts.items():
            with open(os.path.join(pdir, name), "w") as f:
                f.write(text)
        r = subprocess.run([sys.executable, "-I", SCRIPT, spec, pdir],
                           capture_output=True, text=True)
        return r.returncode, r.stdout + r.stderr


class CheckOrders(unittest.TestCase):
    def test_all_complete_exits_zero(self):
        full = "preamble\n## Standing orders\n%s\n%s\nbody\n" % (ORDER1, ORDER2)
        code, out = run(SPEC, {"a.md": full, "b.md": full, "c.md": full})
        self.assertEqual(code, 0, out)

    def test_missing_order_two_names_that_file(self):
        full = "%s\n%s\n" % (ORDER1, ORDER2)
        code, out = run(SPEC, {"a.md": full, "b.md": ORDER1 + "\n", "c.md": full})
        self.assertEqual(code, 1, out)
        self.assertIn("b.md", out)
        self.assertIn("order 2", out)
        self.assertNotIn("a.md", out)
        self.assertNotIn("c.md", out)

    def test_wrapped_order_matches_after_whitespace_normalising(self):
        wrapped = "%s\n2. Report test counts in every\n  summary, not just pass or fail.\n" % ORDER1
        code, out = run(SPEC, {"a.md": wrapped})
        self.assertEqual(code, 0, out)

    def test_no_orders_is_fine(self):
        spec = "# SPEC\n\n## Standing orders\n1. (none)\n"
        code, out = run(spec, {"a.md": "anything"})
        self.assertEqual(code, 0, out)

    def test_empty_prompt_dir_fails(self):
        code, out = run(SPEC, {})
        self.assertEqual(code, 1, out)
        self.assertIn("no prompt files", out)

    def test_spec_without_section_is_a_usage_error(self):
        code, out = run("# SPEC\n", {"a.md": "x"})
        self.assertEqual(code, 2, out)


if __name__ == "__main__":
    unittest.main()
