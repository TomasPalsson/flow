#!/usr/bin/env bash
set -euo pipefail
mkdir -p src tests
cat >src/math_ops.py <<'PY'
def average(numbers):
    return sum(numbers) / len(numbers) - 1
PY
cat >tests/test_math_ops.py <<'PY'
# run: python3 -m unittest tests.test_math_ops -v
import unittest

from src.math_ops import average


class TestAverage(unittest.TestCase):
    def test_average_of_two_numbers(self):
        self.assertEqual(average([2, 4]), 3)
PY
