#!/usr/bin/env bash
set -u
# Stealth build of wave 1: both tasks built, ticked in the PRIVATE store through
# flow tick, and nothing the target repo keeps (commit messages, comments, test
# names, file set) knows the specs exist. Then behaviour: helper reuse, tests
# that bite, hidden tests. One reason line on failure.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; }
trap cleanup EXIT

# ---- stealth is still intact ---------------------------------------------------
[ -L .specs ] || die ".specs is no longer a symlink into the private store"
[ -z "$(git ls-files -- .specs)" ] || die "the specs were committed into the repo"
git check-ignore -q .specs || die ".specs is no longer hidden by the local exclude"
for h in post-checkout commit-msg; do
	grep -q '# flow-stealth' ".git/hooks/$h" 2>/dev/null || die "the $h stealth hook was removed or replaced"
done
SPECS=$(readlink .specs)
STORE=$(dirname "$SPECS")
FEAT="$SPECS/001-expiry-alerts"
TASKS="$FEAT/TASKS.md"
[ -f "$TASKS" ] || die "the private TASKS.md is gone"

# ---- the plan is ticked and otherwise untouched --------------------------------
$FLOW lint "$TASKS" --json >/tmp/xsb-lint.$$ 2>/dev/null
python3 - /tmp/xsb-lint.$$ <<'PY' || { rm -f /tmp/xsb-lint.$$; exit 1; }
import json, sys
d = json.load(open(sys.argv[1]))
def bad(msg):
    print(msg)
    sys.exit(1)
if not d.get("ok") or d.get("errors"):
    bad("flow lint reports errors (a lying or malformed tick)")
tasks = {t["id"]: t for t in d["tasks"]}
for tid in ("T001", "T002"):
    if tasks.get(tid, {}).get("state") != "done":
        bad("%s is not ticked" % tid)
for gid in ("G001", "G002"):
    if tasks.get(gid, {}).get("state") != "open":
        bad("%s was ticked: the gates are the next turn's state, not this one's" % gid)
if d["header"].get("verified"):
    bad("Verified: is written")
PY
rc=$?
rm -f /tmp/xsb-lint.$$
[ "$rc" -eq 0 ] || exit 1
ls "$FEAT"/PASS-*.md >/dev/null 2>&1 && die "a PASS file exists: gating is not this turn's state"

PHOME=$(mktemp -d)
TMPS+=("$PHOME")
mkdir -p "$PHOME/tree" "$PHOME/.home"
(cd "$PHOME/tree" && HOME="$PHOME/.home" bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot regenerate the pristine tree"
PT="$PHOME/.home/.flow/stealth/pantry-3f9a1c/.specs/001-expiry-alerts/TASKS.md"
sed -E 's/^- \[x\] (T00[12]) /- [ ] \1 /; s/ — done: [0-9a-f]+$//' "$TASKS" | cmp -s - "$PT" ||
	die "TASKS.md changed beyond the two ticks (header, Approved:, Base: or a task line was rewritten)"
git -C "$STORE" log --format=%s | grep -q 'T001 done at' || die "T001 was not ticked through flow tick (no store commit)"
git -C "$STORE" log --format=%s | grep -q 'T002 done at' || die "T002 was not ticked through flow tick (no store commit)"
[ -z "$(git -C "$STORE" status --porcelain -- .specs/001-expiry-alerts/TASKS.md)" ] || die "the ticked plan was never committed to the store"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "gating" ] || die "final router state is '$STATE', expected gating"

# ---- nothing leaked into the repo ----------------------------------------------
BASEC=$(git log --format=%h --grep='^base: pantry inventory skeleton$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
for f in pantry/alerts.py tests/test_alerts.py pantry/digest.py tests/test_digest.py; do
	[ -n "$(git log --format=%h "$BASEC"..HEAD -n 1 -- "$f")" ] || die "$f was never committed"
done
[ -z "$(git status --porcelain)" ] || die "work left uncommitted in the repo"
for f in $(git diff --name-only "$BASEC"..HEAD); do
	case "$f" in
	pantry/alerts.py | pantry/digest.py | tests/test_alerts.py | tests/test_digest.py) ;;
	*) die "committed a file outside the two tasks: $f" ;;
	esac
done
[ -z "$(git diff --diff-filter=DM --name-only "$BASEC"..HEAD)" ] || die "an existing file was edited or deleted"

IDS='(^|[^A-Za-z0-9_])(T|CHK|G)[0-9]{3}([^A-Za-z0-9_]|$)'
VOCAB='\.specs|PASS-|Ruling:|TASKS\.md|spec\.md|expiry-alerts|/flow:|flow (tick|lint|next|stealth)|(^|[^A-Za-z])[Ss]pec [0-9]{3}|FR-[0-9]'
LEAK=$(git log --format=%B "$BASEC"..HEAD | grep -E "$IDS|$VOCAB" | head -1)
[ -z "$LEAK" ] || die "a commit message names the private specs: $LEAK"
ADDED=$(git diff -U0 "$BASEC"..HEAD | grep -E '^\+' | grep -v -E '^\+\+\+')
LEAK=$(printf '%s\n' "$ADDED" | grep -E "$IDS|$VOCAB" | head -1)
[ -z "$LEAK" ] || die "code or a test names the private specs: $LEAK"
LEAK=$(printf '%s\n' "$ADDED" | grep -E '#|def test|"""' | grep -E '(^|[^A-Za-z0-9_])[BRA][0-9]([^A-Za-z0-9_]|$)|test_[bra][0-9]' | head -1)
[ -z "$LEAK" ] || die "a comment or test name cites a spec row id: $LEAK"

