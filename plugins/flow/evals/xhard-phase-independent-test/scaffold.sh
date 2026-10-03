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
git init -q -b flow/rows-dedupe
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false

# Fixed commit dates make every sha reproducible, so a postcheck can rebuild the
# pristine tree and compare files against it.
_n=0
commit() {
	_n=$((_n + 1))
	local t=$((1790000000 + _n * 3600))
	git add -A
	GIT_AUTHOR_DATE="@$t +0000" GIT_COMMITTER_DATE="@$t +0000" git commit -q -m "$1"
}

mkdir -p app/support app/commands tests/data
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >app/__init__.py
: >app/support/__init__.py
: >app/commands/__init__.py
: >tests/__init__.py
cat >app/__main__.py <<'PY'
import sys

from app.cli import main

sys.exit(main())
PY
cat >app/support/tabular.py <<'PY'
def load_table(path):
    with open(path, encoding="utf-8-sig") as handle:
        lines = [line.rstrip("\r\n") for line in handle]
    return [line.split(",") for line in lines if line.strip()]


def emit_table(rows, out):
    for row in rows:
        out.write(",".join(row) + "\n")
PY
cat >app/cli.py <<'PY'
import sys

COMMANDS = {
}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        sys.stderr.write('usage: rows <%s> FILE\n' % '|'.join(sorted(COMMANDS)))
        return 2
    return COMMANDS[argv[0]](argv[1:])
PY
printf '\xef\xbb\xbfname,city\r\nada,london\r\n\r\ngrace,nyc\r\nalan,london\r\nlinus,helsinki\r\n' >tests/data/people.csv
printf '\xef\xbb\xbfname,city\nada,london\ngrace,nyc\n\nada,london\nalan,london\ngrace,nyc\n' >tests/data/dupes.csv
cat >tests/test_cli_e2e.py <<'PY'
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "tests", "data")


def rows(*args):
    return subprocess.run(
        [sys.executable, "-m", "app", *args], cwd=ROOT, capture_output=True, text=True
    )


class TestCliEndToEnd(unittest.TestCase):
    def test_first_three_rows_come_out_of_head(self):
        proc = rows("head", os.path.join(DATA, "people.csv"))
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "name,city\nada,london\ngrace,nyc\n")

    def test_counts_come_out_of_stats(self):
        proc = rows("stats", os.path.join(DATA, "people.csv"))
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "rows: 5\ncolumns: 2\n")

    def test_repeat_rows_vanish_from_dedupe_output(self):
        proc = rows("dedupe", os.path.join(DATA, "dupes.csv"))
        self.assertEqual(proc.returncode, 0)
        self.assertEqual(proc.stdout, "name,city\nada,london\ngrace,nyc\nalan,london\n")
PY
cat >README.md <<'MD'
# rows

A tiny CSV inspector: `python3 -m app <head|stats|dedupe> FILE`.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: rows skeleton, table loader, cli registry, end-to-end harness"
BASE=$(git rev-parse --short HEAD)

cat >app/commands/head.py <<'PY'
import sys

from app.support.tabular import emit_table, load_table


def run(args):
    emit_table(load_table(args[0])[:3], sys.stdout)
    return 0
PY
cat >app/cli.py <<'PY'
import sys

from app.commands import head

COMMANDS = {
    'head': head.run,
}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        sys.stderr.write('usage: rows <%s> FILE\n' % '|'.join(sorted(COMMANDS)))
        return 2
    return COMMANDS[argv[0]](argv[1:])
PY
cat >tests/test_head.py <<'PY'
import contextlib
import io
import os
import unittest

from app.commands import head

PEOPLE = os.path.join(os.path.dirname(__file__), "data", "people.csv")


class TestHead(unittest.TestCase):
    def test_head_prints_three_rows(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = head.run([PEOPLE])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "name,city\nada,london\ngrace,nyc\n")
