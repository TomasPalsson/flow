#!/usr/bin/env bash
# codebase-map.sh — SessionStart hook (also fires on compact, per the
# SessionStart "source" field wired by the orchestrator).
#
# Opt-in only: exits 0 silently unless .claude/harness.json sets
# "codebaseMap": true (jq required to read it; jq absent or the key
# absent/false = off). When on, (re)generates .claude/codebase-map.md
# via the codebase-map script and prints exactly one summary line.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

dir=$(hook_project_dir)
cfg="$dir/.claude/harness.json"

enabled="false"
if have jq && [ -f "$cfg" ]; then
  v=$(jq -r 'if has("codebaseMap") then (.codebaseMap | tostring) else empty end' "$cfg" 2>/dev/null)
  [ -n "$v" ] && enabled="$v"
fi
[ "$enabled" != "true" ] && hook_ok

# Sibling script first (the plugin copy is the source of truth); user-level copy only as a fallback.
script="${CC_SCRIPTS_DIR:-$HERE/../scripts}/codebase-map"
[ -x "$script" ] || script="$HOME/.claude/scripts/codebase-map"
[ -x "$script" ] || hook_ok

(cd "$dir" && "$script" >/dev/null 2>&1)

map_file="$dir/.claude/codebase-map.md"
[ -f "$map_file" ] || hook_ok

n=$(wc -l <"$map_file" 2>/dev/null | tr -d ' ')
[ -z "$n" ] && n=0

sha=$(git -C "$dir" rev-parse --short HEAD 2>/dev/null)
[ -z "$sha" ] && sha="(unknown)"

printf 'codebase map: .claude/codebase-map.md (%s lines, head %s) — leads only; verify every path before use\n' "$n" "$sha"

hook_ok
