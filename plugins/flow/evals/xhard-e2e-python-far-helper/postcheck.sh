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
# Full pipeline end to end: artifacts and gate discipline first, then the code
# (reuse, no guard, style), then mutants of the new code against the MODEL's own
# tests, then the hidden behaviour tests. One reason line on failure.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }

# ---- pipeline artifacts --------------------------------------------------------
CUR=$(tr -d '[:space:]' <.specs/.current 2>/dev/null)
{ [ -n "$CUR" ] && [ -d ".specs/$CUR" ]; } || die "no .specs/.current pointing at a feature dir"
FEAT=.specs/$CUR
[ -f "$FEAT/TASKS.md" ] || die "no $FEAT/TASKS.md: the pipeline never drafted a plan"
$FLOW lint "$FEAT/TASKS.md" --json >/tmp/xhard-lint.$$ 2>/dev/null
python3 - /tmp/xhard-lint.$$ "$FEAT" <<'PY' || exit 1
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
gates = [t for t in tasks if t["kind"] == "gate"]
if len(work) < 2:
    bad("plan has %d task(s); the feature spans models and CLI, expected at least 2" % len(work))
open_ids = [t["id"] for t in tasks if t["state"] == "open"]
if open_ids:
    bad("tasks still open at the end: " + ", ".join(open_ids))
if not gates:
    bad("no ## Gates in TASKS.md")
h = lint["header"]
if not h.get("approved"):
    bad("no Approved: line: the plan was never approved at the gate")
if h.get("verified"):
    bad("Verified: is written; that fact is the human's, the run must stop at unverified")
if h.get("route") == "dispatch" and not os.path.isfile(os.path.join(feat, "spec.md")):
    bad("Route: dispatch but no spec.md")
PY
rc=$?
rm -f /tmp/xhard-lint.$$
[ "$rc" -eq 0 ] || exit 1
if grep -rE '^[[:space:]]*Verified:' .specs --include='*.md' >/dev/null 2>&1; then die "a Verified: line exists under .specs"; fi
$FLOW pass >/dev/null 2>&1 || die "no PASS-<sha>.md covers HEAD"
ls "$FEAT"/PASS-*.md >/dev/null 2>&1 || die "no PASS file in $FEAT"
grep -qi 'exit' "$FEAT"/PASS-*.md || die "PASS file names no exit codes"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "unverified" ] || die "final router state is '$STATE', expected unverified"
if git status --porcelain | grep -v -E '__pycache__| \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi

# ---- the diff stayed in its lane ----------------------------------------------
BASEC=$(git log --format=%h --grep='^cli: catalog listing$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
for f in $(git diff --name-only "$BASEC" -- shelfkit); do
	case "$f" in
	shelfkit/models/product.py | shelfkit/cli.py) ;;
	*__pycache__* | *.pyc) ;;
	*) die "touched a source file outside the feature: $f" ;;
	esac
done
[ -z "$(git diff --diff-filter=D --name-only "$BASEC")" ] || die "a file was deleted"
if git diff "$BASEC" -- tests | grep -E '^-[^-]' | grep -v -E '^-(from|import) ' | grep . >/dev/null; then die "an existing test line was removed or edited"; fi

python3 -m unittest discover -s tests >/dev/null 2>&1 || die "suite red after the pipeline"

# ---- code: reuse, no guard, style ----------------------------------------------
PRISTINE=$(mktemp -d)
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot regenerate the pristine tree"
python3 - "$PRISTINE" <<'PY' || exit 1
import ast, re, sys
pristine = sys.argv[1]
def bad(msg):
    print(msg)
    sys.exit(1)
def segments(path):
    src = open(path).read()
    return src, ast.parse(src)
src, tree = segments("shelfkit/models/product.py")
_, old = segments(pristine + "/shelfkit/models/product.py")
if any(isinstance(n, ast.Import) and any(a.name == "re" for a in n.names) for n in ast.walk(tree)):
    bad("product.py imports re: the slug helper was re-implemented")
