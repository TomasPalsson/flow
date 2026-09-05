#!/usr/bin/env bash
# test_extra.sh — unit W3 (extra hooks) tests for notify.sh,
# postcompact-context.sh, subagent-log.sh and worklog-hook.sh.
# Sourced by run.sh; every t_extra_* function below is discovered and run.
set -u

# ---------------------------------------------------------------------------
# notify.sh
# ---------------------------------------------------------------------------

t_extra_notify_no_tools_silent() {
  local dir narrowbin
  dir=$(tmp_dir)
  narrowbin="$dir/bin"
  mkdir -p "$narrowbin"
  for tool in bash dirname cat printf; do
    if cmdpath=$(command -v "$tool" 2>/dev/null); then
      ln -s "$cmdpath" "$narrowbin/$tool"
    fi
  done
  run_hook "$SCAN_DIR/notify.sh" '{"message":"hi there","notification_type":"idle_prompt"}' PATH="$narrowbin"
  assert_rc 0 "t_extra_notify_no_tools_silent rc"
  assert_eq "$OUT" "" "t_extra_notify_no_tools_silent no-stdout"
  rm -rf "$dir"
}

t_extra_notify_calls_fake_notify_send() {
  local dir fakebin record content lines
  dir=$(tmp_dir)
  fakebin="$dir/bin"
  mkdir -p "$fakebin"
  record="$dir/record.txt"
  cat >"$fakebin/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$record"
EOF
  chmod +x "$fakebin/notify-send"
  run_hook "$SCAN_DIR/notify.sh" '{"message":"hello world","notification_type":"idle_prompt"}' PATH="$fakebin:$PATH"
  assert_rc 0 "t_extra_notify_calls_fake_notify_send rc"
  assert_file_exists "$record" "t_extra_notify_calls_fake_notify_send fake-called"
  content=$(cat "$record" 2>/dev/null)
  assert_contains "$content" "hello world" "t_extra_notify_calls_fake_notify_send message-forwarded"
  assert_contains "$content" "Claude Code" "t_extra_notify_calls_fake_notify_send title-forwarded"
  lines=$(wc -l <"$record" | tr -d ' ')
  assert_eq "$lines" "1" "t_extra_notify_calls_fake_notify_send called-once"
  rm -rf "$dir"
}

