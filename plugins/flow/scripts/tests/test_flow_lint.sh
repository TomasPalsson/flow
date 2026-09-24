#!/usr/bin/env bash
# test_flow_lint.sh — tests for flow-lint and task-brief (spec 004 K-B),
# t_flowlint_* / t_taskbrief_* prefixes. Sourced by run.sh; HERE and SCAN_DIR
# are already set.

FIX="$HERE/fixtures"
FLOW_LINT="$SCAN_DIR/flow-lint"
TASK_BRIEF="$SCAN_DIR/task-brief"

# strip the noisy "Base: … is not a commit in this repo" warning the static
# fixtures always earn, so a test can assert on the rest of the output
_no_base_warn() { printf '%s' "$1" | grep -v 'base-unknown' || true; }

# ---------------------------------------------------------------------------
# flow-lint — basics
# ---------------------------------------------------------------------------

t_flowlint_help() {
	run_cmd bash "$FLOW_LINT" --help
	assert_rc 0 "flow-lint --help exits 0"
	assert_contains "$OUT" "Usage: flow-lint" "flow-lint --help shows usage"
}

t_flowlint_unknown_option() {
	run_cmd bash "$FLOW_LINT" --nope
	assert_rc 2 "flow-lint on an unknown option exits 2"
}

t_flowlint_missing_file() {
	run_cmd bash "$FLOW_LINT" "$FIX/does-not-exist.md"
	assert_rc 1 "flow-lint on a missing file exits 1"
	assert_contains "$OUT" "file-missing" "flow-lint names the file-missing rule"
	assert_contains "$OUT" "fix:" "flow-lint on a missing file still carries a fix:"
}

t_flowlint_good_ok() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-good.md"
	assert_rc 0 "flow-lint on tasks-good.md exits 0"
	assert_not_contains "$OUT" "ERROR" "tasks-good.md has no ERROR"
}

t_flowlint_every_error_has_a_fix() {
	# K-B: "Every ERROR has a fix: string." Assert it over every failing fixture.
	local f n_err n_fix bad=""
	for f in "$FIX"/tasks-overlap-in-wave.md "$FIX"/tasks-missing-verify.md \
		"$FIX"/tasks-dropped-no-reason.md "$FIX"/tasks-cycle.md \
		"$FIX"/tasks-unknown-after.md; do
		OUT=$(bash "$FLOW_LINT" "$f" 2>&1)
		n_err=$(printf '%s\n' "$OUT" | grep -c '^ERROR ' || true)
		# only the fix: line that immediately follows an ERROR counts
		n_fix=$(printf '%s\n' "$OUT" | awk '/^ERROR /{e=1;next} /^  fix: /{if(e)n++} {e=0} END{print n+0}')
		[ "$n_err" -eq "$n_fix" ] || bad="$bad ${f##*/}($n_err/$n_fix)"
	done
	assert_eq "$bad" "" "every ERROR carries exactly one fix: line"
}

# ---------------------------------------------------------------------------
# flow-lint — the ERROR rules
# ---------------------------------------------------------------------------

t_flowlint_parallel_overlap_in_wave_is_error() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-overlap-in-wave.md"
	assert_rc 1 "two [P] tasks sharing a file in one wave exits 1"
	assert_contains "$OUT" "parallel-overlap" "overlap names the parallel-overlap rule"
	assert_contains "$OUT" "src/auth/google.test.ts" "overlap names the shared path"
	assert_contains "$OUT" "after: T001" "overlap's fix: offers the after: sequencing"
}

t_flowlint_parallel_overlap_across_waves_is_ok() {
	# v3-B's fatal flaw inverted: the same file in two different waves is fine.
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-overlap-across-waves-ok.md"
	assert_rc 0 "the same file in two different waves exits 0"
	assert_not_contains "$OUT" "parallel-overlap" "no overlap reported across waves"
}

t_flowlint_missing_verify_is_error() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-missing-verify.md"
	assert_rc 1 "a task with no verify: exits 1"
	assert_contains "$OUT" "missing-verify" "missing verify names its rule"
}