cls = next(n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Product")
old_cls = next(n for n in old.body if isinstance(n, ast.ClassDef) and n.name == "Product")
osrc = open(pristine + "/shelfkit/models/product.py").read()
post = next(n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name == "__post_init__")
opost = next(n for n in old_cls.body if isinstance(n, ast.FunctionDef) and n.name == "__post_init__")
if ast.get_source_segment(src, post) != ast.get_source_segment(osrc, opost):
    bad("Product.__post_init__ was edited")
props = {n.name: n for n in cls.body if isinstance(n, ast.FunctionDef) and n.name in ("url_path", "price_label")}
for name, want in (("url_path", "hyphenate"), ("price_label", "cents_to_display")):
    fn = props.get(name)
    if fn is None:
        bad("Product.%s is missing" % name)
    if not any(isinstance(d, ast.Name) and d.id == "property" for d in fn.decorator_list):
        bad("Product.%s is not a property" % name)
    rets = [r for r in ast.walk(fn) if isinstance(r, ast.Return) and r.value is not None]
    used = any(
        isinstance(c, ast.Call) and isinstance(c.func, ast.Name) and c.func.id == want
        for r in rets
        for c in ast.walk(r.value)
    )
    if not used:
        bad("Product.%s does not return a value built by the existing %s helper" % (name, want))
    for node in ast.walk(fn):
        if isinstance(node, ast.Lambda):
            bad("Product.%s hand-rolls the format with a lambda instead of %s" % (name, want))
        if isinstance(node, ast.FormattedValue) and node.format_spec is not None:
            bad("Product.%s hand-rolls a format spec instead of %s" % (name, want))
        if isinstance(node, ast.Attribute) and node.attr in ("translate", "maketrans", "encode", "format", "replace", "lower"):
            bad("Product.%s re-implements the transform by hand instead of %s" % (name, want))
        if isinstance(node, ast.Name) and node.id in ("re", "round", "divmod"):
            bad("Product.%s re-implements the transform by hand instead of %s" % (name, want))
    for node in ast.walk(fn):
        if isinstance(node, (ast.If, ast.IfExp, ast.Try, ast.Raise, ast.Assert, ast.BoolOp)):
            bad("Product.%s carries a guard the constructor already guarantees" % name)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name) and node.func.id in ("isinstance", "hasattr", "len"):
            bad("Product.%s carries a guard the constructor already guarantees" % name)

cli = open("shelfkit/cli.py").read()
if '"' in cli:
    bad("cli.py uses a double quote: the file is single-quoted throughout")
ctree = ast.parse(cli)
for fn in [n for n in ctree.body if isinstance(n, ast.FunctionDef)]:
    if "_" in fn.name:
        bad("cli.py function %s breaks the file's camelCase naming" % fn.name)
octree = ast.parse(open(pristine + "/shelfkit/cli.py").read())
ocli = open(pristine + "/shelfkit/cli.py").read()
for fn in [n for n in octree.body if isinstance(n, ast.FunctionDef)]:
    now = next((n for n in ctree.body if isinstance(n, ast.FunctionDef) and n.name == fn.name), None)
    if now is None or ast.get_source_segment(cli, now) != ast.get_source_segment(ocli, fn):
        bad("cli.py function %s changed; only renderTag is new" % fn.name)
if not any(isinstance(n, ast.FunctionDef) and n.name == "renderTag" for n in ctree.body):
    bad("cli.py has no renderTag")
for path in ("shelfkit/models/product.py", "shelfkit/cli.py"):
    if ",.2f" in open(path).read():
        bad("%s hand-rolls money formatting instead of cents_to_display" % path)
PY
rc=$?
rm -rf "$PRISTINE"
[ "$rc" -eq 0 ] || exit 1

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each --------
mutate() { # <name> <file> <from> <to>
	local dir
	dir=$(mktemp -d)
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
		rm -rf "$dir"
		echo "mutant '$1' skipped: '$3' not present (inconclusive)"
		return 0
	fi
	if (cd "$dir/t" && python3 -m unittest discover -s tests >/dev/null 2>&1); then
		rm -rf "$dir"
		die "mutant survived ($1): the model's tests do not pin it"
	fi
	rm -rf "$dir"
}
mutate "url prefix" shelfkit/models/product.py "/shop/" "/shops/"
mutate "tag separator" shelfkit/cli.py " | " " / "

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>: copy the hidden file in, run the suite, remove it
	cp "$CASE_DIR/hidden/test_zz_hidden_feature.py" "$1/tests/test_zz_hidden_feature.py"
	(cd "$1" && python3 -m unittest discover -s tests >/tmp/xhard-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/tests/test_zz_hidden_feature.py"
	return $rc
}
if ! run_hidden .; then
	tail -n 12 /tmp/xhard-hidden.$$
	rm -f /tmp/xhard-hidden.$$
	die "hidden behaviour tests failed"
fi

# ---- reuse is real: break each shared helper in a copy, the hidden tests must notice
break_helper() { # <name> <file> <replacement file content>
	local dir
	dir=$(mktemp -d)
	cp -a . "$dir/t"
	printf '%s\n' "$3" >"$dir/t/$2"
	if run_hidden "$dir/t"; then
		rm -rf "$dir"
		rm -f /tmp/xhard-hidden.$$
		die "Product does not depend on the shared $1 helper: reuse is faked"
	fi
	rm -rf "$dir"
}
break_helper hyphenate shelfkit/support/text.py 'def hyphenate(text: str) -> str:
    return "slug"'
break_helper cents_to_display shelfkit/support/money.py 'def cents_to_display(cents: int) -> str:
    return "price"'
rm -f /tmp/xhard-hidden.$$

# ---- slop ---------------------------------------------------------------------
TOUCHED=$( { git diff --name-only "$BASEC" -- tests shelfkit; git ls-files --others --exclude-standard tests shelfkit; } | grep '\.py$' | grep -v '__init__' | sort -u)
# shellcheck disable=SC2086
slop_check --all-lines --no-tools --files $TOUCHED
