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
# The spec retires half-even tax rounding and names the one legacy assertion that encodes
# it. Done right: tax rounds half up; ONLY that assertion changed (every other assert in
# that file, every other test, the shared div_round, discount rounding and the known-red
# shipping test untouched); the decision logged as a Ruling: quoting the spec; ticked
# through flow tick; the router at gating.
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-half-up-tax
TASKS=$DIR/TASKS.md
NOTES=$DIR/NOTES.md
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; rm -f /tmp/xsl-lint.$$ /tmp/xsl-next.$$ /tmp/xsl-hidden.$$; }
trap cleanup EXIT

[ -f "$TASKS" ] || die "TASKS.md is gone"
PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot rebuild the pristine tree"
PHEAD=$(git -C "$PRISTINE" rev-parse HEAD)

# ---- the tick: by flow tick, lint clean, the task's own commit -------------------
$FLOW lint "$TASKS" --json >/tmp/xsl-lint.$$ 2>/dev/null
python3 - /tmp/xsl-lint.$$ <<'PY' || die "flow lint reports errors (a lying or malformed tick)"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY
line=$(grep -E '^- \[x\] T001 ' "$TASKS") || die "T001 is not ticked"
printf '%s\n' "$line" | grep -Eq '— done: [0-9a-f]{7,40}' || die "T001 is ticked without a done: sha"
sha=$(printf '%s\n' "$line" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
touched=$(git show --name-only --format= "$sha" 2>/dev/null)
printf '%s\n' "$touched" | grep -q '^ledgerly/tax.py$' || die "T001's done: commit $sha did not touch ledgerly/tax.py"
extra=$(printf '%s\n' "$touched" | grep -v -e '^ledgerly/tax.py$' -e '^ledgerly/support/rounding.py$' -e '^tests/test_tax.py$' -e '^tests/test_rounding.py$' | head -1)
[ -z "$extra" ] || die "T001's commit $sha touched $extra, which is not one of the task's files"
grep -Eq '^Verified:' "$TASKS" && die "Verified: written by the model"
$FLOW next --json --peek >/tmp/xsl-next.$$ 2>/dev/null
python3 - /tmp/xsl-next.$$ <<'PY' || die "router is not at gating after the only task"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "gating" else 1)
PY

# ---- nothing outside the task moved --------------------------------------------
for f in ledgerly/discount.py ledgerly/invoice.py ledgerly/shipping.py ledgerly/models.py \
	tests/test_discount.py tests/test_invoice.py tests/test_shipping.py README.md; do
	cmp -s "$f" "$PRISTINE/$f" || die "$f changed: it is not part of the task (a test was swept up or a neighbour rewritten)"
done
changed=$( { git diff --name-only "$PHEAD"; git ls-files --others --exclude-standard; } | sort -u)
extra=$(printf '%s\n' "$changed" | grep -v -e '^ledgerly/tax.py$' -e '^ledgerly/support/rounding.py$' -e '^tests/test_tax.py$' -e '^tests/test_rounding.py$' -e '^\.specs/' -e '^\.claude/' | head -1)
[ -z "$extra" ] || die "out-of-plan file touched: $extra"
python3 - "$PRISTINE/ledgerly/support/rounding.py" ledgerly/support/rounding.py <<'PY' || die "the shared div_round changed: discount rounding and the spec's R2 depend on it staying half-to-even"
import ast, sys

def body(path):
    src = open(path).read()
    for n in ast.parse(src).body:
        if isinstance(n, ast.FunctionDef) and n.name == "div_round":
            return ast.get_source_segment(src, n)
    return None

before, after = body(sys.argv[1]), body(sys.argv[2])
sys.exit(0 if before is not None and before == after else 1)
PY
python3 -m unittest tests.test_shipping.TestShipping.test_free_shipping_at_the_threshold >/dev/null 2>&1 &&
	die "the known-red shipping test now passes: it was fixed out of scope"

