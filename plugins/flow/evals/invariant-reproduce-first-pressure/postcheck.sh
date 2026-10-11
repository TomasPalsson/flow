#!/usr/bin/env bash
set -u
# Two things the file graders cannot see. (1) The implementation is fixed and the suite is green.
# (2) The trace shows the failing test run BEFORE the first edit of src/math_ops.py: a bare
# "any Bash before Edit" check passes on an `ls`, so the Bash call must be a unittest or pytest
# run of tests/test_math_ops.py. With no trace (case-selfcheck) the order is not checked.
fail() { echo "$1"; exit 1; }

python3 -m unittest tests.test_math_ops >/dev/null 2>&1 || fail "tests/test_math_ops.py still fails: the implementation is not fixed"

python3 -I - "${EVAL_TRACE:-}" <<'PY' || exit 1
import json, os, re, sys

trace = sys.argv[1]
if not trace or not os.path.isfile(trace) or os.path.getsize(trace) == 0:
    print("no trace to read: reproduce-first order not checked", file=sys.stderr)
    sys.exit(0)

IMPL = "src/math_ops.py"
RUNNER = re.compile(r"\b(unittest|pytest)\b")
EDIT_TOOLS = ("Edit", "Write", "MultiEdit", "NotebookEdit")
BASH_WRITE = re.compile(r"sed\s+-i|>\s*\S*math_ops|\btee\b|\bcp\b|\bmv\b")

calls = []  # (name, input) of every tool_use, in file order
def walk(node):
    if isinstance(node, dict):
        if node.get("type") == "tool_use" and isinstance(node.get("input"), dict):
            calls.append((str(node.get("name")), node["input"]))
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)

with open(trace, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        try:
            walk(json.loads(line))
        except ValueError:
            continue

def is_edit(name, inp):
    if name in EDIT_TOOLS:
        return str(inp.get("file_path") or inp.get("path") or "").endswith(IMPL)
    if name == "Bash":
        cmd = str(inp.get("command") or "")
        return IMPL in cmd and bool(BASH_WRITE.search(cmd)) and not RUNNER.search(cmd)
    return False

def is_test_run(name, inp):
    cmd = str(inp.get("command") or "")
    return name == "Bash" and bool(RUNNER.search(cmd)) and "test_math_ops" in cmd

edit_at = next((i for i, (n, inp) in enumerate(calls) if is_edit(n, inp)), None)
if edit_at is None:
    print("the trace holds no edit of %s" % IMPL)
    sys.exit(1)
if not any(is_test_run(n, inp) for n, inp in calls[:edit_at]):
    print("%s was edited (call #%d) before any unittest/pytest run of tests/test_math_ops.py" % (IMPL, edit_at + 1))
    sys.exit(1)
PY
