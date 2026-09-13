#!/usr/bin/env bash
set -euo pipefail
mkdir -p app/legacy app/models app/services
cat >app/__init__.py <<'PY'
PY
cat >app/legacy/__init__.py <<'PY'
PY
cat >app/legacy/parser.py <<'PY'
def parse_line(line):
  parts = line.split(',')
  return [p.strip() for p in parts]


def parse_lines(lines):
  return [parse_line(l) for l in lines]


def strip_comments(lines):
  return [l for l in lines if not l.strip().startswith('#')]
PY
cat >app/models/__init__.py <<'PY'
PY
cat >app/models/record.py <<'PY'
from dataclasses import dataclass


@dataclass
class Record:
    name: str
    fields: list[str]
PY
cat >app/services/__init__.py <<'PY'
PY
cat >app/services/loader.py <<'PY'
from app.legacy.parser import parse_lines


def load(path: str) -> list[list[str]]:
    with open(path) as f:
        return parse_lines(f.readlines())
PY
