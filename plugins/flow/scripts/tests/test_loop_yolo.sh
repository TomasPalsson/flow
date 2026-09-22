#!/usr/bin/env bash
# test_loop_yolo.sh — --yolo caps and child arguments (spec .specs/010-
# autonomous-loop-on-ramp-yolo, B5/B6/FR-09/FR-12) for
# plugins/flow/bin/lib/loop/init.js and plugins/flow/bin/lib/loop/driver.js:
# --yolo arms the spec §5 defaults on any cap the operator did not pass, and
# the spawned child's argv denies prompts instead of waiting on one.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_loop.sh having been sourced.
set -u

YO_CLI_PATH=""
YO_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
YO_CLI_PATH="$YO_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && YO_CLI_PATH="$SCAN_DIR/../bin/flow"

YO_LOOP_DIR=$(cd "$SCAN_DIR/../bin/lib/loop" && pwd -P)
export YO_LOOP_DIR

# yo_cli_in <project-dir> <home-dir> <args...>
yo_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$YO_CLI_PATH" "$@"
}

# yo_front <proj> <key> — read one front-matter field via contract.js, the
# module that owns the format, so this test never guesses at serialization.
yo_front() {
	run_cmd node -e "
const { readContract } = require(process.env.YO_LOOP_DIR + '/contract.js');
const c = readContract('$1');
process.stdout.write(String(c.front['$2']));
"
	printf '%s' "$OUT"
}

# yo_repo — a tmp_repo with one tracked, non-empty file (src.txt) a verifier
# can read and the negative control can break (F2: --yolo now requires
# --neg-control-file, so every --yolo fixture below needs a real target).
yo_repo() {
	local d
	d=$(tmp_repo)
	printf 'the src\n' >"$d/src.txt"
	(cd "$d" && git add src.txt && git commit -q -m "add src.txt") >/dev/null 2>&1
	printf '%s' "$d"
}

# yo_verify — always red (exit 1), but its output is src.txt's own bytes, so
# the negative control's induced break (truncate src.txt) changes the
# verifier's output even though its exit code does not: a real arm, not a
# blind one.
YO_VERIFY='cat src.txt; exit 1'

t_yolo_default_caps() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify "$YO_VERIFY" --shape fresh --yolo \
		--neg-control-file src.txt
	assert_rc 0 "t_yolo_default_caps init"

	assert_eq "$(yo_front "$proj" max_minutes)" "240" "t_yolo_default_caps max_minutes"
	assert_eq "$(yo_front "$proj" max_usd)" "0" "t_yolo_default_caps no money cap by default"
	assert_eq "$(yo_front "$proj" max_iterations)" "40" "t_yolo_default_caps max_iterations"
	assert_eq "$(yo_front "$proj" stall_after)" "3" "t_yolo_default_caps stall_after"
	assert_eq "$(yo_front "$proj" yolo)" "1" "t_yolo_default_caps yolo"
	assert_eq "$(yo_front "$proj" fail_closed)" "1" "t_yolo_default_caps fail_closed"

	rm -rf "$home" "$proj"
}

t_yolo_explicit_cap_kept() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify "$YO_VERIFY" --shape fresh --yolo --max-usd 10 \
		--neg-control-file src.txt
	assert_rc 0 "t_yolo_explicit_cap_kept init"

	assert_eq "$(yo_front "$proj" max_usd)" "10" "t_yolo_explicit_cap_kept max_usd kept"
	assert_eq "$(yo_front "$proj" max_minutes)" "240" "t_yolo_explicit_cap_kept max_minutes defaulted"
	assert_eq "$(yo_front "$proj" max_iterations)" "40" "t_yolo_explicit_cap_kept max_iterations defaulted"
	assert_eq "$(yo_front "$proj" stall_after)" "3" "t_yolo_explicit_cap_kept stall_after defaulted"

	rm -rf "$home" "$proj"
}

t_yolo_child_argv() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify "$YO_VERIFY" --shape fresh --yolo \
		--neg-control-file src.txt >/dev/null
	yo_cli_in "$proj" "$home" loop run --dry-run
	assert_not_contains "$OUT" "--max-budget-usd" "t_yolo_child_argv no money cap by default"
	assert_contains "$OUT" "--permission-prompts none" "t_yolo_child_argv no-prompt"

	rm -rf "$home" "$proj"
}

# F2 (spec.md:17, FR-04): --yolo has nobody watching an unattended run, so
# the negative control is the mandatory gate — init must refuse before it
# ever arms on a verifier that was never proven able to fail.
t_yolo_requires_neg_control() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify true --allow-green --yolo
	assert_rc 3 "t_yolo_requires_neg_control rc"
	assert_contains "$ERR" "--neg-control-file" "t_yolo_requires_neg_control names-flag"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_yolo_requires_neg_control writes-nothing"

	rm -rf "$home" "$proj"
}

# F3 (design.md:31-32): a successful --yolo arm with a control records which
# file the control broke and when it last passed; a run with neither --yolo
# nor a control records neither.
t_yolo_writes_neg_control_front() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify "$YO_VERIFY" --yolo --neg-control-file src.txt
	assert_rc 0 "t_yolo_writes_neg_control_front init"
	assert_eq "$(yo_front "$proj" neg_control_file)" "src.txt" "t_yolo_writes_neg_control_front file"
	assert_contains "$(yo_front "$proj" neg_control_at)" "T" "t_yolo_writes_neg_control_front at is ISO-ish (non-empty, has a T)"

	rm -rf "$home" "$proj"
}

t_no_control_neg_control_front_empty() {
	local proj home
	proj=$(yo_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify "$YO_VERIFY"
	assert_rc 0 "t_no_control_neg_control_front_empty init"
	assert_eq "$(yo_front "$proj" neg_control_file)" "" "t_no_control_neg_control_front_empty file empty"
	assert_eq "$(yo_front "$proj" neg_control_at)" "" "t_no_control_neg_control_front_empty at empty"

	rm -rf "$home" "$proj"
}

t_no_yolo_argv_unchanged() {
	local proj home
	proj=$(tmp_repo)
	home=$(tmp_dir)

	yo_cli_in "$proj" "$home" loop init "make done" --verify false --shape fresh >/dev/null
	yo_cli_in "$proj" "$home" loop run --dry-run
	assert_not_contains "$OUT" "--permission-prompts" "t_no_yolo_argv_unchanged no-prompt-flag absent"

	rm -rf "$home" "$proj"
}
