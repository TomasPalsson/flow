#!/usr/bin/env bash
# test_wave5.sh — tests for unit V1 (C17): slice-overlap --waves, plan-lint's
# Discovered section, and skills-lint's C16 placeholder/fence skip. Sourced
# by tests/run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set. t_v1_* prefix.

FIX="$HERE/fixtures"
SLICE_OVERLAP="$SCAN_DIR/slice-overlap"
PLAN_LINT="$SCAN_DIR/plan-lint"
SKILLS_LINT="$SCAN_DIR/skills-lint"

# ---------------------------------------------------------------------------
# slice-overlap --waves
# ---------------------------------------------------------------------------

t_v1_slice_overlap_waves_help_mentions_waves() {
	run_cmd "$SLICE_OVERLAP" --help
	assert_rc 0 "v1: slice-overlap --help exits 0"
	assert_contains "$OUT" "--waves" "v1: slice-overlap --help documents --waves"
}

t_v1_slice_overlap_waves_two_wave_fixture_plain() {
	run_cmd "$SLICE_OVERLAP" --waves "$FIX/plan-waves.md"
	assert_rc 0 "v1: slice-overlap --waves on plan-waves.md exits 0"
	assert_eq "$OUT" "wave 1: Slice 1
wave 2: Slice 2, Slice 3" "v1: slice-overlap --waves prints the two computed waves"
}

t_v1_slice_overlap_waves_two_wave_fixture_json() {
	run_cmd "$SLICE_OVERLAP" --waves --json "$FIX/plan-waves.md"
	assert_rc 0 "v1: slice-overlap --waves --json on plan-waves.md exits 0"
	assert_eq "$OUT" '{"waves":[[1],[2,3]]}' "v1: slice-overlap --waves --json prints the expected structure"
}

t_v1_slice_overlap_waves_shared_file_exit1() {
	run_cmd "$SLICE_OVERLAP" --waves "$FIX/plan-waves-overlap.md"
	assert_rc 1 "v1: slice-overlap --waves exits 1 on a shared file (overlap unchanged)"
	assert_contains "$OUT" "src/shared.py: Slice 1, Slice 2" "v1: slice-overlap --waves reports the shared file like the plain overlap check"
	assert_not_contains "$OUT" "wave " "v1: slice-overlap --waves does not print wave lines when overlap wins the gate"
}

t_v1_slice_overlap_waves_shared_file_json_uses_overlaps_schema() {
	run_cmd "$SLICE_OVERLAP" --waves --json "$FIX/plan-waves-overlap.md"
	assert_rc 1 "v1: slice-overlap --waves --json exits 1 on a shared file"
	assert_contains "$OUT" '"overlaps":[{"file":"src/shared.py"' "v1: slice-overlap --waves --json reuses the unchanged overlaps JSON schema, not a waves schema, when overlap wins the gate"
}

t_v1_slice_overlap_waves_cycle_exit1() {
	run_cmd "$SLICE_OVERLAP" --waves "$FIX/plan-cycle.md"
	assert_rc 1 "v1: slice-overlap --waves exits 1 on a dependency cycle"
	assert_contains "$OUT" "INVALID: dependency cycle among Slice 1, Slice 2" "v1: slice-overlap --waves names the cycling slices"
}

t_v1_slice_overlap_waves_well_formed() {
	if [ -x "$SLICE_OVERLAP" ]; then
		_pass "v1: slice-overlap is executable"
	else
		_fail "v1: slice-overlap is executable"
	fi
	if head -1 "$SLICE_OVERLAP" | grep -q '^#!/usr/bin/env bash$'; then
		_pass "v1: slice-overlap has a portable shebang"
	else
		_fail "v1: slice-overlap has a portable shebang"
	fi
	if grep -q '^set -u' "$SLICE_OVERLAP"; then
		_pass "v1: slice-overlap sets -u"
	else
		_fail "v1: slice-overlap sets -u"
	fi
	run_cmd bash -n "$SLICE_OVERLAP"
	assert_rc 0 "v1: slice-overlap passes bash -n"
}

# ---------------------------------------------------------------------------
# plan-lint — Discovered section (C17)
# ---------------------------------------------------------------------------

t_v1_plan_lint_discovered_good_ok() {
	run_cmd "$PLAN_LINT" "$FIX/plan-discovered-good.md"
	assert_rc 0 "v1: plan-lint on plan-discovered-good.md exits 0"
	assert_eq "$OUT" "OK" "v1: plan-lint on plan-discovered-good.md prints OK"
}

