#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q -b main
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare the private plan byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p pantry/support tests
cat >.gitignore <<'TXT'
__pycache__/
TXT
: >pantry/__init__.py
: >pantry/support/__init__.py
: >tests/__init__.py
cat >pantry/models.py <<'PY'
from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True)
class Item:
    name: str
    qty: int
    unit: str
    expires: date

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if self.qty < 0:
            raise ValueError("qty must not be negative")
        if not isinstance(self.expires, date):
            raise TypeError("expires must be a date")
PY
cat >pantry/support/calendar_math.py <<'PY'
from datetime import datetime


def _day(value):
    return value.date() if isinstance(value, datetime) else value


def span_days(start, end):
    """Whole calendar days from start to end; negative when end comes first.

    Either side may be a date or a datetime: the time of day never counts.
    """
    return (_day(end) - _day(start)).days
PY
cat >pantry/support/wording.py <<'PY'
def count_noun(n, noun):
    return "%d %s" % (n, noun if n == 1 else noun + "s")
PY
cat >pantry/support/textfmt.py <<'PY'
def squash_spaces(text):
    return " ".join(text.split())


def truncate(text, limit):
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"
PY
cat >pantry/store.py <<'PY'
import json
from datetime import date

from pantry.models import Item


def load_items(path):
    with open(path) as fh:
        rows = json.load(fh)
    return [
        Item(r["name"], r["qty"], r["unit"], date.fromisoformat(r["expires"]))
        for r in rows
    ]
PY
cat >pantry/cli.py <<'PY'
import sys

from pantry.store import load_items
from pantry.support.textfmt import squash_spaces


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    items = load_items(argv[0])
    for item in items:
        sys.stdout.write(squash_spaces("%s %d %s" % (item.name, item.qty, item.unit)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY
cat >tests/test_models.py <<'PY'
import unittest
from datetime import date

from pantry.models import Item


class TestItem(unittest.TestCase):
    def test_blank_name_is_rejected(self):
        with self.assertRaises(ValueError):
            Item(" ", 1, "kg", date(2026, 1, 1))
PY
cat >tests/test_calendar_math.py <<'PY'
import unittest
from datetime import date, datetime

from pantry.support.calendar_math import span_days


class TestSpanDays(unittest.TestCase):
    def test_counts_calendar_days_ignoring_time(self):
        self.assertEqual(span_days(datetime(2026, 3, 1, 23, 0), date(2026, 3, 2)), 1)
PY
cat >tests/test_wording.py <<'PY'
import unittest

from pantry.support.wording import count_noun


class TestCountNoun(unittest.TestCase):
    def test_one_is_singular(self):
        self.assertEqual(count_noun(1, "jar"), "1 jar")
PY
cat >README.md <<'MD'
# pantry

Kitchen inventory helpers: what is in stock and when it goes off.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: pantry inventory skeleton"
BASE=$(git rev-parse --short HEAD)

# ---- stealth: .specs is an untracked symlink into a private store repo outside
# this tree. Hand-built here (the state `flow stealth` leaves): the store repo,
# the link, the local exclude, and the two marked git hooks.
STORE="${HOME:?}/.flow/stealth/pantry-3f9a1c"
FEAT="$STORE/.specs/001-expiry-alerts"
# A reused HOME already holds this store from an earlier scaffold: start it clean, or the
# final store commit has nothing to commit and set -e aborts the scaffold.
rm -rf "$STORE"
mkdir -p "$FEAT"
chmod 700 "$HOME/.flow" "$HOME/.flow/stealth" "$STORE" 2>/dev/null || true
git init -q -b main "$STORE"
git -C "$STORE" config user.email "eval@example.com"
git -C "$STORE" config user.name "eval-scaffold"
git -C "$STORE" config commit.gpgsign false
printf '.current\n.next-call-count\n' >"$STORE/.specs/.gitignore"
printf '001-expiry-alerts\n' >"$STORE/.specs/.current"
ln -s "$STORE/.specs" .specs
printf '.specs\n.claude/\nCLAUDE.local.md\nPROGRESS.md\nREVIEW.md\n' >>.git/info/exclude

cat >.git/hooks/post-checkout <<HOOK
#!/bin/sh
# flow-stealth: git worktree add never copies untracked files; re-link the private specs
top=\$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
[ -e "\$top/.specs" ] || [ -L "\$top/.specs" ] || ln -s '$STORE/.specs' "\$top/.specs" 2>/dev/null
exit 0
HOOK
cat >.git/hooks/commit-msg <<'HOOK'
#!/bin/sh
# flow-stealth: this repo must not learn about the private specs
hit=$(grep -v '^#' "$1" | grep -Eo '\.specs/|TASKS\.md|PASS-[0-9a-f]{7,}|Ruling:|/flow:|flow (tick|lint|stealth)|001-expiry-alerts|(^|[^A-Za-z0-9_])(T|CHK|G)[0-9]{3}([^A-Za-z0-9_]|$)' | head -1)
if [ -n "$hit" ]; then
	echo "commit-msg (flow stealth): \"$hit\" names a private spec - describe the change for the maintainers instead" >&2
	exit 1
fi
exit 0
HOOK
chmod +x .git/hooks/post-checkout .git/hooks/commit-msg

cat >"$FEAT/spec.md" <<'MD'
# Spec — Expiry alerts

The kitchen wants to see what is about to go off.

## Requirements
- R1: `expiring_within(items, today, days)` in `pantry/alerts.py` returns the items that
  expire from `today` up to and including `today + days` days, soonest first, ties broken
  by name. Items already expired are left out. `today` is whatever the caller has: a date
  or a datetime.
- R2: `digest_line(item, today)` in `pantry/digest.py` returns one line per item:
  `<name>: expires today`, `<name>: expires in 1 day`, `<name>: expires in N days`, or
  `<name>: expired N days ago` (`expired 1 day ago` for one). Same `today` rule as R1.

## Acceptance
- A1: an item expiring exactly `days` days out is included; one a day later is not.
- A2: results come back soonest first, ties by name; expired items never appear.
- A3: a digest line reads as R2 for today, one day, many days, and already expired.
MD
cat >"$FEAT/TASKS.md" <<TASKS
# Tasks — Expiry alerts
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given items with varied expiry, when expiring_within(items, today, 3) runs, then only items expiring today through 3 days out come back, soonest first, ties by name | T001 | test_expiring_within |
| B2 (P0) | Given an item and today, when digest_line runs, then the line says expires today, in 1 day, in N days or expired N days ago | T002 | test_digest_line |

## Phase 1 — Alerts
Goal: the kitchen can list what is about to expire and print one line per item.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 [P] expiring_within filter (B1) — files: pantry/alerts.py, tests/test_alerts.py — verify: \`python3 -m unittest tests.test_alerts\`
- [ ] T002 [P] digest_line wording (B2) — files: pantry/digest.py, tests/test_digest.py — verify: \`python3 -m unittest tests.test_digest\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
TASKS
git -C "$STORE" add -A
git -C "$STORE" commit -q -m "expiry-alerts: plan approved"

# The eval sandbox masks /bin/git: hand the model a copy it may run outside the sandbox.
