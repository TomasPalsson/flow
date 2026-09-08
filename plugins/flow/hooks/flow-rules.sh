#!/usr/bin/env bash
# flow-rules.sh — PreToolUse / PostToolUse / Stop. Spec 005, D-4 and D-5.
#
# The rule engine behind `/lesson`. A locked lesson is DATA — a file at
# .claude/flow.rules/<slug>.md with hookify-shaped frontmatter — so locking one
# in never edits hooks.json, never needs `flow doctor`, never needs a restart.
# This one hook reads them all.
#
# The overwhelmingly common case is a project with no rules at all. Nothing
# below parses the payload, and nothing spawns jq or python3, until a rule file
# has actually been found: the directory tests in the walk-up are the entire
# cost of a project that has never run /lesson.
#
# Fail open, always. An unreadable or malformed rule file is skipped and named
# in a note; it never denies. A hook that bricks the tool call because its own
# config is broken is worse than no hook.
set -u
export LC_ALL=C
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off # `flow off` here or above silences every rule

FR_SEEN="|"  # slugs already claimed, |-fenced: the nearest store wins
FR_BAD=""    # rule files that could not be parsed, reported at the end
FR_CTX=0     # 1 once the payload's event/tool have been read
FR_SUBJ=""   # what the pattern matches against
FR_SUBJ_READY=0

# fr_trim <text> → FR_T, without surrounding blanks. Quotes are NOT stripped
# here: `pattern` is an ERE stored raw (D-4), and an ERE that begins and ends
# with a literal `"` — what `flow lesson propose` drafts whenever the --input
# text is itself quoted — would otherwise be enforced two characters shorter
# than the rule on disk and the rule the user was shown.
fr_trim() {
	FR_T=$1
	while :; do case "$FR_T" in [[:blank:]]*) FR_T=${FR_T#?} ;; *) break ;; esac; done
	while :; do case "$FR_T" in *[[:blank:]]) FR_T=${FR_T%?} ;; *) break ;; esac; done
}

# fr_unquote → FR_T without one layer of surrounding double quotes. Only for
# values YAML has to quote to keep them scalars: `tool: "*"` and `tool: *`
# mean the same tool.
fr_unquote() {
	case "$FR_T" in '"'*'"')
		FR_T=${FR_T#\"}
		FR_T=${FR_T%\"}
		;;
	esac
}

# fr_parse <file> — flat `key: value` frontmatter between two --- fences into
# FR_EV/FR_TL/FR_PAT/FR_ACT/FR_EN, the rest of the file into FR_BODY. `hits` is
# deliberately not kept: fr_hit re-reads it under a lock, because a count read
# out here is already stale by the time the rewrite lands. An unknown key is
# ignored, not an error. rc 1 = unreadable, unfenced, or missing event/action:
# malformed, and the caller skips it.
fr_parse() {
	local line key state=0
	FR_EV=""
	FR_TL=""
	FR_PAT=""
	FR_ACT=""
	FR_EN=""
	FR_BODY=""
	[ -r "$1" ] || return 1
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "$state" = 0 ]; then
			[ "$line" = "---" ] || return 1
			state=1
			continue
		fi
		if [ "$state" = 1 ]; then
			if [ "$line" = "---" ]; then
				state=2
				continue
			fi
			case "$line" in *:*) : ;; *) continue ;; esac
			fr_trim "${line%%:*}"
			key=$FR_T
			fr_trim "${line#*:}"
			case "$key" in
			event) FR_EV=$FR_T ;;
			tool)
				fr_unquote
				FR_TL=$FR_T
				;;
			pattern) FR_PAT=$FR_T ;;
			action) FR_ACT=$FR_T ;;
			enabled) FR_EN=$FR_T ;;
			esac
			continue
		fi
		if [ -z "$FR_BODY" ]; then FR_BODY=$line; else FR_BODY="$FR_BODY
$line"; fi
	done <"$1"
	[ "$state" = 2 ] || return 1
	[ -n "$FR_EV" ] && [ -n "$FR_ACT" ] || return 1
	case "$FR_ACT" in deny | warn | note) ;; *) return 1 ;; esac
	return 0
}

