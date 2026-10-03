#!/usr/bin/env bash
# What a perfect run leaves on disk: T002 serialized behind T001, nothing built.
set -euo pipefail
sed -i '/^- \[ \] T002 /s/$/ — after: T001/' .specs/001-recipe-scaling/TASKS.md
node "$EVAL_PLUGIN_ROOT/bin/flow" lint .specs/001-recipe-scaling/TASKS.md >/dev/null
