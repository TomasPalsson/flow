#!/usr/bin/env bash
# test_lesson.sh — lesson-sites and lesson-record (the /lesson skill's scripts).
set -u

SITES="$SCAN_DIR/lesson-sites"
RECORD="$SCAN_DIR/lesson-record"

t_lesson_sites_help() {
	run_cmd "$SITES" --help
	assert_rc 0 "lesson-sites --help exits 0"
	assert_contains "$OUT" "Usage: lesson-sites" "lesson-sites --help shows usage"
}

t_lesson_sites_plain_project_reports_every_rung() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"bun test"}}\n' >"$d/package.json"
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_rc 0 "lesson-sites on a plain project exits 0"
	for rung in test hook lint script skill claude-md progress; do
		assert_contains "$OUT" "$rung " "lesson-sites prints the $rung rung"
	done
	assert_contains "$OUT" "test present package.json test script" "lesson-sites detects the npm test script"
	assert_contains "$OUT" "hook absent" "lesson-sites reports no project hooks"
	printf '{"name":"x","scripts":{"build":"x"}}\n' >"$d/package.json"; mkdir -p "$d/tests"; : >"$d/tests/a.test.js"
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_contains "$OUT" "test absent package.json has no test script" "Node project without a test script is not reported as pytest"
	run_cmd env -u HOME "$SITES" --dir "$d"
	assert_rc 0 "lesson-sites survives an unset HOME"
	assert_contains "$OUT" "progress absent" "lesson-sites reports no PROGRESS.md"
	assert_contains "$OUT" "0/100 lines" "lesson-sites reports the project CLAUDE.md line count against its budget"
	rm -rf "$d"
}

t_lesson_sites_json_parses() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude" && printf '{"maxFileLines":400}\n' >"$d/.claude/harness.json"
	printf '# p\n' >"$d/PROGRESS.md"
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d" --json
	assert_rc 0 "lesson-sites --json exits 0"
	assert_eq "$(printf '%s' "$OUT" | node -e 'const j=JSON.parse(require("fs").readFileSync(0,"utf8"));console.log(j.lint.status+" "+j.progress.status+" "+j.harnessRepo)')" "present present false" "lesson-sites --json is valid JSON with the expected fields"
	rm -rf "$d"
}

t_lesson_sites_recognises_the_harness_plugin() {
	run_cmd env HOME=/nonexistent-home "$SITES" --dir "$SCAN_DIR/.."
	assert_rc 0 "lesson-sites on the plugin exits 0"
	assert_contains "$OUT" "hooks/tests/run.sh" "lesson-sites names the harness suites as the test site"
	assert_contains "$OUT" "hooks.json" "lesson-sites names hooks.json as the hook site"
}

t_lesson_sites_flags_claude_md_at_budget() {
	local d i
	d=$(tmp_dir)
	: >"$d/CLAUDE.md"
	i=0; while [ $i -lt 100 ]; do printf 'line\n' >>"$d/CLAUDE.md"; i=$((i + 1)); done
	run_cmd env HOME="$d/nohome" "$SITES" --dir "$d"
	assert_contains "$OUT" "AT BUDGET" "lesson-sites flags a 100-line project CLAUDE.md"
	rm -rf "$d"
}

t_lesson_record_help_and_usage() {
	run_cmd "$RECORD" --help
	assert_rc 0 "lesson-record --help exits 0"
	run_cmd "$RECORD" --what only
	assert_rc 2 "lesson-record without all three fields exits 2"
}

t_lesson_record_appends_under_rulings() {
	local d
	d=$(tmp_dir)
	cat >"$d/PROGRESS.md" <<'P'
# Progress

## Now
- thing

## Rulings
- Ruling: old — because — nothing

## Blocked / open questions
- (none)
P
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "pushed with --force" --mechanism "hook git-guard.sh + 2 tests" --cost "one manual retry"
	assert_rc 0 "lesson-record exits 0"
	assert_contains "$OUT" "- Ruling: pushed with --force — hook git-guard.sh + 2 tests — one manual retry" "lesson-record prints the line"
	assert_eq "$(sed -n '/^## Rulings/,/^## Blocked/p' "$d/PROGRESS.md" | grep -c '^- Ruling:')" "2" "lesson-record keeps the old ruling and adds the new one inside the section"
	assert_eq "$(grep -n 'pushed with --force' "$d/PROGRESS.md" | cut -d: -f1)" "8" "lesson-record inserts after the last ruling, before the next heading"
	rm -rf "$d"
}

t_lesson_record_creates_file_and_section() {
	local d
	d=$(tmp_dir)
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "a" --mechanism "b" --cost "c"
	assert_rc 0 "lesson-record creates PROGRESS.md"
	assert_contains "$(cat "$d/PROGRESS.md")" "## Rulings" "created file has a Rulings section"
	assert_contains "$(cat "$d/PROGRESS.md")" "- Ruling: a — b — c" "created file holds the ruling"
	printf '# P\n\n## Now\n- x\n' >"$d/other.md"
	run_cmd "$RECORD" --file "$d/other.md" --what "a" --mechanism "b" --cost "c"
	assert_rc 0 "lesson-record adds a missing Rulings section"
	assert_eq "$(tail -2 "$d/other.md" | head -1)" "## Rulings" "section appended at the end"
	rm -rf "$d"
}

