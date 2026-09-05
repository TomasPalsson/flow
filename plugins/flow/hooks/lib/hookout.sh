#!/usr/bin/env bash
# lib/hookout.sh — shared helpers for Claude Code lifecycle hooks.
# Source it; never execute it:   . "$(dirname "$0")/lib/hookout.sh"
#
# Portable: bash 3.2 (macOS) and bash 5 (Linux), BSD or GNU coreutils.
# Never exits during sourcing. Reads stdin once into HOOK_INPUT.
#
# API
#   HOOK_INPUT            raw JSON from stdin ("" when stdin is a TTY/empty)
#   hook_field <jqpath>   print a field ("" if absent/false/null); jq, then python3, else ""
#   have <cmd>            true when <cmd> is on PATH
#   hook_project_dir      print $CLAUDE_PROJECT_DIR or $PWD
#   hook_stamp_path       print "${TMPDIR:-/tmp}/claude-turn-<session_id>"
#   hook_deny <reason>    PreToolUse: print deny JSON, exit 0
#   hook_block <reason>   Stop: print {"decision":"block","reason":...}, exit 0
#   hook_feedback <text>  PostToolUse: print <text> to stderr, exit 2
#   (deny/block/feedback append a "/lesson" suggestion from the second
#    identical reason in a session — see _lesson_nudge)
#   hook_ok               exit 0
#   hook_off_here         true when this directory (or an ancestor) carries a
#                         .claude/flow.off marker — `flow off` wrote it; every
#                         judging hook calls hook_skip_if_off right after
#                         sourcing and exits 0. Bookkeeping hooks (stamps,
#                         logs, session notice, worklog, rtk) keep running.
#   hook_skip_if_off      exit 0 when hook_off_here
#   hook_git_managed <f>  true when <f> sits inside a git work tree and is
#                         not git-ignored; per-file enforcement hooks skip
#                         anything else (scratch files, /tmp, ignored build
#                         output) — git is the boundary of what is enforced.
#                         CC_HOOKS_ALL_FILES=1 makes it always true.
#   hook_log <text>       append a line to ${CLAUDE_HOOK_LOG:-/dev/null}
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

hook_git_managed() {
	[ "${CC_HOOKS_ALL_FILES:-}" = "1" ] && return 0
	local f=$1 d
	have git || return 1
	d=$(dirname "$f")
	git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
	if git -C "$d" -c core.quotePath=false check-ignore -q -- "$f" 2>/dev/null; then
		# Ignored — unless an ignore file is itself uncommitted this turn: adding
		# a path to .gitignore in the same command as editing it would otherwise
		# dodge every hook. Only a committed ignore rule exempts a file.
		if git -C "$d" status --porcelain --untracked-files=all 2>/dev/null | awk '{print $NF}' | grep -qE '(^|/)\.gitignore$|^\.git/info/exclude$'; then
			return 0
		fi
		return 1
	fi
	return 0
}

hook_project_dir() {
	if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then printf '%s' "$CLAUDE_PROJECT_DIR"; else printf '%s' "$PWD"; fi
}

hook_stamp_path() {
	local sid tmp
	sid=$(hook_field .session_id)
	[ -z "$sid" ] && sid="nosession"
	sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	printf '%s/claude-turn-%s' "$tmp" "$sid"
}

# _json_str <text> → a JSON string literal (with quotes), escaped.
_json_str() {
	if have jq; then
		printf '%s' "$1" | jq -Rs . 2>/dev/null && return 0
	fi
	if have python3; then
		printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null && return 0
	fi
	# Last resort: escape backslash, quote, and newlines by hand.
	printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | awk 'BEGIN{ORS="\\n"} {print}' | sed -e 's/\\n$//')"
}

# _lesson_fire <reason> → append one fire line for the first marker found in
# <reason> to $(hook_project_dir)/.claude/lesson-fires.log (mkdir -p; any
# failure swallowed). Grammar: <date>\t<what>\t<UTC ISO-8601 Z>\t<hook
# basename>; tab and newline are stripped from what with tr -d '\t\n'.
_lesson_fire() {
	local reason=$1 remainder marker_date marker_what target_dir
	remainder=${reason#*"[lesson("}
	marker_date=${remainder%%)*}
	marker_what=${remainder#*"): "}
	marker_what=${marker_what%%]*}
	marker_what=$(printf '%s' "$marker_what" | tr -d '\t\n')
	target_dir="$(hook_project_dir)/.claude"
	mkdir -p "$target_dir" 2>/dev/null || return 0
	printf '%s\t%s\t%s\t%s\n' "$marker_date" "$marker_what" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${0##*/}" >>"$target_dir/lesson-fires.log" 2>/dev/null || return 0
}

# _lesson_nudge <reason> → <reason>, plus a "/lesson" line when the same
# hook has produced the same first line of reason before in this session.
# The second identical deny/block/feedback is the deterministic "same
# mistake twice" signal: the fix is a guardrail, not another retry. Counter
# lives in ${TMPDIR:-/tmp}/claude-lesson-<session>; failures fall through
# to the unchanged reason. Reasons that already mention /lesson are left
# alone (stop-gate adds its own wording).
#
# A reason carrying a marker `[lesson(<YYYY-MM-DD>): <what>]` (first one
# counts) is a lesson firing again: append one fire line to
# `.claude/lesson-fires.log` (mkdir -p; any failure swallowed) and return
# the reason unchanged — no nudge text, no signature file write.
_lesson_nudge() {
	local reason=$1 sid tmp f sig n
	case "$reason" in *"/lesson"*)
		printf '%s' "$reason"
		return 0
		;;
	esac
	case "$reason" in
	*"[lesson("[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"): "*"]"*)
		_lesson_fire "$reason"
		printf '%s' "$reason"
		return 0
		;;
	esac
	sid=$(hook_field .session_id)
	[ -z "$sid" ] && sid="nosession"
	sid=$(printf '%s' "$sid" | tr -c 'A-Za-z0-9_-' '_')
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	f="$tmp/claude-lesson-$sid"
	sig=$(printf '%s %s' "${0##*/}" "${reason%%
*}" | cksum | cut -d' ' -f1)
	printf '%s\n' "$sig" >>"$f" 2>/dev/null || {
		printf '%s' "$reason"
		return 0
	}
	n=$(grep -c -x "$sig" "$f" 2>/dev/null || printf '1')
	case "$n" in '' | *[!0-9]*) n=1 ;; esac
	if [ "$n" -ge 2 ]; then
		printf '%s\n\nthe same thing was blocked %s times this session (%s). If this is a recurring mistake rather than a one-off, suggest /lesson to the user in one line; do not run it unasked.' "$reason" "$n" "${0##*/}"
	else
		printf '%s' "$reason"
	fi
}

hook_deny() {
	printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":%s}}\n' "$(_json_str "$(_lesson_nudge "$1")")"
	exit 0
}

hook_block() {
	printf '{"decision":"block","reason":%s}\n' "$(_json_str "$(_lesson_nudge "$1")")"
	exit 0
}

hook_feedback() {
	printf '%s\n' "$(_lesson_nudge "$1")" >&2
	exit 2
}

hook_ok() { exit 0; }

hook_log() {
	local f="${CLAUDE_HOOK_LOG:-/dev/null}"
	printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$1" >>"$f" 2>/dev/null || true
}
