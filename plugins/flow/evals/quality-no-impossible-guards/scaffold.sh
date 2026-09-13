#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/orders.py <<'PY'
from dataclasses import dataclass


@dataclass
class Order:
    id: str
    total: float
PY
