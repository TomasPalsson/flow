#!/usr/bin/env bash
set -u
# src/notifications.py's scaffolded send_email stands in for a real mail
# backend using print(...) - a fixture choice that predates this postcheck.
# Under --all-lines every line of the file counts as "added", so that one
# pre-existing print always trips NS-08 regardless of the task; every other
# finding (including a new print/debug leftover the task's own edit adds)
# still fails the check.
python3 - src/notifications.py "$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" <<'PY'
import json
import subprocess
import sys

path, slop_check = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
base_print_lines = {i + 1 for i, line in enumerate(lines)
                     if line.strip().startswith("print(") and "EMAIL to" in line}

r = subprocess.run([slop_check, "--all-lines", "--json", "--files", path],
                    capture_output=True, text=True)
report = json.loads(r.stdout)
other = [f for f in report["findings"]
         if not (f["id"] == "NS-08" and f["line"] in base_print_lines)]
for f in other:
    print(f"{f['file']}:{f['line']}: {f['id']} {f['msg']}")
sys.exit(1 if other else 0)
PY
