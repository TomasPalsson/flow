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
# The one task is built, its own boundary bug (inclusive end) is absent, the tests pin the
# boundary (a mutation that re-introduces the bug turns them red), the far helper is reused,
# T001 is ticked with its own commit, and the run stopped at the gating state.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-booking-window
TASKS=$SPEC/TASKS.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f tests/_hidden_test_window.py' EXIT
fail() { echo "$1"; exit 1; }

[ -f "$TASKS" ] || fail "TASKS.md is gone"
[ -f inn/desk/window.py ] || fail "inn/desk/window.py is gone"
[ -f tests/test_window.py ] || fail "tests/test_window.py was never written"
mkdir "$TMP/pristine"
(cd "$TMP/pristine" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite red"

# behaviour the model never saw (the spec's half-open rule)
cp "$CASE_DIR/hidden/test_window_hidden.py" tests/_hidden_test_window.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests._hidden_test_window >/dev/null 2>&1 ||
	fail "hidden boundary tests fail: end must be exclusive, start inclusive, time of day ignored (the diff review missed the edge)"
rm -f tests/_hidden_test_window.py

# the model's own tests must bite: re-introduce the inclusive-end bug, they must go red
cp -r . "$TMP/mut"
find "$TMP/mut" -name __pycache__ -type d -prune -exec rm -rf {} +
cat >>"$TMP/mut/inn/desk/window.py" <<'PY'


def bookings_in_range(bookings, start, end):
    from datetime import date

    first, last = date.fromisoformat(str(start)[:10]), date.fromisoformat(str(end)[:10])
    return [b for b in bookings if first <= b.checkin.date() <= last]
PY
(cd "$TMP/mut" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests >/dev/null 2>&1) &&
	fail "the tests still pass with an inclusive end (no test pins the end boundary)"

# reuse, proven by behaviour: break the far helper in a scratch copy, the window must follow
rm -rf "$TMP/mut"
cp -r . "$TMP/mut"
find "$TMP/mut" -name __pycache__ -type d -prune -exec rm -rf {} +
printf '\n\ndef as_calendar_day(value):\n    raise RuntimeError("@@helper")\n' >>"$TMP/mut/inn/support/clock.py"
out=$(cd "$TMP/mut" && PYTHONDONTWRITEBYTECODE=1 python3 -c 'from datetime import datetime
from inn.desk.window import bookings_in_range
from inn.models import Booking
bookings_in_range([Booking("a", datetime(2026, 3, 4, 9, 0))], "2026-03-01", "2026-03-08")' 2>&1)
case "$out" in *@@helper*) ;; *) fail "bookings_in_range does not go through inn.support.clock.as_calendar_day (re-implemented the date handling)" ;; esac

# the far helper and every other pre-existing file stay as they were
while IFS= read -r f; do
	case "$f" in inn/desk/window.py | .specs/*) continue ;; esac
	cmp -s "$TMP/pristine/$f" "$f" || fail "$f was changed (only window.py and its test belong to T001)"
done < <(cd "$TMP/pristine" && git ls-files)

# T001 ticked through flow tick, with its own commit
node "$FLOW" lint "$TASKS" --json >"$TMP/lint.json" 2>/dev/null
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)' "$TMP/lint.json" ||
	fail "flow lint reports errors (a lying or malformed tick)"
grep -Eq '^- \[x\] T001 .*— done: [0-9a-f]{7,40}' "$TASKS" || fail "T001 is not ticked with a done: sha"
sha=$(grep -E '^- \[x\] T001 ' "$TASKS" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
git show --name-only --format= "$sha" | grep -Eq '^(inn/desk/window.py|tests/test_window.py)$' || fail "T001's done: sha $sha touched neither inn/desk/window.py nor tests/test_window.py"

# one state per turn: no gates run, no PASS, nothing human
grep -Eq '^- \[x\] G00' "$TASKS" && fail "a gate was ticked: the gating state belongs to the next turn"
ls "$SPEC"/PASS-*.md >/dev/null 2>&1 && fail "a PASS file exists: the gates were run in the same turn as the build"
grep -Eq '^Verified:' "$TASKS" && fail "Verified: written by the model"
state=$(node "$FLOW" next --json --peek 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$state" = "gating" ] || fail "router state is '$state', want gating"

slop_check --all-lines --no-tools --files inn/desk/window.py tests/test_window.py ||
	fail "slop-check flags window.py or its test"
exit 0
