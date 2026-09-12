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

# pl_assert_field_at_least <field> <threshold> <label> <case names...> — the
# shared shape of the three minimum checks below.
pl_assert_field_at_least() {
	local field="$1" threshold="$2" label="$3" name f val
	shift 3
	for name in "$@"; do
		f="$PL_EVALS_DIR/$name/case.yaml"
		[ -f "$f" ] || continue
		val=$(pl_field "$field" "$f")
		if [ -n "$val" ] && [ "$val" -ge "$threshold" ]; then
			_pass "$label: $name"
		else
			_fail "$label: $name" "got '$val'"
		fi
	done
}

t_build_cases_max_turns_at_least_100() {
	pl_assert_field_at_least max_turns 100 "max_turns >= 100" $PL_BUILD_CASES
}

t_first_turn_cases_max_turns_at_least_8() {
	pl_assert_field_at_least max_turns 8 "max_turns >= 8" $PL_FIRST_TURN_CASES
}

t_build_cases_timeout_at_least_1800() {
	pl_assert_field_at_least timeout_seconds 1800 "timeout_seconds >= 1800" $PL_BUILD_CASES
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

# ---------------------------------------------------------------------------
# Slice 6 review — evals/README.md's Tiers table must enumerate every tag in
# TAGS (code-design.md decision 2: adding a tier touches contract.js,
# test_evals.sh, README.md), including the `pipeline` tier this slice adds.
# ---------------------------------------------------------------------------

t_readme_documents_pipeline_tier() {
	local f table
	f="$SCAN_DIR/../evals/README.md"
	[ -f "$f" ] || { _fail "README.md exists" "missing: $f"; return; }
	table=$(sed -n '/^## Tiers/,/^## Case shape/p' "$f")
	assert_contains "$table" "| \`pipeline\` " "Tiers table has a pipeline row"
}

# ---------------------------------------------------------------------------
# Slice 6 review — scaffold isolation and honest regression-test grading.
#
# `claude plugin eval --scaffold` runs scaffold.sh with the cwd set to the
# case's scratch copy, but nothing stops a human from running one by hand from
# the checkout root. Every scaffold ends in `git add -A; git commit`, so when
# that happens the invoking repo's whole working tree - work in progress and
# untracked scratch files included - lands in one commit under a fake author.
# ---------------------------------------------------------------------------

# pl_scaffold_into <dir> <case name> — run a case's scaffold.sh with the cwd
# set to <dir>, leaving RC/OUT/ERR set as run_cmd does.
pl_scaffold_into() {
	run_cmd bash -c 'cd "$1" && exec bash "$2"' _ "$1" "$PL_EVALS_DIR/$2/scaffold.sh"
}

t_pipeline_scaffolds_refuse_an_existing_checkout() {
	local name repo before
	for name in $PL_ALL_CASES; do
		[ -f "$PL_EVALS_DIR/$name/scaffold.sh" ] || continue
		repo=$(tmp_repo)
		before=$(git -C "$repo" rev-parse HEAD)
		printf 'work in progress\n' >"$repo/uncommitted.txt"
		pl_scaffold_into "$repo" "$name"
		if [ "$RC" -ne 0 ]; then
			_pass "scaffold refuses to run inside a checkout: $name"
		else
			_fail "scaffold refuses to run inside a checkout: $name" "exited 0"
		fi
		assert_eq "$(git -C "$repo" rev-parse HEAD)" "$before" "refused scaffold leaves HEAD alone: $name"
		assert_eq "$(git -C "$repo" status --porcelain)" "?? uncommitted.txt" "refused scaffold commits nothing: $name"
		rm -rf "$repo"
	done
}

t_pipeline_scaffolds_build_a_repo_in_an_empty_dir() {
	local name d
	for name in $PL_ALL_CASES; do
		[ -f "$PL_EVALS_DIR/$name/scaffold.sh" ] || continue
		d=$(tmp_dir)
		pl_scaffold_into "$d" "$name"
		assert_rc 0 "scaffold builds a repo in an empty dir: $name"
		assert_file_exists "$d/src/posts.py" "scaffolded repo has src/posts.py: $name"
		assert_eq "$(git -C "$d" rev-list --count HEAD 2>/dev/null)" "1" "scaffolded repo has one base commit: $name"
		rm -rf "$d"
	done
}

# pipeline-fix-bug's money-test-exists and money-test-can-fail graders read
# tests/test_money.py at the end of the run. A scaffold that commits that file
# itself would score both PASS for a run that never wrote a regression test -
# exactly the behaviour FR-012 and the fix skill make non-negotiable.
t_fix_bug_scaffold_plants_no_regression_test() {
	local buggy clean
	buggy=$(tmp_dir)
	clean=$(tmp_dir)
	pl_scaffold_into "$buggy" pipeline-fix-bug
	pl_scaffold_into "$clean" pipeline-flow-feature
	assert_file_missing "$buggy/tests/test_money.py" "fix-bug scaffold plants no tests/test_money.py"
	assert_file_exists "$buggy/src/money.py" "fix-bug scaffold ships src/money.py"
	if [ -f "$buggy/src/money.py" ] && [ -f "$clean/src/money.py" ] &&
		! cmp -s "$buggy/src/money.py" "$clean/src/money.py"; then
		_pass "fix-bug scaffold's format_cents differs from the working one"
	else
		_fail "fix-bug scaffold's format_cents differs from the working one" "src/money.py is identical to pipeline-flow-feature's"
	fi
	rm -rf "$buggy" "$clean"
}
