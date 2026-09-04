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
    assert_contains "$OUT" "/lesson" "nudge fires: $p"
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
  assert_contains "$OUT" "run /lesson" "second identical deny: nudge"
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
  assert_contains "$ERR" "run /lesson" "second identical feedback: nudge on stderr"
  rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid" "${TMPDIR:-/tmp}/claude-lesson-${sid}-b"; rm -rf "$d"
}
