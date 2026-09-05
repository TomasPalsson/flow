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
#   hook_project_dir      print the project dir: CLAUDE_PROJECT_DIR when the
#                         edited file/cwd is inside it or shares its repo,
#                         else the file/cwd's own git toplevel, else PWD
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

# _pd_first_existing_dir <path> — the nearest existing directory: <path>
# itself when it already is one, else dirname(<path>) and then dirname of
# that repeatedly (max 8 levels) until something exists. Prints nothing when
# nothing is found within that many steps. <path> need not exist yet — a
# PreToolUse hook fires before Write/Edit creates the file.
_pd_first_existing_dir() {
	local p=$1 i=0
	[ -z "$p" ] && return 0
	[ -d "$p" ] || p=$(dirname "$p")
	while [ "$i" -lt 8 ]; do
		[ -d "$p" ] && {
			printf '%s' "$p"
			return 0
		}
		case "$p" in "/" | ".") return 0 ;; esac
		p=$(dirname "$p")
		i=$((i + 1))
	done
}

# _pd_git_toplevel <path> — the git worktree toplevel containing <path> (or
# the nearest existing ancestor of it), or nothing when git is absent, the
# path can't be resolved to an existing ancestor, or it is not inside a
# work tree.
_pd_git_toplevel() {
	local d top
	d=$(_pd_first_existing_dir "$1")
	[ -z "$d" ] && return 0
	have git || return 0
	top=$(git -C "$d" rev-parse --show-toplevel 2>/dev/null) || return 0
	printf '%s' "$top"
}

