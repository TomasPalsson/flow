#!/usr/bin/env bash
# test_spec_gate.sh — unit V7 (spec gate) tests for spec-gate.sh and the C20
# additions to stop-gate.sh. Sourced by run.sh; every t_spec_* function below
# is discovered and run.
set -u

# _spec_scripts_dir — real path of the repo's scripts/ dir, used as
# CC_SCRIPTS_DIR so spec-gate.sh/stop-gate.sh find the real plan-lint.
_spec_scripts_dir() {
	(cd "$SCAN_DIR/../scripts" && pwd -P)
}

# _spec_write_plan <path> — a minimal, C7-grammar-clean plan (no Approved
# line).
_spec_write_plan() {
	mkdir -p "$(dirname "$1")"
	cat >"$1" <<'PLANEOF'
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing works | Slice 1 | `test_thing` |

## Slice 1 — Thing

- **Files**: src/a.ts

### Slice 1 — RED

Write a failing test.

### Slice 1 — GREEN

Make it pass.

### Slice 1 — REFACTOR

Clean up.

## Gate Phases

1. Run tests.
PLANEOF
}

# _spec_write_approved_plan <path> — the plan above with a leading
# "Approved: <date>" line so it passes both the C20 regex and plan-lint.
_spec_write_approved_plan() {
	_spec_write_plan "$1"
	{
		printf 'Approved: 2026-01-01 by user\n\n'
		cat "$1"
	} >"$1.tmp"
	mv "$1.tmp" "$1"
}

# ---------------------------------------------------------------------------
# spec-gate.sh
# ---------------------------------------------------------------------------

t_spec_gate_flow_branch_no_plan_denied() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_flow_branch_no_plan_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_spec_gate_flow_branch_no_plan_denied denied"
	assert_contains "$OUT" "Spec gate:" "t_spec_gate_flow_branch_no_plan_denied message"
	rm -rf "$repo"
}

t_spec_gate_flow_branch_plan_without_approved_line_denied() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	_spec_write_plan "$repo/.claude/feature-plan.local.md"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_flow_branch_plan_without_approved_line_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_spec_gate_flow_branch_plan_without_approved_line_denied denied"
	rm -rf "$repo"
}

t_spec_gate_flow_branch_approved_line_but_lint_fails_denied() {
	local repo scripts plan
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src" "$repo/.claude"
	plan="$repo/.claude/feature-plan.local.md"
	printf 'Approved: 2026-01-01 by user\n\n# not a real plan\n' >"$plan"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_flow_branch_approved_line_but_lint_fails_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_spec_gate_flow_branch_approved_line_but_lint_fails_denied denied"
	rm -rf "$repo"
}

t_spec_gate_flow_branch_approved_lint_clean_plan_allowed() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	_spec_write_approved_plan "$repo/.claude/feature-plan.local.md"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_flow_branch_approved_lint_clean_plan_allowed rc"
	assert_eq "$OUT" "" "t_spec_gate_flow_branch_approved_lint_clean_plan_allowed allowed"
	rm -rf "$repo"
}

t_spec_gate_excluded_paths_always_allowed() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/.specs/001-x" "$repo/tests"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/.specs/001-x/spec.md\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_excluded_paths_always_allowed specs-rc"
	assert_eq "$OUT" "" "t_spec_gate_excluded_paths_always_allowed specs-allowed"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/tests/a.test.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_excluded_paths_always_allowed tests-rc"
	assert_eq "$OUT" "" "t_spec_gate_excluded_paths_always_allowed tests-allowed"
	rm -rf "$repo"
}

t_spec_gate_main_branch_default_config_allowed() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" branch -m main 2>/dev/null || true
	mkdir -p "$repo/src"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_main_branch_default_config_allowed rc"
	assert_eq "$OUT" "" "t_spec_gate_main_branch_default_config_allowed allowed"
	rm -rf "$repo"
}

