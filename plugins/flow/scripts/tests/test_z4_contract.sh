#!/usr/bin/env bash
# test_z4_contract.sh — famous-borrows slice Z4: F03 (exit code after a pipe),
# F04 (T000 baseline for Test:), F93 (spec criteria frozen after approval),
# F94 (open question that blocks the breakdown), F112 (Ask first in the brief).
# Sourced by run.sh; SCAN_DIR (scripts/) is already set. t_z4_* prefix.
#
# Plans below carry an explicit `Approved:` date so the date gate (flow-lint
# NEW_RULES_FROM, lint.js NEW_RULES_FROM) is exercised on both sides of it:
# 2026-10-20 is "new", 2026-10-01 is "old".

Z4_LINT="$SCAN_DIR/flow-lint"
Z4_BRIEF="$SCAN_DIR/task-brief"
Z4_FLOW="$SCAN_DIR/../bin/flow"
Z4_NEW="Approved: 2026-10-20 by user"
Z4_OLD="Approved: 2026-10-01 by user"

# _z4_plan <dir> <spec-field> <extra-header> <approved-line> <behaviors-row> <task-lines>
# writes <dir>/TASKS.md; Base is the repo's current HEAD.
_z4_plan() {
	local d=$1 base
	base=$(git -C "$d" rev-parse --short HEAD 2>/dev/null || printf abc1234)
	{
		printf '# Tasks — z4\nSpec: %s · Design: none · Base: %s · Route: dispatch · Test: `true`%s\n' "$2" "$base" "$3"
		[ -n "$4" ] && printf '%s\n' "$4"
		printf '\n## Behaviors\n| ID | Given / When / Then | Task | Proven by |\n|----|----|----|----|\n%s\n\n' "$5"
		printf '## Phase 1 — One\nGoal: g.\nIndependent test: `true`\n%s\n\n## Gates\n- [ ] G001 clean — files: . — verify: `true`\n' "$6"
	} >"$d/TASKS.md"
}

_Z4_T001='- [ ] T001 One — files: a.txt — verify: `true`'
_Z4_T000='- [ ] T000 Baseline tests at Base — files: verify/baseline-tests.txt — verify: `test -s verify/baseline-tests.txt`
- [ ] T001 One — files: a.txt — verify: `true` — after: T000'
_Z4_ROW='| B1 | g w t | T001 | t |'

_z4_lint() { run_cmd bash -c 'cd "$1" || exit 1; bash "$2" TASKS.md' _ "$1" "$Z4_LINT"; }

