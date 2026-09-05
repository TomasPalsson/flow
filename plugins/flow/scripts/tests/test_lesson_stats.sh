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

t_lesson_stats_B9() {
	local d out_file
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15
	assert_rc 0 "B9: exit 0 on the fixture pair"
	out_file="$d/out.tsv"
	printf '%s\n' "$OUT" >"$out_file"
	run_cmd diff "$out_file" "$FIXTURE_DIR/stats.expected.tsv"
	assert_rc 0 "B9: stdout diffs empty against stats.expected.tsv"
	assert_eq "$OUT" "" "B9: diff produced no output"
	rm -rf "$d"
}

t_lesson_stats_B10() {
	local d out_file exp_file
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15 --json
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

t_lesson_stats_B11() {
	local d
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15
	assert_rc 0 "B11: exit 0 despite one malformed lesson-fires.log line"
	assert_eq "$ERR" "lesson-stats: skipped 1 malformed line(s)" "B11: reports exactly one skipped malformed line on stderr"
	rm -rf "$d"
}

t_lesson_stats_B12() {
	local d
	d=$(tmp_dir)
	run_cmd "$LESSON_STATS" --dir "$d" --now 2026-10-15
	assert_rc 2 "B12: missing PROGRESS.md exits 2"
	assert_eq "$ERR" "lesson-stats: no PROGRESS.md in $d" "B12: names the directory on stderr"
	rm -rf "$d"
}

t_lesson_stats_B13() {
	run_cmd "$LESSON_STATS" --help
	assert_rc 0 "B13: --help exits 0"
	assert_contains "$OUT" "--dir" "B13: documents --dir"
	assert_contains "$OUT" "--file" "B13: documents --file"
	assert_contains "$OUT" "--log" "B13: documents --log"
	assert_contains "$OUT" "--now" "B13: documents --now"
	assert_contains "$OUT" "--prune-days" "B13: documents --prune-days"
	assert_contains "$OUT" "--json" "B13: documents --json"
	assert_contains "$OUT" "--help" "B13: documents --help"
	assert_contains "$OUT" "Exit codes: 0" "B13: documents exit code 0"
	assert_contains "$OUT" "2" "B13: documents exit code 2"
}

t_lesson_stats_B14() {
	local d
	d=$(_fixture_copy)
	run_cmd "$LESSON_STATS" --dir "$d" --now not-a-date
	assert_rc 2 "B14: a malformed --now exits 2"
	assert_contains "$ERR" "--now" "B14: usage error names --now"
	rm -rf "$d"
}
