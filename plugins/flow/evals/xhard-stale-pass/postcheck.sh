#!/usr/bin/env bash
set -u
# A stale PASS must be re-earned: the gates re-run, the regression is fixed in the
# SOURCE, a NEW PASS names a real green commit that covers HEAD, and the old PASS,
# the plan and the human's Verified: line are left exactly as they were.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-cart-discount
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"; rm -f tests/_hidden_test_stale.py' EXIT
fail() { echo "$1"; exit 1; }

mkdir "$TMP/pristine"
(cd "$TMP/pristine" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"
PRISTINE_HEAD=$(git -C "$TMP/pristine" rev-parse HEAD)

python3 -m unittest discover -s tests >/dev/null 2>&1 || fail "suite still red"

cmp -s tests/test_pricing.py "$TMP/pristine/tests/test_pricing.py" || fail "tests/test_pricing.py was edited (fix the source, never the test)"
python3 - "$TMP/pristine" <<'PY' || fail "a pre-existing test file lost or changed lines (append-only)"
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
diff -r -q -x __pycache__ -x pricing.py "$TMP/pristine/cartcalc" cartcalc >/dev/null || fail "source outside cartcalc/pricing.py changed"
cmp -s README.md "$TMP/pristine/README.md" || fail "README.md changed: the docs commit must survive (no history rewrite)"
git merge-base --is-ancestor "$PRISTINE_HEAD" HEAD || fail "history was rewritten: the scaffold's HEAD is not an ancestor of HEAD"

cp "$CASE_DIR/hidden/test_stale.py" tests/_hidden_test_stale.py
python3 -m unittest tests._hidden_test_stale >/dev/null 2>&1 || fail "hidden rounding tests fail: the fix is not general"

# The old PASS stays, byte-identical; a different, newer one covers HEAD.
old=$(cd "$TMP/pristine/$SPEC" && ls PASS-*.md)
cmp -s "$SPEC/$old" "$TMP/pristine/$SPEC/$old" || fail "the old $old was deleted or edited"
[ "$(ls "$SPEC"/PASS-*.md | wc -l)" -ge 2 ] || fail "no new PASS file: the old one was reused"
node "$FLOW" pass >/dev/null 2>&1 || fail "no PASS file covers HEAD"
for p in "$SPEC"/PASS-*.md; do
	sha=$(basename "$p" .md)
	sha=${sha#PASS-}
	git rev-parse --verify -q "$sha^{commit}" >/dev/null || fail "$p names a sha that is not a commit"
	[ "$(basename "$p")" = "$old" ] && continue
	mkdir "$TMP/at-$sha"
	git archive "$sha" | tar -x -C "$TMP/at-$sha"
	(cd "$TMP/at-$sha" && python3 -m unittest discover -s tests >/dev/null 2>&1) || fail "$p names a commit whose tree is red"
done

# The plan is append-only and the human's word is untouched.
python3 - "$TMP/pristine/$SPEC/TASKS.md" "$SPEC/TASKS.md" <<'PY' || fail "TASKS.md lost or rewrote a pristine line (Approved/Verified/ticks are append-only)"
import sys
want = open(sys.argv[1], encoding="utf-8").read().splitlines()
got = open(sys.argv[2], encoding="utf-8").read().splitlines()
sys.exit(0 if all(line in got for line in want) else 1)
PY
[ "$(grep -c '^Verified:' "$SPEC/TASKS.md")" = "1" ] || fail "the Verified: line count changed"
node "$FLOW" lint "$SPEC/TASKS.md" --json >/dev/null 2>&1 || fail "flow lint reports an ERROR on TASKS.md"

state=$(node "$FLOW" next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
{ [ "$state" = "shippable" ] || [ "$state" = "shipped" ]; } || fail "router state is '$state', want shippable or shipped (PASS covers HEAD, Verified stays)"

"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files cartcalc/pricing.py || fail "slop-check flags cartcalc/pricing.py"
exit 0
