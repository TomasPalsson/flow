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

t_negcontrol_survives_refuses_stock_bash() {
	local proj home bindir
	proj=$(nc_repo)
	home=$(tmp_dir)
	bindir=$(tmp_dir)
	# Stock /bin/bash 3.2 (and Linux bash 5.2) print job-control notices
	# such as "[1]+ Done" on the control's own stderr; that noise must not
	# read as the verifier reacting to the break.
	ln -s "$(command -v node)" "$bindir/node"
	PATH="$bindir:/usr/bin:/bin" nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file app.txt
	assert_rc 4 "t_negcontrol_survives_refuses_stock_bash rc"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_survives_refuses_stock_bash writes-nothing"

	rm -rf "$home" "$proj" "$bindir"
}

t_negcontrol_restores_tree() {
	local proj home before_hash started elapsed
	proj=$(nc_repo)
	home=$(tmp_dir)
	before_hash=$(cd "$proj" && git hash-object app.txt)

	# Fails fast while app.txt has content (the "before" run); once the
	# control truncates app.txt, it hangs well past the 1s verify-timeout,
	# so the "after" run is interrupted by its own timeout (rc 124) — the
	# verifier hung, not the control, so the message names that.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 5; exit 1; fi'

	started=$(date +%s)
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--verify-timeout 1 --neg-control-file app.txt
	elapsed=$(($(date +%s) - started))
	assert_rc 6 "t_negcontrol_restores_tree rc"
	assert_eq "$([ "$elapsed" -lt 3 ] && echo bounded || echo "took ${elapsed}s")" "bounded" "t_negcontrol_restores_tree timeout-enforced"
	assert_contains "$ERR" "verify-timeout" "t_negcontrol_restores_tree names-timeout"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_restores_tree writes-nothing"
	# A command-substitution string comparison strips trailing newlines and
	# checks one file's text, not the tree; hash-object pins exact bytes and
	# status --porcelain pins the whole tree (loop scratch under .claude excluded).
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_restores_tree tree-clean"
	assert_eq "$(cd "$proj" && git hash-object app.txt)" "$before_hash" "t_negcontrol_restores_tree tree-byte-identical"

	rm -rf "$home" "$proj"
}

t_negcontrol_broken_run_timeout_bounded() {
	local proj home started elapsed
	proj=$(nc_repo)
	home=$(tmp_dir)
	# Hangs for 15s only once app.txt is broken; --verify-timeout 1 must cut
	# that run off at about 1s, and the hung verifier's own child must not
	# outlive the CLI.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 15 & echo $! >"$HOME/sleep.pid"; wait; exit 1; fi'

	started=$(date +%s)
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" \
		--verify-timeout 1 --neg-control-file app.txt
	elapsed=$(($(date +%s) - started))
	assert_rc 6 "t_negcontrol_broken_run_timeout_bounded rc"
	assert_eq "$([ "$elapsed" -lt 3 ] && echo bounded || echo "took ${elapsed}s")" "bounded" "t_negcontrol_broken_run_timeout_bounded under-3s"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_broken_run_timeout_bounded writes-nothing"
	assert_eq "$(cat "$proj/app.txt")" "the app" "t_negcontrol_broken_run_timeout_bounded tree-restored"
	assert_eq "$(kill -0 "$(cat "$home/sleep.pid")" 2>/dev/null && echo alive || echo gone)" "gone" "t_negcontrol_broken_run_timeout_bounded nothing-outlives"

	kill "$(cat "$home/sleep.pid")" 2>/dev/null
	rm -rf "$home" "$proj"
}