t_spec_gate_require_spec_true_on_main_denied() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" branch -m main 2>/dev/null || true
	mkdir -p "$repo/.claude" "$repo/src"
	printf '{"requireSpec": true}\n' >"$repo/.claude/harness.json"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_require_spec_true_on_main_denied rc"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_spec_gate_require_spec_true_on_main_denied denied"
	rm -rf "$repo"
}

t_spec_gate_require_spec_false_on_flow_branch_allowed() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/.claude" "$repo/src"
	printf '{"requireSpec": false}\n' >"$repo/.claude/harness.json"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_require_spec_false_on_flow_branch_allowed rc"
	assert_eq "$OUT" "" "t_spec_gate_require_spec_false_on_flow_branch_allowed allowed"
	rm -rf "$repo"
}

t_spec_gate_env_disabled_allowed() {
	local repo scripts
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$repo/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$repo" CC_SCRIPTS_DIR="$scripts" CC_NO_SPEC_GATE=1
	assert_rc 0 "t_spec_gate_env_disabled_allowed rc"
	assert_eq "$OUT" "" "t_spec_gate_env_disabled_allowed allowed"
	rm -rf "$repo"
}

t_spec_gate_not_git_repo_allowed() {
	local d
	d=$(tmp_dir)
	run_hook "$SCAN_DIR/spec-gate.sh" "{\"tool_input\":{\"file_path\":\"$d/src/a.ts\"}}" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_spec_gate_not_git_repo_allowed rc"
	assert_eq "$OUT" "" "t_spec_gate_not_git_repo_allowed allowed"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# stop-gate.sh — C20 additions
# ---------------------------------------------------------------------------

t_spec_gate_stopgate_plan_changed_lint_fails_blocks() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	# Seed .claude/ as a tracked dir first: git collapses a brand-new
	# untracked directory into one "?? .claude/" porcelain line, which would
	# never match the exact plan path below.
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/.keep"
	git -C "$repo" add "$repo/.claude/.keep" >/dev/null 2>&1
	git -C "$repo" commit -q -m "seed .claude" >/dev/null 2>&1
	printf '# not a real plan\n' >"$repo/.claude/feature-plan.local.md"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-plan-lint"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_plan_changed_lint_fails_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_spec_gate_stopgate_plan_changed_lint_fails_blocks decision"
	assert_contains "$OUT" "plan-lint" "t_spec_gate_stopgate_plan_changed_lint_fails_blocks names-plan-lint"
	rm -rf "$repo" "$shared"
	rm -f "${TMPDIR:-/tmp}/claude-gatesig-spec-plan-lint"
}

t_spec_gate_stopgate_plan_changed_lint_fails_blocks_untracked_dir() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	# Unlike the sibling test above, .claude/ itself is brand-new and
	# UNTRACKED here (never git-added): git collapses it into a single
	# "?? .claude/" porcelain line rather than listing the plan file inside
	# it. The plan-changed check must still find and lint the plan file.
	mkdir -p "$repo/.claude"
	printf 'Approved: 2026-01-01\n\n# not a real plan\n' >"$repo/.claude/feature-plan.local.md"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-plan-lint-untracked"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_plan_changed_lint_fails_blocks_untracked_dir rc"
	assert_contains "$OUT" '"decision":"block"' "t_spec_gate_stopgate_plan_changed_lint_fails_blocks_untracked_dir decision"
	assert_contains "$OUT" "plan-lint" "t_spec_gate_stopgate_plan_changed_lint_fails_blocks_untracked_dir names-plan-lint"
	rm -rf "$repo" "$shared"
	rm -f "${TMPDIR:-/tmp}/claude-gatesig-spec-plan-lint-untracked"
}

