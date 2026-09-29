#!/usr/bin/env bash
set -u
# The plan is repaired minimally (only T001/T002 lines may change, and only their
# [P] marker or after: list), nothing was built, and the router now says building.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-recipe-scaling
TASKS=$DIR/TASKS.md
fail() { echo "$1"; exit 1; }

[ -f "$TASKS" ] || fail "TASKS.md is gone"

PRISTINE=$(mktemp -d)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$PRISTINE" "$SCRATCH"' EXIT
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

node "$FLOW" lint "$TASKS" --json >"$SCRATCH/lint.json" 2>/dev/null
python3 - "$SCRATCH/lint.json" <<'PY' || fail "flow lint still reports errors"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY

python3 - "$PRISTINE/$TASKS" "$TASKS" <<'PY' || exit 1
import re, sys

old = open(sys.argv[1], encoding="utf-8").read().split("\n")
new = open(sys.argv[2], encoding="utf-8").read().split("\n")
if len(old) != len(new):
    print("TASKS.md gained or lost lines: the repair must be in place")
    sys.exit(1)


def core(line):
    line = line.replace(" [P] ", " ", 1)
    return re.sub(r" — after: [^—]*", "", line)


for a, b in zip(old, new):
    if a == b:
        continue
    m = re.match(r"- \[ \] (T00[12]) ", a)
    if not m:
        print("a line other than T001/T002 changed: " + a[:60])
        sys.exit(1)
    if core(a) != core(b):
        print("%s changed beyond its [P] marker or after: list" % m.group(1))
        sys.exit(1)
sys.exit(0)
PY

cmp -s "$DIR/spec.md" "$PRISTINE/$DIR/spec.md" || fail "spec.md changed"
cmp -s .specs/.current "$PRISTINE/.specs/.current" || fail ".specs/.current changed"
diff -r -q -x .git -x TASKS.md -x __pycache__ -x '*.pyc' .specs "$PRISTINE/.specs" >"$SCRATCH/sdiff.txt" 2>&1 ||
	fail "extra or changed file under .specs: $(head -1 "$SCRATCH/sdiff.txt")"
diff -r -q -x .git -x .specs -x __pycache__ -x '*.pyc' . "$PRISTINE" >"$SCRATCH/diff.txt" 2>&1 ||
	fail "source or tests changed (build attempted?): $(head -1 "$SCRATCH/diff.txt")"
[ -z "$(ls "$DIR" | grep -E '^(PASS-|FINISH)' )" ] || fail "an unexpected gate file was written"
grep -q '^Verified:' "$TASKS" && fail "Verified: written by the model"
grep -q -- '- \[x\]' "$TASKS" && fail "a task was ticked: nothing may be built this turn"
[ "$(git log --format=%H "$(git -C "$PRISTINE" rev-parse HEAD)".. -- app tests | wc -l)" -eq 0 ] ||
	fail "a commit touched app/ or tests/"

node "$FLOW" next --json --peek >"$SCRATCH/next.json" 2>/dev/null
python3 - "$SCRATCH/next.json" <<'PY' || fail "router is not at building"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "building" else 1)
PY
exit 0
