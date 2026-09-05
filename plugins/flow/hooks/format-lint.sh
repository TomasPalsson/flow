#!/usr/bin/env bash
# format-lint.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# Runs a formatter (never a linter — eslint --fix never runs here; that is
# check-all's job inside stop-gate, once per turn) over the file that was
# just edited/written. Missing tools are skipped silently; a formatter that
# exits non-zero blocks the turn with its own output (exit 2) so the model
# fixes the file before continuing.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off   # `flow off` wrote .claude/flow.off here: no judging hooks

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok
[ -f "$file_path" ] || hook_ok

dir=$(hook_project_dir)
cfg="$dir/.claude/flow.config.json"

# C4 default ignore list; overridden wholesale by flow.config.json's "ignore"
# array when the key is present (jq absent = treat the config as absent).
_ignore_list='migrations/
generated/
locales/
i18n/
.generated.'
_format_on_edit="true"
if have jq && [ -f "$cfg" ]; then
  v=$(jq -r 'if has("formatOnEdit") then (.formatOnEdit | tostring) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _format_on_edit="$v"
  v=$(jq -r 'if has("ignore") then ((.ignore // [])[]) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && _ignore_list="$v"
fi

[ "$_format_on_edit" = "false" ] && hook_ok

_fl_ignored() {
  _fp=$1
  case "$_fp" in
  */node_modules/* | */.git/* | */dist/* | */build/*) return 0 ;;
  esac
  case "$(basename "$_fp")" in
  *.min.* | *.lock) return 0 ;;
  esac
  while IFS= read -r pat; do
    [ -z "$pat" ] && continue
    case "$_fp" in
    *"$pat"*) return 0 ;;
    esac
  done <<EOF
$_ignore_list
EOF
  return 1
}
_fl_ignored "$file_path" && hook_ok
# Git is the enforcement boundary: a scratch file outside any repo, or an
# ignored path (build output, .env), is not formatted or linted.
hook_git_managed "$file_path" || hook_ok

# cd to the git toplevel of the file's own directory, falling back to the
# file's directory when it is not inside a repo at all. Config presence
# (biome.json, .prettierrc*, ...) and node-tool discovery (node_modules)
# are both resolved relative to this directory.
_toplevel=$(git -C "$(dirname "$file_path")" rev-parse --show-toplevel 2>/dev/null)
if [ -n "$_toplevel" ]; then
  cd "$_toplevel" 2>/dev/null || hook_ok
else
  cd "$(dirname "$file_path")" 2>/dev/null || hook_ok
fi

case "$file_path" in
"$PWD"/*) rel="${file_path#"$PWD"/}" ;;
*) rel="$file_path" ;;
esac

# _fl_glob_present <pattern> — true if any file matching the (unquoted,
# glob-expanded) pattern exists in $PWD. A literal miss just leaves the
# pattern unexpanded, which then fails the -e test harmlessly.
_fl_glob_present() {
  for f in $1; do
    [ -e "$f" ] && return 0
  done
  return 1
}

_fl_node_runner() {
  if have bun; then
    _FL_R1="bunx"
    _FL_R2="--bun"
    return 0
  fi
  if have npx; then
    _FL_R1="npx"
    _FL_R2="--no-install"
    return 0
  fi
  return 1
}

_fl_ran=0
_fl_rc=0
_fl_out=""

case "$file_path" in
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.json | *.css | *.md)
  _fl_tool=""
  if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
    _fl_tool="biome"
  elif _fl_glob_present ".prettierrc*" || _fl_glob_present "prettier.config.*" ||
    { [ -f "package.json" ] && grep -q '"prettier"' package.json 2>/dev/null; }; then
    _fl_tool="prettier"
  fi
  if [ -n "$_fl_tool" ] && _fl_node_runner; then
    _fl_ran=1
    if [ "$_fl_tool" = "biome" ]; then
      _fl_out=$("$_FL_R1" "$_FL_R2" biome format --write "$file_path" 2>&1)
      _fl_rc=$?
    else
      _fl_out=$("$_FL_R1" "$_FL_R2" prettier --write "$file_path" 2>&1)
      _fl_rc=$?
    fi
  fi
  ;;
esac

if [ "$_fl_ran" -eq 0 ]; then
  case "$file_path" in
  *.py)
    if have ruff; then
      _fl_ran=1
      _fl_out=$(ruff format "$file_path" 2>&1)
      _fl_rc=$?
    fi
    ;;
  *.rs)
    if have rustfmt; then
      _fl_ran=1
      _fl_out=$(rustfmt --edition 2021 "$file_path" 2>&1)
      _fl_rc=$?
    fi
    ;;
  *.go)
    if have gofmt; then
      _fl_ran=1
      _fl_out=$(gofmt -w "$file_path" 2>&1)
      _fl_rc=$?
    fi
    ;;
  *.fish)
    if have fish_indent; then
      _fl_ran=1
      _fl_out=$(fish_indent -w "$file_path" 2>&1)
      _fl_rc=$?
    fi
    ;;
  *.sh | *.bash)
    if have shfmt; then
      _fl_ran=1
      _fl_out=$(shfmt -w "$file_path" 2>&1)
      _fl_rc=$?
    fi
    ;;
  esac
fi

if [ "$_fl_ran" -eq 1 ] && [ "$_fl_rc" -ne 0 ]; then
  hook_feedback "Formatter did not come back clean for $rel:
$(printf '%s' "$_fl_out" | tail -25)
Fix the reported issue in $rel before continuing."
fi

hook_ok
