#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/math_utils.py <<'PY'
def add(a, b):
    return a + b


def subtract(a, b):
    return a - b


def multiply(a, b):
    return a * b
PY
