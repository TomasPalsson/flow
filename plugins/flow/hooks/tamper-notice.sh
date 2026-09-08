#!/usr/bin/env bash
# tamper-notice.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# A detector, not a prohibition: looks at the lines this edit *added* to a
# test file or a gate-config file and flags patterns that look like a check
# being disabled or weakened (a skipped test, a lowered threshold, a
# stopGate:false). Never blocks a change outright — it exits 2 so the
# feedback reaches the model, which can state the reason or revert it.
#
# What counts as a test file is decided by name AND by content, because
# tests live in src/lib.rs and in helpers.py as often as in tests/. What
# counts as "added" is measured against the content at the start of this
# session's first sight of the file (a snapshot under
# ${TMPDIR}/claude-tamper-<session>/), so a skip that was already there is
# reported once and never nagged about again.
#
# On that first sight there is no snapshot, and `git diff HEAD` also shows dirt
# that predates the session — lines this hook may not attribute to this edit.
# For an Edit/MultiEdit the pre-edit content is not guessed but RECONSTRUCTED:
# the current file with new_string substituted back to old_string (for
# MultiEdit, every edit reversed in reverse order), which is exact whenever
# new_string occurs exactly once. When it occurs zero or several times the
# reconstruction is ambiguous — the hook cannot prove which line this edit
# wrote — and it says nothing rather than naming a line it did not write.
# For a Write/NotebookEdit there is no old_string to reverse, so the delta is
# narrowed to the lines the payload text (content/new_string) appears in.
#
# Escape hatch: `flow off` for the directory; otherwise answer the note.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off # `flow off` wrote .claude/flow.off here: no judging hooks

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok

_is_test_file=0
case "$file_path" in
*_test.* | *.test.* | *.spec.* | */tests/* | */__tests__/* | tests/* | __tests__/*)
	_is_test_file=1
	;;
esac

# Content beats naming: a Rust module with #[cfg(test)], a python file with
# def test_, a Go file with func Test — those are test files whatever they
# are called.
if [ "$_is_test_file" -eq 0 ] && [ -f "$file_path" ]; then
	case "$file_path" in
	*.rs) grep -qE '^[[:space:]]*#\[(cfg\(test\)|test)\]' "$file_path" 2>/dev/null && _is_test_file=1 ;;
	*.py) grep -qE '^[[:space:]]*(def test_|class Test)' "$file_path" 2>/dev/null && _is_test_file=1 ;;
	*.go) grep -qE '^func Test' "$file_path" 2>/dev/null && _is_test_file=1 ;;
	esac
fi

_is_gate_config=0
case "$file_path" in
*/.claude/flow.config.json | .claude/flow.config.json | \
	*/eslint.config.* | eslint.config.* | \
	*/.eslintrc* | .eslintrc* | \
	*/pyproject.toml | pyproject.toml | \
	*/ruff.toml | ruff.toml | \
	*/clippy.toml | clippy.toml | \
	*/.golangci.yml | .golangci.yml)
	_is_gate_config=1
	;;
esac

if [ "$_is_test_file" -eq 0 ] && [ "$_is_gate_config" -eq 0 ]; then
	hook_ok
fi

have git || hook_ok

_filedir=$(dirname "$file_path")
git -C "$_filedir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok
# git-ignored test files are out of scope; gate config (often under a
# gitignored .claude/) is always in scope — weakening it is the whole point.
if [ "$_is_gate_config" -eq 0 ]; then hook_git_managed "$file_path" || hook_ok; fi

# The baseline this edit is measured against, best evidence first: the snapshot
# taken when this session first saw the file (nothing already present is ever
# reported twice), else the pre-edit content reconstructed from the payload,
# else git (HEAD for a tracked file, nothing at all for a new one) — the first
# sight of a file is still worth judging.
_tn_sid=$(hook_field '.session_id')
[ -z "$_tn_sid" ] && _tn_sid="nosession"
_tn_sid=$(printf '%s' "$_tn_sid" | tr -c 'A-Za-z0-9_-' '_')
_tn_tmp="${TMPDIR:-/tmp}"
_tn_snapdir="${_tn_tmp%/}/claude-tamper-$_tn_sid"
_tn_snap="$_tn_snapdir/$(printf '%s' "$file_path" | cksum | awk '{print $1}')"

