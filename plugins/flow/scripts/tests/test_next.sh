#!/usr/bin/env bash
# test_next.sh — the flow v2 router (spec 004 K-C, research 11 §3.4): one test
# per state row, over fixture .specs/ trees in a tmp_repo.
#
# Sourced by run.sh; every t_next_* function below is discovered and run.
# Self-contained: TEST_ONLY can restrict a run to this one file, so it must
# not depend on test_cli.sh having been sourced.
set -u

NX_CLI_PATH=""
NX_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
NX_CLI_PATH="$NX_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && NX_CLI_PATH="$SCAN_DIR/../bin/flow"

# nx_cli_in <project-dir> <home-dir> <args...> — run the CLI with cwd=<dir>
# and HOME=<home>, without moving this runner's own cwd. Sets RC/OUT/ERR.
nx_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$NX_CLI_PATH" "$@"
}

# nx_tasks <file> <base-sha> <header-extra> <body-line...> — write a TASKS.md
# whose Base: is a real commit, so the git joins have something to check.
nx_tasks() {
	local f=$1 base=$2 extra=$3
	shift 3
	{
		printf '# Tasks — fixture\n'
		printf 'Spec: spec.md · Base: %s · Route: dispatch · Test: `true`\n' "$base"
		[ -n "$extra" ] && printf '%s\n' "$extra"
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf '%s\n' "$@"
	} >"$f"
}

# nx_feature <repo> <slug> — a feature dir with spec.md, made current.
nx_feature() {
	mkdir -p "$1/.specs/$2"
	printf '# Spec\n' >"$1/.specs/$2/spec.md"
	printf '%s\n' "$2" >"$1/.specs/.current"
}

# nx_commit <repo> <path> — one commit touching <path>; echoes the short sha.
nx_commit() {
	(
		cd "$1" || exit 1
		mkdir -p "$(dirname "$2")"
		printf 'x\n' >"$2"
		git add -A && git commit -qm "$2"
	) >/dev/null 2>&1
	git -C "$1" rev-parse --short HEAD
}

# ---------------------------------------------------------------------------
# row 0 — scan-failed. "Refusing to report clean" is the whole point: today
# `terraform` reports clean while spec-gate denies every edit on that branch.
# ---------------------------------------------------------------------------

t_next_row0_not_a_git_repo() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir) # no git init
	nx_cli_in "$proj" "$home" next
	assert_rc 0 "row 0 outside a repo exits 0"
	assert_contains "$OUT" "Next: flow init" "outside a repo the runnable answer is flow init"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "scan-failed"' "outside a repo the state is scan-failed"
	assert_contains "$OUT" '"scan_failed": true' "outside a repo the scan_failed gate is set"
	rm -rf "$home" "$proj"
}

t_next_row0_lint_crash_is_not_clean() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	# FLOW_SCRIPTS_DIR pins the flow-lint lookup at an empty dir, so the router
	# cannot lint — and must say so rather than report a state.
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export FLOW_SCRIPTS_DIR="$3"; shift 3; exec "$@"' \
		_ "$proj" "$home" "$home" node "$NX_CLI_PATH" next --json
	assert_contains "$OUT" '"state": "scan-failed"' "a missing flow-lint is scan-failed, not clean"
	assert_contains "$OUT" 'refusing to report clean' "row 0 says it is refusing to report clean"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# row 1a — blocked. A [ -f ] presence test no fenced example can fake.
# ---------------------------------------------------------------------------

t_next_row1a_blocked() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs"
	printf 'the migration corrupts prod rows\n' >"$proj/.specs/BLOCKED.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "blocked"' "BLOCKED.md routes to blocked"
	assert_contains "$OUT" '"blocked": true' "the blocked gate is set"
	assert_contains "$OUT" 'the migration corrupts prod rows' "the deny text quotes BLOCKED.md's first line"
	assert_contains "$OUT" '/flow:next --force' "every hard stop names its own bypass"
	rm -rf "$home" "$proj"
}

