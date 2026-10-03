#!/usr/bin/env bash
set -u
# slop-check with every finding fatal except NS-16 (advisory: spelling similarity only)
slop_check() {
	local out rc
	out=$("$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" "$@") || rc=$?
	[ "${rc:-0}" -eq 0 ] || { printf '%s\n' "$out"; return "$rc"; }
	out=$(printf '%s\n' "$out" | grep -v ': NS-16 ')
	[ -z "$out" ] || { printf '%s\n' "$out"; return 1; }
}
# A drafted 12-task, 4-wave, 2-phase plan on autoApprove, run to the end: approved by the
# model at the gate, every task ticked through flow tick with the commit that touched ITS
# files (12 distinct shas), waves respected in commit order, each phase's Independent test
# executed (phase 1 BEFORE phase 2 starts, per the trace), gates -> PASS-<HEAD>.md, stopped
# at unverified without Verified:. Then behaviour: hidden tests per task, helper reuse,
# mutants of the model's own tests, slop. One reason line on failure.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
FEAT=.specs/001-log-report
TASKS=$FEAT/TASKS.md
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; rm -f /tmp/xtw-*.$$ tests/_hidden_logreport.py; }
trap cleanup EXIT

[ -f "$TASKS" ] || die "TASKS.md is gone"
PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot rebuild the pristine tree"
PHEAD=$(git -C "$PRISTINE" rev-parse HEAD)
BASEC=$(git log --format=%h --grep='^base: logkit clock, tables, reader$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"

# ---- the plan: lint clean, all twelve ticked, approved by the model, no Verified: ----
$FLOW lint "$TASKS" --json >/tmp/xtw-lint.$$ 2>/dev/null
python3 - /tmp/xtw-lint.$$ <<'PY' || exit 1
import json, sys
d = json.load(open(sys.argv[1]))
def bad(msg):
    print(msg)
    sys.exit(1)
if not d.get("ok") or d.get("errors"):
    bad("flow lint reports errors (a lying or malformed tick)")
tasks = d["tasks"]
work = [t for t in tasks if t["kind"] == "task"]
gates = [t for t in tasks if t["kind"] == "gate"]
if len(work) != 12 or len({t["phase"] for t in work}) != 2:
    bad("the plan was rewritten: expected 12 tasks in 2 phases, found %d in %d" % (len(work), len({t["phase"] for t in work})))
open_ids = [t["id"] for t in tasks if t["state"] != "done"]
if open_ids:
    bad("not ticked at the end: " + ", ".join(open_ids))
if len(gates) != 2:
    bad("the gates were rewritten")
if d["header"].get("verified"):
    bad("Verified: is written; that fact is the human's, the run must stop at unverified")
PY
[ $? -eq 0 ] || exit 1
grep -Eq '^Approved: [0-9]{4}-[0-9]{2}-[0-9]{2} by model \(autoApprove\)' "$TASKS" || die "no 'Approved: <date> by model (autoApprove)' line: the unapproved gate was skipped or mis-written"
grep -Eq '^[[:space:]]*Verified:' "$TASKS" && die "Verified: written by the model"
if grep -rEq '^[[:space:]]*Verified:' .specs --include='*.md' 2>/dev/null; then die "a Verified: line exists under .specs"; fi
# the plan is otherwise the plan that was drafted: ticks, done: shas, Approved: and Base: aside
norm() { grep -v -e '^Approved:' -e '^Base:' "$1" | sed -E -e 's/^- \[x\] /- [ ] /' -e 's/ — done: [0-9a-f]+$//' -e 's/Base: [0-9a-f]+/Base: X/'; }
[ "$(norm "$TASKS")" = "$(norm "$PRISTINE/$TASKS")" ] || die "TASKS.md changed beyond ticks and the Approved:/Base: lines (a task line or a header was rewritten)"

# ---- gates: PASS for HEAD, exit codes named, router at unverified ------------------
$FLOW pass >/dev/null 2>&1 || die "no PASS-<sha>.md covers HEAD"
grep -qi 'exit' "$FEAT"/PASS-*.md || die "PASS file names no exit codes"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "unverified" ] || die "final router state is '$STATE', expected unverified"
if git status --porcelain | grep -v -E '__pycache__| \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi
python3 -m unittest discover -s tests >/dev/null 2>&1 || die "suite red after the pipeline"

