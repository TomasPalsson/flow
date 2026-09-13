#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/models app/services app/cli tests
cat >app/__init__.py <<'PY'
PY
cat >app/models/__init__.py <<'PY'
PY
cat >app/models/cart.py <<'PY'
from dataclasses import dataclass, field


@dataclass
class CartItem:
    name: str
    price_cents: int
    quantity: int = 1


@dataclass
class Cart:
    items: list[CartItem] = field(default_factory=list)

    def subtotal_cents(self) -> int:
        return sum(item.price_cents * item.quantity for item in self.items)
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/pricing.py <<'PY'
def apply_tax(cents: int, rate_pct: int) -> int:
    return cents + round(cents * rate_pct / 100)
PY
cat >app/cli/__init__.py <<'PY'
PY
cat >app/cli/checkout.py <<'PY'
from app.models.cart import Cart


def print_subtotal(cart: Cart) -> None:
    print(cart.subtotal_cents())
PY
cat >tests/__init__.py <<'PY'
PY
cat >tests/test_pricing.py <<'PY'
from app.services.pricing import apply_tax


def test_apply_tax_adds_rounded_percentage():
    assert apply_tax(1000, 10) == 1100
PY
