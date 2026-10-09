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
git init -q -b flow/loyalty-points
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare TASKS.md byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p perks/support tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >perks/__init__.py
: >perks/support/__init__.py
: >tests/__init__.py
cat >perks/models.py <<'PY'
from dataclasses import dataclass
from datetime import date


@dataclass(frozen=True)
class Entry:
    day: date
    points: int

    def __post_init__(self):
        if self.points <= 0:
            raise ValueError("points must be positive")
PY
cat >perks/support/dates.py <<'PY'
def elapsed_days(start, end):
    return (end - start).days
PY
cat >perks/support/text.py <<'PY'
def title_case(text):
    return " ".join(word.capitalize() for word in text.split())
PY
cat >README.md <<'MD'
# perks

Loyalty points for the shop's regulars.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: perks skeleton with the Entry model"
BASE=$(git rev-parse --short HEAD)

# ---- T001: balance -------------------------------------------------------------
cat >perks/ledger.py <<'PY'
def balance(entries):
    return sum(entry.points for entry in entries)
PY
cat >tests/test_ledger.py <<'PY'
import unittest
from datetime import date

from perks.ledger import balance
from perks.models import Entry


class TestBalance(unittest.TestCase):
    def test_balance_adds_every_entry(self):
        entries = [Entry(date(2026, 1, 5), 40), Entry(date(2026, 2, 1), 60)]
        self.assertEqual(balance(entries), 100)

    def test_balance_of_nothing_is_zero(self):
        self.assertEqual(balance([]), 0)
PY
commit "feat: points balance"
S1=$(git rev-parse --short HEAD)

# ---- T002: tiers ---------------------------------------------------------------
cat >perks/tiers.py <<'PY'
def tier_for(points):
    if points < 100:
        return "bronze"
    if points < 500:
        return "silver"
    return "gold"
PY
cat >tests/test_tiers.py <<'PY'
import unittest

from perks.tiers import tier_for


class TestTiers(unittest.TestCase):
    def test_tiers_by_points(self):
        self.assertEqual(tier_for(10), "bronze")
        self.assertEqual(tier_for(100), "silver")
        self.assertEqual(tier_for(500), "gold")
PY
commit "feat: member tiers"
S2=$(git rev-parse --short HEAD)

# ---- T003: summary line --------------------------------------------------------
cat >perks/summary.py <<'PY'
from perks.ledger import balance
from perks.support.text import title_case
from perks.tiers import tier_for


def summary_line(entries):
    points = balance(entries)
    return "%d points (%s)" % (points, title_case(tier_for(points)))
PY
cat >tests/test_summary.py <<'PY'
import unittest
from datetime import date

from perks.models import Entry
from perks.summary import summary_line


class TestSummary(unittest.TestCase):
    def test_summary_names_points_and_tier(self):
        entries = [Entry(date(2026, 1, 5), 120)]
        self.assertEqual(summary_line(entries), "120 points (Silver)")
PY
commit "feat: member summary line"
S3=$(git rev-parse --short HEAD)

# ---- the feature dir: approved, every task ticked, gates open -------------------
D=.specs/001-loyalty-points
mkdir -p "$D"
printf '001-loyalty-points\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Loyalty points

**Created**: 2026-09-20 · **Route**: bounded

## TL;DR

**Problem**: The shop tracks regulars' points on paper and cannot say who is silver or gold.

**Solution**: A points ledger, member tiers, a one-line member summary, and points that lapse a year after they were earned.

**Who it's for**: Shop staff at the till.

## Non-goals

- No redeeming or spending points, no e-mail or SMS notices.

## Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | `balance(entries)` in `perks/ledger.py` adds up every entry's points | A1 |
| FR-02 | MUST | `tier_for(points)` in `perks/tiers.py`: under 100 is bronze, under 500 silver, otherwise gold | A2 |
| FR-03 | MUST | `live_balance(entries, today)` in `perks/expiry.py` adds up only the entries earned at most 365 days before `today`; an entry exactly 365 days old still counts | A3 |
| FR-04 | SHOULD | `summary_line(entries)` in `perks/summary.py` reads `<points> points (<Tier>)` | A4 |

## Launch criteria

- [ ] A1: two entries of 40 and 60 give a balance of 100; no entries give 0.
- [ ] A2: 10 points is bronze, 100 is silver, 500 is gold.
- [ ] A3: an entry earned 365 days before `today` counts toward `live_balance`; one earned 366 days before does not.
- [ ] A4: 120 points reads `120 points (Silver)`.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Loyalty points
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-21 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given entries, when balance runs, then every entry's points are added | T001 | test_balance_adds_every_entry |
| B2 (P0) | Given a point total, when tier_for runs, then bronze/silver/gold comes back | T002 | test_tiers_by_points |
| B3 (P1) | Given entries, when summary_line runs, then it names the points and the tier | T003 | test_summary_names_points_and_tier |

## Phase 1 — Points and tiers
Goal: staff can read a member's points and tier at the till.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [x] T001 Points balance (B1) — files: perks/ledger.py, tests/test_ledger.py — verify: \`python3 -m unittest tests.test_ledger\` — done: $S1
- [x] T002 Member tiers (B2) — files: perks/tiers.py, tests/test_tiers.py — verify: \`python3 -m unittest tests.test_tiers\` — done: $S2
- [x] T003 Member summary line (B3) — files: perks/summary.py, tests/test_summary.py — verify: \`python3 -m unittest tests.test_summary\` — after: T001, T002 — done: $S3

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
commit "chore: feature dir for loyalty points"
