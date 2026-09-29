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
git init -q -b flow/recipe-scaling
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
cat >app/recipes.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Ingredient:
    name: str
    grams: int

    def __post_init__(self):
        if not self.name.strip():
            raise ValueError("name must not be blank")
        if self.grams <= 0:
            raise ValueError("grams must be positive")


@dataclass(frozen=True)
class Recipe:
    title: str
    serves: int
    ingredients: tuple

    def __post_init__(self):
        if self.serves <= 0:
            raise ValueError("serves must be positive")
PY
cat >app/units.py <<'PY'
def grams_to_ounces(grams):
    return round(grams / 28.3495, 1)
PY
cat >app/render.py <<'PY'
def render_ingredient(ingredient):
    return "%dg %s" % (ingredient.grams, ingredient.name)
PY
cat >tests/test_render.py <<'PY'
import unittest

from app.recipes import Ingredient
from app.render import render_ingredient


class TestRender(unittest.TestCase):
    def test_ingredient_line(self):
        self.assertEqual(render_ingredient(Ingredient("flour", 250)), "250g flour")
PY
cat >README.md <<'MD'
# recipebox

Recipe cards for the community kitchen.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: recipebox skeleton"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-recipe-scaling
printf '001-recipe-scaling\n' >.specs/.current
cat >.specs/001-recipe-scaling/spec.md <<'MD'
# Spec — Recipe scaling

Cooks scale a recipe to the number of people they are feeding.

## Requirements
- R1: `scale_grams(grams, from_serves, to_serves)` in `app/scaling.py` returns the scaled amount,
  rounded to the nearest whole gram.
- R2: `scale_recipe(recipe, to_serves)` in `app/scaling.py` returns a new Recipe with every
  ingredient scaled and `serves` set to `to_serves`.
- R3: `render_scaled(recipe, to_serves)` in `app/cards.py` renders one line per scaled ingredient.
- R4: `scaling_note(recipe, to_serves)` in `app/notes.py` returns a one-line note such as `x2 (4 -> 8 servings)`.

## Acceptance
- A1: scaling 250 g from 4 to 8 servings gives 500 g.
- A2: the scaled recipe reports the new serving count.
MD
# T001 and T002 are both [P] and both own app/scaling.py: flow lint rejects the plan.
cat >.specs/001-recipe-scaling/TASKS.md <<TASKS
# Tasks — Recipe scaling
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given 250 g for 4 servings, when scaled to 8, then 500 g comes back | T001 | test_scale_grams |
| B2 (P0) | Given a recipe, when scale_recipe runs, then every ingredient is scaled and serves updated | T002 | test_scale_recipe |
| B3 (P1) | Given a recipe, when render_scaled runs, then one line per scaled ingredient comes back | T003 | test_cards |
| B4 (P2) | Given a recipe, when scaling_note runs, then a one-line multiplier note comes back | T004 | test_notes |

## Phase 1 — Scaling
Goal: a cook can scale a recipe and read the scaled card.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 [P] scale_grams (B1) — files: app/scaling.py, tests/test_scaling.py — verify: \`python3 -m unittest tests.test_scaling\`
- [ ] T002 [P] scale_recipe (B2) — files: app/scaling.py, tests/test_scale_recipe.py — verify: \`python3 -m unittest tests.test_scale_recipe\`
- [ ] T003 [P] render_scaled (B3) — files: app/cards.py, tests/test_cards.py — verify: \`python3 -m unittest tests.test_cards\` — after: T002
- [ ] T004 [P] scaling_note (B4) — files: app/notes.py, tests/test_notes.py — verify: \`python3 -m unittest tests.test_notes\` — after: T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: recipe scaling, approved"
