#!/usr/bin/env bash
# test_lesson_mine.sh — lesson-mine, the /lesson --retro transcript extractor.
# Sourced by run.sh; HERE and SCAN_DIR are set.
set -u

MINE="$SCAN_DIR/lesson-mine"
MINE_FIX="$HERE/fixtures/lesson-mine"

# lm_rows <kind>: "line:text" for each output row of that kind, from $OUT.
lm_rows() {
	printf '%s\n' "$OUT" | python3 -I -c '
import json, sys
for raw in sys.stdin:
    if raw.strip():
        r = json.loads(raw)
        if r["kind"] == sys.argv[1]:
            print("%s:%s" % (r["line"], r["text"]))' "$1"
}

t_lesson_mine_help_and_usage() {
	run_cmd "$MINE" --help
	assert_rc 0 "lesson-mine --help exits 0"
	assert_contains "$OUT" "Usage: lesson-mine" "help shows usage"
	run_cmd "$MINE"
	assert_rc 2 "no session file is a usage error"
	run_cmd "$MINE" /no/such/session.jsonl
	assert_rc 2 "an unreadable file exits 2"
	assert_contains "$ERR" "cannot read" "says which file"
}

# The transcript holds, under the user role: a first human turn before any tool use, a
# system-reminder, hook feedback, an isMeta line, a tool_result that says "no, don't", and
# a thank-you. None is a correction. Two real corrections after tool use are.
t_lesson_mine_only_real_human_turns_count_as_corrections() {
	run_cmd "$MINE" "$MINE_FIX/session.jsonl"
	assert_rc 0 "exit 0"
	local got
	got=$(lm_rows correction | cut -d: -f1 | tr '\n' ' ')
	assert_eq "$got" "9 16 " "corrections are exactly lines 9 and 16"
	assert_contains "$(lm_rows correction)" "9:no, don't do that - use the existing helper in cart_utils instead" "the real correction is kept in full"
	assert_not_contains "$OUT" "system-reminder" "the system-reminder never appears"
	assert_not_contains "$OUT" "Stop hook feedback" "hook output never appears as a correction"
	assert_not_contains "$OUT" "run the gates before you stop" "hook feedback text is dropped"
	assert_not_contains "$OUT" "stop waiting" "an injected task-notification is not a correction"
	assert_not_contains "$OUT" "don't touch this file" "a tool_result is never a correction"
	assert_not_contains "$OUT" "don't use pytest" "a first turn before any tool use is not a correction"
	assert_not_contains "$OUT" "thanks, that looks good" "a turn with no correction cue is not a row"
}

t_lesson_mine_reverts_hook_blocks_and_skills() {
	run_cmd "$MINE" "$MINE_FIX/session.jsonl"
	assert_eq "$(lm_rows revert)" "5:git revert --no-edit HEAD" "the revert command"
	assert_contains "$(lm_rows hook_block)" "6:PreToolUse:Bash hook blocked this command" "a tool_result hook block"
	assert_contains "$(lm_rows hook_block)" "15:PreToolUse:Bash: BLOCKED: rm -rf outside the project" "an attachment hook block"
	assert_eq "$(lm_rows skill_invoked | tr '\n' ' ')" "3:flow:fix 14:flow:next " "one row per distinct skill, at its first use"
}

t_lesson_mine_row_shape_and_text_cap() {
	local long
	long=$(python3 -I -c 'print("x" * 900)')
	local f
	f=$(tmp_dir)/s.jsonl
	{
		printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"a","name":"Read","input":{}}]}}\n'
		printf '{"type":"user","message":{"role":"user","content":"no, wrong %s"}}\n' "$long"
	} >"$f"
	run_cmd "$MINE" "$f"
	assert_eq "$(printf '%s\n' "$OUT" | python3 -I -c 'import json,sys; r=json.loads(sys.stdin.readline()); print(sorted(r), len(r["text"]))')" \
		"['kind', 'line', 'session', 'text'] 300" "keys and the 300-char cap"
}

