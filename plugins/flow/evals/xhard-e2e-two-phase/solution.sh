#!/usr/bin/env bash
# What a perfect run leaves on disk: spec + a two-phase TASKS drafted and approved
# at the gate, three committed tasks ticked through `flow tick`, the live data
# migrated with the shop's own reader, gates green, PASS for HEAD, and NO
# Verified: line (that fact is the human's).
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
TODAY=$(date +%F)
BASE=$(git rev-parse --short HEAD)

bash "$EVAL_PLUGIN_ROOT/scripts/new-spec" "Price in cents" --dir .specs --current --no-branch >/dev/null
SPEC=.specs/001-price-in-cents
mkdir -p "$SPEC"

cat >"$SPEC/spec.md" <<'MD'
# Spec: Price in cents

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

**Problem**: Prices are stored as dollar text, so nothing can add them up.
**Solution**: Products carry integer cents, the live data is migrated, and a totals command sums them.
**Who it's for**: Shop desk staff.
**Key decision**: An empty price migrates to null, never to zero.

## 2. Scope

### 2.1 In scope
- `Product.price_cents`, the store, `list`, a one-off migration of `data/` (not `data/archive/`) and `tests/fixtures/`, and a `totals` command.

### 2.2 Non-goals
- No change to `data/archive/`, no new dependencies.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Product MUST carry `price_cents` (int or None) instead of `price` | load a migrated file |
| FR-02 | MUST | Every live record MUST migrate with exact cents and every other field kept | compare against the old files |
| FR-03 | MUST | `list` MUST print what it printed before, and `-` for an unpriced product | list catalog and clearance |
| FR-04 | MUST | `totals <file>` MUST print `Total: <sum> (<n> priced, <m> unpriced)` | totals on catalog and clearance |

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The shop's existing money helpers are the house formats | High | Cents disagree with the rest of the shop |
MD

cat >"$SPEC/TASKS.md" <<MD
# Tasks — Price in cents
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a file with price_cents, when I load it, then products carry cents or None | T001 | test_load_reads_cents |
| B2 (P0) | Given the old data files, when I migrate them, then every record keeps its fields and gets exact cents | T002 | test_migrate_file |
| B3 (P0) | Given a priced file, when I run totals, then I get the sum and the counts | T003 | test_totals_line |