# ---- each task ticked with ITS commit; waves respected in commit order --------------
git rev-list --reverse "$BASEC"..HEAD >/tmp/xtw-order.$$
python3 - "$TASKS" /tmp/xtw-order.$$ <<'PY' || exit 1
import re, subprocess, sys

tasks_path, order_path = sys.argv[1:3]
order = {}
for i, full in enumerate(open(order_path).read().split()):
    order[full] = i
def bad(msg):
    print(msg)
    sys.exit(1)

modules = {
    "T001": "parse", "T004": "parse", "T002": "levels", "T005": "levels", "T003": "window", "T006": "window",
    "T007": "filters", "T010": "filters", "T008": "stats", "T011": "stats", "T009": "render", "T012": "render",
}
waves = [["T001", "T002", "T003"], ["T004", "T005", "T006"], ["T007", "T008", "T009"], ["T010", "T011", "T012"]]
pos, shas = {}, {}
for line in open(tasks_path, encoding="utf-8"):
    m = re.match(r"^- \[x\] (T\d{3}) .*— done: ([0-9a-f]{7,40})\s*$", line)
    if not m:
        continue
    tid, short = m.groups()
    full = subprocess.run(["git", "rev-parse", short], capture_output=True, text=True).stdout.strip()
    if full not in order:
        bad("%s's done: %s is not a commit after the scaffold's base" % (tid, short))
    files = subprocess.run(["git", "show", "--name-only", "--format=", full], capture_output=True, text=True).stdout.split()
    mod = modules[tid]
    allowed = {"logkit/%s.py" % mod, "tests/test_%s.py" % mod}
    if "logkit/%s.py" % mod not in files:
        bad("%s's done: commit %s did not touch logkit/%s.py" % (tid, short, mod))
    stray = [f for f in files if f not in allowed]
    if stray:
        bad("%s's done: commit %s also touched %s (one commit per task, its own files only)" % (tid, short, stray[0]))
    pos[tid], shas[tid] = order[full], full
if len(pos) != 12:
    bad("only %d of 12 tasks carry a done: sha" % len(pos))
if len(set(shas.values())) != 12:
    bad("the twelve tasks do not carry twelve distinct done: shas (commits were folded together or ticks lagged a wave)")
for a, b in zip(waves, waves[1:]):
    late = max(a, key=lambda t: pos[t])
    early = min(b, key=lambda t: pos[t])
    if pos[late] > pos[early]:
        bad("wave order broken: %s was committed after %s, which is a later wave" % (late, early))
PY
[ $? -eq 0 ] || exit 1

# ---- the trace: each Independent test executed; phase 1's BEFORE phase 2 starts -----
python3 - "${EVAL_TRACE:-}" <<'PY' || exit 1
import json, os, re, sys

trace_path = sys.argv[1]
if not trace_path or not os.path.isfile(trace_path) or os.path.getsize(trace_path) == 0:
    print("no trace to read: Independent test order not checked", file=sys.stderr)
    sys.exit(0)
P1 = ("tests.test_parse", "tests.test_levels", "tests.test_window")
P2 = ("tests.test_filters", "tests.test_stats", "tests.test_render")
events = []  # (kind, text, main_thread)
def walk(node, main):
    if isinstance(node, dict):
        if node.get("type") == "tool_use" and isinstance(node.get("input"), dict):
            inp = node["input"]
            events.append((node.get("name"), json.dumps(inp), main, inp.get("command") if isinstance(inp.get("command"), str) else ""))
        for v in node.values():
            walk(v, main)
    elif isinstance(node, list):
        for v in node:
            walk(v, main)
