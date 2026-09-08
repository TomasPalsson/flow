#!/usr/bin/env bash
# worklog-hook.sh — forwards SessionStart and SessionEnd events to
# `worklog hook-run` when the `worklog` binary is installed; a no-op
# (exit 0) otherwise. Never propagates worklog's stdout or exit code:
# this hook only records history and must never narrate or block a turn.
#
# Deliberately does NOT source lib/hookout.sh: hookout.sh reads all of
# stdin into HOOK_INPUT at source time, which would prevent
# `worklog hook-run` from seeing the original JSON payload. The
# guard-then-swallow below is the whole script so the hook's stdin
# reaches worklog untouched: `worklog` runs as a child (not via `exec`)
# with its stdout, stderr and exit code all discarded, and the script
# always ends on `exit 0`.
set -u

command -v worklog >/dev/null 2>&1 || exit 0
{ worklog hook-run >/dev/null 2>&1; } 2>/dev/null || true
exit 0
