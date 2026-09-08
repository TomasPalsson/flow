#!/usr/bin/env bash
# lib/hookout.sh — shared helpers for Claude Code lifecycle hooks.
# Source it; never execute it:   . "$(dirname "$0")/lib/hookout.sh"
#
# Portable: bash 3.2 (macOS) and bash 5 (Linux), BSD or GNU coreutils.
# Never exits during sourcing. Reads stdin once into HOOK_INPUT.
#
# API (frozen contract: .specs/003-harness-idiot-proof/spec.md, C-A)
#   HOOK_INPUT            raw JSON from stdin ("" when stdin is a TTY/empty)
#   hook_field <jqpath>   print a field ("" if absent/false/null); jq, then python3, else ""
#   have <cmd>            true when <cmd> is on PATH
#   hook_project_dir      physical path of $CLAUDE_PROJECT_DIR (or $PWD)
#   hook_config <key>     raw value of .claude/flow.config.json <key>: strings
#                         verbatim, else compact JSON ("" when absent or no jq)
#   hook_prune_dirs / hook_ignore_patterns / hook_excluded_path /
#   hook_changed_since    same contract, defined in lib/hookpath.sh which this
#                         file sources — see its header
#   hook_stamp_path       "${TMPDIR:-/tmp}/claude-turn-<session_id>"
#   hook_deny/hook_block/hook_feedback <reason>  the blocking channels (deny
#                         JSON, Stop block JSON, stderr + rc 2); all three emit
#                         the reason UNCHANGED and only bump hook_count
#   hook_note <msg>       {"systemMessage":…}, exit 0 — for a hook that will
#                         not block but must not stay silent
#   hook_soft <msg>       Stop-only additionalContext, exit 0, turn continues
#   hook_once <key>       rc 0 the first time <key> is seen this session
#   hook_count <sig>      record <sig>, print how often it was recorded
#   hook_ok               exit 0;  hook_log <text>: append a line to
#                         ${CLAUDE_HOOK_LOG:-/dev/null}
#   hook_off_here / hook_skip_if_off  .claude/flow.off here or above: judging
#                         hooks exit 0, bookkeeping hooks keep running
#   hook_git_managed <f>  in a git work tree and not git-ignored (that call is
#                         the turn-scoped rule below); CC_HOOKS_ALL_FILES=1
#                         makes it always true
#
# Contract: when neither jq nor python3 exists, hook_field prints "" and a hook
# must treat that as "cannot judge" and call hook_ok.

HOOK_INPUT=""
if [ ! -t 0 ]; then
	HOOK_INPUT=$(cat 2>/dev/null || true)
fi

have() { command -v "$1" >/dev/null 2>&1; }

hook_field() {
	if [ -z "$HOOK_INPUT" ]; then
		printf ''
		return 0
	fi
	if have jq; then
		printf '%s' "$HOOK_INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''
	elif have python3; then
		printf '%s' "$HOOK_INPUT" | python3 -c '
import sys, json
path = [p for p in sys.argv[1].lstrip(".").split(".") if p]
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
for p in path:
    if isinstance(d, dict) and p in d:
        d = d[p]
    else:
        sys.exit(0)
if d is None or d is False:
    sys.exit(0)
if d is True:
    print("true")
elif isinstance(d, (str, int, float)):
    print(d)
else:
    print(json.dumps(d))
' "$1" 2>/dev/null || printf ''
	else
		printf ''
	fi
}

