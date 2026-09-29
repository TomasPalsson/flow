#!/usr/bin/env bash
# What a perfect run leaves on disk: T001 ticked against the commit that already
# exists (no rebuild), T002 untouched for the next call.
set -euo pipefail
python3 -m unittest tests.test_isbn >/dev/null
node "$EVAL_PLUGIN_ROOT/bin/flow" tick T001