t_next_row1a_force_bypasses_blocked() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs"
	printf 'stop\n' >"$proj/.specs/BLOCKED.md"
	nx_cli_in "$proj" "$home" next --json --force
	assert_not_contains "$OUT" '"state": "blocked"' "--force routes past BLOCKED.md"
	assert_contains "$OUT" '"blocked": true' "--force still reports the blocked gate as data"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# row 1b — the completeness scan. gsd reports and halts; it never switches.
# ---------------------------------------------------------------------------

t_next_row1b_other_approved_feature_reports_and_halts() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-a
	nx_feature "$proj" 002-b
	printf '002-b\n' >"$proj/.specs/.current"
	nx_tasks "$proj/.specs/001-a/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 unfinished — files: a.py — verify: `true`'
	nx_tasks "$proj/.specs/002-b/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 also open — files: b.py — verify: `true`'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "disagreement"' "another approved feature with open tasks halts"
	assert_contains "$OUT" '001-a (1 open)' "the report names the other feature and its open count"
	assert_contains "$OUT" '"slug": "002-b"' "the pointer is authoritative — the scan does not switch it"
	assert_contains "$OUT" '--force' "the report names the bypass"
	rm -rf "$home" "$proj"
}

t_next_row1b_force_carries_on_here() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-a
	nx_feature "$proj" 002-b
	printf '002-b\n' >"$proj/.specs/.current"
	nx_tasks "$proj/.specs/001-a/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 unfinished — files: a.py — verify: `true`'
	nx_tasks "$proj/.specs/002-b/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 also open — files: b.py — verify: `true`'
	nx_cli_in "$proj" "$home" next --json --force
	assert_contains "$OUT" '"state": "building"' "--force carries on with the active feature"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# row 1c — looping. --unattended is meant to be looped; nothing bounded it.
# ---------------------------------------------------------------------------

t_next_row1c_five_calls_with_no_state_change() {
	local home proj base i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	i=0
	while [ "$i" -lt 4 ]; do
		nx_cli_in "$proj" "$home" next >/dev/null 2>&1
		i=$((i + 1))
	done
	# --peek: observing the counter must not move it (--json counts, F6)
	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"consecutive_calls": 4' "the counter survives between calls"
	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "consecutive flow next calls with no state change" "5 calls with no change stops"
	assert_contains "$OUT" "/flow:next --force" "the loop stop names its own bypass"
	rm -rf "$home" "$proj"
}

t_next_row1c_counter_resets_on_a_state_change() {
	local home proj base i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	i=0
	while [ "$i" -lt 3 ]; do
		nx_cli_in "$proj" "$home" next >/dev/null 2>&1
		i=$((i + 1))
	done
	# approving changes the state, so the counter must start over
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	nx_cli_in "$proj" "$home" next >/dev/null 2>&1
	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"consecutive_calls": 1' "a state change resets the counter"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# rows 1d / 1e — invalid, and lying
# ---------------------------------------------------------------------------

t_next_row1d_lint_error_is_invalid() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 no verify at all — files: a.py'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "invalid"' "a lint ERROR routes to invalid"
	assert_contains "$OUT" '"lint_error": true' "the lint_error gate is set"
	assert_contains "$OUT" 'has no verify:' "the first ERROR is printed verbatim"
	assert_contains "$OUT" 'fix:' "the ERROR's fix: string is printed with it"
	rm -rf "$home" "$proj"
}

t_next_row1e_lying_tick() {
	local home proj base sha
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	sha=$(nx_commit "$proj" src/a.py)
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		"- [x] T001 claims a commit that touched none of its files — files: src/zzz.py — verify: \`true\` — done: $sha"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "lying"' "a tick whose commit touched none of files: routes to lying"
	assert_contains "$OUT" '"unreachable_done": true' "the unreachable_done gate is set"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# rows 2, 3, 4
# ---------------------------------------------------------------------------

t_next_row2_no_project() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Next: /flow:spec" "an empty repo points at the only door"
	assert_contains "$OUT" "nothing in flight" "row 2 says nothing is in flight"
	rm -rf "$home" "$proj"
}

t_next_row3_ambiguous_never_guesses() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a" "$proj/.specs/002-b"
	printf '# Spec\n' >"$proj/.specs/001-a/spec.md"
	printf '# Spec\n' >"$proj/.specs/002-b/spec.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "ambiguous"' "two features and no pointer is ambiguous"
	assert_contains "$OUT" '"command": "flow use ' "the answer is a runnable flow use"
	assert_contains "$OUT" '"feature": null' "row 3 never guesses a feature"
	rm -rf "$home" "$proj"
}

