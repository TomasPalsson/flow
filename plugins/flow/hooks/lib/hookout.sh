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
#   hook_project_dir      the project dir: CLAUDE_PROJECT_DIR (physical) when
#                         the edited file/cwd is inside it or shares its repo,
#                         else the file/cwd's own git toplevel, else PWD
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
	local raw base cand cwd_field top common_t common_b
	raw=${CLAUDE_PROJECT_DIR:-}
	base=$raw
	[ -n "$base" ] && base=$(cd "$base" 2>/dev/null && pwd -P || printf '%s' "$base")
	_hook_input_fields
	cand=$_HI_FILE
	[ -z "$cand" ] && cand=$_HI_CWD
	if [ -n "$cand" ]; then
		case "$cand" in
		/*) : ;;
		*)
			cwd_field=$_HI_CWD
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
		"$base" | "$base"/* | "$raw" | "$raw"/*)
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
		if [ -n "$base" ]; then _PD_RESULT=$base; else _PD_RESULT=$(pwd -P); fi
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

_hook_tmp() {
	local t
	t="${TMPDIR:-/tmp}"
	printf '%s' "${t%/}"
}

# The session id, sanitised for a file name (cached: HOOK_INPUT is read once).
# The three input fields hooks locate themselves by, parsed with ONE jq per
# process (the perf budget in test_hookout.sh counts them) and cached; the
# eager call at the bottom of this file fills the cache in the parent so
# $(hook_project_dir) and $(hook_stamp_path) subshells never re-parse.
_hook_input_fields() {
	[ "${_HI_DONE:-0}" = "1" ] && return 0
	_HI_SID=""
	_HI_FILE=""
	_HI_CWD=""
	if [ -n "$HOOK_INPUT" ] && have jq; then
		{
			IFS= read -r _HI_SID
			IFS= read -r _HI_FILE
			IFS= read -r _HI_CWD
		} <<EOF
$(printf '%s' "$HOOK_INPUT" | jq -r '(.session_id // ""), (.tool_input.file_path // ""), (.cwd // "")' 2>/dev/null)
EOF
	elif [ -n "$HOOK_INPUT" ]; then
		_HI_SID=$(hook_field '.session_id')
		_HI_FILE=$(hook_field '.tool_input.file_path')
		_HI_CWD=$(hook_field '.cwd')
	fi
	_HI_DONE=1
}

_hook_sid() {
	if [ -z "${_HOOK_SID:-}" ]; then
		_hook_input_fields
		_HOOK_SID=$_HI_SID
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

# Resolve the input fields and the project dir once, here in the parent, so
# every later $(...) call is a cache hit (see _hook_input_fields).
_hook_input_fields
hook_project_dir >/dev/null