t_spec_gate_stopgate_untracked_dir_with_only_excluded_content_not_blocked() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" checkout -qb flow/x
	# vendor/ is a brand-new untracked directory containing only an excluded
	# lockfile; git collapses it into one "?? vendor/" porcelain line. C20
	# explicitly excludes lockfiles from the "source file" definition — the
	# collapsed directory path must not be treated as one opaque source path
	# that masks the excluded content inside it.
	mkdir -p "$repo/vendor"
	printf '{}\n' >"$repo/vendor/composer.lock"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-vendor-lock"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_untracked_dir_with_only_excluded_content_not_blocked rc"
	assert_eq "$OUT" "" "t_spec_gate_stopgate_untracked_dir_with_only_excluded_content_not_blocked no-block"
	rm -rf "$repo" "$shared"
}

t_spec_gate_stopgate_source_changed_flow_branch_no_plan_blocks() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-source-block"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_source_changed_flow_branch_no_plan_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_spec_gate_stopgate_source_changed_flow_branch_no_plan_blocks decision"
	assert_contains "$OUT" "Spec gate:" "t_spec_gate_stopgate_source_changed_flow_branch_no_plan_blocks message"
	rm -rf "$repo" "$shared"
	rm -f "${TMPDIR:-/tmp}/claude-gatesig-spec-source-block"
}

t_spec_gate_stopgate_source_changed_main_branch_not_blocked() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" branch -m main 2>/dev/null || true
	mkdir -p "$repo/src"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-source-noblock"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_source_changed_main_branch_not_blocked rc"
	assert_eq "$OUT" "" "t_spec_gate_stopgate_source_changed_main_branch_not_blocked no-block"
	rm -rf "$repo" "$shared"
}

t_spec_gate_stopgate_env_disabled_not_blocked() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-source-envoff"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts" CC_NO_SPEC_GATE=1
	assert_rc 0 "t_spec_gate_stopgate_env_disabled_not_blocked rc"
	assert_eq "$OUT" "" "t_spec_gate_stopgate_env_disabled_not_blocked no-block"
	rm -rf "$repo" "$shared"
}

t_spec_gate_stopgate_stopgate_false_source_changed_flow_branch_still_blocks() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/.claude" "$repo/src"
	printf '{"stopGate": false}\n' >"$repo/.claude/harness.json"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-stopgate-false"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_stopgate_false_source_changed_flow_branch_still_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_spec_gate_stopgate_stopgate_false_source_changed_flow_branch_still_blocks decision"
	assert_contains "$OUT" "Spec gate:" "t_spec_gate_stopgate_stopgate_false_source_changed_flow_branch_still_blocks message"
	rm -rf "$repo" "$shared"
	rm -f "${TMPDIR:-/tmp}/claude-gatesig-spec-stopgate-false"
}

t_spec_gate_stopgate_flow_branch_approved_plan_source_changed_not_blocked() {
	local repo scripts shared
	repo=$(tmp_repo)
	scripts=$(_spec_scripts_dir)
	shared=$(tmp_dir)
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	_spec_write_approved_plan "$repo/.claude/feature-plan.local.md"
	git -C "$repo" add "$repo/.claude/feature-plan.local.md" >/dev/null 2>&1
	git -C "$repo" commit -q -m "add approved plan" >/dev/null 2>&1
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"spec-source-approved"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "t_spec_gate_stopgate_flow_branch_approved_plan_source_changed_not_blocked rc"
	assert_eq "$OUT" "" "t_spec_gate_stopgate_flow_branch_approved_plan_source_changed_not_blocked no-block"
	rm -rf "$repo" "$shared"
}

# ---------------------------------------------------------------------------
# bin/.local/bin/harness — C4 default `requireSpec` (C20: "V7 may edit only
# the C4 default object in bin/.local/bin/harness"). These exercise that
# `requireSpec` is present in C4_DEFAULTS, since `harness init` and
# `harness doctor`'s override-WARN check both derive from that one object.
# ---------------------------------------------------------------------------

# _spec_harness_cli — real path of bin/.local/bin/harness. SCAN_DIR is
# claude/.claude/hooks (set by run.sh, C6); the dotfiles root is three
# levels up (hooks -> .claude -> claude -> root).
_spec_harness_cli() {
	if [ -x "$SCAN_DIR/../bin/harness" ]; then printf '%s' "$SCAN_DIR/../bin/harness"; return 0; fi
	printf '%s/bin/.local/bin/harness' "$(cd "$SCAN_DIR/../../.." && pwd -P)"
}

