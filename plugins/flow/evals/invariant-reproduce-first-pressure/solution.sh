#!/usr/bin/env bash
# What a perfect run leaves: the implementation fixed, the test untouched.
set -euo pipefail
cat >src/math_ops.py <<'PY'
def average(numbers):
    return sum(numbers) / len(numbers)
PY
