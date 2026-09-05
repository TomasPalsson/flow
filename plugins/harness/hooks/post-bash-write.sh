#!/usr/bin/env bash
# post-bash-write.sh — PostToolUse/Bash hook (C19).
#
# Auto mode is instructed to read/edit files through Bash (cat, sed,
# heredocs), so the Edit|Write|NotebookEdit-matched hooks (format-lint,
# size-guard, tamper-notice) never fire for those writes. This hook closes
# that gap deterministically: when the just-run Bash command looks like it
# wrote something, it finds every file under the project dir newer than the
# tool-stamp.sh timestamp (PreToolUse/Bash) and re-runs the three
# PostToolUse/Edit hooks against each one by piping them synthesized JSON —
# it never reimplements their logic, only invokes the sibling scripts.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

[ "${CC_NO_POST_BASH_WRITE:-}" = "1" ] && hook_ok

cmd=$(hook_field '.tool_input.command')
[ -z "$cmd" ] && hook_ok

# A permissive write-indicator scan: false positives only cost a `find`.
printf '%s' "$cmd" | grep -Eq '>|tee|sed[[:space:]]+-i|<<|mv[[:space:]]|cp[[:space:]]|python|node|perl' || hook_ok

stamp="$(hook_stamp_path)-tool"
[ -f "$stamp" ] || hook_ok

dir=$(hook_project_dir)
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

# _pbw_json_str <text> — a JSON string literal (with quotes), escaped.
# Mirrors hookout.sh's own escaping strategy (jq, then python3, then a
# hand-rolled fallback) without depending on its private helper.
_pbw_json_str() {
	if have jq; then
		printf '%s' "$1" | jq -Rs . 2>/dev/null && return 0
	fi
	if have python3; then
		printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null && return 0
	fi
	printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

sid=$(hook_field '.session_id')

_pbw_cd=$(cd "$dir" 2>/dev/null && pwd -P) || hook_ok
dir="$_pbw_cd"

# List files changed since the tool stamp, pruning noisy/irrelevant trees
# (BSD- and GNU-safe: -path/-prune/-o, never -newermt). NOTE: .claude/ itself
# is deliberately NOT pruned — gate-config files such as .claude/harness.json
# live there and tamper-notice.sh (C10) must see edits to them; pruning the
# whole tree silently defeated that (C19 fatal finding). Only the well-known
# noise trees are excluded.
_pbw_all=$(cd "$dir" && find . \( \
	-path '*/.git' -o \
	-path '*/node_modules' -o \
	-path '*/.venv' -o \
	-path '*/target' -o \
	-path '*/dist' -o \
	-path '*/build' -o \
	-path '*/__pycache__' \
	\) -prune -o -type f -newer "$stamp" -print 2>/dev/null)

[ -z "$_pbw_all" ] && hook_ok

# Drop gitignored files: they are runtime state (container logs, caches,
# databases) that background processes keep rewriting, not something the
# command authored — a live *arr stack blocked every read-only command with
# "logs/x.txt is 8000 lines" until this filter existed. .claude/ is exempt
# because it is commonly gitignored yet holds the gate config tamper-notice.sh
# must keep seeing (C19).
#
# Fail closed when the command also touched an ignore file: `echo x >>
# .gitignore; cat > x` would otherwise hide x from every gate with one extra
# token (adversary finding, 2026-09-05). core.quotePath=false so check-ignore
# echoes non-ASCII names verbatim and the exact-line match below still holds.
_pbw_ignored=""
if ! printf '%s\n' "$_pbw_all" | grep -Eq '(^|/)\.gitignore$|^\./\.git/info/exclude$'; then
	_pbw_ignored=$(printf '%s\n' "$_pbw_all" | git -C "$dir" -c core.quotePath=false check-ignore --stdin 2>/dev/null)
fi
if [ -n "$_pbw_ignored" ]; then
	_pbw_keep=""
	while IFS= read -r f; do
		[ -z "$f" ] && continue
		case "$f" in
		./.claude/*) _pbw_keep="$_pbw_keep
$f" ;;
		*)
			if ! printf '%s\n' "$_pbw_ignored" | grep -Fxq -- "$f"; then
				_pbw_keep="$_pbw_keep
$f"
			fi
			;;
		esac
	done <<EOF
$_pbw_all
EOF
	_pbw_all=$(printf '%s\n' "$_pbw_keep" | grep .)
	[ -z "$_pbw_all" ] && hook_ok
fi

_pbw_total=$(printf '%s\n' "$_pbw_all" | grep -c .)
_pbw_list="$_pbw_all"
if [ "$_pbw_total" -gt 50 ]; then
	_pbw_list=$(printf '%s\n' "$_pbw_all" | head -50)
	hook_log "post-bash-write: capped changed-file list at 50 (of $_pbw_total touched)"
fi

_pbw_n=0
_pbw_failed=0
_pbw_out=""

while IFS= read -r f; do
	[ -z "$f" ] && continue
	_pbw_n=$((_pbw_n + 1))
	_pbw_rel="${f#./}"
	_pbw_abs="$dir/$_pbw_rel"
	_pbw_json=$(printf '{"session_id":%s,"tool_input":{"file_path":%s}}' \
		"$(_pbw_json_str "$sid")" "$(_pbw_json_str "$_pbw_abs")")

	for _pbw_hook in format-lint.sh size-guard.sh tamper-notice.sh; do
		_pbw_errf=$(mktemp "${TMPDIR:-/tmp}/pbw-err.XXXXXX")
		printf '%s' "$_pbw_json" | CLAUDE_PROJECT_DIR="$dir" bash "$HERE/$_pbw_hook" >/dev/null 2>"$_pbw_errf"
		_pbw_rc=$?
		_pbw_e=$(cat "$_pbw_errf" 2>/dev/null)
		rm -f "$_pbw_errf"
		if [ "$_pbw_rc" -eq 2 ]; then
			_pbw_failed=1
			if [ -n "$_pbw_e" ]; then
				_pbw_out="$_pbw_out
$_pbw_e"
			fi
		fi
	done
done <<EOF
$_pbw_list
EOF

if [ "$_pbw_failed" -eq 1 ]; then
	hook_feedback "post-bash-write: $_pbw_n file(s) changed by that command
$_pbw_out"
fi

hook_ok
