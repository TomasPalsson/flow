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
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every scaffold run produce the same shas, so a
# postcheck can compare a finished tree against a regenerated pristine one.
N=0
commit() {
	N=$((N + 1))
	local when
	when=$(printf '2026-09-%02dT10:00:00Z' $((10 + N)))
	GIT_AUTHOR_DATE=$when GIT_COMMITTER_DATE=$when git commit -q -m "$1"
}

# ---- base commit: a tiny notes tool, listing only -----------------------------
mkdir -p notekeep tests data
printf '__pycache__/\n*.pyc\n.specs/.next-call-count\n' >.gitignore
cat >README.md <<'MD'
# notekeep

A tiny notes lister. Notes live in a JSON-lines file, one object per line:
`{"title": "...", "tags": ["..."]}`.

Run tests: `python3 -m unittest discover -s tests -v`
Try it: `python3 -m notekeep data/sample.jsonl`
MD
cat >pyproject.toml <<'TOML'
# Tests: python3 -m unittest discover -s tests -v
[project]
name = "notekeep"
version = "0.0.0"
dependencies = []
TOML
: >notekeep/__init__.py
: >tests/__init__.py
cat >data/sample.jsonl <<'JSONL'
{"title": "Renew passport", "tags": ["errands", "Urgent"]}
{"title": "Draft Q4 roadmap", "tags": ["work"]}
{"title": "Buy oat milk", "tags": ["errands"]}
{"title": "Review pull request 41", "tags": ["work", "urgent"]}
JSONL
cat >notekeep/store.py <<'PY'
import json
from dataclasses import dataclass


@dataclass(frozen=True)
class Note:
    title: str
    tags: tuple = ()


def load_notes(path):
    if not isinstance(path, str):
        path = str(path)
    notes = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            try:
                raw = json.loads(line)
            except ValueError:
                continue
            notes.append(Note(raw["title"], tuple(raw.get("tags", []))))
    return notes
PY
cat >notekeep/tags.py <<'PY'
def normalize(tag):
    return tag.strip().lower()
PY
cat >tests/test_store.py <<'PY'
import unittest

from notekeep.store import load_notes


class TestStore(unittest.TestCase):
    def test_loads_every_sample_note(self):
        self.assertEqual(len(load_notes("data/sample.jsonl")), 4)
PY
git add -A
commit "base: notekeep store and tag normalising"
BASE=$(git rev-parse --short HEAD)

# ---- T001: find_by_tag --------------------------------------------------------
cat >notekeep/search.py <<'PY'
from notekeep.tags import normalize


def find_by_tag(notes, tag):
    want = normalize(tag)
    return [n for n in notes if want in (normalize(t) for t in n.tags)]
PY
cat >tests/test_search.py <<'PY'
import unittest

from notekeep.search import find_by_tag
from notekeep.store import load_notes


class TestSearch(unittest.TestCase):
    def setUp(self):
        self.notes = load_notes("data/sample.jsonl")

    def test_finds_notes_carrying_the_tag(self):
        self.assertEqual([n.title for n in find_by_tag(self.notes, "work")],
                         ["Draft Q4 roadmap", "Review pull request 41"])

    def test_tag_match_ignores_case(self):
        self.assertEqual(len(find_by_tag(self.notes, "URGENT")), 2)
PY
git add -A
commit "feat: find_by_tag"
S1=$(git rev-parse --short HEAD)

# ---- T002: --tag on the CLI ------------------------------------------------------
cat >notekeep/cli.py <<'PY'
import argparse

from notekeep.search import find_by_tag
from notekeep.store import load_notes


def main(argv=None):
    parser = argparse.ArgumentParser(prog="notekeep")
    parser.add_argument("path")
    parser.add_argument("--tag")
    args = parser.parse_args(argv)
    notes = load_notes(args.path)
    if args.tag:
        notes = find_by_tag(notes, args.tag)
    for note in notes:
        print(note.title)
    return 0