for line in open(trace_path, encoding="utf-8", errors="replace"):
    try:
        ev = json.loads(line)
    except ValueError:
        continue
    walk(ev, not ev.get("parent_tool_use_id"))
def ran(idx, mods):
    name, blob, main, cmd = events[idx]
    return name == "Bash" and "unittest" in cmd and all(m in cmd for m in mods)
def phase2_start(idx):
    name, blob, main, cmd = events[idx]
    if name in ("Agent", "Task") and re.search(r"T00[789]|T01[012]", blob):
        return True
    if name == "Bash" and "task-brief" in cmd and re.search(r"T00[789]|T01[012]", cmd):
        return True
    if name in ("Write", "Edit") and re.search(r"logkit/(filters|stats|render)\.py|tests/test_(filters|stats|render)\.py", blob):
        return True
    return False
p1 = [i for i in range(len(events)) if events[i][2] and ran(i, P1)]
p2 = [i for i in range(len(events)) if events[i][2] and ran(i, P2)]
if not p1:
    print("phase 1's Independent test was never executed (no Bash command runs tests.test_parse tests.test_levels tests.test_window)")
    sys.exit(1)
if not p2:
    print("phase 2's Independent test was never executed (no Bash command runs tests.test_filters tests.test_stats tests.test_render)")
    sys.exit(1)
starts = [i for i in range(len(events)) if phase2_start(i)]
if starts and min(starts) < min(p1):
    print("phase 2 started (%s) before phase 1's Independent test was executed" % events[min(starts)][0])
    sys.exit(1)
PY
[ $? -eq 0 ] || exit 1