hook_off_here() {
	local d
	d=$(hook_project_dir)
	while :; do
		[ -f "$d/.claude/flow.off" ] && return 0
		case "$d" in */*)
			[ "$d" = "/" ] && return 1
			d=${d%/*}
			[ -z "$d" ] && d="/"
			;;
		*) return 1 ;; esac
	done
}
hook_skip_if_off() {
	hook_off_here && exit 0
	return 0
}

hook_project_dir() {
	local d p
	if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then d="$CLAUDE_PROJECT_DIR"; else d="$PWD"; fi
	p=$(cd "$d" 2>/dev/null && pwd -P) || p=""
	if [ -n "$p" ]; then printf '%s' "$p"; else printf '%s' "$d"; fi
}

_hook_tmp() {
	local t
	t="${TMPDIR:-/tmp}"
	printf '%s' "${t%/}"
}

# The session id, sanitised for a file name (cached: HOOK_INPUT is read once).
_hook_sid() {
	if [ -z "${_HOOK_SID:-}" ]; then
		_HOOK_SID=$(hook_field '.session_id')
		[ -z "$_HOOK_SID" ] && _HOOK_SID="nosession"
		_HOOK_SID=$(printf '%s' "$_HOOK_SID" | tr -c 'A-Za-z0-9_-' '_')
	fi
	printf '%s' "$_HOOK_SID"
}

hook_stamp_path() { printf '%s/claude-turn-%s' "$(_hook_tmp)" "$(_hook_sid)"; }

hook_config() {
	local cfg
	have jq || {
		printf ''
		return 0
	}
	cfg="$(hook_project_dir)/.claude/flow.config.json"
	[ -f "$cfg" ] || {
		printf ''
		return 0
	}
	jq -r --arg k "$1" \
		'if type == "object" and has($k) then (.[$k] | if type == "string" then . else tojson end) else empty end' \
		"$cfg" 2>/dev/null || printf ''
}

# Which files may be judged, and what changed this turn: lib/hookpath.sh next
# door. Split out of this file so both halves stay under the size guard's file
# limit and the shared library has room to grow.
_HOOKOUT_DIR=${BASH_SOURCE[0]%/*}
[ "$_HOOKOUT_DIR" = "${BASH_SOURCE[0]}" ] && _HOOKOUT_DIR="."
# shellcheck source=hookpath.sh
. "$_HOOKOUT_DIR/hookpath.sh"

hook_git_managed() {
	[ "${CC_HOOKS_ALL_FILES:-}" = "1" ] && return 0
	local f=$1 d
	have git || return 1
	# hook_nearest_dir, not ${f%/*}: a Write can create a file under
	# directories that do not exist yet (src/new/deep/x.ts). `git -C <missing
	# dir>` fails, which used to make this return 1 and let spec-gate's
	# PreToolUse half allow an unapproved source file simply because its
	# parent directory was new.
	d=$(hook_nearest_dir "$f")
	git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
	_hook_git_ignored "$f" && return 1
	return 0
}

# _json_str <text> → a JSON string literal (with quotes), escaped.
_json_str() {
	if have jq; then
		printf '%s' "$1" | jq -Rs . 2>/dev/null && return 0
	fi
	if have python3; then
		printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null && return 0
	fi
	# Last resort: escape backslash, quote, tab, CR and newlines by hand, and
	# drop the other C0 controls — a raw control character makes the JSON
	# unparseable, which is worse than losing the character.
	printf '"%s"' "$(printf '%s' "$1" |
		sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
			-e "s/$(printf '\t')/\\\\t/g" -e "s/$(printf '\r')/\\\\r/g" |
		tr -d '\001-\010\013\014\016-\037' |
		awk 'BEGIN{ORS="\\n"} {print}' | sed -e 's/\\n$//')"
}

# hook_once <key> — rc 0 the first time this key is seen in this session.
hook_once() {
	local key f
	key=$(printf '%s' "$1" | tr '\n' ' ')
	f="$(_hook_tmp)/claude-once-$(_hook_sid)"
	# -e: a key that starts with "-" is a pattern, never a grep option.
	if [ -f "$f" ] && grep -q -x -F -e "$key" "$f" 2>/dev/null; then return 1; fi
	printf '%s\n' "$key" >>"$f" 2>/dev/null || return 0
	return 0
}

# Record <sig>, print how often it was recorded this session. The number is all
# hooks keep about repeated denials; what to do with it is the caller's call.
hook_count() {
	local sig f n
	sig=$(printf '%s' "$1" | tr '\n' ' ')
	f="$(_hook_tmp)/claude-count-$(_hook_sid)"
	printf '%s\n' "$sig" >>"$f" 2>/dev/null || {
		printf '1\n'
		return 0
	}
	n=$(grep -c -x -F -e "$sig" "$f" 2>/dev/null || printf '1')
	case "$n" in '' | *[!0-9]*) n=1 ;; esac
	printf '%s\n' "$n"
}

# Blocking helpers record the reason and emit it unchanged: the message a hook
# writes is the message the model reads.
_hook_record() { hook_count "${0##*/} ${1%%
*}" >/dev/null 2>&1 || true; }

hook_deny() {
	_hook_record "$1"
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(_json_str "$1")"
	exit 0
}

hook_block() {
	_hook_record "$1"
	printf '{"decision":"block","reason":%s}\n' "$(_json_str "$1")"
	exit 0
}

hook_feedback() {
	_hook_record "$1"
	printf '%s\n' "$1" >&2
	exit 2
}

# Not a block: a line the user sees while the turn continues.
hook_note() {
	printf '{"systemMessage":%s}\n' "$(_json_str "$1")"
	exit 0
}

# Stop only: extra context for the model, no hook-error styling, turn continues.
hook_soft() {
	printf '{"hookSpecificOutput":{"hookEventName":"Stop","additionalContext":%s}}\n' "$(_json_str "$1")"
	exit 0
}

hook_ok() { exit 0; }

hook_log() {
	local f="${CLAUDE_HOOK_LOG:-/dev/null}"
	printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" >>"$f" 2>/dev/null || true
}