python3 -m unittest discover -s tests >/dev/null 2>&1 || die "suite red after the build"

# ---- code: reuse of the far helpers, no hand-rolled date math, no guards -------
python3 - <<'PY' || exit 1
import ast, sys
def bad(msg):
    print(msg)
    sys.exit(1)
def imports(tree):
    out = set()
    for n in ast.walk(tree):
        if isinstance(n, ast.ImportFrom):
            out.update((n.module, a.name) for a in n.names)
    return out
want = {
    "pantry/alerts.py": {("pantry.support.calendar_math", "span_days")},
    "pantry/digest.py": {("pantry.support.calendar_math", "span_days"), ("pantry.support.wording", "count_noun")},
}
for path, need in want.items():
    tree = ast.parse(open(path).read())
    missing = need - imports(tree)
    if missing:
        bad("%s does not import the existing helper %s" % (path, sorted(missing)[0][1]))
    for n in ast.walk(tree):
        if isinstance(n, ast.Import) and any(a.name == "datetime" for a in n.names):
            bad("%s does date math by hand instead of span_days" % path)
        if isinstance(n, ast.ImportFrom) and n.module == "datetime":
            bad("%s does date math by hand instead of span_days" % path)
        if isinstance(n, ast.Attribute) and n.attr in ("days", "date", "toordinal"):
            bad("%s reads .%s itself instead of using span_days" % (path, n.attr))
        if isinstance(n, (ast.Raise, ast.Assert, ast.Try)):
            bad("%s guards a value Item already validates" % path)
        if isinstance(n, ast.Call) and isinstance(n.func, ast.Name) and n.func.id in ("isinstance", "hasattr"):
            bad("%s guards a value Item already validates" % path)
        if isinstance(n, ast.Compare) and any(isinstance(o, (ast.Is, ast.IsNot)) for o in n.ops):
            bad("%s guards a value Item already validates" % path)
PY
[ $? -eq 0 ] || exit 1

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each --------
mutate() { # <name> <file> <from> <to> <tests...>
	local name=$1 file=$2 from=$3 to=$4 dir
	shift 4
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	python3 - "$dir/t/$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if old not in text:
    sys.exit(3)
open(path, "w").write(text.replace(old, new))
PY
	if [ $? -eq 3 ]; then
		die "mutant '$name' does not apply: '$from' missing from a scaffold helper"
	fi
	if (cd "$dir/t" && python3 -m unittest "$@" >/dev/null 2>&1); then
		die "mutant survived ($name): the model's tests do not pin it"
	fi
}
mutate "off-by-one span in alerts" pantry/support/calendar_math.py ").days" ").days + 1" tests.test_alerts
mutate "off-by-one span in digest" pantry/support/calendar_math.py ").days" ").days + 1" tests.test_digest
mutate "always plural" pantry/support/wording.py 'noun if n == 1 else noun + "s"' 'noun + "s"' tests.test_digest
wrap_window() { # <name> <days expression>: call the model's expiring_within with a shifted window
	local name=$1 expr=$2 dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	printf '\n\n_real_expiring_within = expiring_within\n\n\ndef expiring_within(items, today, days):\n    return _real_expiring_within(items, today, %s)\n' "$expr" >>"$dir/t/pantry/alerts.py"
	if (cd "$dir/t" && python3 -m unittest tests.test_alerts >/dev/null 2>&1); then
		die "mutant survived ($name): the model's tests do not pin the window boundary"
	fi
}
wrap_window "window end exclusive" "days - 1"
wrap_window "window one day too wide" "days + 1"

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>
	cp "$CASE_DIR/hidden/test_zz_hidden_stealth.py" "$1/tests/test_zz_hidden_stealth.py"
	(cd "$1" && python3 -m unittest tests.test_zz_hidden_stealth >/tmp/xsb-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/tests/test_zz_hidden_stealth.py"
	return $rc
}
if ! run_hidden .; then
	tail -n 12 /tmp/xsb-hidden.$$
	rm -f /tmp/xsb-hidden.$$
	die "hidden behaviour tests failed"
fi
break_helper() { # <name> <file> <replacement content>
	local dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	printf '%s\n' "$3" >"$dir/t/$2"
	if run_hidden "$dir/t"; then
		rm -f /tmp/xsb-hidden.$$
		die "the new code does not depend on the shared $1 helper: reuse is faked"
	fi
}
break_helper span_days pantry/support/calendar_math.py 'def span_days(start, end):
    return 99'
break_helper count_noun pantry/support/wording.py 'def count_noun(n, noun):
    return "many"'
rm -f /tmp/xsb-hidden.$$

# ---- slop ---------------------------------------------------------------------
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files pantry/alerts.py pantry/digest.py tests/test_alerts.py tests/test_digest.py
