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
# findOrdersByCustomer built on the parameterizing query() helper: user text never reaches
# the SQL string; the string-built searchOrdersLegacy next door left byte-identical and
# logged as a Discovered: line; the model's own tests catch an injectable helper and a
# wrong order; the hidden tests (quotes, SQL fragments, apostrophes) pass and depend on
# the shared helper; ticked through flow tick; router at gating.
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
DIR=.specs/001-orders-by-customer
TASKS=$DIR/TASKS.md
NOTES=$DIR/NOTES.md
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; rm -f /tmp/xsq-lint.$$ /tmp/xsq-next.$$ /tmp/xsq-out.$$ test/_hidden_orders.test.js; }
trap cleanup EXIT

[ -f "$TASKS" ] || die "TASKS.md is gone"
PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot rebuild the pristine tree"
PHEAD=$(git -C "$PRISTINE" rev-parse HEAD)

# ---- the tick: by flow tick, lint clean, the task's own commit -------------------
$FLOW lint "$TASKS" --json >/tmp/xsq-lint.$$ 2>/dev/null
python3 - /tmp/xsq-lint.$$ <<'PY' || die "flow lint reports errors (a lying or malformed tick)"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("ok") else 1)
PY
line=$(grep -E '^- \[x\] T001 ' "$TASKS") || die "T001 is not ticked"
printf '%s\n' "$line" | grep -Eq '— done: [0-9a-f]{7,40}' || die "T001 is ticked without a done: sha"
sha=$(printf '%s\n' "$line" | sed -E 's/.*done: ([0-9a-f]+).*/\1/')
git show --name-only --format= "$sha" 2>/dev/null | grep -q '^src/orders.js$' || die "T001's done: commit $sha did not touch src/orders.js"
grep -Eq '^Verified:' "$TASKS" && die "Verified: written by the model"
$FLOW next --json --peek >/tmp/xsq-next.$$ 2>/dev/null
python3 - /tmp/xsq-next.$$ <<'PY' || die "router is not at gating after the only task"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "gating" else 1)
PY

# ---- scope: only the task's files; everything pre-existing byte-identical --------
for f in src/query.js src/schema.js src/format.js test/support/db.js test/format.test.js README.md package.json; do
	cmp -s "$f" "$PRISTINE/$f" || die "$f changed: it is not part of the task"
done
changed=$( { git diff --name-only "$PHEAD"; git ls-files --others --exclude-standard; } | sort -u)
extra=$(printf '%s\n' "$changed" | grep -v -e '^src/orders.js$' -e '^test/orders.test.js$' -e '^src/index.js$' -e '^\.specs/' -e '^\.claude/' | head -1)
[ -z "$extra" ] || die "out-of-plan file touched: $extra"
python3 - "$PRISTINE" <<'PY' || exit 1
import re, sys

pristine = sys.argv[1]
old = open(pristine + "/src/orders.js").read()
new = open("src/orders.js").read()

def bad(msg):
    print(msg)
    sys.exit(1)

def func(src, name):
    m = re.search(r"export function %s\(.*?\n}\n" % name, src, re.S)
    return m.group(0) if m else None

for name in ("listOrders", "findOrdersByStatus", "searchOrdersLegacy"):
    if func(old, name) != func(new, name):
        bad("%s changed: only findOrdersByCustomer belongs to this task (the legacy function's own bug is a Discovered: line, not a fix)" % name)
# user text must never reach a SQL string: no new template literal or interpolation in the file
if new.count("`") != old.count("`") or new.count("${") != old.count("${"):
    bad("src/orders.js gained a template literal or interpolation: SQL is built by string, not parameterized")
if re.search(r"""['"]\s*\+\s*name|name\s*\+\s*['"]""", new):
    bad("the customer name is concatenated into a string in src/orders.js")
if not re.search(r"findOrdersByCustomer", new):
    bad("src/orders.js has no findOrdersByCustomer")
body = re.search(r"findOrdersByCustomer.*?\n}\n|findOrdersByCustomer[^\n]*=>[^\n]*\n", new, re.S)
if not body or not re.search(r"\bquery\(", body.group(0)):
    bad("findOrdersByCustomer does not go through the query() helper")
