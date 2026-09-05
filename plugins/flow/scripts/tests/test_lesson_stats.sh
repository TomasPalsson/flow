#!/usr/bin/env bash
# test_lesson_stats.sh — lesson-stats (recurrence-budget reporting over
# PROGRESS.md's Rulings and lesson-fires.log). Fixtures under
# tests/fixtures/lesson/ are read-only golden inputs: always copy them into
# a fresh temp dir before running lesson-stats against them.
set -u

LESSON_STATS="$SCAN_DIR/lesson-stats"
FIXTURE_DIR="$SCAN_DIR/tests/fixtures/lesson"

# copy the read-only fixture pair into a fresh temp dir, echo the temp dir
_fixture_copy() {
	local d
	d=$(tmp_dir)
	cp "$FIXTURE_DIR/PROGRESS.md" "$d/PROGRESS.md"
	cp "$FIXTURE_DIR/lesson-fires.log" "$d/lesson-fires.log"
	printf '%s' "$d"
}

t_lesson_stats_B9_golden_tsv() {
	local d out_file
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "B9: exit 0 on the fixture pair"
	out_file="$d/out.tsv"
	printf '%s\n' "$OUT" >"$out_file"
	run_cmd diff "$out_file" "$FIXTURE_DIR/stats.expected.tsv"
	assert_rc 0 "B9: stdout diffs empty against stats.expected.tsv"
	assert_eq "$OUT" "" "B9: diff produced no output"
	rm -rf "$d"
}

t_lesson_stats_B10_golden_json() {
	local d out_file exp_file
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15 --json
	assert_rc 0 "B10: --json exit 0 on the fixture pair"
	out_file="$d/out.json"
	exp_file="$FIXTURE_DIR/stats.expected.json"
	printf '%s\n' "$OUT" >"$out_file"
	if command -v python3 >/dev/null 2>&1; then
		run_cmd python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    a = json.load(f)
with open(sys.argv[2]) as f:
    b = json.load(f)
sys.exit(0 if a == b else 1)
' "$out_file" "$exp_file"
		assert_rc 0 "B10: parsed JSON matches stats.expected.json (python3 structural compare)"
	else
		local a b
		a=$(tr -d '[:space:]' <"$out_file")
		b=$(tr -d '[:space:]' <"$exp_file")
		assert_eq "$a" "$b" "B10: JSON matches stats.expected.json (whitespace-stripped text compare)"
	fi
	rm -rf "$d"
}

t_lesson_stats_B11_escaped() {
	local d expected
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "B11: exit 0 on the fixture pair"
	expected=$(printf '2026-09-03\thook\t0\t-\t1\tescaped\tformat-lint reran prettier on generated files')
	assert_contains "$OUT" "$expected" "B11: earlier duplicate-what ruling shows escaped 1 and verdict escaped"
	rm -rf "$d"
}

t_lesson_stats_B12_now_drives_age() {
	local d expected_prune expected_young
	d=$(_fixture_copy)
	expected_prune=$(printf '2026-08-20\thook\t0\t-\t0\tprune?\tsize-guard flagged generated protobuf files')
	expected_young=$(printf '2026-08-20\thook\t0\t-\t0\tyoung\tsize-guard flagged generated protobuf files')

	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "B12: exit 0 with --now 2026-10-15"
	assert_contains "$OUT" "$expected_prune" "B12: --now 2026-10-15 makes the 2026-08-20 hook ruling prune?"

	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-09-10
	assert_rc 0 "B12: exit 0 with --now 2026-09-10"
	assert_contains "$OUT" "$expected_young" "B12: --now 2026-09-10 makes the same ruling young"

	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15 --prune-days 60
	assert_rc 0 "B12: exit 0 with --now 2026-10-15 --prune-days 60"
	assert_contains "$OUT" "$expected_young" "B12: --prune-days 60 keeps the same ruling young at --now 2026-10-15"

	rm -rf "$d"
}

