#!/usr/bin/env bash
# worklog-hook.sh — forwards PreToolUse, PostToolUse, SessionStart,
# SessionEnd, Stop, SubagentStop and UserPromptSubmit events to
# `worklog hook-run` when the `worklog` binary is installed; a no-op
# (exit 0) otherwise.
#
# Deliberately does NOT source lib/hookout.sh: hookout.sh reads all of
# stdin into HOOK_INPUT at source time, which would prevent
# `worklog hook-run` from seeing the original JSON payload. The
# guard-then-exec below is the whole script so the hook's stdin reaches
# worklog untouched.
set -u

command -v worklog >/dev/null 2>&1 || exit 0
exec worklog hook-run
