#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/models app/support app/services
cat >app/__init__.py <<'PY'
PY
cat >app/support/__init__.py <<'PY'
PY
cat >app/support/strings.py <<'PY'
def to_kebab(value: str) -> str:
    return "-".join(value.strip().lower().split())
PY
cat >app/models/__init__.py <<'PY'
PY
cat >app/models/order.py <<'PY'
from dataclasses import dataclass


@dataclass
class Order:
    id: str
    total_cents: int

    def __post_init__(self) -> None:
        assert self.total_cents >= 0, "total_cents must not be negative"
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/receipts.py <<'PY'
from app.models.order import Order


def receipt_lines(order: Order) -> list[str]:
    return [f"Order {order.id}"]
PY
