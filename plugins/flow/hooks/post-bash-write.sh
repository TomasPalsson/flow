#!/usr/bin/env bash
# post-bash-write.sh — PostToolUse/Bash hook (C19, spec 003 G3/B2/FU-02).
#
# Auto mode reads/edits files through Bash (cat, sed, heredocs), so the
# Edit|Write|NotebookEdit-matched hooks never fire for those writes. This
# hook closes the gap: when the just-run Bash command actually wrote
# something, it finds every file both newer than the tool-stamp and dirty in
# git and re-runs size-guard.sh + tamper-notice.sh against each, piping them
# synthesized JSON — never reimplementing their logic. format-lint never runs
# from here (formatting a file not touched via Edit is surprising).
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
# shellcheck source=lib/bashwrite.sh
. "$HERE/lib/bashwrite.sh" # _pbw_strip_heredocs / _pbw_is_writer (G3(1))
hook_skip_if_off           # `flow off` wrote .claude/flow.off here: no judging hooks

[ "${CC_NO_POST_BASH_WRITE:-}" = "1" ] && hook_ok

cmd=$(hook_field '.tool_input.command')
[ -z "$cmd" ] && hook_ok

# _pbw_json_str <text> — a JSON string literal (with quotes), escaped.
# Mirrors hookout.sh's escaping strategy (jq, python3, hand-rolled fallback).
_pbw_json_str() {
	if have jq; then
		printf '%s' "$1" | jq -Rs . 2>/dev/null && return 0
	fi
	if have python3; then
		printf '%s' "$1" | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))' 2>/dev/null && return 0
	fi
	printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
}

_pbw_stripped=$(_pbw_strip_heredocs "$cmd")
_pbw_is_writer "$_pbw_stripped" || hook_ok

stamp="$(hook_stamp_path)-tool"
[ -f "$stamp" ] || hook_ok

dir=$(hook_project_dir)
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

sid=$(hook_field '.session_id')

# What changed (pruned, ignore-filtered, turn-scoped gitignore rule): C-A.
_pbw_changed=$(hook_changed_since "$stamp")
[ -z "$_pbw_changed" ] && hook_ok

