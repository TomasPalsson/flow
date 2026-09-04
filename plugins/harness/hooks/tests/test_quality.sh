#!/usr/bin/env bash
# test_quality.sh — unit U2 (hooks-quality) tests for format-lint.sh,
# size-guard.sh + size_guard.py, tamper-notice.sh and stop-gate.sh.
# Sourced by run.sh; every t_quality_* function below is discovered and run.
set -u

_FIXTURES="$SCAN_DIR/tests/fixtures"

# ---------------------------------------------------------------------------
# format-lint.sh
# ---------------------------------------------------------------------------

t_quality_format_lint_missing_file_path_ok() {
  run_hook "$SCAN_DIR/format-lint.sh" '{"tool_input":{}}'
  assert_rc 0 "t_quality_format_lint_missing_file_path_ok rc"
}

t_quality_format_lint_ignored_path_rc0() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/generated"
  printf 'def foo(:\n    pass\n' >"$d/generated/bad.py"
  run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/generated/bad.py\"}}"
  assert_rc 0 "t_quality_format_lint_ignored_path_rc0 rc"
  rm -rf "$d"
}

t_quality_format_lint_format_on_edit_false_rc0() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/.claude"
  printf '{"formatOnEdit": false}\n' >"$d/.claude/harness.json"
  printf 'def foo(:\n    pass\n' >"$d/bad.py"
  run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/bad.py\"}}" CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "t_quality_format_lint_format_on_edit_false_rc0 rc"
  rm -rf "$d"
}

t_quality_format_lint_py_syntax_error_rc2() {
  local d
  if ! have_ruff; then
    printf '  skip t_quality_format_lint_py_syntax_error_rc2 (ruff not installed)\n'
    return 0
  fi
  d=$(tmp_dir)
  printf 'def foo(:\n    pass\n' >"$d/bad.py"
  run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/bad.py\"}}"
  assert_rc 2 "t_quality_format_lint_py_syntax_error_rc2 rc"
  assert_contains "$ERR" "Formatter did not come back clean for" "t_quality_format_lint_py_syntax_error_rc2 message"
  assert_contains "$ERR" "bad.py" "t_quality_format_lint_py_syntax_error_rc2 filename"
  rm -rf "$d"
}

t_quality_format_lint_py_clean_format_rc0() {
  local d
  if ! have_ruff; then
    printf '  skip t_quality_format_lint_py_clean_format_rc0 (ruff not installed)\n'
    return 0
  fi
  d=$(tmp_dir)
  printf 'def   foo( ):\n  return   1\n' >"$d/ok.py"
  run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/ok.py\"}}"
  assert_rc 0 "t_quality_format_lint_py_clean_format_rc0 rc"
  assert_contains "$(cat "$d/ok.py")" "def foo():" "t_quality_format_lint_py_clean_format_rc0 reformatted"
  rm -rf "$d"
}

have_ruff() { command -v ruff >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# size-guard.sh + size_guard.py
# ---------------------------------------------------------------------------

t_quality_size_guard_react_component_no_problem() {
  run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/react-component.tsx" 400 60
  assert_rc 0 "t_quality_size_guard_react_component_no_problem rc"
  assert_eq "$ERR" "" "t_quality_size_guard_react_component_no_problem no-stderr"
}

t_quality_size_guard_long_function_flagged() {
  run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/long-function.py" 400 60
  assert_rc 2 "t_quality_size_guard_long_function_flagged rc"
  assert_contains "$ERR" "process_large_batch" "t_quality_size_guard_long_function_flagged names-function"
  assert_contains "$ERR" "70 lines" "t_quality_size_guard_long_function_flagged line-count"
}

t_quality_size_guard_long_file_flagged() {
  run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/long-file.js" 400 60
  assert_rc 2 "t_quality_size_guard_long_file_flagged rc"
  assert_contains "$ERR" "449 lines" "t_quality_size_guard_long_file_flagged line-count"
  assert_not_contains "$ERR" "function '" "t_quality_size_guard_long_file_flagged no-function-problem"
}

t_quality_size_guard_binary_file_never_crashes() {
  local d
  d=$(tmp_dir)
  printf '\x00\x01\x02binary\xff\xfe' >"$d/blob.bin"
  run_cmd python3 "$SCAN_DIR/size_guard.py" "$d/blob.bin" 400 60
  assert_rc 0 "t_quality_size_guard_binary_file_never_crashes rc"
  rm -rf "$d"
}

t_quality_size_guard_sh_ignore_default_locales_rc0() {
  # The fixture itself lives under hooks/tests/fixtures/, which the hook
  # would (correctly) also skip as "under tests/"; copy its content to a
  # path that is ignored only via the C4 default "locales/" entry, to test
  # that skip path in isolation.
  local d
  d=$(tmp_dir)
  mkdir -p "$d/locales"
  cp "$_FIXTURES/locales/en-strings.txt" "$d/locales/en-strings.txt"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/locales/en-strings.txt\"}}"
  assert_rc 0 "t_quality_size_guard_sh_ignore_default_locales_rc0 rc"
  rm -rf "$d"
}

t_quality_size_guard_sh_missing_file_rc0() {
  run_hook "$SCAN_DIR/size-guard.sh" '{"tool_input":{"file_path":"/no/such/file.py"}}'
  assert_rc 0 "t_quality_size_guard_sh_missing_file_rc0 rc"
}

t_quality_size_guard_sh_size_guard_false_rc0() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/.claude"
  printf '{"sizeGuard": false}\n' >"$d/.claude/harness.json"
  cp "$_FIXTURES/long-function.py" "$d/big.py"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}" CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "t_quality_size_guard_sh_size_guard_false_rc0 rc"
  rm -rf "$d"
}

