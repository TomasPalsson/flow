#!/usr/bin/env bash
# A perfect run reads the router, sees `disagreement`, prints the completeness report and touches nothing.
set -euo pipefail
node "$EVAL_PLUGIN_ROOT/bin/flow" next --json --peek >/dev/null
