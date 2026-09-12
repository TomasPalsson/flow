#!/usr/bin/env bash
set -euo pipefail
mkdir -p src
cat >src/text.py <<'PY'
import re


def slugify(value: str) -> str:
    value = value.lower().strip()
    return re.sub(r"[^a-z0-9]+", "-", value).strip("-")
PY
cat >src/posts.py <<'PY'
from dataclasses import dataclass


@dataclass
class Post:
    title: str
    body: str
PY
