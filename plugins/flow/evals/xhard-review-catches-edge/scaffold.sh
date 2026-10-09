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
git init -q -b flow/booking-window
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

mkdir -p inn/support inn/reports inn/desk tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >inn/__init__.py
: >inn/support/__init__.py
: >inn/reports/__init__.py
: >inn/desk/__init__.py
: >tests/__init__.py
cat >inn/models.py <<'PY'
from dataclasses import dataclass
from datetime import datetime


@dataclass(frozen=True)
class Booking:
    guest: str
    checkin: datetime

    def __post_init__(self):
        if not self.guest.strip():
            raise ValueError("guest must not be blank")
PY
cat >inn/support/clock.py <<'PY'
from datetime import date, datetime


def as_calendar_day(value):
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    return date.fromisoformat(value)
PY
cat >inn/support/text.py <<'PY'
def initials(name):
    return "".join(part[0].upper() for part in name.split())
PY
cat >inn/reports/arrivals.py <<'PY'
from inn.support.clock import as_calendar_day


def arrivals_on(bookings, day):
    wanted = as_calendar_day(day)
    return [booking for booking in bookings if as_calendar_day(booking.checkin) == wanted]
PY
cat >inn/desk/roster.py <<'PY'
from inn.support.text import initials


def roster_line(booking):
    return "%s  %s" % (booking.checkin.strftime("%Y-%m-%d %H:%M"), initials(booking.guest))
PY
cat >inn/desk/window.py <<'PY'
def bookings_in_range(bookings, start, end):
    raise NotImplementedError("the desk window is built by T001")
PY
cat >tests/test_arrivals.py <<'PY'
import unittest
from datetime import datetime

from inn.models import Booking
from inn.reports.arrivals import arrivals_on


class TestArrivals(unittest.TestCase):
    def test_arrivals_on_a_day_ignore_the_time_of_day(self):
        bookings = [
            Booking("Ada Byron", datetime(2026, 3, 4, 9, 30)),
            Booking("Bo Chen", datetime(2026, 3, 5, 15, 0)),
        ]
        self.assertEqual([b.guest for b in arrivals_on(bookings, "2026-03-04")], ["Ada Byron"])
PY
cat >tests/test_roster.py <<'PY'
import unittest
from datetime import datetime

from inn.desk.roster import roster_line
from inn.models import Booking


class TestRoster(unittest.TestCase):
    def test_roster_line_has_time_and_initials(self):
        line = roster_line(Booking("Ada Byron", datetime(2026, 3, 4, 9, 30)))
        self.assertEqual(line, "2026-03-04 09:30  AB")
PY
cat >README.md <<'MD'
# inn

Front-desk tooling for a small inn.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: inn skeleton with bookings, arrivals and the roster"
BASE=$(git rev-parse --short HEAD)

D=.specs/001-booking-window
mkdir -p "$D"
printf '001-booking-window\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Booking window

**Created**: 2026-09-20 · **Route**: bounded

## TL;DR

**Problem**: The desk prints one arrivals sheet per day and staff add sheets up by hand to plan a week.

**Solution**: `bookings_in_range(bookings, start, end)` returns the bookings that check in inside a date range, so a weekly sheet is one call.

**Who it's for**: Front-desk staff planning a shift.

## Non-goals

- No check-out dates, no room numbers, no overlap logic for stays.

## Requirements

- R1: `bookings_in_range(bookings, start, end)` in `inn/desk/window.py` returns the bookings whose check-in falls in the range, in the order they were given.
- R2: `start` and `end` are calendar days, given as ISO strings (`"2026-03-01"`) or as dates. The time of day of a check-in never matters, only its calendar day.
- R3: The range is half-open, like the rota: a booking checking in on `start` is in; a booking checking in on `end` is out, at any time of that day, because that day belongs to the next range. So `start == end` is an empty range.

## Launch criteria

- [ ] A1: bookings in the middle of a range come back, bookings well outside it do not.
- [ ] A2: a check-in on `start` is in the range; a check-in on `end` (any time) is not.
- [ ] A3: an empty list gives an empty list; `start == end` gives an empty list.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Booking window
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-21 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given bookings across a fortnight, when bookings_in_range runs for one week, then the bookings inside that week come back in the order given | T001 | test_bookings_inside_the_range_come_back |

## Phase 1 — Weekly window
Goal: staff can pull every arrival of a date range in one call.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 Bookings in a date range (B1) — files: inn/desk/window.py, tests/test_window.py — verify: \`python3 -m unittest tests.test_window.TestWindow.test_bookings_inside_the_range_come_back\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
commit "plan: booking window, approved"
