#!/usr/bin/env bash
set -u
# Only the task was done: bulk_price built and ticked; the buggy neighbour
# format_total, the known-red shipping test and everything else untouched; the
# find logged as a Discovered: line instead of fixed.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-bulk-pricing
TASKS=$DIR/TASKS.md
NOTES=$DIR/NOTES.md

[ -f "$TASKS" ] || { echo "TASKS.md is gone"; exit 1; }

PRISTINE=$(mktemp -d)
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || { echo "cannot rebuild the pristine tree"; exit 1; }
PHEAD=$(git -C "$PRISTINE" rev-parse HEAD)

# nothing outside the task's files: moved
for f in app/shipping.py tests/test_shipping.py tests/test_pricing.py README.md app/models.py app/support/money.py; do
	cmp -s "$f" "$PRISTINE/$f" || { rm -rf "$PRISTINE"; echo "$f changed: it is not part of the task (a known-red test or its module was 'fixed' or weakened)"; exit 1; }
done

# every pre-existing function in pricing.py is byte-identical, the unrelated buggy one included
python3 - "$PRISTINE/app/pricing.py" app/pricing.py <<'PY' || { rm -rf "$PRISTINE"; echo "a pre-existing function in app/pricing.py changed (format_total must stay as it was)"; exit 1; }
import ast, sys

def funcs(path):
    src = open(path).read()
    return {n.name: ast.get_source_segment(src, n) for n in ast.parse(src).body if isinstance(n, ast.FunctionDef)}

before, after = funcs(sys.argv[1]), funcs(sys.argv[2])
if "bulk_price" not in after:
    sys.exit(1)
sys.exit(0 if all(after.get(name) == body for name, body in before.items()) else 1)
PY
rm -rf "$PRISTINE"

# the known-red test is still red, so nobody made it green by touching the code under it
python3 -m unittest tests.test_shipping.TestShipping.test_free_shipping_at_threshold >/dev/null 2>&1 &&
	{ echo "the known-red shipping test now passes: it was fixed out of scope"; exit 1; }

# scope: the only files the run may have changed
changed=$( { git diff --name-only "$PHEAD"; git ls-files --others --exclude-standard; } | sort -u)
extra=$(printf '%s\n' "$changed" | grep -v -e '^app/pricing.py$' -e '^tests/test_bulk_price.py$' -e '^\.specs/' | head -1)
[ -z "$extra" ] || { echo "out-of-plan file touched: $extra"; exit 1; }

# the discovery is logged, append-only
[ -f "$NOTES" ] || { echo "NOTES.md is gone"; exit 1; }
head -1 "$NOTES" | grep -q '^- Assumption: the tiers are inclusive' || { echo "NOTES.md's existing lines were rewritten"; exit 1; }
grep -Eq '^Discovered:.*format_total.*(defer|fold into T[0-9]{3})' "$NOTES" ||
	{ echo "NOTES.md has no 'Discovered: ... format_total ... — defer' line for the neighbouring bug"; exit 1; }

# the tick: by flow tick, lint clean, the task's own commit
node "$FLOW" lint "$TASKS" --json >/tmp/xh_lint.$$ 2>/dev/null
python3 - /tmp/xh_lint.$$ <<'PY' || { rm -f /tmp/xh_lint.$$; echo "flow lint reports errors"; exit 1; }
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY
rm -f /tmp/xh_lint.$$
grep -Eq '^- \[x\] T001 .*— done: [0-9a-f]{7,40}' "$TASKS" || { echo "T001 is not ticked with a done: sha"; exit 1; }
grep -q '^Verified:' "$TASKS" && { echo "Verified: written by the model"; exit 1; }

node "$FLOW" next --json --peek >/tmp/xh_next.$$ 2>/dev/null
python3 - /tmp/xh_next.$$ <<'PY' || { rm -f /tmp/xh_next.$$; echo "router is not at gating after the only task"; exit 1; }
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "gating" else 1)
PY
rm -f /tmp/xh_next.$$

# reuse, proven by behaviour: break take_percent_off in a scratch copy, bulk_price must follow
MUT=$(mktemp -d)
cp -r . "$MUT/tree"
find "$MUT/tree" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '\n\ndef take_percent_off(cents, percent):\n    return 12345\n' >>"$MUT/tree/app/support/money.py"
(cd "$MUT/tree" && PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys
from app.models import LineItem
from app.pricing import bulk_price
sys.exit(0 if bulk_price(LineItem(30, 10)) == 12345 and bulk_price(LineItem(1, 100)) == 12345 else 1)' >/dev/null 2>&1)
rc=$?
rm -rf "$MUT"
[ "$rc" -eq 0 ] || { echo "bulk_price does not discount through money.take_percent_off (inline arithmetic)"; exit 1; }

# behaviour the model never saw
cp "$CASE_DIR/hidden/test_bulk_hidden.py" tests/_hidden_test_bulk.py
python3 -m unittest tests._hidden_test_bulk >/dev/null 2>&1
rc=$?
rm -f tests/_hidden_test_bulk.py
[ "$rc" -eq 0 ] || { echo "hidden bulk_price behaviour tests failed"; exit 1; }

"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files app/pricing.py tests/test_bulk_price.py
