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

# nc_verify_script <project-dir> <script-body> — writes and commits a verify
# script; it must be tracked or the dirty-tree preflight refuses to run it.
nc_verify_script() {
	local proj=$1 body=$2
	printf '%s' "$body" >"$proj/verify.sh"
	(cd "$proj" && git add verify.sh && git commit -q -m "add verify.sh") >/dev/null 2>&1
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
	local proj home before_hash
	proj=$(nc_repo)
	home=$(tmp_dir)
	before_hash=$(cd "$proj" && git hash-object app.txt)

	# Fails fast while app.txt has content (the "before" run); once the
	# control truncates app.txt, it hangs well past the 1s verify-timeout,
	# so the "after" run is interrupted by its own timeout (rc 124) — the
	# verifier hung, not the control, so the message names that.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 5; exit 1; fi'

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--verify-timeout 1 --neg-control-file app.txt
	assert_rc 6 "t_negcontrol_restores_tree rc"
	assert_contains "$ERR" "verify-timeout" "t_negcontrol_restores_tree names-timeout"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_restores_tree writes-nothing"
	# A command-substitution string comparison strips trailing newlines and
	# checks one file's text, not the tree; hash-object pins exact bytes and
	# status --porcelain pins the whole tree (loop scratch under .claude excluded).
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_restores_tree tree-clean"
	assert_eq "$(cd "$proj" && git hash-object app.txt)" "$before_hash" "t_negcontrol_restores_tree tree-byte-identical"

	rm -rf "$home" "$proj"
}

t_negcontrol_real_change_arms() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	# A genuine verifier: green while app.txt has content, red once broken.
	# A verdict that compares only masked output text never distinguishes
	# these runs (both print nothing), so ignoring the exit code here
	# ships REFUSED instead of ARMED.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "test -s app.txt" --allow-green \
		--neg-control-file app.txt
	assert_rc 0 "t_negcontrol_real_change_arms rc"
	assert_file_exists "$proj/.claude/loop/loop.md" "t_negcontrol_real_change_arms arms"
	assert_eq "$(cat "$proj/app.txt")" "the app" "t_negcontrol_real_change_arms tree-restored"

	rm -rf "$home" "$proj"
}

t_negcontrol_not_restored_exit5() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	# The verifier itself makes the target unrestorable — replaces it with
	# a directory partway through the break — so neither restore method
	# (the shell trap's blob read, or Node's own byte-write from what it
	# read before the break) can put a regular file back.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else rm -f app.txt; mkdir app.txt; exit 1; fi'

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--neg-control-file app.txt
	assert_rc 5 "t_negcontrol_not_restored_exit5 rc"
	assert_contains "$ERR" "app.txt" "t_negcontrol_not_restored_exit5 names-file"
	assert_contains "$ERR" "human must look" "t_negcontrol_not_restored_exit5 names-verdict"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_not_restored_exit5 writes-nothing"

	rm -rf "$home" "$proj"
}

t_negcontrol_edit_after_exit_survives() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	# A process left running beside Node after the CLI exits could revert
	# whatever the operator writes next. Break, verifier and restore run as
	# one synchronous shell, so nothing outlives the command; a write made
	# right after the CLI returns must still be there later.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 4 "t_negcontrol_edit_after_exit_survives rc"
	printf 'MY NEW WORK' >"$proj/app.txt"
	sleep 2
	assert_eq "$(cat "$proj/app.txt")" "MY NEW WORK" "t_negcontrol_edit_after_exit_survives edit-survives"

	rm -rf "$home" "$proj"
}

