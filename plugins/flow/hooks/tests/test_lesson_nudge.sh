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
	d=$(tmp_dir)
	s=$(_ln_deny_script "$d")
	sid="ln-cnt-$$"
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
	rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid"
	rm -rf "$d"
}

t_lesson_counter_feedback_and_sessions_isolated() {
	local d sid
	d=$(tmp_dir)
	_ln_deny_script "$d" >/dev/null
	sid="ln-fb-$$"
	rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid" "${TMPDIR:-/tmp}/claude-lesson-${sid}-b"
	run_hook "$d/fb-x.sh" "{\"session_id\":\"$sid\"}" DENY_REASON="file too long"
	assert_rc 2 "feedback rc 2"
	assert_not_contains "$ERR" "/lesson" "first feedback: no nudge"
	run_hook "$d/fb-x.sh" "{\"session_id\":\"${sid}-b\"}" DENY_REASON="file too long"
	assert_not_contains "$ERR" "/lesson" "other session: no nudge"
	run_hook "$d/fb-x.sh" "{\"session_id\":\"$sid\"}" DENY_REASON="file too long"
	assert_rc 2 "second feedback rc 2"
	assert_contains "$ERR" "suggest /lesson" "second identical feedback: suggestion on stderr"
	rm -f "${TMPDIR:-/tmp}/claude-lesson-$sid" "${TMPDIR:-/tmp}/claude-lesson-${sid}-b"
	rm -rf "$d"
}

# Git is the enforcement boundary: per-file hooks skip files outside any
# repo and git-ignored files (scratch scripts, build output).
t_hooks_skip_files_outside_git_and_ignored() {
	local d repo f json
	d=$(tmp_dir)
	repo=$(tmp_repo)
	# 1. a file outside any git repo: size-guard and format-lint say nothing
	f="$d/scratch.py"
	: >"$f"
	i=0
	while [ $i -lt 500 ]; do
		printf 'x = %s\n' "$i" >>"$f"
		i=$((i + 1))
	done
	json=$(printf '{"session_id":"gm-1","tool_input":{"file_path":"%s"}}' "$f")
	run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "outside git: size-guard rc 0"
	assert_eq "$ERR" "" "outside git: size-guard silent on a 500-line file"
	run_hook "$SCAN_DIR/format-lint.sh" "$json" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "outside git: format-lint rc 0"
	assert_eq "$ERR" "" "outside git: format-lint silent"
	# 2. the same file inside a repo but git-ignored: still silent
	mkdir -p "$repo/scratch"
	printf 'scratch/\n' >"$repo/.gitignore"
	git -C "$repo" add .gitignore >/dev/null
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ignore
	cp "$f" "$repo/scratch/gen.py"
	json=$(printf '{"session_id":"gm-2","tool_input":{"file_path":"%s"}}' "$repo/scratch/gen.py")
	run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "ignored: size-guard rc 0"
	assert_eq "$ERR" "" "ignored: size-guard silent"
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

# A throwaway hook that denies with the reason in $REASON, to exercise the
# fire recorder inside _lesson_nudge for marker reasons (B5..B8).
_fires_deny_script() {
	local d=$1
	cat >"$d/deny-fires.sh" <<SH
#!/usr/bin/env bash
. "$SCAN_DIR/lib/hookout.sh"
hook_deny "\$REASON"
SH
	printf '%s' "$d/deny-fires.sh"
}

t_lesson_fires_B5_marker_reason_counts_silently() {
	local scriptdir proj s sid reason log first_out line1 line2 fields1 fields2 stamp1
	scriptdir=$(tmp_dir)
	proj=$(tmp_dir)
	s=$(_fires_deny_script "$scriptdir")
	sid="fires-b5-$$"
	reason="no push --force [lesson(2026-09-05): push --force in heredoc]"
	log="$proj/.claude/lesson-fires.log"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B5 first deny rc 0"
	assert_not_contains "$OUT" "/lesson" "B5 first deny: no nudge in stdout"
	assert_eq "$ERR" "" "B5 first deny: nothing on stderr"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "$reason" "B5 first deny: reason printed verbatim"
	first_out=$OUT
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B5 second deny rc 0"
	assert_not_contains "$OUT" "/lesson" "B5 second deny: still no nudge"
	assert_eq "$OUT" "$first_out" "B5 second deny: stdout byte-identical to the first (no nudge, no count text)"
	assert_file_exists "$log" "B5 fire log created"
	line1=$(sed -n '1p' "$log")
	line2=$(sed -n '2p' "$log")
	fields1=$(printf '%s' "$line1" | awk -F'\t' '{print NF}')
	fields2=$(printf '%s' "$line2" | awk -F'\t' '{print NF}')
	assert_eq "$fields1" "4" "B5 fire line 1 has 4 tab-separated fields"
	assert_eq "$fields2" "4" "B5 fire line 2 has 4 tab-separated fields"
	assert_eq "$(printf '%s' "$line1" | awk -F'\t' '{print $1}')" "2026-09-05" "B5 fire line 1 date"
	assert_eq "$(printf '%s' "$line1" | awk -F'\t' '{print $2}')" "push --force in heredoc" "B5 fire line 1 what"
	assert_eq "$(printf '%s' "$line1" | awk -F'\t' '{print $4}')" "deny-fires.sh" "B5 fire line 1 hook basename"
	assert_eq "$(printf '%s' "$line2" | awk -F'\t' '{print $1}')" "2026-09-05" "B5 fire line 2 date"
	assert_eq "$(printf '%s' "$line2" | awk -F'\t' '{print $2}')" "push --force in heredoc" "B5 fire line 2 what"
	stamp1=$(printf '%s' "$line1" | awk -F'\t' '{print $3}')
	case "$stamp1" in
	[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) _pass "B5 fire line 1 timestamp is UTC ISO-8601 Z" ;;
	*) _fail "B5 fire line 1 timestamp is UTC ISO-8601 Z" "got: $stamp1" ;;
	esac
	rm -rf "$scriptdir" "$proj"
}

