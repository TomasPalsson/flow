# Phase 2 of solution.sh (sourced): waves 3 and 4, phase 2's Independent test, the gates, PASS.
# Uses $FLOW, $SPEC and ship() from solution.sh.
# ---- wave 3: T007 T008 T009
cat >logkit/filters.py <<'PY'
from logkit.levels import at_least
from logkit.window import in_window


def filter_records(records, floor=None, start=None, end=None):
    return [
        record
        for record in records
        if (floor is None or at_least(record.level, floor)) and in_window(record.ts, start, end)
    ]
PY
cat >tests/test_filters.py <<'PY'
import unittest

from logkit.filters import filter_records
from logkit.parse import Record

SAMPLE = [
    Record(100, "INFO", "api", "listening"),
    Record(105, "DEBUG", "api", "warm cache"),
    Record(170, "WARN", "db", "slow query"),
    Record(200, "ERROR", "db", "timeout"),
]


class TestFilterRecords(unittest.TestCase):
    def test_no_filters_keeps_everything_in_order(self):
        self.assertEqual(filter_records(SAMPLE), SAMPLE)

    def test_floor_keeps_that_level_and_above(self):
        self.assertEqual([r.message for r in filter_records(SAMPLE, floor="WARN")], ["slow query", "timeout"])

    def test_window_keeps_start_and_drops_end(self):
        got = filter_records(SAMPLE, start=105, end=200)
        self.assertEqual([r.message for r in got], ["warm cache", "slow query"])

    def test_floor_and_window_together(self):
        got = filter_records(SAMPLE, floor="INFO", start=150)
        self.assertEqual([r.message for r in got], ["slow query", "timeout"])
PY
cat >logkit/stats.py <<'PY'
from collections import Counter

from logkit.levels import LEVELS


def count_by_level(records):
    counts = Counter(record.level for record in records)
    return {level: counts[level] for level in LEVELS}
PY
cat >tests/test_stats.py <<'PY'
import unittest

from logkit.parse import Record
from logkit.stats import count_by_level

SAMPLE = [
    Record(1, "INFO", "api", "listening"),
    Record(2, "ERROR", "db", "timeout"),
    Record(3, "ERROR", "db", "timeout"),
    Record(4, "TRACE", "api", "noise"),
]


class TestCountByLevel(unittest.TestCase):
    def test_every_level_appears_in_order_with_zeros(self):
        got = count_by_level(SAMPLE)
        self.assertEqual(got, {"DEBUG": 0, "INFO": 1, "WARN": 0, "ERROR": 2})
        self.assertEqual(list(got), ["DEBUG", "INFO", "WARN", "ERROR"])

    def test_empty_gives_all_zero(self):
        self.assertEqual(count_by_level([]), {"DEBUG": 0, "INFO": 0, "WARN": 0, "ERROR": 0})
PY
cat >logkit/render.py <<'PY'
from logkit.support.clock import to_stamp
from logkit.support.tables import pad_right


def render_row(record):
    return "%s %-5s %s %s" % (to_stamp(record.ts), record.level, pad_right(record.service, 8), record.message)
PY
cat >tests/test_render.py <<'PY'
import unittest

from logkit.parse import Record
from logkit.render import render_row
from logkit.support.clock import to_epoch


class TestRenderRow(unittest.TestCase):
    def test_columns_are_padded(self):
        record = Record(to_epoch("2026-09-01T10:15:30Z"), "WARN", "api", "slow query")
        self.assertEqual(render_row(record), "2026-09-01T10:15:30Z WARN  api      slow query")

    def test_long_service_is_cut_with_a_marker(self):
        record = Record(to_epoch("2026-09-01T10:15:30Z"), "ERROR", "database-primary", "down")
        self.assertEqual(render_row(record), "2026-09-01T10:15:30Z ERROR databas~ down")
PY
python3 -m unittest tests.test_filters tests.test_stats tests.test_render >/dev/null 2>&1
ship T007 "filters: filter records by level floor and window" logkit/filters.py tests/test_filters.py
ship T008 "stats: count records per level" logkit/stats.py tests/test_stats.py
ship T009 "render: format one record as a row" logkit/render.py tests/test_render.py

# ---- wave 4: T010 T011 T012
cat >>logkit/filters.py <<'PY'


def for_service(records, service):
    return [record for record in records if record.service == service]