t_lesson_stats_B13_missing_progress() {
	local d
	d=$(tmp_dir)
	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15
	assert_rc 2 "B13: missing PROGRESS.md exits 2"
	assert_eq "$ERR" "lesson-stats: no PROGRESS.md in $d" "B13: names the directory on stderr"
	rm -rf "$d"
}

t_lesson_stats_B14_malformed_skipped() {
	local d
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "B14: exit 0 despite one malformed lesson-fires.log line"
	assert_eq "$ERR" "lesson-stats: skipped 1 malformed line(s)" "B14: reports exactly one skipped malformed line on stderr"
	rm -rf "$d"
}

t_lesson_stats_help_documents_flags_and_defaults() {
	run_cmd "$LESSON_STATS" --help
	assert_rc 0 "help: --help exits 0"
	assert_contains "$OUT" "--dir" "help: documents --dir"
	assert_contains "$OUT" "--file" "help: documents --file"
	assert_contains "$OUT" "--log" "help: documents --log"
	assert_contains "$OUT" "--now" "help: documents --now"
	assert_contains "$OUT" "--prune-days" "help: documents --prune-days"
	assert_contains "$OUT" "--json" "help: documents --json"
	assert_contains "$OUT" "--help" "help: documents --help"
	assert_contains "$OUT" "Exit codes: 0" "help: documents exit code 0"
	assert_contains "$OUT" "2" "help: documents exit code 2"
	assert_contains "$OUT" "git toplevel" "help: documents the --dir default (git toplevel, else cwd)"
	assert_contains "$OUT" ".claude/lesson-fires.log" "help: documents the --log default path"
}

t_lesson_stats_now_malformed_is_usage_error() {
	local d
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --now not-a-date
	assert_rc 2 "malformed --now: exits 2"
	assert_contains "$ERR" "--now" "malformed --now: usage error names --now"
	rm -rf "$d"
}

# --- fix 1: fires join rulings on (date, what), not what alone ---

t_lesson_stats_fire_join_requires_date_and_what() {
	local d fires_log matched_row unmatched_row orphan_row
	d=$(_fixture_copy)
	fires_log="$d/lesson-fires.log"

	# a fire dated 2026-09-03 with the duplicate "what" matches only the
	# 2026-09-03 ruling, not the 2026-09-05 ruling with the same "what".
	printf '2026-09-03\tformat-lint reran prettier on generated files\t2026-09-10T09:00:00Z\tformat-lint.sh\n' >>"$fires_log"
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "fire-join: exit 0 after appending a matching fire"
	matched_row=$(printf '2026-09-03\thook\t1\t35\t1\tescaped\tformat-lint reran prettier on generated files')
	assert_contains "$OUT" "$matched_row" "fire-join: 2026-09-03 ruling shows caught 1"
	unmatched_row=$(printf '2026-09-05\tscript\t0\t-\t0\tunmeasured\tformat-lint reran prettier on generated files')
	assert_contains "$OUT" "$unmatched_row" "fire-join: 2026-09-05 ruling (same what, script rung) still shows caught 0"

	# a fire with the same "what" but a date that matches no ruling becomes
	# an orphan row, not a match on either ruling above.
	printf '2026-01-05\tformat-lint reran prettier on generated files\t2026-01-05T09:00:00Z\tformat-lint.sh\n' >>"$fires_log"
	run_cmd "$LESSON_STATS" --dir "$d" --log lesson-fires.log --now 2026-10-15
	assert_rc 0 "fire-join: exit 0 after appending a date-mismatched fire"
	orphan_row=$(printf '2026-01-05\t-\t1\t283\t0\torphan\tformat-lint reran prettier on generated files')
	assert_contains "$OUT" "$orphan_row" "fire-join: fire whose what matches a ruling but whose date matches none is an orphan row"
	assert_contains "$OUT" "$matched_row" "fire-join: 2026-09-03 ruling is unaffected by the date-mismatched fire"
	assert_contains "$OUT" "$unmatched_row" "fire-join: 2026-09-05 ruling is still not credited by the date-mismatched fire"

	rm -rf "$d"
}

# --- fix 2: default --now uses UTC, not local time ---

