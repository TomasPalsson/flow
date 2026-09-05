#!/usr/bin/env bash
# test_next.sh — unit N1 (flow next, C23) tests for `flow next`.
# Sourced by run.sh; every t_next_* function below is discovered and run.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_cli.sh's CLI_PATH/cli_in having
# been sourced in the same run — it defines its own equivalents below.
set -u

NX_CLI_PATH=""
NX_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
NX_CLI_PATH="$NX_CLI_PATH/bin/.local/bin/flow"; [ -x "$SCAN_DIR/../bin/flow" ] && NX_CLI_PATH="$SCAN_DIR/../bin/flow"

# nx_cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $NX_CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>,
# without touching this test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
nx_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$NX_CLI_PATH" "$@"
}

# nx_branch <repo-dir> — the current branch name (tmp_repo's default branch
# name depends on the machine's init.defaultBranch, so tests read it back
# instead of assuming "main").
nx_branch() {
	git -C "$1" branch --show-current
}

# ---------------------------------------------------------------------------
# state 1 — not a git repo
# ---------------------------------------------------------------------------

t_next_not_a_git_repo() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir) # no `git init`

	nx_cli_in "$proj" "$home" next
	assert_rc 0 "t_next_not_a_git_repo rc"
	assert_eq "$OUT" "Next: cd into a project (flow init to set one up)" "t_next_not_a_git_repo exact-line"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 2 — PROGRESS.md's ## Now names a resume command
# ---------------------------------------------------------------------------

t_next_progress_now_resume_line() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	cat >"$proj/PROGRESS.md" <<'EOF'
# Progress

## Now
- resume: /flow to continue slice 2

## Next
- (none)
EOF

	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Next: /flow to continue slice 2" "t_next_progress_now_resume_line next-line"
	assert_contains "$OUT" "Why: PROGRESS.md · Now:" "t_next_progress_now_resume_line why-line"

	rm -rf "$home" "$proj"
}

t_next_progress_now_backticked_command() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	cat >"$proj/PROGRESS.md" <<'EOF'
# Progress

## Now
- finish the docs pass, then run `flow check`
EOF

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "$(printf 'Next: flow check\nWhy: PROGRESS.md \xc2\xb7 Now: finish the docs pass, then run `flow check`')" \
		"t_next_progress_now_backticked_command exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3a — flow.json present, worktree disagrees with the checkout
# ---------------------------------------------------------------------------

t_next_flow_worktree_mismatch() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"flow/x","worktree":"/elsewhere/code-worktrees/flow/x"}\n' \
		>"$proj/.claude/flow.json"

	nx_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Next: agents /elsewhere/code-worktrees/flow/x" "t_next_flow_worktree_mismatch next-line"
	assert_contains "$OUT" "Why: this flow lives in /elsewhere/code-worktrees/flow/x (branch flow/x)" "t_next_flow_worktree_mismatch why-line"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3b — flow.json present, no plan written yet
# ---------------------------------------------------------------------------

t_next_flow_no_plan() {
	local home proj branch
	home=$(tmp_dir)
	proj=$(tmp_repo)
	branch=$(nx_branch "$proj")
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"%s","worktree":null}\n' "$branch" \
		>"$proj/.claude/flow.json"

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /flow
Why: spec exists (.specs/001-x), plan not written" "t_next_flow_no_plan exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3c — plan exists but has no Approved: line
# ---------------------------------------------------------------------------