t_lesson_record_refuses_duplicate_and_drops_placeholder() {
	local d
	d=$(tmp_dir)
	printf '# P\n\n## Rulings\n- Ruling: <what was decided> — <why> — <cost if wrong>\n\n## Blocked / open questions\n- (none)\n' >"$d/PROGRESS.md"
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "dup" --mechanism "m" --cost "c"
	assert_rc 0 "first ruling written"
	assert_eq "$(grep -c 'what was decided' "$d/PROGRESS.md")" "0" "template placeholder bullet removed"
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "dup" --mechanism "m" --cost "c"
	assert_rc 3 "exact duplicate ruling exits 3"
	assert_eq "$(grep -c '^- Ruling: dup' "$d/PROGRESS.md")" "1" "exact duplicate not written"
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "dup" --mechanism "other" --cost "c"
	assert_rc 0 "same what, new mechanism: written as superseding"
	assert_contains "$ERR" "superseding" "same what, new mechanism: noted on stderr"
	assert_eq "$(grep -c '^- Ruling: dup' "$d/PROGRESS.md")" "2" "same what, new mechanism: both rulings present"
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "issue — with dashes" --mechanism "different mech" --cost "x"
	assert_rc 0 "a what containing an em dash is not a false duplicate"
	rm -rf "$d"
}

t_lesson_record_ignores_headings_inside_fences() {
	local d
	d=$(tmp_dir)
	printf '# P\n\n## Rulings\n- Ruling: old — a — b\n\n```\n## Rulings\n## Blocked\n```\n\n## Blocked / open questions\n- (none)\n' >"$d/PROGRESS.md"
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "new one" --mechanism "m" --cost "c"
	assert_rc 0 "fenced headings: exit 0"
	assert_eq "$(grep -n '^- Ruling: new one' "$d/PROGRESS.md" | cut -d: -f1)" "10" "fenced headings: inserted at the end of the real section, not inside the fence"
	assert_eq "$(sed -n '6,9p' "$d/PROGRESS.md" | tr '\n' '|')" "\`\`\`|## Rulings|## Blocked|\`\`\`|" "fenced headings: fence content byte-identical"
	assert_eq "$(sed -n '12p' "$d/PROGRESS.md")" "## Blocked / open questions" "fenced headings: the real next heading follows"
	rm -rf "$d"
}

t_lesson_record_fails_loudly_when_it_cannot_write() {
	local d
	d=$(tmp_dir)
	run_cmd "$RECORD" --file "$d/nosuchdir/deep/PROGRESS.md" --what "orphan" --mechanism "m" --cost "c"
	assert_rc 4 "unwritable target: exit 4"
	assert_not_contains "$OUT" "- Ruling: orphan" "unwritable target: nothing claimed as written"
	assert_contains "$ERR" "lesson-record:" "unwritable target: error on stderr"
	rm -rf "$d"
}

t_lesson_record_concurrent_runs_keep_both_rulings() {
	local d i
	d=$(tmp_dir)
	printf '# P\n\n## Rulings\n\n## Blocked / open questions\n- (none)\n' >"$d/PROGRESS.md"
	i=0
	while [ $i -lt 6 ]; do
		"$RECORD" --file "$d/PROGRESS.md" --what "parallel $i" --mechanism "m" --cost "c" >/dev/null 2>&1 &
		i=$((i + 1))
	done
	wait
	assert_eq "$(grep -c '^- Ruling: parallel' "$d/PROGRESS.md")" "6" "six concurrent runs: six rulings, none lost"
	assert_eq "$(ls -d "$d/PROGRESS.md.lock" 2>/dev/null | wc -l | tr -d ' ')" "0" "lock released"
	rm -rf "$d"
}

t_lesson_record_warns_over_budget() {
	local d i
	d=$(tmp_dir)
	printf '# P\n\n## Rulings\n' >"$d/PROGRESS.md"
	i=0; while [ $i -lt 60 ]; do printf -- '- filler %s\n' "$i" >>"$d/PROGRESS.md"; i=$((i + 1)); done
	run_cmd "$RECORD" --file "$d/PROGRESS.md" --what "w" --mechanism "m" --cost "c"
	assert_rc 0 "over-budget file still exits 0"
	assert_contains "$ERR" "budget 60" "lesson-record warns when PROGRESS.md exceeds 60 lines"
	rm -rf "$d"
}

t_lesson_skill_frontmatter_and_references() {
	local skill
	skill="$SCAN_DIR/../skills/lesson/SKILL.md"
	assert_file_exists "$skill" "lesson skill exists"
	assert_eq "$(sed -n '1p' "$skill")" "---" "lesson skill starts its frontmatter"
	assert_contains "$(sed -n '2,5p' "$skill")" "name: lesson" "lesson skill is named lesson"
	assert_contains "$(cat "$skill")" 'scripts/lesson-sites' "skill calls lesson-sites"
	assert_contains "$(cat "$skill")" 'scripts/lesson-record' "skill calls lesson-record"
	assert_contains "$(sed -n '3p' "$skill")" "Use WHENEVER the user corrects" "description carries the trigger"
}