t_negcontrol_sigint_kills_without_arming() {
	local proj home before_hash pid outf errf i
	proj=$(nc_repo)
	home=$(tmp_dir)
	before_hash=$(cd "$proj" && git hash-object app.txt)
	outf=$(tmp_dir)/out
	errf=$(tmp_dir)/err
	# Unlike the other tests here, this verifier WOULD detect the break and
	# arm if left to run to completion (green while app.txt has content,
	# green again once it is gone, after a slow settle) — proving Ctrl-C
	# actually stops the arm, not that this particular verifier survives.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 5; exit 0; fi'

	# A real Ctrl-C reaches the whole foreground process group, not just
	# the CLI's own pid, which is what lets the shell's own trap cover it;
	# `set -m` puts the background job in its own group so `kill -INT
	# -$pid` reproduces that. `exec` so $! is the node pid itself.
	set -m
	(cd "$proj" && HOME="$home" exec node "$NC_CLI_PATH" loop init "grow the app" --verify "sh verify.sh" \
		--neg-control-file app.txt >"$outf" 2>"$errf") &
	pid=$!
	set +m
	i=0
	while [ -s "$proj/app.txt" ] && [ "$i" -lt 50 ]; do
		sleep 0.1
		i=$((i + 1))
	done
	kill -INT -"$pid" 2>/dev/null
	wait "$pid"
	# shellcheck disable=SC2034  # RC is the global assert_rc reads
	RC=$?
	sleep 1

	# Node cannot run a JS signal callback while spawnSync blocks the one
	# thread, so the CLI dies from SIGINT's own default disposition rather
	# than completing the run and arming on the verdict it would otherwise
	# have reached.
	assert_rc 130 "t_negcontrol_sigint_kills_without_arming rc"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_sigint_kills_without_arming writes-nothing"
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_sigint_kills_without_arming tree-clean"
	assert_eq "$(cd "$proj" && git hash-object app.txt)" "$before_hash" "t_negcontrol_sigint_kills_without_arming tree-byte-identical"

	rm -rf "$home" "$proj"
}

t_negcontrol_mktemp_refuses() {
	local proj home i
	# A blind verifier whose only output is a fresh mktemp path every call —
	# letters and digits, unmasked by a digit-only normalization — must
	# still read as unchanged across the break, every time, not by luck.
	for i in 1 2 3 4 5 6 7 8 9 10; do
		proj=$(nc_repo)
		home=$(tmp_dir)
		nc_cli_in "$proj" "$home" loop init "grow the app" --verify "mktemp -u; true" --allow-green \
			--neg-control-file app.txt
		assert_rc 4 "t_negcontrol_mktemp_refuses rc (run $i)"
		rm -rf "$home" "$proj"
	done
}

t_negcontrol_digit_output_change_arms() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	# The exit code never changes (always 1) but the byte count in the
	# output does — a real, break-caused signal a normalization that
	# collapses every digit run would erase.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify 'echo "bytes: $(wc -c < app.txt)"; exit 1' \
		--neg-control-file app.txt
	assert_rc 0 "t_negcontrol_digit_output_change_arms rc"
	assert_file_exists "$proj/.claude/loop/loop.md" "t_negcontrol_digit_output_change_arms arms"

	rm -rf "$home" "$proj"
}

t_negcontrol_random_output_refuses() {
	local proj home i
	# The exit code never changes and the output differs on every single
	# call, including the two calls on the UNBROKEN tree (cmdInit's own
	# baseline and the control's "before"), for a reason that has nothing
	# to do with the break. Unstable output must not be trusted, so only
	# the (unchanged) exit code counts — every time, not by luck.
	for i in 1 2 3 4 5 6 7 8 9 10; do
		proj=$(nc_repo)
		home=$(tmp_dir)
		nc_cli_in "$proj" "$home" loop init "grow the app" --verify 'echo "run $((RANDOM % 999))"; exit 1' \
			--neg-control-file app.txt
		assert_rc 4 "t_negcontrol_random_output_refuses rc (run $i)"
		rm -rf "$home" "$proj"
	done
}

t_negcontrol_pid_output_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify 'echo $$; true' --allow-green \
		--neg-control-file app.txt
	assert_rc 4 "t_negcontrol_pid_output_refuses rc"
	assert_contains "$ERR" "only its exit code can be trusted" "t_negcontrol_pid_output_refuses names-reason"

	rm -rf "$home" "$proj"
}

t_negcontrol_stable_error_name_change_arms() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	# Same exit code (1) either side of the break; only the printed error
	# name changes, and it is identical on the two unbroken runs (cmdInit's
	# baseline and the control's own "before"), so the control can trust it.
	nc_cli_in "$proj" "$home" loop init "grow the app" \
		--verify 'if [ -s app.txt ]; then echo TimeoutError; else echo ValueError; fi; exit 1' \
		--neg-control-file app.txt
	assert_rc 0 "t_negcontrol_stable_error_name_change_arms rc"
	assert_file_exists "$proj/.claude/loop/loop.md" "t_negcontrol_stable_error_name_change_arms arms"

	rm -rf "$home" "$proj"
}

