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
# Two-phase pipeline end to end: artifacts and gate discipline first (>= 2 phases,
# a non-bounded route, each phase's Independent test executed per the trace), then
# the migrated data against the pristine files, then code (reuse, no float math),
# mutants of the model's OWN tests, hidden behaviour, slop. One reason line on failure.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; rm -f /tmp/xtp-lint.$$ /tmp/xtp-hidden.$$; }
trap cleanup EXIT

# ---- pipeline artifacts --------------------------------------------------------
CUR=$(tr -d '[:space:]' <.specs/.current 2>/dev/null)
{ [ -n "$CUR" ] && [ -d ".specs/$CUR" ]; } || die "no .specs/.current pointing at a feature dir"
FEAT=.specs/$CUR
[ -f "$FEAT/TASKS.md" ] || die "no $FEAT/TASKS.md: the pipeline never drafted a plan"
$FLOW lint "$FEAT/TASKS.md" --json >/tmp/xtp-lint.$$ 2>/dev/null
python3 - /tmp/xtp-lint.$$ "$FEAT" <<'PY' || exit 1
import json, os, sys
lint = json.load(open(sys.argv[1]))
feat = sys.argv[2]
def bad(msg):
    print(msg)
    sys.exit(1)
if lint.get("errors"):
    bad("flow lint ERROR: " + lint["errors"][0].get("message", "?"))
tasks = lint["tasks"]
work = [t for t in tasks if t["kind"] == "task"]
phases = {t["phase"] for t in work}
if len(phases) < 2:
    bad("plan has %d phase(s); the feature is a data migration then a command, expected at least 2" % len(phases))
if len(work) < 3:
    bad("plan has %d task(s), expected at least 3" % len(work))
if not [t for t in tasks if t["kind"] == "gate"]:
    bad("no ## Gates in TASKS.md")
open_ids = [t["id"] for t in tasks if t["state"] == "open"]
if open_ids:
    bad("tasks still open at the end: " + ", ".join(open_ids))
h = lint["header"]
if h.get("route") == "bounded":
    bad("Route: bounded for a two-phase feature; the route should not be bounded")
if not h.get("approved"):
    bad("no Approved: line: the plan was never approved at the gate")
if h.get("verified"):
    bad("Verified: is written; that fact is the human's, the run must stop at unverified")
if not os.path.isfile(os.path.join(feat, "spec.md")):
    bad("no spec.md beside TASKS.md")
PY
[ $? -eq 0 ] || exit 1
if grep -rE '^[[:space:]]*Verified:' .specs --include='*.md' >/dev/null 2>&1; then die "a Verified: line exists under .specs"; fi
$FLOW pass >/dev/null 2>&1 || die "no PASS-<sha>.md covers HEAD"
grep -qi 'exit' "$FEAT"/PASS-*.md || die "PASS file names no exit codes"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "unverified" ] || die "final router state is '$STATE', expected unverified"
if git status --porcelain | grep -v -E '__pycache__| \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi

# ---- every phase's Independent test was EXECUTED, per the trace -----------------
python3 - "$FEAT/TASKS.md" "${EVAL_TRACE:-}" <<'PY' || exit 1
import json, os, re, sys
tasks_path, trace_path = sys.argv[1], sys.argv[2]
if not trace_path or not os.path.isfile(trace_path) or os.path.getsize(trace_path) == 0:
    print("no trace to read: phase test execution not checked", file=sys.stderr)
    sys.exit(0)
def commands(node, out):
    if isinstance(node, dict):
        inp = node.get("input")
        if node.get("name") == "Bash" and isinstance(inp, dict) and isinstance(inp.get("command"), str):
            out.append(" ".join(inp["command"].split()))
        for v in node.values():
            commands(v, out)
    elif isinstance(node, list):
        for v in node:
            commands(v, out)
ran = []
for line in open(trace_path, encoding="utf-8", errors="replace"):
    try:
        commands(json.loads(line), ran)
    except ValueError:
        continue
wanted = []
for line in open(tasks_path, encoding="utf-8"):
    m = re.match(r"^Independent test:\s*(.*)$", line.strip())
    if not m:
        continue
    cmds = re.findall(r"`([^`]+)`", m.group(1))
    if not cmds:
        print("a phase's Independent test names no runnable command in backticks: " + line.strip())
        sys.exit(1)
    wanted.append(" ".join(cmds[0].split()))