t_next_row3_branch_resolves_without_a_pointer() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-entry-tagging"
	printf '# Spec\n' >"$proj/.specs/001-entry-tagging/spec.md"
	git -C "$proj" checkout -q -b flow/entry-tagging
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "drafting"' "an exact flow/<slug> branch resolves the feature"
	assert_contains "$OUT" '001-entry-tagging' "the resolved feature is named"
	rm -rf "$home" "$proj"
}

t_next_row3_a_pointer_naming_nothing_says_so() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	printf '# Spec\n' >"$proj/.specs/001-a/spec.md"
	printf '009-gone\n' >"$proj/.specs/.current"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "ambiguous"' "a pointer at a missing dir is ambiguous, not a crash"
	assert_contains "$OUT" '009-gone' "the stale pointer's own value is named"
	rm -rf "$home" "$proj"
}

t_next_row4_drafting() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-x
	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Next: /flow:next" "drafting continues with the only build verb"
	assert_contains "$OUT" "TASKS.md not yet" "row 4 says what is missing"
	assert_contains "$OUT" "Then: /clear" "a state that ends in work asks for a /clear"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# rows 5, 6, 7 — the build
# ---------------------------------------------------------------------------

t_next_row5_unapproved_is_a_hard_gate() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "unapproved"' "a TASKS.md with no Approved: is unapproved"
	assert_contains "$OUT" '"human_gate": true' "row 5 is flagged as a human gate"
	assert_contains "$OUT" 'reply' "row 5 asks the human for the word"
	assert_contains "$OUT" '"after": null' "a hard gate never asks for a /clear"
	rm -rf "$home" "$proj"
}

t_next_row6_building_names_the_wave() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 first — files: a.py — verify: `true`' \
		'- [ ] T002 [P] second — files: b.py — verify: `true` — after: T001' \
		'- [ ] T003 [P] third — files: c.py — verify: `true` — after: T001'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "building"' "an unchecked T### is building"
	assert_contains "$OUT" '"T001"' "wave 0 holds the dependency-free task"
	assert_not_contains "$OUT" '"T002"' "wave 1 does not start before wave 0 reports"
	assert_contains "$OUT" '"after": "/clear"' "building asks for a /clear"
	rm -rf "$home" "$proj"
}

t_next_row6_parallel_wave_is_flagged() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 [P] one — files: a.py — verify: `true`' \
		'- [ ] T002 [P] two — files: b.py — verify: `true`'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"parallel": true' "two disjoint [P] tasks in one wave dispatch in parallel"
	rm -rf "$home" "$proj"
}

t_next_row7_checkpoint_prints_its_own_text() {
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] CHK011 look at the filter chip at 375px in dark mode — files: ui.tsx — verify: human: user says yes'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "checkpoint"' "a leading CHK### is a checkpoint"
	assert_contains "$OUT" 'look at the filter chip at 375px in dark mode' "the CHK line's own text is printed verbatim"
	assert_contains "$OUT" '"human_gate": true' "a checkpoint is a human gate"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# rows 8, 9, 10 — the two halves of done, deliberately kept apart
# ---------------------------------------------------------------------------

t_next_row8_gating() {
	local home proj base sha
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	sha=$(nx_commit "$proj" a.py)
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		"- [x] T001 a — files: a.py — verify: \`true\` — done: $sha" \
		'' '## Gates' '- [ ] G001 clean — verify: `true`'
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "gating"' "all tasks done with a gate open is gating"
	assert_contains "$OUT" 'G001' "the open gate is named"
	assert_contains "$OUT" 'PASS-' "row 8 says what it has to write"
	rm -rf "$home" "$proj"
}

