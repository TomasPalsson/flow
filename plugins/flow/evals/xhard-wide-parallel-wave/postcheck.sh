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
# Wave 1 (T001-T004) built and ticked, each with a commit touching its own files; wave 2
# (T005) untouched; every formatter goes through the shared fit_right helper (no copies);
# hidden behaviour tests pass; nothing human or gate-shaped was written.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-cell-formats
TASKS=$SPEC/TASKS.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f tests/_hidden_test_cells.py' EXIT
fail() { echo "$1"; exit 1; }

[ -f "$TASKS" ] || fail "TASKS.md is gone"
mkdir "$TMP/pristine"
(cd "$TMP/pristine" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite red after wave 1"

node "$FLOW" lint "$TASKS" --json >"$TMP/lint.json" 2>/dev/null
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)' "$TMP/lint.json" ||
	fail "flow lint reports errors (a lying or malformed tick)"

# ticks: each of T001-T004 through flow tick, naming a commit that touched ITS module
shas=""
for pair in T001:money T002:percent T003:duration T004:filesize; do
	id=${pair%%:*}
	mod=${pair##*:}
	line=$(grep -E "^- \[x\] $id " "$TASKS") || fail "$id is not ticked"
	printf '%s\n' "$line" | grep -Eq '— done: [0-9a-f]{7,40}' || fail "$id is ticked without a done: sha"
	sha=$(printf '%s\n' "$line" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
	git show --name-only --format= "$sha" | grep -q "^cells/fmt/$mod.py$" || fail "$id's done: sha $sha did not touch cells/fmt/$mod.py"
	[ -s "tests/test_$mod.py" ] || fail "tests/test_$mod.py is missing or empty"
	shas="$shas $sha"
done
[ "$(printf '%s\n' $shas | sort -u | wc -l)" -eq 4 ] || fail "T001-T004 do not carry four distinct done: shas (one combined commit)"

# wave 2 stays untouched
grep -Eq '^- \[ \] T005 ' "$TASKS" || fail "T005 was ticked or rewritten: wave 2 must not start"
grep -E '^- \[ \] T005 ' "$TASKS" | grep -q 'done:' && fail "T005 carries a done: sha"
cmp -s cells/fmt/row.py "$TMP/pristine/cells/fmt/row.py" || fail "cells/fmt/row.py changed: T005 belongs to wave 2"
[ ! -e tests/test_row.py ] || fail "tests/test_row.py exists: T005 belongs to wave 2"

# nothing gate-shaped or human
grep -Eq '^- \[x\] G00' "$TASKS" && fail "a gate was ticked in the building turn"
ls "$SPEC"/PASS-*.md >/dev/null 2>&1 && fail "a PASS file exists before the gates"
grep -Eq '^Verified:' "$TASKS" && fail "Verified: written by the model"

state_json=$(node "$FLOW" next --json --peek 2>/dev/null)
printf '%s' "$state_json" | python3 -c 'import json,sys
d = json.load(sys.stdin)
sys.exit(0 if d.get("state") == "building" and (d.get("wave") or {}).get("ids") == ["T005"] else 1)' ||
	fail "router is not at building wave T005"

# pre-existing files (the shared helper included) are unchanged; only new files were added
while IFS= read -r f; do
	case "$f" in cells/fmt/row.py | .specs/*) continue ;; esac
	cmp -s "$TMP/pristine/$f" "$f" || fail "$f was changed (wave 1 only adds the four formatters and their tests)"
done < <(cd "$TMP/pristine" && git ls-files)

# reuse, proven by behaviour: break fit_right in a scratch copy, all four cells must follow
cp -r . "$TMP/mut"
find "$TMP/mut" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '\n\ndef fit_right(text, width):\n    return "@@" + text\n' >>"$TMP/mut/cells/support/layout.py"
out=$(cd "$TMP/mut" && PYTHONDONTWRITEBYTECODE=1 python3 -c 'from cells.fmt.money import format_money
from cells.fmt.percent import format_percent
from cells.fmt.duration import format_duration
from cells.fmt.filesize import format_size
for name, cell in (("money", format_money(123456)), ("percent", format_percent(0.5)),
                   ("duration", format_duration(725)), ("filesize", format_size(1536))):
    print(name, "@@" in cell)' 2>&1)
for name in money percent duration filesize; do
	printf '%s\n' "$out" | grep -q "^$name True$" || fail "$name does not go through cells.support.layout.fit_right (re-implemented the cell fit)"
done

# the model's own tests must bite: make fit_right never cut, each formatter's test module must go red
rm -rf "$TMP/mut"
cp -r . "$TMP/mut"
find "$TMP/mut" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '\n\ndef fit_right(text, width):\n    return text.rjust(width)\n' >>"$TMP/mut/cells/support/layout.py"
for mod in money percent duration filesize; do
	(cd "$TMP/mut" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest "tests.test_$mod" >/dev/null 2>&1) &&
		fail "tests/test_$mod.py still passes when fit_right never cuts (no test pins the narrow-cell cut)"
done

# no copies: no three consecutive identical code lines shared by two formatters
python3 - <<'PY' || fail "two formatters share a copied block of three or more lines (the shared helper exists)"
import itertools, re, sys

names = ["money", "percent", "duration", "filesize"]
blocks = {}
for name in names:
    lines = [ln.strip() for ln in open("cells/fmt/%s.py" % name, encoding="utf-8")]
    lines = [ln for ln in lines if ln and not re.match(r"(from|import) ", ln)]
    blocks[name] = {tuple(lines[i:i + 3]) for i in range(len(lines) - 2)}
for a, b in itertools.combinations(names, 2):
    if blocks[a] & blocks[b]:
        sys.exit(1)
PY

# behaviour the model never saw
cp "$CASE_DIR/hidden/test_cells_hidden.py" tests/_hidden_test_cells.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests._hidden_test_cells >/dev/null 2>&1 || fail "hidden behaviour tests failed for the four formatters"
rm -f tests/_hidden_test_cells.py

slop_check --all-lines --no-tools --files \
	cells/fmt/money.py cells/fmt/percent.py cells/fmt/duration.py cells/fmt/filesize.py ||
	fail "slop-check flags the new formatter modules"
exit 0
