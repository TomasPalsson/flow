#!/usr/bin/env bash
# test_no_slop.sh — tests for the no-slop skill's scripts/slop-check
# against the planted-slop fixture in fixtures/no-slop/make-fixture.sh
# (B1 to B5). t_noslop_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

SKILL_DIR="$SCAN_DIR/../skills/no-slop"
SLOP_CHECK="$SKILL_DIR/scripts/slop-check"
MAKE_FIXTURE="$HERE/fixtures/no-slop/make-fixture.sh"

PLANTED_IDS='NS-03 NS-04 NS-05 NS-06 NS-08 NS-09 NS-10 NS-13 NS-15'

# run_slop <repo-dir> [slop-check args...] — runs slop-check with its cwd
# set to <repo-dir>, since it resolves the repo root via `git rev-parse`.
run_slop() {
	local repo=$1
	shift
	run_cmd bash -c 'cd "$1" || exit 1; shift; exec "$@"' _ "$repo" "$SLOP_CHECK" "$@"
}

# ---------------------------------------------------------------------------
# B1 — make-fixture.sh builds a "base"-tagged clean commit and a HEAD
# commit planted on top of it.
# ---------------------------------------------------------------------------

t_noslop_fixture_builds_base_tag() {
	d=$(tmp_dir)
	run_cmd bash "$MAKE_FIXTURE" "$d"
	assert_rc 0 "make-fixture.sh exits 0"
	run_cmd bash -c 'cd "$1" && git rev-parse --verify --quiet base' _ "$d"
	assert_rc 0 "make-fixture.sh tags the clean commit 'base'"
}

t_noslop_fixture_base_is_clean() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --head base --no-tools
	assert_eq "$OUT" "" "slop-check finds nothing between base and itself"
}

# ---------------------------------------------------------------------------
# B2 — slop-check --no-tools reports every planted NS id on the fixture's
# HEAD commit.
# ---------------------------------------------------------------------------

t_noslop_reports_planted_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools
	assert_rc 0 "slop-check exits 0 (advisory) despite findings"
	for id in $PLANTED_IDS; do
		assert_contains "$OUT" "$id" "slop-check reports $id on the fixture"
	done
}

# ---------------------------------------------------------------------------
# B3 — advisory by default; --strict turns findings into a non-zero exit.
# ---------------------------------------------------------------------------

t_noslop_strict_exits_nonzero_on_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools --strict
	assert_rc 1 "slop-check --strict exits 1 when findings exist"
}

t_noslop_strict_exits_zero_with_no_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --head base --no-tools --strict
	assert_rc 0 "slop-check --strict exits 0 when there are no findings"
}

# ---------------------------------------------------------------------------
# B4 — --json emits a findings array plus a summary.
# ---------------------------------------------------------------------------

t_noslop_json_output_shape() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools --json
	assert_rc 0 "slop-check --json exits 0"
	assert_contains "$OUT" '"findings"' "slop-check --json emits a findings array"
	assert_contains "$OUT" '"summary"' "slop-check --json emits a summary"
	assert_contains "$OUT" '"NS-03"' "slop-check --json findings carry NS ids"
}

# ---------------------------------------------------------------------------
# B5 — the skill package itself is present and well-formed.
# ---------------------------------------------------------------------------

t_noslop_skill_files_present() {
	assert_file_exists "$SKILL_DIR/SKILL.md" "SKILL.md exists"
	assert_file_exists "$SKILL_DIR/references/rubric.md" "references/rubric.md exists"
	assert_file_exists "$SKILL_DIR/references/developer-block.md" "references/developer-block.md exists"
	assert_file_exists "$SKILL_DIR/references/adversary-lens.md" "references/adversary-lens.md exists"
	assert_file_exists "$SKILL_DIR/references/evidence.md" "references/evidence.md exists"
	assert_file_exists "$SKILL_DIR/references/integration-seams.md" "references/integration-seams.md exists"
	assert_file_exists "$SKILL_DIR/scripts/slop_tools.py" "scripts/slop_tools.py exists"
}

t_noslop_skill_md_frontmatter() {
	run_cmd head -5 "$SKILL_DIR/SKILL.md"
	assert_contains "$OUT" "name: no-slop" "SKILL.md declares name: no-slop"
}

t_noslop_slop_check_is_executable() {
	if [ -x "$SLOP_CHECK" ]; then
		_pass "scripts/slop-check is executable"
	else
		_fail "scripts/slop-check is executable" "not executable: $SLOP_CHECK"
	fi
}
