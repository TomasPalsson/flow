#!/usr/bin/env bash
# context-pressure.sh — PreToolUse hook.
#
# Warns once per 60k-token bucket that the context window is filling, so the
# model wraps up the current step and records where it left off before
# /compact or /clear loses the thread mid-task.
#
# The window is read from the session transcript's last usage-bearing
# record: only the newest 262144 bytes are scanned (a file that small is
# read whole), and the tail's first line is dropped when the file is bigger
# than that — a byte-offset tail almost certainly lands mid-line. tokens =
# input_tokens + cache_read_input_tokens + cache_creation_input_tokens, the
# same three fields that partition a turn's prompt. The window is 1M once
# tokens already exceed the 200k default, the model id carries the "[1m]"
# marker, or it is a known large-window family (claude-opus-5,
# claude-fable-5); otherwise 200k. A state file remembers the last fired
# "<window>:<bucket>" per session so the same bucket never repeats, and a
# window change (a 200k session growing past 200k) always re-arms it.
#
# Never blocks and never writes anything else to stdout: a missing/unreadable
# transcript, no jq, no usable usage record, or a below-threshold session all
# fall through to hook_ok.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off

# _cp_known_family <model> <family> — true when <family> (e.g. claude-opus-5)
# appears in <model> immediately followed by end-of-string, a delimiter ([, :,
# .) or a "-<digit>" date suffix — never a bare alnum continuation or a
# letter suffix (claude-opus-5-mini is a different, possibly smaller model).
_cp_known_family() {
	local model=$1 family=$2 rest
	case "$model" in
	*"$family"*) : ;;
	*) return 1 ;;
	esac
	rest=${model#*"$family"}
	case "$rest" in
	'' | '['* | ':'* | '.'* | -[0-9]*) return 0 ;;
	*) return 1 ;;
	esac
}

_cp_transcript=$(hook_field '.transcript_path')
[ -r "$_cp_transcript" ] || hook_ok

_cp_size=$(wc -c <"$_cp_transcript" 2>/dev/null | tr -d '[:space:]')
case "$_cp_size" in '' | *[!0-9]*) hook_ok ;; esac

# tokens and model, tab-joined, one output line per matching record. The
# byte-tail (and, when truncated, its dropped partial first line) stay in
# the pipe between tail and jq instead of a bash variable — capturing
# 256KiB into a variable and printf-ing it back out for jq costs far more
# than jq spends parsing it. jq recovers after a malformed line and keeps
# emitting valid ones, so a broken trailing record naturally falls back to
# an earlier line; the LAST output line is the most recent match.
_cp_jq_usage='
	select(.message.usage != null) |
	[((.message.usage.input_tokens // 0) + (.message.usage.cache_read_input_tokens // 0) + (.message.usage.cache_creation_input_tokens // 0)), (.message.model // "")] | @tsv
'
if [ "$_cp_size" -gt 262144 ]; then
	_cp_lines=$(tail -c 262144 "$_cp_transcript" 2>/dev/null | tail -n +2 | jq -r "$_cp_jq_usage" 2>/dev/null)
else
	_cp_lines=$(tail -c 262144 "$_cp_transcript" 2>/dev/null | jq -r "$_cp_jq_usage" 2>/dev/null)
fi
[ -z "$_cp_lines" ] && hook_ok
_cp_line=${_cp_lines##*$'\n'}

_cp_tokens=${_cp_line%%$'\t'*}
_cp_model=${_cp_line#*$'\t'}
case "$_cp_tokens" in '' | *[!0-9]*) hook_ok ;; esac

_cp_window=200000
[ "$_cp_tokens" -gt 200000 ] && _cp_window=1000000
case "$_cp_model" in
*'[1m]'*) _cp_window=1000000 ;;
esac
if _cp_known_family "$_cp_model" claude-opus-5 || _cp_known_family "$_cp_model" claude-fable-5; then
	_cp_window=1000000
fi

_cp_threshold=160000
[ "$_cp_window" -eq 1000000 ] && _cp_threshold=250000

_cp_bucket=-1
[ "$_cp_tokens" -ge "$_cp_threshold" ] && _cp_bucket=$(((_cp_tokens - _cp_threshold) / 60000))
[ "$_cp_bucket" -lt 0 ] && hook_ok

_cp_state_file="$(_hook_tmp)/claude-context-$(_hook_sid)"
_cp_previous=""
[ -f "$_cp_state_file" ] && IFS= read -r _cp_previous <"$_cp_state_file" 2>/dev/null
_cp_previous_window=${_cp_previous%%:*}
_cp_previous_bucket=${_cp_previous#*:}
case "$_cp_previous_bucket" in '' | *[!0-9]*) _cp_previous_bucket=-1 ;; esac

if [ "$_cp_window" = "$_cp_previous_window" ] && [ "$_cp_bucket" -le "$_cp_previous_bucket" ]; then
	hook_ok
fi
printf '%s:%s\n' "$_cp_window" "$_cp_bucket" >"$_cp_state_file" 2>/dev/null

_cp_msg="flow: context is ~$((_cp_tokens / 1000))k tokens of a ~$((_cp_window / 1000))k window. Finish the current step, make sure TASKS.md / PROGRESS.md say where you are, then /compact — or /clear and /flow:next."

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":%s}}\n' "$(_json_str "$_cp_msg")"
