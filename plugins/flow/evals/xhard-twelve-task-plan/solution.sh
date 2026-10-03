#!/usr/bin/env bash
# What a perfect run leaves: the plan approved at the gate by the model (autoApprove), twelve
# tasks built wave by wave with one commit each and ticked through flow tick right after
# their wave, phase 1's Independent test run before phase 2 starts, phase 2's run after,
# the gates green, PASS-<HEAD sha>.md written, and NO Verified: line.
set -euo pipefail
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-log-report
TODAY=$(date +%F)

# ---- the unapproved gate, with autoApprove on
{ head -2 "$SPEC/TASKS.md"; echo "Approved: $TODAY by model (autoApprove)"; tail -n +3 "$SPEC/TASKS.md"; } >"$SPEC/TASKS.new"
mv "$SPEC/TASKS.new" "$SPEC/TASKS.md"

ship() { # <ID> <message> <files...>: one pathspec commit, then the tick
	local id=$1 msg=$2
	shift 2
	git add -- "$@"
	git commit -q -m "$msg" -- "$@"
	$FLOW tick "$id"
}

# ---- wave 1: T001 T002 T003
cat >logkit/parse.py <<'PY'
from typing import NamedTuple

from logkit.support.clock import to_epoch


class Record(NamedTuple):
    ts: int
    level: str
    service: str
    message: str


def parse_line(line):
    fields = line.rstrip("\n").split(" ", 3)
    if len(fields) < 4:
        return None
    try:
        ts = to_epoch(fields[0])
    except ValueError:
        return None
    return Record(ts, fields[1].upper(), fields[2], fields[3])
PY
cat >tests/test_parse.py <<'PY'
import unittest

from logkit.parse import Record, parse_line
from logkit.support.clock import to_epoch


class TestParseLine(unittest.TestCase):
    def test_valid_line_becomes_a_record(self):
        got = parse_line("2026-09-01T10:15:30Z WARN api slow query took 900ms")
        self.assertEqual(got, Record(to_epoch("2026-09-01T10:15:30Z"), "WARN", "api", "slow query took 900ms"))

    def test_newline_dropped_and_level_upper_cased(self):
        got = parse_line("2026-09-01T10:15:30Z warn api boom\n")
        self.assertEqual((got.level, got.message), ("WARN", "boom"))

    def test_malformed_lines_give_none(self):
        for line in ("", "only two", "2026-09-01T10:15:30Z WARN api", "yesterday WARN api boom"):
            with self.subTest(line=line):
                self.assertIsNone(parse_line(line))
PY
cat >logkit/levels.py <<'PY'
LEVELS = ("DEBUG", "INFO", "WARN", "ERROR")


def level_rank(level):
    return LEVELS.index(level.upper())
PY
cat >tests/test_levels.py <<'PY'
import unittest

from logkit.levels import LEVELS, level_rank


class TestLevelRank(unittest.TestCase):
    def test_ranks_follow_severity(self):
        self.assertEqual([level_rank(level) for level in LEVELS], [0, 1, 2, 3])

    def test_case_insensitive(self):
        self.assertEqual(level_rank("warn"), 2)

    def test_unknown_level_raises(self):
        with self.assertRaises(ValueError):
            level_rank("TRACE")
PY
cat >logkit/window.py <<'PY'
def in_window(ts, start, end):
    return (start is None or ts >= start) and (end is None or ts < end)
PY
cat >tests/test_window.py <<'PY'
import unittest

from logkit.window import in_window


class TestInWindow(unittest.TestCase):
    def test_start_is_kept_and_end_is_dropped(self):
        self.assertTrue(in_window(5, 5, 10))
        self.assertTrue(in_window(9, 5, 10))
        self.assertFalse(in_window(10, 5, 10))
        self.assertFalse(in_window(4, 5, 10))

    def test_none_bounds_are_open(self):
        self.assertTrue(in_window(3, None, None))
        self.assertTrue(in_window(3, None, 10))
        self.assertTrue(in_window(10, 10, None))
        self.assertFalse(in_window(9, 10, None))