# _z4_commit <dir> <date> <msg> — commit everything at <date>
_z4_commit() {
	(
		cd "$1" || exit 1
		git add -A
		GIT_COMMITTER_DATE="$2T12:00:00" GIT_AUTHOR_DATE="$2T12:00:00" git commit -qm "$3"
	) >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# F04 — a Test: plan opens with T000 (baseline-missing); old plans are exempt
# ---------------------------------------------------------------------------

t_z4_test_plan_without_t000_errors() {
	local d
	d=$(tmp_repo)
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T001"
	_z4_lint "$d"
	assert_rc 1 "a new plan with Test: and no T000 is an ERROR"
	assert_contains "$OUT" "[baseline-missing]" "rule name"
	assert_contains "$OUT" "verify/baseline-tests.txt" "the fix names the baseline file"
	rm -rf "$d"
}

t_z4_test_plan_unapproved_is_exempt() {
	local d
	d=$(tmp_repo)
	(cd "$d" && GIT_COMMITTER_DATE="2026-10-20T12:00:00" git commit -q --amend --no-edit --date "2026-10-20T12:00:00") >/dev/null 2>&1
	_z4_plan "$d" "spec.md" "" "" "$_Z4_ROW" "$_Z4_T001"
	_z4_lint "$d"
	assert_not_contains "$OUT" "baseline-missing" "an unapproved plan is not dated by its Base commit"
	rm -rf "$d"
}

t_z4_old_test_plan_without_t000_is_clean() {
	local d
	d=$(tmp_repo)
	_z4_plan "$d" "spec.md" "" "$Z4_OLD" "$_Z4_ROW" "$_Z4_T001"
	_z4_lint "$d"
	assert_rc 0 "a plan approved before the cutoff stays clean"
	assert_not_contains "$OUT" "baseline-missing" "no baseline-missing"
	rm -rf "$d"
}

t_z4_test_plan_with_t000_is_clean() {
	local d
	d=$(tmp_repo)
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T000"
	_z4_lint "$d"
	assert_rc 0 "a plan with T000 is clean"
	assert_not_contains "$OUT" "baseline-missing" "no baseline-missing"
	rm -rf "$d"
}

t_z4_test_plus_parity_plan_with_one_t000_is_clean() {
	local d
	d=$(tmp_repo)
	printf '# Spec\n\n**Behaviour-preserving**: yes\n' >"$d/spec.md"
	_z4_plan "$d" "spec.md" " · Parity: ./run.sh" "$Z4_NEW" "$_Z4_ROW" \
		'- [ ] T000 Baselines — files: verify/baseline.txt, verify/baseline-tests.txt — verify: `test -s verify/baseline.txt && test -s verify/parity-redcheck.txt && test -s verify/baseline-tests.txt`
- [ ] T001 One — files: a.txt — verify: `true` — after: T000'
	_z4_lint "$d"
	assert_rc 0 "Test: plus Parity: with one T000 is clean"
	assert_not_contains "$OUT" "baseline-missing" "no baseline-missing"
	assert_not_contains "$OUT" "parity-marker" "no parity-marker"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# F94 — an unresolved "blocks: tasks" question stops the breakdown
# ---------------------------------------------------------------------------

_z4_spec_q() { # <dir> <question-line>
	printf '# Spec\n\n## 8. Open questions\n\n1. %s\n' "$2" >"$1/spec.md"
}

t_z4_open_question_blocking_tasks_errors() {
	local d
	d=$(tmp_repo)
	_z4_spec_q "$d" '[NEEDS CLARIFICATION: which store holds sessions? — owner: user — blocks: tasks]'
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T000"
	_z4_lint "$d"
	assert_rc 1 "a blocks: tasks question is an ERROR"
	assert_contains "$OUT" "[open-question-blocks-tasks]" "rule name"
	assert_contains "$OUT" "/flow:spec --amend" "the fix points at --amend"
	rm -rf "$d"
}

t_z4_open_question_without_blocks_is_clean() {
	local d
	d=$(tmp_repo)
	_z4_spec_q "$d" '[NEEDS CLARIFICATION: which store holds sessions? — owner: user]'
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T000"
	_z4_lint "$d"
	assert_rc 0 "a question without the marker passes"
	assert_not_contains "$OUT" "open-question-blocks-tasks" "no rule fires"
	rm -rf "$d"
}

t_z4_resolved_open_question_is_clean() {
	local d
	d=$(tmp_repo)
	_z4_spec_q "$d" 'Sessions live in Redis (answered 2026-10-21).'
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T000"
	_z4_lint "$d"
	assert_rc 0 "a removed marker passes"
	assert_not_contains "$OUT" "open-question-blocks-tasks" "no rule fires"
	rm -rf "$d"
}

t_z4_old_blocking_question_is_spared() {
	local d
	d=$(tmp_repo)
	_z4_spec_q "$d" '[NEEDS CLARIFICATION: q — owner: user — blocks: tasks]'
	_z4_plan "$d" "spec.md" "" "$Z4_OLD" "$_Z4_ROW" "$_Z4_T001"
	_z4_lint "$d"
	assert_not_contains "$OUT" "open-question-blocks-tasks" "a pre-cutoff plan is not flagged"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# F93 — FR rows are frozen at the baseline; Amendment or Ruling is the way out
# ---------------------------------------------------------------------------

_Z4_FR_ROWS='| FR-01 | MUST | does a | t1 |
| FR-02 | MUST | does b | t2 |'
_Z4_FR_BEH='| FR-01 | g w t | T001 | t |
| FR-02 | g w t | T001 | t |'

# _z4_frozen <dir> — repo with spec.md committed after Base (2026-10-20) and a
# plan beside it; the working copy of spec.md is still the baseline.
_z4_frozen() {
	local d=$1
	printf '# Spec\n\n## 4.1\n\n| ID | P | Requirement | Acceptance |\n|----|----|----|----|\n%s\n' "$_Z4_FR_ROWS" >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_FR_BEH" "$_Z4_T000"
	_z4_commit "$d" 2026-10-20 "spec and plan"
}

t_z4_reworded_fr_row_errors_and_routes_lying() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	sed 's/does b/does b and also c/' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	_z4_lint "$d"
	assert_rc 1 "a reworded FR row is an ERROR"
	assert_contains "$OUT" "[spec-criterion-changed]" "rule name"
	assert_contains "$OUT" "FR-02" "names the row"
	assert_contains "$OUT" "fix:" "carries a fix"
	rm -rf "$d"
}

# _z4_routes_to <fr-edit: reword|delete|none> — builds a feature under .specs/,
# edits spec.md as asked, runs `flow next --json`; leaves the output in OUT.
_z4_route() {
	local d home
	d=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$d/.specs/001-x"
	printf '001-x\n' >"$d/.specs/.current"
	printf '# Spec\n\n| ID | P | Requirement | Acceptance |\n|----|----|----|----|\n%s\n' "$_Z4_FR_ROWS" >"$d/.specs/001-x/spec.md"
	_z4_plan "$d/.specs/001-x" "spec.md" "" "$Z4_NEW" "$_Z4_FR_BEH" "$_Z4_T000"
	_z4_commit "$d" 2026-10-20 "spec and plan"
	case "$1" in
	reword) sed 's/does b/does b and c/' "$d/.specs/001-x/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/.specs/001-x/spec.md" ;;
	delete) grep -v 'FR-02' "$d/.specs/001-x/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/.specs/001-x/spec.md" ;;
	amend)
		sed 's/does b/does b and c/' "$d/.specs/001-x/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/.specs/001-x/spec.md"
		printf '\n## Amendment 2026-10-22\n\nFR-02 widened.\n' >>"$d/.specs/001-x/spec.md"
		;;
	esac
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; node "$3" next --json' _ "$d" "$home" "$Z4_FLOW"
	rm -rf "$d" "$home"
}

