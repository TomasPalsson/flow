#!/usr/bin/env bash
set -u
# --no-tools: jscpd reports the dataclass header shared with app/models/user.py (scaffold boilerplate) as a clone; the reuse graders own the real detection here.
"$EVAL_PLUGIN_ROOT/skills/no-slop/scripts/slop-check" --all-lines --strict --no-tools --files app/models/post.py
