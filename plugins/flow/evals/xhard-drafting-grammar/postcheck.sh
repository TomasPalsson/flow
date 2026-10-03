#!/usr/bin/env bash
set -u
# Drafting: TASKS.md is grammatical, covers every criterion, is unapproved, and
# nothing else moved.
fail() { echo "$1"; exit 1; }
PRISTINE=$(mktemp -d)
LINT=$(mktemp)
trap 'rm -rf "$PRISTINE" "$LINT"' EXIT
(cd "$PRISTINE" && bash "$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE/scaffold.sh" >/dev/null 2>&1) || fail "could not regenerate the pristine tree"

diff -r -x __pycache__ -x '*.pyc' -x .git -x .specs -x .claude "$PRISTINE" . >/dev/null \
	|| fail "source, tests or README changed: drafting must not edit code"
[ "$(git rev-list --count HEAD 2>/dev/null)" = "$(git -C "$PRISTINE" rev-list --count HEAD)" ] \
	|| fail "drafting made a commit"

DIR=.specs/001-low-stock-report
cmp -s "$PRISTINE/$DIR/spec.md" "$DIR/spec.md" || fail "spec.md was edited: drafting reads the spec, it does not rewrite it"
[ -s "$DIR/TASKS.md" ] || fail "no TASKS.md was drafted"
grep -rEq '^[[:space:]]*Approved:' .specs && fail "an Approved: line exists: drafting never approves its own plan"

node "$EVAL_PLUGIN_ROOT/bin/flow" lint "$DIR/TASKS.md" --json >"$LINT" 2>&1 || fail "flow lint reports an ERROR in TASKS.md"
python3 - "$DIR/TASKS.md" "$LINT" <<'PY' || exit 1
import json
import re
import subprocess
import sys

tasks_path, lint_path = sys.argv[1], sys.argv[2]
text = open(tasks_path, encoding="utf-8").read()
lint = json.load(open(lint_path, encoding="utf-8"))
if lint.get("warnings"):
    print("flow lint warns: %s" % json.dumps(lint["warnings"])[:160])
    sys.exit(1)

# a real Base, not the template's placeholder
m = re.search(r"Base:\s*([0-9a-f]{7,40})", text)
if not m or subprocess.run(["git", "cat-file", "-e", m.group(1) + "^{commit}"], capture_output=True).returncode:
    print("TASKS.md Base: is not a real commit in this repo")
    sys.exit(1)

task_re = re.compile(r"^- \[[ x~]\] ((?:T|CHK|G)\d+)\b(.*)$")
work = []
for line in text.splitlines():
    t = task_re.match(line)
    if not t:
        continue
    tid, rest = t.group(1), t.group(2)
    fm = re.search(r"files:\s*(.*?)\s+—\s+verify:", rest)
    if not fm:
        print("%s has no files:/verify: pair" % tid)
        sys.exit(1)
    if re.search(r"[*?\[]", fm.group(1)):
        print("%s lists a glob in files: %s" % (tid, fm.group(1)))
        sys.exit(1)
    verify = re.search(r"verify:\s*(.*?)(?:\s+—\s+after:.*)?$", rest).group(1)
    if tid.startswith("CHK"):
        if not verify.startswith("human:"):
            print("%s is a checkpoint but its verify is not human:" % tid)
            sys.exit(1)
    elif tid.startswith("T"):
        cmd = re.match(r"`([^`]+)`", verify)
        if not cmd:
            print("%s verify is not a backticked command: %s" % (tid, verify[:60]))
            sys.exit(1)
        prog = cmd.group(1).split()[0]
        if subprocess.run(["bash", "-c", "command -v " + prog], capture_output=True).returncode:
            print("%s verify runs '%s', which does not exist here" % (tid, prog))
            sys.exit(1)
        work.append(tid)
if not work:
    print("no T### tasks drafted")
    sys.exit(1)
if not re.search(r"^- \[ \] CHK\d+ ", text, re.M):
    print("no CHK### checkpoint for the criterion that needs a human's eyes")
    sys.exit(1)

# every acceptance criterion needs a Behaviors row (the row may open with B1 or with
# the spec's own AC id), and every row's Task column names a task or checkpoint that exists
spec_text = open(tasks_path.replace("TASKS.md", "spec.md"), encoding="utf-8").read()
acs = sorted(set(re.findall(r"\bAC-\d+\b", spec_text)))
beh = []
in_beh = False
for l in text.splitlines():
    if re.match(r"^##\s+Behaviors\b", l):
        in_beh = True
        continue
    if in_beh and l.startswith("#"):
        break
    if in_beh and l.strip().startswith("|"):
        cells = [c.strip() for c in l.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-+:?", c) for c in cells if c) or cells[0].lower() == "id":
            continue
        beh.append((l, cells))
if len(beh) < len(acs):
    print("Behaviors table has %d rows, the spec has %d acceptance criteria" % (len(beh), len(acs)))
    sys.exit(1)
for ac in acs:
    if not any(re.search(r"\b%s\b" % re.escape(ac), row) for row, _ in beh):
        print("%s from spec.md has no Behaviors row" % ac)
        sys.exit(1)
ids = set(re.findall(r"^- \[[ x~]\] ((?:T|CHK)\d+)\b", text, re.M))
for row, cols in beh:
    if len(cols) < 3 or cols[2] not in ids:
        print("Behaviors row names no existing task: %s" % row[:80])
        sys.exit(1)

# verify commands that run a tests/ module, every AC-n tag from the spec kept
# (a task may serve several criteria, so no task-count floor)
tasks_only = re.findall(r"^- \[[ x~]\] (T\d+)\b(.*)$", text, re.M)
for tid, body in tasks_only:
    cmd = re.search(r"verify:\s*`([^`]+)`", body)
    words = cmd.group(1).split() if cmd else []
    if not words or words[0] in ("true", "echo", ":", "exit") or "tests" not in cmd.group(1):
        print("%s verify does not run a tests/ module: %s" % (tid, cmd.group(1) if cmd else body[-60:]))
        sys.exit(1)
for ac in acs:
    if ac not in text:
        print("%s from spec.md appears nowhere in TASKS.md" % ac)
        sys.exit(1)

# the two src/reports.py tasks may never share a wave, and both must exist
waves = lint.get("waves") or []
touching = [tid for tid, body in re.findall(r"^- \[[ x~]\] ((?:T)\d+)\b(.*)$", text, re.M) if "src/reports.py" in body]
if len(touching) < 2:
    print("AC-1 and AC-3 both need src/reports.py, but %d task(s) list it" % len(touching))
    sys.exit(1)
for w in waves:
    if sum(1 for tid in touching if tid in w) > 1:
        print("two tasks that both edit src/reports.py share a wave: %s" % w)
        sys.exit(1)
PY

STATE=$(node "$EVAL_PLUGIN_ROOT/bin/flow" next --json --peek 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>/dev/null)
[ "$STATE" = "unapproved" ] || fail "router state is '$STATE', expected unapproved"
exit 0
