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
# Monorepo: .specs at the repo root, the task in services/worker. The wave was
# built and ticked from the root, the worker's tests (not the api's) decided it,
# the api service and the developer's stray work in it are byte-identical, the
# task's commit holds exactly its two files, and describe_job reuses the worker's
# clock_span. Then mutants against the model's own tests and hidden behaviour.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; }
trap cleanup EXIT

FEAT=.specs/001-job-status-line
TASKS=$FEAT/TASKS.md
[ -f "$TASKS" ] || die "TASKS.md is gone"
REPORT=services/worker/worker/report.py
TEST=services/worker/tests/test_report.py
[ -f "$REPORT" ] || die "$REPORT was never written"
[ -f "$TEST" ] || die "$TEST was never written"

# ---- the plan: T001 ticked by flow tick, nothing else moved ----------------------
$FLOW lint "$TASKS" --json >/tmp/xmr-lint.$$ 2>/dev/null
python3 - /tmp/xmr-lint.$$ <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
def bad(msg):
    print(msg)
    sys.exit(1)
if not d.get("ok") or d.get("errors"):
    bad("flow lint reports errors (a lying or malformed tick)")
tasks = {t["id"]: t for t in d["tasks"]}
if tasks.get("T001", {}).get("state") != "done":
    bad("T001 is not ticked")
for gid in ("G001", "G002"):
    if tasks.get(gid, {}).get("state") != "open":
        bad("%s was ticked: the gates are the next turn's state, not this one's" % gid)
if d["header"].get("verified"):
    bad("Verified: is written")
if not d["header"].get("approved"):
    bad("the Approved: line was removed")
PY
rc=$?
rm -f /tmp/xmr-lint.$$
[ "$rc" -eq 0 ] || exit 1
ls "$FEAT"/PASS-*.md >/dev/null 2>&1 && die "a PASS file exists: gating is not this turn's state"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "gating" ] || die "final router state is '$STATE', expected gating"

# ---- nothing outside the task moved ---------------------------------------------
PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot rebuild the pristine tree"
DIFFS=$(diff -rq -x .git -x .specs -x .claude -x __pycache__ "$PRISTINE" . | grep -v -e "Only in ./services/worker/worker: report.py" -e "Only in ./services/worker/tests: test_report.py")
[ -z "$DIFFS" ] || die "files outside the task changed: $(printf '%s' "$DIFFS" | head -1)"
git ls-files --error-unmatch services/api/scratch.log >/dev/null 2>&1 && die "the developer's stray services/api/scratch.log was committed"
git status --porcelain -- services/api | grep -q 'services/api/src/handler.js' || die "the developer's uncommitted services/api/src/handler.js edit was committed or reverted"
PLANC=$(git log --format=%h --grep='^plan: job status line, approved$' -n 1)
[ -n "$PLANC" ] || die "scaffold history missing"
OUT=$(git diff --name-only "$PLANC"..HEAD | grep -v -e '^\.specs/' -e '^\.claude/' | grep -v -x -e "$REPORT" -e "$TEST")
[ -z "$OUT" ] || die "a commit touched a file outside the task: $(printf '%s' "$OUT" | head -1)"
if git status --porcelain | grep -v -E ' \.specs/| \.claude/|services/api/src/handler\.js|services/api/scratch\.log' | grep . >/dev/null; then
	die "the task's files were left uncommitted"
fi
DONE=$(grep -E '^- \[x\] T001 ' "$TASKS" | sed -E 's/.*— done: ([0-9a-f]+).*/\1/')
[ -n "$DONE" ] || die "T001 has no done: sha"
FILES=$(git show --name-only --format= "$DONE" | sort | tr '\n' ' ')
WANT=$(printf '%s\n%s\n' "$REPORT" "$TEST" | sort | tr '\n' ' ')
[ "$FILES" = "$WANT" ] || die "the commit T001 names holds '$FILES' instead of exactly the task's two files"

# ---- the worker's tests, run the worker's way ------------------------------------
(cd services/worker && python3 -m unittest discover -s tests >/dev/null 2>&1) || die "the worker's suite is red"

# ---- code: reuse of clock_span, no hand-rolled arithmetic, no guards -------------
python3 - <<'PY' || exit 1
import ast, sys
def bad(msg):
    print(msg)
    sys.exit(1)
