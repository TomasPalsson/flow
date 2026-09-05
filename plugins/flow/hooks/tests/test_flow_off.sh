#!/usr/bin/env bash
# `flow off` marker (.claude/flow.off): judging hooks exit 0 silently, the
# session notice says so, bookkeeping hooks keep running, ancestors count.

_fo_big() { : >"$1"; local i=0; while [ $i -lt 500 ]; do printf 'x = %s\n' "$i" >>"$1"; i=$((i + 1)); done; }

t_flow_off_marker_silences_judging_hooks() {
  local repo json
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"; : >"$repo/.claude/flow.off"
  _fo_big "$repo/src.py"
  json=$(printf '{"session_id":"fo-1","tool_input":{"file_path":"%s"}}' "$repo/src.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "off: size-guard rc 0"; assert_eq "$ERR" "" "off: size-guard silent"
  run_hook "$SCAN_DIR/format-lint.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "off: format-lint rc 0"; assert_eq "$ERR" "" "off: format-lint silent"
  json=$(printf '{"session_id":"fo-1","tool_input":{"command":"git push --force origin main"}}')
  run_hook "$SCAN_DIR/git-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "off: git-guard rc 0"; assert_eq "$OUT" "" "off: git-guard does not deny"
  printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"fo-1"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  assert_rc 0 "off: stop-gate rc 0"; assert_eq "$OUT" "" "off: stop-gate does not block a red suite"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-fo-1"; rm -rf "$repo"
}

t_flow_off_marker_in_ancestor_counts() {
  local repo json
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude" "$repo/sub/deeper"; : >"$repo/.claude/flow.off"
  _fo_big "$repo/sub/deeper/src.py"
  json=$(printf '{"session_id":"fo-2","tool_input":{"file_path":"%s"}}' "$repo/sub/deeper/src.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo/sub/deeper"
  assert_rc 0 "ancestor marker: rc 0"; assert_eq "$ERR" "" "ancestor marker: silent"
  rm -rf "$repo"
}

t_flow_off_without_marker_hooks_still_judge() {
  local repo json
  repo=$(tmp_repo)
  _fo_big "$repo/src.py"
  json=$(printf '{"session_id":"fo-3","tool_input":{"file_path":"%s"}}' "$repo/src.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 2 "no marker: size-guard still reports"
  rm -rf "$repo"
}

t_flow_off_session_notice_and_bookkeeping_hooks() {
  local repo stamp
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"; : >"$repo/.claude/flow.off"
  run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"fo-4"}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "notice: rc 0"
  assert_contains "$OUT" "hooks are OFF in this directory" "notice: session start says hooks are off"
  assert_contains "$OUT" "flow on" "notice: names the way back"
  run_hook "$SCAN_DIR/turn-stamp.sh" '{"session_id":"fo-4"}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "bookkeeping: turn-stamp still runs"
  stamp="${TMPDIR:-/tmp}/claude-turn-fo-4"
  assert_file_exists "$stamp" "bookkeeping: turn stamp written while off"
  rm -f "$stamp"; rm -rf "$repo"
}