t_lesson_stats_source_uses_utc_clock() {
	assert_contains "$(cat "$LESSON_STATS")" "date -u" "utc-clock: script text uses date -u for the default clock"
}

t_lesson_stats_now_default_is_utc_regardless_of_tz() {
	local d out_kiritimati out_utc
	d=$(_fixture_copy)
	run_cmd env TZ=Pacific/Kiritimati "$LESSON_STATS" --dir "$d"
	assert_rc 0 "utc-clock: exits 0 under TZ=Pacific/Kiritimati"
	out_kiritimati="$OUT"
	run_cmd env TZ=UTC "$LESSON_STATS" --dir "$d"
	assert_rc 0 "utc-clock: exits 0 under TZ=UTC"
	out_utc="$OUT"
	assert_eq "$out_kiritimati" "$out_utc" "utc-clock: default --now output is identical under TZ=Pacific/Kiritimati and TZ=UTC"
	rm -rf "$d"
}

# --- fix 4: --dir defaults to git toplevel, --log to .claude/lesson-fires.log ---

t_lesson_stats_control_characters_are_escaped() {
	local d tab_what quote_what field_counts
	d=$(tmp_dir)
	tab_what=$(printf 'weird\ttabbed')
	quote_what='say "hi" \ backslash'
	printf '# Progress\n\n## Rulings\n- Ruling: %s — hook guard.sh + 1 test — a cost (2026-09-01)\n- Ruling: %s — hook guard.sh + 1 test — a cost (2026-09-02)\n\n## Blocked / open questions\n- (none)\n' "$tab_what" "$quote_what" >"$d/PROGRESS.md"

	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15 --json
	assert_rc 0 "control chars: --json exits 0 with a tab and quote/backslash in what"
	printf '%s\n' "$OUT" >"$d/out.json"
	if command -v python3 >/dev/null 2>&1; then
		run_cmd python3 -c '
import json, sys
with open(sys.argv[1]) as f:
    rows = json.load(f)
found = [r for r in rows if r["what"].replace("\t", "") == "weirdtabbed"]
sys.exit(0 if found and "\t" in found[0]["what"] else 1)
' "$d/out.json"
		assert_rc 0 "control chars: JSON what round-trips with the tab intact"
	else
		_pass "control chars: python3 not available, skipping JSON round-trip assertion"
	fi

	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15
	assert_rc 0 "control chars: TSV mode exits 0"
	printf '%s\n' "$OUT" >"$d/out.tsv"
	field_counts=$(awk -F'\t' '{print NF}' "$d/out.tsv" | sort -u | tr '\n' ' ')
	field_counts=$(printf '%s' "$field_counts" | sed 's/ *$//')
	assert_eq "$field_counts" "7" "control chars: every TSV row has exactly 7 tab-separated fields"

	rm -rf "$d"
}

t_lesson_stats_dir_and_log_default_to_project_root() {
	local prevdir repo sub expected
	prevdir=$(pwd)
	repo=$(tmp_repo)
	printf '# Progress\n\n## Rulings\n- Ruling: something broke — hook guard.sh + 1 test — a false alarm costs one look (2026-08-01)\n' >"$repo/PROGRESS.md"
	mkdir -p "$repo/.claude"
	printf '2026-08-01\tsomething broke\t2026-08-02T00:00:00Z\tguard.sh\n' >"$repo/.claude/lesson-fires.log"
	git -C "$repo" add PROGRESS.md
	git -C "$repo" commit -q -m "progress" >/dev/null 2>&1

	sub="$repo/sub"
	mkdir -p "$sub"
	cd "$sub" || {
		_fail "defaults: setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$LESSON_STATS" --now 2026-08-05
	cd "$prevdir" || true
	assert_rc 0 "defaults: exits 0 with no --dir/--file/--log from a subdirectory of the git toplevel"
	expected=$(printf 'date\trung\tcaught\tlast\tescaped\tverdict\twhat\n2026-08-01\thook\t1\t3\t0\theld\tsomething broke')
	assert_eq "$OUT" "$expected" "defaults: fires in <toplevel>/.claude/lesson-fires.log are counted against the ruling"
}