t_quality_size_guard_sh_cc_no_size_guard_env_rc0() {
  local d
  d=$(tmp_dir)
  cp "$_FIXTURES/long-function.py" "$d/big.py"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}" CC_NO_SIZE_GUARD=1
  assert_rc 0 "t_quality_size_guard_sh_cc_no_size_guard_env_rc0 rc"
  rm -rf "$d"
}

t_quality_size_guard_sh_test_file_skip_rc0() {
  local d
  d=$(tmp_dir)
  cp "$_FIXTURES/long-function.py" "$d/big_test.py"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big_test.py\"}}"
  assert_rc 0 "t_quality_size_guard_sh_test_file_skip_rc0 rc"
  rm -rf "$d"
}

t_quality_size_guard_sh_triggers_on_real_invocation_rc2() {
  local d
  d=$(tmp_dir)
  cp "$_FIXTURES/long-function.py" "$d/big.py"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}"
  assert_rc 2 "t_quality_size_guard_sh_triggers_on_real_invocation_rc2 rc"
  assert_contains "$ERR" "process_large_batch" "t_quality_size_guard_sh_triggers_on_real_invocation_rc2 names-function"
  rm -rf "$d"
}

t_quality_size_guard_sh_env_threshold_override_rc2() {
  local d
  d=$(tmp_dir)
  printf 'line one\nline two\nline three\n' >"$d/small.txt"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/small.txt\"}}" CC_MAX_FILE_LINES=2
  assert_rc 2 "t_quality_size_guard_sh_env_threshold_override_rc2 rc"
  assert_contains "$ERR" "3 lines" "t_quality_size_guard_sh_env_threshold_override_rc2 message"
  rm -rf "$d"
}

t_quality_size_guard_sh_config_threshold_override_rc2() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/.claude"
  printf '{"maxFuncLines": 5}\n' >"$d/.claude/harness.json"
  printf 'def tiny():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 5\n    return a + b + c + d + e\n' >"$d/tiny.py"
  run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/tiny.py\"}}" CLAUDE_PROJECT_DIR="$d"
  assert_rc 2 "t_quality_size_guard_sh_config_threshold_override_rc2 rc"
  assert_contains "$ERR" "tiny" "t_quality_size_guard_sh_config_threshold_override_rc2 names-function"
  rm -rf "$d"
}

# ---------------------------------------------------------------------------
# tamper-notice.sh
# ---------------------------------------------------------------------------

t_quality_tamper_notice_no_file_path_rc0() {
  run_hook "$SCAN_DIR/tamper-notice.sh" '{"tool_input":{}}'
  assert_rc 0 "t_quality_tamper_notice_no_file_path_rc0 rc"
}

t_quality_tamper_notice_non_test_non_config_rc0() {
  local repo
  repo=$(tmp_repo)
  printf 'console.log(1);\n' >"$repo/app.js"
  (cd "$repo" && git add app.js && git commit -q -m app) >/dev/null 2>&1
  printf 'console.log(2);\n' >"$repo/app.js"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/app.js\"}}"
  assert_rc 0 "t_quality_tamper_notice_non_test_non_config_rc0 rc"
  rm -rf "$repo"
}

