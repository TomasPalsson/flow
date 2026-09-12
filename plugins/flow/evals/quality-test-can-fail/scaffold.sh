#!/usr/bin/env bash
set -e
mkdir -p src tests
cat >src/calc.py <<'PY'
def add(a, b):
    return a + b
PY
