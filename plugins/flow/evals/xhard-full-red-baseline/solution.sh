#!/usr/bin/env bash
# What a perfect autoApprove pipeline leaves on disk: TASKS.md drafted and linted,
# Approved by the model (autoApprove) with a real Base, the red tax bug fixed in the
# SOURCE, total_label built on the existing usd() helper, every task and gate ticked
# through flow tick, PASS-<HEAD>.md, and no Verified: (that one stays the human's).
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
D=.specs/001-total-label
BASE=$(git rev-parse --short HEAD)
TODAY=$(date +%Y-%m-%d)

# drafting: TASKS.md without Approved:
cat >"$D/TASKS.md" <<MD
# Tasks — Total label
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an order with tax, when tax is computed, then a half cent rounds up | T001 | test_tax_rounds_half_up |
| B2 (P0) | Given an order, when I ask for its label, then it reads Total: \$X.XX (incl. tax \$Y.YY) | T002 | test_label_matches_the_spec_examples |

## Phase 1 — Total label
Goal: an order reads as one total line whose tax matches what is charged.
Independent test: \`python3 -m unittest tests.test_pricing tests.test_labels\` — green with the report module untouched.
- [ ] T001 Tax rounds half up (B1) — files: shopkit/pricing.py — verify: \`python3 -m unittest tests.test_pricing\`
- [ ] T002 total_label built on usd (B2) — files: shopkit/labels.py, tests/test_labels.py — verify: \`python3 -m unittest tests.test_labels\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
node "$FLOW" lint "$D/TASKS.md" --json >/dev/null
# unapproved -> autoApprove: the model writes the line itself, then carries on
sed -i "2a Approved: $TODAY by model (autoApprove)" "$D/TASKS.md"
node "$FLOW" lint "$D/TASKS.md" --json >/dev/null

# T001: the tax bug the red test already pins
cat >shopkit/pricing.py <<'PY'
def subtotal_cents(order):
    return sum(item.unit_cents * item.qty for item in order.items)


def tax_cents(order):
    return (subtotal_cents(order) * order.tax_bp + 5000) // 10000


def order_total_cents(order):
    return subtotal_cents(order) + tax_cents(order)
PY
python3 -m unittest tests.test_pricing >/dev/null 2>&1
git add shopkit/pricing.py "$D/TASKS.md"
git commit -q -m "fix: tax rounds half up"
node "$FLOW" tick T001

# T002: the label, on the existing usd() helper
cat >shopkit/labels.py <<'PY'
from shopkit.pricing import order_total_cents, tax_cents
from shopkit.support.display import usd


def total_label(order):
    return f"Total: {usd(order_total_cents(order))} (incl. tax {usd(tax_cents(order))})"
PY
cat >tests/test_labels.py <<'PY'
import unittest

from shopkit.labels import total_label
from shopkit.models import LineItem, Order


class TestLabels(unittest.TestCase):
    def test_label_matches_the_spec_examples(self):
        taxed = Order((LineItem("Mug", 1050),), tax_bp=500)
        untaxed = Order((LineItem("Mug", 1000),))
        self.assertEqual(total_label(taxed), "Total: $11.03 (incl. tax $0.53)")
        self.assertEqual(total_label(untaxed), "Total: $10.00 (incl. tax $0.00)")

    def test_half_cent_of_tax_rounds_up_in_the_label(self):
        order = Order((LineItem("Pin", 30),), tax_bp=500)
        self.assertEqual(total_label(order), "Total: $0.32 (incl. tax $0.02)")
PY
python3 -m unittest tests.test_labels >/dev/null 2>&1
git add shopkit/labels.py tests/test_labels.py
git commit -q -m "feat: total_label"
node "$FLOW" tick T002

# gating: green, PASS for HEAD, gates ticked
python3 -m unittest discover -s tests >/dev/null 2>&1
SHA=$(git rev-parse --short HEAD)
cat >"$D/PASS-$SHA.md" <<MD
# PASS-$SHA

| Gate | Command | Exit |
|------|---------|------|
| G001 | python3 -m unittest discover -s tests | 0 |
| G002 | whole-branch review of Base..HEAD | 0 |
MD
node "$FLOW" tick G001
node "$FLOW" tick G002
git add "$D"
git commit -q -m "chore: PASS for $SHA, tick gates"
