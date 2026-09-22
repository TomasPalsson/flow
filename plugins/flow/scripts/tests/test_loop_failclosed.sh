#!/usr/bin/env bash
# test_loop_failclosed.sh — fail-closed tamper (spec .specs/010-autonomous-
# loop-on-ramp-yolo, B7/FR-07) for plugins/flow/bin/lib/loop/tick.js: with
# front.fail_closed === '1', a tamper finding stops the run instead of
# merely marking it suspect.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_loop.sh having been sourced.
#
# Nothing yet writes fail_closed into the contract (that gap is a later
# task), so these fixtures set it directly with contract.js, the module
# that owns the front-matter format.
set -u

FC_CLI_PATH=""
FC_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
FC_CLI_PATH="$FC_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && FC_CLI_PATH="$SCAN_DIR/../bin/flow"

FC_LOOP_DIR=$(cd "$SCAN_DIR/../bin/lib/loop" && pwd -P)
export FC_LOOP_DIR

# fc_cli_in <project-dir> <home-dir> <args...>
fc_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$FC_CLI_PATH" "$@"
}

# fc_repo — a tmp_repo with one tracked test file (so test_files starts >0,
# needed for "test files removed" to register as a tamper finding).
fc_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/tests"
	printf 'echo test\n' >"$d/tests/foo_test.sh"
	(cd "$d" && git add tests/foo_test.sh && git commit -q -m "add test file") >/dev/null 2>&1
	printf '%s' "$d"
}

# fc_set_fail_closed <proj> — patch fail_closed: '1' onto the loop.md
# contract via contract.js's own read/write, so the on-disk shape stays
# whatever that module produces.
fc_set_fail_closed() {
	run_cmd node -e "
const { readContract, writeContract } = require(process.env.FC_LOOP_DIR + '/contract.js');
const c = readContract('$1');
c.front.fail_closed = '1';
writeContract('$1', c.front, c.body);
"
}

t_failclosed_tamper_stops_run_b7() {
	local proj home
	proj=$(fc_repo)
	home=$(tmp_dir)
	fc_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	: >"$proj/done.txt"
	fc_set_fail_closed "$proj"

	(cd "$proj" && rm tests/foo_test.sh && git add -A) >/dev/null 2>&1

	fc_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "stopped:" "t_failclosed_tamper_stops_run_b7 stopped"
	assert_contains "$OUT" "test files removed" "t_failclosed_tamper_stops_run_b7 reason"
	assert_not_contains "$OUT" "SUSPECT" "t_failclosed_tamper_stops_run_b7 not-suspect"

	rm -rf "$home" "$proj"
}

# Baseline guard: without fail_closed, the same tamper finding still just
# marks the run suspect (existing K-F behaviour, untouched by this task).
t_failclosed_off_still_marks_suspect_b7() {
	local proj home
	proj=$(fc_repo)
	home=$(tmp_dir)
	fc_cli_in "$proj" "$home" loop init "make done" --verify "test -f done.txt" >/dev/null
	: >"$proj/done.txt"

	(cd "$proj" && rm tests/foo_test.sh && git add -A) >/dev/null 2>&1

	fc_cli_in "$proj" "$home" loop tick --hook
	assert_contains "$OUT" "SUSPECT" "t_failclosed_off_still_marks_suspect_b7 suspect"
	assert_not_contains "$OUT" "stopped:" "t_failclosed_off_still_marks_suspect_b7 not-stopped"

	rm -rf "$home" "$proj"
}