t_spec_gate_cli_init_writes_require_spec_default() {
	local repo cli content plugin_cli
	repo=$(tmp_repo)
	# C21 M3: this test file's own repo has moved the CLI to
	# plugins/harness/bin/harness (sibling of hooks/, this dir's parent) —
	# try that location first, and fall back to the dotfiles-style
	# bin/.local/bin/harness path (_spec_harness_cli) so this test still
	# passes when this file is run from a dotfiles-shaped checkout.
	plugin_cli="$SCAN_DIR/../bin/harness"
	if [ -f "$plugin_cli" ]; then
		cli=$plugin_cli
	else
		cli=$(_spec_harness_cli)
	fi
	if ! command -v node >/dev/null 2>&1; then
		printf '  skip t_spec_gate_cli_init_writes_require_spec_default (node absent)\n'
		rm -rf "$repo"
		return 0
	fi
	run_cmd bash -c "cd '$repo' && node '$cli' init --stack node >/dev/null 2>&1; cat '$repo/.claude/harness.json' 2>/dev/null"
	content="$OUT"
	assert_contains "$content" '"requireSpec": "flow-branches"' "t_spec_gate_cli_init_writes_require_spec_default default-value"
	rm -rf "$repo"
}

t_spec_gate_cli_doctor_warns_on_require_spec_override() {
	local repo cli
	repo=$(tmp_repo)
	cli=$(_spec_harness_cli)
	if ! command -v node >/dev/null 2>&1; then
		printf '  skip t_spec_gate_cli_doctor_warns_on_require_spec_override (node absent)\n'
		rm -rf "$repo"
		return 0
	fi
	mkdir -p "$repo/.claude"
	printf '{"requireSpec": true}\n' >"$repo/.claude/harness.json"
	run_cmd bash -c "cd '$repo' && node '$cli' doctor --json 2>/dev/null"
	assert_contains "$OUT" 'harness-json-overrides' "t_spec_gate_cli_doctor_warns_on_require_spec_override check-present"
	assert_contains "$OUT" 'overrides C4 defaults: requireSpec' "t_spec_gate_cli_doctor_warns_on_require_spec_override warns-requirespec"
	rm -rf "$repo"
}

# Regression: an untracked directory with 2+ files must expand to one path per line
# (a glued path once let an unapproved source edit through when the second file was a lockfile).
t_spec_untracked_dir_two_files_source_edit_blocks() {
	d=$(tmp_repo)
	git -C "$d" checkout -q -b flow/x
	mkdir -p "$d/newmod"
	printf '{}\n' >"$d/newmod/composer.lock"
	printf 'export const x = 1;\n' >"$d/newmod/real.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"two-files-$$-$RANDOM\",\"stop_hook_active\":false}" \
		CLAUDE_PROJECT_DIR="$d" CC_SCRIPTS_DIR="$SCAN_DIR/../scripts" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
	assert_rc 0 "two-file untracked dir: rc 0 (block is JSON)"
	assert_contains "$OUT" "decision" "two-file untracked dir: source edit without plan is blocked"
}

t_spec_untracked_claude_dir_plan_plus_other_file_lints() {
	d=$(tmp_repo)
	git -C "$d" checkout -q -b flow/x
	mkdir -p "$d/.claude"
	printf '# not a plan\n' >"$d/.claude/feature-plan.local.md"
	printf '{}\n' >"$d/.claude/settings.local.json"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"plan-plus-$$-$RANDOM\",\"stop_hook_active\":false}" \
		CLAUDE_PROJECT_DIR="$d" CC_SCRIPTS_DIR="$SCAN_DIR/../scripts" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
	assert_rc 0 "plan + second untracked file: rc 0"
	assert_contains "$OUT" "plan-lint" "plan + second untracked file: plan-lint failure is reported"
}