t_next_flow_plan_unapproved() {
	local home proj branch
	home=$(tmp_dir)
	proj=$(tmp_repo)
	branch=$(nx_branch "$proj")
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"%s","worktree":null}\n' "$branch" \
		>"$proj/.claude/flow.json"
	printf '## Behavior Inventory\n\n## Slice 1 — x\n\n## Gate Phases\n' >"$proj/.claude/feature-plan.local.md"

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: review and approve the plan (then /flow continues)" "t_next_flow_plan_unapproved exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3d — approved plan, unfinished slices tracked in
# .claude/workflow-state.local.md's `## Progress` checkboxes. This is the
# REAL location the flow skill writes and reads (flow/planning.md: "Mirror
# each slice's sub-phases into `## Progress` in
# `.claude/workflow-state.local.md` ... that is what step 0's resume check
# reads"); the plan file's own `## Progress` section, when the flow skill
# writes one at all, holds `Ruling:` lines from the fix ladder, never
# checkboxes — so the fixture below intentionally does NOT put a `##
# Progress` checkbox section in the plan file itself.
# ---------------------------------------------------------------------------

t_next_flow_slices_unfinished() {
	local home proj branch
	home=$(tmp_dir)
	proj=$(tmp_repo)
	branch=$(nx_branch "$proj")
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"%s","worktree":null}\n' "$branch" \
		>"$proj/.claude/flow.json"
	cat >"$proj/.claude/feature-plan.local.md" <<'EOF'
Approved: 2026-09-04 by user

## Behavior Inventory

## Slice 1 — x

## Slice 2 — y

## Gate Phases
EOF
	cat >"$proj/.claude/workflow-state.local.md" <<'EOF'
type: flow

## Progress
- [x] Slice 1
- [ ] Slice 2
EOF

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /flow
Why: 1 of 2 slices done" "t_next_flow_slices_unfinished exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3d, alternate detection method — no workflow-state.local.md and no
# checkbox `## Progress` in the plan at all: falls back to slice headings
# without a "Done" marker (C23: "checkboxes under ## Progress, or slice
# headings without a done marker").
# ---------------------------------------------------------------------------

t_next_flow_slices_unfinished_heading_marker() {
	local home proj branch
	home=$(tmp_dir)
	proj=$(tmp_repo)
	branch=$(nx_branch "$proj")
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"%s","worktree":null}\n' "$branch" \
		>"$proj/.claude/flow.json"
	cat >"$proj/.claude/feature-plan.local.md" <<'EOF'
Approved: 2026-09-04 by user

## Behavior Inventory

## Slice 1 — x

Done

## Slice 2 — y

## Gate Phases
EOF

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /flow
Why: 1 of 2 slices done" "t_next_flow_slices_unfinished_heading_marker exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3e — approved plan, all slices done (per workflow-state.local.md),
# dirty tree
# ---------------------------------------------------------------------------

t_next_flow_done_dirty() {
	local home proj branch
	home=$(tmp_dir)
	proj=$(tmp_repo)
	branch=$(nx_branch "$proj")
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"%s","worktree":null}\n' "$branch" \
		>"$proj/.claude/flow.json"
	cat >"$proj/.claude/feature-plan.local.md" <<'EOF'
Approved: 2026-09-04 by user

## Behavior Inventory

## Slice 1 — x

## Gate Phases
EOF
	cat >"$proj/.claude/workflow-state.local.md" <<'EOF'
type: flow

## Progress
- [x] Slice 1
EOF
	printf 'dirty\n' >"$proj/dirty.txt"

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /wrap then /ship" "t_next_flow_done_dirty exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3f — approved plan, all slices done (per workflow-state.local.md),
# clean tree, non-default branch
# ---------------------------------------------------------------------------

t_next_flow_done_clean_non_default_branch() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	(
		cd "$proj" || exit 1
		git checkout -q -b feature/side
	) >/dev/null 2>&1
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"feature/side","worktree":null}\n' \
		>"$proj/.claude/flow.json"
	cat >"$proj/.claude/feature-plan.local.md" <<'EOF'
Approved: 2026-09-04 by user

## Behavior Inventory

## Slice 1 — x

## Gate Phases
EOF
	cat >"$proj/.claude/workflow-state.local.md" <<'EOF'
type: flow