t_negcontrol_keeps_executable_bit() {
	local proj home
	proj=$(nc_repo)
	home=$(tmp_dir)
	printf '#!/bin/sh\necho run\n' >"$proj/run.sh"
	chmod 755 "$proj/run.sh"
	nc_verify_script "$proj" 'if [ -s run.sh ]; then exit 1; else sleep 5; exit 1; fi'
	(cd "$proj" && git add run.sh && git commit -q -m "add run.sh") >/dev/null 2>&1

	# Arms, refuses as survived, and refuses on timeout: every exit path
	# must hand back run.sh as the same executable file git has.
	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "test -s run.sh" --allow-green \
		--neg-control-file run.sh
	assert_rc 0 "t_negcontrol_keeps_executable_bit armed rc"
	# Arming itself writes .gitignore (the loop's own scratch rules).
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude' ':!.gitignore')" "" "t_negcontrol_keeps_executable_bit armed tree-clean"
	assert_eq "$([ -x "$proj/run.sh" ] && echo executable || echo lost)" "executable" "t_negcontrol_keeps_executable_bit armed mode"
	rm -rf "$proj/.claude" "$proj/.gitignore"

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "true" --allow-green \
		--neg-control-file run.sh
	assert_rc 4 "t_negcontrol_keeps_executable_bit survived rc"
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_keeps_executable_bit survived tree-clean"

	nc_cli_in "$proj" "$home" loop init "grow the app" --verify "sh verify.sh" --verify-timeout 1 \
		--neg-control-file run.sh
	assert_rc 6 "t_negcontrol_keeps_executable_bit timed-out rc"
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_keeps_executable_bit timed-out tree-clean"

	rm -rf "$home" "$proj"
}

