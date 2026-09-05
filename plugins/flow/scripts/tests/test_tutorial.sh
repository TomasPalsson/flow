#!/usr/bin/env bash
# test_tutorial.sh — tests for the interactive tutorial runner (lib/tutorial.js)
# and lessons 1-3 (lib/lessons/01-doctor.js, 02-init.js, 03-progress-and-next.js).
# Self-contained: does not assume any other test_*.sh has been sourced in the
# same run.sh invocation (TEST_ONLY=test_tutorial.sh runs this file alone).
#
# bin/flow has no `tutorial` dispatch yet (a later slice wires it up), so
# every test below invokes lib/tutorial.js directly: `node lib/tutorial.js ...`.
set -u

TUTORIAL_PATH="$SCAN_DIR/../bin/lib/tutorial.js"

# The one-liner lesson 3's tryIt suggests: insert a `- resume: /flow` bullet
# right under PROGRESS.md's "## Now" heading, then run `flow next`.
TT_EDIT_AND_NEXT="awk '1;/^## Now\$/{print \"- resume: /flow\"}' PROGRESS.md > p.tmp && mv p.tmp PROGRESS.md && flow next"

# tt_in <dir> <home> <tutorial-args...>
# Runs `node $TUTORIAL_PATH <args>` with cwd=<dir> and HOME=<home>, inheriting
# whatever stdin the caller redirected onto THIS call (a `<file` redirection
# on the call itself — never a pipe, which would fork tt_in into a subshell
# and lose the RC/OUT/ERR globals run_cmd sets). Sets RC/OUT/ERR.
tt_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$TUTORIAL_PATH" "$@"
}

# tt_stdin <line...> — writes each argument as its own line to a fresh temp
# file and prints its path, for `tt_in ... <"$(tt_stdin ...)"`.
tt_stdin() {
	local f
	f=$(mktemp "${TMPDIR:-/tmp}/flow-tutorial-stdin.XXXXXX")
	printf '%s\n' "$@" >"$f"
	printf '%s' "$f"
}

tt_progress_path() {
	printf '%s' "$1/.claude/flow-tutorial-progress.json"
}

# ---------------------------------------------------------------------------
# B9 — sandbox creation: mkdtemp-style dir, one git commit of README.md, and
# a `flow` shim on a sibling `<sandbox>-bin` dir.
# ---------------------------------------------------------------------------