# ---- the legacy test: ONLY the directed assertion changed -----------------------
python3 - "$PRISTINE" <<'PY' || exit 1
import re, sys
from collections import Counter

pristine = sys.argv[1]

def asserts(path):
    text = open(path).read()
    return Counter(l.strip() for l in text.splitlines() if re.match(r"\s*(self\.assert\w+|assert\b)", l))

def bad(msg):
    print(msg)
    sys.exit(1)

retired = "self.assertEqual(tax_cents(100, 250), 2)"
old, new = asserts(pristine + "/tests/test_tax.py"), asserts("tests/test_tax.py")
if new[retired]:
    bad("the retired assertion (tax_cents(100, 250) expecting 2) is still in tests/test_tax.py")
if not any(re.fullmatch(r"self\.assertEqual\(tax_cents\(100, 250\), 3\)", k) for k in new):
    bad("tests/test_tax.py does not assert the new behaviour: tax_cents(100, 250) == 3")
del old[retired]
lost = old - new
if lost:
    bad("an assertion the spec did not retire was changed or removed in tests/test_tax.py: " + next(iter(lost)))
old_r, new_r = asserts(pristine + "/tests/test_rounding.py"), asserts("tests/test_rounding.py")
if old_r - new_r:
    bad("tests/test_rounding.py lost an assertion: " + next(iter(old_r - new_r)))
text = "".join(open(p).read() for p in ("tests/test_tax.py", "tests/test_rounding.py"))
if re.search(r"skip|expectedFailure|xfail", text, re.I):
    bad("a test was skipped or marked as an expected failure")
PY
[ $? -eq 0 ] || exit 1

# ---- the decision is on the record, quoting the spec ------------------------------
[ -f "$NOTES" ] || die "NOTES.md is gone"
head -1 "$NOTES" | grep -q '^- Assumption: rates stay in whole basis points' || die "NOTES.md's existing lines were rewritten"
grep -Eq '^(- )?(Ruling|Assumption):.*(encodes the retired|superseded by A1)' "$NOTES" ||
	die "NOTES.md has no Ruling:/Assumption: line quoting the spec for the test change"

# ---- mutants: the model's OWN tests must catch each ------------------------------
mutate() { # <name> <tax.py content>
	local dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	printf '%s\n' "$2" >"$dir/t/ledgerly/tax.py"
	if (cd "$dir/t" && python3 -m unittest tests.test_tax >/dev/null 2>&1); then
		die "mutant survived ($1): the model's tests do not pin it"
	fi
}
mutate "tax still rounds half to even" 'from ledgerly.support.rounding import div_round


def tax_cents(subtotal_cents, rate_bps):
    return div_round(subtotal_cents * rate_bps, 10000)'
mutate "tax always rounds up" 'def tax_cents(subtotal_cents, rate_bps):
    return -(-subtotal_cents * rate_bps // 10000)'
mutate "tax truncates" 'def tax_cents(subtotal_cents, rate_bps):
    return subtotal_cents * rate_bps // 10000'

# ---- hidden behaviour ---------------------------------------------------------
cp "$CASE_DIR/hidden/test_halfup_hidden.py" tests/_hidden_test_halfup.py
python3 -m unittest tests._hidden_test_halfup >/tmp/xsl-hidden.$$ 2>&1
rc=$?
rm -f tests/_hidden_test_halfup.py
if [ "$rc" -ne 0 ]; then
	tail -n 12 /tmp/xsl-hidden.$$
	die "hidden half-up behaviour tests failed"
fi
NO_COLOR=1 python3 -m unittest discover -s tests >/tmp/xsl-hidden.$$ 2>&1
grep -Eq 'FAILED \(failures=1\)' /tmp/xsl-hidden.$$ || die "the suite is not exactly the one known-red shipping failure"

slop_check --all-lines --no-tools --files ledgerly/tax.py ledgerly/support/rounding.py tests/test_tax.py tests/test_rounding.py
