#!/usr/bin/env bash
# What a perfect run leaves on disk: wave 1 only. Four formatters, each through the shared
# fit_right helper, one commit per task, each ticked through flow tick. T005 untouched.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

cat >cells/fmt/money.py <<'PY'
from cells.support.layout import fit_right


def format_money(cents, width=12):
    dollars, rest = divmod(abs(cents), 100)
    sign = "-" if cents < 0 else ""
    return fit_right("%s$%s.%02d" % (sign, format(dollars, ","), rest), width)
PY
cat >tests/test_money.py <<'PY'
import unittest

from cells.fmt.money import format_money


class TestMoney(unittest.TestCase):
    def test_dollars_are_grouped_and_cents_padded(self):
        self.assertEqual(format_money(123456, 9), "$1,234.56")
        self.assertEqual(format_money(5, 5), "$0.05")

    def test_negative_amount_keeps_its_sign(self):
        self.assertEqual(format_money(-1234050, 11), "-$12,340.50")

    def test_wide_amount_is_cut_on_the_left(self):
        self.assertEqual(format_money(123456, 6), "…34.56")
PY
python3 -m unittest tests.test_money >/dev/null 2>&1
git add cells/fmt/money.py tests/test_money.py
git commit -q -m "feat: money cell"

cat >cells/fmt/percent.py <<'PY'
from cells.support.layout import fit_right


def format_percent(ratio, width=8):
    return fit_right("%.1f%%" % (ratio * 100), width)
PY
cat >tests/test_percent.py <<'PY'
import unittest

from cells.fmt.percent import format_percent


class TestPercent(unittest.TestCase):
    def test_one_decimal(self):
        self.assertEqual(format_percent(0.125, 5), "12.5%")
        self.assertEqual(format_percent(1, 6), "100.0%")

    def test_wide_percent_is_cut_on_the_left(self):
        self.assertEqual(format_percent(0.125, 4), "….5%")
PY
python3 -m unittest tests.test_percent >/dev/null 2>&1
git add cells/fmt/percent.py tests/test_percent.py
git commit -q -m "feat: percent cell"

cat >cells/fmt/duration.py <<'PY'
from cells.support.layout import fit_right


def format_duration(seconds, width=10):
    minutes, secs = divmod(seconds, 60)
    hours, minutes = divmod(minutes, 60)
    if hours:
        text = "%dh %02dm" % (hours, minutes)
    elif minutes:
        text = "%dm %02ds" % (minutes, secs)
    else:
        text = "%ds" % secs
    return fit_right(text, width)
PY
cat >tests/test_duration.py <<'PY'
import unittest

from cells.fmt.duration import format_duration


class TestDuration(unittest.TestCase):
    def test_seconds_minutes_and_hours(self):
        self.assertEqual(format_duration(45, 3), "45s")
        self.assertEqual(format_duration(725, 7), "12m 05s")
        self.assertEqual(format_duration(3900, 6), "1h 05m")

    def test_wide_duration_is_cut_on_the_left(self):
        self.assertEqual(format_duration(725, 5), "… 05s")
PY
python3 -m unittest tests.test_duration >/dev/null 2>&1
git add cells/fmt/duration.py tests/test_duration.py
git commit -q -m "feat: duration cell"

cat >cells/fmt/filesize.py <<'PY'
from cells.support.layout import fit_right

UNITS = ["KB", "MB", "GB"]


def format_size(size_bytes, width=10):
    if size_bytes < 1024:
        return fit_right("%d B" % size_bytes, width)
    size = size_bytes / 1024
    unit = 0
    while size >= 1024 and unit < len(UNITS) - 1:
        size /= 1024
        unit += 1
    return fit_right("%.1f %s" % (size, UNITS[unit]), width)
PY
cat >tests/test_filesize.py <<'PY'
import unittest

from cells.fmt.filesize import format_size


class TestFilesize(unittest.TestCase):
    def test_bytes_stay_whole(self):
        self.assertEqual(format_size(512, 5), "512 B")

    def test_units_step_by_1024(self):
        self.assertEqual(format_size(1536, 6), "1.5 KB")
        self.assertEqual(format_size(1048576, 6), "1.0 MB")

    def test_wide_size_is_cut_on_the_left(self):
        self.assertEqual(format_size(1536, 4), "… KB")
PY
python3 -m unittest tests.test_filesize >/dev/null 2>&1
git add cells/fmt/filesize.py tests/test_filesize.py
git commit -q -m "feat: file size cell"

for id in T001 T002 T003 T004; do
	node "$FLOW" tick "$id"
done
git add .specs
git commit -q -m "chore: tick wave 1"