# fr_lock <dir> — rc 0 with <dir>/.hits.lock held, to be released by fr_unlock.
# A store nobody can write to has no lock to wait for — testing the dir, not the
# failed mkdir, is what keeps this honest: a holder that releases between our
# mkdir and a `[ -d $lock ]` test would look exactly like an unwritable store
# and we would carry on unlocked. A live holder keeps the lock for four forks,
# so the wait is milliseconds; the budget is deliberately patient because giving
# up early is exactly the lost count this lock exists to prevent — on a loaded
# machine eight parallel fires blew a half-second budget and landed 5 of 8. Only
# a lock with no readable pid can burn the whole budget, and that needs a hook
# killed inside the one write between its mkdir and its pid file.
fr_lock() {
	local lock=$1/.hits.lock tries=0 holder
	while [ -w "$1" ]; do
		if mkdir "$lock" 2>/dev/null; then
			printf '%s\n' "$$" 2>/dev/null >"$lock/pid"
			return 0
		fi
		holder=$(cat "$lock/pid" 2>/dev/null)
		# A hook killed mid-write leaves a lock nobody will ever release, and a
		# patient waiter would then pay the whole budget on every later fire. An
		# empty pid is the winner's own window between its mkdir and its write,
		# so only a pid whose process is gone counts as stale. Move that lock
		# aside before deleting it: mv is atomic, so one waiter breaks a given
		# stale lock and the rest go straight back to racing for a fresh one.
		case "$holder" in
		'' | *[!0-9]*) : ;;
		*)
			if ! kill -0 "$holder" 2>/dev/null && mv "$lock" "$lock.$$" 2>/dev/null; then
				rm -f "$lock.$$/pid" 2>/dev/null
				rmdir "$lock.$$" 2>/dev/null
			fi
			;;
		esac
		tries=$((tries + 1))
		[ "$tries" -ge 500 ] && break
		sleep 0.02 2>/dev/null
	done
	return 1
}
fr_unlock() {
	rm -f "$1/.hits.lock/pid" 2>/dev/null
	rmdir "$1/.hits.lock" 2>/dev/null
	return 0
}

# fr_hit <file> — charge the rule one hit. `hits` is a read-modify-write, so the
# whole of it runs under the store's lock (mkdir is atomic on every POSIX
# filesystem — the lock lesson-record takes for PROGRESS.md): parallel tool calls
# in one turn fire the same rule at the same time, and unlocked they all read the
# same count and every increment but one is lost. awk re-reads the count from the
# file for the same reason. The rewrite is atomic (a temp file beside the rule,
# then mv) because a half-written rule file is a rule that stops working.
#
# Every failure here is swallowed, and `2>/dev/null` leads each redirection
# because the shell reports a failed *open* on the stderr it had before the
# redirection list ran: a trailing `2>/dev/null` would let a read-only store
# splice a permission error into the correction the model is meant to read.
# Bookkeeping never changes the decision the caller is about to emit, and never
# speaks over its message.
fr_hit() {
	local f=$1 dir slug tmp held=0
	dir=${f%/*}
	slug=${f##*/}
	slug=${slug%.md}
	fr_lock "$dir" && held=1
	if tmp=$(mktemp "$dir/.flow-rules.XXXXXX" 2>/dev/null); then
		cp -p "$f" "$tmp" 2>/dev/null || true # inherit the rule file's mode, not mktemp's 600
		if awk '
			NR == 1 && $0 == "---" { fm = 1; print; next }
			fm == 1 && $0 == "---" { if (!seen) print "hits: 1"; fm = 0; print; next }
			fm == 1 && !seen && /^[[:space:]]*hits[[:space:]]*:/ {
				cur = $0
				sub(/^[^:]*:[[:space:]]*/, "", cur)
				sub(/[[:space:]]*$/, "", cur)
				print "hits: " (cur ~ /^[0-9]+$/ ? cur + 1 : 1)
				seen = 1
				next
			}
			{ print }
		' "$f" 2>/dev/null >"$tmp" && [ -s "$tmp" ]; then
			mv -f "$tmp" "$f" 2>/dev/null || rm -f "$tmp"
		else
			rm -f "$tmp"
		fi
	fi
	printf '%s %s %s %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$slug" "$FR_EVENT" "$FR_TOOL" \
		2>/dev/null >>"$dir/.hits.log" || true
	[ "$held" = 1 ] && fr_unlock "$dir"
	return 0
}