t_flowlint_dropped_without_reason_is_error() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-dropped-no-reason.md"
	assert_rc 1 "[~] with no dropped: exits 1"
	assert_contains "$OUT" "dropped-no-reason" "[~] with no reason names its rule"
}

t_flowlint_cycle_is_error() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-cycle.md"
	assert_rc 1 "an after: cycle exits 1"
	assert_contains "$OUT" "after-cycle" "a cycle names the after-cycle rule"
}

t_flowlint_unknown_after_is_error_without_a_phantom_cycle() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-unknown-after.md"
	assert_rc 1 "a dangling after: exits 1"
	assert_contains "$OUT" "unknown-after" "a dangling after: names its rule"
	assert_not_contains "$OUT" "after-cycle" "a dangling after: is not also reported as a cycle"
}

t_flowlint_bad_id_is_error() {
	local d f
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — bad id\n'
		printf 'Base: none · Route: dispatch\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] TASK1 do it — files: a.py — verify: `true`\n'
	} >"$f"
	run_cmd bash "$FLOW_LINT" "$f"
	assert_rc 1 "a non-conforming id exits 1"
	assert_contains "$OUT" "bad-id" "a non-conforming id names the bad-id rule"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — WARN and INFO
# ---------------------------------------------------------------------------

t_flowlint_phase_without_goal_is_warn_not_error() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-no-phase-meta.md"
	assert_rc 0 "a phase with no Goal:/Independent test: still exits 0"
	assert_contains "$OUT" "phase-no-goal" "the missing Goal: is reported"
	assert_contains "$OUT" "phase-no-independent-test" "the missing Independent test: is reported"
}

t_flowlint_oneshot_over_five_tasks_is_info() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-oneshot-big.md"
	assert_rc 0 "Route: oneshot with 6 tasks still exits 0"
	assert_contains "$OUT" "oneshot-too-big" "6 tasks on oneshot is reported"
	assert_contains "$OUT" "--escalate" "the oneshot INFO names --escalate as the fix"
}

# ---------------------------------------------------------------------------
# flow-lint — parsing edge cases
# ---------------------------------------------------------------------------

t_flowlint_fenced_task_lines_are_examples() {
	# A fenced "- [ ] T999 …" with no verify: must never become a finding —
	# this is why BLOCKED.md is a file and a fenced example cannot route.
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-fenced-example.md"
	assert_rc 0 "a fenced bad task line does not fail the lint"
	assert_not_contains "$OUT" "T999" "the fenced T999 is not parsed as a task"
	assert_not_contains "$OUT" "T998" "the fenced T998 is not parsed as a task"
}

t_flowlint_crlf_parses_like_lf() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-crlf.md"
	assert_rc 0 "a CRLF TASKS.md exits 0"
	assert_contains "$OUT" "1 tasks" "a CRLF TASKS.md still finds its one task"
}

t_flowlint_unicode_description_keeps_one_task() {
	# An em dash inside the description must not be read as a field separator.
	run_cmd bash "$FLOW_LINT" --json "$FIX/tasks-unicode.md"
	assert_rc 0 "a unicode TASKS.md exits 0"
	assert_contains "$OUT" '"id":"T001"' "the unicode task is parsed"
	assert_contains "$OUT" 'með striki' "the em dash inside the description is kept in the description"
}

# ---------------------------------------------------------------------------
# flow-lint — waves and json
# ---------------------------------------------------------------------------

t_flowlint_waves_output() {
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-good.md" --waves
	assert_rc 0 "--waves exits 0 on a clean file"
	assert_contains "$OUT" "wave 0: T001" "wave 0 holds the dependency-free task"
	assert_contains "$OUT" "wave 1: T002 T003" "wave 1 holds both tasks that come after T001"
}