t_negcontrol_interrupted_restores() {
	local proj home before_hash pid outf errf i
	proj=$(nc_repo)
	home=$(tmp_dir)
	chmod 755 "$proj/app.txt"
	(cd "$proj" && git commit -q -am "app.txt is executable") >/dev/null 2>&1
	before_hash=$(cd "$proj" && git hash-object app.txt)
	outf=$(tmp_dir)/out
	errf=$(tmp_dir)/err
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 5 & echo $! >"$HOME/sleep.pid"; wait; exit 1; fi'

	# A SIGTERM delivered to the CLI's pid alone (an agent harness, a
	# subprocess timeout) while it is blocked in the "after" verifier run
	# must not return with the target still broken. Sent once the verifier
	# is running on the truncated app.txt (polled on its pid file, not
	# slept: a slow node start must not land the kill before the break and
	# pass vacuously). `exec` so $! is the node pid itself.
	(cd "$proj" && HOME="$home" exec node "$NC_CLI_PATH" loop init "grow the app" --verify "sh verify.sh" \
		--neg-control-file app.txt >"$outf" 2>"$errf") &
	pid=$!
	i=0
	while [ ! -s "$home/sleep.pid" ] && [ "$i" -lt 50 ]; do
		sleep 0.1
		i=$((i + 1))
	done
	kill -TERM "$pid" 2>/dev/null
	wait "$pid"

	# Checked the instant the CLI returns, then the operator's next write
	# must survive: nothing may restore behind their back later.
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_interrupted_restores tree-clean"
	assert_eq "$(cd "$proj" && git hash-object app.txt)" "$before_hash" "t_negcontrol_interrupted_restores tree-byte-identical"
	printf 'MY NEW WORK' >"$proj/app.txt"
	sleep 2
	assert_eq "$(cat "$proj/app.txt")" "MY NEW WORK" "t_negcontrol_interrupted_restores edit-survives"
	assert_eq "$(kill -0 "$(cat "$home/sleep.pid")" 2>/dev/null && echo alive || echo gone)" "gone" "t_negcontrol_interrupted_restores nothing-outlives"

	kill "$(cat "$home/sleep.pid")" 2>/dev/null
	rm -rf "$home" "$proj" "$(dirname "$outf")" "$(dirname "$errf")"
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
	# (the shell trap's copy from its backup, or Node's own byte-write from what it
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
	chmod 755 "$proj/app.txt"
	(cd "$proj" && git commit -q -am "app.txt is executable") >/dev/null 2>&1
	before_hash=$(cd "$proj" && git hash-object app.txt)
	outf=$(tmp_dir)/out
	errf=$(tmp_dir)/err
	# Unlike the other tests here, this verifier WOULD detect the break and
	# arm if left to run to completion (green while app.txt has content,
	# green again once it is gone, after a slow settle) — proving Ctrl-C
	# actually stops the arm, not that this particular verifier survives.
	nc_verify_script "$proj" 'if [ -s app.txt ]; then exit 1; else sleep 5 & echo $! >"$HOME/sleep.pid"; wait; exit 0; fi'

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
	while [ ! -s "$home/sleep.pid" ] && [ "$i" -lt 50 ]; do
		sleep 0.1
		i=$((i + 1))
	done
	kill -INT -"$pid" 2>/dev/null
	wait "$pid"
	# shellcheck disable=SC2034  # RC is the global assert_rc reads
	RC=$?

	# Checked the instant the CLI returns: the tree must already be back,
	# and the operator's next write must survive.
	assert_eq "$(cd "$proj" && git status --porcelain -- . ':!.claude')" "" "t_negcontrol_sigint_kills_without_arming tree-clean"
	assert_eq "$(cd "$proj" && git hash-object app.txt)" "$before_hash" "t_negcontrol_sigint_kills_without_arming tree-byte-identical"
	printf 'MY NEW WORK' >"$proj/app.txt"
	sleep 2
	assert_eq "$(cat "$proj/app.txt")" "MY NEW WORK" "t_negcontrol_sigint_kills_without_arming edit-survives"
	assert_eq "$(kill -0 "$(cat "$home/sleep.pid")" 2>/dev/null && echo alive || echo gone)" "gone" "t_negcontrol_sigint_kills_without_arming nothing-outlives"
	assert_rc 130 "t_negcontrol_sigint_kills_without_arming rc"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_sigint_kills_without_arming writes-nothing"

	kill "$(cat "$home/sleep.pid")" 2>/dev/null
	rm -rf "$home" "$proj" "$(dirname "$outf")" "$(dirname "$errf")"
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

# yolo_recipe_repo — a tmp_repo with the --yolo bootstrap's own task-list
# gate: .claude/loop/tasks.json with one unproven item over app.js, plus a
# real scoped test (test_app.js) that passes while app.js has content and
# fails, with distinct output, once it is emptied — exactly what
# negcontrol.js's induced break does to --neg-control-file.
yolo_recipe_repo() {
	local d
	d=$(tmp_repo)
	printf 'module.exports = 1;\n' >"$d/app.js"
	printf "const fs=require('fs');if(fs.readFileSync('app.js','utf8').trim()){process.exit(0);}console.log('app.js is empty');process.exit(1);\n" >"$d/test_app.js"
	mkdir -p "$d/.claude/loop"
	printf '{"items":[{"files":["app.js"],"passes":false}]}' >"$d/.claude/loop/tasks.json"
	(cd "$d" && git add app.js test_app.js && git commit -q -m "add app.js and its scoped test") >/dev/null 2>&1
	printf '%s' "$d"
}

YR_GATE='node -e "const T=require(\"./.claude/loop/tasks.json\");process.exit(T.items.every(i=>i.passes)?0:1)"'
YR_NEW_RECIPE="node test_app.js; t=\$?; $YR_GATE && exit \$t"
YR_OLD_RECIPE="$YR_GATE && node test_app.js"

# F1: the OLD `<gate> && <scoped test command>` form (yolo-bootstrap.md §3
# before this fix) never runs the scoped test at init — every task item is
# unproven, so the gate alone exits 1 and short-circuits the `&&` — so the
# negative control's before/after runs are identical (rc 1, empty output)
# and it reads the break as survived. Documents the bug this fix removes;
# not itself required by the brief.
t_negcontrol_yolo_recipe_old_form_survives() {
	local proj home
	proj=$(yolo_recipe_repo)
	home=$(tmp_dir)

	nc_cli_in "$proj" "$home" loop init "g" --verify "$YR_OLD_RECIPE" \
		--neg-control-file app.js --yolo
	assert_rc 4 "t_negcontrol_yolo_recipe_old_form_survives rc"
	assert_file_missing "$proj/.claude/loop/loop.md" "t_negcontrol_yolo_recipe_old_form_survives writes-nothing"

	rm -rf "$home" "$proj"
}

# F1: the NEW recipe (scoped tests first, unconditionally; the tasks.json
# gate only overrides the scoped tests' own exit code) always runs
# test_app.js, so its output changes the moment app.js is broken even though
# the gate's own exit code (1, every item still unproven) does not — the
# control reads that as red-then-restored and init proceeds past the gate.
t_negcontrol_yolo_recipe_arms() {
	local proj home
	proj=$(yolo_recipe_repo)
	home=$(tmp_dir)

	nc_cli_in "$proj" "$home" loop init "g" --verify "$YR_NEW_RECIPE" \
		--neg-control-file app.js --yolo
	assert_rc 0 "t_negcontrol_yolo_recipe_arms arms (not the survived exit 4)"
	assert_file_exists "$proj/.claude/loop/loop.md" "t_negcontrol_yolo_recipe_arms writes-contract"
	assert_eq "$(cat "$proj/app.js")" "module.exports = 1;" "t_negcontrol_yolo_recipe_arms tree-restored"

	rm -rf "$home" "$proj"
}
