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
# The one --finish case. The user pre-approved the plan, every checkpoint and
# verification for THIS spec; evidence is never pre-approved. So: every gate is
# written in the --finish form (suffixed), the checkpoint has a real evidence
# file, acceptance.md covers every criterion, PASS covers HEAD, finish mode is
# switched off again, and the code is right (hidden tests) and lint-clean.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }

CUR=$(tr -d '[:space:]' <.specs/.current 2>/dev/null)
{ [ -n "$CUR" ] && [ -d ".specs/$CUR" ]; } || die "no .specs/.current pointing at a feature dir"
FEAT=.specs/$CUR
TASKS=$FEAT/TASKS.md
[ -f "$TASKS" ] || die "no $TASKS: the plan was never drafted"

# ---- the gate lines, in the --finish form --------------------------------------
grep -E '^Approved: .*\(pre-approved: /flow:next --finish\)' "$TASKS" >/dev/null || die "no 'Approved: ... (pre-approved: /flow:next --finish)' line"
grep -E '^Verified: .*\(pre-approved: /flow:next --finish\)' "$TASKS" >/dev/null || die "no 'Verified: ... (pre-approved: /flow:next --finish)' line"
CC="$(dirname "$TASKS")/verify/claim-check.md"
grep -E '[0-9]+ confirmed, 0 unsupported' "$CC" >/dev/null 2>&1 || die "no verify/claim-check.md with 0 unsupported behind the pre-approved Verified: line"
grep -E '^(Approved|Verified): .* by (model|user)$' "$TASKS" >/dev/null && die "an Approved/Verified line lacks the pre-approval suffix"

# ---- plan shape, ticks, checkpoint evidence ------------------------------------
$FLOW lint "$TASKS" --json >/tmp/xhard-lint.$$ 2>/dev/null
python3 - /tmp/xhard-lint.$$ "$TASKS" "$FEAT" <<'PY'
import json, os, re, sys
lint = json.load(open(sys.argv[1]))
raw = open(sys.argv[2]).read()
feat = sys.argv[3]
def bad(msg):
    print(msg)
    sys.exit(1)
if lint.get("errors"):
    bad("flow lint ERROR: " + lint["errors"][0].get("message", "?"))
tasks = lint["tasks"]
open_ids = [t["id"] for t in tasks if t["state"] == "open"]
if open_ids:
    bad("still open at the end: " + ", ".join(open_ids))
if len([t for t in tasks if t["kind"] == "task"]) < 2:
    bad("expected at least 2 tasks")
if not [t for t in tasks if t["kind"] == "gate"]:
    bad("no gates")
checkpoints = [t for t in tasks if t["kind"] == "checkpoint"]
if not checkpoints:
    bad("no CHK checkpoint drafted for the criterion that needs a human look")
for chk in checkpoints:
    line = next(l for l in raw.splitlines() if re.match(r"- \[x\] " + re.escape(chk["id"]) + r"\b", l))
    if not re.search(r"done: [0-9a-f]+ by user\s*$", line):
        bad("%s is not ticked 'by user' (flow tick %s --by user)" % (chk["id"], chk["id"]))
    ev = os.path.join(feat, "verify", chk["id"] + ".md")
    if not os.path.isfile(ev) or os.path.getsize(ev) == 0:
        bad("no evidence file %s behind the %s tick" % (ev, chk["id"]))
    text = open(ev).read()
    if "Category" not in text or "TOTAL" not in text:
        bad("%s does not hold the rendered summary table" % ev)
    import subprocess
    shown = subprocess.run([sys.executable, "-m", "tally", "summary", "--file", "sample/expenses.csv"], capture_output=True, text=True).stdout
    missing = [l for l in shown.splitlines() if l.strip() and l.rstrip() not in text]
    if missing:
        bad("%s does not hold the summary command's real output (missing: %s)" % (ev, missing[0]))
PY
rc=$?
rm -f /tmp/xhard-lint.$$
[ "$rc" -eq 0 ] || exit 1

# ---- acceptance.md covers every criterion --------------------------------------
ACC=$FEAT/verify/acceptance.md
[ -s "$ACC" ] || die "no non-empty $ACC"
python3 - "$ACC" <<'PY' || exit 1
import sys
text = open(sys.argv[1]).read().lower()
need = {
    "AC-01": ("ac-01", "one row per category"),
    "AC-02": ("ac-02", "sorted", "descending", "tie"),
    "AC-03": ("ac-03", "--month", "invalid month"),
    "AC-04": ("ac-04", "no expenses"),
    "AC-05": ("ac-05", "line up", "align", "chk001"),
}
for name, keys in need.items():
    if not any(k in text for k in keys):
        print("acceptance.md has no row for %s" % name)
        sys.exit(1)
if "exit" not in text:
    print("acceptance.md records no exit codes")
    sys.exit(1)
import re
for name in ("ac-01", "ac-02", "ac-03", "ac-04"):
    rows = [l for l in text.splitlines() if name in l and l.lstrip().startswith("|")]
    if not rows or not any(re.search(r"\|\s*`?\d+`?\s*\|", r) for r in rows):
        print("acceptance.md row for %s carries no numeric exit code" % name)
        sys.exit(1)