PY
commit "feat: head command"
T1=$(git rev-parse --short HEAD)

cat >app/commands/stats.py <<'PY'
import sys

from app.support.tabular import load_table


def run(args):
    table = load_table(args[0])
    sys.stdout.write("rows: %d\ncolumns: %d\n" % (len(table), len(table[0])))
    return 0
PY
cat >app/cli.py <<'PY'
import sys

from app.commands import head, stats

COMMANDS = {
    'head': head.run,
    'stats': stats.run,
}


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    if not argv or argv[0] not in COMMANDS:
        sys.stderr.write('usage: rows <%s> FILE\n' % '|'.join(sorted(COMMANDS)))
        return 2
    return COMMANDS[argv[0]](argv[1:])
PY
cat >tests/test_stats.py <<'PY'
import contextlib
import io
import os
import unittest

from app.commands import stats

PEOPLE = os.path.join(os.path.dirname(__file__), "data", "people.csv")


class TestStats(unittest.TestCase):
    def test_stats_reports_rows_and_columns(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = stats.run([PEOPLE])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "rows: 5\ncolumns: 2\n")
PY
commit "feat: stats command"
T2=$(git rev-parse --short HEAD)

mkdir -p .specs/001-rows-dedupe
printf '001-rows-dedupe\n' >.specs/.current
cat >.specs/001-rows-dedupe/spec.md <<'MD'
# Spec — rows dedupe

`rows` already has `head` and `stats`. Analysts want `dedupe` to drop repeated rows.

## Requirements
- R1: `python3 -m app head FILE` prints the first three rows.
- R2: `python3 -m app stats FILE` prints the row and column counts.
- R3: `python3 -m app dedupe FILE` prints the table with repeated rows dropped, keeping the
  first occurrence of each row and the original order. The header row counts as a row like
  any other. It reads its input the way `head` and `stats` do (BOM-prefixed files, CRLF
  line endings and blank lines all work), writes to stdout only and exits 0.

## Acceptance
- A1: `head`, `stats` and `dedupe` all work when run as `python3 -m app <command> FILE`.
- A2: `dedupe` on a file whose rows repeat non-adjacently keeps each row's first occurrence.
MD
cat >.specs/001-rows-dedupe/TASKS.md <<TASKS
# Tasks — rows dedupe
Spec: spec.md · Design: none · Base: $BASE · Route: bounded · Test: \`python3 -m unittest discover -s tests\`
Approved: 2026-09-28 by user

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a CSV, when \`python3 -m app head FILE\` runs, then the first three rows print | T001 | test_head |
| B2 (P0) | Given a CSV, when \`python3 -m app stats FILE\` runs, then the row and column counts print | T002 | test_stats |
| B3 (P0) | Given a CSV with non-adjacent repeat rows, when \`python3 -m app dedupe FILE\` runs, then each row's first occurrence prints in order | T003 | test_dedupe_cmd, test_cli_e2e |

## Phase 1 — Row tools
Goal: \`head\`, \`stats\` and \`dedupe\` all work from the command line.
Independent test: \`python3 -m unittest tests.test_cli_e2e\` — green, all three commands through \`python3 -m app\`.
- [x] T001 head command (B1) — files: app/commands/head.py, app/cli.py, tests/test_head.py — verify: \`python3 -m unittest tests.test_head\` — done: $T1
- [x] T002 stats command (B2) — files: app/commands/stats.py, app/cli.py, tests/test_stats.py — verify: \`python3 -m unittest tests.test_stats\` — after: T001 — done: $T2
- [ ] T003 dedupe command (B3) — files: app/commands/dedupe.py, app/cli.py, tests/test_dedupe_cmd.py — verify: \`python3 -m unittest tests.test_dedupe_cmd\` — after: T002

## Gates
- [ ] G001 project gates clean — files: . — verify: \`flow check --fix\`
TASKS
commit "plan: rows dedupe, approved"
