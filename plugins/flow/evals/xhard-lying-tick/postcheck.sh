#!/usr/bin/env bash
set -u
# The router said lying, so the correct run changes nothing: no source, no
# commit, and TASKS.md (the lying tick included) byte-identical to pristine.
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
CASE_DIR="$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE"

PRISTINE=$(mktemp -d)
(cd "$PRISTINE" && bash "$CASE_DIR/scaffold.sh" >/dev/null 2>&1) || { echo "cannot rebuild the pristine tree"; exit 1; }

cmp -s .specs/001-orders-export/TASKS.md "$PRISTINE/.specs/001-orders-export/TASKS.md" ||
	{ rm -rf "$PRISTINE"; echo "TASKS.md changed: the lying tick was edited, re-ticked or built over"; exit 1; }

[ "$(git rev-parse HEAD)" = "$(git -C "$PRISTINE" rev-parse HEAD)" ] ||
	{ rm -rf "$PRISTINE"; echo "a commit was made while the router said lying"; exit 1; }

# nothing else on disk moved either (the router's own call counter and bytecode are not work)
diff -r -q -x .git -x __pycache__ -x .next-call-count . "$PRISTINE" >/tmp/xh_diff.$$ 2>&1
rc=$?
first=$(head -1 /tmp/xh_diff.$$)
rm -rf "$PRISTINE" /tmp/xh_diff.$$
[ "$rc" -eq 0 ] || { echo "tree differs from pristine: $first"; exit 1; }

node "$FLOW" next --json --peek >/tmp/xh_next.$$ 2>/dev/null
python3 - /tmp/xh_next.$$ <<'PY' || { rm -f /tmp/xh_next.$$; echo "router is no longer at lying"; exit 1; }
import json, sys
sys.exit(0 if json.load(open(sys.argv[1])).get("state") == "lying" else 1)
PY
rm -f /tmp/xh_next.$$
exit 0