t_next_row9_unverified_is_a_hard_gate() {
	local home proj base sha
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	sha=$(nx_commit "$proj" a.py)
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		"- [x] T001 a — files: a.py — verify: \`true\` — done: $sha" \
		'' '## Gates' "- [x] G001 clean — verify: \`true\` — done: $sha"
	printf 'gates green\n' >"$proj/.specs/001-x/PASS-$sha.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "unverified"' "a PASS for HEAD with no Verified: is unverified"
	assert_contains "$OUT" '"human_gate": true' "row 9 is a human gate"
	assert_contains "$OUT" 'verify/' "row 9 points the human at the evidence dir"
	rm -rf "$home" "$proj"
}

t_next_row10_a_later_commit_invalidates_the_pass() {
	local home proj base sha
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	sha=$(nx_commit "$proj" a.py)
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user
Verified: 2026-09-08 by user" \
		"- [x] T001 a — files: a.py — verify: \`true\` — done: $sha" \
		'' '## Gates' "- [x] G001 clean — verify: \`true\` — done: $sha"
	printf 'gates green\n' >"$proj/.specs/001-x/PASS-$sha.md"
	nx_commit "$proj" b.py >/dev/null # PASS-<sha> is self-invalidating by design
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "stale-pass"' "a commit after the PASS drops back to the gates"
	assert_contains "$OUT" "PASS-$sha.md is not HEAD" "row 10 names the stale PASS"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# rows 11, 13
# ---------------------------------------------------------------------------

t_next_row11_shippable() {
	local home proj base sha
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	sha=$(nx_commit "$proj" a.py)
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user
Verified: 2026-09-08 by user" \
		"- [x] T001 a — files: a.py — verify: \`true\` — done: $sha" \
		'' '## Gates' "- [x] G001 clean — verify: \`true\` — done: $sha"
	printf 'gates green\n' >"$proj/.specs/001-x/PASS-$sha.md"
	# a gh that always fails makes "no PR" the deterministic answer, with no
	# network call and no dependence on gh being installed at all
	printf '#!/bin/sh\nexit 1\n' >"$home/gh"
	chmod +x "$home/gh"
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$2:$PATH"; shift 2; exec "$@"' \
		_ "$proj" "$home" node "$NX_CLI_PATH" next --json
	assert_contains "$OUT" '"state": "shippable"' "verified with no PR is shippable"
	assert_contains "$OUT" '"after": "/clear"' "shippable ends in work, so it asks for a /clear"
	rm -rf "$home" "$proj"
}

t_next_row13_idle() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-x" # a feature dir with nothing left in it
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "idle"' "a feature dir with no spec and no tasks is idle"
	assert_contains "$OUT" '/flow:spec' "idle points back at the only door"
	rm -rf "$home" "$proj"
}

t_next_an_empty_active_feature_is_not_idle() {
	# new-spec --current makes the dir before /flow:spec fills it. Reporting
	# "nothing unchecked anywhere" at someone three seconds into a feature is
	# true and useless; row 2 names the dir instead.
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-x"
	printf '001-x\n' >"$proj/.specs/.current"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "no-project"' "an empty but pointed-at feature is row 2"
	assert_contains "$OUT" '.specs/001-x/ is empty' "and the why names the dir"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# sibling states: an active loop, and a prep waiting on its spec
# ---------------------------------------------------------------------------

t_next_loop_active_wins_over_everything() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.claude/loop" "$proj/.specs"
	printf 'stop\n' >"$proj/.specs/BLOCKED.md"
	{
		printf -- '---\n'
		printf 'status: active\n'
		printf 'shape: fresh\n'
		printf 'goal: x\n'
		printf -- '---\n'
	} >"$proj/.claude/loop/loop.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "loop-active"' "an active loop contract is checked before the router"
	assert_contains "$OUT" 'flow loop run' "a fresh loop resumes with flow loop run"
	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: flow loop run" "K-L's exact one-line contract survives the router rewrite"
	rm -rf "$home" "$proj"
}

t_next_prep_ready() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/003-tagging"
	printf '# Prep\nStatus: ready for spec · Questions: 6 of 6\n' >"$proj/.specs/003-tagging/PREP.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "prep-ready"' "a finished PREP.md with no spec.md is prep-ready"
	assert_contains "$OUT" '"command": "/flow:spec"' "prep-ready hands off to /flow:spec"
	rm -rf "$home" "$proj"
}

t_next_prep_interviewing() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/003-tagging"
	printf '# Prep\nStatus: interviewing · Questions: 2 of 6\n' >"$proj/.specs/003-tagging/PREP.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "prep-interviewing"' "an unfinished PREP.md resumes the interview"
	assert_contains "$OUT" '2 of 6' "the interview's position is reported"
	rm -rf "$home" "$proj"
}

t_next_prep_with_a_spec_is_ignored() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 003-tagging
	printf '# Prep\nStatus: interviewing · Questions: 2 of 6\n' >"$proj/.specs/003-tagging/PREP.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "drafting"' "once spec.md exists the prep no longer routes"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# invariants that hold across every row
# ---------------------------------------------------------------------------

t_next_identical_from_root_and_subdirectory() {
	local home proj base root sub
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	mkdir -p "$proj/src/lib/api"
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	# --peek on both sides: --json now counts (F6), and the counter is
	# per-invocation state, not a cwd-dependent answer — leaving it in would
	# make the two reads differ for a reason that has nothing to do with cwd.
	nx_cli_in "$proj" "$home" next --peek --json
	root=$OUT
	nx_cli_in "$proj/src/lib/api" "$home" next --peek --json
	sub=$OUT
	assert_eq "$sub" "$root" "the router answers identically at the root and in src/lib/api"
	rm -rf "$home" "$proj"
}

t_next_progress_md_never_outranks_the_router() {
	# L5: a stale `## Now` bullet used to return before any flow state was read.
	local home proj base
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	printf '# Progress\n\n## Now\n- resume: `/wrap` — leftover from three weeks ago\n' >"$proj/PROGRESS.md"
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "building"' "the router owns the answer"
	assert_not_contains "$OUT" 'PROGRESS.md' "PROGRESS.md is not consulted at all"
	assert_not_contains "$OUT" '/wrap' "a stale resume bullet cannot outrank the router"
	rm -rf "$home" "$proj"
}