t_z4_reworded_fr_row_routes_lying() {
	_z4_route reword
	assert_contains "$OUT" '"state": "lying"' "a reworded FR row routes to lying"
}

t_z4_deleted_fr_row_routes_lying() {
	_z4_route delete
	assert_contains "$OUT" '"state": "lying"' "a deleted FR row routes to lying"
}

t_z4_amended_fr_row_does_not_route_lying() {
	_z4_route amend
	assert_not_contains "$OUT" '"state": "lying"' "an Amendment keeps the route out of lying"
}

t_z4_untouched_spec_does_not_route_lying() {
	_z4_route none
	assert_not_contains "$OUT" '"state": "lying"' "an untouched spec is not lying"
}

t_z4_deleted_fr_row_errors() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	grep -v 'FR-02' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	_z4_lint "$d"
	assert_contains "$OUT" "[spec-criterion-changed]" "a deleted FR row is an ERROR"
	assert_contains "$OUT" "FR-02" "names the row"
	rm -rf "$d"
}

t_z4_amendment_exempts_changed_fr_row() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	sed 's/does b/does b and also c/' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	printf '\n## Amendment 2026-10-22\n\nFR-02 widened to c.\n' >>"$d/spec.md"
	_z4_lint "$d"
	assert_not_contains "$OUT" "spec-criterion-changed" "an Amendment dated after the baseline commit exempts the change"
	rm -rf "$d"
}

t_z4_preexisting_amendment_does_not_exempt() {
	local d
	d=$(tmp_repo)
	printf '# Spec\n\n## 4.1\n\n| ID | P | Requirement | Acceptance |\n|----|----|----|----|\n%s\n\n## Amendment 2026-10-20\n\nearlier.\n' "$_Z4_FR_ROWS" >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_FR_BEH" "$_Z4_T000"
	_z4_commit "$d" 2026-10-20 "spec and plan"
	sed 's/does b/does nothing at all/' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	_z4_lint "$d"
	assert_contains "$OUT" "[spec-criterion-changed]" "an Amendment already at the baseline does not exempt a later change"
	rm -rf "$d"
}

