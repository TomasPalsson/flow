#!/usr/bin/env bash
# test-prefilter.sh — mechanical leads for the audit tests agent (Phase 0).
# Usage: test-prefilter.sh [dir]
# Prints, relative to dir:
#   NO_ASSERTION:<file>          test file with no assertion-like call
#   NEAR_DUPLICATE:<a> <b>       two test files identical after whitespace
#                                normalisation (first in sort order is <a>)
# These are leads for the tests agent, not verdicts: a test may assert through
# a helper this grep does not know. Always exits 0.
set -uo pipefail

DIR="${1:-.}"
cd "$DIR" || exit 0

files=$(find . \( -name node_modules -o -name .git -o -name vendor -o -name .venv -o -name dist \) -prune -o \
  -type f \( -name '*.test.*' -o -name '*.spec.*' -o -name 'test_*.py' -o -name '*_test.py' -o -name '*_test.go' \) -print |
  sed 's|^\./||' | LC_ALL=C sort)

[ -n "$files" ] || exit 0

ASSERT_RE='assert|expect|should|t\.(Error|Fatal|Fail)|pytest\.raises|toThrow|toMatch'

printf '%s\n' "$files" | while IFS= read -r f; do
  grep -Eq "$ASSERT_RE" "$f" 2>/dev/null || echo "NO_ASSERTION:$f"
done

printf '%s\n' "$files" | while IFS= read -r f; do
  sum=$(tr -s ' \t\r\n' ' ' <"$f" | cksum | cut -d' ' -f1,2)
  printf '%s %s\n' "$sum" "$f"
done | LC_ALL=C sort | awk '
  { key = $1 " " $2; file = substr($0, length($1) + length($2) + 3)
    if (key == prev) { print "NEAR_DUPLICATE:" first " " file } else { first = file }
    prev = key }'
exit 0
