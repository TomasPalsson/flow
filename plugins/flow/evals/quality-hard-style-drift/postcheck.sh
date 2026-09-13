#!/usr/bin/env bash
set -u
# --no-tools: parse_int_list's small comma-split-and-map shape is close
# enough to parse_line's for jscpd to call it a clone once identifiers are
# normalized, even though they parse different things - a false-positive
# NS-01, not the style-matching (NS-25) this case actually tests for.
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files app/legacy/parser.py