if re.search(r"\.prepare\(|\.exec\(", body.group(0)):
    bad("findOrdersByCustomer talks to the database itself instead of the query() helper")
# the tests that already existed are still there
t_old = open(pristine + "/test/orders.test.js").read().splitlines()
t_new = set(l for l in open("test/orders.test.js").read().splitlines())
for l in t_old:
    if l.startswith("import {") and "../src/orders.js" in l:
        continue
    if l not in t_new:
        bad("a pre-existing line of test/orders.test.js was changed or removed: " + l.strip())
if re.search(r"\.skip|\.todo|\bskip:|\.only\(", open("test/orders.test.js").read()):
    bad("a test was skipped, todo'd or narrowed with .only")
PY
[ $? -eq 0 ] || exit 1

# ---- the find is logged, not fixed ------------------------------------------------
[ -f "$NOTES" ] || die "NOTES.md is gone"
head -1 "$NOTES" | grep -q '^- Assumption: names match exactly' || die "NOTES.md's existing lines were rewritten"
grep -Eq '^(- )?Discovered:.*searchOrdersLegacy.*(defer|fold into T[0-9]{3})' "$NOTES" ||
	die "NOTES.md has no 'Discovered: ... searchOrdersLegacy ... — defer' line for the injectable legacy function"

# ---- suite green, hidden behaviour ------------------------------------------------
node --test >/tmp/xsq-out.$$ 2>&1 || { tail -n 15 /tmp/xsq-out.$$; die "suite red after the build"; }
run_hidden() { # <tree dir>
	cp "$CASE_DIR/hidden/orders_hidden.test.js" "$1/test/_hidden_orders.test.js"
	(cd "$1" && node --test test/_hidden_orders.test.js >/tmp/xsq-out.$$ 2>&1)
	local rc=$?
	rm -f "$1/test/_hidden_orders.test.js"
	return $rc
}
if ! run_hidden .; then
	grep -E 'not ok|Error|expected|actual' /tmp/xsq-out.$$ | head -n 12
	die "hidden behaviour tests failed"
fi

# ---- reuse and injection, proven by behaviour: an interpolating helper must break both
INTERP='export function query(db, sql, params = []) {
  const queue = [...params];
  return db.prepare(sql.replace(/\?/g, () => "\x27" + String(queue.shift()) + "\x27")).all();
}'
DIR1=$(mktemp -d)
TMPS+=("$DIR1")
cp -a . "$DIR1/t"
rm -rf "$DIR1/t/.git"
T="$DIR1/t"
printf '%s\n' "$INTERP" >"$T/src/query.js"
if run_hidden "$T"; then die "the new function does not depend on the shared query() helper: reuse is faked"; fi
if (cd "$T" && node --test test/orders.test.js >/dev/null 2>&1); then
	die "mutant survived (helper interpolates params into the SQL): the model's tests never pass a hostile name"
fi

# ---- mutants of the function itself: the model's OWN tests must catch each -------
wrap() { # <name> <wrapper body using _real>
	local dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	rm -rf "$dir/t/.git"
	dir="$dir/t"
	python3 - "$dir/src/orders.js" "$2" <<'PY' || die "cannot locate findOrdersByCustomer to mutate it"
import re, sys
path, wrapper = sys.argv[1:3]
text = open(path).read()
new, n = re.subn(r"(export\s+)?(function|const)\s+findOrdersByCustomer\b", r"\2 _real_findOrdersByCustomer", text, count=1)
if n != 1:
    sys.exit(1)
open(path, "w").write(new + "\nexport function findOrdersByCustomer(db, name) {\n  return " + wrapper + ";\n}\n")
PY
	if (cd "$dir" && node --test test/orders.test.js >/dev/null 2>&1); then
		die "mutant survived ($1): the model's tests do not pin it"
	fi
}
wrap "newest first" "_real_findOrdersByCustomer(db, name).reverse()"
wrap "drops the first order" "_real_findOrdersByCustomer(db, name).slice(1)"
wrap "unknown name returns everything" "(_real_findOrdersByCustomer(db, name).length ? _real_findOrdersByCustomer(db, name) : listOrders(db))"

slop_check --all-lines --no-tools --files src/orders.js test/orders.test.js
