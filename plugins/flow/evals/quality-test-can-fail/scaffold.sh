#!/usr/bin/env bash
set -euo pipefail
mkdir -p src tests
cat >src/calc.py <<'PY'
def add(a, b):
    return a + b
PY