t_negcontrol_stable_count_change_arms() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	nc_cli_in "$proj" "$home" loop init "grow the app" \
		--verify 'if [ -s app.txt ]; then echo "0 tests failed"; else echo "3 tests failed"; fi; exit 1' \
		--neg-control-file app.txt
	assert_rc 0 "t_negcontrol_stable_count_change_arms rc"
	assert_file_exists "$proj/.claude/loop/loop.md" "t_negcontrol_stable_count_change_arms arms"

	rm -rf "$home" "$proj"
}

t_negcontrol_verifier_removes_target_exits1() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	# Deletes app.txt on its SECOND call (the control's own "before" run),
	# not its first (cmdInit's own pre-gate check, which must still pass
	# preflight untouched) — so the failure surfaces once the control is
	# already running, not as an exit-3 input problem.
	nc_verify_script "$proj" 'n=$(cat .n 2>/dev/null || echo 0); echo $((n + 1)) >.n; if [ "$n" = "1" ]; then rm -f app.txt; fi; exit 1'

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--neg-control-file app.txt
	assert_rc 1 "t_negcontrol_verifier_removes_target_exits1 rc"
	assert_contains "$ERR" "app.txt" "t_negcontrol_verifier_removes_target_exits1 names-file"
	assert_not_contains "$ERR" "ENOENT" "t_negcontrol_verifier_removes_target_exits1 no-raw-node-error"

	rm -rf "$home" "$proj"
}

t_negcontrol_unrelated_untracked_runs() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	printf 'stray\n' >"$proj/stray.tmp"

	# A stray untracked file elsewhere in the tree is not the target's
	# business; the control must still run rather than refuse at exit 3.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 4 "t_negcontrol_unrelated_untracked_runs rc"
	assert_contains "$ERR" "did not change" "t_negcontrol_unrelated_untracked_runs names-verdict"

	rm -rf "$home" "$proj"
}

t_negcontrol_symlink_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	rm -f "$proj/app.txt"
	ln -s /etc/hosts "$proj/app.txt"
	(cd "$proj" && git add -A && git commit -q -m "app.txt becomes a symlink") >/dev/null 2>&1

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 3 "t_negcontrol_symlink_refuses rc"
	assert_contains "$ERR" "app.txt" "t_negcontrol_symlink_refuses names-file"
	assert_contains "$ERR" "symlink" "t_negcontrol_symlink_refuses names-reason"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_symlink_refuses writes-nothing"

	rm -rf "$home" "$proj"
}

t_negcontrol_dirty_tree_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	printf 'uncommitted\n' >>"$proj/app.txt"

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 3 "t_negcontrol_dirty_tree_refuses rc"
	assert_contains "$ERR" "app.txt" "t_negcontrol_dirty_tree_refuses names-file"
	assert_contains "$ERR" "uncommitted" "t_negcontrol_dirty_tree_refuses names-reason"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_dirty_tree_refuses writes-nothing"

	rm -rf "$home" "$proj"
}

t_negcontrol_untracked_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	printf 'untracked\n' >"$proj/other.txt"

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file other.txt
	assert_rc 3 "t_negcontrol_untracked_refuses rc"
	assert_contains "$ERR" "other.txt" "t_negcontrol_untracked_refuses names-file"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_untracked_refuses writes-nothing"

	rm -rf "$home" "$proj"
}

t_negcontrol_missing_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file nope.txt
	assert_rc 3 "t_negcontrol_missing_refuses rc"
	assert_contains "$ERR" "nope.txt" "t_negcontrol_missing_refuses names-file"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_missing_refuses writes-nothing"

	rm -rf "$home" "$proj"
}

t_negcontrol_directory_refuses() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/adir"
	printf 'x\n' >"$proj/adir/f.txt"
	(cd "$proj" && git add -A && git commit -q -m "add a directory") >/dev/null 2>&1

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file adir
	assert_rc 3 "t_negcontrol_directory_refuses rc"
	assert_contains "$ERR" "adir" "t_negcontrol_directory_refuses names-file"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_directory_refuses writes-nothing"

	rm -rf "$home" "$proj"
}
