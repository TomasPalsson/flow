#!/usr/bin/env bash
set -u
# app/auth.py deliberately keeps an unused `json` import as this case's
# tempting-cleanup bait (NS-24: only the reported typo is in scope). With
# tools available, ruff would report that untouched import as NS-11 even
# though leaving it alone is the correct behaviour here, so this postcheck
# runs --no-tools and grades the stdlib checks only.
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files app/auth.py