# REWRITTEN (spec 004 F6, was t_next_json_never_moves_the_counter): the
# read-only door is --peek, not --json. `flow next --json` is exactly what the
# /flow:next skill runs every turn, so if --json did not count, row 1c could
# never fire for the loop it exists to bound. The behaviour the old test
# guarded — a passive observer can ask without tripping the loop stop — is
# unchanged and asserted below; only the flag that buys it moved.
t_next_peek_never_moves_the_counter() {
	local home proj base i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	i=0
	while [ "$i" -lt 8 ]; do
		nx_cli_in "$proj" "$home" next --peek >/dev/null 2>&1
		i=$((i + 1))
	done
	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"consecutive_calls": 0' "--peek leaves the counter where it found it"
	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Next: /flow:next" "a hook or status line can ask with --peek without tripping the loop stop"
	rm -rf "$home" "$proj"
}

# The skill reads `flow next --json`; that read IS the turn, so it counts.
t_next_json_moves_the_counter_and_trips_row_1c() {
	local home proj base i
	home=$(tmp_dir)
	proj=$(tmp_repo)
	base=$(git -C "$proj" rev-parse --short HEAD)
	nx_feature "$proj" 001-x
	nx_tasks "$proj/.specs/001-x/TASKS.md" "$base" "Approved: 2026-09-08 by user" \
		'- [ ] T001 a — files: a.py — verify: `true`'
	i=0
	while [ "$i" -lt 4 ]; do
		nx_cli_in "$proj" "$home" next --json >/dev/null 2>&1
		i=$((i + 1))
	done
	nx_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "looping"' "five --json reads with no state change is row 1c"
	assert_contains "$OUT" '"consecutive_calls": 5' "and --json counted every one of them"
	assert_contains "$OUT" '/flow:next --force' "the loop stop names its own bypass"
	rm -rf "$home" "$proj"
}

# session-context.sh prints the Next: banner at session start; that banner must
# not be what drives the loop guard.
t_next_session_context_hook_asks_with_peek() {
	assert_contains "$(cat "$SCAN_DIR/../hooks/session-context.sh")" 'next --peek' \
		"the session-start banner reads the router with --peek"
}