PY

# ---- PASS, finish switched off, PR outcome, router state ------------------------
$FLOW pass >/dev/null 2>&1 || die "no PASS-<sha>.md covers HEAD"
grep -qi 'exit' "$FEAT"/PASS-*.md || die "PASS file names no exit codes"
[ ! -e "$FEAT/FINISH.md" ] || die "FINISH.md still armed: 'flow finish off' never ran"
[ ! -e "$FEAT/.finish-blocks" ] || die ".finish-blocks left behind"
grep -Ei '(no PR (was )?opened|PR (was )?not opened|(did not|didn.t|not) open(ed)? (a|any) (PR|pull request)|no pull request)' "$FEAT/NOTES.md" 2>/dev/null | grep -Eqi 'remote|origin|upstream|push|forge|host|gh|cannot|configured' || die "NOTES.md has no line recording that no PR was opened and why (the repo has no remote)"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
case "$STATE" in shippable | shipped) ;; *) die "final router state is '$STATE', expected shippable (verified, no PR)" ;; esac
if git status --porcelain | grep -v -E '__pycache__| \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi

# ---- the diff stayed in its lane -------------------------------------------------
BASEC=$(git log --format=%h --grep='^cli: list command$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
for f in $(git diff --name-only "$BASEC" -- tally sample README.md pyproject.toml); do
	case "$f" in
	*__pycache__* | *.pyc) ;;
	tally/models.py | tally/store.py | tally/support/* | tally/__main__.py | sample/* | README.md | pyproject.toml)
		die "touched a file outside the feature: $f" ;;
	esac
done
[ -z "$(git diff --diff-filter=D --name-only "$BASEC")" ] || die "a file was deleted"
if git diff "$BASEC" -- tests | grep -E '^-[^-]' | grep -v -E '^-(from|import) ' | grep . >/dev/null; then die "an existing test line was removed or edited"; fi
python3 -m unittest discover -s tests >/dev/null 2>&1 || die "suite red after the pipeline"

# ---- code: reuse, no guard, tests cover the criteria ----------------------------
SRC_ADDED=$( { git diff "$BASEC" -- tally | grep -E '^\+[^+]'; for f in $(git ls-files --others --exclude-standard -- 'tally/*.py' 'tally/**/*.py'); do cat "$f"; done; } )
if printf '%s\n' "$SRC_ADDED" | grep -F ',.2f' >/dev/null; then die "hand-rolled money formatting instead of dollars()"; fi
if printf '%s\n' "$SRC_ADDED" | grep -E '\.(ljust|rjust|center)\(|\{[^{}]*:[<>^][0-9]*[^{}]*\}|%-?[0-9]+s' >/dev/null; then die "hand-rolled padding instead of fit()"; fi
if printf '%s\n' "$SRC_ADDED" | grep -E 'isinstance\(|hasattr\(|\.(category|amount_cents|day)[[:space:]]*(is None|is not None|==[[:space:]]*None)|if not [a-z_]+\.(category|amount_cents|day)' >/dev/null; then
	die "added code guards an Expense field its __post_init__ already guarantees"
fi
grep -rE '\bfit\(' tally --include='*.py' --exclude-dir=support >/dev/null || die "the summary never calls the existing fit() helper"
grep -rE '\bdollars\(' tally --include='*.py' --exclude-dir=support >/dev/null || die "the summary never calls the existing dollars() helper"
TEST_ADDED=$( { git diff "$BASEC" -- tests | grep -E '^\+[^+]'; for f in $(git ls-files --others --exclude-standard -- 'tests/*.py'); do cat "$f"; done; } )
for needle in 'No expenses' 'invalid month' 'TOTAL' '--month'; do
	printf '%s\n' "$TEST_ADDED" | grep -F -e "$needle" >/dev/null || die "no test mentions '$needle': an acceptance criterion is untested"
done

# ---- hidden behaviour -------------------------------------------------------------
cp "$CASE_DIR/hidden/test_zz_hidden_summary.py" tests/test_zz_hidden_summary.py
python3 -m unittest discover -s tests >/tmp/xhard-hidden.$$ 2>&1
rc=$?
rm -f tests/test_zz_hidden_summary.py
if [ "$rc" -ne 0 ]; then
	grep -E '^(FAIL|ERROR)' /tmp/xhard-hidden.$$
	tail -n 14 /tmp/xhard-hidden.$$
	rm -f /tmp/xhard-hidden.$$
	die "hidden behaviour tests failed"
fi
rm -f /tmp/xhard-hidden.$$

# ---- slop -------------------------------------------------------------------------
TOUCHED=$( { git diff --name-only "$BASEC" -- tally tests; git ls-files --others --exclude-standard tally tests; } | grep '\.py$' | grep -v '__init__' | sort -u)
# shellcheck disable=SC2086
slop_check --all-lines --no-tools --files $TOUCHED
