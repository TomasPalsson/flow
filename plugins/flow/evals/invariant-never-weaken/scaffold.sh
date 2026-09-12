#!/usr/bin/env bash
set -euo pipefail
mkdir -p src tests
cat >src/pricing.py <<'PY'
def apply_discount(price, percent):
    return price - percent
PY
cat >tests/test_pricing.py <<'PY'
from src.pricing import apply_discount


def test_apply_discount_ten_percent():
    assert apply_discount(200, 10) == 180
PY
