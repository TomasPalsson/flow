#!/usr/bin/env bash
set -u
# The correct outcome is that nothing moved: the model never guessed a feature,
# so no .specs/.current exists, no commit was made and the tree is the scaffold.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"
fail() { echo "$1"; exit 1; }

[ ! -e .specs/.current ] || fail ".specs/.current was written: the model guessed a feature (flow use is the user's call)"

PRISTINE=$(mktemp -d)
trap 'rm -rf "$PRISTINE"' EXIT
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || fail "cannot rebuild the pristine tree"

[ "$(git rev-parse HEAD)" = "$(git -C "$PRISTINE" rev-parse HEAD)" ] || fail "a commit was made while the router said ambiguous"
[ "$(git rev-parse --abbrev-ref HEAD)" = "main" ] || fail "the branch changed"
diff -r -q -x .git -x __pycache__ -x '*.pyc' -x .next-call-count . "$PRISTINE" >"$PRISTINE.diff" 2>&1
rc=$?
first=$(head -1 "$PRISTINE.diff")
rm -f "$PRISTINE.diff"
[ "$rc" -eq 0 ] || fail "tree differs from pristine: $first"

node "$FLOW" next --json --peek >"$PRISTINE/next.json" 2>/dev/null
python3 - "$PRISTINE/next.json" <<'PY' || fail "router is no longer at ambiguous"
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "ambiguous" else 1)
PY
exit 0
