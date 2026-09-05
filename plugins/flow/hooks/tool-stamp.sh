#!/usr/bin/env bash
# tool-stamp.sh — PreToolUse/Bash hook. Runs first, before rtk-rewrite.sh and
# git-guard.sh (C5).
#
# Touches a per-session "tool stamp" file that post-bash-write.sh (C19) uses
# to find files a Bash command wrote through cat/sed/heredocs — the coverage
# gap left by the Edit|Write|NotebookEdit-matched hooks when auto mode edits
# files through Bash instead. Never blocks; no stdout.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

stamp="$(hook_stamp_path)-tool"
: >"$stamp" 2>/dev/null || true

hook_ok