t_z4_old_amendment_does_not_exempt() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	sed 's/does b/does b and also c/' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	printf '\n## Amendment 2026-10-02\n\nunrelated.\n' >>"$d/spec.md"
	_z4_lint "$d"
	assert_contains "$OUT" "[spec-criterion-changed]" "an Amendment dated before the baseline commit does not exempt"
	rm -rf "$d"
}

t_z4_ruling_naming_the_fr_exempts_it() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	grep -v 'FR-02' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	printf -- '- Ruling: FR-02 dropped, the vendor removed the endpoint\n' >"$d/NOTES.md"
	_z4_lint "$d"
	assert_not_contains "$OUT" "spec-criterion-changed" "a Ruling naming FR-02 exempts it"
	rm -rf "$d"
}

t_z4_unchanged_fr_rows_are_clean() {
	local d
	d=$(tmp_repo)
	_z4_frozen "$d"
	printf '\nA new note.\n' >>"$d/spec.md"
	_z4_lint "$d"
	assert_rc 0 "an edit outside the FR rows is clean"
	rm -rf "$d"
}

t_z4_no_baseline_skips_silently() {
	local d
	d=$(tmp_repo)
	printf '# Spec\n\n| ID | P | Requirement | Acceptance |\n|----|----|----|----|\n%s\n' "$_Z4_FR_ROWS" >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_FR_BEH" "$_Z4_T000"
	_z4_lint "$d"
	assert_rc 0 "an uncommitted spec.md has no baseline: skipped"
	assert_not_contains "$OUT" "spec-criterion-changed" "no rule fires"
	rm -rf "$d"
}

t_z4_old_plan_spec_edit_is_spared() {
	local d
	d=$(tmp_repo)
	printf '# Spec\n\n| ID | P | Requirement | Acceptance |\n|----|----|----|----|\n%s\n' "$_Z4_FR_ROWS" >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_OLD" "$_Z4_FR_BEH" "$_Z4_T001"
	_z4_commit "$d" 2026-10-01 "old spec"
	sed 's/does b/does b and also c/' "$d/spec.md" >"$d/s.tmp" && mv "$d/s.tmp" "$d/spec.md"
	_z4_lint "$d"
	assert_not_contains "$OUT" "spec-criterion-changed" "pre-cutoff features lint as before"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# F03 — flow lint: an exit code taken after a pipe in acceptance.md / PASS
# ---------------------------------------------------------------------------

# _z4_evidence_repo <date> <file> <body> — a repo with .specs/001-x/TASKS.md
# (old, so no F04/F93 rule interferes) and <file> committed on <date>.
_z4_evidence_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/.specs/001-x/verify"
	_z4_plan "$d/.specs/001-x" "spec.md" "" "$Z4_OLD" "$_Z4_ROW" "$_Z4_T001"
	printf '%s\n' "$3" >"$d/.specs/001-x/$2"
	_z4_commit "$d" "$1" "evidence"
	printf '%s' "$d"
}

_z4_flow_lint() { run_cmd bash -c 'cd "$1" || exit 1; node "$2" lint .specs/001-x/TASKS.md' _ "$1" "$Z4_FLOW"; }

_Z4_ACC_HEAD='| Criterion | Command | Exit | Showed |
|---|---|---|---|'

