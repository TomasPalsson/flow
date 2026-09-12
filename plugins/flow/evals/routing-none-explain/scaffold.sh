#!/usr/bin/env bash
set -e
mkdir -p src
cat >src/cart.py <<'PY'
def calculate_total(items):
    return sum(item["price"] * item["qty"] for item in items)
PY
