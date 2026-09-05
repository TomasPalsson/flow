#!/usr/bin/env bash
# lesson-nudge.sh (UserPromptSubmit) and the repeat counter in hook_deny /
# hook_block / hook_feedback: the deterministic "/lesson" triggers.

_ln_json() { printf '{"session_id":"%s","prompt":%s}' "$1" "$(printf '%s' "$2" | jq -Rs .)"; }

t_lesson_nudge_fires_on_corrections() {
  local p
  for p in "You deleted the wrong file again" "don't do that again" "Why did you push to main?" \
           "that's wrong, the tests were fine" "you keep editing the generated file" "Not what I asked for." \
           "you changed the config without asking" "you always forget the tests"; do
    run_hook "$SCAN_DIR/lesson-nudge.sh" "$(_ln_json ln-pos "$p")"
    assert_rc 0 "nudge rc 0: $p"
    assert_contains "$OUT" "offer /lesson" "nudge fires as a suggestion: $p"
  done
}

t_lesson_nudge_silent_on_plain_prompts() {
  local p
  for p in "add tests for the parser" "don't forget to run the formatter" "you can use bun for this" \
           "/flow add a login page" "what does this function do?" "again, the goal is a green suite" \
           "why did you choose this approach?" "you added a great feature" "you used bun, nice" \
           "why are you using a queue here?" "you did well on the parser" "you changed the API, good"; do
    run_hook "$SCAN_DIR/lesson-nudge.sh" "$(_ln_json ln-neg "$p")"
    assert_rc 0 "silent rc 0: $p"
    assert_eq "$OUT" "" "no nudge: $p"
  done
}

t_lesson_nudge_env_escape_and_empty_input() {
  run_hook "$SCAN_DIR/lesson-nudge.sh" "$(_ln_json ln-esc "you deleted it again")" CC_NO_LESSON_NUDGE=1
  assert_rc 0 "escape rc 0"
  assert_eq "$OUT" "" "CC_NO_LESSON_NUDGE=1 silences the nudge"
  run_hook "$SCAN_DIR/lesson-nudge.sh" ''
  assert_rc 0 "empty stdin rc 0"
  assert_eq "$OUT" "" "empty stdin: nothing printed"
}

# A throwaway hook that denies with a fixed reason, to exercise the counter.
_ln_deny_script() {
  local d=$1
  cat >"$d/deny-x.sh" <<SH
#!/usr/bin/env bash
. "$SCAN_DIR/lib/hookout.sh"
hook_deny "\$DENY_REASON"
SH
  cat >"$d/fb-x.sh" <<SH
#!/usr/bin/env bash
. "$SCAN_DIR/lib/hookout.sh"
hook_feedback "\$DENY_REASON"
SH
  printf '%s' "$d/deny-x.sh"
}

t_lesson_counter_second_identical_deny_nudges() {
  local d s sid
  d=$(tmp_dir); s=$(_ln_deny_script "$d"); sid="ln-cnt-$$"
  rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid"
  run_hook "$s" "{\"session_id\":\"$sid\"}" DENY_REASON="git push --force is blocked"
  assert_rc 0 "first deny rc 0"
  assert_contains "$OUT" '"permissionDecision":"deny"' "first deny is a deny"
  assert_not_contains "$OUT" "/lesson" "first deny: no nudge"
  run_hook "$s" "{\"session_id\":\"$sid\"}" DENY_REASON="git push --force is blocked"
  assert_contains "$OUT" "suggest /lesson" "second identical deny: suggestion"
  assert_contains "$OUT" "blocked 2 times" "second identical deny: count"
  assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecision')" "deny" "nudged deny is still valid JSON"
  run_hook "$s" "{\"session_id\":\"$sid\"}" DENY_REASON="a different reason"
  assert_not_contains "$OUT" "/lesson" "different reason: no nudge"
  rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid"; rm -rf "$d"
}

t_lesson_counter_feedback_and_sessions_isolated() {
  local d sid
  d=$(tmp_dir); _ln_deny_script "$d" >/dev/null; sid="ln-fb-$$"
  rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid" "${TMPDIR:-/tmp}/claude-lesson-${sid}-b"
  run_hook "$d/fb-x.sh" "{\"session_id\":\"$sid\"}" DENY_REASON="file too long"
  assert_rc 2 "feedback rc 2"
  assert_not_contains "$ERR" "/lesson" "first feedback: no nudge"
  run_hook "$d/fb-x.sh" "{\"session_id\":\"${sid}-b\"}" DENY_REASON="file too long"
  assert_not_contains "$ERR" "/lesson" "other session: no nudge"
  run_hook "$d/fb-x.sh" "{\"session_id\":\"$sid\"}" DENY_REASON="file too long"
  assert_rc 2 "second feedback rc 2"
  assert_contains "$ERR" "suggest /lesson" "second identical feedback: suggestion on stderr"
  rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid" "${TMPDIR:-/tmp}/claude-lesson-${sid}-b"; rm -rf "$d"
}

# Git is the enforcement boundary: per-file hooks skip files outside any
# repo and git-ignored files (scratch scripts, build output).
t_hooks_skip_files_outside_git_and_ignored() {
  local d repo f json
  d=$(tmp_dir); repo=$(tmp_repo)
  # 1. a file outside any git repo: size-guard and format-lint say nothing
  f="$d/scratch.py"; : >"$f"; i=0; while [ $i -lt 500 ]; do printf 'x = %s\n' "$i" >>"$f"; i=$((i + 1)); done
  json=$(printf '{"session_id":"gm-1","tool_input":{"file_path":"%s"}}' "$f")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "outside git: size-guard rc 0"; assert_eq "$ERR" "" "outside git: size-guard silent on a 500-line file"
  run_hook "$SCAN_DIR/format-lint.sh" "$json" CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "outside git: format-lint rc 0"; assert_eq "$ERR" "" "outside git: format-lint silent"
  # 2. the same file inside a repo but git-ignored: still silent
  mkdir -p "$repo/scratch"; printf 'scratch/\n' >"$repo/.gitignore"; git -C "$repo" add .gitignore >/dev/null; git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ignore; cp "$f" "$repo/scratch/gen.py"
  json=$(printf '{"session_id":"gm-2","tool_input":{"file_path":"%s"}}' "$repo/scratch/gen.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 0 "ignored: size-guard rc 0"; assert_eq "$ERR" "" "ignored: size-guard silent"
  # 3. tracked-or-untracked source inside the repo: measured (feedback, rc 2)
  cp "$f" "$repo/src.py"
  json=$(printf '{"session_id":"gm-3","tool_input":{"file_path":"%s"}}' "$repo/src.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 2 "managed: size-guard reports the oversized file"
  # 4. escape hatch: CC_HOOKS_ALL_FILES=1 measures the ignored file too
  # 5. an ignore rule added but not committed does not exempt anything
  printf 'src.py\n' >>"$repo/.gitignore"
  json=$(printf '{"session_id":"gm-5","tool_input":{"file_path":"%s"}}' "$repo/src.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
  assert_rc 2 "uncommitted .gitignore rule: file still measured"
  git -C "$repo" checkout -q -- .gitignore
  json=$(printf '{"session_id":"gm-4","tool_input":{"file_path":"%s"}}' "$repo/scratch/gen.py")
  run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo" CC_HOOKS_ALL_FILES=1
  assert_rc 2 "CC_HOOKS_ALL_FILES=1: ignored file measured"
  rm -rf "$d" "$repo"
}
