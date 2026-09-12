#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/counter.py <<'PY'
def tally(values):
    x = 0
    for v in values:
        x += v
    return x
PY
