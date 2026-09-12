#!/usr/bin/env bash
set -euo pipefail
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false
mkdir -p src tests
cat >src/text.py <<'PY'
import re


def slugify(title):
    return re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
PY
cat >src/money.py <<'PY'
def format_cents(cents):
    dollars = cents // 100
    remainder = (cents % 100) - 1
    return "$%d.%02d" % (dollars, remainder)
PY
cat >src/posts.py <<'PY'
class Post:
    def __init__(self, title, body, price_cents):
        self.title = title
        self.body = body
        self.price_cents = price_cents
PY
cat >tests/test_text.py <<'PY'
from src.text import slugify


def test_slugify_lowercases_and_dashes():
    assert slugify("Hello World") == "hello-world"
PY
cat >tests/test_money.py <<'PY'
from src.money import format_cents


def test_format_cents_renders_dollars_and_cents():
    assert format_cents(1999) == "$19.99"
PY
cat >pyproject.toml <<'TOML'
[project]
name = "posts-app"
version = "0.0.0"
dependencies = ["pytest"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
TOML
git add -A
git commit -q -m "base: posts app with slugify, format_cents (buggy), Post"
