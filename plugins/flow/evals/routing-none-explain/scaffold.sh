#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/cart.py <<'PY'
def calculate_total(items):
    return sum(item["price"] * item["qty"] for item in items)
PY
