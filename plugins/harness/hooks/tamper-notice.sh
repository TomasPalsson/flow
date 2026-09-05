#!/usr/bin/env bash
# tamper-notice.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# A detector, not a prohibition: looks at the lines *added* in this edit to
# a test file or a gate-config file and flags patterns that look like a
# check being disabled or weakened (a skipped test, a lowered threshold, a
# stopGate:false). Never blocks a change outright — it exits 2 so the
# feedback reaches the model, which can state the reason or revert it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok

_is_test_file=0
case "$file_path" in
*_test.* | *.test.* | *.spec.* | */tests/* | */__tests__/* | tests/* | __tests__/*)
  _is_test_file=1
  ;;
esac

_is_gate_config=0
case "$file_path" in
*/.claude/harness.json | .claude/harness.json | \
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

_tn_tracked=1
git -C "$_filedir" ls-files --error-unmatch "$file_path" >/dev/null 2>&1 || _tn_tracked=0

if [ "$_tn_tracked" -eq 1 ]; then
  _diff=$(git -C "$_filedir" diff HEAD -- "$file_path" 2>/dev/null)
  _added=$(printf '%s\n' "$_diff" | grep -E '^\+' | grep -vE '^\+\+\+' || true)
  _removed=$(printf '%s\n' "$_diff" | grep -E '^-' | grep -vE '^---' || true)
else
  # Untracked file: every line counts as added; there is nothing to remove.
  _added=$(sed 's/^/+/' "$file_path" 2>/dev/null || true)
  _removed=""
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
You just disabled or weakened a check. If that is intentional and correct, state which check and why in your reply; otherwise revert it."
fi

hook_ok