t_lesson_mine_may_have_fired_skips_skills_the_session_invoked() {
	run_cmd "$MINE" --skills "$MINE_FIX/skills" "$MINE_FIX/session.jsonl"
	assert_rc 0 "exit 0"
	local corr
	corr=$(printf '%s\n' "$OUT" | grep '"kind": "correction"')
	assert_contains "$(printf '%s\n' "$corr" | sed -n 1p)" '"may_have_fired": ["helper-reuse"]' "line 9 matches helper-reuse, not the invoked fix skill"
	assert_not_contains "$(printf '%s\n' "$corr" | sed -n 1p)" '"fix"' "an invoked skill is never suggested"
	assert_contains "$(printf '%s\n' "$corr" | sed -n 2p)" '"may_have_fired": ["lockfile-guard"]' "line 16 matches lockfile-guard"
	run_cmd "$MINE" "$MINE_FIX/session.jsonl"
	assert_not_contains "$OUT" "may_have_fired" "no hint without --skills"
}

# A 5 MB session (one record over 1 MB) comes out under 20 KB.
t_lesson_mine_five_mb_session_stays_small() {
	local f bytes size
	f=$(tmp_dir)/big.jsonl
	python3 -I - "$f" <<'PY'
import json, sys
with open(sys.argv[1], "w") as fh:
    pad = "z" * 1200000
    fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "x", "content": pad}]}}) + "\n")
    for i in range(4000):
        fh.write(json.dumps({"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "id": "u%d" % i, "name": "Bash", "input": {"command": "git revert --no-edit HEAD~%d  # %s" % (i, "p" * 200)}}]}}) + "\n")
        fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": "no, don't do that, number %d: %s" % (i, "q" * 250)}}) + "\n")
        fh.write(json.dumps({"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "tool_use_id": "u%d" % i, "content": "PreToolUse:Bash hook blocked this command (%d) %s" % (i, "r" * 100)}]}}) + "\n")
PY
	size=$(wc -c <"$f" | tr -d ' ')
	if [ "$size" -ge 5000000 ]; then _pass "synthetic session is at least 5 MB ($size bytes)"; else _fail "synthetic session is at least 5 MB" "$size bytes"; fi
	run_cmd "$MINE" "$f"
	assert_rc 0 "exit 0"
	bytes=$(printf '%s\n' "$OUT" | wc -c | tr -d ' ')
	if [ "$bytes" -lt 20000 ]; then _pass "output is under 20 KB ($bytes bytes)"; else _fail "output is under 20 KB" "$bytes bytes"; fi
	assert_contains "$OUT" '"kind": "correction"' "corrections are present"
	run_cmd "$MINE" --max-bytes 3000 "$f"
	bytes=$(printf '%s\n' "$OUT" | wc -c | tr -d ' ')
	if [ "$bytes" -le 3000 ]; then _pass "--max-bytes 3000 holds ($bytes bytes)"; else _fail "--max-bytes 3000 holds" "$bytes bytes"; fi
	assert_contains "$ERR" "capped" "says it dropped rows"
	assert_contains "$OUT" '"kind": "correction"' "corrections survive the cap, lower-priority kinds go first"
}

t_lesson_skill_uses_lesson_mine_rows_only() {
	local s
	s=$(cat "$SCAN_DIR/../skills/lesson/SKILL.md")
	assert_contains "$s" 'scripts/lesson-mine' "the skill names the extractor"
	assert_contains "$s" 'never a raw jsonl' "subagents get rows, never a raw jsonl"
	assert_contains "$s" 'system reminders and hook output arrive under the user role' "the skill says why"
	assert_contains "$s" 'Missed trigger' "the skill has the missed-trigger step"
	assert_contains "$s" 'not in that session' "tune description only for a skill the session did not invoke"
}