if len(wanted) < 2:
    print("fewer than two phases carry an Independent test: line")
    sys.exit(1)
need = {}
for c in wanted:
    need[c] = need.get(c, 0) + 1
for cmd, count in need.items():
    seen = sum(1 for r in ran if cmd in r)
    if seen < count:
        print("a phase's Independent test was never executed (%d of %d runs): %s" % (seen, count, cmd))
        sys.exit(1)
PY
[ $? -eq 0 ] || exit 1

# ---- the diff stayed in its lane ----------------------------------------------
BASEC=$(git log --format=%h --grep='^base: shopdesk catalogue tools$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
[ -z "$(git diff --diff-filter=D --name-only "$BASEC")" ] || die "a file was deleted"
# tests may change (the prompt mandates price -> price_cents in the Product constructor)
# but none may be weakened: every base def test_* survives and no base test file loses
# an assert line (the constructor argument is not an assert line, so the rename passes).
for tf in $(git ls-tree -r --name-only "$BASEC" -- tests | grep -E '\.py$'); do
	python3 - "$tf" "$BASEC" <<'PY' || exit 1
import re, subprocess, sys
path, base = sys.argv[1], sys.argv[2]
old = subprocess.run(["git", "show", base + ":" + path], capture_output=True, text=True, check=True).stdout
try:
    new = open(path, encoding="utf-8").read()
except OSError:
    print("%s is gone" % path)
    sys.exit(1)
tests = lambda t: set(re.findall(r"^\s*def (test_\w+)", t, re.M))
asserts = lambda t: len(re.findall(r"^\s*(?:self\.assert\w+|assert\b)", t, re.M))
missing = tests(old) - tests(new)
if missing:
    print("%s lost test(s): %s" % (path, ", ".join(sorted(missing))))
    sys.exit(1)
if asserts(new) < asserts(old):
    print("%s has fewer assert lines than the base (%d < %d): a test was weakened" % (path, asserts(new), asserts(old)))
    sys.exit(1)
PY
done
[ $? -eq 0 ] || exit 1
git diff --quiet "$BASEC" -- data/archive || die "data/archive changed: it is frozen history"
python3 -m unittest discover -s tests >/dev/null 2>&1 || die "suite red after the pipeline"

PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot regenerate the pristine tree"

# ---- code: reuse, no float math, no guards --------------------------------------
NEWSRC=$(git diff --name-only --diff-filter=AM "$BASEC" HEAD | grep -E '\.py$' | grep -v -E '^tests/' | sort -u)
ADDED=$(for f in $NEWSRC; do git diff -U0 "$BASEC" HEAD -- "$f"; done | grep -E '^\+' | grep -v -E '^\+\+\+')
printf '%s\n' "$ADDED" | grep -q 'show_amount' || die "no source line uses show_amount: the display format was re-implemented"
grep -q 'show_amount' shopdesk/cli.py || die "shopdesk/cli.py does not use show_amount"
# read_amount must appear in committed source or in a Bash command the model ran
# (a read of moneytext.py in a tool result does not count); inline python that
# rewrites data with float or Decimal math is refused.
USED=$(python3 - "${EVAL_TRACE:-}" <<'PY'
import json, os, re, sys
path = sys.argv[1]
cmds = []
def walk(node):
    if isinstance(node, dict):
        inp = node.get("input")
        if node.get("name") == "Bash" and isinstance(inp, dict) and isinstance(inp.get("command"), str):
            cmds.append(inp["command"])
        for v in node.values():
            walk(v)
    elif isinstance(node, list):
        for v in node:
            walk(v)
if path and os.path.isfile(path):
    for line in open(path, encoding="utf-8", errors="replace"):
        try:
            walk(json.loads(line))
        except ValueError:
            pass
if any("read_amount" in c for c in cmds):
    print("cmd")
if any("python" in c and re.search(r"float\(|Decimal\(", c) and re.search(r"write|json\.dump", c) for c in cmds):
    print("floatmath")
PY
)
case "$USED" in *floatmath*) die "an inline migration script does float or Decimal math on the data" ;; esac
if ! printf '%s\n' "$ADDED" | grep -q 'read_amount'; then
	case "$USED" in *cmd*) ;; *) die "the migration never used read_amount: dollar text was parsed by hand" ;; esac
