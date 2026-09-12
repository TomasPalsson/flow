#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
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