t_quality_tamper_notice_test_skip_added_rc2() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/tests"
  printf 'def test_a():\n    assert True\n\ndef test_b():\n    assert True\n' >"$repo/tests/foo_test.py"
  (cd "$repo" && git add tests/foo_test.py && git commit -q -m t) >/dev/null 2>&1
  printf 'def test_a():\n    assert True\n\n@pytest.mark.skip\ndef test_b():\n    assert True\n' >"$repo/tests/foo_test.py"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/tests/foo_test.py\"}}"
  assert_rc 2 "t_quality_tamper_notice_test_skip_added_rc2 rc"
  assert_contains "$ERR" "pytest.mark.skip" "t_quality_tamper_notice_test_skip_added_rc2 matched-line"
  assert_contains "$ERR" "You just disabled or weakened a check" "t_quality_tamper_notice_test_skip_added_rc2 message"
  rm -rf "$repo"
}

t_quality_tamper_notice_test_harmless_edit_rc0() {
  local repo
  repo=$(tmp_repo)
  printf 'def test_a():\n    assert True\n' >"$repo/foo.test.js"
  (cd "$repo" && git add foo.test.js && git commit -q -m t) >/dev/null 2>&1
  printf 'def test_a():\n    assert 1 == 1\n' >"$repo/foo.test.js"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/foo.test.js\"}}"
  assert_rc 0 "t_quality_tamper_notice_test_harmless_edit_rc0 rc"
  rm -rf "$repo"
}

t_quality_tamper_notice_untracked_new_test_with_skip_rc2() {
  local repo
  repo=$(tmp_repo)
  printf "it.skip('does a thing', () => {});\n" >"$repo/new.test.js"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/new.test.js\"}}"
  assert_rc 2 "t_quality_tamper_notice_untracked_new_test_with_skip_rc2 rc"
  assert_contains "$ERR" "it.skip" "t_quality_tamper_notice_untracked_new_test_with_skip_rc2 matched-line"
  rm -rf "$repo"
}

t_quality_tamper_notice_gate_config_threshold_weaken_rc2() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"maxFileLines": 400}\n' >"$repo/.claude/harness.json"
  (cd "$repo" && git add .claude/harness.json && git commit -q -m cfg) >/dev/null 2>&1
  printf '{"maxFileLines": 4000}\n' >"$repo/.claude/harness.json"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/.claude/harness.json\"}}"
  assert_rc 2 "t_quality_tamper_notice_gate_config_threshold_weaken_rc2 rc"
  assert_contains "$ERR" "4000" "t_quality_tamper_notice_gate_config_threshold_weaken_rc2 matched-line"
  rm -rf "$repo"
}

t_quality_tamper_notice_gate_config_stopgate_false_rc2() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"maxFileLines": 400}\n' >"$repo/.claude/harness.json"
  (cd "$repo" && git add .claude/harness.json && git commit -q -m cfg) >/dev/null 2>&1
  printf '{"maxFileLines": 400, "stopGate": false}\n' >"$repo/.claude/harness.json"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/.claude/harness.json\"}}"
  assert_rc 2 "t_quality_tamper_notice_gate_config_stopgate_false_rc2 rc"
  assert_contains "$ERR" "stopGate" "t_quality_tamper_notice_gate_config_stopgate_false_rc2 matched-line"
  rm -rf "$repo"
}

t_quality_tamper_notice_gate_config_harmless_change_rc0() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"maxFileLines": 400}\n' >"$repo/.claude/harness.json"
  (cd "$repo" && git add .claude/harness.json && git commit -q -m cfg) >/dev/null 2>&1
  printf '{"maxFileLines": 400, "sizeGuard": true}\n' >"$repo/.claude/harness.json"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/.claude/harness.json\"}}"
  assert_rc 0 "t_quality_tamper_notice_gate_config_harmless_change_rc0 rc"
  rm -rf "$repo"
}

t_quality_tamper_notice_not_git_repo_rc0() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/tests"
  printf "it.skip('x', () => {});\n" >"$d/tests/foo.test.js"
  run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$d/tests/foo.test.js\"}}"
  assert_rc 0 "t_quality_tamper_notice_not_git_repo_rc0 rc"
  rm -rf "$d"
}

