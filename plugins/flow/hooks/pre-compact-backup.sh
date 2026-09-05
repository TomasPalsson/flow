#!/usr/bin/env bash
# pre-compact-backup.sh — PreCompact hook.
#
# Copies transcript_path into ${CC_BACKUP_DIR:-$HOME/.claude/transcript-backups}
# as <epoch10>_<session_id>_<trigger>.jsonl, then prunes the backup dir down
# to the 50 newest files by name sort (epoch is zero-padded so name order is
# chronological order). Exits 0 always, including when transcript_path is
# absent or unreadable.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

backup_dir="${CC_BACKUP_DIR:-$HOME/.claude/transcript-backups}"

transcript=$(hook_field '.transcript_path')

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  mkdir -p "$backup_dir" 2>/dev/null || true

  session_id=$(hook_field '.session_id')
  [ -z "$session_id" ] && session_id="nosession"
  session_id=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9_-' '_')

  trigger=$(hook_field '.trigger')
  [ -z "$trigger" ] && trigger="manual"
  trigger=$(printf '%s' "$trigger" | tr -c 'A-Za-z0-9_-' '_')

  epoch=$(date +%s 2>/dev/null)
  [ -z "$epoch" ] && epoch=0
  epoch=$(printf '%010d' "$epoch" 2>/dev/null)

  dest="$backup_dir/${epoch}_${session_id}_${trigger}.jsonl"
  cp "$transcript" "$dest" 2>/dev/null || true
fi

# Retention: keep at most the 50 newest files (lexical sort == chronological
# order because the epoch prefix is zero-padded). Runs whenever the backup
# dir exists, independent of whether this turn added a new file.
if [ -d "$backup_dir" ]; then
  count=$(ls -1 "$backup_dir" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$count" -gt 50 ]; then
    excess=$((count - 50))
    ls -1 "$backup_dir" 2>/dev/null | sort | head -n "$excess" | while IFS= read -r stale; do
      rm -f "$backup_dir/$stale" 2>/dev/null || true
    done
  fi
fi

hook_ok
