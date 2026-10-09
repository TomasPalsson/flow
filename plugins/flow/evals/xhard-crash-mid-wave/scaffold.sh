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
git init -q -b flow/isbn-labels
git config user.email "dev@example.com"
git config user.name "Dev"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare the pre-existing T001 commit sha.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app/support tests
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >app/support/__init__.py
: >tests/__init__.py
cat >app/books.py <<'PY'
from dataclasses import dataclass


@dataclass(frozen=True)
class Book:
    isbn: str
    title: str

    def __post_init__(self):
        if not self.isbn.strip():
            raise ValueError("isbn must not be blank")
        if not self.title.strip():
            raise ValueError("title must not be blank")
PY
cat >app/support/text.py <<'PY'
def ellipsize(text, limit):
    if len(text) <= limit:
        return text
    return text[: limit - 1] + "…"
PY
cat >app/catalog.py <<'PY'
def titles(books):
    return sorted(book.title for book in books)
PY
cat >tests/test_catalog.py <<'PY'
import unittest

from app.books import Book
from app.catalog import titles


class TestCatalog(unittest.TestCase):
    def test_titles_are_sorted(self):
        books = [Book("9780306406157", "Zed"), Book("9780306406157", "Abe")]
        self.assertEqual(titles(books), ["Abe", "Zed"])
PY
cat >README.md <<'MD'
# bookshelf

Catalog tooling for the library desk.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: bookshelf catalog skeleton"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-isbn-labels
printf '001-isbn-labels\n' >.specs/.current
cat >.specs/001-isbn-labels/spec.md <<'MD'
# Spec — ISBN labels

The desk prints one spine label line per book, always keyed by the 13-digit ISBN.

## Requirements
- R1: `normalize_isbn(raw)` in `app/isbn.py` returns the 13-digit ISBN as a string. It strips
  hyphens and spaces; an ISBN-10 is converted by prefixing `978` and recomputing the check digit.
- R2: `shelf_line(book)` in `app/labels.py` returns `<normalized isbn> <title cut to 20 characters>`.

## Acceptance
- A1: `0-306-40615-2` and `978-0-306-40615-7` both normalize to `9780306406157`.
- A2: a title longer than 20 characters is cut with a trailing ellipsis.
MD
cat >.specs/001-isbn-labels/TASKS.md <<TASKS
# Tasks — ISBN labels
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given an ISBN-10 or ISBN-13 with hyphens, when normalize_isbn runs, then the 13-digit ISBN comes back | T001 | test_isbn |
| B2 (P0) | Given a book with a long title, when shelf_line runs, then the ISBN and a title cut to 20 characters come back | T002 | test_labels |

## Phase 1 — Labels
Goal: the desk can print a spine label line for any book.
Independent test: \`python3 -m unittest discover -s tests\` — green.
- [ ] T001 normalize_isbn (B1) — files: app/isbn.py, tests/test_isbn.py — verify: \`python3 -m unittest tests.test_isbn\`
- [ ] T002 shelf_line (B2) — files: app/labels.py, tests/test_labels.py — verify: \`python3 -m unittest tests.test_labels\` — after: T001

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: isbn labels, approved"

# The crash: T001's code and test were committed, then the laptop died before `flow tick T001`.
cat >app/isbn.py <<'PY'
def normalize_isbn(raw):
    digits = raw.replace("-", "").replace(" ", "")
    if len(digits) == 13:
        return digits
    core = "978" + digits[:9]
    total = sum(int(d) * (1 if i % 2 == 0 else 3) for i, d in enumerate(core))
    return core + str((10 - total % 10) % 10)
PY
cat >tests/test_isbn.py <<'PY'
import unittest

from app.isbn import normalize_isbn


class TestNormalizeIsbn(unittest.TestCase):
    def test_isbn13_loses_its_hyphens(self):
        self.assertEqual(normalize_isbn("978-0-306-40615-7"), "9780306406157")

    def test_isbn10_is_converted(self):
        self.assertEqual(normalize_isbn("0-306-40615-2"), "9780306406157")
PY
commit "feat: normalize_isbn"