# ${TMPDIR}/claude-tamper-nosession is a guessable name on a shared /tmp: refuse
# a directory someone else planted or owns, and never write through a symlink.
_tn_snapdir_ok=1
[ -L "$_tn_snapdir" ] && _tn_snapdir_ok=0
if [ "$_tn_snapdir_ok" -eq 1 ] && [ -d "$_tn_snapdir" ] && [ ! -O "$_tn_snapdir" ]; then
	_tn_snapdir_ok=0
fi

_tn_have_snap=0
if [ "$_tn_snapdir_ok" -eq 1 ] && [ -f "$_tn_snap" ] && [ ! -L "$_tn_snap" ] && [ -O "$_tn_snap" ]; then
	_tn_have_snap=1
fi

# The pre-edit content, reconstructed from the tool payload: the current file
# with this call's new_string(s) substituted back to old_string(s). Exact when
# each new_string occurs exactly once (what Claude Code's uniqueness rule
# guarantees for old_string); null — meaning "cannot be proved" — otherwise.
_TN_RECON_JQ='
def _tnrepl($s; $old; $new; $all):
  if ($new|length) == 0 then null
  elif $all then ($s | split($new) | join($old))
  else (($s | split($new)) as $p | if ($p|length) == 2 then ($p|join($old)) else null end)
  end;
