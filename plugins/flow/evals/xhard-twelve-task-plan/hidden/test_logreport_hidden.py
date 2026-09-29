import calendar
import time
import unittest

from logkit.filters import filter_records, for_service
from logkit.levels import LEVELS, at_least, level_rank
from logkit.parse import Record, parse_line, parse_lines
from logkit.render import render_report, render_row
from logkit.stats import count_by_level, top_messages
from logkit.window import in_window, window_from_stamps


def ts(stamp):
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))


def rec(stamp, level, service, message):
    return Record(ts(stamp), level, service, message)


SAMPLE = [
    rec("2026-09-01T10:00:00Z", "INFO", "api", "listening"),
    rec("2026-09-01T10:00:05Z", "DEBUG", "api", "warm cache"),
    rec("2026-09-01T10:01:10Z", "WARN", "db", "slow query"),
    rec("2026-09-01T10:02:00Z", "ERROR", "db", "timeout"),
    rec("2026-09-01T10:02:30Z", "ERROR", "db", "timeout"),
    rec("2026-09-01T10:03:00Z", "INFO", "worker", "job done"),
]


class TestParseLine(unittest.TestCase):
    def test_valid_line_becomes_a_record(self):
        got = parse_line("2026-09-01T10:15:30Z WARN api slow query took 900ms")
        self.assertEqual(got, Record(ts("2026-09-01T10:15:30Z"), "WARN", "api", "slow query took 900ms"))
        self.assertEqual((got.ts, got.level, got.service, got.message),
                         (1788257730, "WARN", "api", "slow query took 900ms"))

    def test_trailing_newline_is_dropped_and_level_upper_cased(self):
        got = parse_line("2026-09-01T10:15:30Z warn api boom\n")
        self.assertEqual(got.level, "WARN")
        self.assertEqual(got.message, "boom")

    def test_malformed_lines_give_none(self):
        for line in ("", "only two", "2026-09-01T10:15:30Z WARN api",
                     "yesterday WARN api boom", "2026-13-45T99:99:99Z WARN api boom"):
            with self.subTest(line=line):
                self.assertIsNone(parse_line(line))


class TestParseLines(unittest.TestCase):
    def test_records_and_malformed_count(self):
        lines = [
            "2026-09-01T10:00:00Z INFO api listening",
            "",
            "   ",
            "not a log line",
            "2026-09-01T10:00:05Z DEBUG api warm cache",
            "2026-09-01T10:00:09Z WARN",
        ]
        records, malformed = parse_lines(lines)
        self.assertEqual([r.message for r in records], ["listening", "warm cache"])
        self.assertEqual(malformed, 2)

    def test_empty_input(self):
        self.assertEqual(parse_lines([]), ([], 0))

    def test_only_blank_lines_are_not_malformed(self):
        self.assertEqual(parse_lines(["", "\t", "  "]), ([], 0))


class TestLevelRank(unittest.TestCase):
    def test_levels_constant_and_ranks(self):
        self.assertEqual(tuple(LEVELS), ("DEBUG", "INFO", "WARN", "ERROR"))
        self.assertEqual([level_rank(l) for l in LEVELS], [0, 1, 2, 3])

    def test_case_insensitive(self):
        self.assertEqual(level_rank("warn"), 2)

    def test_unknown_level_raises(self):
        with self.assertRaises(ValueError):
            level_rank("TRACE")


class TestAtLeast(unittest.TestCase):
    def test_floor_keeps_that_level_and_above(self):
        self.assertTrue(at_least("ERROR", "WARN"))
        self.assertTrue(at_least("WARN", "WARN"))
        self.assertFalse(at_least("INFO", "WARN"))

    def test_case_insensitive_and_unknown_raises(self):
        self.assertTrue(at_least("error", "warn"))
        with self.assertRaises(ValueError):
            at_least("TRACE", "WARN")
        with self.assertRaises(ValueError):
            at_least("WARN", "LOUD")


class TestInWindow(unittest.TestCase):
    def test_start_is_kept_and_end_is_dropped(self):
        self.assertTrue(in_window(5, 5, 10))
        self.assertTrue(in_window(9, 5, 10))
        self.assertFalse(in_window(10, 5, 10))
        self.assertFalse(in_window(4, 5, 10))

    def test_none_bounds_are_open(self):
        self.assertTrue(in_window(3, None, None))
        self.assertTrue(in_window(3, None, 10))
        self.assertFalse(in_window(10, None, 10))
        self.assertTrue(in_window(10, 10, None))
        self.assertFalse(in_window(9, 10, None))


class TestWindowFromStamps(unittest.TestCase):
    def test_both_stamps_become_epoch_seconds(self):
        self.assertEqual(
            window_from_stamps("2026-09-01T10:00:00Z", "2026-09-01T11:00:00Z"),
            (ts("2026-09-01T10:00:00Z"), ts("2026-09-01T11:00:00Z")),
        )

    def test_none_stays_none(self):
        self.assertEqual(window_from_stamps(None, "2026-09-01T11:00:00Z"), (None, ts("2026-09-01T11:00:00Z")))
        self.assertEqual(window_from_stamps("2026-09-01T10:00:00Z", None), (ts("2026-09-01T10:00:00Z"), None))
        self.assertEqual(window_from_stamps(None, None), (None, None))

    def test_invalid_stamp_raises(self):
        with self.assertRaises(ValueError):
            window_from_stamps("noon", None)
        with self.assertRaises(ValueError):
            window_from_stamps(None, "2026-09-01")


