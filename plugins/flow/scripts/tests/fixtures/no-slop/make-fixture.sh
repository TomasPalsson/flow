#!/usr/bin/env bash
# make-fixture.sh <dir> — builds a git repo for no-slop's slop-check tests:
# a "base" tag with clean src/text.py::slugify and src/util.ts::formatDate,
# then a HEAD commit that plants NS-03, 04, 05, 06, 08, 09, 10, 13, 15 for
# slop-check to find (see plugins/flow/skills/no-slop/references/rubric.md).
set -eu

dir=${1:?"usage: make-fixture.sh <dir>"}

mkdir -p "$dir/src" "$dir/tests"
cd "$dir"

git init -q
git config user.email "fixture@example.com"
git config user.name "no-slop fixture"
git config commit.gpgsign false

cat >src/text.py <<'EOF'
def slugify(value):
    return value.strip().lower().replace(" ", "-")
EOF

cat >src/util.ts <<'EOF'
export function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}
EOF

cat >tests/test_text.py <<'EOF'
import pytest


def test_slugify_lowercases_and_dashes():
    assert slugify("Hello World") == "hello-world"


def test_placeholder():
    assert True
EOF

git add -A
git commit -q -m "base: clean slugify + formatDate"
git tag base

# ---- HEAD: plant slop on top of the clean base ----

cat >>src/text.py <<'EOF'


def process(value):
    """
    Process the value.

    Returns the value unchanged.
    """
    return value


def slugify_legacy(value):  # kept for compat
    return value


def handle_request(payload):
    try:
        return payload.strip()
    except Exception:
        pass


def debug_dump(payload):
    print(payload)  # for now just debug
    return payload


def cast_value(value):
    result = value  # type: ignore
    return result
EOF

cat >>src/util.ts <<'EOF'


export function formatDateLegacy(d: Date): string {
  // added for the export flow
  return d.toISOString();
}
EOF

cat >tests/test_text.py <<'EOF'
import pytest


def test_slugify_lowercases_and_dashes():
    pass


def test_placeholder():
    assert True


@pytest.mark.skip(reason="flaky")
def test_process_returns_value():
    # assert process("x") == "x"
    pass
EOF

git add -A
git commit -q -m "HEAD: planted slop for slop-check to find"