t_flowlint_json_shape() {
	run_cmd bash "$FLOW_LINT" --json "$FIX/tasks-good.md"
	assert_rc 0 "--json exits 0 on a clean file"
	assert_contains "$OUT" '"ok":true' "json reports ok"
	assert_contains "$OUT" '"waves":[["T001","CHK011"],["T002","T003"]]' "json carries the waves"
	assert_contains "$OUT" '"route":"dispatch"' "json carries the header route"
	assert_contains "$OUT" '"approved":"2026-09-08 by user"' "json carries Approved:"
	assert_contains "$OUT" '"kind":"checkpoint"' "json distinguishes a CHK checkpoint"
	assert_contains "$OUT" '"kind":"gate"' "json distinguishes a G gate"
	if command -v python3 >/dev/null 2>&1; then
		if printf '%s' "$OUT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
			_pass "flow-lint --json emits parseable JSON"
		else
			_fail "flow-lint --json emits parseable JSON" "python3 could not parse it"
		fi
	fi
}

t_flowlint_json_errors_carry_fix() {
	run_cmd bash "$FLOW_LINT" --json "$FIX/tasks-missing-verify.md"
	assert_rc 1 "--json exits 1 when there is an ERROR"
	assert_contains "$OUT" '"ok":false' "json reports not ok"
	assert_contains "$OUT" '"rule":"missing-verify"' "json names the rule"
	assert_contains "$OUT" '"fix":"append' "json carries the fix string"
}

# ---------------------------------------------------------------------------
# flow-lint — the git joins (need a real repo)
# ---------------------------------------------------------------------------

_lying_repo() { # echoes a repo whose TASKS.md ticks T002 against T001's commit
	local d base sha_a
	d=$(tmp_repo)
	(
		cd "$d" || exit 1
		mkdir -p src .specs/001-x
		base=$(git rev-parse --short HEAD)
		printf 'a\n' >src/a.py
		git add -A && git commit -qm a
		sha_a=$(git rev-parse --short HEAD)
		printf 'b\n' >src/b.py
		git add -A && git commit -qm b
		{
			printf '# Tasks — x\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [x] T001 make a — files: src/a.py — verify: `true` — done: %s\n' "$sha_a"
			printf -- '- [x] T002 make b — files: src/b.py — verify: `true` — done: %s\n' "$sha_a"
			printf -- '- [x] T003 nothing — files: src/c.py — verify: `true` — done: %s\n' "$base"
			printf -- '- [x] T004 bogus — files: src/d.py — verify: `true` — done: deadbee\n'
			printf '\n## Gates\n- [ ] G001 clean — verify: `true`\n'
		} >.specs/001-x/TASKS.md
	) >/dev/null 2>&1
	printf '%s' "$d"
}

t_flowlint_lying_tick_touching_nothing() {
	local d
	d=$(_lying_repo)
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	RC=$?
	assert_rc 1 "a lying tick exits 1"
	assert_contains "$OUT" "done-touches-nothing" "a commit touching none of files: is caught"
	assert_contains "$OUT" "T002" "the lying task is named"
	assert_not_contains "$OUT" "T001 claims" "the honest tick is not reported"
	rm -rf "$d"
}

t_lint_done_touches_dot_and_directory() {
	local d base sha_dirtask sha_other
	d=$(tmp_repo)
	(
		cd "$d" || exit 1
		mkdir -p src/dirtask .specs/001-x
		base=$(git rev-parse --short HEAD)
		printf 'a\n' >src/dirtask/a.py
		git add -A && git commit -qm dirtask
		sha_dirtask=$(git rev-parse --short HEAD)
		printf 'b\n' >src/other.py
		git add -A && git commit -qm other
		sha_other=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — x\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [x] T002 fill dirtask — files: src/dirtask — verify: `true` — done: %s\n' "$sha_dirtask"
			printf -- '- [x] T003 nothing in emptydir — files: src/emptydir — verify: `true` — done: %s\n' "$sha_other"
			printf '\n## Gates\n- [x] G001 clean — files: . — verify: `true` — done: %s\n' "$sha_other"
		} >.specs/001-x/TASKS.md
	) >/dev/null 2>&1
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	RC=$?
	assert_rc 1 "T003's directory miss still fails the lint"
	assert_contains "$OUT" "done-touches-nothing" "T003's directory miss is still caught"
	assert_contains "$OUT" "T003 claims" "the directory-miss task is named"
	assert_not_contains "$OUT" "T002 claims" "T002's directory hit is not reported as done-touches-nothing"
	assert_not_contains "$OUT" "G001 claims" "G001's files: . pathspec is not reported as done-touches-nothing"
	rm -rf "$d"
}

