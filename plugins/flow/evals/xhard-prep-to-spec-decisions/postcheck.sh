#!/usr/bin/env bash
set -u
# /flow:spec on a finished PREP.md: spec.md carries the decisions and keeps the
# out-of-scope item out, TASKS.md lints and is unapproved, nothing was built.
fail() { echo "$1"; exit 1; }
PRISTINE=$(mktemp -d)
trap 'rm -rf "$PRISTINE"' EXIT
(cd "$PRISTINE" && bash "$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE/scaffold.sh" >/dev/null 2>&1) || fail "could not regenerate the pristine tree"

diff -r -x __pycache__ -x '*.pyc' -x .git -x .specs -x .claude "$PRISTINE" . >/dev/null \
	|| fail "source, tests or README changed: a spec run must not build anything"
[ "$(git rev-list --count HEAD 2>/dev/null)" = "$(git -C "$PRISTINE" rev-list --count HEAD)" ] \
	|| fail "a spec run made a commit"

DIR=.specs/001-order-csv-export
[ -f "$DIR/PREP.md" ] || fail "PREP.md is gone"
[ "$(find .specs -maxdepth 1 -type d -name '[0-9][0-9][0-9]-*' | wc -l)" = "1" ] \
	|| fail "a second feature directory was allocated: the prepped one must be reused"
[ -s "$DIR/spec.md" ] || fail "no spec.md beside the PREP.md"
[ -s "$DIR/TASKS.md" ] || fail "no TASKS.md: a dispatch spec writes spec.md and TASKS.md"

# every decision is in the spec
grep -q 'RFC 4180' "$DIR/spec.md" || fail "spec.md lost D-01 (RFC 4180)"
grep -q 'CRLF' "$DIR/spec.md" || fail "spec.md lost D-01's CRLF line endings"
grep -Eqi 'no new dependenc|standard library only|stdlib only' "$DIR/spec.md" || fail "spec.md lost D-02 (no new dependencies)"
grep -Eq '10,000|10000|10k' "$DIR/spec.md" || fail "spec.md lost D-03 (the 10,000-row cap)"
grep -q -- '--out' "$DIR/spec.md" || fail "spec.md lost D-05 (the --out entry point)"
grep -q 'conflicts with D-' "$DIR/spec.md" && fail "spec.md flags a conflict with a decision that nothing contradicts"

# the out-of-scope item is only ever a non-goal: a line about streaming is fine
# under a Non-goals / Not this heading or when the line opens with a negation.
python3 - "$DIR/spec.md" "$DIR/TASKS.md" <<'PY' || exit 1
import re
import sys

spec, tasks = sys.argv[1], sys.argv[2]
# a line outside a Non-goals heading may mention streaming only to exclude it, and
# only by OPENING with the negation ("No streaming ..."); a negation word buried in
# a requirement ("streams in chunks instead of being refused") does not count
lead = re.compile(r"^(no|not|never|without)\b", re.I)
# a line that REJECTS streaming is also safe: a rejection word directly before the
# streaming word ("instead of streaming", "not stream", "no chunking"), the refusal
# named before it ("refuses ... instead of streaming"), or "out of scope" on the line
rejects = re.compile(r"\b(instead of|rather than|not|no|never|without)\s+(?:\w+\s+){0,2}(?:stream|chunk)|\brefus\w*\b.*(?:stream|chunk)|out of scope|out-of-scope|non-?goal", re.I)
head_ok = re.compile(r"non-?goals?|not this|out of scope|out-of-scope", re.I)
heading = ""
for n, line in enumerate(open(spec, encoding="utf-8"), 1):
    if line.lstrip().startswith("#"):
        heading = line
        continue
    if re.search(r"(?<![A-Za-z])(?:stream|chunk)", line, re.I) and not head_ok.search(heading) and not rejects.search(line) and not lead.match(re.sub(r"^[\s>*|-]*(?:(?:FR|NFR|D|AC)-\d+\s*\|[^|]*\|)?[\s>*|-]*", "", line)):
        print("spec.md:%d treats streaming/chunking as something to build: %s" % (n, line.strip()[:100]))
        sys.exit(1)
for n, line in enumerate(open(tasks, encoding="utf-8"), 1):
    if re.search(r"(?<![A-Za-z])(?:stream|chunk)", line, re.I):
        print("TASKS.md:%d plans streaming/chunking, which the prep put out of scope" % n)
        sys.exit(1)
PY

# the plan: lint-clean, a real Base, unapproved, and the router says so
grep -rEq '^[[:space:]]*Approved:' .specs && fail "an Approved: line exists: a spec run never approves its own plan"
node "$EVAL_PLUGIN_ROOT/bin/flow" lint "$DIR/TASKS.md" --json >/tmp/xhard-p2-lint.$$ 2>&1 || { rm -f /tmp/xhard-p2-lint.$$; fail "flow lint reports an ERROR in TASKS.md"; }
rm -f /tmp/xhard-p2-lint.$$
BASE=$(sed -n 's/.*Base: \([0-9a-f]\{7,40\}\).*/\1/p' "$DIR/TASKS.md" | head -1)
[ -n "$BASE" ] && git cat-file -e "$BASE^{commit}" 2>/dev/null || fail "TASKS.md Base: is not a real commit in this repo"
STATE=$(node "$EVAL_PLUGIN_ROOT/bin/flow" next --json --peek 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' 2>/dev/null)
[ "$STATE" = "unapproved" ] || fail "router state is '$STATE', expected unapproved"
exit 0