t_tt_sandbox_created_with_shim() {
	local home dir sandbox stdinf
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb1"
	stdinf=$(tt_stdin q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_sandbox_created_with_shim rc"
	assert_file_exists "$sandbox/.git" "t_tt_sandbox_created_with_shim git init"
	assert_file_exists "$sandbox/README.md" "t_tt_sandbox_created_with_shim readme written"
	assert_file_exists "$sandbox-bin/flow" "t_tt_sandbox_created_with_shim shim written"
	run_cmd test -x "$sandbox-bin/flow"
	assert_rc 0 "t_tt_sandbox_created_with_shim shim executable"
	assert_contains "$(cat "$sandbox-bin/flow")" "exec" "t_tt_sandbox_created_with_shim shim execs the real cli"
	run_cmd git -C "$sandbox" rev-list --count HEAD
	assert_eq "$OUT" "1" "t_tt_sandbox_created_with_shim exactly one commit"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B10 — --list: discovers all 3 lessons, in order, all not-started initially.
# ---------------------------------------------------------------------------

t_tt_list_shows_three_lessons_not_started() {
	local home dir
	home=$(tmp_dir)
	dir=$(tmp_dir)

	tt_in "$dir" "$home" --list </dev/null
	assert_rc 0 "t_tt_list_shows_three_lessons_not_started rc"
	assert_contains "$OUT" "1. " "t_tt_list_shows_three_lessons_not_started numbers lesson 1"
	assert_contains "$OUT" "2. " "t_tt_list_shows_three_lessons_not_started numbers lesson 2"
	assert_contains "$OUT" "3. " "t_tt_list_shows_three_lessons_not_started numbers lesson 3"
	assert_contains "$OUT" "doctor" "t_tt_list_shows_three_lessons_not_started lesson 1 title"
	assert_contains "$OUT" "init" "t_tt_list_shows_three_lessons_not_started lesson 2 title"
	assert_contains "$OUT" "next" "t_tt_list_shows_three_lessons_not_started lesson 3 title"
	assert_eq "$(printf '%s' "$OUT" | grep -c 'not-started')" "3" "t_tt_list_shows_three_lessons_not_started all not-started"

	rm -rf "$home" "$dir"
}

# ---------------------------------------------------------------------------
# B11 — lesson 1 renders with an embedded `$` prompt.
# ---------------------------------------------------------------------------

t_tt_lesson1_renders_prompt() {
	local home dir sandbox stdinf
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb2"
	stdinf=$(tt_stdin q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_lesson1_renders_prompt rc"
	assert_contains "$OUT" "Lesson 1/3" "t_tt_lesson1_renders_prompt shows lesson 1 of 3"
	assert_contains "$OUT" "flow doctor" "t_tt_lesson1_renders_prompt mentions the command to try"
	assert_contains "$OUT" "$sandbox \$ " "t_tt_lesson1_renders_prompt embeds a dollar prompt"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B12 — a typed command actually runs in the sandbox; a command that does not
# satisfy the lesson's check does not advance the cursor.
# ---------------------------------------------------------------------------

t_tt_wrong_command_runs_but_does_not_advance() {
	local home dir sandbox stdinf
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb3"
	stdinf=$(tt_stdin "echo hello-from-sandbox" q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_wrong_command_runs_but_does_not_advance rc"
	assert_contains "$OUT" "hello-from-sandbox" "t_tt_wrong_command_runs_but_does_not_advance command actually ran"
	assert_eq "$(printf '%s' "$OUT" | grep -c 'Lesson 1/3')" "2" "t_tt_wrong_command_runs_but_does_not_advance still on lesson 1"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B13 — lesson 1 advances to lesson 2 once `flow doctor` passes its check.
# ---------------------------------------------------------------------------

t_tt_lesson1_advances_on_flow_doctor() {
	local home dir sandbox stdinf
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb4"
	stdinf=$(tt_stdin "flow doctor" q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_lesson1_advances_on_flow_doctor rc"
	assert_contains "$OUT" "lesson 1 passed" "t_tt_lesson1_advances_on_flow_doctor announces the pass"
	assert_contains "$OUT" "Lesson 2/3" "t_tt_lesson1_advances_on_flow_doctor moved to lesson 2"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B14 — a full run through lessons 1-3 persists cursor and per-lesson status.
# ---------------------------------------------------------------------------

t_tt_full_run_persists_progress() {
	local home dir sandbox stdinf progress
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb5"
	stdinf=$(tt_stdin "flow doctor" "flow init" "$TT_EDIT_AND_NEXT" q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_full_run_persists_progress rc"
	assert_contains "$OUT" "Lesson 3/3" "t_tt_full_run_persists_progress reached lesson 3"
	assert_contains "$OUT" "lesson 3 passed" "t_tt_full_run_persists_progress lesson 3 passed"

	progress=$(tt_progress_path "$home")
	assert_file_exists "$progress" "t_tt_full_run_persists_progress progress file written"
	assert_contains "$(cat "$progress")" '"cursor": 3' "t_tt_full_run_persists_progress cursor persisted"
	assert_contains "$(cat "$progress")" '"1": "done"' "t_tt_full_run_persists_progress lesson 1 done persisted"
	assert_contains "$(cat "$progress")" '"2": "done"' "t_tt_full_run_persists_progress lesson 2 done persisted"
	assert_contains "$(cat "$progress")" '"3": "done"' "t_tt_full_run_persists_progress lesson 3 done persisted"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B15 — a second invocation (no --sandbox) resumes at the saved cursor and
# reuses the saved sandbox.
# ---------------------------------------------------------------------------

t_tt_resumes_at_saved_cursor() {
	local home dir sandbox stdinf1 stdinf2
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb6"
	stdinf1=$(tt_stdin "flow doctor" "flow init" "$TT_EDIT_AND_NEXT" q)
	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf1"
	assert_rc 0 "t_tt_resumes_at_saved_cursor first run rc"

	stdinf2=$(tt_stdin q)
	tt_in "$dir" "$home" <"$stdinf2"
	assert_rc 0 "t_tt_resumes_at_saved_cursor second run rc"
	assert_contains "$OUT" "Lesson 3/3" "t_tt_resumes_at_saved_cursor resumes at lesson 3"
	assert_not_contains "$OUT" "Lesson 1/3" "t_tt_resumes_at_saved_cursor does not restart at lesson 1"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf1" "$stdinf2"
}

# ---------------------------------------------------------------------------
# Regression (adversarial review, slice 2 fix round) — a relative --sandbox
# path is resolved against the cwd it was FIRST created in and persisted
# absolute, so a later resume (no --sandbox) from a *different* cwd still
# reuses that same sandbox instead of silently creating a new one relative
# to the new cwd. Not one of B9-B18/B27/B28: those never vary cwd between
# invocations, so this path was untested until now.
# ---------------------------------------------------------------------------

t_tt_resume_relative_sandbox_survives_cwd_change() {
	local home dirA dirB stdinf1 stdinf2 progress
	home=$(tmp_dir)
	dirA=$(tmp_dir)
	dirB=$(tmp_dir)
	stdinf1=$(tt_stdin "flow doctor" "flow init" "$TT_EDIT_AND_NEXT" q)
	tt_in "$dirA" "$home" --sandbox rel-sb <"$stdinf1"
	assert_rc 0 "t_tt_resume_relative_sandbox_survives_cwd_change first run rc"
	assert_file_exists "$dirA/rel-sb/.git" "t_tt_resume_relative_sandbox_survives_cwd_change sandbox created under first cwd"

	stdinf2=$(tt_stdin q)
	tt_in "$dirB" "$home" <"$stdinf2"
	assert_rc 0 "t_tt_resume_relative_sandbox_survives_cwd_change second run rc"
	assert_contains "$OUT" "Lesson 3/3" "t_tt_resume_relative_sandbox_survives_cwd_change resumes at lesson 3"
	assert_file_missing "$dirB/rel-sb" "t_tt_resume_relative_sandbox_survives_cwd_change does not create a new sandbox under second cwd"

	progress=$(tt_progress_path "$home")
	assert_contains "$(cat "$progress")" "\"sandboxDir\": \"$dirA/rel-sb\"" "t_tt_resume_relative_sandbox_survives_cwd_change progress stores the absolute path"

	rm -rf "$home" "$dirA" "$dirB" "$stdinf1" "$stdinf2"
}

# ---------------------------------------------------------------------------
# B16 — `s` skips (a status change, persisted) and moves forward; `b` only
# moves the cursor back, it never undoes a status.
# ---------------------------------------------------------------------------

t_tt_skip_and_back_semantics() {
	local home dir sandbox stdinf progress
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb7"
	stdinf=$(tt_stdin s b q)

	tt_in "$dir" "$home" --sandbox "$sandbox" <"$stdinf"
	assert_rc 0 "t_tt_skip_and_back_semantics rc"
	assert_contains "$OUT" "Lesson 2/3" "t_tt_skip_and_back_semantics s moves forward"
	assert_contains "$OUT" "[skipped]" "t_tt_skip_and_back_semantics b returns to the skipped lesson 1"

	progress=$(tt_progress_path "$home")
	assert_contains "$(cat "$progress")" '"1": "skipped"' "t_tt_skip_and_back_semantics status persisted as skipped"
	assert_contains "$(cat "$progress")" '"cursor": 1' "t_tt_skip_and_back_semantics cursor back at 1 after b"

	rm -rf "$home" "$dir" "$sandbox-bin" "$stdinf"
}

# ---------------------------------------------------------------------------
# B17 — --reset deletes the progress file; a fresh --list shows lesson 1
# again with every lesson not-started.
# ---------------------------------------------------------------------------

t_tt_reset_clears_progress() {
	local home dir progress
	home=$(tmp_dir)
	dir=$(tmp_dir)
	progress=$(tt_progress_path "$home")
	mkdir -p "$(dirname "$progress")"
	printf '{"version":1,"cursor":3,"sandboxDir":null,"statuses":{"1":"done","2":"done","3":"done"}}' >"$progress"

	tt_in "$dir" "$home" --reset </dev/null
	assert_rc 0 "t_tt_reset_clears_progress rc"
	assert_file_missing "$progress" "t_tt_reset_clears_progress progress file removed"

	tt_in "$dir" "$home" --list </dev/null
	assert_eq "$(printf '%s' "$OUT" | grep -c 'not-started')" "3" "t_tt_reset_clears_progress list shows fresh state"

	rm -rf "$home" "$dir"
}

# ---------------------------------------------------------------------------
# B18 — a corrupt progress file is INVALID_PROGRESS_FILE, not a crash.
# ---------------------------------------------------------------------------

t_tt_invalid_progress_file_errors() {
	local home dir sandbox progress
	home=$(tmp_dir)
	dir=$(tmp_dir)
	sandbox="$dir/sb8"
	progress=$(tt_progress_path "$home")
	mkdir -p "$(dirname "$progress")"
	printf 'not json at all' >"$progress"

	tt_in "$dir" "$home" --sandbox "$sandbox" </dev/null
	assert_rc 1 "t_tt_invalid_progress_file_errors rc"
	assert_contains "$ERR" "INVALID_PROGRESS_FILE" "t_tt_invalid_progress_file_errors reports the error code"

	rm -rf "$home" "$dir"
}

# ---------------------------------------------------------------------------
# B27 — --lesson N outside 1..lessonCount is LESSON_OUT_OF_RANGE.
# ---------------------------------------------------------------------------

t_tt_lesson_out_of_range_errors() {
	local home dir
	home=$(tmp_dir)
	dir=$(tmp_dir)

	tt_in "$dir" "$home" --lesson 0 </dev/null
	assert_rc 1 "t_tt_lesson_out_of_range_errors rc for 0"
	assert_contains "$ERR" "LESSON_OUT_OF_RANGE" "t_tt_lesson_out_of_range_errors reports the error code for 0"

	tt_in "$dir" "$home" --lesson 99 </dev/null
	assert_rc 1 "t_tt_lesson_out_of_range_errors rc for 99"
	assert_contains "$ERR" "LESSON_OUT_OF_RANGE" "t_tt_lesson_out_of_range_errors reports the error code for 99"

	rm -rf "$home" "$dir"
}

# ---------------------------------------------------------------------------
# B28 — a --sandbox path that cannot become a sandbox (a file sits in the
# way) is SANDBOX_CREATE_FAILED, not a crash.
# ---------------------------------------------------------------------------

t_tt_sandbox_create_failed_errors() {
	local home dir blocked
	home=$(tmp_dir)
	dir=$(tmp_dir)
	blocked="$dir/blocked-file"
	printf 'not a directory\n' >"$blocked"

	tt_in "$dir" "$home" --sandbox "$blocked" </dev/null
	assert_rc 1 "t_tt_sandbox_create_failed_errors rc"
	assert_contains "$ERR" "SANDBOX_CREATE_FAILED" "t_tt_sandbox_create_failed_errors reports the error code"

	rm -rf "$home" "$dir"
}
