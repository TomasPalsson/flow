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
git init -q
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# ---- base commit: a small parcel-rate library, no rate tiers yet ----------
mkdir -p parcelly tests
printf '__pycache__/\n*.pyc\n.specs/.next-call-count\n' >.gitignore
cat >README.md <<'MD'
# parcelly

Shipping rate quotes for small parcels. Weights are integers in grams, money
is integer cents.

Run tests: `python3 -m unittest discover -s tests -v`
MD
cat >pyproject.toml <<'TOML'
# Tests: python3 -m unittest discover -s tests -v
[project]
name = "parcelly"
version = "0.0.0"
dependencies = []
TOML
: >parcelly/__init__.py
: >tests/__init__.py
cat >parcelly/parcel.py <<'PY'
from dataclasses import dataclass

ZONES = ("local", "national", "remote")


@dataclass(frozen=True)
class Parcel:
    weight_g: int
    zone: str = "local"

    def __post_init__(self):
        if self.weight_g <= 0:
            raise ValueError("weight_g must be positive")
        if self.zone not in ZONES:
            raise ValueError(f"unknown zone: {self.zone}")
PY
cat >parcelly/labels.py <<'PY'
def format_label(parcel, cents):
    out = "PARCEL"
    out = out + " " + str(parcel.weight_g) + "g"
    out = out + " / " + parcel.zone.upper()
    dollars = cents // 100
    rest = cents % 100
    if rest < 10:
        rest = "0" + str(rest)
    else:
        rest = str(rest)
    out = out + " / $" + str(dollars) + "." + rest
    return out
PY
cat >tests/test_labels.py <<'PY'
import unittest

from parcelly.labels import format_label
from parcelly.parcel import Parcel


class TestLabels(unittest.TestCase):
    def test_label_shows_weight_zone_and_price(self):
        self.assertEqual(format_label(Parcel(800, "remote"), 750), "PARCEL 800g / REMOTE / $7.50")
PY
git add -A
git commit -q -m "base: parcelly with Parcel and label printing"
BASE=$(git rev-parse --short HEAD)

# ---- T001: weight tiers ------------------------------------------------------
cat >parcelly/tiers.py <<'PY'
TIERS = [(1000, "light"), (5000, "medium")]


def tier_for(weight_g):
    for limit, name in TIERS:
        if weight_g < limit:
            return name
    return "heavy"
PY
cat >tests/test_tiers.py <<'PY'
import unittest

from parcelly.tiers import tier_for


class TestTiers(unittest.TestCase):
    def test_light_parcel(self):
        self.assertEqual(tier_for(400), "light")

    def test_medium_parcel(self):
        self.assertEqual(tier_for(3000), "medium")

    def test_heavy_parcel(self):
        self.assertEqual(tier_for(9000), "heavy")
PY
git add -A
git commit -q -m "feat: weight tiers"
S1=$(git rev-parse --short HEAD)

# ---- T002: quoting -----------------------------------------------------------
cat >parcelly/rates.py <<'PY'
from parcelly.tiers import tier_for

PRICE_CENTS = {"light": 500, "medium": 900, "heavy": 1500}
ZONE_SURCHARGE_CENTS = {"local": 0, "national": 100, "remote": 250}


def quote_cents(parcel):
    return PRICE_CENTS[tier_for(parcel.weight_g)] + ZONE_SURCHARGE_CENTS[parcel.zone]
PY
cat >tests/test_rates.py <<'PY'
import unittest

from parcelly.parcel import Parcel
from parcelly.rates import quote_cents


class TestRates(unittest.TestCase):
    def test_local_light(self):
        self.assertEqual(quote_cents(Parcel(400, "local")), 500)

    def test_national_medium(self):
        self.assertEqual(quote_cents(Parcel(3000, "national")), 1000)

    def test_remote_heavy(self):
        self.assertEqual(quote_cents(Parcel(9000, "remote")), 1750)
PY
git add -A
git commit -q -m "feat: quote_cents from tier and zone"
S2=$(git rev-parse --short HEAD)

# ---- T003: boundary and zone tests -------------------------------------------
cat >tests/test_boundaries.py <<'PY'
import unittest

from parcelly.parcel import Parcel
from parcelly.rates import quote_cents


class TestBoundaries(unittest.TestCase):
    def test_zone_surcharge(self):
        self.assertEqual(quote_cents(Parcel(800, "remote")), 750)

    def test_light_tier_includes_1000_g(self):
        self.assertEqual(quote_cents(Parcel(1000, "local")), 500)
PY
git add -A
git commit -q -m "test: boundary and zone cases"
S3=$(git rev-parse --short HEAD)

# ---- the feature dir: approved, every task ticked, gates open -------------------
D=.specs/001-parcel-rates
mkdir -p "$D"
printf '001-parcel-rates\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Parcel rates

**Created**: 2026-09-20 · **Route**: dispatch

## TL;DR

**Problem**: Support quotes parcel shipping prices by hand from a wiki table.

**Solution**: `quote_cents(parcel)` returns the price in cents from the parcel's weight tier and zone.

**Who it's for**: Support agents quoting customers.

## 2. Scope

### 2.2 Non-goals

- No carrier API calls, no currency other than cents.

## 4. Requirements

| ID | Priority | Requirement | Acceptance |
|----|----------|-------------|------------|
| FR-01 | MUST | Support agent gets a tier price: light 500, medium 900, heavy 1500 cents | AC1 |
| FR-02 | MUST | Weights up to and including 1000 g are light; up to and including 5000 g are medium; anything heavier is heavy | AC2 |
| FR-03 | MUST | Zones add a flat surcharge: local 0, national 100, remote 250 cents | AC3 |

## 6. Launch criteria

- [ ] AC1: a 400 g local parcel quotes 500; a 3000 g national parcel quotes 1000.
- [ ] AC2: a parcel of exactly 1000 g quotes the light price, exactly 5000 g the medium price.
- [ ] AC3: a remote surcharge of 250 is added to the tier price.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Parcel rates
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-21 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a parcel weight, when I ask for its tier, then light/medium/heavy comes back | T001 | test_light_parcel |
| B2 (P0) | Given a parcel, when I quote it, then tier price plus zone surcharge comes back | T002 | test_local_light |
| B3 (P0) | Given exactly 1000 g or 5000 g, when I quote it, then the lower tier's price applies | T003 | test_light_tier_includes_1000_g |

## Phase 1 — Quote a parcel
Goal: support can quote any parcel weight and zone in cents.
Independent test: \`python3 -m unittest tests.test_rates\` — green with the label printer untouched.
- [x] T001 Weight tiers (B1) — files: parcelly/tiers.py, tests/test_tiers.py — verify: \`python3 -m unittest tests.test_tiers.TestTiers.test_heavy_parcel\` — done: $S1
- [x] T002 Quote from tier and zone (B2) — files: parcelly/rates.py, tests/test_rates.py — verify: \`python3 -m unittest tests.test_rates\` — after: T001 — done: $S2
- [x] T003 Boundary and zone tests (B3) — files: tests/test_boundaries.py — verify: \`python3 -m unittest tests.test_boundaries.TestBoundaries.test_zone_surcharge\` — after: T002 — done: $S3

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
MD
git add -A
git commit -q -m "chore: feature dir for parcel rates"
