#!/usr/bin/env bash
# test_lesson_claude_md.sh — lesson-claude-md (the CLAUDE.md rung's budgeted line writer).
set -u

SCRIPT="$SCAN_DIR/lesson-claude-md"

t_lesson_claude_md_B15_appends_with_marker() {
	local d f i
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	: >"$f"
	i=0
	while [ $i -lt 10 ]; do
		printf 'line %s\n' "$i" >>"$f"
		i=$((i + 1))
	done
	run_cmd "$SCRIPT" --file "$f" --line "Always run tests before committing" --what "skipped tests" --date "2026-01-15"
	assert_rc 0 "B15: appending a fresh line exits 0"
	assert_eq "$(tail -1 "$f")" "Always run tests before committing <!-- lesson(2026-01-15): skipped tests -->" "B15: marker appended to the same line"
	assert_contains "$OUT" "lines: 11/100" "B15: stdout reports the new line count against budget"
	rm -rf "$d"
}

t_lesson_claude_md_B16_duplicate_refused() {
	local d f
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	printf 'Use uv for Python.\n' >"$f"
	run_cmd "$SCRIPT" --file "$f" --line "USE UV, for python!!"
	assert_rc 3 "B16: a normalised-equal line exits 3"
	assert_contains "$ERR" "duplicate of line 1" "B16: stderr names the matching line number"
	assert_eq "$(cat "$f")" "Use uv for Python." "B16: file left unchanged"
	rm -rf "$d"
}

t_lesson_claude_md_B17_at_budget_refused() {
	local d f i
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	: >"$f"
	i=0
	while [ $i -lt 100 ]; do
		printf 'existing line %s\n' "$i" >>"$f"
		i=$((i + 1))
	done
	run_cmd "$SCRIPT" --file "$f" --line "a brand new line"
	assert_rc 5 "B17: a 100-line file without --cut exits 5"
	assert_contains "$ERR" "at budget (100/100)" "B17: stderr reports the budget"
	assert_eq "$(wc -l <"$f" | tr -d ' ')" "100" "B17: file left unchanged at 100 lines"
	rm -rf "$d"
}

t_lesson_claude_md_B18_cut_swaps() {
	local d f i
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	: >"$f"
	i=0
	while [ $i -lt 100 ]; do
		printf 'existing line %s\n' "$i" >>"$f"
		i=$((i + 1))
	done
	run_cmd "$SCRIPT" --file "$f" --line "a brand new line" --cut "existing line 5"
	assert_rc 0 "B18: --cut of an existing line exits 0"
	assert_eq "$(wc -l <"$f" | tr -d ' ')" "100" "B18: line count unchanged"
	assert_eq "$(grep -c '^existing line 5$' "$f")" "0" "B18: the cut line is gone"
	assert_eq "$(tail -1 "$f")" "a brand new line" "B18: the new line is last"
	rm -rf "$d"
}

t_lesson_claude_md_B19_similar_reported() {
	local d f
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	printf 'Remember to run tests before pushing changes.\n' >"$f"
	run_cmd "$SCRIPT" --file "$f" --line "Please run tests before pushing important changes"
	assert_rc 0 "B19: a similar but not duplicate line exits 0"
	assert_contains "$OUT" "similar: 1:" "B19: stdout reports the similar existing line"
	rm -rf "$d"
}

t_lesson_claude_md_B20_cut_missing_refused() {
	local d f
	d=$(tmp_dir)
	f="$d/CLAUDE.md"
	printf 'existing line\n' >"$f"
	run_cmd "$SCRIPT" --file "$f" --line "new line" --cut "line that is not there"
	assert_rc 3 "B20: --cut naming a missing line exits 3"
	assert_eq "$(cat "$f")" "existing line" "B20: file left unchanged"
	rm -rf "$d"
}

t_lesson_claude_md_B21_create_project_only() {
	local d
	d=$(tmp_dir)
	run_cmd "$SCRIPT" --file "$d/CLAUDE.md" --line "first line"
	assert_rc 0 "B21: a missing project CLAUDE.md is created"
	assert_eq "$(cat "$d/CLAUDE.md")" "first line" "B21: created file holds the one line"
	run_cmd env HOME="$d/home" "$SCRIPT" --file "$d/home/.claude/CLAUDE.md" --line "second line"
	assert_rc 4 "B21: a missing \$HOME/.claude/CLAUDE.md exits 4"
	assert_file_missing "$d/home/.claude/CLAUDE.md" "B21: \$HOME/.claude/CLAUDE.md is not created"
	rm -rf "$d"
}