t_flowlint_tick_at_or_before_base() {
	local d
	d=$(_lying_repo)
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	assert_contains "$OUT" "done-sha-before-base" "a tick at Base is caught"
	assert_contains "$OUT" "T003" "the task ticked at Base is named"
	rm -rf "$d"
}

t_flowlint_tick_at_an_unknown_sha() {
	local d
	d=$(_lying_repo)
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	assert_contains "$OUT" "done-sha-unknown" "a tick at a sha the repo does not have is caught"
	assert_contains "$OUT" "T004" "the task ticked at a bogus sha is named"
	rm -rf "$d"
}

# A ticked G### gate declares no files: BY DESIGN — a gate asserts a repo-wide
# property, not an owned path — so the [x]->sha->files: join has nothing to check
# and warning about it fires on every finished feature. A ticked T### with no
# files: is still worth a warn: there the omission is an accident.
t_flowlint_done_gate_without_files_is_not_warned() {
	local d base sha_a
	d=$(tmp_repo)
	(
		cd "$d" || exit 1
		mkdir -p src .specs/001-x
		base=$(git rev-parse --short HEAD)
		printf 'a\n' >src/a.py
		git add -A && git commit -qm a
		sha_a=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — x\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [x] T001 make a — files: src/a.py — verify: `true` — done: %s\n' "$sha_a"
			printf -- '- [x] T009 no paths — verify: `true` — done: %s\n' "$sha_a"
			printf '\n## Gates\n'
			printf -- '- [x] G001 gates green — verify: `true` — done: %s\n' "$sha_a"
		} >.specs/001-x/TASKS.md
	) >/dev/null 2>&1
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	RC=$?
	assert_rc 0 "a clean file with a ticked gate exits 0"
	assert_not_contains "$OUT" "G001 is done" "a ticked gate with no files: is not warned about"
	assert_contains "$OUT" "done-no-files" "a ticked task with no files: still warns"
	assert_contains "$OUT" "T009 is done" "and the warn names the task, not the gate"
	rm -rf "$d"
}

