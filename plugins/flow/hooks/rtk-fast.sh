#!/bin/bash
# rtk-fast: optimized wrapper for rtk-rewrite.sh (same protocol, fewer forks). Not managed by rtk.
#
# Exit code protocol of `rtk rewrite` (mirrors rtk-rewrite.sh exactly):
#   0 + stdout  Rewrite found, no deny/ask rule matched -> auto-allow
#   1           No RTK equivalent -> pass through unchanged
#   2           Deny rule matched -> pass through (Claude Code native deny handles it)
#   3 + stdout  Ask rule matched -> rewrite but let Claude Code prompt user

CACHE_FILE="/Users/tomas/.claude/hooks/.rtk-fast-cache"

RTK_BIN=""
JQ_BIN=""

# --- Warm path: try the cached stamp first, bash builtins only, zero PATH scans ---
if [ -f "$CACHE_FILE" ]; then
  IFS='|' read -r CACHED_RTK CACHED_MTIME CACHED_JQ < "$CACHE_FILE"
  if [ -n "$CACHED_RTK" ] && [ -n "$CACHED_JQ" ] && [ -x "$CACHED_RTK" ] && [ -x "$CACHED_JQ" ]; then
    CURRENT_MTIME=$(/usr/bin/stat -f %m "$CACHED_RTK" 2>/dev/null)
    if [ -n "$CURRENT_MTIME" ] && [ "$CURRENT_MTIME" = "$CACHED_MTIME" ]; then
      RTK_BIN="$CACHED_RTK"
      JQ_BIN="$CACHED_JQ"
    fi
  fi
fi

# --- Cold path: stamp missing/stale, resolve via command -v and (re)validate ---
if [ -z "$RTK_BIN" ] || [ -z "$JQ_BIN" ]; then
  JQ_BIN=$(command -v jq)
  if [ -z "$JQ_BIN" ]; then
    echo "[rtk] WARNING: jq not installed. Hook cannot rewrite commands. Install jq: https://jqlang.github.io/jq/download/" >&2
    exit 0
  fi

  RTK_BIN=$(command -v rtk)
  if [ -z "$RTK_BIN" ]; then
    echo "[rtk] WARNING: rtk not installed or not in PATH. Hook cannot rewrite commands. Install: https://github.com/rtk-ai/rtk#installation" >&2
    exit 0
  fi

  # Version guard: rtk rewrite added in 0.23.0.
  # Older binaries: warn once and exit cleanly (no silent failure).
  RTK_VERSION=$("$RTK_BIN" --version 2>/dev/null | /usr/bin/grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | /usr/bin/head -1)
  if [ -n "$RTK_VERSION" ]; then
    MAJOR=$(/usr/bin/cut -d. -f1 <<<"$RTK_VERSION")
    MINOR=$(/usr/bin/cut -d. -f2 <<<"$RTK_VERSION")
    # Require >= 0.23.0
    if [ "$MAJOR" -eq 0 ] && [ "$MINOR" -lt 23 ]; then
      echo "[rtk] WARNING: rtk $RTK_VERSION is too old (need >= 0.23.0). Upgrade: cargo install rtk" >&2
      exit 0
    fi
  fi

  # Write the stamp for next time. Failure to write must not break the hook.
  RTK_MTIME=$(/usr/bin/stat -f %m "$RTK_BIN" 2>/dev/null)
  if [ -n "$RTK_MTIME" ]; then
    printf '%s|%s|%s\n' "$RTK_BIN" "$RTK_MTIME" "$JQ_BIN" > "$CACHE_FILE" 2>/dev/null || true
  fi
fi

# --- Work path: 3 forks here (jq extract, rtk rewrite, jq build); combined
# with the warm-check's stat and the cat below, a warm hit forks 5 times total ---
INPUT=$(cat)
CMD=$("$JQ_BIN" -r '.tool_input.command // empty' <<<"$INPUT")

if [ -z "$CMD" ]; then
  exit 0
fi

# Delegate all rewrite + permission logic to the Rust binary.
REWRITTEN=$("$RTK_BIN" rewrite "$CMD" 2>/dev/null)
EXIT_CODE=$?

case $EXIT_CODE in
  0)
    # Rewrite found, no permission rules matched — safe to auto-allow.
    # If the output is identical, the command was already using RTK.
    [ "$CMD" = "$REWRITTEN" ] && exit 0
    ;;
  1)
    # No RTK equivalent — pass through unchanged.
    exit 0
    ;;
  2)
    # Deny rule matched — let Claude Code's native deny rule handle it.
    exit 0
    ;;
  3)
    # Ask rule matched — rewrite the command but do NOT auto-allow so that
    # Claude Code prompts the user for confirmation.
    ;;
  *)
    exit 0
    ;;
esac

if [ "$EXIT_CODE" -eq 3 ]; then
  # Ask: rewrite the command, omit permissionDecision so Claude Code prompts.
  "$JQ_BIN" -n \
    --argjson input "$INPUT" \
    --arg cmd "$REWRITTEN" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": ($input.tool_input | .command = $cmd)
      }
    }'
else
  # Allow: rewrite the command and auto-allow.
  "$JQ_BIN" -n \
    --argjson input "$INPUT" \
    --arg cmd "$REWRITTEN" \
    '{
      "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "allow",
        "permissionDecisionReason": "RTK auto-rewrite",
        "updatedInput": ($input.tool_input | .command = $cmd)
      }
    }'
fi
