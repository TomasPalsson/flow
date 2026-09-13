#!/usr/bin/env bash
set -u
# The pipeline must leave a green suite and slop-free code: every added line
# of the touched source and test file passes the no-slop mechanical checks.
python3 -m unittest discover -s tests >/dev/null 2>&1 || { echo "suite red after the pipeline"; exit 1; }
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files src/posts.py tests/test_posts.py