t_flowlint_vanished_id_is_error() {
	local d
	d=$(_lying_repo)
	(
		cd "$d" || exit 1
		git add -A && git commit -qm tasks
		grep -v 'T002' .specs/001-x/TASKS.md >t && mv t .specs/001-x/TASKS.md
	) >/dev/null 2>&1
	OUT=$(cd "$d" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	assert_contains "$OUT" "id-vanished" "an ID deleted since HEAD is caught"
	assert_contains "$OUT" "append-only" "the fix: names the append-only rule"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — stealth: .specs is a symlink into a separate store repo. Built
# by hand with git+ln (no dependency on `flow stealth`).
# ---------------------------------------------------------------------------

_stealth_pair() { # sets $D (target repo) and $STORE (store repo, .specs symlinked from D)
	D=$(tmp_repo)
	STORE=$(tmp_repo)
	(
		cd "$STORE" || exit 1
		mkdir -p .specs/001-x
		base=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — x\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 make a — files: src/a.py — verify: `true`\n'
			printf '\n## Gates\n- [ ] G001 clean — verify: `true`\n'
		} >.specs/001-x/TASKS.md
		git add -A && git commit -qm tasks
	) >/dev/null 2>&1
	ln -s "$STORE/.specs" "$D/.specs"
}

t_flowlint_stealth_store_vanished_id_is_error() {
	_stealth_pair
	grep -v 'T001' "$STORE/.specs/001-x/TASKS.md" >t && mv t "$STORE/.specs/001-x/TASKS.md"
	OUT=$(cd "$D" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	assert_contains "$OUT" "id-vanished" "an id deleted from a stealth store's working copy is caught from the target"
	assert_contains "$OUT" "T001" "the vanished id is named"
	rm -rf "$D" "$STORE"
}

t_flowlint_stealth_store_no_deletion_is_ok() {
	_stealth_pair
	OUT=$(cd "$D" && bash "$FLOW_LINT" .specs/001-x/TASKS.md 2>&1)
	assert_not_contains "$OUT" "id-vanished" "nothing deleted in the store means no id-vanished"
	rm -rf "$D" "$STORE"
}

t_flowlint_resolves_the_active_feature_from_dot_current() {
	local d
	d=$(_lying_repo)
	printf '001-x\n' >"$d/.specs/.current"
	OUT=$(cd "$d" && bash "$FLOW_LINT" --json 2>&1)
	assert_contains "$OUT" '001-x/TASKS.md' "flow-lint with no argument resolves via .specs/.current"
	OUT=$(cd "$d/src" && bash "$FLOW_LINT" --json 2>&1)
	assert_contains "$OUT" '001-x/TASKS.md' "the same resolution happens from a subdirectory"
	rm -rf "$d"
}

t_flowlint_stealth_branch_wins_over_shared_current() {
	local d store base
	d=$(tmp_repo)
	store=$(tmp_repo)
	(
		cd "$store" || exit 1
		mkdir -p .specs/001-x .specs/002-y
		base=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — x\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 make a — files: src/a.py — verify: `true`\n'
		} >.specs/001-x/TASKS.md
		{
			printf '# Tasks — y\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 make b — files: src/b.py — verify: `true`\n'
		} >.specs/002-y/TASKS.md
		git add -A && git commit -qm tasks
	) >/dev/null 2>&1
	ln -s "$store/.specs" "$d/.specs"
	printf '002-y\n' >"$d/.specs/.current"
	(cd "$d" && git checkout -qb flow/x) >/dev/null 2>&1

	OUT=$(cd "$d" && bash "$FLOW_LINT" --json 2>&1)
	assert_contains "$OUT" '001-x/TASKS.md' "stealth: branch flow/x outranks .specs/.current=002-y"
	rm -rf "$d" "$store"
}

# R4 — a branch slug must match a feature dir's NNN- stripped name EXACTLY.
# flow/login used to resolve to 001-auth-login (matched by the *-$slug glob)
# instead of 002-login (the real match); the fix is [0-9][0-9][0-9]-$slug.
t_flowlint_branch_slug_matches_exact_nnn_prefix() {
	local d base
	d=$(tmp_repo)
	(
		cd "$d" || exit 1
		mkdir -p .specs/001-auth-login .specs/002-login .specs/003-other
		base=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — auth-login\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 do it — files: a.py — verify: `true`\n'
		} >.specs/001-auth-login/TASKS.md
		{
			printf '# Tasks — login\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T009 do it — files: a.py\n' # no verify: — a distinct ERROR only 002-login has
		} >.specs/002-login/TASKS.md
		{
			printf '# Tasks — other\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 do it — files: a.py — verify: `true`\n'
		} >.specs/003-other/TASKS.md
		git add -A && git commit -qm tasks
		git checkout -qb flow/login
	) >/dev/null 2>&1
	OUT=$(cd "$d" && bash "$FLOW_LINT" --json 2>&1)
	assert_contains "$OUT" '002-login/TASKS.md' "branch flow/login resolves 002-login, not 001-auth-login (exact NNN- match)"
	assert_contains "$OUT" 'T009 has no verify' "the ERROR planted only in 002-login is present, proving it was linted"
	rm -rf "$d"
}