fi
printf '%s\n' "$ADDED" | grep -E 'float\(|\* *100|round\(|Decimal|isinstance|hasattr' | grep . >/dev/null && die "hand-rolled money math or a guard in new source: $(printf '%s\n' "$ADDED" | grep -E 'float\(|\* *100|round\(|Decimal|isinstance|hasattr' | head -1)"

# ---- migration keeps every field: only price -> price_cents may change ----------
python3 - "$PRISTINE" <<'PY' || exit 1
import json, sys
pristine = sys.argv[1]
files = ["data/catalog.json", "data/clearance.json", "data/imports/supplier-2025.json", "tests/fixtures/sample_products.json"]
def cents(text):
    text = text.strip().replace("$", "").replace(",", "")
    if not text:
        return None
    whole, _, frac = text.partition(".")
    return int(whole) * 100 + int((frac + "00")[:2])
for rel in files:
    old = json.load(open(pristine + "/" + rel, encoding="utf-8"))
    new = json.load(open(rel, encoding="utf-8"))
    if len(new) != len(old):
        print("%s: %d records after migration, %d before" % (rel, len(new), len(old)))
        sys.exit(1)
    for was, now in zip(old, new):
        if now.get("sku") != was.get("sku"):
            print("%s: record order changed at %s" % (rel, was.get("sku")))
            sys.exit(1)
        lost = [k for k in was if k != "price" and k not in now]
        if lost:
            print("%s: migration dropped %s from %s" % (rel, ", ".join(lost), was["sku"]))
            sys.exit(1)
        if "price" in now or now.get("price_cents", "missing") != cents(was["price"]):
            print("%s: %s has wrong price fields (want price_cents=%r, no price)" % (rel, was["sku"], cents(was["price"])))
            sys.exit(1)
        changed = [k for k in was if k != "price" and now[k] != was[k]]
        if changed:
            print("%s: migration altered %s on %s" % (rel, ", ".join(changed), was["sku"]))
            sys.exit(1)
PY

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>
	cp "$CASE_DIR/hidden/test_zz_hidden_twophase.py" "$1/tests/test_zz_hidden_twophase.py"
	(cd "$1" && PRISTINE_DIR="$PRISTINE" python3 -m unittest tests.test_zz_hidden_twophase >/tmp/xtp-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/tests/test_zz_hidden_twophase.py"
	return $rc
}
if ! run_hidden .; then
	tail -n 14 /tmp/xtp-hidden.$$
	die "hidden behaviour tests failed"
fi

# ---- reuse is real: break show_amount in a copy, the hidden tests must notice ---
BR=$(mktemp -d)
TMPS+=("$BR")
cp -a . "$BR/t"
printf 'def read_amount(text):\n    return 0\n\n\ndef show_amount(cents):\n    return "amt"\n' >"$BR/t/shopdesk/support/moneytext.py"
if run_hidden "$BR/t"; then die "the CLI does not depend on the shared show_amount helper: reuse is faked"; fi

# ---- mutants: the model's OWN new tests must catch each --------------------------
NEWTESTS=$(git diff --name-only --diff-filter=AM "$BASEC" HEAD -- 'tests/*.py' | sed -e 's#/#.#g' -e 's#\.py$##')
[ -n "$NEWTESTS" ] || die "no test module was added or extended"
mutate() { # <name> <file> <from> <to>
	local dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	python3 - "$dir/t/$2" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path).read()
if old not in text:
    sys.exit(3)
open(path, "w").write(text.replace(old, new))
PY
	if [ $? -eq 3 ]; then
		echo "mutant '$1' skipped: '$3' not present (inconclusive)"
		return 0
	fi
	# shellcheck disable=SC2086
	if (cd "$dir/t" && python3 -m unittest $NEWTESTS >/dev/null 2>&1); then
		die "mutant survived ($1): the model's new tests do not pin it"
	fi
}
mutate "display drops the dollar sign" shopdesk/support/moneytext.py '"$%s.%02d"' '"%s.%02d"'
mutate "display drops thousands grouping" shopdesk/support/moneytext.py 'format(dollars, ",")' 'str(dollars)'
if printf '%s\n' "$ADDED" | grep -q 'read_amount'; then
	mutate "reader truncates cents" shopdesk/support/moneytext.py '(frac + "00")[:2]' '(frac + "00")[:1]'
fi

# ---- slop ---------------------------------------------------------------------
slop_check --base "$BASEC" --head HEAD --no-tools