# What git considers dirty: tracked-and-modified or untracked (--ignored=
# matching also surfaces a file that became ignored THIS turn; hook_changed_since
# already decided whether that exemption is voided, this list only needs to
# not be narrower). `git status --porcelain` paths are relative to the git
# TOPLEVEL, never to the `-C` directory, and CLAUDE_PROJECT_DIR need not BE
# the toplevel (`cd repo/backend && claude`), so join onto the toplevel.
_pbw_top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -n "$_pbw_top" ] || _pbw_top=$dir
# `-z`, not the default format: git C-quotes any path holding a `"`, a
# backslash or a newline even under core.quotePath=false, and stripping the
# outer quotes without un-escaping left `a"b.py` unmatchable against
# hook_changed_since's raw path — its write was missed (fix-round finding).
# `-z` emits paths verbatim; `tr` then makes them lines (a path containing a
# newline is unrepresentable in this hook's line-based intersection either
# way). Under `-z` a rename is `XY <to>` followed by a bare `<from>` record,
# so the record after an R/C status is skipped. Single streaming awk pass,
# never a per-line bash string append: a glob ignore (`*.log`) does not
# collapse under --ignored=matching the way a directory ignore does, and
# growing $_pbw_dirty one line at a time was O(n^2) — seconds of hang on a
# repo with a few thousand such files.
_pbw_dirty=$(git -C "$dir" status --porcelain -uall --ignored=matching -z 2>/dev/null | tr '\0' '\n' | awk -v top="$_pbw_top" '
	{
		if (skip) { skip = 0; next }
		if (length($0) < 4) next
		x = substr($0, 1, 1); y = substr($0, 2, 1)
		if (x == "R" || x == "C" || y == "R" || y == "C") skip = 1
		print top "/" substr($0, 4)
	}
')
_pbw_dirty_f=$(mktemp "${TMPDIR:-/tmp}/pbw-dirty.XXXXXX")
printf '%s\n' "$_pbw_dirty" >"$_pbw_dirty_f"

# The frozen candidate set (spec G3(2)): hook_changed_since ∩ git-dirty. A
# single `grep -Fxf` pass, not a per-line `grep -Fxq` in a while-read loop
# (same O(n^2) class as the dirty-set build above).
_pbw_candidates=$(printf '%s\n' "$_pbw_changed" | grep -Fxf "$_pbw_dirty_f" 2>/dev/null | grep .)
rm -f "$_pbw_dirty_f"

# .claude/ gate-config carve-out (C19 fatal finding), kept SEPARATE from the
# frozen intersection above: a whole-directory ignore (`.claude/`) collapses
# git status to one "!! .claude/" line, so a gate-config file under it can
# never appear in the per-file dirty set (nor in hook_changed_since), and
# gets its own message claiming only what's provable ("changed since this
# command started"), never "dirty in git". The `-name` filter below is
# narrowed to the exact basenames tamper-notice.sh's `_is_gate_config`
# recognises, so that claim is provable from this hook's own state, not just
# safe because a downstream hook happens to re-filter it. `.claude/skills/`
# is vendored content, not gate config, and stays excluded.
_pbw_claude_dir="$dir/.claude"
_pbw_claude_extra=""
if [ -d "$_pbw_claude_dir" ]; then
	_pbw_cprune=('(' -path "$_pbw_claude_dir/skills")
	while IFS= read -r _pbw_pd; do
		[ -z "$_pbw_pd" ] && continue
		_pbw_cprune=("${_pbw_cprune[@]}" -o -name "$_pbw_pd")
	done <<PBWPDEOF
$(hook_prune_dirs)
PBWPDEOF
	_pbw_cprune=("${_pbw_cprune[@]}" ')')
	_pbw_claude_extra=$(find "$_pbw_claude_dir" -mindepth 1 "${_pbw_cprune[@]}" -prune -o -type f \( \
		-name 'flow.config.json' -o -name 'eslint.config.*' -o -name '.eslintrc*' -o \
		-name 'pyproject.toml' -o -name 'ruff.toml' -o -name 'clippy.toml' -o -name '.golangci.yml' \
		\) -newer "$stamp" -print 2>/dev/null)
	if [ -n "$_pbw_claude_extra" ]; then
		_pbw_cand_f=$(mktemp "${TMPDIR:-/tmp}/pbw-cand.XXXXXX")
		printf '%s\n' "$_pbw_candidates" >"$_pbw_cand_f"
		_pbw_claude_extra=$(printf '%s\n' "$_pbw_claude_extra" | grep -Fxvf "$_pbw_cand_f" 2>/dev/null | grep .)
		rm -f "$_pbw_cand_f"
	fi
fi

_pbw_all=$(printf '%s\n%s\n' "$_pbw_candidates" "$_pbw_claude_extra" | grep .)
[ -z "$_pbw_all" ] && hook_ok

_pbw_total=$(printf '%s\n' "$_pbw_all" | grep -c .)
_pbw_list="$_pbw_all"
_pbw_capped=0
if [ "$_pbw_total" -gt 50 ]; then
	_pbw_list=$(printf '%s\n' "$_pbw_all" | head -50)
	_pbw_capped=1
	hook_log "post-bash-write: capped changed-file list at 50 (of $_pbw_total touched)"
fi

_pbw_n_normal=0
_pbw_n_claude=0
_pbw_failed_normal=0
_pbw_failed_claude=0
_pbw_out_normal=""
_pbw_out_claude=""

while IFS= read -r f; do
	[ -z "$f" ] && continue
	_pbw_group=normal
	printf '%s\n' "$_pbw_claude_extra" | grep -Fxq -- "$f" && _pbw_group=claude
	if [ "$_pbw_group" = claude ]; then
		_pbw_n_claude=$((_pbw_n_claude + 1))
	else
		_pbw_n_normal=$((_pbw_n_normal + 1))
	fi
	_pbw_json=$(printf '{"session_id":%s,"tool_input":{"file_path":%s}}' \
		"$(_pbw_json_str "$sid")" "$(_pbw_json_str "$f")")

	for _pbw_hook in size-guard.sh tamper-notice.sh; do
		_pbw_errf=$(mktemp "${TMPDIR:-/tmp}/pbw-err.XXXXXX")
		printf '%s' "$_pbw_json" | CLAUDE_PROJECT_DIR="$dir" bash "$HERE/$_pbw_hook" >/dev/null 2>"$_pbw_errf"
		_pbw_rc=$?
		_pbw_e=$(cat "$_pbw_errf" 2>/dev/null)
		rm -f "$_pbw_errf"
		if [ "$_pbw_rc" -eq 2 ]; then
			if [ "$_pbw_group" = claude ]; then
				_pbw_failed_claude=1
				[ -n "$_pbw_e" ] && _pbw_out_claude="$_pbw_out_claude
$_pbw_e"
			else
				_pbw_failed_normal=1
				[ -n "$_pbw_e" ] && _pbw_out_normal="$_pbw_out_normal
$_pbw_e"
			fi
		fi
	done
done <<EOF
$_pbw_list
EOF

_pbw_msg=""
if [ "$_pbw_failed_normal" -eq 1 ]; then
	_pbw_count="$_pbw_n_normal"
	[ "$_pbw_capped" -eq 1 ] && _pbw_count="showing 50 of $_pbw_total"
	_pbw_msg="post-bash-write: $_pbw_count file(s) newer than this command's start and dirty in git
$_pbw_out_normal"
fi
if [ "$_pbw_failed_claude" -eq 1 ]; then
	[ -n "$_pbw_msg" ] && _pbw_msg="$_pbw_msg
"
	_pbw_msg="${_pbw_msg}post-bash-write: gate config under .claude/ changed since this command started
$_pbw_out_claude"
fi

if [ -n "$_pbw_msg" ]; then
	hook_feedback "$_pbw_msg
(escape: CC_NO_POST_BASH_WRITE=1 for this session, or ask the user)"
fi

hook_ok