## Progress
- [x] Slice 1
EOF
	(
		cd "$proj" || exit 1
		git add .claude
		git commit -q -m "flow state"
	) >/dev/null 2>&1

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /ship" "t_next_flow_done_clean_non_default_branch exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 3a, branch-mismatch sub-path — worktree is null (matches, since
# there is none) but flow.json's branch differs from the current checkout.
# Previously only the worktree-mismatch sub-path had a test.
# ---------------------------------------------------------------------------

t_next_flow_branch_mismatch_no_worktree() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"flow/elsewhere","worktree":null}\n' \
		>"$proj/.claude/flow.json"

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: agents flow/elsewhere
Why: this flow lives in flow/elsewhere (branch flow/elsewhere)" "t_next_flow_branch_mismatch_no_worktree exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 4 — no flow.json, branch matches flow/*, no plan file
# ---------------------------------------------------------------------------

t_next_flow_branch_no_flow_json_no_plan() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	(
		cd "$proj" || exit 1
		git checkout -q -b flow/thing
	) >/dev/null 2>&1

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /flow <describe the feature>
Why: spec gate is active on this branch" "t_next_flow_branch_no_flow_json_no_plan exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 5 — no flow, dirty tree
# ---------------------------------------------------------------------------

t_next_no_flow_dirty_tree() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	printf 'dirty\n' >"$proj/dirty.txt"

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /wrap before leaving, or continue" "t_next_no_flow_dirty_tree exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# state 5 — no flow, clean tree, default branch
# ---------------------------------------------------------------------------

t_next_no_flow_clean_default_branch() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)

	nx_cli_in "$proj" "$home" next
	assert_eq "$OUT" "Next: /flow <feature> for a feature, or just ask for a one-sentence change" \
		"t_next_no_flow_clean_default_branch exact"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# --json shape
# ---------------------------------------------------------------------------

t_next_json_shape() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)

	nx_cli_in "$proj" "$home" next --json
	assert_rc 0 "t_next_json_shape rc"
	assert_contains "$OUT" '"next":' "t_next_json_shape has-next"
	assert_contains "$OUT" '"why":' "t_next_json_shape has-why"
	assert_contains "$OUT" '"state":' "t_next_json_shape has-state"
	assert_contains "$OUT" '"gitRepo": true' "t_next_json_shape has-gitrepo"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

t_next_help_exits_0() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)

	nx_cli_in "$proj" "$home" next --help
	assert_rc 0 "t_next_help_exits_0 rc"
	assert_contains "$OUT" "Usage:" "t_next_help_exits_0 usage-line"

	rm -rf "$home" "$proj"
}

# flow off / flow on write and remove the .claude/flow.off marker.
t_next_flow_off_on_marker() {
	local repo
	repo=$(tmp_repo)
	run_cmd bash -c 'cd "$1" && node "$2" off' _ "$repo" "$SCAN_DIR/../bin/flow"
	assert_rc 0 "flow off exits 0"
	assert_file_exists "$repo/.claude/flow.off" "flow off writes the marker"
	assert_contains "$OUT" "hooks OFF" "flow off says so"
	assert_contains "$(cat "$repo/.git/info/exclude")" ".claude/flow.off" "flow off excludes the marker locally, never in a tracked file"
	run_cmd bash -c 'cd "$1" && node "$2" off' _ "$repo" "$SCAN_DIR/../bin/flow"
	assert_contains "$OUT" "already off" "flow off is idempotent"
	assert_eq "$(grep -c 'flow.off' "$repo/.git/info/exclude")" "1" "exclude line not duplicated"
	run_cmd bash -c 'cd "$1" && node "$2" on' _ "$repo" "$SCAN_DIR/../bin/flow"
	assert_rc 0 "flow on exits 0"
	assert_file_missing "$repo/.claude/flow.off" "flow on removes the marker"
	run_cmd node "$SCAN_DIR/../bin/flow" off "$repo/sub-does-not-exist"
	assert_rc 2 "flow off on a missing dir exits 2"
	run_cmd node "$SCAN_DIR/../bin/flow" --help
	assert_contains "$OUT" "off [<dir>]" "top help lists off"
	rm -rf "$repo"
}
