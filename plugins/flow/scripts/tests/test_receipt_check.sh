#!/usr/bin/env bash
# tests/test_receipt_check.sh — scripts/receipt-check: the mechanical receipt
# check that runs between Find and Score in review-diff. Sourced by run.sh;
# SCAN_DIR comes from there. Test names: t_receipt_check_*.

RC_BIN="$SCAN_DIR/receipt-check"

# _rc_fixture <dir> — a fake repo root plus a review-package style diff.
# src/a.js has 60 lines; line 12 is `const saved = await save(item);`, line 52
# is a distinct statement. test/gone.test.js is deleted in the diff.
_rc_fixture() {
	local d=$1 i
	mkdir -p "$d/root/src" "$d/root/test"
	i=1
	: >"$d/root/src/a.js"
	while [ "$i" -le 60 ]; do
		case "$i" in
			12) printf '  const saved = await save(item);\n' >>"$d/root/src/a.js" ;;
			52) printf '  return   cleanupTemp( dir );\n' >>"$d/root/src/a.js" ;;
			*) printf '  filler%s();\n' "$i" >>"$d/root/src/a.js" ;;
		esac
		i=$((i + 1))
	done
	printf 'export const onlyInB = 1;\n' >"$d/root/src/b.js"
	cat >"$d/diff" <<'DIFF'
# review-package base=aaaa head=bbbb
abc1234 change things

 src/a.js | 2 +-

diff --git a/src/a.js b/src/a.js
index 111..222 100644
--- a/src/a.js
+++ b/src/a.js
@@ -10,3 +10,3 @@
   filler10();
-  const oldName = compute(x);
+  const saved = await save(item);
diff --git a/src/b.js b/src/b.js
index 444..555 100644
--- a/src/b.js
+++ b/src/b.js
@@ -1,1 +1,1 @@
 export const onlyInB = 1;
diff --git a/test/gone.test.js b/test/gone.test.js
deleted file mode 100644
index 333..000
--- a/test/gone.test.js
+++ /dev/null
@@ -1,3 +0,0 @@
-it('keeps the total', () => {
-  expect(total([1, 2])).toBe(3);
-});
DIFF
}

# _rc_run <dir> <findings-json> — runs receipt-check with the findings on stdin.
_rc_run() {
	printf '%s' "$2" >"$1/findings.json"
	run_cmd bash -c '"$0" --diff "$1" --root "$2" <"$3"' "$RC_BIN" "$1/diff" "$1/root" "$1/findings.json"
}

t_receipt_check_quote_at_line_is_verified() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"const saved = await save(item);"}]'
	assert_rc 0 "receipt-check: runs"
	assert_contains "$OUT" '"index":0,"disposition":"verified"' "receipt-check: quote at the cited line is verified"
}

t_receipt_check_whitespace_is_normalised() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":54,"quote":"return cleanupTemp( dir );"}]'
	assert_contains "$OUT" '"disposition":"verified"' "receipt-check: quote within 5 lines matches despite spacing"
}

t_receipt_check_same_file_far_away_is_moved() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"return cleanupTemp( dir );"}]'
	assert_contains "$OUT" '"disposition":"moved"' "receipt-check: quote 40 lines away is moved"
	assert_contains "$OUT" '"line":52' "receipt-check: moved carries the corrected line"
}

t_receipt_check_invented_quote_is_failed() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"dangerouslyEval(userInput)"}]'
	assert_contains "$OUT" '"disposition":"failed"' "receipt-check: an invented quote is failed"
	assert_contains "$OUT" 'not found' "receipt-check: failed names a reason"
}

t_receipt_check_quote_only_in_another_file_is_unsupported() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"export const onlyInB = 1;"}]'
	assert_contains "$OUT" '"disposition":"unsupported"' "receipt-check: a quote found only in another file is unsupported"
}

t_receipt_check_missing_file_is_failed() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/nope.js","line":3,"quote":"x"}]'
	assert_contains "$OUT" '"disposition":"failed"' "receipt-check: a file neither at head nor deleted in the diff is failed"
}

t_receipt_check_deleted_test_removed_line_is_verified() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"test/gone.test.js","line":2,"quote":"expect(total([1, 2])).toBe(3);"}]'
	assert_contains "$OUT" '"disposition":"verified"' "receipt-check: a removed line of a deleted test file is verified, not failed"
}

t_receipt_check_removed_line_in_existing_file_is_verified() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":40,"quote":"const oldName = compute(x);"}]'
	assert_contains "$OUT" '"disposition":"verified"' "receipt-check: a '-' line of the file's hunk is verified far from the cited line"
}

t_receipt_check_no_quote_is_unverifiable() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12}]'
	assert_contains "$OUT" '"disposition":"unverifiable"' "receipt-check: no quote is unverifiable, never failed"
}

t_receipt_check_path_outside_root_is_failed() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"../diff","line":1,"quote":"review-package"}]'
	assert_contains "$OUT" '"disposition":"failed"' "receipt-check: a path that climbs out of the root is failed"
}

t_receipt_check_bad_stdin_exits_2() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" 'not json'
	assert_rc 2 "receipt-check: unparseable stdin is a usage error"
}

t_receipt_check_one_result_per_finding_in_order() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"const saved = await save(item);"},{"file":"src/a.js","line":12},{"line":"x"}]'
	assert_contains "$OUT" '"index":1,"disposition":"unverifiable"' "receipt-check: second finding reported by index"
	assert_contains "$OUT" '"index":2,"disposition":"unverifiable"' "receipt-check: a malformed finding is unverifiable, never a crash"
}

t_receipt_check_absolute_path_inside_root_is_checked() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"'"$d"'/root/src/a.js","line":12,"quote":"const saved = await save(item);"},{"file":"'"$d"'/root/src/a.js","line":12}]'
	assert_contains "$OUT" '"index":0,"disposition":"verified"' "receipt-check: absolute path inside the root is verified"
	assert_contains "$OUT" '"index":1,"disposition":"unverifiable"' "receipt-check: absolute path without a quote is unverifiable"
}

t_receipt_check_diff_marker_prefix_is_stripped() {
	local d
	d=$(tmp_dir)
	_rc_fixture "$d"
	_rc_run "$d" '[{"file":"src/a.js","line":12,"quote":"+  const saved = await save(item);"}]'
	assert_contains "$OUT" '"disposition":"verified"' "receipt-check: a copied diff marker does not fail the quote"
}
