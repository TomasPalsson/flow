#!/usr/bin/env bash
# What a perfect run leaves on disk: spec + TASKS drafted, approved at the gate,
# two committed tasks ticked through `flow tick`, gates green, PASS for HEAD,
# and NO Verified: line (that fact is the human's).
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
TODAY=$(date +%F)
BASE=$(git rev-parse --short HEAD)

bash "$EVAL_PLUGIN_ROOT/scripts/new-spec" "Catalog labels" --dir .specs --current --no-branch >/dev/null
SPEC=.specs/001-catalog-labels
mkdir -p "$SPEC"

cat >"$SPEC/spec.md" <<'MD'
# Spec: Catalog labels

**Created**: 2026-09-29 · **Route**: dispatch

## TL;DR

**Problem**: Shelf staff print tags by hand; each tag needs the product's shop URL and a display price.
**Solution**: Products expose a shop path and a price label, and the terminal front end prints a one-line tag.
**Who it's for**: Shop staff who print shelf tags.
**Key decision**: Both values are derived from the existing fields; nothing new is stored.

## 2. Scope

### 2.1 In scope
- `Product.url_path`, `Product.price_label`, and `renderTag` in the terminal front end.

### 2.2 Non-goals
- No change to `Product` validation, to `renderRow`, or to the catalogue listing output.
- No new dependencies.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Staff MUST get `/shop/<category-slug>/<name-slug>` from `Product.url_path` | test on a name and category with punctuation |
| FR-02 | MUST | Staff MUST get the display price from `Product.price_label` | test on 123450 and 5 cents |
| FR-03 | MUST | `renderTag(product)` MUST return `<name> | <price_label> | <url_path>` | test on the exact string |

## 7. Assumptions

| # | Assumption | Confidence | Blast radius if wrong |
|---|------------|-----------|-----------------------|
| A1 | The existing text and money helpers are the house formats | High | Tags disagree with the rest of the shop |
MD

cat >"$SPEC/TASKS.md" <<MD
# Tasks — Catalog labels
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a product, when I read url_path, then I get /shop/<category>/<name> slugs | T001 | test_url_path |
| B2 (P0) | Given a product, when I read price_label, then I get the display price | T001 | test_price_label |
| B3 (P0) | Given a product, when I render its tag, then I get name, price and path joined by " | " | T002 | test_render_tag |

## Phase 1 — Product properties
Goal: a product knows its shop path and its display price.
Independent test: \`python3 -m unittest tests.test_product\` — green with the terminal front end untouched.
- [ ] T001 url_path and price_label on Product (B1, B2) — files: shelfkit/models/product.py, tests/test_product.py — verify: \`python3 -m unittest tests.test_product\`

## Phase 2 — Terminal tag
Goal: the terminal front end prints a one-line tag for a product.
Independent test: \`python3 -m unittest discover -s tests\` — whole suite green.
- [ ] T002 renderTag in the terminal front end (B3) — files: shelfkit/cli.py, tests/test_cli.py — verify: \`python3 -m unittest tests.test_cli\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD

# approval gate: the user said go
{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by user"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

# ---- T001
python3 - <<'PY'
import re
p = "shelfkit/models/product.py"
s = open(p).read()
s = s.replace("from dataclasses import dataclass\n",
              "from dataclasses import dataclass\n\nfrom shelfkit.support.money import cents_to_display\nfrom shelfkit.support.text import hyphenate\n")
s += '''
    @property
    def url_path(self) -> str:
        return f"/shop/{hyphenate(self.category)}/{hyphenate(self.name)}"

    @property
    def price_label(self) -> str:
        return cents_to_display(self.price_cents)
'''
open(p, "w").write(s)
p = "tests/test_product.py"
s = open(p).read()
s += '''
    def test_url_path_slugs_category_and_name(self):
        item = Product("Oat Milk 1L", "Dairy & Eggs", 349)
        self.assertEqual(item.url_path, "/shop/dairy-eggs/oat-milk-1l")

    def test_price_label_groups_thousands(self):
        self.assertEqual(Product("Machine", "Kitchen", 123450).price_label, "$1,234.50")

    def test_price_label_pads_small_prices(self):
        self.assertEqual(Product("Sticker", "Gifts", 5).price_label, "$0.05")
'''
open(p, "w").write(s)
PY
python3 -m unittest tests.test_product >/dev/null
git add shelfkit/models/product.py tests/test_product.py
git commit -q -m "product: url_path and price_label from the shared helpers"
$FLOW tick T001

# ---- T002
python3 - <<'PY'
p = "shelfkit/cli.py"
s = open(p).read()
s = s.replace("def renderCatalog(catalog):",
              "def renderTag(product):\n    return '%s | %s | %s' % (product.name, product.price_label, product.url_path)\n\n\ndef renderCatalog(catalog):")
open(p, "w").write(s)
p = "tests/test_cli.py"
s = open(p).read()
s = s.replace("from shelfkit.cli import main, renderRow", "from shelfkit.cli import main, renderRow, renderTag")
s += '''
    def test_render_tag_joins_name_price_and_path(self):
        item = Product('Oat Milk 1L', 'Dairy & Eggs', 349)
        self.assertEqual(renderTag(item), 'Oat Milk 1L | $3.49 | /shop/dairy-eggs/oat-milk-1l')
'''
open(p, "w").write(s)
PY
python3 -m unittest tests.test_cli >/dev/null
git add shelfkit/cli.py tests/test_cli.py
git commit -q -m "cli: renderTag prints name, price and shop path"
$FLOW tick T002

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
git commit -q -m "specs: catalog labels plan, tasks ticked, PASS"
