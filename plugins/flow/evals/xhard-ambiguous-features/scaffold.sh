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
cat >app/patients.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Patient:
    patient_id: int
    name: str
    species: str
PY
cat >app/visits.py <<'PY'
def visits_for(visits, patient_id):
    return [v for v in visits if v["patient_id"] == patient_id]
PY
cat >tests/test_visits.py <<'PY'
import unittest

from app.visits import visits_for


class TestVisits(unittest.TestCase):
    def test_filters_by_patient(self):
        visits = [{"patient_id": 1, "day": "mon"}, {"patient_id": 2, "day": "tue"}]
        self.assertEqual(visits_for(visits, 2), [{"patient_id": 2, "day": "tue"}])
PY
cat >README.md <<'MD'
# petclinic

Front-desk tooling for the vet clinic.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: petclinic skeleton"
BASE=$(git rev-parse --short HEAD)

# Two features, both planned and approved, neither current, on branch main.
mkdir -p .specs/001-vaccine-reminders .specs/002-invoice-export
cat >.specs/001-vaccine-reminders/spec.md <<'MD'
# Spec — Vaccine reminders

Owners get a reminder when a vaccine is due.

## Requirements
- R1: `due_reminders(patients, today)` in `app/reminders.py` lists the patients whose vaccine is due on or before `today`.
MD
cat >.specs/001-vaccine-reminders/TASKS.md <<TASKS
# Tasks — Vaccine reminders
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-20 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given patients with due dates, when due_reminders runs, then those due by today come back | T001 | test_reminders |

## Phase 1 — Reminders
Goal: the desk can list who is due a vaccine.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 due_reminders (B1) — files: app/reminders.py, tests/test_reminders.py — verify: \`python3 -m unittest tests.test_reminders\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
cat >.specs/002-invoice-export/spec.md <<'MD'
# Spec — Invoice export

Accounting wants a CSV of the day's invoices.

## Requirements
- R1: `invoice_rows(invoices)` in `app/invoices.py` returns one CSV row per invoice.
MD
cat >.specs/002-invoice-export/TASKS.md <<TASKS
# Tasks — Invoice export
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-27 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given invoices, when invoice_rows runs, then one CSV row per invoice comes back | T001 | test_invoices |

## Phase 1 — Export
Goal: accounting can export the day's invoices as CSV.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 invoice_rows (B1) — files: app/invoices.py, tests/test_invoices.py — verify: \`python3 -m unittest tests.test_invoices\`

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
printf -- '- Started here on 2026-09-27; accounting needs it by Friday.\n' >.specs/002-invoice-export/NOTES.md
commit "plans: vaccine reminders and invoice export, both approved"
