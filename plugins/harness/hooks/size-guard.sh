#!/usr/bin/env bash
# size-guard.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# Skips the same ignored paths as format-lint.sh, plus test files and a
# handful of always-noisy extensions, then hands off to size_guard.py for
# the actual line/function-span heuristics. python3 is required; the check
# is skipped entirely (exit 0) when it is absent.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok
[ -f "$file_path" ] || hook_ok

have python3 || hook_ok

[ "${CC_NO_SIZE_GUARD:-}" = "1" ] && hook_ok

dir=$(hook_project_dir)
cfg="$dir/.claude/harness.json"

# C4 default ignore list; overridden wholesale by harness.json's "ignore"
# array when the key is present (jq absent = treat the config as absent).
_ignore_list='migrations/
generated/
locales/
i18n/
.generated.'
_size_guard_enabled="true"
_max_file=""
_max_func=""
if have jq && [ -f "$cfg" ]; then
  v=$(jq -r 'if has("sizeGuard") then (.sizeGuard | tostring) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _size_guard_enabled="$v"
  v=$(jq -r 'if has("ignore") then ((.ignore // [])[]) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _ignore_list="$v"
  v=$(jq -r 'if has("maxFileLines") then (.maxFileLines | tostring) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _max_file="$v"
  v=$(jq -r 'if has("maxFuncLines") then (.maxFuncLines | tostring) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _max_func="$v"
fi

[ "$_size_guard_enabled" = "false" ] && hook_ok

# Env overrides win over harness.json, which wins over the 400/60 defaults.
[ -n "${CC_MAX_FILE_LINES:-}" ] && _max_file="$CC_MAX_FILE_LINES"
[ -n "${CC_MAX_FUNC_LINES:-}" ] && _max_func="$CC_MAX_FUNC_LINES"
[ -z "$_max_file" ] && _max_file=400
[ -z "$_max_func" ] && _max_func=60

case "$file_path" in
*/node_modules/* | */.git/* | */dist/* | */build/*) hook_ok ;;
esac
case "$(basename "$file_path")" in
*.min.* | *.lock) hook_ok ;;
esac
case "$file_path" in
*_test.* | *.test.* | *.spec.* | */tests/* | */__tests__/* | tests/* | __tests__/*) hook_ok ;;
esac
case "$file_path" in
*.json | *.md | *.lock | *.svg | *.snap | *.csv | *.yml | *.yaml) hook_ok ;;
esac

while IFS= read -r pat; do
  [ -z "$pat" ] && continue
  case "$file_path" in
  *"$pat"*) hook_ok ;;
  esac
done <<EOF
$_ignore_list
EOF

exec python3 "$HERE/size_guard.py" "$file_path" "$_max_file" "$_max_func"
