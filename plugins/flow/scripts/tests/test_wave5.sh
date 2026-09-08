#!/usr/bin/env bash
# test_wave5.sh — tests for unit V1 (C17): skills-lint's C16 placeholder/fence
# skip. Sourced by tests/run.sh; HERE (this dir) and SCAN_DIR (its parent,
# "scripts/") are already set. t_v1_* prefix.
#
# Spec 004 deleted slice-overlap and plan-lint, so the t_v1_slice_overlap_waves_*
# and t_v1_plan_lint_discovered_* tests that lived here are gone from this file.
# Neither was weakened:
#   slice-overlap --waves -> flow-lint --waves / --json "waves", tested by
#       t_flowlint_waves_output, t_flowlint_json_shape, t_flowlint_cycle_is_error
#       and t_flowlint_parallel_overlap_in_wave_is_error in test_flow_lint.sh.
#   plan-lint's "## Discovered" section -> DROPPED, no replacement grammar:
#       spec 004 moves discovered work to a `Discovered:` line in NOTES.md
#       (asserted by t_v2_* in test_wave5_prose.sh), so there is no longer a
#       plan-file section whose placement or bullet shape can be linted.

FIX="$HERE/fixtures"
SKILLS_LINT="$SCAN_DIR/skills-lint"

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