# R5 — a present-but-blank .current is not a decision: it falls through to
# the branch, matching router.js and specgate.sh (both guard the miss with
# `if (want)` / `[ -n ... ]`). Pinning round 1's fix.
t_flowlint_blank_current_falls_through_to_branch() {
	local d base
	d=$(tmp_repo)
	(
		cd "$d" || exit 1
		mkdir -p .specs/001-aaa
		base=$(git rev-parse --short HEAD)
		{
			printf '# Tasks — aaa\n'
			printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n\n' "$base"
			printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
			printf -- '- [ ] T001 do it — files: a.py — verify: `true`\n'
		} >.specs/001-aaa/TASKS.md
		: >.specs/.current # present but blank
		git add -A && git commit -qm tasks
		git checkout -qb flow/aaa
	) >/dev/null 2>&1
	OUT=$(cd "$d" && bash "$FLOW_LINT" --json 2>&1)
	assert_contains "$OUT" '001-aaa/TASKS.md' "a present-but-blank .current falls through to the branch, not a resolve failure"
	rm -rf "$d"
}

t_flowlint_no_resolvable_file_exits_2() {
	local d
	d=$(tmp_repo)
	OUT=$(cd "$d" && bash "$FLOW_LINT" 2>&1)
	# shellcheck disable=SC2034  # RC is the global assert_rc reads
	RC=$?
	assert_rc 2 "flow-lint with nothing to lint exits 2, not 0"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# task-brief
# ---------------------------------------------------------------------------

t_taskbrief_help() {
	run_cmd bash "$TASK_BRIEF" --help
	assert_rc 0 "task-brief --help exits 0"
	assert_contains "$OUT" "Usage: task-brief" "task-brief --help shows usage"
}

t_taskbrief_cuts_one_task_with_its_phase() {
	local d out
	d=$(tmp_dir)
	out="$d/T002-brief.md"
	run_cmd bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --out "$out"
	assert_rc 0 "task-brief on a real task exits 0"
	assert_eq "$OUT" "$out" "task-brief prints the output path"
	OUT=$(cat "$out")
	assert_contains "$OUT" "## Phase 1 — Tag persistence" "the brief carries the phase heading"
	assert_contains "$OUT" "Goal: an entry can carry tags" "the brief carries the phase Goal:"
	assert_contains "$OUT" "Independent test:" "the brief carries the phase Independent test:"
	assert_contains "$OUT" "T002 [P] POST tags persists" "the brief carries the task line"
	assert_not_contains "$OUT" "T003" "the brief carries no other task"
	rm -rf "$d"
}

t_taskbrief_records_base_before_dispatch() {
	# The BASE rule: measured now, never HEAD~1, and never the file's stale Base:.
	local d out want
	d=$(tmp_dir)
	out="$d/b.md"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T001 --out "$out" >/dev/null
	want=$(git rev-parse --short HEAD)
	OUT=$(grep -c '^Base:' "$out")
	assert_eq "$OUT" "1" "the brief carries exactly one Base: line"
	OUT=$(grep '^Base:' "$out")
	assert_eq "$OUT" "Base: $want" "the brief's Base: is the measured HEAD, not the file's stale one"
	rm -rf "$d"
}

t_taskbrief_unknown_task_exits_1() {
	local d
	d=$(tmp_dir)
	run_cmd bash "$TASK_BRIEF" "$FIX/tasks-good.md" T999 --out "$d/x.md"
	assert_rc 1 "task-brief on an unknown id exits 1"
	assert_file_missing "$d/x.md" "task-brief writes nothing for an unknown id"
	rm -rf "$d"
}

t_taskbrief_appends_a_matching_design_contract() {
	local d out design
	d=$(tmp_dir)
	out="$d/b.md"
	design="$d/design.md"
	{
		printf '# Design\n\n## Contract — T002\nThe tag id is a ULID string.\n\n'
		printf '## Contract — T003\nDuplicates return 409.\n'
	} >"$design"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --design "$design" --out "$out" >/dev/null
	OUT=$(cat "$out")
	assert_contains "$OUT" "The tag id is a ULID string." "the matching contract is appended"
	assert_not_contains "$OUT" "Duplicates return 409." "another task's contract is not appended"
	rm -rf "$d"
}

t_taskbrief_defaults_into_review_dir() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/003-x"
	cp "$FIX/tasks-good.md" "$d/003-x/TASKS.md"
	run_cmd bash "$TASK_BRIEF" "$d/003-x/TASKS.md" T001
	assert_rc 0 "task-brief with no --out exits 0"
	assert_file_exists "$d/003-x/review/T001-brief.md" "the default brief lands in review/"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — cost. The router spawns this on every call, under a timeout.
# ---------------------------------------------------------------------------

t_flowlint_a_large_tasks_file_stays_cheap() {
	# flow-lint used to fork `printf | sed` per LINE and `printf | cut` per
	# task. On a machine where spawning costs ~110ms (a shim, a scanned
	# binary, a slow FS) a 60-task TASKS.md took over a minute, the router hit
	# its spawn timeout, and EVERY state read scan-failed — while running
	# flow-lint by hand looked fine. This test is the fork budget: it fails
	# long before a reintroduced per-line fork can kill the router again.
	local d f i n t0 t1 ms
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — big\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n'
		printf 'Approved: 2026-09-08 by user\n\n'
		printf '## Behaviors\n| ID | G/W/T | Task | Proven by |\n|--|--|--|--|\n| B1 | g | T001 | t |\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		i=1
		while [ "$i" -le 60 ]; do
			n=$(printf '%03d' "$i")
			if [ "$i" -eq 1 ]; then
				printf -- '- [ ] T%s first — files: f%s.py — verify: `true`\n' "$n" "$i"
			else
				printf -- '- [ ] T%s [P] a — files: f%s.py — verify: `true` — after: T001\n' "$n" "$i"
			fi
			i=$((i + 1))
		done
		printf '\n## Gates\n- [ ] G001 clean — verify: `true`\n'
	} >"$f"

	t0=$(_flowlint_ms)
	run_cmd bash "$FLOW_LINT" "$f"
	t1=$(_flowlint_ms)
	assert_rc 0 "a 60-task TASKS.md lints clean"
	assert_contains "$OUT" "60 tasks, 2 waves" "and finds every task and both waves"
	if [ "$t0" = "0" ]; then
		printf '  skip no millisecond clock available\n'
		return 0
	fi
	ms=$((t1 - t0))
	# ~0.5s on a normal machine; the pre-fix code took 60s+ on a slow-fork one.
	if [ "$ms" -lt 15000 ]; then
		_pass "60 tasks lint in under 15s (took ${ms}ms)"
	else
		_fail "60 tasks lint in under 15s (took ${ms}ms)" "a per-line or per-task fork is back; the router will time out"
	fi
	rm -rf "$d"
}

