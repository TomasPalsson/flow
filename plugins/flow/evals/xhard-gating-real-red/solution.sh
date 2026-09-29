#!/usr/bin/env bash
# What a perfect gating run leaves on disk: the SOURCE fixed (tests untouched),
# a green suite, PASS-<HEAD>.md, both gates ticked through flow tick. No Verified:.
set -euo pipefail
FLOW="$EVAL_PLUGIN_ROOT/bin/flow"
SPEC=.specs/001-parcel-rates

sed -i 's/if weight_g < limit:/if weight_g <= limit:/' parcelly/tiers.py
python3 -m unittest discover -s tests >/dev/null 2>&1
git add parcelly/tiers.py
git commit -q -m "fix: weight tier upper bounds are inclusive (1000 g is light, 5000 g is medium)"
SHA=$(git rev-parse --short HEAD)

cat >"$SPEC/PASS-$SHA.md" <<MD
# PASS-$SHA

| Gate | Command | Exit |
|------|---------|------|
| G001 | python3 -m unittest discover -s tests | 0 |
| G002 | whole-branch review of Base..HEAD, one finding (inclusive tier bounds), fixed in parcelly/tiers.py | 0 |
MD

node "$FLOW" tick G001
node "$FLOW" tick G002
git add "$SPEC"
git commit -q -m "chore: PASS for $SHA, tick gates"
