#!/usr/bin/env bash
# What a perfect stale-pass run leaves: the gates re-run (red), the regression fixed
# in the SOURCE, a NEW PASS-<HEAD>.md beside the untouched old one, TASKS.md and the
# human's Verified: line untouched.
set -euo pipefail
SPEC=.specs/001-cart-discount

if python3 -m unittest discover -s tests >/dev/null 2>&1; then
	echo "solution.sh: expected the scaffold's suite to be red" >&2
	exit 1
fi
cat >cartcalc/pricing.py <<'PY'
def discount_cents(subtotal_cents, percent):
    return (subtotal_cents * percent + 50) // 100
PY
python3 -m unittest discover -s tests >/dev/null 2>&1
git add cartcalc/pricing.py
git commit -q -m "fix: half-cent discounts round up again (round() rounds half to even)"
SHA=$(git rev-parse --short HEAD)

cat >"$SPEC/PASS-$SHA.md" <<MD
# PASS-$SHA

Re-run after the stale PASS: the suite was red at HEAD (round() in discount_cents).

| Gate | Command | Exit |
|------|---------|------|
| G001 | python3 -m unittest discover -s tests | 0 |
| G002 | whole-branch review of Base..HEAD, one finding (banker's rounding), fixed | 0 |
MD
git add "$SPEC/PASS-$SHA.md"
git commit -q -m "chore: PASS for $SHA"