# _flowlint_ms — epoch milliseconds, or 0 when neither python3 nor a
# nanosecond `date` is available (BSD date has no %N).
_flowlint_ms() {
	if command -v python3 >/dev/null 2>&1; then
		python3 -c 'import time; print(int(time.time() * 1000))'
	else
		printf '0'
	fi
}

# ---------------------------------------------------------------------------
# flow-lint — `done: <sha> by <who>`, the form `flow tick --by user` writes
# ---------------------------------------------------------------------------

t_flowlint_done_sha_with_by_who_is_accepted() {
	# `flow tick <CHK> --by user` appends "— done: <sha> by user", and a CHK
	# can ONLY be ticked that way (tick refuses a CHK without --by). Reading
	# the whole tail as the sha therefore made every human checkpoint in the
	# harness unlintable: `git rev-parse "<sha> by user"` cannot resolve.
	local d sha
	d=$(tmp_repo)
	printf 'a\n' >"$d/a.py"
	(cd "$d" && git add a.py && git commit -qm "task work") >/dev/null 2>&1
	sha=$(cd "$d" && git rev-parse --short HEAD)
	base=$(cd "$d" && git rev-parse --short HEAD~1)
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [x] T001 done task — files: a.py — verify: `true` — done: %s by user\n' "$sha"
	} >"$d/TASKS.md"

	run_cmd bash -c "cd '$d' && bash '$FLOW_LINT' TASKS.md"
	assert_not_contains "$OUT" "done-sha-unknown" "a 'done: <sha> by <who>' tick resolves its sha"
	assert_rc 0 "flow-lint accepts the tick form that flow tick --by user writes"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — unknown segment keys (a typo'd field must not vanish)
# ---------------------------------------------------------------------------

t_flowlint_unknown_field_is_error() {
	local d f
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — unknown field\n'
		printf 'Base: none · Route: dispatch\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do it — files: a.py — afetr: T000 — verify: `true`\n'
	} >"$f"
	run_cmd bash "$FLOW_LINT" "$f"
	assert_rc 1 "a typo'd field segment exits 1"
	assert_contains "$OUT" "unknown-field" "the typo names the unknown-field rule"
	assert_contains "$OUT" "T001" "the unknown-field error names the task id"
	assert_contains "$OUT" "afetr" "the unknown-field error names the bad key"
	assert_contains "$OUT" "fix:" "the unknown-field error carries a fix:"
	assert_contains "$OUT" "files" "the unknown-field fix: lists files as a known key"
	assert_contains "$OUT" "dropped" "the unknown-field fix: lists dropped as a known key"
	rm -rf "$d"
}

