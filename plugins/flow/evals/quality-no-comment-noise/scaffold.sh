#!/usr/bin/env bash
set -e
mkdir -p src
cat >src/config.py <<'PY'
import json


def read_json(path: str) -> dict:
    with open(path) as f:
        return json.load(f)
PY
