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
#
# Claude Code never waits on it: the payload is read here, then handed to
# a detached `worklog hook-run` — its own session (setsid via the stock
# perl) and none of this hook's stdio — so the hook exits at once and
# worklog still finishes after a SessionEnd teardown.
set -u

command -v worklog >/dev/null 2>&1 || exit 0
# With fd 0 closed, `$(cat)`'s own pipe would land on fd 0 and cat would
# wait on itself forever — no stdin means no event, so just leave.
[ -e /dev/stdin ] || exit 0
payload=$(cat)
perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' worklog hook-run <<<"$payload" >/dev/null 2>&1 &
exit 0
