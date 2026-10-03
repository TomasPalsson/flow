#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

mkdir -p shelfkit/support shelfkit/models tests .claude
cat >.gitignore <<'GI'
__pycache__/
*.pyc
GI
cat >.claude/flow.config.json <<'JSON'
{
  "requireSpec": true
}
JSON

# --- commit 1: text and money helpers, in a support package -------------------
cat >shelfkit/__init__.py <<'PY'
PY
cat >shelfkit/support/__init__.py <<'PY'
PY
cat >shelfkit/support/text.py <<'PY'
import re


def hyphenate(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.strip().lower()).strip("-")
PY
cat >shelfkit/support/money.py <<'PY'
def cents_to_display(cents: int) -> str:
    return f"${cents / 100:,.2f}"
PY
cat >tests/__init__.py <<'PY'
PY
cat >tests/test_text.py <<'PY'
import unittest

from shelfkit.support.text import hyphenate


class TestHyphenate(unittest.TestCase):
    def test_hyphenate_lowercases_and_dashes(self):
        self.assertEqual(hyphenate("Hello World"), "hello-world")

    def test_hyphenate_collapses_runs_and_trims(self):
        self.assertEqual(hyphenate("  A -- B!  "), "a-b")
PY
cat >tests/test_money.py <<'PY'
import unittest

from shelfkit.support.money import cents_to_display


class TestCentsToDisplay(unittest.TestCase):
    def test_cents_to_display_groups_thousands(self):
        self.assertEqual(cents_to_display(123450), "$1,234.50")

    def test_cents_to_display_pads_cents(self):
        self.assertEqual(cents_to_display(5), "$0.05")
PY
cat >pyproject.toml <<'TOML'
[project]
name = "shelfkit"
version = "0.3.0"
dependencies = []
TOML
cat >README.md <<'MD'
# shelfkit

Small shelf-catalogue library and terminal front end for a corner shop.

- Run tests: `python3 -m unittest discover -s tests -v`
- No new dependencies: the standard library only.
- Layout: `shelfkit/models` (validated records), `shelfkit/support` (shared
  helpers), `shelfkit/catalog.py`, `shelfkit/cli.py` (terminal output).
MD
git add -A
git commit -q -m "support: text and money helpers"

# --- commit 2: validated models -----------------------------------------------
cat >shelfkit/models/__init__.py <<'PY'
PY
cat >shelfkit/models/product.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Product:
    name: str
    category: str
    price_cents: int

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if not self.category.strip():
            raise ValueError("category must not be blank")
        if not isinstance(self.price_cents, int) or self.price_cents < 0:
            raise ValueError("price_cents must be a non-negative integer")
PY
cat >shelfkit/models/supplier.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Supplier:
    name: str
    email: str

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if "@" not in self.email:
            raise ValueError("email must contain @")
PY
cat >tests/test_product.py <<'PY'
import unittest

from shelfkit.models.product import Product


class TestProduct(unittest.TestCase):
    def test_product_rejects_blank_name(self):
        with self.assertRaises(ValueError):
            Product("  ", "Dairy", 100)

    def test_product_rejects_negative_price(self):
        with self.assertRaises(ValueError):
            Product("Milk", "Dairy", -1)

    def test_product_keeps_fields(self):
        item = Product("Milk", "Dairy", 349)
        self.assertEqual((item.name, item.category, item.price_cents), ("Milk", "Dairy", 349))
PY
git add -A
git commit -q -m "models: validated Product and Supplier"

# --- commit 3: catalog and the terminal front end (single quotes, camelCase) --
cat >shelfkit/catalog.py <<'PY'
from shelfkit.models.product import Product


class Catalog:
    def __init__(self):
        self._products = []

    def add(self, product: Product) -> None:
        self._products.append(product)

    def products(self):
        return list(self._products)

    def in_category(self, category: str):
        return [p for p in self._products if p.category == category]
PY
cat >shelfkit/cli.py <<'PY'
import sys


def renderRow(product):
    return '%-24s %10d' % (product.name, product.price_cents)


def renderCatalog(catalog):
    lines = ['%-24s %10s' % ('NAME', 'CENTS')]
    for product in catalog.products():
        lines.append(renderRow(product))
    return '\n'.join(lines)


def main(catalog, out=None):
    out = out or sys.stdout
    out.write(renderCatalog(catalog) + '\n')
    return 0
PY
cat >tests/test_cli.py <<'PY'
import io
import unittest

from shelfkit.catalog import Catalog
from shelfkit.cli import main, renderRow
from shelfkit.models.product import Product


class TestCli(unittest.TestCase):
    def test_render_row_pads_name_and_right_aligns_cents(self):
        self.assertEqual(renderRow(Product('Oat Milk 1L', 'Dairy', 349)), 'Oat Milk 1L                     349')

    def test_main_prints_header_then_rows(self):
        catalog = Catalog()
        catalog.add(Product('Eggs', 'Dairy', 520))
        out = io.StringIO()
        self.assertEqual(main(catalog, out), 0)
        self.assertEqual(out.getvalue().splitlines()[0].split(), ['NAME', 'CENTS'])
PY
git add -A
git commit -q -m "cli: catalog listing"