t_v1_plan_lint_discovered_good_fence_decoy_ignored() {
	run_cmd "$PLAN_LINT" "$FIX/plan-discovered-good.md"
	assert_not_contains "$OUT" "Slice 9" "v1: plan-lint ignores the fenced decoy Discovered bullet and heading"
}

t_v1_plan_lint_discovered_bad_misplaced() {
	run_cmd "$PLAN_LINT" "$FIX/plan-discovered-bad.md"
	assert_rc 1 "v1: plan-lint on plan-discovered-bad.md exits 1"
	assert_contains "$OUT" "INVALID: Discovered section is misplaced" "v1: plan-lint flags a Discovered section that is not after the last slice"
}

t_v1_plan_lint_discovered_bad_bullet_shape() {
	run_cmd "$PLAN_LINT" "$FIX/plan-discovered-bad.md"
	assert_contains "$OUT" "INVALID: Discovered bullet 2 does not name an existing slice" "v1: plan-lint flags a Discovered bullet naming a non-existent slice"
}

t_v1_plan_lint_discovered_absence_never_missing() {
	# plan-good.md (U4's fixture, read-only) has no Discovered section at
	# all; its absence must never be reported as MISSING.
	run_cmd "$PLAN_LINT" "$FIX/plan-good.md"
	assert_not_contains "$OUT" "Discovered" "v1: plan-lint never reports a missing Discovered section"
}

t_v1_plan_lint_discovered_misplaced_before_any_slice() {
	d=$(tmp_dir)
	cat >"$d/plan.md" <<'PLANEOF'
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | `test_thing` |

## Discovered

- Found something early — discovered in Slice 1 — defer

## Slice 1 — Thing

- **Files**: src/thing.ts

### Slice 1 — RED

x

### Slice 1 — GREEN

x

### Slice 1 — REFACTOR

x

## Gate Phases

1. Run check-all.
PLANEOF
	run_cmd "$PLAN_LINT" "$d/plan.md"
	assert_rc 1 "v1: plan-lint rejects a Discovered section before the first slice"
	assert_contains "$OUT" "INVALID: Discovered section is misplaced" "v1: plan-lint names the misplaced-Discovered problem"
}

# ---------------------------------------------------------------------------
# skills-lint — C16 placeholder / fence skip
# ---------------------------------------------------------------------------

t_v1_skills_lint_placeholders_help_mentions_c16() {
	run_cmd "$SKILLS_LINT" --help
	assert_contains "$OUT" "foo" "v1: skills-lint --help documents the foo/bar placeholder skip"
}

t_v1_skills_lint_placeholders_skipped() {
	run_cmd "$SKILLS_LINT" "$FIX/skills-placeholders"
	assert_not_contains "$OUT" "references/a.md" "v1: skills-lint skips a single-char placeholder stem (a)"
	assert_not_contains "$OUT" "references/X.md" "v1: skills-lint skips the literal X placeholder stem"
	assert_not_contains "$OUT" "references/foo.md" "v1: skills-lint skips the literal foo placeholder stem"
	assert_not_contains "$OUT" "references/bar.md" "v1: skills-lint skips the literal bar placeholder stem"
}

t_v1_skills_lint_fenced_reference_skipped() {
	run_cmd "$SKILLS_LINT" "$FIX/skills-placeholders"
	assert_not_contains "$OUT" "fenced-ghost" "v1: skills-lint skips a dead reference inside a fenced code block"
}

t_v1_skills_lint_real_missing_still_reported() {
	run_cmd "$SKILLS_LINT" "$FIX/skills-placeholders"
	assert_rc 1 "v1: skills-lint on skills-placeholders still exits 1 (one genuine dead reference)"
	assert_contains "$OUT" "MISSING" "v1: skills-lint reports the genuine dead reference"
	assert_contains "$OUT" "scripts/deploy-staging.sh" "v1: skills-lint names the genuine dead reference"
}

t_v1_skills_lint_placeholders_fixture_only_one_line() {
	run_cmd "$SKILLS_LINT" "$FIX/skills-placeholders"
	lines=$(printf '%s\n' "$OUT" | grep -vc '^$')
	assert_eq "$lines" "1" "v1: skills-lint on skills-placeholders prints exactly the one genuine MISSING line"
}