# ---- the diff stayed in its lane ---------------------------------------------------
while IFS= read -r f; do
	case "$f" in .specs/* | .claude/*) continue ;; esac
	cmp -s "$PRISTINE/$f" "$f" || die "$f was changed: the plan only adds modules and their tests"
done < <(cd "$PRISTINE" && git ls-files)
changed=$( { git diff --name-only "$PHEAD"; git ls-files --others --exclude-standard; } | sort -u)
extra=$(printf '%s\n' "$changed" | grep -v -E -e '^logkit/(parse|levels|window|filters|stats|render)\.py$' -e '^tests/test_(parse|levels|window|filters|stats|render)\.py$' -e '^\.specs/' -e '^\.claude/' | head -1)
[ -z "$extra" ] || die "out-of-plan file touched: $extra"
for f in logkit/parse.py logkit/levels.py logkit/window.py logkit/filters.py logkit/stats.py logkit/render.py \
	tests/test_parse.py tests/test_levels.py tests/test_window.py tests/test_filters.py tests/test_stats.py tests/test_render.py; do
	[ -s "$f" ] || die "$f is missing or empty"
done
git diff --diff-filter=D --name-only "$PHEAD" | grep -q . && die "a file was deleted"

# ---- hand-rolled time and padding instead of the shared helpers ----------------------
grep -Eq 'import datetime|from datetime|strptime|strftime|timegm|mktime|import time|import calendar' logkit/parse.py logkit/window.py logkit/render.py logkit/filters.py logkit/stats.py &&
	die "new code does its own time handling instead of logkit.support.clock"
grep -q 'to_epoch' logkit/parse.py || die "parse.py does not use the existing to_epoch"
grep -q 'to_epoch' logkit/window.py || die "window.py does not use the existing to_epoch"
grep -q 'to_stamp' logkit/render.py || die "render.py does not use the existing to_stamp"
grep -q 'pad_right' logkit/render.py || die "render.py does not use the existing pad_right"

# ---- hidden behaviour, per task -----------------------------------------------------
CLASSES="TestParseLine TestParseLines TestLevelRank TestAtLeast TestInWindow TestWindowFromStamps TestFilterRecords TestForService TestCountByLevel TestTopMessages TestRenderRow TestRenderReport"
run_class() { # <tree dir> <class>
	cp "$CASE_DIR/hidden/test_logreport_hidden.py" "$1/tests/_hidden_logreport.py"
	(cd "$1" && python3 -m unittest "tests._hidden_logreport.$2" >/tmp/xtw-out.$$ 2>&1)
	local rc=$?
	rm -f "$1/tests/_hidden_logreport.py"
	return $rc
}
failed=""
for c in $CLASSES; do
	run_class . "$c" || failed="$failed $c"
done
[ -z "$failed" ] || { tail -n 8 /tmp/xtw-out.$$; die "hidden behaviour tests failed for:$failed"; }

# ---- reuse is real: break each shared helper in a copy, the dependent behaviour must notice
break_helper() { # <name> <file> <content> <classes...>
	local name=$1 file=$2 content=$3 dir c
	shift 3
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	rm -rf "$dir/t/.git"
	printf '%s\n' "$content" >"$dir/t/$file"
	for c in "$@"; do
		if run_class "$dir/t" "$c"; then die "$c does not depend on the shared $name helper: it was re-implemented"; fi
	done
}
break_helper to_epoch logkit/support/clock.py 'def to_epoch(stamp):
    return 0


def to_stamp(epoch):
    return "STAMP"' TestParseLine TestWindowFromStamps
break_helper to_stamp logkit/support/clock.py 'import calendar
import time


def to_epoch(stamp):
    return calendar.timegm(time.strptime(stamp, "%Y-%m-%dT%H:%M:%SZ"))


def to_stamp(epoch):
    return "STAMP"' TestRenderRow TestRenderReport
break_helper pad_right logkit/support/tables.py 'def pad_right(text, width):
    return "@@" + text' TestRenderRow TestRenderReport

# ---- mutants: the model's OWN tests must catch each -------------------------------------
mutate() { # <name> <module file> <test module> <appended code>
	local dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	rm -rf "$dir/t/.git"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	printf '\n\n%s\n' "$4" >>"$dir/t/$2"
	if (cd "$dir/t" && python3 -m unittest "$3" >/dev/null 2>&1); then
		die "mutant survived ($1): the model's tests do not pin it"
	fi
}
mutate "window end inclusive" logkit/window.py tests.test_window 'def in_window(ts, start, end):
    return (start is None or ts >= start) and (end is None or ts <= end)'
mutate "floor is strict" logkit/levels.py tests.test_levels 'def at_least(level, floor):
    return level_rank(level) > level_rank(floor)'
mutate "blank lines counted as malformed" logkit/parse.py tests.test_parse '_orig_parse_lines = parse_lines


def parse_lines(lines):
    lines = list(lines)
    records, bad = _orig_parse_lines(lines)
    return records, bad + sum(1 for line in lines if not line.strip())'
mutate "level counts drop zeros" logkit/stats.py tests.test_stats '_orig_count = count_by_level


def count_by_level(records):
    return {k: v for k, v in _orig_count(records).items() if v}'
mutate "top messages off by one" logkit/stats.py tests.test_stats '_orig_top = top_messages


def top_messages(records, n):
    return _orig_top(records, n + 1)'
mutate "floor ignored" logkit/filters.py tests.test_filters '_orig_filter = filter_records


def filter_records(records, floor=None, start=None, end=None):
    return _orig_filter(records, None, start, end)'
mutate "malformed count dropped from the report" logkit/render.py tests.test_render '_orig_report = render_report


def render_report(records, malformed=0):
    return _orig_report(records, 0)'
mutate "empty errors section is blank" logkit/render.py tests.test_render '_orig_report2 = render_report


def render_report(records, malformed=0):
    return _orig_report2(records, malformed).replace("\n  none", "")'

# ---- slop ---------------------------------------------------------------------------
slop_check --all-lines --no-tools --files logkit/parse.py logkit/levels.py logkit/window.py logkit/filters.py logkit/stats.py logkit/render.py \
	tests/test_parse.py tests/test_levels.py tests/test_window.py tests/test_filters.py tests/test_stats.py tests/test_render.py