t_z4_acceptance_pipe_without_pipefail_errors() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 verify/acceptance.md "$_Z4_ACC_HEAD
| FR-01 | \`pytest \\| tail -5\` | 0 | 12 passed |")
	_z4_flow_lint "$d"
	assert_rc 1 "a piped command in acceptance.md is an ERROR"
	assert_contains "$OUT" "[exit-after-pipe]" "rule name"
	assert_contains "$OUT" "pipefail" "the fix names pipefail"
	rm -rf "$d"
}

t_z4_acceptance_pipe_with_longer_command_header_errors() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 verify/acceptance.md "| Criterion | Command run now | Exit | Showed |
|---|---|---|---|
| FR-01 | \`pytest \\| tail -5\` | 0 | 12 passed |")
	_z4_flow_lint "$d"
	assert_rc 1 "a 'Command run now' header is still checked"
	assert_contains "$OUT" "[exit-after-pipe]" "rule name"
	rm -rf "$d"
}

t_z4_acceptance_unescaped_pipe_splits_cells_still_errors() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 verify/acceptance.md "$_Z4_ACC_HEAD
| FR-01 | \`pytest | tail -5\` | 0 | 12 passed |")
	_z4_flow_lint "$d"
	assert_contains "$OUT" "[exit-after-pipe]" "a pipe that split the cell is found too"
	rm -rf "$d"
}

t_z4_acceptance_pipefail_is_accepted() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 verify/acceptance.md "$_Z4_ACC_HEAD
| FR-01 | \`set -o pipefail; pytest \\| tail -5\` | 0 | 12 passed |
| FR-02 | \`pytest \\| tail -5; echo \${PIPESTATUS[0]}\` | 0 | ok |")
	_z4_flow_lint "$d"
	assert_rc 0 "pipefail or PIPESTATUS is accepted"
	assert_not_contains "$OUT" "exit-after-pipe" "no rule fires"
	rm -rf "$d"
}

t_z4_acceptance_quoted_pipe_and_or_are_not_pipes() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 verify/acceptance.md "$_Z4_ACC_HEAD
| FR-01 | \`grep -E \"a\\|b\" f.txt\` | 0 | x |
| FR-02 | \`test -f a \\|\\| test -f b\` | 0 | x |")
	_z4_flow_lint "$d"
	assert_not_contains "$OUT" "exit-after-pipe" "a quoted pipe and || are not pipes"
	rm -rf "$d"
}

t_z4_old_acceptance_with_pipe_is_spared() {
	local d
	d=$(_z4_evidence_repo 2026-10-01 verify/acceptance.md "$_Z4_ACC_HEAD
| FR-01 | \`pytest \\| tail -5\` | 0 | 12 passed |")
	_z4_flow_lint "$d"
	assert_not_contains "$OUT" "exit-after-pipe" "a file dated before the cutoff is not flagged"
	rm -rf "$d"
}

t_z4_pass_file_pipe_errors() {
	local d
	d=$(_z4_evidence_repo 2026-10-20 PASS-abc1234.md '| Gate | Command | Exit | Executed |
|------|---------|------|----------|
| test | `pytest \| tail -5` | 0 | 12 |

Not checked: none')
	_z4_flow_lint "$d"
	assert_rc 1 "a piped command in a PASS table is an ERROR"
	assert_contains "$OUT" "[exit-after-pipe]" "rule name"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# F112 — task-brief prints the spec's "Ask first" bullets
# ---------------------------------------------------------------------------

t_z4_task_brief_prints_ask_first_bullets() {
	local d
	d=$(tmp_dir)
	printf '# Spec\n\n## 2. Scope\n\n### 2.3 Ask first\n\n- new runtime dependency\n- CI/workflow config\n- schema migration\n\n## 3. Journeys\n- not this one\n' >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T001"
	run_cmd bash "$Z4_BRIEF" "$d/TASKS.md" T001
	assert_rc 0 "task-brief runs"
	local b
	b=$(cat "$d/review/T001-brief.md")
	assert_contains "$b" "## Ask first" "the brief has an Ask first block"
	assert_contains "$b" "- new runtime dependency" "it carries the bullets"
	assert_contains "$b" "- schema migration" "all of them"
	assert_not_contains "$b" "not this one" "and stops at the next heading"
	rm -rf "$d"
}

t_z4_task_brief_without_ask_first_adds_no_block() {
	local d
	d=$(tmp_dir)
	printf '# Spec\n\n## 2. Scope\n\n### 2.1 In scope\n- a\n' >"$d/spec.md"
	_z4_plan "$d" "spec.md" "" "$Z4_NEW" "$_Z4_ROW" "$_Z4_T001"
	run_cmd bash "$Z4_BRIEF" "$d/TASKS.md" T001
	assert_not_contains "$(cat "$d/review/T001-brief.md")" "Ask first" "no block when the spec has no 2.3"
	rm -rf "$d"
}
