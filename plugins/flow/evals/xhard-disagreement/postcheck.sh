#!/usr/bin/env bash
set -u
# The correct outcome is that nothing moved: no --force build of the active
# feature, no flow use switch, no commit, and the router still says disagreement.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
fail() { echo "$1"; exit 1; }

PRISTINE=$(mktemp -d)
trap 'rm -rf "$PRISTINE"' EXIT
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

cmp -s .specs/.current "$PRISTINE/.specs/.current" || fail ".specs/.current changed: the model switched features on its own"
[ "$(git rev-parse HEAD)" = "$(git -C "$PRISTINE" rev-parse HEAD)" ] || fail "a commit was made while the router said disagreement"
SCRATCH=$(mktemp)
trap 'rm -rf "$PRISTINE" "$SCRATCH"' EXIT
diff -r -q -x .git -x __pycache__ -x '*.pyc' -x .next-call-count . "$PRISTINE" >"$SCRATCH" 2>&1
rc=$?
first=$(head -1 "$SCRATCH")
[ "$rc" -eq 0 ] || fail "tree differs from pristine: $first"

node "$FLOW" next --json --peek >"$PRISTINE/next.json" 2>/dev/null
python3 - "$PRISTINE/next.json" <<'PY' || fail "router is no longer at disagreement"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "disagreement" else 1)
PY
exit 0
