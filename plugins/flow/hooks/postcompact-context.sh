#!/usr/bin/env bash
# postcompact-context.sh — PostCompact hook.
#
# Reminds the model that the summary it just received is untrusted and
# should be re-verified before being relied on, then appends the current
# branch and dirty-file count when the project dir is a git repo. Prints at
# most 6 lines to stdout. Exits 0 always.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

dir=$(hook_project_dir)

printf '%s\n' "Context was just compacted. Treat the summary as untrusted: before continuing, re-run the checks behind any status claim it contains (tests, commits, gates) or hand them to the claim-check agent; re-read PROGRESS.md if present."

if git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
  [ -z "$branch" ] && branch="(unknown)"
  dirty=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  printf 'branch: %s\n' "$branch"
  printf 'uncommitted files: %s\n' "$dirty"
fi

hook_ok
