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
# Security review: download_attachment takes a user-chosen name. It must be built on
# the package's own safe_join (hidden tests with ../, absolute names, sibling-prefix
# folders and symlink escapes; breaking safe_join in a copy must break the hidden
# tests), the model's OWN tests must fail when safe_join is replaced by a plain join
# or a check that only looks for "..", the diff stays on the task's two files, and the
# wave is ticked through flow tick with the gates left for the next turn.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
export PYTHONDONTWRITEBYTECODE=1
die() { echo "$1"; exit 1; }
TMPS=()
cleanup() { [ ${#TMPS[@]} -eq 0 ] || rm -rf "${TMPS[@]}"; }
trap cleanup EXIT

FEAT=.specs/001-attachment-download
TASKS=$FEAT/TASKS.md
SERVE=fileserve/serve.py
TEST=tests/test_attachments.py
[ -f "$TASKS" ] || die "TASKS.md is gone"
[ -f "$TEST" ] || die "$TEST was never written"

# ---- the plan: T001 ticked by flow tick, nothing else moved ----------------------
$FLOW lint "$TASKS" --json >/tmp/xsr-lint.$$ 2>/dev/null
python3 - /tmp/xsr-lint.$$ <<'PY'
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
rm -f /tmp/xsr-lint.$$
[ "$rc" -eq 0 ] || exit 1
ls "$FEAT"/PASS-*.md >/dev/null 2>&1 && die "a PASS file exists: gating is not this turn's state"
STATE=$($FLOW next --peek --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])')
[ "$STATE" = "gating" ] || die "final router state is '$STATE', expected gating"

# ---- the diff stayed in its lane -------------------------------------------------
PRISTINE=$(mktemp -d)
TMPS+=("$PRISTINE")
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || die "cannot rebuild the pristine tree"
DIFFS=$(diff -rq -x .git -x .specs -x .claude -x __pycache__ "$PRISTINE" . | grep -v -e "Only in ./tests: test_attachments.py" -e "^Files $PRISTINE/fileserve/serve.py and ./fileserve/serve.py differ$")
[ -z "$DIFFS" ] || die "a file outside the task changed: $(printf '%s' "$DIFFS" | head -1)"
if git status --porcelain | grep -v -E ' \.specs/| \.claude/' | grep . >/dev/null; then
	die "the task's files were left uncommitted"
fi
DONE=$(grep -E '^- \[x\] T001 ' "$TASKS" | sed -E 's/.*— done: ([0-9a-f]+).*/\1/')
[ -n "$DONE" ] || die "T001 has no done: sha"
FILES=$(git show --name-only --format= "$DONE" | sort | tr '\n' ' ')
WANT=$(printf '%s\n%s\n' "$SERVE" "$TEST" | sort | tr '\n' ' ')
[ "$FILES" = "$WANT" ] || die "the commit T001 names holds '$FILES' instead of exactly the task's two files"
python3 - "$PRISTINE/$SERVE" "$SERVE" <<'PY' || exit 1
import ast, sys
def funcs(path):
    src = open(path).read()
    return {n.name: ast.get_source_segment(src, n) for n in ast.parse(src).body if isinstance(n, ast.FunctionDef)}
before, after = funcs(sys.argv[1]), funcs(sys.argv[2])
for name, body in before.items():
    if after.get(name) != body:
        print("the existing %s in fileserve/serve.py was edited" % name)
        sys.exit(1)
if "download_attachment" not in after:
    print("fileserve/serve.py has no download_attachment")
    sys.exit(1)
PY
python3 -m unittest discover -s tests >/dev/null 2>&1 || die "the suite is red"

# ---- code: built on safe_join, not a hand-rolled check ----------------------------
python3 - <<'PY' || exit 1
import ast, sys
def bad(msg):
    print(msg)
    sys.exit(1)
src = open("fileserve/serve.py").read()
tree = ast.parse(src)
def imports_support(n):
    if isinstance(n, ast.ImportFrom):
        if n.module in ("fileserve.support",) or (n.level == 1 and n.module == "support"):
            return any(a.name == "safe_join" for a in n.names)
        if n.module == "fileserve" or (n.level == 1 and n.module is None):
            return any(a.name == "support" for a in n.names)
    if isinstance(n, ast.Import):
        return any(a.name == "fileserve.support" for a in n.names)
    return False
if not any(imports_support(n) for n in tree.body):
    bad("serve.py does not import safe_join from the package's support module")
fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "download_attachment")
params = [a.arg for a in fn.args.args]
if len(params) != 2:
    bad("download_attachment must take (root, name)")
name = params[1]
def mentions(node, ident):
    return any(isinstance(x, ast.Name) and x.id == ident for x in ast.walk(node))
def dotted(func):
    parts = []
    while isinstance(func, ast.Attribute):
        parts.append(func.attr)
        func = func.value
    if isinstance(func, ast.Name):
        parts.append(func.id)
    return ".".join(reversed(parts))
routed = False
docstrings = set()
for f in ast.walk(fn):
    if isinstance(f, ast.FunctionDef) and f.body and isinstance(f.body[0], ast.Expr) and isinstance(f.body[0].value, ast.Constant):
        docstrings.add(f.body[0].value)
for n in ast.walk(fn):
    if isinstance(n, ast.Call):
        d = dotted(n.func)
        if (d == "safe_join" or d.endswith(".safe_join")) and any(mentions(a, name) for a in n.args):
            routed = True
        if d in ("os.path.join", "os.path.abspath", "os.path.realpath", "os.path.normpath", "os.path.commonpath", "os.path.commonprefix", "pathlib.Path", "Path") and any(mentions(a, name) for a in n.args):
            bad("download_attachment builds a path from the user's name by hand instead of through safe_join")
        if isinstance(n.func, ast.Attribute) and n.func.attr in ("startswith", "endswith", "resolve", "is_relative_to", "replace"):
            bad("download_attachment hand-rolls a path check (%s) instead of safe_join" % n.func.attr)
    if isinstance(n, ast.Constant) and isinstance(n.value, str) and ".." in n.value and n not in docstrings:
        bad("download_attachment filters '..' by hand instead of safe_join")
    if isinstance(n, ast.Try):
        bad("download_attachment catches errors: a refused name must reach the caller")
if not routed:
    bad("the user's name never goes through safe_join")
PY
[ $? -eq 0 ] || exit 1

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each ----------
NEWTESTS=$(git diff --diff-filter=A --name-only "$(git log --format=%h --grep='^plan: attachment download, approved$' -n 1)"..HEAD -- tests | sed -E 's:/:.:; s:\.py$::' | tr '\n' ' ')
[ -n "$NEWTESTS" ] || die "no new test module"
mutate() { # <name> <python source appended to support.py>
	local name=$1 body=$2 dir
	dir=$(mktemp -d)
	TMPS+=("$dir")
	cp -a . "$dir/t"
	find "$dir/t" -name __pycache__ -prune -exec rm -rf {} + 2>/dev/null
	printf '\n\n%s\n' "$body" >>"$dir/t/fileserve/support.py"
	# shellcheck disable=SC2086
	if (cd "$dir/t" && python3 -m unittest $NEWTESTS >/dev/null 2>&1); then
		die "mutant survived ($name): the model's tests do not pin it"
	fi
}
mutate "safe_join is a plain os.path.join" 'def safe_join(base, name):
    return os.path.join(base, name)'
mutate "safe_join only looks for .. steps" 'def safe_join(base, name):
    if ".." in name.split("/"):
        raise PathEscapeError(name)
    return os.path.join(base, name)'
mutate "safe_join ignores symlinks" 'def safe_join(base, name):
    root = os.path.abspath(base)
    target = os.path.abspath(os.path.join(root, name))
    if os.path.commonpath([root, target]) != root:
        raise PathEscapeError(name)
    return target'
mutate "safe_join compares a prefix without the separator" 'def safe_join(base, name):
    root = os.path.realpath(base)
    target = os.path.realpath(os.path.join(root, name))
    if not target.startswith(root):
        raise PathEscapeError(name)
    return target'
mutate "safe_join treats an absolute name as relative" 'def safe_join(base, name):
    root = os.path.realpath(base)
    target = os.path.realpath(os.path.join(root, name.lstrip("/")))
    if os.path.commonpath([root, target]) != root:
        raise PathEscapeError(name)
    return target'

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>
	cp "$CASE_DIR/hidden/test_attachments_hidden.py" "$1/tests/_hidden_test_attachments.py"
	(cd "$1" && python3 -m unittest tests._hidden_test_attachments >/tmp/xsr-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/tests/_hidden_test_attachments.py"
	return $rc
}
if ! run_hidden .; then
	tail -n 12 /tmp/xsr-hidden.$$
	rm -f /tmp/xsr-hidden.$$
	die "hidden behaviour tests failed (a traversal, absolute or symlink name got through, or a legitimate name was refused)"
fi
dir=$(mktemp -d)
TMPS+=("$dir")
cp -a . "$dir/t"
printf '\n\ndef safe_join(base, name):\n    return os.path.join(base, name)\n' >>"$dir/t/fileserve/support.py"
if run_hidden "$dir/t"; then
	rm -f /tmp/xsr-hidden.$$
	die "download_attachment does not depend on safe_join: reuse is faked"
fi
rm -f /tmp/xsr-hidden.$$

# ---- slop ---------------------------------------------------------------------
slop_check --all-lines --no-tools --files "$SERVE" "$TEST"
