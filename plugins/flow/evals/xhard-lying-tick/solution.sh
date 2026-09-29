#!/usr/bin/env bash
# A perfect run reads the router, sees `lying`, reports it and touches nothing.
set -euo pipefail
node "$EVAL_PLUGIN_ROOT/bin/flow" next --json >/dev/null
