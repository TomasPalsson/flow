#!/usr/bin/env bash
# turn-stamp.sh — UserPromptSubmit hook.
#
# Touches the per-session turn stamp file used by stop-gate.sh's "changed
# this turn" detection (C3). No stdout, exit 0 always.
#
# The stamp is reset only when it is missing or stop-gate.sh left
# "<stamp>.consumed" (it judged the turn). A turn the user interrupted never
# reaches Stop, so its stamp stays and its edits are still in the next turn's
# change set instead of falling behind a fresh stamp unjudged.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

stamp=$(hook_stamp_path)
if [ ! -e "$stamp" ] || [ -e "$stamp.consumed" ]; then
	: >"$stamp" 2>/dev/null || true
	rm -f "$stamp.consumed" 2>/dev/null || true
fi

hook_ok