t_next_plain_output_is_one_line_per_field() {
	local home proj n
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-x
	nx_cli_in "$proj" "$home" next
	n=$(printf '%s\n' "$OUT" | grep -c '^\(Next\|Why\|Then\): ')
	assert_eq "$n" "3" "drafting prints exactly Next:, Why: and Then:"
	n=$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')
	assert_eq "$n" "3" "and nothing else — a forged fourth line would be obeyed"
	rm -rf "$home" "$proj"
}

t_next_help_exits_0() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_cli_in "$proj" "$home" next --help
	assert_rc 0 "flow next --help exits 0"
	assert_contains "$OUT" "flow next" "the help names the command"
	assert_contains "$OUT" "PROGRESS.md is never consulted" "the help states the deleted precedence"
	rm -rf "$home" "$proj"
}

t_next_flow_off_marker_still_works() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_cli_in "$proj" "$home" off "$proj"
	assert_rc 0 "flow off exits 0"
	assert_file_exists "$proj/.claude/flow.off" "flow off writes its marker"
	nx_cli_in "$proj" "$home" on "$proj"
	assert_file_missing "$proj/.claude/flow.off" "flow on removes it"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# the prep states must be reachable for the ACTIVE feature, not only when the
# whole repo is empty (K-C puts them between rows 2 and 4)
# ---------------------------------------------------------------------------

t_next_prep_is_reachable_in_a_repo_that_has_other_features() {
	# Field report: a repo with 28 spec folders, `flow use 013-...` on one that
	# holds only a PREP.md, and the router answered "013 is empty — no spec.md
	# and no TASKS.md". It was not empty; it held a finished interview. The
	# prep branch was gated on the WHOLE repo having no spec anywhere, so it
	# could never fire once a second feature existed.
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-already-specced # another feature, with a spec.md
	mkdir -p "$proj/.specs/013-measure"
	printf '# Prep — measure it\nStatus: ready for spec · Questions: 6 of 6\n' \
		>"$proj/.specs/013-measure/PREP.md"
	printf '013-measure\n' >"$proj/.specs/.current"

	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"state": "prep-ready"' "a prep-only active feature is prep-ready, not no-project"
	assert_contains "$OUT" '"command": "/flow:spec"' "and the answer is the spec door"
	assert_not_contains "$OUT" "is empty" "the router never calls a folder with a PREP.md empty"
	assert_contains "$OUT" '"slug": "013-measure"' "the prep state names the active feature"
	rm -rf "$home" "$proj"
}

t_next_prep_interviewing_resumes_the_active_feature() {
	# The worse half of the same bug: an unfinished interview got the WRONG
	# command (/flow:spec instead of /flow:prep), so discovery restarted.
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-already-specced
	mkdir -p "$proj/.specs/013-measure"
	printf '# Prep\nStatus: interviewing · Questions: 2 of 6\n' \
		>"$proj/.specs/013-measure/PREP.md"
	printf '013-measure\n' >"$proj/.specs/.current"

	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"state": "prep-interviewing"' "an unfinished interview resumes"
	assert_contains "$OUT" '"command": "/flow:prep"' "and it resumes with /flow:prep, not /flow:spec"
	assert_contains "$OUT" '2 of 6' "the interview position is reported"
	rm -rf "$home" "$proj"
}

t_next_a_prep_with_no_status_line_still_routes_to_spec() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-already-specced
	mkdir -p "$proj/.specs/013-measure"
	printf '# Prep — measure it\n\nSome answers, no Status: line at all.\n' \
		>"$proj/.specs/013-measure/PREP.md"
	printf '013-measure\n' >"$proj/.specs/.current"

	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"state": "prep-ready"' "a PREP.md with no Status: is still a prep, not an empty dir"
	rm -rf "$home" "$proj"
}

t_next_a_genuinely_empty_active_feature_still_says_so() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	nx_feature "$proj" 001-already-specced
	mkdir -p "$proj/.specs/013-measure" # nothing in it at all
	printf '013-measure\n' >"$proj/.specs/.current"

	nx_cli_in "$proj" "$home" next --peek --json
	assert_contains "$OUT" '"state": "no-project"' "a truly empty dir is still row 2"
	assert_contains "$OUT" "no PREP.md" "and the why says which files are missing"
	rm -rf "$home" "$proj"
}
