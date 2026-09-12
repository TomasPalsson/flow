#!/usr/bin/env bash
set -e
mkdir -p src
cat >src/math_utils.py <<'PY'
def add(a, b):
    return a + b


def subtract(a, b):
    return a - b


def multiply(a, b):
    return a * b
PY