class TestFilterRecords(unittest.TestCase):
    def test_no_filters_keeps_everything_in_order(self):
        self.assertEqual(filter_records(SAMPLE), SAMPLE)

    def test_floor_only(self):
        got = filter_records(SAMPLE, floor="WARN")
        self.assertEqual([r.message for r in got], ["slow query", "timeout", "timeout"])

    def test_window_only_keeps_start_and_drops_end(self):
        start, end = ts("2026-09-01T10:00:05Z"), ts("2026-09-01T10:02:00Z")
        got = filter_records(SAMPLE, start=start, end=end)
        self.assertEqual([r.message for r in got], ["warm cache", "slow query"])

    def test_floor_and_window_together(self):
        got = filter_records(SAMPLE, floor="INFO", start=ts("2026-09-01T10:01:00Z"))
        self.assertEqual([r.message for r in got], ["slow query", "timeout", "timeout", "job done"])

    def test_returns_a_new_list(self):
        self.assertIsNot(filter_records(SAMPLE), SAMPLE)


class TestForService(unittest.TestCase):
    def test_exact_match_only(self):
        self.assertEqual([r.message for r in for_service(SAMPLE, "db")], ["slow query", "timeout", "timeout"])
        self.assertEqual(for_service(SAMPLE, "DB"), [])
        self.assertEqual(for_service(SAMPLE, "d"), [])

    def test_order_is_kept(self):
        self.assertEqual(for_service(SAMPLE, "api"), SAMPLE[:2])


class TestCountByLevel(unittest.TestCase):
    def test_every_level_with_zeros(self):
        got = count_by_level(SAMPLE)
        self.assertEqual(got, {"DEBUG": 1, "INFO": 2, "WARN": 1, "ERROR": 2})
        self.assertEqual(list(got), ["DEBUG", "INFO", "WARN", "ERROR"])

    def test_empty_gives_all_zero(self):
        self.assertEqual(count_by_level([]), {"DEBUG": 0, "INFO": 0, "WARN": 0, "ERROR": 0})

    def test_other_levels_are_ignored(self):
        extra = SAMPLE + [rec("2026-09-01T10:04:00Z", "TRACE", "api", "noise")]
        self.assertEqual(count_by_level(extra), count_by_level(SAMPLE))

    def test_missing_levels_are_zero(self):
        self.assertEqual(count_by_level(SAMPLE[3:5]), {"DEBUG": 0, "INFO": 0, "WARN": 0, "ERROR": 2})


class TestTopMessages(unittest.TestCase):
    def test_highest_count_first_ties_by_message(self):
        got = top_messages(SAMPLE, 10)
        self.assertEqual(got, [("timeout", 2), ("job done", 1), ("listening", 1), ("slow query", 1), ("warm cache", 1)])

    def test_limit(self):
        self.assertEqual(top_messages(SAMPLE, 2), [("timeout", 2), ("job done", 1)])
        self.assertEqual(top_messages(SAMPLE, 0), [])

    def test_empty(self):
        self.assertEqual(top_messages([], 3), [])


class TestRenderRow(unittest.TestCase):
    def test_columns_are_padded(self):
        self.assertEqual(
            render_row(rec("2026-09-01T10:15:30Z", "WARN", "api", "slow query")),
            "2026-09-01T10:15:30Z WARN  api      slow query",
        )
        self.assertEqual(
            render_row(rec("2026-09-01T10:15:30Z", "ERROR", "db", "timeout")),
            "2026-09-01T10:15:30Z ERROR db       timeout",
        )

    def test_long_service_is_cut_with_a_marker(self):
        self.assertEqual(
            render_row(rec("2026-09-01T10:15:30Z", "INFO", "database-primary", "up")),
            "2026-09-01T10:15:30Z INFO  databas~ up",
        )


class TestRenderReport(unittest.TestCase):
    def test_report_with_errors(self):
        expected = "\n".join([
            "logkit report: 6 records",
            "levels:",
            "  DEBUG 1",
            "  INFO  2",
            "  WARN  1",
            "  ERROR 2",
            "errors:",
            "  2026-09-01T10:02:00Z ERROR db       timeout",
            "  2026-09-01T10:02:30Z ERROR db       timeout",
        ])
        self.assertEqual(render_report(SAMPLE), expected)

    def test_malformed_count_is_appended_to_the_header(self):
        self.assertEqual(render_report(SAMPLE, 3).splitlines()[0], "logkit report: 6 records, 3 malformed")

    def test_no_errors_says_none(self):
        expected = "\n".join([
            "logkit report: 2 records",
            "levels:",
            "  DEBUG 1",
            "  INFO  1",
            "  WARN  0",
            "  ERROR 0",
            "errors:",
            "  none",
        ])
        self.assertEqual(render_report(SAMPLE[:2]), expected)

    def test_empty_report(self):
        self.assertEqual(render_report([]).splitlines()[0], "logkit report: 0 records")
        self.assertTrue(render_report([]).endswith("  none"))


if __name__ == "__main__":
    unittest.main()
