#!/usr/bin/env bash
set -u
# slop-check with every finding fatal except NS-16 (advisory: spelling similarity only)
slop_check() {
	local out rc
	out=$("$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" "$@") || rc=$?
	[ "${rc:-0}" -eq 0 ] || { printf '%s\n' "$out"; return "$rc"; }
	out=$(printf '%s\n' "$out" | grep -v ': NS-16 ')
	[ -z "$out" ] || { printf '%s\n' "$out"; return 1; }
}
# Wave 1 (T001 + T002) built and ticked with each task's own commit; wave 2
# (T003) untouched and unticked; the tree lints clean and the far helper reused.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-low-stock-digest
TASKS=$DIR/TASKS.md

[ -f "$TASKS" ] || { echo "TASKS.md is gone"; exit 1; }

python3 -m unittest discover -s tests >/dev/null 2>&1 || { echo "suite red after wave 1"; exit 1; }

node "$FLOW" lint "$TASKS" --json >/tmp/xh_lint.$$ 2>/dev/null
python3 - /tmp/xh_lint.$$ <<'PY' || { rm -f /tmp/xh_lint.$$; echo "flow lint reports errors (a lying or malformed tick)"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("ok") else 1)
PY
rm -f /tmp/xh_lint.$$

grep -Eq '^- \[x\] T001 .*— done: [0-9a-f]{7,40}' "$TASKS" || { echo "T001 is not ticked with a done: sha"; exit 1; }
grep -Eq '^- \[x\] T002 .*— done: [0-9a-f]{7,40}' "$TASKS" || { echo "T002 is not ticked with a done: sha"; exit 1; }
grep -Eq '^- \[ \] T003 ' "$TASKS" || { echo "T003 was ticked or rewritten: wave 2 must not start"; exit 1; }
grep -E '^- \[ \] T003 ' "$TASKS" | grep -q 'done:' && { echo "T003 carries a done: sha"; exit 1; }

# each tick names the task's own commit, not whatever HEAD was
sha1=$(grep -E '^- \[x\] T001 ' "$TASKS" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
sha2=$(grep -E '^- \[x\] T002 ' "$TASKS" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
git show --name-only --format= "$sha1" | grep -q '^app/reports/low_stock.py$' || { echo "T001's done: sha $sha1 did not touch low_stock.py"; exit 1; }
git show --name-only --format= "$sha2" | grep -q '^app/reports/labels.py$' || { echo "T002's done: sha $sha2 did not touch labels.py"; exit 1; }

# wave 2 is untouched
PRISTINE=$(mktemp -d)
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || { echo "cannot rebuild the pristine tree"; exit 1; }
cmp -s app/reports/digest.py "$PRISTINE/app/reports/digest.py" || { rm -rf "$PRISTINE"; echo "app/reports/digest.py changed: T003 belongs to wave 2"; exit 1; }
rm -rf "$PRISTINE"
[ ! -e tests/test_digest.py ] || { echo "tests/test_digest.py exists: T003 belongs to wave 2"; exit 1; }

# no human fact written by the model
grep -q '^Verified:' "$TASKS" && { echo "Verified: written by the model"; exit 1; }
ls "$DIR"/PASS-*.md >/dev/null 2>&1 && { echo "a PASS file exists before the gates"; exit 1; }

# the router now names wave 2
node "$FLOW" next --json --peek >/tmp/xh_next.$$ 2>/dev/null
python3 - /tmp/xh_next.$$ <<'PY' || { rm -f /tmp/xh_next.$$; echo "router is not at building wave T003"; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
ok = d.get("state") == "building" and (d.get("wave") or {}).get("ids") == ["T003"]
sys.exit(0 if ok else 1)
PY
rm -f /tmp/xh_next.$$

# reuse, proven by behaviour: break ellipsize in a scratch copy, shelf_label must follow
MUT=$(mktemp -d)
cp -r . "$MUT/tree"
find "$MUT/tree" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '\n\ndef ellipsize(text, limit):\n    return "@@" + text\n' >>"$MUT/tree/app/support/text.py"
(cd "$MUT/tree" && PYTHONDONTWRITEBYTECODE=1 python3 -c 'import sys
from app.models import Item
from app.reports.labels import shelf_label
sys.exit(0 if "@@" in shelf_label(Item(1, "x" * 30, 1), 12) else 1)' >/dev/null 2>&1)
rc=$?
rm -rf "$MUT"
[ "$rc" -eq 0 ] || { echo "shelf_label does not go through app.support.text.ellipsize (re-implemented the cut)"; exit 1; }

# behaviour the model never saw
cp "$CASE_DIR/hidden/test_wave_hidden.py" tests/_hidden_test_wave.py
python3 -m unittest tests._hidden_test_wave >/dev/null 2>&1
rc=$?
rm -f tests/_hidden_test_wave.py
[ "$rc" -eq 0 ] || { echo "hidden behaviour tests failed for low_stock / shelf_label"; exit 1; }

slop_check --all-lines --no-tools --files app/reports/low_stock.py app/reports/labels.py tests/test_low_stock.py tests/test_labels.py
