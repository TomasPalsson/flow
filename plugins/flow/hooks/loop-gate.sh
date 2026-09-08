#!/usr/bin/env bash
# loop-gate.sh — Stop hook. See spec 006 K-K.
# Reads: .claude/loop/loop.md (fast path: no contract, no spawn).
# Prints: `flow loop tick --hook --session <id>`'s stdout, verbatim.
# All loop logic (block/allow, iteration caps, shape) lives in `flow
# loop tick`; this hook decides nothing itself.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off

# The contract lives at the git toplevel (K-A); the session may have started
# in a subdirectory, so resolve the toplevel before the fast path.
dir=$(hook_project_dir)
if have git; then
	top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] && dir=$top
fi
[ -f "$dir/.claude/loop/loop.md" ] || exit 0

sid=$(hook_field .session_id)
if [ -n "${CC_FLOW_BIN:-}" ]; then
	out=$(cd "$dir" && "$CC_FLOW_BIN" loop tick --hook --session "$sid" 2>/dev/null) || exit 0
else
	have node || exit 0
	out=$(cd "$dir" && node "$HERE/../bin/flow" loop tick --hook --session "$sid" 2>/dev/null) || exit 0
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