t_flowlint_unknown_field_after_em_dash_is_error() {
	local d f
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — unknown field 2\n'
		printf 'Base: none · Route: dispatch\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do it — files: a.py — verify: `true` — note: foo\n'
	} >"$f"
	run_cmd bash "$FLOW_LINT" "$f"
	assert_rc 1 "a 'note:' segment after an em dash exits 1"
	assert_contains "$OUT" "unknown-field" "'note:' after an em dash names the unknown-field rule"
	assert_contains "$OUT" "note" "the unknown-field error names the note key"
}

t_flowlint_colon_in_description_without_em_dash_is_ok() {
	# A colon word inside the description itself (never split off by an em
	# dash) is not a field — it stays part of the description as today.
	run_cmd bash "$FLOW_LINT" "$FIX/tasks-good.md"
	assert_not_contains "$OUT" "unknown-field" "tasks-good.md's descriptions do not trip unknown-field"
}

t_flowlint_colon_word_in_first_segment_stays_ok() {
	local d f
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — colon in description\n'
		printf 'Base: none · Route: dispatch\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 fix bug: urgent one — files: a.py — verify: `true`\n'
	} >"$f"
	run_cmd bash "$FLOW_LINT" "$f"
	assert_rc 0 "a colon word in the description (no preceding em dash) still lints clean"
	assert_not_contains "$OUT" "unknown-field" "the description's colon word is not read as a field"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — a hyphen instead of an em dash before verify:/files:/after:
# ---------------------------------------------------------------------------

t_flowlint_hyphen_before_verify_hints_em_dash() {
	local d f
	d=$(tmp_dir)
	f="$d/TASKS.md"
	{
		printf '# Tasks — hyphen typo\n'
		printf 'Base: none · Route: dispatch\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do it - files: a.py - verify: `true`\n'
	} >"$f"
	run_cmd bash "$FLOW_LINT" "$f"
	assert_rc 1 "a hyphen-separated task line still exits 1 (no verify: was actually parsed)"
	assert_contains "$OUT" "missing-verify" "the swallowed verify: still names missing-verify"
	assert_contains "$OUT" "em dash" "the fix: line calls out the missing em dash"
	assert_contains "$OUT" " — " "the fix: line shows the required em dash separator"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# flow-lint — git missing from PATH must not exit silently
# ---------------------------------------------------------------------------

t_flowlint_git_missing_exits_nonzero_with_message() {
	local fakebin
	fakebin=$(tmp_dir)
	ln -s "$(command -v bash)" "$fakebin/bash"

	run_cmd bash -c 'export PATH="$1"; command -v git' _ "$fakebin"
	assert_rc 1 "sanity: git is not on the restricted PATH"

	run_cmd bash -c 'export PATH="$1"; shift; exec "$@"' _ "$fakebin" bash "$FLOW_LINT" "$FIX/tasks-good.md"
	assert_rc 1 "flow-lint with git missing from PATH exits non-zero"
	assert_contains "$ERR" "git not found on PATH" "flow-lint names git as missing on stderr"
	rm -rf "$fakebin"
}
