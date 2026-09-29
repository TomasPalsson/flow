#!/usr/bin/env bash
# A perfect run leaves the tree exactly as scaffolded: it prints the summary and
# the router's gate line, and stops.
set -euo pipefail
node "$EVAL_PLUGIN_ROOT/bin/flow" next --json --peek >/dev/null