PY
python3 -m unittest tests.test_parse tests.test_levels tests.test_window >/dev/null 2>&1
ship T001 "parse: turn a log line into a record" logkit/parse.py tests/test_parse.py
ship T002 "levels: rank log levels" logkit/levels.py tests/test_levels.py
ship T003 "window: half-open time window test" logkit/window.py tests/test_window.py

# ---- wave 2: T004 T005 T006
cat >>logkit/parse.py <<'PY'


def parse_lines(lines):
    records = []
    malformed = 0
    for line in lines:
        if not line.strip():
            continue
        record = parse_line(line)
        if record is None:
            malformed += 1
        else:
            records.append(record)
    return records, malformed
PY
python3 - <<'PY'
path = "tests/test_parse.py"
text = open(path).read()
text = text.replace("import Record, parse_line", "import Record, parse_line, parse_lines")
text += '''

class TestParseLines(unittest.TestCase):
    def test_records_and_malformed_count_with_blanks_ignored(self):
        lines = [
            "2026-09-01T10:00:00Z INFO api listening",
            "",
            "   ",
            "not a log line",
            "2026-09-01T10:00:05Z DEBUG api warm cache",
        ]
        records, malformed = parse_lines(lines)
        self.assertEqual([r.message for r in records], ["listening", "warm cache"])
        self.assertEqual(malformed, 1)

    def test_empty_input(self):
        self.assertEqual(parse_lines([]), ([], 0))
'''
open(path, "w").write(text)
PY
cat >>logkit/levels.py <<'PY'


def at_least(level, floor):
    return level_rank(level) >= level_rank(floor)
PY
python3 - <<'PY'
path = "tests/test_levels.py"
text = open(path).read()
text = text.replace("import LEVELS, level_rank", "import LEVELS, at_least, level_rank")
text += '''

class TestAtLeast(unittest.TestCase):
    def test_floor_keeps_that_level_and_above(self):
        self.assertTrue(at_least("ERROR", "WARN"))
        self.assertTrue(at_least("WARN", "WARN"))
        self.assertFalse(at_least("INFO", "WARN"))

    def test_unknown_level_raises(self):
        with self.assertRaises(ValueError):
            at_least("TRACE", "WARN")
'''
open(path, "w").write(text)
PY
python3 - <<'PY'
path = "logkit/window.py"
text = open(path).read()
text = "from logkit.support.clock import to_epoch\n\n\n" + text
text += '''

def window_from_stamps(since, until):
    start = None if since is None else to_epoch(since)
    end = None if until is None else to_epoch(until)
    return start, end
'''
open(path, "w").write(text)
path = "tests/test_window.py"
text = open(path).read()
text = text.replace("import in_window\n", "import in_window, window_from_stamps\nfrom logkit.support.clock import to_epoch\n")
text += '''

class TestWindowFromStamps(unittest.TestCase):
    def test_stamps_become_epoch_seconds_and_none_stays_none(self):
        self.assertEqual(
            window_from_stamps("2026-09-01T10:00:00Z", "2026-09-01T11:00:00Z"),
            (to_epoch("2026-09-01T10:00:00Z"), to_epoch("2026-09-01T11:00:00Z")),
        )
        self.assertEqual(window_from_stamps(None, None), (None, None))

    def test_invalid_stamp_raises(self):
        with self.assertRaises(ValueError):
            window_from_stamps("noon", None)
'''
open(path, "w").write(text)
PY
python3 -m unittest tests.test_parse tests.test_levels tests.test_window >/dev/null 2>&1
ship T004 "parse: parse a whole file's lines" logkit/parse.py tests/test_parse.py
ship T005 "levels: floor comparison" logkit/levels.py tests/test_levels.py
ship T006 "window: build a window from stamps" logkit/window.py tests/test_window.py

# ---- phase 1's Independent test, before phase 2 starts
python3 -m unittest tests.test_parse tests.test_levels tests.test_window >/dev/null 2>&1

# ---- phase 2 and the gates live in solution.d/phase2.sh
. "$CASE_DIR/solution.d/phase2.sh"
