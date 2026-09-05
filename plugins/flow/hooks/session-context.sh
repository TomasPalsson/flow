#!/usr/bin/env bash
# session-context.sh — SessionStart hook.
#
# Prints a short digest of repo state, PROGRESS.md, REVIEW.md presence, and
# any .claude/flow.config.json fields that differ from the C4 defaults. Silent
# (exit 0, no output) when the project dir is not a git repo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

dir=$(hook_project_dir)

if hook_off_here; then
  printf 'flow: hooks are OFF in this directory (.claude/flow.off, from `flow off`) — no format, size, tamper, spec, stop or git guards; `flow on` re-enables them.\n'
  hook_ok
fi

if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hook_ok
fi

# _sc_print <line> — print one line, but never more than 20 lines total
# across the whole hook (C10 hard cap). Lines past the budget are dropped
# silently; earlier sections (repo state, then PROGRESS.md, then the
# REVIEW.md note, then harness overrides) always win the remaining budget.
_sc_line_count=0
_sc_print() {
  if [ "$_sc_line_count" -ge 20 ]; then
    return 0
  fi
  printf '%s\n' "$1"
  _sc_line_count=$((_sc_line_count + 1))
}

branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && branch="(unknown)"

uncommitted=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

_sc_print "## Repo state"
_sc_print "branch: $branch"
_sc_print "uncommitted files: $uncommitted"
_sc_print "last 3 commits:"
# Read via a heredoc (not a piped `| while`) so the loop runs in the current
# shell and _sc_line_count increments persist past the loop.
commits=$(git -C "$dir" log -3 --oneline 2>/dev/null)
if [ -n "$commits" ]; then
  while IFS= read -r commit_line; do
    _sc_print "  $commit_line"
  done <<EOF
$commits
EOF
fi

if [ -f "$dir/PROGRESS.md" ]; then
  _sc_print "## PROGRESS.md"
  progress_content=$(head -20 "$dir/PROGRESS.md")
  if [ -n "$progress_content" ]; then
    while IFS= read -r progress_line; do
      _sc_print "$progress_line"
    done <<EOF
$progress_content
EOF
  fi
fi

if [ -f "$dir/REVIEW.md" ]; then
  _sc_print "note: REVIEW.md present"
fi

harness_json="$dir/.claude/flow.config.json"
if [ -f "$harness_json" ] && have jq; then
  for key in maxFileLines maxFuncLines stopGate stopGateFullEverySec sizeGuard formatOnEdit ignore; do
    default=""
    case "$key" in
    maxFileLines) default="400" ;;
    maxFuncLines) default="60" ;;
    stopGate) default="scoped" ;;
    stopGateFullEverySec) default="900" ;;
    sizeGuard) default="true" ;;
    formatOnEdit) default="true" ;;
    ignore) default="migrations/,generated/,locales/,i18n/,.generated." ;;
    esac
    present=$(jq -r --arg k "$key" 'has($k)' "$harness_json" 2>/dev/null)
    if [ "$present" = "true" ]; then
      val=$(jq -r --arg k "$key" 'if (.[$k] | type) == "array" then (.[$k] | join(",")) else (.[$k] | tostring) end' "$harness_json" 2>/dev/null)
      if [ "$val" != "$default" ]; then
        _sc_print "note: harness override: $key=$val"
      fi
    fi
  done
fi

# flow worktree / branch mismatch: agent-view sessions start in the main checkout,
# so a flow that lives in a worktree or on another branch is invisible from here.
if [ -f "$dir/.claude/flow.json" ] && have jq; then
  _fw=$(jq -r '.worktree // empty' "$dir/.claude/flow.json" 2>/dev/null)
  _fb=$(jq -r '.branch // empty' "$dir/.claude/flow.json" 2>/dev/null)
  _top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
  _cur=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [ -n "$_fw" ] && [ "$_fw" != "$_top" ]; then
    _sc_print "note: flow worktree mismatch — this flow lives in $_fw (branch $_fb); this session is in $_top. Start the session there (agents $_fw) or cd before touching it."
  elif [ -n "$_fb" ] && [ "$_fb" != "$_cur" ]; then
    _sc_print "note: flow branch mismatch — .claude/flow.json says branch $_fb but this checkout is on $_cur."
  fi
fi

# flow next (C23): append its output within the 20-line budget above,
# via the CLI at $HERE/../bin/flow when present, else `harness` on PATH,
# else print nothing (a missing/broken CLI never fails the session). No
# `timeout` binary here — GNU-only and banned by the portability scan; `next`
# only reads local git state and small files, so it returns fast enough that
# a hard guard is unnecessary.
_sc_next_cli=""
if [ -x "$HERE/../bin/flow" ]; then
  _sc_next_cli="$HERE/../bin/flow"
elif have harness; then
  _sc_next_cli="harness"
fi
if [ -n "$_sc_next_cli" ]; then
  _sc_next_out=$(cd "$dir" 2>/dev/null && "$_sc_next_cli" next 2>/dev/null || true)
  if [ -n "$_sc_next_out" ]; then
    while IFS= read -r _sc_next_line; do
      _sc_print "$_sc_next_line"
    done <<EOF
$_sc_next_out
EOF
  fi
fi

hook_ok