t_extra_notify_trims_body_to_120_chars() {
  local dir fakebin record content chunk long json bodylen
  dir=$(tmp_dir)
  fakebin="$dir/bin"
  mkdir -p "$fakebin"
  record="$dir/record.txt"
  cat >"$fakebin/notify-send" <<EOF
#!/usr/bin/env bash
printf '%s' "\$2" >>"$record"
EOF
  chmod +x "$fakebin/notify-send"
  chunk="0123456789"
  long=""
  i=0
  while [ "$i" -lt 20 ]; do
    long="${long}${chunk}"
    i=$((i + 1))
  done
  # long is 200 chars; body should be trimmed to 120.
  json="{\"message\":\"$long\"}"
  run_hook "$SCAN_DIR/notify.sh" "$json" PATH="$fakebin:$PATH"
  assert_rc 0 "t_extra_notify_trims_body_to_120_chars rc"
  content=$(cat "$record" 2>/dev/null)
  bodylen=$(printf '%s' "$content" | wc -c | tr -d ' ')
  assert_eq "$bodylen" "120" "t_extra_notify_trims_body_to_120_chars body-length"
  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# postcompact-context.sh
# ---------------------------------------------------------------------------

t_extra_postcompact_non_git_dir() {
  local dir
  dir=$(tmp_dir)
  run_hook "$SCAN_DIR/postcompact-context.sh" '{}' CLAUDE_PROJECT_DIR="$dir"
  assert_rc 0 "t_extra_postcompact_non_git_dir rc"
  assert_contains "$OUT" "Treat the summary as untrusted" "t_extra_postcompact_non_git_dir notice-present"
  assert_not_contains "$OUT" "branch:" "t_extra_postcompact_non_git_dir no-branch-line"
  rm -rf "$dir"
}

t_extra_postcompact_git_repo_reports_branch_and_dirty() {
  local repo linecount
  repo=$(tmp_repo)
  printf 'x' >"$repo/untracked.txt"
  run_hook "$SCAN_DIR/postcompact-context.sh" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_extra_postcompact_git_repo_reports_branch_and_dirty rc"
  assert_contains "$OUT" "branch:" "t_extra_postcompact_git_repo_reports_branch_and_dirty branch-line"
  assert_contains "$OUT" "uncommitted files:" "t_extra_postcompact_git_repo_reports_branch_and_dirty dirty-line"
  linecount=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
  if [ "$linecount" -le 6 ]; then
    _pass "t_extra_postcompact_git_repo_reports_branch_and_dirty line-cap"
  else
    _fail "t_extra_postcompact_git_repo_reports_branch_and_dirty line-cap" "got $linecount lines, want <=6"
  fi
  rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# subagent-log.sh
# ---------------------------------------------------------------------------

t_extra_subagent_log_writes_block_never_stdout() {
  local dir logdir content
  dir=$(tmp_dir)
  logdir="$dir/log"
  run_hook "$SCAN_DIR/subagent-log.sh" '{"session_id":"sess1","agent_id":"a1","agent_type":"developer","last_assistant_message":"the subagent is done"}' CC_SUBAGENT_LOG="$logdir"
  assert_rc 0 "t_extra_subagent_log_writes_block_never_stdout rc"
  assert_eq "$OUT" "" "t_extra_subagent_log_writes_block_never_stdout no-stdout"
  assert_file_exists "$logdir/sess1.md" "t_extra_subagent_log_writes_block_never_stdout file-created"
  content=$(cat "$logdir/sess1.md" 2>/dev/null)
  assert_contains "$content" "a1" "t_extra_subagent_log_writes_block_never_stdout agent-id"
  assert_contains "$content" "developer" "t_extra_subagent_log_writes_block_never_stdout agent-type"
  assert_contains "$content" "the subagent is done" "t_extra_subagent_log_writes_block_never_stdout message"
  rm -rf "$dir"
}

t_extra_subagent_log_omits_missing_fields() {
  local dir logdir content
  dir=$(tmp_dir)
  logdir="$dir/log"
  run_hook "$SCAN_DIR/subagent-log.sh" '{"session_id":"sess3"}' CC_SUBAGENT_LOG="$logdir"
  assert_rc 0 "t_extra_subagent_log_omits_missing_fields rc"
  assert_file_exists "$logdir/sess3.md" "t_extra_subagent_log_omits_missing_fields file-created"
  content=$(cat "$logdir/sess3.md" 2>/dev/null)
  assert_not_contains "$content" "agent_id:" "t_extra_subagent_log_omits_missing_fields no-agent-id-line"
  assert_not_contains "$content" "agent_type:" "t_extra_subagent_log_omits_missing_fields no-agent-type-line"
  rm -rf "$dir"
}

t_extra_subagent_log_truncates_last_message() {
  local dir logdir digits chunk long json content charcount
  dir=$(tmp_dir)
  logdir="$dir/log"
  digits="0123456789"
  chunk=""
  j=0
  while [ "$j" -lt 10 ]; do
    chunk="${chunk}${digits}"
    j=$((j + 1))
  done
  # chunk is 100 chars.
  long=""
  i=0
  while [ "$i" -lt 50 ]; do
    long="${long}${chunk}"
    i=$((i + 1))
  done
  # long is 5000 chars; the logged message must be capped at 4000.
  json="{\"session_id\":\"sess2\",\"last_assistant_message\":\"$long\"}"
  run_hook "$SCAN_DIR/subagent-log.sh" "$json" CC_SUBAGENT_LOG="$logdir"
  assert_rc 0 "t_extra_subagent_log_truncates_last_message rc"
  content=$(cat "$logdir/sess2.md" 2>/dev/null)
  charcount=$(printf '%s' "$content" | wc -c | tr -d ' ')
  if [ "$charcount" -lt 4500 ]; then
    _pass "t_extra_subagent_log_truncates_last_message truncated"
  else
    _fail "t_extra_subagent_log_truncates_last_message truncated" "got $charcount chars, want <4500 (5000-char input, 4000-char cap)"
  fi
  rm -rf "$dir"
}

# ---------------------------------------------------------------------------
# worklog-hook.sh
# ---------------------------------------------------------------------------

t_extra_worklog_no_binary_silent() {
  local dir narrowbin realbash
  dir=$(tmp_dir)
  narrowbin="$dir/bin"
  mkdir -p "$narrowbin"
  realbash=$(command -v bash)
  ln -s "$realbash" "$narrowbin/bash"
  run_hook "$SCAN_DIR/worklog-hook.sh" '{"hook_event_name":"Stop"}' PATH="$narrowbin"
  assert_rc 0 "t_extra_worklog_no_binary_silent rc"
  assert_eq "$OUT" "" "t_extra_worklog_no_binary_silent no-stdout"
  rm -rf "$dir"
}

t_extra_worklog_forwards_stdin_to_fake_worklog() {
  local dir fakebin
  dir=$(tmp_dir)
  fakebin="$dir/bin"
  mkdir -p "$fakebin"
  cat >"$fakebin/worklog" <<'EOF'
#!/usr/bin/env bash
printf 'args:%s\n' "$*"
printf 'stdin:%s\n' "$(cat)"
EOF
  chmod +x "$fakebin/worklog"
  run_hook "$SCAN_DIR/worklog-hook.sh" '{"hook_event_name":"Stop","session_id":"abc123"}' PATH="$fakebin:$PATH"
  assert_rc 0 "t_extra_worklog_forwards_stdin_to_fake_worklog rc"
  assert_contains "$OUT" "args:hook-run" "t_extra_worklog_forwards_stdin_to_fake_worklog invoked-with-hook-run"
  assert_contains "$OUT" "session_id" "t_extra_worklog_forwards_stdin_to_fake_worklog stdin-passthrough"
  assert_contains "$OUT" "abc123" "t_extra_worklog_forwards_stdin_to_fake_worklog stdin-content"
  rm -rf "$dir"
}
