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
# T001 ticked against the pre-crash commit (no rebuild commit), the tree lints
# clean, and T002, if attempted, is built and ticked correctly.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-isbn-labels
TASKS=$DIR/TASKS.md
fail() { echo "$1"; exit 1; }

[ -f "$TASKS" ] || fail "TASKS.md is gone"

PRISTINE=$(mktemp -d)
trap 'rm -rf "$PRISTINE"' EXIT
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"
CRASH_SHA=$(git -C "$PRISTINE" rev-parse HEAD)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$PRISTINE" "$SCRATCH"' EXIT

node "$FLOW" lint "$TASKS" --json >"$SCRATCH/lint.json" 2>/dev/null
python3 - "$SCRATCH/lint.json" <<'PY' || fail "flow lint reports errors (a lying or malformed tick)"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY

line=$(grep -E '^- \[x\] T001 ' "$TASKS") || fail "T001 is not ticked"
sha=$(printf '%s\n' "$line" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
[ "$(git rev-parse "$sha^{commit}" 2>/dev/null)" = "$CRASH_SHA" ] ||
	fail "T001's done: sha $sha is not the pre-crash commit ($CRASH_SHA)"

n=$(git log --format=%H "$CRASH_SHA".. -- app/isbn.py tests/test_isbn.py | wc -l)
[ "$n" -eq 0 ] || fail "$n commit(s) touched T001's files after the pre-crash commit: T001 was rebuilt"
git diff --quiet "$CRASH_SHA" -- app/isbn.py tests/test_isbn.py || fail "T001's files differ from the pre-crash commit"

grep -q '^Verified:' "$TASKS" && fail "Verified: written by the model"
ls "$DIR"/PASS-*.md >/dev/null 2>&1 && fail "a PASS file exists before the gates"

python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite red"

cp "$CASE_DIR/hidden/test_t001_hidden.py" tests/_hidden_test_t001.py
python3 -m unittest tests._hidden_test_t001 >/dev/null 2>&1
rc=$?
rm -f tests/_hidden_test_t001.py
[ "$rc" -eq 0 ] || fail "hidden behaviour tests for normalize_isbn failed"

if grep -Eq '^- \[x\] T002 ' "$TASKS"; then
	grep -E '^- \[x\] T002 ' "$TASKS" | grep -Eq '— done: [0-9a-f]{7,40}' || fail "T002 ticked without a done: sha"
	[ -f tests/test_labels.py ] || fail "tests/test_labels.py is missing"
	code=$(grep -Ev '^[[:space:]]*#' app/labels.py)
	printf '%s\n' "$code" | grep -Eq 'from app\.support\.text import .*ellipsize|from app\.support import text|import app\.support\.text' || fail "app/labels.py does not import the ellipsize helper"
	printf '%s\n' "$code" | grep -Eq 'ellipsize\(' || fail "shelf_line does not call ellipsize"
	printf '%s\n' "$code" | grep -Eq 'normalize_isbn\(' || fail "shelf_line does not call normalize_isbn"
	printf '%s\n' "$code" | grep -Eq '\[ *: *(19|20) *\]|raise |isinstance|\.strip\(' && fail "app/labels.py hand-cuts the title or guards book fields"
	cp "$CASE_DIR/hidden/test_t002_hidden.py" tests/_hidden_test_t002.py
	python3 -m unittest tests._hidden_test_t002 >/dev/null 2>&1
	rc=$?
	rm -f tests/_hidden_test_t002.py
	[ "$rc" -eq 0 ] || fail "hidden behaviour tests for shelf_line failed"
	slop_check --all-lines --no-tools --files app/labels.py tests/test_labels.py || exit 1
else
	grep -Eq '^- \[ \] T002 ' "$TASKS" || fail "T002 line was rewritten"
	[ ! -e app/labels.py ] || fail "app/labels.py exists but T002 is not ticked"
	node "$FLOW" next --json --peek >"$SCRATCH/next.json" 2>/dev/null
	python3 - "$SCRATCH/next.json" <<'PY' || fail "router is not at building wave T002"
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if d.get("state") == "building" and (d.get("wave") or {}).get("ids") == ["T002"] else 1)
PY
fi
exit 0
