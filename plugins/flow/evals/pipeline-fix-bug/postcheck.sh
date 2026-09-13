#!/usr/bin/env bash
set -u
# pipeline-fix-bug's scaffold.sh commits once ("base: posts app with
# slugify, format_cents (buggy), Post") and never tags it "base" - the
# scaffold's own root commit is that base, regardless of how many commits
# the run adds on top, so this resolves it directly instead of assuming a
# ref name.
BASE_SHA=$(git rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)
if [ -z "$BASE_SHA" ]; then
	echo "postcheck: could not resolve the scaffold's base commit"
	exit 1
fi

# The fixture is stdlib-runnable (README/pyproject: `python3 -m unittest
# discover -s tests`), so the same command the model is told to use is the
# one that judges it; a pytest-style `def test_*` module would be invisible
# to discover, which the money-test-* graders and the mutation below catch.
run_tests() {
	python3 -m unittest discover -s tests >/dev/null 2>&1
}

run_tests || { echo "suite red after fix"; exit 1; }

fixed=$(mktemp)
cp src/money.py "$fixed"
git show "$BASE_SHA":src/money.py >src/money.py # re-introduce the bug

if run_tests; then
	echo "new test does not catch the bug"
	cp "$fixed" src/money.py
	rm -f "$fixed"
	exit 1
fi

cp "$fixed" src/money.py
rm -f "$fixed"
echo "test bites"
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files src/money.py $(ls tests/test_money*.py)