t_lesson_fires_B6_plain_reason_unchanged() {
	local scriptdir proj s sid reason log
	scriptdir=$(tmp_dir)
	proj=$(tmp_dir)
	s=$(_fires_deny_script "$scriptdir")
	sid="fires-b6-$$"
	reason="git push --force is blocked"
	log="$proj/.claude/lesson-fires.log"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B6 first deny rc 0"
	assert_not_contains "$OUT" "/lesson" "B6 first deny: no nudge (first occurrence)"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B6 second deny rc 0"
	assert_contains "$OUT" "suggest /lesson" "B6 second identical plain deny: nudge fires as before"
	assert_contains "$OUT" "blocked 2 times" "B6 second identical plain deny: count text as before"
	assert_file_missing "$log" "B6 no fire log for a marker-less reason"
	rm -rf "$scriptdir" "$proj"
}

t_lesson_fires_B7_unwritable_is_swallowed() {
	local scriptdir projA projB s sidA sidB reason outA outB errB rcB
	if [ "$(id -u)" = "0" ]; then
		_pass "B7: unwritable project dir swallowed (skipped: running as root)"
		return
	fi
	scriptdir=$(tmp_dir)
	s=$(_fires_deny_script "$scriptdir")
	reason="blocked [lesson(2026-09-05): unwritable case]"
	projA=$(tmp_dir)
	sidA="fires-b7a-$$"
	run_hook "$s" "{\"session_id\":\"$sidA\"}" CLAUDE_PROJECT_DIR="$projA" REASON="$reason"
	outA=$OUT
	projB=$(tmp_dir)
	chmod 555 "$projB"
	sidB="fires-b7b-$$"
	run_hook "$s" "{\"session_id\":\"$sidB\"}" CLAUDE_PROJECT_DIR="$projB" REASON="$reason"
	outB=$OUT
	rcB=$RC
	errB=$ERR
	chmod 755 "$projB"
	assert_eq "$rcB" "0" "B7 deny rc 0 despite an unwritable project dir"
	assert_eq "$outB" "$outA" "B7 JSON identical whether or not the fire log could be written"
	assert_eq "$errB" "" "B7 no crash noise on stderr"
	assert_file_missing "$projB/.claude/lesson-fires.log" "B7 no fire log written when the project dir is unwritable"
	rm -rf "$scriptdir" "$projA" "$projB"
}

t_lesson_fires_B7b_readonly_log_is_silent() {
	local scriptdir proj s sid reason log
	if [ "$(id -u)" = "0" ]; then
		_pass "B7b: read-only fire log silent (skipped: running as root)"
		return
	fi
	scriptdir=$(tmp_dir)
	s=$(_fires_deny_script "$scriptdir")
	reason="blocked [lesson(2026-09-05): readonly log case]"

	# Sub-case 1: .claude/lesson-fires.log pre-exists, chmod 444
	proj=$(tmp_dir)
	sid="fires-b7b1-$$"
	mkdir -p "$proj/.claude"
	log="$proj/.claude/lesson-fires.log"
	: >"$log"
	chmod 444 "$log"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B7b readonly log: deny rc 0"
	assert_eq "$ERR" "" "B7b readonly log: nothing on stderr"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "$reason" "B7b readonly log: reason printed verbatim"
	assert_eq "$(cat "$log")" "" "B7b readonly log: log still empty"
	chmod 644 "$log"
	rm -rf "$proj"

	# Sub-case 2: .claude directory chmod 555, log absent
	proj=$(tmp_dir)
	sid="fires-b7b2-$$"
	mkdir -p "$proj/.claude"
	chmod 555 "$proj/.claude"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B7b unwritable .claude dir: deny rc 0"
	assert_eq "$ERR" "" "B7b unwritable .claude dir: nothing on stderr"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "$reason" "B7b unwritable .claude dir: reason printed verbatim"
	assert_file_missing "$proj/.claude/lesson-fires.log" "B7b unwritable .claude dir: no log written"
	chmod 755 "$proj/.claude"
	rm -rf "$scriptdir" "$proj"
}

t_lesson_fires_B8_tab_stripped() {
	local scriptdir proj s sid reason log line fields what date
	scriptdir=$(tmp_dir)
	proj=$(tmp_dir)
	s=$(_fires_deny_script "$scriptdir")
	sid="fires-b8-$$"
	reason=$(printf 'blocked [lesson(2026-09-05): push\t--force]')
	log="$proj/.claude/lesson-fires.log"
	run_hook "$s" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$proj" REASON="$reason"
	assert_rc 0 "B8 deny rc 0"
	assert_file_exists "$log" "B8 fire log created for a tab-carrying what"
	line=$(sed -n '1p' "$log")
	fields=$(printf '%s' "$line" | awk -F'\t' '{print NF}')
	assert_eq "$fields" "4" "B8 fire line still has exactly 4 tab-separated fields"
	date=$(printf '%s' "$line" | awk -F'\t' '{print $1}')
	what=$(printf '%s' "$line" | awk -F'\t' '{print $2}')
	assert_eq "$date" "2026-09-05" "B8 fire line date"
	assert_eq "$what" "push--force" "B8 the tab inside what is deleted (tr -d), not replaced with a space"
	rm -rf "$scriptdir" "$proj"
}
