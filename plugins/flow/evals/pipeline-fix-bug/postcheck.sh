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

# The scaffold's pyproject.toml declares pytest, and the fixture's tests use
# plain test_* functions (not unittest.TestCase), which `unittest discover`
# cannot see at all - it would report "0 tests, OK" regardless of the bug,
# so pytest (or uvx pytest, when pytest itself is not importable) is the
# real runner here; unittest discover is a last-resort fallback only.
run_tests() {
	if python3 -c 'import pytest' >/dev/null 2>&1; then
		python3 -m pytest -q tests >/dev/null 2>&1
	elif command -v uvx >/dev/null 2>&1; then
		uvx --quiet pytest -q tests >/dev/null 2>&1
	else
		python3 -m unittest discover -s tests >/dev/null 2>&1
	fi
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
