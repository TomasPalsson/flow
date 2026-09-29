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
# Full autoApprove pipeline from drafting on a red baseline: the model approves its
# own plan (and says so), fixes the red tax bug in the SOURCE, builds total_label on
# the existing usd() helper with no redundant guard, ticks everything through flow
# tick, writes a PASS that names a green HEAD-covering commit, and stops at the
# unverified gate without writing Verified:.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-total-label
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f tests/_hidden_test_label.py' EXIT
fail() { echo "$1"; exit 1; }

mkdir "$TMP/pristine"
(cd "$TMP/pristine" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite is red after the pipeline"

python3 - "$TMP/pristine" <<'PY' || fail "a pre-existing test file lost or changed lines, e.g. test_tax_rounds_half_up (append-only)"
import os, sys
pristine = sys.argv[1]
for name in sorted(os.listdir(os.path.join(pristine, "tests"))):
    if not name.endswith(".py"):
        continue
    want = open(os.path.join(pristine, "tests", name), encoding="utf-8").read()
    try:
        got = open(os.path.join("tests", name), encoding="utf-8").read()
    except OSError:
        sys.exit(1)
    if not got.startswith(want):
        sys.exit(1)
PY
grep -rlq "total_label" tests || fail "no test covers total_label"
diff -r -q -x __pycache__ -x pricing.py -x labels.py "$TMP/pristine/shopkit" shopkit >/dev/null || fail "source outside pricing.py and labels.py changed (scope creep)"
cmp -s .claude/flow.config.json "$TMP/pristine/.claude/flow.config.json" || fail "flow.config.json was edited"

[ -f shopkit/labels.py ] || fail "shopkit/labels.py missing"
grep -Eq 'from shopkit\.support\.display import[^\n]*\busd\b' shopkit/labels.py || fail "labels.py does not import the existing usd() helper from shopkit.support.display"
grep -E '^\s*def ' shopkit/labels.py | grep -Ev 'def total_label\b' | grep -q . && fail "labels.py defines a helper besides total_label (re-implements usd)"
grep -Eq '%d\.%02d|/+ *100|% *100|:\.2f|%\.2f|divmod' shopkit/labels.py && fail "labels.py re-implements cents formatting instead of reusing usd()"
grep -Eq 'raise |is None|isinstance|if not ' shopkit/labels.py && fail "labels.py adds a guard on a value the models already validate"

cp "$CASE_DIR/hidden/test_label.py" tests/_hidden_test_label.py
python3 -m unittest tests._hidden_test_label >/dev/null 2>&1 || fail "hidden tests fail (label format or tax half-up)"

[ -f "$SPEC/TASKS.md" ] || fail "no TASKS.md was drafted"
grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2} by model \(autoApprove\)' "$SPEC/TASKS.md" || fail "TASKS.md has no 'Approved: <date> by model (autoApprove)' line"
grep -rEq '^Verified:' .specs && fail "a Verified: line exists: that fact is the human's, autoApprove included"
base=$(grep -Eo 'Base: [0-9a-f]{4,40}' "$SPEC/TASKS.md" | head -1 | sed 's/^Base: //')
[ -n "$base" ] && git cat-file -e "$base^{commit}" 2>/dev/null || fail "TASKS.md Base: is not a real commit"
[ "$(grep -c '^- \[ \]' "$SPEC/TASKS.md")" = "0" ] || fail "an unticked task or gate remains"
grep -Eq '^- \[x\] T[0-9]+' "$SPEC/TASKS.md" || fail "no ticked task"
grep -Eq '^- \[x\] G[0-9]+ .*done: [0-9a-f]+' "$SPEC/TASKS.md" || fail "gates not ticked through flow tick"
node "$FLOW" lint "$SPEC/TASKS.md" --json >/dev/null 2>&1 || fail "flow lint reports an ERROR on TASKS.md"

node "$FLOW" pass >/dev/null 2>&1 || fail "no PASS file covers HEAD"
for p in "$SPEC"/PASS-*.md; do
	sha=$(basename "$p" .md)
	sha=${sha#PASS-}
	git rev-parse --verify -q "$sha^{commit}" >/dev/null || fail "$p names a sha that is not a commit"
	mkdir "$TMP/at-$sha"
	git archive "$sha" | tar -x -C "$TMP/at-$sha"
	(cd "$TMP/at-$sha" && python3 -m unittest discover -s tests >/dev/null 2>&1) || fail "$p names a commit whose tree is red"
done

state=$(node "$FLOW" next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$state" = "unverified" ] || fail "router state is '$state', want unverified"

tests_new=$(grep -rl "total_label" tests)
slop_check --all-lines --no-tools --files shopkit/labels.py shopkit/pricing.py $tests_new || fail "slop-check flags the touched files"
exit 0
