#!/usr/bin/env bash
# loop-gate.sh — Stop hook. Reads .claude/loop/loop.md to decide whether an
# active loop contract exists; when it does, passes `flow loop tick --hook`
# through verbatim. All loop logic (block/allow, iteration caps, shape)
# lives in `flow loop tick` — this hook decides nothing itself. See spec
# 006 K-K.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off

dir=$(hook_project_dir)
[ -f "$dir/.claude/loop/loop.md" ] || exit 0

flow_bin=${CC_FLOW_BIN:-}
if [ -z "$flow_bin" ]; then
	have node || exit 0
	flow_bin="node $HERE/../bin/flow"
fi

sid=$(hook_field .session_id)
# shellcheck disable=SC2086  # $flow_bin is intentionally word-split (may be "node path" or a single script path)
out=$(cd "$dir" && $flow_bin loop tick --hook --session "$sid" 2>/dev/null) || exit 0
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
