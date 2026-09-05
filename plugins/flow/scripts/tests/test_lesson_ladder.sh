#!/usr/bin/env bash
# test_lesson_ladder.sh — lesson-sites' deny rung and the /lesson skill's
# ladder (Slice 5: Test -> Deny -> Hook / lint -> Script -> Skill -> CLAUDE.md).
set -u

SITES="$SCAN_DIR/lesson-sites"

t_lesson_sites_B22_deny_absent() {
	local d
	d=$(tmp_dir)
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_rc 0 "B22: lesson-sites on a dir with no settings.json exits 0"
	assert_contains "$OUT" "deny absent" "B22: deny rung reports absent when settings.json is missing"
	assert_contains "$OUT" "$d/.claude/settings.json" "B22: absent detail names the settings.json path"
	assert_contains "$OUT" "create it" "B22: absent detail says to create the missing file"
	assert_contains "$OUT" "~/.claude/settings.json" "B22: absent detail mentions the machine-wide file"
	rm -rf "$d"
}

t_lesson_sites_B23_deny_present() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	printf '{"permissions":{"deny":["Bash(git commit --no-verify*)"]}}\n' >"$d/.claude/settings.json"
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_rc 0 "B23: lesson-sites with a deny block exits 0"
	assert_contains "$OUT" "deny present" "B23: deny rung reports present when settings.json has a deny block"
	assert_contains "$OUT" "$d/.claude/settings.json" "B23: present detail names the settings.json path"
	rm -rf "$d"
}

t_lesson_sites_B25_settings_without_deny() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	printf '{"hooks":{}}\n' >"$d/.claude/settings.json"
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_rc 0 "B25: lesson-sites with a settings.json lacking deny exits 0"
	assert_contains "$OUT" "deny absent" "B25: deny rung reports absent when settings.json has no deny block"
	assert_contains "$OUT" "$d/.claude/settings.json" "B25: absent detail names the settings.json path"
	assert_contains "$OUT" "add a permissions.deny block to it" "B25: absent detail says to add a block to the existing file"
	assert_contains "$OUT" "~/.claude/settings.json" "B25: absent detail mentions the machine-wide file"
	rm -rf "$d"
}

t_lesson_ladder_B24_skill_names_deny_and_scripts() {
	local skill test_line deny_line hook_line stats_path md_path order_ok
	skill="$SCAN_DIR/../skills/lesson/SKILL.md"
	assert_file_exists "$skill" "B24: lesson skill exists"

	test_line=$(grep -n '^| \*\*Test\*\*' "$skill" | head -1 | cut -d: -f1)
	deny_line=$(grep -n '^| \*\*Deny\*\*' "$skill" | head -1 | cut -d: -f1)
	hook_line=$(grep -n '^| \*\*Hook / lint\*\*' "$skill" | head -1 | cut -d: -f1)
	assert_eq "$([ -n "$test_line" ] && [ -n "$deny_line" ] && [ -n "$hook_line" ] && printf yes || printf no)" \
		"yes" "B24: Test, Deny and Hook / lint rows all exist in the ladder table"

	order_ok=no
	if [ -n "$test_line" ] && [ -n "$deny_line" ] && [ -n "$hook_line" ]; then
		if [ "$test_line" -lt "$deny_line" ] && [ "$deny_line" -lt "$hook_line" ]; then order_ok=yes; fi
	fi
	assert_eq "$order_ok" "yes" "B24: Deny row sits between Test and Hook / lint"

	assert_contains "$(cat "$skill")" '${CLAUDE_PLUGIN_ROOT}/scripts/lesson-stats' "B24: skill names lesson-stats"
	assert_contains "$(cat "$skill")" '${CLAUDE_PLUGIN_ROOT}/scripts/lesson-claude-md' "B24: skill names lesson-claude-md"

	stats_path="$SCAN_DIR/lesson-stats"
	md_path="$SCAN_DIR/lesson-claude-md"
	assert_file_exists "$stats_path" "B24: lesson-stats exists"
	assert_file_exists "$md_path" "B24: lesson-claude-md exists"
	assert_eq "$([ -x "$stats_path" ] && printf yes || printf no)" "yes" "B24: lesson-stats is executable"
	assert_eq "$([ -x "$md_path" ] && printf yes || printf no)" "yes" "B24: lesson-claude-md is executable"

	assert_eq "$(grep -cE 'every turn|each turn|on every prompt' "$skill")" "0" "B24: no per-turn instruction (zero-noise rule)"
}
