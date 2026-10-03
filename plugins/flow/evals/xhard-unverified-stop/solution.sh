#!/usr/bin/env bash
# A perfect run only reads: it asks the router, reports what is left and prints the
# router's gate line. Nothing on disk changes.
set -euo pipefail
node "$EVAL_PLUGIN_ROOT/bin/flow" next --peek >/dev/null
