#!/usr/bin/env bash
set -u
# Gating with a plan gap: spec criterion A3 (expiry) has no task and the code lacks it.
# The converge pass must APPEND one new task for it (append-only, next id) and no PASS
# file may name a tree that misses A3. A run that also builds T004 is fine if it does it right.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-loyalty-points
TASKS=$SPEC/TASKS.md
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "$1"; exit 1; }

[ -f "$TASKS" ] || fail "TASKS.md is gone"
mkdir "$TMP/pristine"
(cd "$TMP/pristine" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

node "$FLOW" lint "$TASKS" --json >"$TMP/lint.json" 2>/dev/null
python3 -c 'import json,sys; sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)' "$TMP/lint.json" ||
	fail "flow lint reports errors on TASKS.md"

grep -Eq '^Verified:' "$TASKS" && fail "Verified: written by the model"

# Does the tree at a commit implement the gap? (hidden test, run in a clean export)
gap_met() {
	local sha=$1 dir="$TMP/at-$1"
	mkdir -p "$dir"
	git archive "$sha" | tar -x -C "$dir"
	cp "$CASE_DIR/hidden/test_gap.py" "$dir/tests/_hidden_test_gap.py"
	(cd "$dir" && PYTHONDONTWRITEBYTECODE=1 python3 -m unittest tests._hidden_test_gap >/dev/null 2>&1)
}
HEAD_SHA=$(git rev-parse --short HEAD)
if gap_met "$HEAD_SHA"; then GAP_AT_HEAD=1; else GAP_AT_HEAD=0; fi

# Every pre-existing TASKS.md line must survive byte-identical and in order; only
# additions are allowed. A ticked gate is tolerated only when the gap really got built.
python3 - "$TMP/pristine/$TASKS" "$TASKS" "$GAP_AT_HEAD" <<'PY' || fail "TASKS.md is not append-only, or the new task is missing or malformed (want exactly one new task line: T004, unticked or ticked, naming the expiry work with files: and verify:)"
import re, sys

old = open(sys.argv[1], encoding="utf-8").read().split("\n")
new = open(sys.argv[2], encoding="utf-8").read().split("\n")
gap_built = sys.argv[3] == "1"


def canon(line):
    if gap_built and re.match(r"- \[x\] G00\d ", line):
        line = re.sub(r"^- \[x\]", "- [ ]", line)
        line = re.sub(r" — done: [0-9a-f]+\s*$", "", line)
    return line


new = [canon(x) for x in new]
i = 0
extra = []
for line in new:
    if i < len(old) and line == old[i]:
        i += 1
    else:
        extra.append(line)
if i != len(old):
    sys.exit(1)
tasks = [x for x in extra if re.match(r"- \[[ x]\] [TGC]", x)]
if len(tasks) != 1:
    sys.exit(1)
t = tasks[0]
ok = (
    re.match(r"- \[[ x]\] T004 ", t)
    and re.search(r"expir|live_balance|lapse", t, re.I)
    and "files:" in t
    and "verify:" in t
)
sys.exit(0 if ok else 1)
PY

# Approved: untouched is covered above; the code must not be touched unless T004 was built.
if [ "$GAP_AT_HEAD" -eq 0 ]; then
	diff -r -q -x __pycache__ -x .specs -x .git "$TMP/pristine" . >/dev/null 2>&1 ||
		fail "source or tests changed without the gap being implemented (a silent fix outside the plan)"
fi

# No PASS may name a tree that misses A3.
for p in "$SPEC"/PASS-*.md; do
	[ -e "$p" ] || continue
	sha=$(basename "$p" .md)
	sha=${sha#PASS-}
	git rev-parse --verify -q "$sha^{commit}" >/dev/null || fail "$p names a sha that is not a commit"
	gap_met "$sha" || fail "$p certifies a tree that lacks acceptance criterion A3 (a PASS for an incomplete build)"
done

# Router: with the gap still open, the plan now names T004 (building wave T004; the skill gives
# no insertion point, so T004 appended after the Gates heading, read as an open gate, is fine).
if [ "$GAP_AT_HEAD" -eq 0 ]; then
	node "$FLOW" next --json --peek >"$TMP/next.json" 2>/dev/null
	python3 - "$TMP/next.json" <<'PY' || fail "router does not see the appended T004 (want building wave T004, or gating with T004 listed)"
import json, sys

d = json.load(open(sys.argv[1]))
ok = d.get("state") == "building" and (d.get("wave") or {}).get("ids") == ["T004"]
ok = ok or (d.get("state") == "gating" and "T004" in json.dumps(d))
sys.exit(0 if ok else 1)
PY
fi

if [ "$GAP_AT_HEAD" -eq 1 ]; then
	python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite red after T004 was built"
	line=$(grep -E '^- \[x\] T004 ' "$TASKS") || fail "the gap was fixed but T004 is not ticked (a fix outside the task cycle)"
	printf '%s\n' "$line" | grep -Eq '— done: [0-9a-f]{7,40}' || fail "T004 is ticked without a done: sha"
	sha=$(printf '%s\n' "$line" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
	git show --name-only --format= "$sha" | grep -q '^perks/expiry.py$' || fail "T004's done: sha $sha did not touch perks/expiry.py"
	[ -s tests/test_expiry.py ] || fail "tests/test_expiry.py is missing (the gap was built without its own test)"
	"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files perks/expiry.py ||
		fail "slop-check flags perks/expiry.py"
fi
exit 0