PY
cat >notekeep/__main__.py <<'PY'
from notekeep.cli import main

raise SystemExit(main())
PY
cat >tests/test_cli.py <<'PY'
import io
import unittest
from contextlib import redirect_stdout

from notekeep.cli import main


class TestCli(unittest.TestCase):
    def test_tag_flag_filters_the_listing(self):
        out = io.StringIO()
        with redirect_stdout(out):
            main(["data/sample.jsonl", "--tag", "errands"])
        self.assertEqual(out.getvalue().splitlines(), ["Renew passport", "Buy oat milk"])
PY
git add -A
commit "feat: --tag filter on the notekeep CLI"
S2=$(git rev-parse --short HEAD)

# ---- the feature dir: built, gated, PASS written, waiting on a human ---------------
D=.specs/001-tag-search
mkdir -p "$D/verify"
printf '001-tag-search\n' >.specs/.current
cat >"$D/spec.md" <<'MD'
# Spec: Tag search

**Created**: 2026-09-22 · **Route**: dispatch

## TL;DR

**Problem**: Finding every note about one topic means scrolling the whole list.

**Solution**: `notekeep <file> --tag <tag>` lists only the notes carrying that tag, ignoring case.

**Who it's for**: People who keep a notes file and read it from a terminal.

## 2. Scope

### 2.2 Non-goals

- No multi-tag queries, no tag editing.

## 6. Launch criteria

- [ ] AC1: `find_by_tag` returns exactly the notes carrying the tag.
- [ ] AC2: the match ignores case.
- [ ] AC3: `notekeep <file> --tag <tag>` prints only the matching titles.
MD
cat >"$D/TASKS.md" <<MD
# Tasks — Tag search
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-23 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given notes with tags, when I search a tag in any case, then only notes carrying it come back | T001 | test_tag_match_ignores_case |
| B2 (P0) | Given a notes file, when I run it with --tag, then only matching titles print | T002 | test_tag_flag_filters_the_listing |

## Phase 1 — Tag search
Goal: a person can list only the notes that carry one tag.
Independent test: \`python3 -m unittest tests.test_cli\` — green with the store untouched.
- [x] T001 find_by_tag (B1) — files: notekeep/search.py, tests/test_search.py — verify: \`python3 -m unittest tests.test_search\` — done: $S1
- [x] T002 --tag on the CLI (B2) — files: notekeep/cli.py, notekeep/__main__.py, tests/test_cli.py — verify: \`python3 -m unittest tests.test_cli\` — after: T001 — done: $S2

## Gates
- [x] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\` — done: $S2
- [x] G002 branch review clean — files: . — verify: \`flow pass\` — done: $S2
MD
cat >"$D/NOTES.md" <<'MD'
- Assumption: tags are compared case-insensitively (spec AC2).
- Discovered: load_notes silently skips malformed lines instead of reporting them — defer → I-001
MD
NO_COLOR=1 python3 -m unittest discover -s tests 2>&1 | sed 's/ in [0-9.]*s$/ in 0.001s/' >"$D/verify/test-run.txt"
python3 -m notekeep data/sample.jsonl --tag work >"$D/verify/cli-output.txt"
cat >"$D/verify/review.md" <<'MD'
# Whole-branch review (automated, fresh reviewer)

Verdict: approved, score 92/100. No finding at or above the keep threshold.
This is the machine review. It is not the human verification: nobody has
looked at this evidence yet.
MD
find . -name __pycache__ -type d -prune -exec rm -rf {} +
git add -A
commit "chore: feature dir for tag search, gates and evidence"
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$D/PASS-$HEAD_SHA.md" <<MD
# PASS-$HEAD_SHA

| Gate | Command | Exit |
|------|---------|------|
| G001 | python3 -m unittest discover -s tests | 0 |
| G002 | whole-branch review of Base..HEAD | 0 |
MD
git add -A
commit "chore: PASS for $HEAD_SHA"
