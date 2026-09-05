#!/usr/bin/env bash
# notify.sh — Notification hook (matcher: permission_prompt|idle_prompt).
#
# Sends a desktop notification via notify-send (Linux) or osascript (macOS)
# when one of them is available; otherwise exits 0 silently. Never blocks
# Claude: every notifier call is guarded by `have` and its own failures are
# swallowed, so this hook always exits 0.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

message=$(hook_field '.message')
title="Claude Code"
body="${message:0:120}"

if have notify-send; then
  notify-send "$title" "$body" >/dev/null 2>&1 || true
elif have osascript; then
  # Escape backslashes and double quotes so the AppleScript string literal
  # stays well-formed.
  esc=$(printf '%s' "$body" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
  osascript -e "display notification \"$esc\" with title \"$title\"" >/dev/null 2>&1 || true
fi

hook_ok