tree = ast.parse(open("services/worker/worker/report.py").read())
def imports_clock_span(n):
    if isinstance(n, ast.ImportFrom):
        if n.module == "lib.durations":
            return any(a.name == "clock_span" for a in n.names)
        if n.module == "lib":
            return any(a.name == "durations" for a in n.names)
    if isinstance(n, ast.Import):
        return any(a.name == "lib.durations" for a in n.names)
    return False
if not any(imports_clock_span(n) for n in ast.walk(tree)):
    bad("report.py does not import clock_span from lib.durations")
def calls_clock_span(n):
    if not isinstance(n, ast.Call):
        return False
    return (isinstance(n.func, ast.Name) and n.func.id == "clock_span") or (isinstance(n.func, ast.Attribute) and n.func.attr == "clock_span")
if not any(calls_clock_span(n) for n in ast.walk(tree)):
    bad("report.py never calls clock_span")
for n in ast.walk(tree):
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ("divmod", "isinstance", "hasattr", "round"):
        bad("report.py hand-rolls the span or guards a value Job already validates (%s)" % n.func.id)
    if isinstance(n, ast.BinOp) and isinstance(n.op, (ast.FloorDiv, ast.Div)):
        bad("report.py does duration arithmetic by hand instead of clock_span")
    if isinstance(n, ast.Constant) and n.value in (60, 3600):
        bad("report.py hard-codes a duration constant instead of clock_span")
    if isinstance(n, (ast.Raise, ast.Assert, ast.Try)):
        bad("report.py guards a value Job already validates")
    if isinstance(n, ast.Compare) and any(isinstance(o, (ast.Is, ast.IsNot)) for o in n.ops):
        bad("report.py guards a value Job already validates")
    if isinstance(n, ast.ImportFrom) and n.module in ("datetime", "time") or isinstance(n, ast.Import) and any(a.name in ("datetime", "time") for a in n.names):
        bad("report.py reaches for a time library instead of clock_span")
PY
[ $? -eq 0 ] || exit 1

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each ----------
wrap() { # <name> <python body of the wrapper>
	local name=$1 body=$2 dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	printf '\n\n_real_describe_job = describe_job\n\n\ndef describe_job(job, now):\n%s\n' "$body" >>"$dir/t/$REPORT"
	(cd "$dir/t/services/worker" && python3 -c 'import worker.report' >/dev/null 2>&1) || die "mutant '$name' does not import: report.py has no top-level describe_job"
	if (cd "$dir/t/services/worker" && python3 -m unittest discover -s tests >/dev/null 2>&1); then
		die "mutant survived ($name): the model's tests do not pin it"
	fi
}
wrap "done wording" '    return _real_describe_job(job, now).replace(": done in ", ": done after ")'
wrap "running wording" '    return _real_describe_job(job, now).replace(": running for ", ": running ")'
wrap "queued wording" '    return _real_describe_job(job, now).replace(": queued", ": waiting")'
wrap "running span off by one" '    return _real_describe_job(job, now + 1 if job.state == "running" else now)'
wrap "done span off by one" '    import dataclasses
    if job.state == "done":
        job = dataclasses.replace(job, finished_at=job.finished_at + 1)
    return _real_describe_job(job, now)'
wrap "done span measured to now" '    import dataclasses
    if job.state == "done":
        job = dataclasses.replace(job, finished_at=now)
    return _real_describe_job(job, now)'
wrap "running span measured from zero" '    import dataclasses
    if job.state == "running":
        job = dataclasses.replace(job, started_at=0)
    return _real_describe_job(job, now)'

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>
	cp "$CASE_DIR/hidden/test_report_hidden.py" "$1/services/worker/tests/_hidden_test_report.py"
	(cd "$1/services/worker" && python3 -m unittest tests._hidden_test_report >/tmp/xmr-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/services/worker/tests/_hidden_test_report.py"
	return $rc
}
if ! run_hidden .; then
	tail -n 12 /tmp/xmr-hidden.$$
	rm -f /tmp/xmr-hidden.$$
	die "hidden behaviour tests failed"
fi
dir=$(mktemp -d)
TMPS+=("$dir")
cp -a . "$dir/t"
printf 'def clock_span(seconds: int) -> str:\n    return "SPAN"\n' >"$dir/t/services/worker/lib/durations.py"
if run_hidden "$dir/t"; then
	rm -f /tmp/xmr-hidden.$$
	die "describe_job does not depend on the worker's clock_span: reuse is faked"
fi
rm -f /tmp/xmr-hidden.$$

# ---- slop ---------------------------------------------------------------------
slop_check --all-lines --no-tools --files "$REPORT" "$TEST"
