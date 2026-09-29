#!/usr/bin/env bash
set -u
# Full pipeline end to end on a node ESM repo: artifacts and gate discipline,
# then the code (reuse, no guard, errors not swallowed), then mutants of the new
# code against the MODEL's own tests, then the hidden behaviour tests.
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
FLOW="node $EVAL_PLUGIN_ROOT/bin/flow"
die() { echo "$1"; exit 1; }

# ---- pipeline artifacts --------------------------------------------------------
CUR=$(tr -d '[:space:]' <.specs/.current 2>/dev/null)
{ [ -n "$CUR" ] && [ -d ".specs/$CUR" ]; } || die "no .specs/.current pointing at a feature dir"
FEAT=.specs/$CUR
[ -f "$FEAT/TASKS.md" ] || die "no $FEAT/TASKS.md: the pipeline never drafted a plan"
$FLOW lint "$FEAT/TASKS.md" --json >/tmp/xhard-lint.$$ 2>/dev/null
python3 - /tmp/xhard-lint.$$ "$FEAT" <<'PY'
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
    bad("plan has %d task(s); two functions with different failure rules, expected at least 2" % len(work))
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
if git status --porcelain | grep -v -E ' \.specs/| \.claude/' | grep . >/dev/null; then
	die "source changes left uncommitted (PASS would not describe HEAD)"
fi

# ---- the diff stayed in its lane ----------------------------------------------
BASEC=$(git log --format=%h --grep='^services: overdue invoices and customer labels$' -n 1)
[ -n "$BASEC" ] || die "scaffold history missing"
for f in $(git diff --name-only "$BASEC" -- src package.json); do
	[ "$f" = "src/services/invoices.js" ] || die "touched a source file outside the feature: $f"
done
[ -z "$(git diff --diff-filter=D --name-only "$BASEC")" ] || die "a file was deleted"
if git diff "$BASEC" -- src | grep -E '^-[^-]' | grep . >/dev/null; then die "existing source lines were removed or edited"; fi
if git diff "$BASEC" -- test | grep -E '^-[^-]' | grep -v -E '^-import ' | grep . >/dev/null; then die "an existing test line was removed or edited"; fi

node --test >/dev/null 2>&1 || die "suite red after the pipeline"

# ---- code: reuse, no guard, errors not swallowed ---------------------------------
SVC=src/services/invoices.js
# Comments cannot satisfy or trip a check: look at code only, imports excluded.
CODE=$(grep -v -E '^[[:space:]]*(import |//|\*|/\*)' "$SVC" | sed -E 's://.*$::')
for name in keepTrying renderAmount parseInvoice; do
	printf '%s\n' "$CODE" | grep -q "$name(" || die "$SVC never calls the existing $name helper"
done
if printf '%s\n' "$CODE" | grep -E 'toLocaleString|Intl\.|toFixed' >/dev/null; then die "$SVC hand-rolls money formatting"; fi
ADDED=$(git diff "$BASEC" -- "$SVC" | grep -E '^\+[^+]' | sed -E 's/^\+//' | grep -v -E '^[[:space:]]*(//|\*|/\*)' | sed -E 's://.*$::')
if printf '%s\n' "$ADDED" | grep -E '\bwhile\b|\bdo[[:space:]]*\{|\bfor[[:space:]]*\(' | grep -v -E 'for[[:space:]]*\((const|let)[[:space:]]+[A-Za-z_]+[[:space:]]+of[[:space:]]' >/dev/null; then
	die "$SVC hand-rolls a loop; retries belong to keepTrying"
fi
if printf '%s\n' "$ADDED" | grep -E 'typeof |isInteger|instanceof|\?\.|=== null|== null|=== undefined|Array\.isArray|Number\.isNaN' >/dev/null; then
	die "added code guards a value the parser or the caller contract already guarantees"
fi
if printf '%s\n' "$ADDED" | grep -E 'catch' >/dev/null; then
	die "added catch: the shared helper retries and errors must propagate untouched"
fi

# ---- mutants: the model's OWN tests (no hidden file yet) must catch each --------
# A mutant whose target text is absent is inconclusive (skipped), never the model's fault;
# only code lines are mutated, so a match inside a comment cannot produce a false verdict.
mutate() { # <name> <file> <python regex> <replacement>
	local dir rc
	dir=$(mktemp -d)
	cp -a . "$dir/t"
	python3 - "$dir/t/$2" "$3" "$4" <<'PY'
import re, sys
path, pattern, new = sys.argv[1:4]
out, n = [], 0
for line in open(path).read().split("\n"):
    if line.lstrip().startswith(("//", "*", "/*", "import ")):
        out.append(line)
        continue
    line, k = re.subn(pattern, new, line)
    n += k
    out.append(line)
if n == 0:
    sys.exit(3)
open(path, "w").write("\n".join(out))
PY
	rc=$?
	if [ "$rc" -eq 3 ]; then
		rm -rf "$dir"
		echo "mutant '$1' skipped: literal not present in code"
		return 0
	fi
	if (cd "$dir/t" && node --test >/dev/null 2>&1); then
		rm -rf "$dir"
		die "mutant survived ($1): the model's tests do not pin it"
	fi
	rm -rf "$dir"
}
mutate "invoice route" "$SVC" '/invoices/' '/invoice/'
mutate "attempt count" "$SVC" '\b3\b' '2'

# ---- hidden behaviour ---------------------------------------------------------
run_hidden() { # <tree dir>: copy the hidden file in, run the suite, remove it
	cp "$CASE_DIR/hidden/summaries.hidden.test.js" "$1/test/zz-hidden-summaries.test.js"
	(cd "$1" && node --test >/tmp/xhard-hidden.$$ 2>&1)
	local rc=$?
	rm -f "$1/test/zz-hidden-summaries.test.js"
	return $rc
}
if ! run_hidden .; then
	grep -E '^not ok|^# (fail|pass)|failureType|error:' /tmp/xhard-hidden.$$ | head -n 12
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
		die "$SVC does not depend on the shared $1 helper: reuse is faked"
	fi
	rm -rf "$dir"
}
break_helper keepTrying src/lib/attempt.js 'export async function keepTrying(task) { return await task() }'
break_helper renderAmount src/lib/money.js 'export function renderAmount(cents) { return "amount:" + cents }'
break_helper parseInvoice src/models/invoice.js 'export function parseInvoice(raw) { return { id: raw.id, customer: raw.customer, totalCents: 0 } }'
rm -f /tmp/xhard-hidden.$$

# ---- slop ---------------------------------------------------------------------
TOUCHED=$( { git diff --name-only "$BASEC" -- test src; git ls-files --others --exclude-standard test src; } | grep '\.js$' | sort -u)
# shellcheck disable=SC2086
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files $TOUCHED