## Phase 1 — Cents model and data
Goal: products carry integer cents and every live data file has been migrated without losing a record.
Independent test: \`python3 -m unittest tests.test_price_cents tests.test_migrate\` — green, then \`python3 -m shopdesk.cli list data/clearance.json\` prints the migrated file.
- [ ] T001 Product, store and list use price_cents (B1) — files: shopdesk/models.py, shopdesk/store.py, shopdesk/cli.py, tests/test_price_cents.py — verify: \`python3 -m unittest tests.test_price_cents\`
- [ ] T002 Migrate the live data and fixtures (B2) — files: shopdesk/migrate.py, tests/test_migrate.py, data/catalog.json, data/clearance.json, data/imports/supplier-2025.json, tests/fixtures/sample_products.json — verify: \`python3 -m unittest tests.test_migrate\` — after: T001

## Phase 2 — Totals
Goal: staff can total a catalogue file from the command line.
Independent test: \`python3 -m shopdesk.cli totals data/clearance.json\` — prints Total: \$61.15 (2 priced, 1 unpriced).
- [ ] T003 totals command (B3) — files: shopdesk/cli.py, tests/test_totals.py — verify: \`python3 -m unittest tests.test_totals\` — after: T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD

# approval gate: the user said go
{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by user"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

# ---- T001
cat >shopdesk/models.py <<'PY'
from dataclasses import dataclass
from typing import Optional


@dataclass(frozen=True)
class Product:
    sku: str
    name: str
    price_cents: Optional[int]

    def __post_init__(self):
        if not self.sku.strip():
            raise ValueError("sku must not be blank")
        if not self.name.strip():
            raise ValueError("name must not be blank")
PY
cat >shopdesk/store.py <<'PY'
import json

from shopdesk.models import Product


def load_products(path):
    with open(path) as fh:
        rows = json.load(fh)
    return [Product(r["sku"], r["name"], r["price_cents"]) for r in rows]


def save_products(path, products):
    rows = [{"sku": p.sku, "name": p.name, "price_cents": p.price_cents} for p in products]
    with open(path, "w") as fh:
        json.dump(rows, fh, indent=2)
        fh.write("\n")
PY
cat >shopdesk/cli.py <<'PY'
import sys

from shopdesk.store import load_products
from shopdesk.support.moneytext import show_amount


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if argv and argv[0] == "list":
        for product in load_products(argv[1]):
            price = "-" if product.price_cents is None else show_amount(product.price_cents)
            sys.stdout.write("%s  %s  %s\n" % (product.sku, product.name, price))
        return 0
    sys.stderr.write("usage: shopdesk list <file>\n")
    return 2


if __name__ == "__main__":
    sys.exit(main())
PY
cat >tests/test_price_cents.py <<'PY'
import contextlib
import io
import json
import os
import tempfile
import unittest

from shopdesk.cli import main
from shopdesk.models import Product
from shopdesk.store import load_products, save_products


def write_rows(tmp, rows):
    path = os.path.join(tmp, "products.json")
    with open(path, "w") as fh:
        json.dump(rows, fh)
    return path


class TestPriceCents(unittest.TestCase):
    def test_load_reads_cents_and_none(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_rows(tmp, [
                {"sku": "A-1", "name": "Lamp", "price_cents": 123450},
                {"sku": "A-2", "name": "Box", "price_cents": None},
            ])
            self.assertEqual([p.price_cents for p in load_products(path)], [123450, None])

    def test_save_writes_price_cents_key_only(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "out.json")
            save_products(path, [Product("A-1", "Lamp", 1999)])
            with open(path) as fh:
                self.assertEqual(json.load(fh), [{"sku": "A-1", "name": "Lamp", "price_cents": 1999}])

    def test_list_formats_cents_and_dashes_unpriced(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = write_rows(tmp, [
                {"sku": "A-1", "name": "Lamp", "price_cents": 123450},
                {"sku": "A-2", "name": "Box", "price_cents": None},
            ])
            out = io.StringIO()
            with contextlib.redirect_stdout(out):
                main(["list", path])
        self.assertEqual(out.getvalue(), "A-1  Lamp  $1,234.50\nA-2  Box  -\n")
PY
python3 -m unittest tests.test_price_cents >/dev/null 2>&1
git add shopdesk/models.py shopdesk/store.py shopdesk/cli.py tests/test_price_cents.py
git commit -q -m "products: carry integer cents, list prints them as before"
$FLOW tick T001

# ---- T002
cat >shopdesk/migrate.py <<'PY'
import json
import sys

from shopdesk.support.moneytext import read_amount


def migrate_row(row):
    """Swap "price" for "price_cents" in place of the key, leaving every other field alone."""
    out = {}
    for key, value in row.items():
        if key == "price":
            out["price_cents"] = read_amount(value) if value.strip() else None
        else:
            out[key] = value
    return out


def migrate_file(path):
    with open(path) as fh:
        rows = json.load(fh)
    with open(path, "w") as fh:
        json.dump([migrate_row(r) for r in rows], fh, indent=2)
        fh.write("\n")


if __name__ == "__main__":
    for target in sys.argv[1:]:
        migrate_file(target)
PY
cat >tests/test_migrate.py <<'PY'
import json
import os
import tempfile
import unittest

from shopdesk.migrate import migrate_file, migrate_row


class TestMigrate(unittest.TestCase):
    def test_migrate_row_is_exact_where_float_math_is_not(self):
        self.assertEqual(migrate_row({"price": "$19.99"})["price_cents"], 1999)
        self.assertEqual(migrate_row({"price": "$0.29"})["price_cents"], 29)

    def test_migrate_row_keeps_other_fields_and_position(self):
        row = {"sku": "A-1", "price": "$1,234.50", "tags": ["x"], "note": "n"}
        got = migrate_row(row)
        self.assertEqual(list(got), ["sku", "price_cents", "tags", "note"])
        self.assertEqual(got["tags"], ["x"])

    def test_migrate_row_empty_price_is_null_not_zero(self):
        self.assertIsNone(migrate_row({"price": ""})["price_cents"])

    def test_migrate_file_rewrites_in_place_without_dropping_records(self):
        rows = [{"sku": "A-1", "price": " $58.10 "}, {"sku": "A-2", "price": "7"}]
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "p.json")
            with open(path, "w") as fh:
                json.dump(rows, fh)
            migrate_file(path)
            with open(path) as fh:
                self.assertEqual(json.load(fh), [
                    {"sku": "A-1", "price_cents": 5810},
                    {"sku": "A-2", "price_cents": 700},
                ])
PY
python3 -m shopdesk.migrate data/catalog.json data/clearance.json data/imports/supplier-2025.json tests/fixtures/sample_products.json
python3 -m unittest tests.test_migrate >/dev/null 2>&1
git add shopdesk/migrate.py tests/test_migrate.py data/catalog.json data/clearance.json data/imports/supplier-2025.json tests/fixtures/sample_products.json
git commit -q -m "data: migrate live catalogues and fixtures to integer cents"
$FLOW tick T002
python3 -m unittest tests.test_price_cents tests.test_migrate >/dev/null 2>&1
python3 -m shopdesk.cli list data/clearance.json >/dev/null

# ---- T003
python3 - <<'PY'
p = "shopdesk/cli.py"
s = open(p).read()
s = s.replace('''    sys.stderr.write("usage: shopdesk list <file>\\n")''', '''    if argv and argv[0] == "totals":
        products = load_products(argv[1])
        priced = [p.price_cents for p in products if p.price_cents is not None]
        sys.stdout.write("Total: %s (%d priced, %d unpriced)\\n" % (
            show_amount(sum(priced)), len(priced), len(products) - len(priced)))
        return 0
    sys.stderr.write("usage: shopdesk list|totals <file>\\n")''')
open(p, "w").write(s)
PY
cat >tests/test_totals.py <<'PY'
import contextlib
import io
import json
import os
import tempfile
import unittest

from shopdesk.cli import main


def totals_line(rows):
    with tempfile.TemporaryDirectory() as tmp:
        path = os.path.join(tmp, "p.json")
        with open(path, "w") as fh:
            json.dump(rows, fh)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            main(["totals", path])
    return out.getvalue()


class TestTotals(unittest.TestCase):
    def test_totals_line_sums_priced_and_counts_both(self):
        rows = [
            {"sku": "A", "name": "a", "price_cents": 123450},
            {"sku": "B", "name": "b", "price_cents": 5},
            {"sku": "C", "name": "c", "price_cents": None},
        ]
        self.assertEqual(totals_line(rows), "Total: $1,234.55 (2 priced, 1 unpriced)\n")

    def test_totals_line_with_nothing_priced_is_zero(self):
        rows = [{"sku": "A", "name": "a", "price_cents": None}]
        self.assertEqual(totals_line(rows), "Total: $0.00 (0 priced, 1 unpriced)\n")

    def test_totals_line_on_empty_file(self):
        self.assertEqual(totals_line([]), "Total: $0.00 (0 priced, 0 unpriced)\n")
PY
python3 -m unittest tests.test_totals >/dev/null 2>&1
python3 -m shopdesk.cli totals data/clearance.json >/dev/null
git add shopdesk/cli.py tests/test_totals.py
git commit -q -m "cli: totals command sums priced products"
$FLOW tick T003

# ---- gates
python3 -m unittest discover -s tests >/dev/null
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$SPEC/PASS-$HEAD_SHA.md" <<MD
# PASS $HEAD_SHA
- G001 \`python3 -m unittest discover -s tests\` — exit 0
- G002 branch review — no findings above threshold
MD
$FLOW tick G001
$FLOW tick G002
git add "$SPEC"
git commit -q -m "specs: price in cents plan, tasks ticked, PASS"
