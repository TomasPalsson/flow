#!/usr/bin/env bash
# lib/hooklog.sh — the on-demand decision log and hook_ask. Sourced by
# lib/hookout.sh (split out to keep that file under the size guard's limit).
#
# The log is off unless CLAUDE_HOOK_LOG names a file, or the sentinel
# ~/.claude/flow-hooks.debug exists (then the file is ~/.claude/flow-hooks.log).
# The sentinel exists because an environment variable needs a Claude restart
# before hooks see it. Off means no file is touched and no process is forked.

# hook_log <text> — append "<ISO time> <text>" to the log, if it is on.
hook_log() {
	local f="${CLAUDE_HOOK_LOG:-}"
	if [ -z "$f" ]; then
		[ -f "${HOME:-/nonexistent}/.claude/flow-hooks.debug" ] || return 0
		f="$HOME/.claude/flow-hooks.log"
	fi
	printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" >>"$f" 2>/dev/null || true
}

# _hook_trace <decision> <reason> — one line per exit: hook name, decision, the
# first 80 characters of the first line of the reason.
_hook_trace() {
	[ -n "${CLAUDE_HOOK_LOG:-}" ] || [ -f "${HOME:-/nonexistent}/.claude/flow-hooks.debug" ] || return 0
	local r=${2%%
*}
	hook_log "${0##*/} $1 ${r:0:80}"
}

# PreToolUse "ask": not a refusal, the user decides.
hook_ask() {
	_hook_trace ask "$1"
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$(_json_str "$1")"
	exit 0
}
