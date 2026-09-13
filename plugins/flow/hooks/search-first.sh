#!/usr/bin/env bash
# search-first.sh — UserPromptSubmit hook.
#
# A prompt that asks to add/implement/create/introduce a new symbol (a
# property, field, method, function, helper, endpoint, route, class or
# attribute) gets one line of model-facing context: search the repo before
# writing new code. Slash commands have their own skill for this and are
# left alone.
#
# Matching is done on whole words, in order (verb, then somewhere later a
# noun) — the same thing the spec's \b...\b regex means, but without \b
# itself: word-boundary support is inconsistent between GNU and BSD grep,
# and a character-consuming stand-in (e.g. [^A-Za-z]) breaks on the common
# one-space case ("add property") because it eats the very separator the
# following boundary needs to see. Splitting the prompt into lowercase
# tokens with tr and walking them with awk avoids both problems and reads
# more literally as "a verb token, then later a noun token".
#
# Escape hatches: CC_SEARCH_FIRST=0 for one command (or any other value to
# force it on regardless of config — env wins outright once set), else
# `searchFirst: false` in .claude/flow.config.json, else on by default —
# the same env > config > default precedence size-guard.sh uses for
# sizeGuard, just decided in one place instead of two.
#
# Never fails the prompt: any internal error (no jq/python3, malformed
# stdin, an empty prompt, ...) falls through to hook_ok.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off

if [ -n "${CC_SEARCH_FIRST:-}" ]; then
	[ "$CC_SEARCH_FIRST" = "0" ] && hook_ok
elif [ "$(hook_config searchFirst)" = "false" ]; then
	hook_ok
fi

prompt=$(hook_field '.prompt')
[ -z "$prompt" ] && hook_ok

# Slash commands (their own skill covers this) — leading whitespace is
# stripped first so "  /flow:next" is still recognised as one.
_sf_trimmed=${prompt#"${prompt%%[![:space:]]*}"}
case "$_sf_trimmed" in
/*) hook_ok ;;
esac

_sf_hit=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '\n' | awk '
	BEGIN { verb = 0 }
	!verb && ($0 == "add" || $0 == "implement" || $0 == "create" || $0 == "introduce") { verb = 1; next }
	verb && ($0 == "property" || $0 == "field" || $0 == "method" || $0 == "function" || \
		$0 == "helper" || $0 == "endpoint" || $0 == "route" || $0 == "class" || $0 == "attribute") {
		print "1"
		exit
	}
')
[ "$_sf_hit" = "1" ] || hook_ok

_sf_msg="Before adding code: search the whole repo for an existing implementation (the verb, two synonyms, the library you'd import, the error string; look in utils/support/helpers/lib), reuse it, and state one receipt line: searched: <terms>; found: <path:line | nothing>."

printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$(_json_str "$_sf_msg")"
