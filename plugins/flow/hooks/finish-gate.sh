#!/usr/bin/env bash
# finish-gate.sh — Stop hook for /flow:next --finish.
# Reads: .specs/*/FINISH.md (fast path: none armed, no spawn).
# Prints: `flow finish check --hook --session <id>`'s stdout, verbatim.
# All block/release logic lives in `flow finish check`; this hook decides
# nothing itself.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off

dir=$(hook_project_dir)
if have git; then
	top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) && [ -n "$top" ] && dir=$top
fi
armed=0
for f in "$dir"/.specs/*/FINISH.md; do
	[ -f "$f" ] && armed=1 && break
done
[ "$armed" = 1 ] || exit 0

sid=$(hook_field .session_id)
if [ -n "${CC_FLOW_BIN:-}" ]; then
	out=$(cd "$dir" && "$CC_FLOW_BIN" finish check --hook --session "$sid" 2>/dev/null) || exit 0
else
	have node || exit 0
	out=$(cd "$dir" && node "$HERE/../bin/flow" finish check --hook --session "$sid" 2>/dev/null) || exit 0
fi
[ -n "$out" ] && printf '%s\n' "$out"
exit 0