# fr_fire <file> — record the hit, then take the action and leave. Degradation
# (D-5 step 5): `deny` has no channel outside PreToolUse, so elsewhere it acts
# as `warn`; `warn` on PreToolUse has no correction channel — stderr there is a
# hook error, not feedback — so it becomes a note.
fr_fire() {
	local act=$FR_ACT
	fr_hit "$1"
	[ "$act" = deny ] && [ "$FR_EVENT" = PreToolUse ] && hook_deny "$FR_BODY"
	[ "$act" = deny ] && act=warn
	if [ "$act" = warn ]; then
		case "$FR_EVENT" in
		Stop) hook_block "$FR_BODY" ;;
		PreToolUse) hook_note "$FR_BODY" ;;
		*) hook_feedback "$FR_BODY" ;;
		esac
	fi
	hook_note "$FR_BODY"
}

# The payload, read once and only once a rule exists to judge with it.
fr_ctx() {
	[ "$FR_CTX" = 1 ] && return 0
	FR_CTX=1
	FR_EVENT=$(hook_field '.hook_event_name')
	FR_TOOL=$(hook_field '.tool_name')
}
fr_subject() {
	[ "$FR_SUBJ_READY" = 1 ] && return 0
	FR_SUBJ_READY=1
	FR_SUBJ=$(hook_field '.tool_input.command')
	[ -n "$FR_SUBJ" ] || FR_SUBJ=$(hook_field '.tool_input.file_path')
}

# fr_eval <file> — judge one rule; fr_fire never returns.
fr_eval() {
	fr_ctx
	if ! fr_parse "$1"; then
		FR_BAD="$FR_BAD $1"
		return 0
	fi
	[ "$FR_EN" = true ] || return 0
	[ "$FR_EV" = "$FR_EVENT" ] || return 0
	[ "$FR_TL" = "*" ] || [ "$FR_TL" = "$FR_TOOL" ] || return 0
	# An empty or "*" pattern is event+tool only — the normal shape of a Stop
	# rule, which has no tool_input to match against.
	case "$FR_PAT" in '' | '*') fr_fire "$1" ;; esac
	fr_subject
	# grep, not case: `pattern` is an ERE. An unparseable one matches nothing.
	printf '%s' "$FR_SUBJ" | grep -Eq -e "$FR_PAT" 2>/dev/null && fr_fire "$1"
	return 0
}

# fr_store <dir> — every rule in one store, in name order. A slug already
# claimed by a nearer store is skipped whole, which is how a project rule beats
# the global rule of the same name (D-5 step 3).
fr_store() {
	local f b
	for f in "$1"/*.md; do
		[ -f "$f" ] || continue
		b=${f##*/}
		b=${b%.md}
		case "$FR_SEEN" in *"|$b|"*) continue ;; esac
		FR_SEEN="$FR_SEEN$b|"
		fr_eval "$f"
	done
}

# Project stores first, nearest first, up to the git toplevel (a .git entry) or
# the filesystem root; then the global store.
fr_dir=$(hook_project_dir)
while :; do
	[ -d "$fr_dir/.claude/flow.rules" ] && fr_store "$fr_dir/.claude/flow.rules"
	[ -e "$fr_dir/.git" ] && break
	case "$fr_dir" in
	*/?*)
		fr_dir=${fr_dir%/*}
		[ -z "$fr_dir" ] && fr_dir="/"
		;;
	*) break ;;
	esac
done
if [ -n "${HOME:-}" ] && [ -d "$HOME/.claude/flow.rules" ]; then
	fr_store "$HOME/.claude/flow.rules"
fi

# Nothing fired. Say so only if a rule file was broken, and only once per
# session per set of broken files — a nag every tool call is its own bug.
if [ -n "$FR_BAD" ] && hook_once "flow-rules-bad$FR_BAD"; then
	hook_note "flow: rule file skipped, malformed frontmatter:$FR_BAD
Every other rule still applies. Fix the frontmatter (event/action are required, between two --- lines) or delete the file."
fi
hook_ok