# ---------------------------------------------------------------------------
# stop-gate.sh
# ---------------------------------------------------------------------------

t_quality_stop_gate_stop_hook_active_rc0_instant() {
  local repo
  repo=$(tmp_repo)
  run_hook "$SCAN_DIR/stop-gate.sh" '{"stop_hook_active":true}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_quality_stop_gate_stop_hook_active_rc0_instant rc"
  rm -rf "$repo"
}

t_quality_stop_gate_env_disabled_rc0() {
  local repo
  repo=$(tmp_repo)
  echo x >"$repo/f.txt"
  run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo" CC_NO_STOP_GATE=1
  assert_rc 0 "t_quality_stop_gate_env_disabled_rc0 rc"
  rm -rf "$repo"
}

t_quality_stop_gate_stopgate_false_rc0() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"stopGate": false}\n' >"$repo/.claude/harness.json"
  echo x >"$repo/f.txt"
  run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_quality_stop_gate_stopgate_false_rc0 rc"
  rm -rf "$repo"
}

t_quality_stop_gate_no_changes_rc0() {
  local repo
  repo=$(tmp_repo)
  run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
  assert_rc 0 "t_quality_stop_gate_no_changes_rc0 rc"
  rm -rf "$repo"
}

t_quality_stop_gate_not_git_repo_rc0() {
  local d
  d=$(tmp_dir)
  run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "t_quality_stop_gate_not_git_repo_rc0 rc"
  rm -rf "$d"
}

t_quality_stop_gate_both_shared_scripts_absent_rc0() {
  local repo
  repo=$(tmp_repo)
  echo x >"$repo/f.txt"
  run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$(tmp_dir)"
  assert_rc 0 "t_quality_stop_gate_both_shared_scripts_absent_rc0 rc"
  rm -rf "$repo"
}

t_quality_stop_gate_full_sweep_test_exit1_blocks() {
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  mkdir -p "$repo/.claude"
  printf '{"stopGate": true}\n' >"$repo/.claude/harness.json"
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-exit1"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_full_sweep_test_exit1_blocks rc"
  assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_full_sweep_test_exit1_blocks decision"
  assert_contains "$OUT" "test" "t_quality_stop_gate_full_sweep_test_exit1_blocks gate-name"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-exit1"
  rm -rf "$repo"
}

t_quality_stop_gate_full_sweep_test_exit0_passes() {
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  mkdir -p "$repo/.claude"
  printf '{"stopGate": true}\n' >"$repo/.claude/harness.json"
  printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-exit0"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_full_sweep_test_exit0_passes rc"
  assert_eq "$OUT" "" "t_quality_stop_gate_full_sweep_test_exit0_passes no-block"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-exit0"
  rm -rf "$repo"
}

t_quality_stop_gate_wedge_valve_fourth_failure_rc2() {
  local repo shared sid i out rc
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  mkdir -p "$repo/.claude"
  printf '{"stopGate": true}\n' >"$repo/.claude/harness.json"
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  sid="quality-wedge-$$"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-$sid"
  i=1
  while [ "$i" -le 4 ]; do
    run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
    if [ "$i" -lt 4 ]; then
      assert_rc 0 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 block-$i-rc"
      assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 block-$i-json"
    fi
    i=$((i + 1))
  done
  assert_rc 2 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 fourth-rc"
  assert_contains "$ERR" "already failing before this turn" "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 fourth-message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-$sid"
  rm -rf "$repo"
}

t_quality_stop_gate_manifest_deleted_blocks() {
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  mkdir -p "$repo/.claude"
  printf '{"stopGate": true}\n' >"$repo/.claude/harness.json"
  printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
  (cd "$repo" && git add package.json .claude/harness.json && git commit -q -m addpkg && git rm -q package.json) >/dev/null 2>&1
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_manifest_deleted_blocks rc"
  assert_contains "$OUT" "manifest disappeared this turn" "t_quality_stop_gate_manifest_deleted_blocks message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-manifest-del"
  rm -rf "$repo"
}

