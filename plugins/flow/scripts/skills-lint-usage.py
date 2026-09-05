#!/usr/bin/env python3
"""skills-lint-usage.py — usage-count report for `skills-lint --usage` (C14/C15 W4).

Invoked as: python3 skills-lint-usage.py <names-file> <history-file>
<names-file> is a TSV of "skill\\t<name>" / "command\\t<name>" lines built by
the caller. Reads the JSONL history file, counts how many records mention
"/<name>" as a whole token, and prints a header line ("<total> prompts,
<first>..<last>") followed by one "<uses> <name> <kind> <last-used>" line
per name, sorted ascending by uses (never-used first). See skills-lint
--help for the full contract.
"""

import json
import re
import sys
from datetime import datetime, timezone

names_file, history_file = sys.argv[1], sys.argv[2]

items = []
with open(names_file, "r", encoding="utf-8") as fh:
    for raw in fh:
        raw = raw.rstrip("\n")
        if not raw:
            continue
        kind, name = raw.split("\t", 1)
        items.append((name, kind))


def content_of(rec):
    for key in ("display", "prompt", "text"):
        val = rec.get(key)
        if isinstance(val, str) and val:
            return val
    return ""


def date_of(rec):
    # "timestamp" in a real ~/.claude/history.jsonl is Unix MILLISECONDS
    # (13 digits); treat anything past 10**11 (~year 2286 in seconds) as
    # milliseconds so datetime.fromtimestamp() (which assumes seconds)
    # never overflows on the common, spec-named default file.
    ts = rec.get("timestamp")
    if isinstance(ts, (int, float)):
        try:
            t = ts / 1000.0 if ts > 10**11 else ts
            return datetime.fromtimestamp(t, tz=timezone.utc).strftime("%Y-%m-%d")
        except (OverflowError, OSError, ValueError):
            return None
    d = rec.get("date")
    if isinstance(d, str) and re.match(r"^\d{4}-\d{2}-\d{2}", d):
        return d[:10]
    return None


# A skill dir and a command file may share a basename (items then holds two
# entries with the same name, different kind); count once per unique name,
# not once per items-entry, or a single matching prompt double-counts both
# the skill and command rows for that shared name.
names = sorted(set(name for name, _ in items))

patterns = dict(
    (name, re.compile(r"(?<![A-Za-z0-9_/-])/" + re.escape(name) + r"(?![A-Za-z0-9_-])"))
    for name in names
)
uses = dict((name, 0) for name in names)
last_used = dict((name, None) for name in names)

total = 0
all_dates = []
try:
    # Explicit encoding="utf-8": a bare open() falls back to
    # locale.getpreferredencoding() (ASCII under a deliberately-set
    # LC_ALL=C/LANG=C CI locale), and real chat history is routinely
    # non-ASCII (curly quotes, emoji, accents, CJK) — must not crash.
    with open(history_file, "r", encoding="utf-8") as hf:
        for line in hf:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if not isinstance(rec, dict):
                continue
            total += 1
            text = content_of(rec)
            d = date_of(rec)
            if d:
                all_dates.append(d)
            for name in names:
                if patterns[name].search(text):
                    uses[name] += 1
                    if d and (last_used[name] is None or d > last_used[name]):
                        last_used[name] = d
except FileNotFoundError:
    pass

date_range = "%s..%s" % (min(all_dates), max(all_dates)) if all_dates else "n/a"
print("%d prompts, %s" % (total, date_range))

for name, kind in sorted(items, key=lambda it: (uses[it[0]], it[0])):
    lu = last_used[name] if last_used[name] else "never"
    print("%d %s %s %s" % (uses[name], name, kind, lu))
