#!/usr/bin/env bash
# test_map.sh — unit W6 (codebase map) tests for the SessionStart hook
# codebase-map.sh. Sourced by run.sh; every t_map_* function below is
# discovered and run. HERE (this dir) and SCAN_DIR (its parent, "hooks/")
# are set by run.sh. The generator script itself (scripts/codebase-map)
# is exercised separately by scripts/tests/test_map_script.sh (t_mapscript_*).
set -u

MAP_HOOK="$SCAN_DIR/codebase-map.sh"

# _map_full_toolbin <dir> — populate <dir> with symlinks to every external
# command the hook and the codebase-map generator need, EXCLUDING jq, so a
# PATH pointed only at it truly lacks jq rather than merely shadowing it
# (a fake executable named "jq" earlier in PATH would still satisfy
# `command -v jq`, which is not what "jq absent" means here).
_map_full_toolbin() {
  local d="$1" tool
  mkdir -p "$d"
  for tool in bash dirname cat printf sed awk grep git head wc tr mkdir \
    mktemp date cksum rm cp sort basename env true false; do
    if cmdpath=$(command -v "$tool" 2>/dev/null); then
      ln -s "$cmdpath" "$d/$tool"
    fi
  done
}

t_map_disabled_by_default_no_output() {
  local repo
  repo=$(tmp_repo)
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_map_disabled_by_default_no_output rc"
  assert_eq "$OUT" "" "t_map_disabled_by_default_no_output no-stdout"
  assert_file_missing "$repo/.claude/codebase-map.md" "t_map_disabled_by_default_no_output no-map-file"
  rm -rf "$repo"
}

t_map_disabled_explicit_false_no_output() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": false}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_map_disabled_explicit_false_no_output rc"
  assert_eq "$OUT" "" "t_map_disabled_explicit_false_no_output no-stdout"
  rm -rf "$repo"
}

t_map_enabled_true_prints_one_line() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "t_map_enabled_true_prints_one_line rc"
  assert_contains "$OUT" "codebase map: .claude/codebase-map.md (" "t_map_enabled_true_prints_one_line summary-prefix"
  assert_contains "$OUT" "leads only; verify every path before use" "t_map_enabled_true_prints_one_line teaching-suffix"
  rm -rf "$repo"
}

t_map_enabled_writes_map_file() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  assert_file_exists "$repo/.claude/codebase-map.md" "t_map_enabled_writes_map_file map-file-exists"
  rm -rf "$repo"
}

t_map_enabled_output_is_single_line() {
  local repo lines
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  lines=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
  assert_eq "$lines" "1" "t_map_enabled_output_is_single_line exactly-one-line"
  rm -rf "$repo"
}

t_map_enabled_output_has_matching_head_sha() {
  local repo sha
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  sha=$(git -C "$repo" rev-parse --short HEAD)
  assert_contains "$OUT" "head $sha)" "t_map_enabled_output_has_matching_head_sha sha-in-summary"
  rm -rf "$repo"
}

t_map_enabled_output_line_count_matches_file() {
  local repo n_reported n_actual
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  n_reported=$(printf '%s' "$OUT" | sed -n 's/.*(\([0-9]*\) lines,.*/\1/p')
  n_actual=$(wc -l <"$repo/.claude/codebase-map.md" | tr -d ' ')
  assert_eq "$n_reported" "$n_actual" "t_map_enabled_output_line_count_matches_file reported-n-matches-wc"
  rm -rf "$repo"
}

t_map_missing_jq_treated_as_absent() {
  local repo toolbin
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  toolbin=$(tmp_dir)
  _map_full_toolbin "$toolbin"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo" PATH="$toolbin"
  assert_rc 0 "t_map_missing_jq_treated_as_absent rc"
  assert_eq "$OUT" "" "t_map_missing_jq_treated_as_absent no-stdout-when-jq-absent"
  rm -rf "$repo" "$toolbin"
}

t_map_not_git_repo_silent_no_crash() {
  local d
  d=$(tmp_dir)
  mkdir -p "$d/.claude"
  printf '{"codebaseMap": true}\n' >"$d/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "t_map_not_git_repo_silent_no_crash rc"
  assert_eq "$OUT" "" "t_map_not_git_repo_silent_no_crash no-stdout"
  rm -rf "$d"
}

t_map_falls_back_to_sibling_script_when_home_script_missing() {
  local repo
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo" HOME=/nonexistent-home-for-codebase-map-test
  assert_rc 0 "t_map_falls_back_to_sibling_script_when_home_script_missing rc"
  assert_contains "$OUT" "codebase map: .claude/codebase-map.md (" "t_map_falls_back_to_sibling_script_when_home_script_missing still-runs-via-sibling-fallback"
  assert_file_exists "$repo/.claude/codebase-map.md" "t_map_falls_back_to_sibling_script_when_home_script_missing map-file-written"
  rm -rf "$repo"
}

t_map_second_invocation_still_prints_summary_line() {
  # The generator itself prints "unchanged" on a no-op second run, but the
  # hook always reports its own one-line summary from the file on disk,
  # regardless of whether the generator rewrote it this turn.
  local repo out1 out2
  repo=$(tmp_repo)
  mkdir -p "$repo/.claude"
  printf '{"codebaseMap": true}\n' >"$repo/.claude/flow.config.json"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  out1="$OUT"
  run_hook "$MAP_HOOK" '{}' CLAUDE_PROJECT_DIR="$repo"
  out2="$OUT"
  assert_eq "$out2" "$out1" "t_map_second_invocation_still_prints_summary_line same-summary-on-unchanged-rerun"
  assert_contains "$out2" "leads only; verify every path before use" "t_map_second_invocation_still_prints_summary_line still-has-teaching-suffix"
  rm -rf "$repo"
}

t_map_hook_is_well_formed() {
  if [ -x "$MAP_HOOK" ]; then
    _pass "t_map_hook_is_well_formed executable"
  else
    _fail "t_map_hook_is_well_formed executable" "not executable: $MAP_HOOK"
  fi
  if head -1 "$MAP_HOOK" | grep -q '^#!/usr/bin/env bash$'; then
    _pass "t_map_hook_is_well_formed portable-shebang"
  else
    _fail "t_map_hook_is_well_formed portable-shebang"
  fi
  if grep -q '^set -u' "$MAP_HOOK"; then
    _pass "t_map_hook_is_well_formed sets-u"
  else
    _fail "t_map_hook_is_well_formed sets-u"
  fi
  if grep -q 'set -e' "$MAP_HOOK"; then
    _fail "t_map_hook_is_well_formed no-set-e" "hooks must never set -e"
  else
    _pass "t_map_hook_is_well_formed no-set-e"
  fi
  run_cmd bash -n "$MAP_HOOK"
  assert_rc 0 "t_map_hook_is_well_formed bash-n"
}