t_quality_stop_gate_manifest_created_via_rename_not_blocked() {
  # A rename whose NEW side is a manifest (`git mv foo.json package.json`)
  # creates the manifest; it must never be mistaken for the manifest
  # disappearing, even though the resulting package.json (here: no
  # "scripts" block) still leaves check-all reporting no ecosystem.
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf '{"name":"x"}\n' >"$repo/foo.json"
  (cd "$repo" && git add foo.json && git commit -q -m addfoo && git mv foo.json package.json) >/dev/null 2>&1
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-create"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_manifest_created_via_rename_not_blocked rc"
  assert_not_contains "$OUT" "manifest disappeared this turn" "t_quality_stop_gate_manifest_created_via_rename_not_blocked no-block-message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-manifest-rename-create"
  rm -rf "$repo"
}

t_quality_stop_gate_manifest_renamed_away_blocks() {
  # A rename whose OLD side is the manifest (`git mv package.json
  # backup.json`) is the manifest disappearing from its path, same as a
  # plain delete — must still block.
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
  (cd "$repo" && git add package.json && git commit -q -m addpkg && git mv package.json backup.json) >/dev/null 2>&1
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-away"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_manifest_renamed_away_blocks rc"
  assert_contains "$OUT" "manifest disappeared this turn" "t_quality_stop_gate_manifest_renamed_away_blocks message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-manifest-rename-away"
  rm -rf "$repo"
}

t_quality_stop_gate_manifest_lookalike_deleted_not_blocked() {
  # Deleting a file whose name merely contains "package.json" as a
  # substring (package.json.orig) must never be mistaken for the manifest
  # disappearing — matching is by exact basename, not substring.
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf '{"name":"x"}\n' >"$repo/package.json.orig"
  (cd "$repo" && git add package.json.orig && git commit -q -m addorig && git rm -q package.json.orig) >/dev/null 2>&1
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-lookalike-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_manifest_lookalike_deleted_not_blocked rc"
  assert_not_contains "$OUT" "manifest disappeared this turn" "t_quality_stop_gate_manifest_lookalike_deleted_not_blocked no-block-message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-manifest-lookalike-del"
  rm -rf "$repo"
}

t_quality_stop_gate_manifest_renamed_to_plain_name_blocks() {
  # `git mv package.json x` — a rename whose OLD side is the manifest —
  # still blocks even when the new name is a short, unrelated basename.
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
  (cd "$repo" && git add package.json && git commit -q -m addpkg && git mv package.json x) >/dev/null 2>&1
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-to-x"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_manifest_renamed_to_plain_name_blocks rc"
  assert_contains "$OUT" "manifest disappeared this turn" "t_quality_stop_gate_manifest_renamed_to_plain_name_blocks message"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-manifest-rename-to-x"
  rm -rf "$repo"
}

t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep() {
  local repo shared
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  # No harness.json => default "scoped" mode. package.json is untracked, so
  # test-changed's own git-diff-based detection reports no changed files
  # (test_cmd:""), so stop-gate falls through to the check-all full sweep,
  # which does see the untracked file via git status --porcelain (C3) and
  # runs `npm run test` for real.
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-fallthrough"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep rc"
  assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep blocked-by-full-sweep"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-fallthrough"
  rm -rf "$repo"
}

# _quality_gates_stamp_path <repo> — mirrors stop-gate.sh's own
# ${TMPDIR:-/tmp}/claude-gates-<repo-basename>-<8-char cksum hash of
# toplevel path> computation exactly, so tests can pre-seed or inspect the
# periodic full-sweep timer stamp for a given tmp_repo.
_quality_gates_stamp_path() {
  local repo toplevel tmp hash_num hash8 base
  repo=$1
  toplevel=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
  [ -z "$toplevel" ] && toplevel="$repo"
  tmp="${TMPDIR:-/tmp}"
  tmp="${tmp%/}"
  hash_num=$(printf '%s' "$toplevel" | cksum | awk '{print $1}')
  hash8=$(printf '%s' "$hash_num" | tail -c 8)
  base=$(basename "$toplevel")
  printf '%s/claude-gates-%s-%s' "$tmp" "$base" "$hash8"
}