(.tool_input // {}) as $t
| if ($t.edits|type) == "array" then
    reduce ($t.edits|reverse)[] as $e ($cur;
      if . == null then null
      else _tnrepl(.; ($e.old_string // ""); ($e.new_string // ""); ($e.replace_all // false)) end)
  elif ($t.old_string|type) == "string" then
    _tnrepl($cur; $t.old_string; ($t.new_string // ""); ($t.replace_all // false))
  else null end
'

# _tn_reconstruct — write the pre-edit content to $_tn_recon; rc 1 when this
# payload cannot be reversed (Write/NotebookEdit, an ambiguous or absent
# new_string, no jq, an unreadable file).
_tn_recon=""
_tn_reconstruct() {
	local cur
	have jq || return 1
	cur=$(jq -Rs . "$file_path" 2>/dev/null) || return 1
	[ -n "$cur" ] || return 1
	_tn_recon=$(mktemp "${_tn_tmp%/}/claude-tn-base.XXXXXX" 2>/dev/null) || return 1
	printf '%s' "$HOOK_INPUT" |
		jq -j -e --argjson cur "$cur" "$_TN_RECON_JQ" >"$_tn_recon" 2>/dev/null
}

_tn_isedit=$(hook_field '[.tool_input | select((.old_string|type)=="string" or (.edits|type)=="array")] | length')
_tn_narrow=0
_tn_base=""
_tn_gave_up=0
if [ "$_tn_have_snap" -eq 1 ]; then
	_tn_base="$_tn_snap"
elif [ "$_tn_isedit" = "1" ]; then
	if _tn_reconstruct; then
		_tn_base="$_tn_recon"
	else
		# An Edit this hook cannot reverse: reporting the whole uncommitted
		# delta would name lines written before this turn. Say nothing.
		_tn_gave_up=1
	fi
	[ -n "$_tn_recon" ] && [ "$_tn_gave_up" -eq 1 ] && rm -f "$_tn_recon"
else
	_tn_narrow=1
fi

if [ "$_tn_gave_up" -eq 1 ]; then
	_added=""
	_removed=""
elif [ -n "$_tn_base" ]; then
	_diff=$(diff -u "$_tn_base" "$file_path" 2>/dev/null || true)
	_added=$(printf '%s\n' "$_diff" | grep -E '^\+' | grep -vE '^\+\+\+' || true)
	_removed=$(printf '%s\n' "$_diff" | grep -E '^-' | grep -vE '^---' || true)
	[ -n "$_tn_recon" ] && rm -f "$_tn_recon"
elif git -C "$_filedir" ls-files --error-unmatch "$file_path" >/dev/null 2>&1; then
	_diff=$(git -C "$_filedir" diff HEAD -- "$file_path" 2>/dev/null)
	_added=$(printf '%s\n' "$_diff" | grep -E '^\+' | grep -vE '^\+\+\+' || true)
	_removed=$(printf '%s\n' "$_diff" | grep -E '^-' | grep -vE '^---' || true)
else
	# Untracked and never seen: every line counts as added; nothing to remove.
	_added=$(awk '{print "+" $0}' "$file_path" 2>/dev/null || true)
	_removed=""
fi

# First sight through a payload that carries no old_string (Write,
# NotebookEdit): the delta above is "everything uncommitted", which includes
# work that predates this session. Keep the added lines the payload text
# appears in — a Write's content is the whole file it just wrote, so every line
# it kept is one it wrote. With no payload text at all (a Bash-driven write
# re-dispatched here) there is nothing to match against and the delta stands.
if [ "$_tn_narrow" -eq 1 ]; then
	_tn_written=$(hook_field '.tool_input.content')
	if [ -z "$_tn_written" ]; then
		_tn_written=$(hook_field '.tool_input.new_string')
	fi
	if [ -n "$_tn_written" ]; then
		_added=$(printf '%s\n' "$_added" | TN_WRITTEN="$_tn_written" awk '
			BEGIN {
				n = split(ENVIRON["TN_WRITTEN"], w, "\n")
				m = 0
				for (i = 1; i <= n; i++) {
					f = w[i]
					gsub(/^[ \t\r]+/, "", f)
					gsub(/[ \t\r]+$/, "", f)
					# A blank or whitespace-only fragment is a substring of every
					# line; it would keep the whole delta instead of narrowing it.
					if (f != "") frag[++m] = f
				}
			}
			{
				line = substr($0, 2)
				for (i = 1; i <= m; i++) {
					if (index(line, frag[i]) > 0) { print; break }
				}
			}
		')
	fi
fi

# Snapshot before deciding: whatever is reported below is reported once. The
# name is unlinked first so a symlink planted there is replaced, not written
# through, and the copy is readable only by its owner.
if [ "$_tn_snapdir_ok" -eq 1 ] && mkdir -p "$_tn_snapdir" 2>/dev/null; then
	chmod 700 "$_tn_snapdir" 2>/dev/null || true
	if [ -O "$_tn_snapdir" ] && [ ! -L "$_tn_snapdir" ]; then
		rm -f "$_tn_snap" 2>/dev/null || true
		cp "$file_path" "$_tn_snap" 2>/dev/null && chmod 600 "$_tn_snap" 2>/dev/null || true
	fi
fi

_matched=""

if [ "$_is_test_file" -eq 1 ]; then
	_tn_hits=$(printf '%s\n' "$_added" | grep -E '\.skip\(|\.only\(|it\.todo\(|xfail|@pytest\.mark\.skip|#\[ignore\]|t\.Skip\(' || true)
	if [ -n "$_tn_hits" ]; then
		_matched="$_matched
$_tn_hits"
	fi
fi

if [ "$_is_gate_config" -eq 1 ]; then
	_tn_stopgate=$(printf '%s\n' "$_added" | grep -E '"?stopGate"?[[:space:]]*[:=][[:space:]]*false' || true)
	if [ -n "$_tn_stopgate" ]; then
		_matched="$_matched
$_tn_stopgate"
	fi

	# A numeric value change on a max*/complexity/threshold-like key: the same
	# key name appears in both a removed line (old value) and an added line
	# (new, different value).
	_kv_extract() {
		sed 's/^[+-]//' | grep -oE '"?[A-Za-z_][A-Za-z0-9_-]*"?[[:space:]]*[:=][[:space:]]*-?[0-9]+' |
			sed -E 's/^"?([A-Za-z_][A-Za-z0-9_-]*)"?[[:space:]]*[:=][[:space:]]*(-?[0-9]+)$/\1 \2/'
	}
	_removed_kv=$(printf '%s\n' "$_removed" | _kv_extract | grep -E '^(max[-_A-Za-z]*|complexity|threshold)[[:space:]]' || true)
	_added_kv=$(printf '%s\n' "$_added" | _kv_extract | grep -E '^(max[-_A-Za-z]*|complexity|threshold)[[:space:]]' || true)

	if [ -n "$_added_kv" ]; then
		while IFS=' ' read -r _tn_k _tn_v; do
			[ -z "$_tn_k" ] && continue
			_tn_rv=$(printf '%s\n' "$_removed_kv" | awk -v k="$_tn_k" '$1==k{print $2; exit}')
			if [ -n "$_tn_rv" ] && [ "$_tn_rv" != "$_tn_v" ]; then
				_tn_line=$(printf '%s\n' "$_added" | grep -F "$_tn_k" | head -1)
				_matched="$_matched
$_tn_line"
			fi
		done <<EOF
$_added_kv
EOF
	fi
fi

_matched=$(printf '%s\n' "$_matched" | sed '/^$/d')

if [ -n "$_matched" ]; then
	hook_feedback "$file_path
$_matched
You just disabled or weakened a check. If that is intentional and correct, state which check and why in your reply; otherwise revert it. (escape: state the reason in your reply and continue, or \`flow off\` in this directory to silence this hook)"
fi

hook_ok
