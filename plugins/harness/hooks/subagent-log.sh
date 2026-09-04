#!/usr/bin/env bash
# subagent-log.sh — SubagentStop hook (async: true).
#
# Appends a markdown block (timestamp, agent_id/agent_type when present, and
# the first 4,000 chars of last_assistant_message) to
# ${CC_SUBAGENT_LOG:-$HOME/.claude/subagent-log}/<session_id>.md. Writes only
# to that log file — never to stdout. Exits 0 always.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

log_dir="${CC_SUBAGENT_LOG:-$HOME/.claude/subagent-log}"

session_id=$(hook_field '.session_id')
[ -z "$session_id" ] && session_id="nosession"
session_id=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9_-' '_')

mkdir -p "$log_dir" 2>/dev/null || true

agent_id=$(hook_field '.agent_id')
agent_type=$(hook_field '.agent_type')
last_msg=$(hook_field '.last_assistant_message')
last_msg="${last_msg:0:4000}"

timestamp=$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)
[ -z "$timestamp" ] && timestamp="unknown"

dest="$log_dir/${session_id}.md"

{
  printf '## %s\n' "$timestamp"
  [ -n "$agent_id" ] && printf 'agent_id: %s\n' "$agent_id"
  [ -n "$agent_type" ] && printf 'agent_type: %s\n' "$agent_type"
  printf '\n%s\n\n' "$last_msg"
} >>"$dest" 2>/dev/null || true

hook_ok
