#!/usr/bin/env bash
# turn-stamp.sh — UserPromptSubmit hook.
#
# Touches the per-session turn stamp file used by stop-gate.sh's "changed
# this turn" detection (C3). No stdout, exit 0 always.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

stamp=$(hook_stamp_path)
: >"$stamp" 2>/dev/null || true

hook_ok
