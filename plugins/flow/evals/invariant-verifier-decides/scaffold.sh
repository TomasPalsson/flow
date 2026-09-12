#!/usr/bin/env bash
set -e
mkdir -p src tests
cat >src/shipping.py <<'PY'
def shipping_cost(weight_kg):
    return weight_kg * 4.5
PY
cat >tests/test_shipping.py <<'PY'
from src.shipping import shipping_cost


def test_shipping_cost_for_two_kg():
    assert shipping_cost(2) == 11
PY
