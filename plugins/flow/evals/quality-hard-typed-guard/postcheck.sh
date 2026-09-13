#!/usr/bin/env bash
set -u
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --files app/models/order.py
