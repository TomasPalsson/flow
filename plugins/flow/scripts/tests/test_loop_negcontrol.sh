#!/usr/bin/env bash
# test_loop_negcontrol.sh — the arming safety net (spec .specs/010-autonomous-
# loop-on-ramp-yolo, B3/B4, FR-04/FR-05/FR-11) for
# plugins/flow/bin/lib/loop/negcontrol.js and init.js's `--neg-control-file` gate.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_loop.sh having been sourced.
set -u

NC_CLI_PATH=""
NC_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
NC_CLI_PATH="$NC_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && NC_CLI_PATH="$SCAN_DIR/../bin/flow"

# nc_cli_in <project-dir> <home-dir> <args...>
nc_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$NC_CLI_PATH" "$@"
}

# nc_repo — a tmp_repo with one tracked, non-empty file to break: app.txt.
nc_repo() {
	local d
	d=$(tmp_repo)
	printf 'the app\n' >"$d/app.txt"
	(cd "$d" && git add app.txt && git commit -q -m "add app.txt") >/dev/null 2>&1
	printf '%s' "$d"
}

t_negcontrol_survives_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	# "true" always exits 0 no matter what app.txt contains, so the control's
	# before/after verdicts never change: the verifier is blind to the break.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 4 "t_negcontrol_survives_refuses rc"
	assert_contains "$ERR" "app.txt" "t_negcontrol_survives_refuses names-file"
	assert_contains "$ERR" "did not change" "t_negcontrol_survives_refuses names-verdict"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_survives_refuses writes-nothing"
	assert_eq "$(cat "$proj/app.txt")" "the app" "t_negcontrol_survives_refuses tree-restored"

	rm -rf "$home" "$proj"
}

t_negcontrol_restores_tree() {
	local proj home verify
	proj=$(nc_repo)
	home=$(tmp_dir)

	# Fails fast while app.txt has content (the "before" run); once the
	# control truncates app.txt, it hangs well past the 1s verify-timeout,
	# so the "after" run is interrupted by its own timeout (rc 124).
	verify='if [ -s app.txt ]; then exit 1; else sleep 5; exit 1; fi'
	printf '%s' "$verify" >"$proj/verify.sh"

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--verify-timeout 1 --neg-control-file app.txt
	assert_rc 6 "t_negcontrol_restores_tree rc"
	assert_contains "$ERR" "time bound" "t_negcontrol_restores_tree names-timeout"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_restores_tree writes-nothing"
	assert_eq "$(cat "$proj/app.txt")" "the app" "t_negcontrol_restores_tree tree-byte-identical"

	rm -rf "$home" "$proj"
}