t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep() {
  # C10 "scoped" mode: a tracked, uncommitted-modified test file whose test
  # command fails must be blocked directly off test-changed's own
  # passed:false JSON, without ever running the check-all full sweep. The
  # reason text is test-changed's own ("Gate failed: test-changed (...)"),
  # never the full-sweep's ("Gate(s) failed: <name>\n<output>").
  local repo shared stamp
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf 'test("x", () => { expect(1).toBe(1); });\n' >"$repo/app.test.js"
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  (cd "$repo" && git add app.test.js package.json && git commit -q -m tests) >/dev/null 2>&1
  # Modify the test file this turn (uncommitted) — test-changed picks it up
  # via its own unstaged-diff detection and runs it for real.
  printf 'test("x", () => { expect(1).toBe(2); });\n' >"$repo/app.test.js"
  stamp=$(_quality_gates_stamp_path "$repo")
  rm -f "$stamp"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-tc-direct"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep rc"
  assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep decision"
  assert_contains "$OUT" "test-changed (" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep reason-is-test-changed"
  assert_contains "$OUT" "app.test.js" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep names-test-file"
  assert_not_contains "$OUT" "Gate(s) failed:" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep no-full-sweep-reason"
  assert_file_missing "$stamp" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep no-full-sweep-ran"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-tc-direct"
  rm -rf "$repo"
}

t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks() {
  # C10 "scoped" mode: when the scoped test-changed run is green (here: a
  # tracked source file changed with no matching test file, so test-changed
  # itself reports passed:true), stop-gate must additionally run the full
  # sweep once stopGateFullEverySec has elapsed since the last full sweep —
  # and block on that full sweep's own failure, distinct from test-changed.
  local repo shared stamp
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf 'module.exports = 1;\n' >"$repo/util.js"
  printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
  (cd "$repo" && git add util.js package.json && git commit -q -m src) >/dev/null 2>&1
  printf 'module.exports = 2;\n' >"$repo/util.js"
  mkdir -p "$repo/.claude"
  printf '{"stopGateFullEverySec": 5}\n' >"$repo/.claude/harness.json"
  stamp=$(_quality_gates_stamp_path "$repo")
  echo 1 >"$stamp"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-periodic-block"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks rc"
  assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks decision"
  assert_contains "$OUT" "Gate(s) failed:" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks full-sweep-reason"
  assert_not_contains "$OUT" "test-changed (" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks not-test-changed-reason"
  assert_eq "$(cat "$stamp")" "1" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks stamp-unchanged-on-fail"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-periodic-block" "$stamp"
  rm -rf "$repo"
}

t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass() {
  # Same promotion as above, but with a passing full sweep: the turn must
  # not be blocked, and the periodic-sweep stamp must be rewritten to a
  # fresh epoch (proving the promoted sweep actually ran, not just that the
  # turn passed because nothing was checked).
  local repo shared stamp before after rewritten
  repo=$(tmp_repo)
  shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
  printf 'module.exports = 1;\n' >"$repo/util.js"
  printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
  (cd "$repo" && git add util.js package.json && git commit -q -m src) >/dev/null 2>&1
  printf 'module.exports = 2;\n' >"$repo/util.js"
  mkdir -p "$repo/.claude"
  printf '{"stopGateFullEverySec": 5}\n' >"$repo/.claude/harness.json"
  stamp=$(_quality_gates_stamp_path "$repo")
  before=1
  echo "$before" >"$stamp"
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-periodic-pass"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
  assert_rc 0 "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass rc"
  assert_eq "$OUT" "" "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass no-block"
  after=$(cat "$stamp" 2>/dev/null)
  case "$after" in '' | *[!0-9]*) after=0 ;; esac
  rewritten="no"
  [ "$after" -gt "$before" ] && rewritten="yes"
  assert_eq "$rewritten" "yes" "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass stamp-rewritten (before=$before after=$after)"
  rm -f "${TMPDIR:-/tmp}/claude-gatesig-quality-periodic-pass" "$stamp"
  rm -rf "$repo"
}

# C16: only a ROOT-level manifest deletion blocks; nested manifests never do.
t_quality_stop_gate_nested_manifest_deletion_does_not_block() {
  d=$(tmp_repo)
  _prev=$PWD
  cd "$d" || return 1
  mkdir -p node_modules/dep
  printf '{"name":"dep"}\n' >node_modules/dep/package.json
  git add -A && git commit -q -m "add nested manifest"
  git rm -q node_modules/dep/package.json
  run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"nested-manifest","stop_hook_active":false}' \
    CLAUDE_PROJECT_DIR="$d" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
  cd "$_prev" || return 1
  assert_rc 0 "nested manifest deletion: rc 0"
  assert_not_contains "$OUT" "manifest disappeared" "nested manifest deletion: no block"
}
