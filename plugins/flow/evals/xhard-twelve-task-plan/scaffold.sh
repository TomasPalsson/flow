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
git init -q -b flow/log-report
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

mkdir -p logkit/support tests data .claude
cat >.gitignore <<'TXT'
__pycache__/
.specs/.next-call-count
TXT
: >logkit/__init__.py
: >logkit/support/__init__.py
: >tests/__init__.py
printf '{"autoApprove": true}\n' >.claude/flow.config.json
cat >logkit/support/clock.py <<'PY'
import calendar
import time

STAMP_FORMAT = "%Y-%m-%dT%H:%M:%SZ"


def to_epoch(stamp):
    return calendar.timegm(time.strptime(stamp, STAMP_FORMAT))


def to_stamp(epoch):
    return time.strftime(STAMP_FORMAT, time.gmtime(epoch))
PY
cat >logkit/support/tables.py <<'PY'
def pad_right(text, width):
    if len(text) > width:
        return text[: width - 1] + "~"
    return text.ljust(width)
PY
cat >logkit/reader.py <<'PY'
def read_lines(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return [line.rstrip("\n") for line in fh]
PY
cat >logkit/cli.py <<'PY'
import sys

from logkit.reader import read_lines


def main(argv=None):
    argv = sys.argv[1:] if argv is None else argv
    for line in read_lines(argv[0]):
        print(line)


if __name__ == "__main__":
    main()
PY
cat >data/sample.log <<'LOG'
2026-09-01T10:00:00Z INFO api listening on :8080
2026-09-01T10:00:05Z DEBUG api warm cache
2026-09-01T10:01:10Z WARN db slow query took 900ms
2026-09-01T10:02:00Z ERROR db connection timeout

2026-09-01T10:02:30Z ERROR db connection timeout
not a log line
2026-09-01T10:03:00Z INFO worker job 41 done
LOG
cat >tests/test_clock.py <<'PY'
import unittest

from logkit.support.clock import to_epoch, to_stamp


class TestClock(unittest.TestCase):
    def test_epoch_of_a_known_stamp(self):
        self.assertEqual(to_epoch("1970-01-02T00:00:00Z"), 86400)

    def test_stamp_round_trips(self):
        self.assertEqual(to_stamp(to_epoch("2026-09-01T10:15:30Z")), "2026-09-01T10:15:30Z")

    def test_bad_stamp_raises(self):
        with self.assertRaises(ValueError):
            to_epoch("yesterday")
PY
cat >tests/test_tables.py <<'PY'
import unittest

from logkit.support.tables import pad_right


class TestTables(unittest.TestCase):
    def test_short_text_is_padded(self):
        self.assertEqual(pad_right("api", 6), "api   ")

    def test_long_text_is_cut_with_a_marker(self):
        self.assertEqual(pad_right("database", 6), "datab~")
PY
cat >tests/test_reader.py <<'PY'
import os
import tempfile
import unittest

from logkit.reader import read_lines


class TestReader(unittest.TestCase):
    def test_lines_come_back_without_newlines(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = os.path.join(tmp, "a.log")
            with open(path, "w") as fh:
                fh.write("one\ntwo\n")
            self.assertEqual(read_lines(path), ["one", "two"])
PY
cat >README.md <<'MD'
# logkit

Small helpers for reading service logs.

Log lines look like `<stamp> <LEVEL> <service> <message>`, for example
`2026-09-01T10:15:30Z WARN api slow query took 900ms`.

Run tests: `python3 -m unittest discover -s tests -v`
MD
commit "base: logkit clock, tables, reader"
BASE=$(git rev-parse --short HEAD)

mkdir -p .specs/001-log-report
printf '001-log-report\n' >.specs/.current
cat >.specs/001-log-report/spec.md <<'MD'
# Spec — Log report

Turn a service log into a short report: parse the lines, filter them, count them, print them.

## Contracts
All functions are plain Python in `logkit/`, stdlib only; time stamps go through the existing
helpers in `logkit/support/clock.py`, padding through `logkit/support/tables.py`.

- `parse.Record` is a `NamedTuple(ts, level, service, message)`: `ts` is epoch seconds (int).
- `parse.parse_line(line)`: fields are `<stamp> <LEVEL> <service> <message>`, single spaces, the
  message is the rest of the line. A trailing newline is dropped and the level is upper-cased.
  Fewer than four fields, or a stamp that is not a valid stamp, returns `None`.
- `parse.parse_lines(lines)` returns `(records, malformed)`: blank or whitespace-only lines are
  skipped and not counted; every other line `parse_line` rejects adds one to `malformed`.
- `levels.LEVELS` is `("DEBUG", "INFO", "WARN", "ERROR")`; `levels.level_rank(level)` is the index
  in it, case-insensitive, and an unknown level raises `ValueError`.
- `levels.at_least(level, floor)` is true when `level` ranks at or above `floor`.
- `window.in_window(ts, start, end)` is `start <= ts < end`; a `None` bound is open.
- `window.window_from_stamps(since, until)` returns `(start, end)` as epoch seconds; a `None` stamp
  stays `None`; an invalid stamp raises `ValueError`.
- `filters.filter_records(records, floor=None, start=None, end=None)` keeps, in order, the records
  at or above `floor` (when given) and inside the window.
- `filters.for_service(records, service)` keeps the records whose service equals `service` exactly.
- `stats.count_by_level(records)` is a dict with every level in `LEVELS` order, zeros included;
  records with any other level are ignored.
- `stats.top_messages(records, n)` is a list of `(message, count)`, highest count first, ties by
  message ascending, at most `n` long.
- `render.render_row(record)` is `<stamp> <LEVEL padded to 5> <service padded to 8> <message>`.
- `render.render_report(records, malformed=0)` is these lines joined by newlines, no trailing one:
  `logkit report: <N> records` (`, <M> malformed` appended when `malformed` is not 0), `levels:`,
  one `  <LEVEL padded to 5> <count>` line per level, `errors:`, then one `  <render_row>` line per
  ERROR record or `  none`.

## Acceptance
- A1: a valid line parses to a record and a malformed one does not raise.
- A2: a file's lines parse to records plus a malformed count, blank lines ignored.
- A3: levels rank DEBUG < INFO < WARN < ERROR and a floor keeps that level and above.
- A4: a time window keeps its start and drops its end, given as stamps, either bound optional.
- A5: records filter by floor and window together, and by service.
- A6: records count per level, and the most repeated messages rank first.
- A7: the report shows the header, the level counts and the ERROR rows.

## Non-goals
- No command line wiring in this plan; `logkit/cli.py` is untouched.
MD
: >.specs/001-log-report/NOTES.md
cat >.specs/001-log-report/TASKS.md <<TASKS
# Tasks — Log report
Spec: spec.md · Design: none · Base: $BASE · Route: dispatch · Test: \`python3 -m unittest discover -s tests\`

## Behaviors
| ID | Given / When / Then | Task | Proven by |
|----|---------------------|------|-----------|
| B1 (P0) | Given a valid log line, when it is parsed, then a record with epoch seconds comes back and a malformed line gives None | T001 | test_parse |
| B2 (P0) | Given a file's lines, when they are parsed, then records and a malformed count come back with blank lines ignored | T004 | test_parse |
| B3 (P0) | Given a level and a floor, when compared, then ranks decide and an unknown level raises | T005 | test_levels |
| B4 (P0) | Given a window, when a timestamp is tested, then its start is kept and its end dropped | T006 | test_window |
| B5 (P0) | Given records, when filtered by floor, window and service, then only the matches remain in order | T007 | test_filters |
| B6 (P1) | Given records, when counted, then every level has a count and the top messages rank by count | T008 | test_stats |
| B7 (P1) | Given records, when a report is rendered, then it shows the header, level counts and ERROR rows | T012 | test_render |

## Phase 1 — Parse and select
Goal: raw log lines become records that can be ranked by level and placed in a time window.
Independent test: \`python3 -m unittest tests.test_parse tests.test_levels tests.test_window\` — green.
- [ ] T001 [P] parse_line and Record (B1) — files: logkit/parse.py, tests/test_parse.py — verify: \`python3 -m unittest tests.test_parse\`
- [ ] T002 [P] LEVELS and level_rank — files: logkit/levels.py, tests/test_levels.py — verify: \`python3 -m unittest tests.test_levels\`
- [ ] T003 [P] in_window — files: logkit/window.py, tests/test_window.py — verify: \`python3 -m unittest tests.test_window\`
- [ ] T004 parse_lines (B2) — files: logkit/parse.py, tests/test_parse.py — verify: \`python3 -m unittest tests.test_parse\` — after: T001
- [ ] T005 at_least (B3) — files: logkit/levels.py, tests/test_levels.py — verify: \`python3 -m unittest tests.test_levels\` — after: T002
- [ ] T006 window_from_stamps (B4) — files: logkit/window.py, tests/test_window.py — verify: \`python3 -m unittest tests.test_window\` — after: T003

## Phase 2 — Filter, count, render
Goal: parsed records are filtered, counted and printed as a short report.
Independent test: \`python3 -m unittest tests.test_filters tests.test_stats tests.test_render\` — green.
- [ ] T007 [P] filter_records (B5) — files: logkit/filters.py, tests/test_filters.py — verify: \`python3 -m unittest tests.test_filters\` — after: T004, T005, T006
- [ ] T008 [P] count_by_level (B6) — files: logkit/stats.py, tests/test_stats.py — verify: \`python3 -m unittest tests.test_stats\` — after: T002, T004
- [ ] T009 [P] render_row — files: logkit/render.py, tests/test_render.py — verify: \`python3 -m unittest tests.test_render\` — after: T004
- [ ] T010 [P] for_service — files: logkit/filters.py, tests/test_filters.py — verify: \`python3 -m unittest tests.test_filters\` — after: T007
- [ ] T011 [P] top_messages — files: logkit/stats.py, tests/test_stats.py — verify: \`python3 -m unittest tests.test_stats\` — after: T008
- [ ] T012 [P] render_report (B7) — files: logkit/render.py, tests/test_render.py — verify: \`python3 -m unittest tests.test_render\` — after: T008, T009

## Gates
- [ ] G001 project gates clean — files: . — verify: \`python3 -m unittest discover -s tests\`
- [ ] G002 branch review clean — files: . — verify: \`flow pass\`
TASKS
commit "plan: log report, drafted"
