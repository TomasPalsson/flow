#!/usr/bin/env bash
# test_evals_pipeline.sh — tests for the pipeline-tier eval cases under
# plugins/flow/evals/ (Slice 6, .claude/slices/6-brief.md; spec
# .specs/007-plugin-eval-suite-and-optimisation-loop/spec.md FR-012, AC-030,
# FR-013, Journey 2) (B20, B21, B22).
#
# Checks the four pipeline-* case dirs exist, each case.yaml's tags/runs/
# max_turns/timeout_seconds meet the pipeline tier's minimums, every
# scaffold.sh is executable and builds a real git repo (`git init`), and the
# pipeline-flow-feature case carries the specific graders the reuse-not-
# reimplement contract for src/posts.py needs.
#
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent) are already set.
set -u

PL_EVALS_DIR="$SCAN_DIR/../evals"
PL_BUILD_CASES="pipeline-flow-feature pipeline-fix-bug"
PL_FIRST_TURN_CASES="pipeline-spec-only pipeline-prep-first-turn"
PL_ALL_CASES="$PL_BUILD_CASES $PL_FIRST_TURN_CASES"

# pl_field <field> <file> — the numeric value of the first "<field>: N" line
# at any indent level.
pl_field() {
	grep -m1 -E "^[[:space:]]*$1:[[:space:]]*[0-9]+" "$2" | sed -E 's/^[^:]*:[[:space:]]*//'
}

# ---------------------------------------------------------------------------
# B20 — the four case dirs exist, tagged pipeline (and needs-bash for the
# two build cases), runs: 1.
# ---------------------------------------------------------------------------

t_pipeline_case_dirs_present() {
	local name
	for name in $PL_ALL_CASES; do
		assert_file_exists "$PL_EVALS_DIR/$name/case.yaml" "case dir present: $name/case.yaml"
	done
}

t_pipeline_cases_tagged_pipeline() {
	local name f tags
	for name in $PL_ALL_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		tags=$(grep -m1 '^tags:' "$f")
		assert_contains "$tags" "pipeline" "tagged pipeline: $name"
	done
}

t_build_cases_tagged_needs_bash() {
	local name f tags
	for name in $PL_BUILD_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		tags=$(grep -m1 '^tags:' "$f")
		assert_contains "$tags" "needs-bash" "tagged needs-bash: $name"
	done
}

t_pipeline_cases_run_once() {
	local name f val
	for name in $PL_ALL_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		val=$(pl_field runs "$f")
		assert_eq "$val" "1" "runs: 1: $name"
	done
}

# ---------------------------------------------------------------------------
# B21 — max_turns and timeout_seconds minimums, executable scaffold.sh
# with a real `git init`.
# ---------------------------------------------------------------------------

t_build_cases_max_turns_at_least_100() {
	local name f val
	for name in $PL_BUILD_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		val=$(pl_field max_turns "$f")
		if [ -n "$val" ] && [ "$val" -ge 100 ]; then
			_pass "max_turns >= 100: $name"
		else
			_fail "max_turns >= 100: $name" "got '$val'"
		fi
	done
}

t_first_turn_cases_max_turns_at_least_8() {
	local name f val
	for name in $PL_FIRST_TURN_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		val=$(pl_field max_turns "$f")
		if [ -n "$val" ] && [ "$val" -ge 8 ]; then
			_pass "max_turns >= 8: $name"
		else
			_fail "max_turns >= 8: $name" "got '$val'"
		fi
	done
}

t_build_cases_timeout_at_least_1800() {
	local name f val
	for name in $PL_BUILD_CASES; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		val=$(pl_field timeout_seconds "$f")
		if [ -n "$val" ] && [ "$val" -ge 1800 ]; then
			_pass "timeout_seconds >= 1800: $name"
		else
			_fail "timeout_seconds >= 1800: $name" "got '$val'"
		fi
	done
}

t_pipeline_scaffolds_executable_git_init() {
	local name s
	for name in $PL_ALL_CASES; do
		s="$PL_EVALS_DIR/$name/scaffold.sh"
		if [ -x "$s" ] && grep -q 'git init' "$s"; then
			_pass "executable scaffold.sh with git init: $name"
		else
			_fail "executable scaffold.sh with git init: $name" "missing, not executable, or no git init: $s"
		fi
	done
}

# ---------------------------------------------------------------------------
# B22 — pipeline-flow-feature's graders: file_exists for the spec doc and
# verification evidence, reuse-not-reimplement regexes on src/posts.py, and a
# tool_order proving exploration happens before the edit.
# ---------------------------------------------------------------------------

t_flow_feature_file_exists_graders() {
	local f
	f="$PL_EVALS_DIR/pipeline-flow-feature/case.yaml"
	[ -f "$f" ] || return
	assert_contains "$(cat "$f")" ".specs/*/spec.md" "file_exists targets .specs/*/spec.md"
	# Not .claude/feature-plan.local.md: 06-pr.md's Promote step cleans up every
	# .claude/*.local.md on a fully-shipped run, which would flip this grader to
	# FAIL for the best-behaved runs. .claude/verification/ is the one directory
	# 06-pr.md and SKILL.md's invariants both name as never deleted.
	assert_contains "$(cat "$f")" ".claude/verification/*.md" "file_exists targets .claude/verification/*.md"
}

t_flow_feature_reuse_regex_graders() {
	local f content
	f="$PL_EVALS_DIR/pipeline-flow-feature/case.yaml"
	[ -f "$f" ] || return
	content=$(cat "$f")
	assert_contains "$content" "slugify" "regex contains targets slugify"
	assert_contains "$content" "format_cents" "regex contains targets format_cents"
	assert_contains "$content" "src/posts.py" "regex graders target src/posts.py"
	assert_contains "$content" 're\\.sub|import re' "regex not_contains targets re.sub|import re"
	assert_contains "$content" "not_contains" "a not_contains match is declared"
}

t_flow_feature_tool_order_grader() {
	local f content
	f="$PL_EVALS_DIR/pipeline-flow-feature/case.yaml"
	[ -f "$f" ] || return
	content=$(cat "$f")
	assert_contains "$content" "tool_order" "tool_order grader declared"
	assert_contains "$content" "Grep|Bash" "tool_order before is Grep|Bash"
	assert_contains "$content" "Edit|Write" "tool_order after is Edit|Write"
}