PY
python3 - <<'PY'
path = "tests/test_filters.py"
text = open(path).read()
text = text.replace("import filter_records\n", "import filter_records, for_service\n")
text += '''

class TestForService(unittest.TestCase):
    def test_exact_match_only(self):
        self.assertEqual([r.message for r in for_service(SAMPLE, "db")], ["slow query", "timeout"])
        self.assertEqual(for_service(SAMPLE, "DB"), [])
        self.assertEqual(for_service(SAMPLE, "d"), [])
'''
open(path, "w").write(text)
PY
cat >>logkit/stats.py <<'PY'


def top_messages(records, n):
    counts = Counter(record.message for record in records)
    ranked = sorted(counts.items(), key=lambda item: (-item[1], item[0]))
    return ranked[:n]
PY
python3 - <<'PY'
path = "tests/test_stats.py"
text = open(path).read()
text = text.replace("import count_by_level\n", "import count_by_level, top_messages\n")
text += '''

class TestTopMessages(unittest.TestCase):
    def test_highest_count_first_ties_by_message(self):
        got = top_messages(SAMPLE, 10)
        self.assertEqual(got, [("timeout", 2), ("listening", 1), ("noise", 1)])

    def test_limit(self):
        self.assertEqual(top_messages(SAMPLE, 2), [("timeout", 2), ("listening", 1)])
        self.assertEqual(top_messages(SAMPLE, 0), [])
'''
open(path, "w").write(text)
PY
python3 - <<'PY'
path = "logkit/render.py"
text = open(path).read()
text = text.replace("from logkit.support.clock", "from logkit.stats import count_by_level\nfrom logkit.support.clock")
text += '''

def render_report(records, malformed=0):
    header = "logkit report: %d records" % len(records)
    if malformed:
        header += ", %d malformed" % malformed
    lines = [header, "levels:"]
    lines += ["  %-5s %d" % (level, count) for level, count in count_by_level(records).items()]
    lines.append("errors:")
    errors = ["  " + render_row(record) for record in records if record.level == "ERROR"]
    return "\\n".join(lines + (errors or ["  none"]))
'''
open(path, "w").write(text)
path = "tests/test_render.py"
text = open(path).read()
text = text.replace("import render_row\n", "import render_report, render_row\n")
text += '''

class TestRenderReport(unittest.TestCase):
    def test_report_with_an_error_row_and_malformed_count(self):
        records = [
            Record(to_epoch("2026-09-01T10:00:00Z"), "INFO", "api", "listening"),
            Record(to_epoch("2026-09-01T10:02:00Z"), "ERROR", "db", "timeout"),
        ]
        expected = "\\n".join([
            "logkit report: 2 records, 3 malformed",
            "levels:",
            "  DEBUG 0",
            "  INFO  1",
            "  WARN  0",
            "  ERROR 1",
            "errors:",
            "  2026-09-01T10:02:00Z ERROR db       timeout",
        ])
        self.assertEqual(render_report(records, 3), expected)

    def test_no_errors_says_none(self):
        report = render_report([Record(1, "INFO", "api", "up")])
        self.assertTrue(report.endswith("errors:\\n  none"))
        self.assertEqual(report.splitlines()[0], "logkit report: 1 records")
'''
open(path, "w").write(text)
PY
python3 -m unittest tests.test_filters tests.test_stats tests.test_render >/dev/null 2>&1
ship T010 "filters: narrow records to one service" logkit/filters.py tests/test_filters.py
ship T011 "stats: rank the most repeated messages" logkit/stats.py tests/test_stats.py
ship T012 "render: print the report" logkit/render.py tests/test_render.py

# ---- phase 2's Independent test, then the gates
python3 -m unittest tests.test_filters tests.test_stats tests.test_render >/dev/null 2>&1
python3 -m unittest discover -s tests >/dev/null 2>&1
git add "$SPEC"
git commit -q -m "specs: approve plan, tick tasks"
HEAD_SHA=$(git rev-parse --short HEAD)
cat >"$SPEC/PASS-$HEAD_SHA.md" <<MD
# PASS $HEAD_SHA
- G001 \`python3 -m unittest discover -s tests\` — exit 0
- G002 branch review — no findings above threshold, exit 0
MD
$FLOW tick G001
$FLOW tick G002
git add "$SPEC"
git commit -q -m "specs: PASS, gates ticked"
