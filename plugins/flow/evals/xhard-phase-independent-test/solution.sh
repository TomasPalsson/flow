#!/usr/bin/env bash
# What a perfect run leaves: the dedupe module, the registry entry in the
# registry's own single-quote style, the phase Independent test run and green,
# and the tick made through flow tick.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"

cat >app/commands/dedupe.py <<'PY'
import sys

from app.support.tabular import emit_table, load_table


def run(args):
    seen = set()
    kept = []
    for row in load_table(args[0]):
        key = tuple(row)
        if key not in seen:
            seen.add(key)
            kept.append(row)
    emit_table(kept, sys.stdout)
    return 0
PY
cat >tests/test_dedupe_cmd.py <<'PY'
import contextlib
import io
import os
import unittest

from app.commands import dedupe

DUPES = os.path.join(os.path.dirname(__file__), "data", "dupes.csv")


class TestDedupeCommand(unittest.TestCase):
    def test_keeps_the_first_of_each_row(self):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = dedupe.run([DUPES])
        self.assertEqual(code, 0)
        self.assertEqual(out.getvalue(), "name,city\nada,london\ngrace,nyc\nalan,london\n")
PY
python3 -m unittest tests.test_dedupe_cmd >/dev/null

python3 - <<'PY'
import re

path = "app/cli.py"
text = open(path).read()
text = text.replace("import head, stats", "import dedupe, head, stats")
text = text.replace("    'stats': stats.run,\n", "    'stats': stats.run,\n    'dedupe': dedupe.run,\n")
open(path, "w").write(text)
PY
python3 -m unittest tests.test_cli_e2e >/dev/null
git add app/commands/dedupe.py app/cli.py tests/test_dedupe_cmd.py
git commit -q -m "feat: dedupe command"
node "$FLOW" tick T003
git add .specs
git commit -q -m "chore: tick T003"
