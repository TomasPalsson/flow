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
git init -q -b flow/holiday-calendar
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare it byte for byte.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >tests/__init__.py
cat >app/entries.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Entry:
    employee: str
    day: str
    hours: float
PY
cat >app/totals.py <<'PY'
def total_hours(entries, employee):
    return sum(e.hours for e in entries if e.employee == employee)
PY
cat >tests/test_totals.py <<'PY'
import unittest

from app.entries import Entry
from app.totals import total_hours


class TestTotals(unittest.TestCase):
    def test_total_hours_per_employee(self):
        entries = [Entry("ada", "mon", 4.0), Entry("ada", "tue", 3.5), Entry("bo", "mon", 8.0)]
        self.assertEqual(total_hours(entries, "ada"), 7.5)
PY
cat >README.md <<'MD'
# timesheet

Timesheet totals for the payroll team.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: timesheet skeleton"
BASE=$(git rev-parse --short HEAD)

# 001 is approved and half built (its T001 is really done); 002 is the active feature.
mkdir -p .specs/001-overtime-report .specs/002-holiday-calendar
cat >app/overtime.py <<'PY'
def overtime_hours(entries, employee, weekly_limit=40.0):
    total = sum(e.hours for e in entries if e.employee == employee)
    return max(0.0, total - weekly_limit)
PY
cat >tests/test_overtime.py <<'PY'
import unittest

from app.entries import Entry
from app.overtime import overtime_hours


class TestOvertime(unittest.TestCase):
    def test_hours_above_the_limit_count(self):
        entries = [Entry("ada", "mon", 45.0)]
        self.assertEqual(overtime_hours(entries, "ada"), 5.0)
PY
commit "feat: overtime_hours"
DONE=$(git rev-parse --short HEAD)

cat >.specs/001-overtime-report/spec.md <<'MD'
# Spec — Overtime report

Payroll wants overtime per employee and a printable report.

## Requirements
- R1: `overtime_hours(entries, employee, weekly_limit=40.0)` in `app/overtime.py`.
- R2: `overtime_report(entries)` in `app/overtime_report.py` lists every employee with overtime.
MD
cat >.specs/001-overtime-report/TASKS.md <<TASKS
# Tasks — Overtime report
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-22 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given 45 hours, when overtime_hours runs, then 5 comes back | T001 | test_overtime |
| B2 (P0) | Given entries, when overtime_report runs, then employees with overtime are listed | T002 | test_overtime_report |

## Phase 1 — Overtime
Goal: payroll can see who worked overtime.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [x] T001 overtime_hours (B1) — files: app/overtime.py, tests/test_overtime.py — verify: \`python3 -m unittest tests.test_overtime\` — done: $DONE
- [ ] T002 overtime_report (B2) — files: app/overtime_report.py, tests/test_overtime_report.py — verify: \`python3 -m unittest tests.test_overtime_report\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
cat >.specs/002-holiday-calendar/spec.md <<'MD'
# Spec — Holiday calendar

Holidays do not count towards the weekly limit.

## Requirements
- R1: `is_holiday(day, holidays)` in `app/holidays.py` says whether a day is in the holiday set.
MD
cat >.specs/002-holiday-calendar/TASKS.md <<TASKS
# Tasks — Holiday calendar
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a holiday set, when is_holiday runs, then membership is reported | T001 | test_holidays |

## Phase 1 — Calendar
Goal: the code can tell a holiday from a working day.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 is_holiday (B1) — files: app/holidays.py, tests/test_holidays.py — verify: \`python3 -m unittest tests.test_holidays\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
printf '002-holiday-calendar\n' >.specs/.current
commit "plans: overtime report (in flight) and holiday calendar (current)"
