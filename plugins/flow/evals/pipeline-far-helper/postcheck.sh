#!/usr/bin/env bash
set -u
# The pipeline must leave a green suite (including the test it wrote for
# url_path) and slop-free code in the touched model and test files.
python3 -m unittest discover -s tests >/dev/null 2>&1 || { echo "suite red after the pipeline"; exit 1; }
grep -rl "url_path" tests >/dev/null 2>&1 || { echo "no test covers url_path"; exit 1; }
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files app/models/post.py $(grep -rl "url_path" tests)