# _pd_common_dir <dir> — <dir>'s `git rev-parse --git-common-dir`, normalised
# to an absolute, symlink-resolved path (git prints it relative to <dir>
# when the common dir sits inside it, e.g. plain ".git"). Prints nothing on
# any failure (not a repo, git absent, dir missing).
_pd_common_dir() {
	local dir=$1 cd_out
	cd_out=$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null) || return 0
	[ -z "$cd_out" ] && return 0
	case "$cd_out" in
	/*) : ;;
	*) cd_out="$dir/$cd_out" ;;
	esac
	(cd "$cd_out" 2>/dev/null && pwd -P)
}

# hook_project_dir — the project directory a hook should judge against.
# Candidate = tool_input.file_path (Edit/Write/NotebookEdit), else cwd (Bash
# calls carry no file_path); a relative candidate is resolved against the
# .cwd field when present, else $PWD — never against ".". When
# CLAUDE_PROJECT_DIR (base) is set and the candidate is base or under it, or
# when the candidate's git toplevel shares base's repo (same
# --git-common-dir, e.g. a worktree of it), base wins — one repo, no matter
# which worktree/subpath a hook happened to touch. A candidate outside
# base's repo (unrelated repo, or base unset) resolves to its own toplevel;
# no toplevel at all falls back to base, else $PWD. Memoised into
# $_PD_RESULT for the life of the process: later calls just print it. Any
# failure along the way (no git, not a repo, jq and python3 both absent)
# falls through to the next rule; this never prints an empty string and
# never writes to stderr.
# lesson(2026-09-05): hooks resolved the project from the session start dir, not the edited file
# lesson(2026-09-05): a nested repo, or an unrelated one, could hijack the project dir
hook_project_dir() {
	if [ "${_PD_DONE:-0}" = "1" ]; then
		printf '%s' "$_PD_RESULT"
		return 0
	fi
	local base cand cwd_field top common_t common_b
	base=${CLAUDE_PROJECT_DIR:-}
	cand=$(hook_field '.tool_input.file_path')
	[ -z "$cand" ] && cand=$(hook_field '.cwd')
	if [ -n "$cand" ]; then
		case "$cand" in
		/*) : ;;
		*)
			cwd_field=$(hook_field '.cwd')
			if [ -n "$cwd_field" ]; then
				cand="$cwd_field/$cand"
			else
				cand="$PWD/$cand"
			fi
			;;
		esac
	fi

	if [ -n "$base" ] && [ -n "$cand" ]; then
		case "$cand" in
		"$base" | "$base"/*)
			_PD_RESULT=$base
			_PD_DONE=1
			printf '%s' "$_PD_RESULT"
			return 0
			;;
		esac
	fi

	top=""
	[ -n "$cand" ] && top=$(_pd_git_toplevel "$cand")

	if [ -z "$top" ]; then
		if [ -n "$base" ]; then _PD_RESULT=$base; else _PD_RESULT=$PWD; fi
	elif [ -z "$base" ]; then
		_PD_RESULT=$top
	else
		common_t=$(_pd_common_dir "$top")
		common_b=$(_pd_common_dir "$base")
		if [ -n "$common_t" ] && [ "$common_t" = "$common_b" ]; then
			_PD_RESULT=$top
		else
			_PD_RESULT=$base
		fi
	fi

	_PD_DONE=1
	printf '%s' "$_PD_RESULT"
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

# _lesson_trailing_marker <reason> → rc 0 and sets _LESSON_DATE/_LESSON_WHAT
# when <reason> ends (trailing whitespace/newline tolerated) with a
# `[lesson(<YYYY-MM-DD>): <what>]` marker — the LAST such marker in the
# reason, so leading noise (including an earlier, malformed marker) never
# wins and a `]` inside <what> never truncates it. rc 1 (no globals set)
# when the reason does not end that way: no marker at all, a marker only
# mid-reason, a malformed date, or a <what> that is empty once tab/newline
# are stripped with tr -d '\t\n'.
_lesson_trailing_marker() {
	local reason=$1 trimmed body tail
	trimmed=$reason
	while :; do
		case "$trimmed" in
		*[[:space:]]) trimmed=${trimmed%?} ;;
		*) break ;;
		esac
	done
	case "$trimmed" in
	*"]") ;;
	*) return 1 ;;
	esac
	body=${trimmed%"]"}
	case "$body" in
	*"[lesson("*) ;;
	*) return 1 ;;
	esac
	tail=${body##*"[lesson("}
	case "$tail" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]"): "*) ;;
	*) return 1 ;;
	esac
	_LESSON_DATE=${tail:0:10}
	_LESSON_WHAT=${tail:13}
	_LESSON_WHAT=$(printf '%s' "$_LESSON_WHAT" | tr -d '\t\n')
	[ -z "$_LESSON_WHAT" ] && return 1
	return 0
}

# _lesson_fire <reason> → when <reason> ends with a marker (see
# _lesson_trailing_marker), append one fire line to
# $(hook_project_dir)/.claude/lesson-fires.log (mkdir -p; any failure
# swallowed). Grammar: <date>\t<what>\t<UTC ISO-8601 Z>\t<hook basename>.
_lesson_fire() {
	local reason=$1 target_dir
	_lesson_trailing_marker "$reason" || return 0
	target_dir="$(hook_project_dir)/.claude"
	{ mkdir -p "$target_dir"; } 2>/dev/null || return 0
	{ printf '%s\t%s\t%s\t%s\n' "$_LESSON_DATE" "$_LESSON_WHAT" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${0##*/}" >>"$target_dir/lesson-fires.log"; } 2>/dev/null || return 0
}

# _lesson_nudge <reason> → <reason>, plus a "/lesson" line when the same
# hook has produced the same first line of reason before in this session.
# The second identical deny/block/feedback is the deterministic "same
# mistake twice" signal: the fix is a guardrail, not another retry. Counter
# lives in ${TMPDIR:-/tmp}/claude-lesson-<session>; failures fall through
# to the unchanged reason. Reasons that already mention /lesson are left
# alone (stop-gate adds its own wording).
#
# A reason that ENDS with a marker `[lesson(<YYYY-MM-DD>): <what>]` (see
# _lesson_trailing_marker; the last marker wins, trailing whitespace is
# tolerated) is a lesson firing again: append one fire line to
# `.claude/lesson-fires.log` (mkdir -p; any failure swallowed) and return
# the reason unchanged — no nudge text, no signature file write. A marker
# that only appears mid-reason (e.g. echoed file content that happens to
# contain the marker literal) is treated as a plain reason: normal counter
# and nudge behaviour below.
_lesson_nudge() {
	local reason=$1 sid tmp f sig n
	case "$reason" in
	*"/lesson"*)
		printf '%s' "$reason"
		return 0
		;;
	esac
	if _lesson_trailing_marker "$reason"; then
		_lesson_fire "$reason"
		printf '%s' "$reason"
		return 0
	fi
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
