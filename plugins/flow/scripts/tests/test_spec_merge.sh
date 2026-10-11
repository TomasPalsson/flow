#!/usr/bin/env bash
# test_spec_merge.sh — spec-merge folds an archived feature's keyed Behaviors
# rows into the living .specs/SPEC.md (famous-borrows F99). t_specmerge_*.
# Sourced by run.sh; SCAN_DIR is already set.

SPEC_MERGE="$SCAN_DIR/spec-merge"

# _sm_tasks <file> <rows...> — a TASKS.md whose Behaviors table has a Key column.
_sm_tasks() {
	local f=$1 hdr=${_SM_HDR:-}
	shift
	{
		printf '# Tasks — sm\nSpec: spec.md · Base: abc1234 · Route: dispatch · Test: `true`%s\n\n' "$hdr"
		printf '## Behaviors\n| ID | Given / When / Then | Task | Proven by | Key |\n|----|----|----|----|----|\n'
		printf '%s\n' "$@"
		printf '\n## Phase 1 — One\nGoal: g.\nIndependent test: `true`\n- [ ] T001 One — files: a.txt — verify: `true`\n'
	} >"$f"
}

# _sm_proj — a tmp dir with .specs/archive/{001-a,002-b}/
_sm_proj() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.specs/archive/001-a" "$d/.specs/archive/002-b"
	printf '%s' "$d"
}

t_specmerge_adds_rows_sorted_by_key() {
	local d
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" \
		'| FR-01 | a user adds a tag, then it persists | T001 | test_persist | tags/persist |' \
		'| FR-02 | a duplicate is refused | T001 | test_dup | tags/duplicate |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a clean merge exits 0"
	assert_file_exists "$d/.specs/SPEC.md" "the living file is created beside the archive"
	assert_contains "$(cat "$d/.specs/SPEC.md")" "| tags/persist | a user adds a tag, then it persists | test_persist | 001-a |" "the row carries its source feature"
	assert_eq "$(grep -n 'tags/duplicate' "$d/.specs/SPEC.md" | cut -d: -f1)" "$(($(grep -n 'tags/persist' "$d/.specs/SPEC.md" | cut -d: -f1) - 1))" "rows are sorted by key"
	rm -rf "$d"
}

t_specmerge_two_runs_are_byte_identical() {
	local d first second
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | g w t | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	first=$(cksum <"$d/.specs/SPEC.md")
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a second run exits 0"
	second=$(cksum <"$d/.specs/SPEC.md")
	assert_eq "$second" "$first" "the second run changes nothing"
	rm -rf "$d"
}

t_specmerge_second_run_with_a_recorded_base_is_still_a_noop() {
	local d first
	d=$(_sm_proj)
	_SM_HDR=' · Spec-base: none' _sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | g w t | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "an empty living file matches Spec-base: none"
	first=$(cksum <"$d/.specs/SPEC.md")
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "re-running an already merged feature is not a divergence"
	assert_eq "$(cksum <"$d/.specs/SPEC.md")" "$first" "and changes nothing"
	rm -rf "$d"
}

t_specmerge_replaces_records_previously() {
	local d
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | old behaviour | T001 | t1 | tags/persist |'
	_sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | new behaviour | T001 | t2 | tags/persist, Replaces: tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a Replaces: row merges"
	assert_contains "$(cat "$d/.specs/SPEC.md")" "new behaviour (Previously: old behaviour)" "the old text is kept as (Previously: ...)"
	assert_not_contains "$(cat "$d/.specs/SPEC.md")" "| old behaviour |" "the old row is gone"
	rm -rf "$d"
}

t_specmerge_retire_removes_and_lists() {
	local d
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | g w t | T001 | t | tags/persist |' '| FR-02 | g w t | T001 | t | tags/keep |'
	_sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | retire it | T001 | t | Retire: tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a Retire: row merges"
	assert_not_contains "$(cat "$d/.specs/SPEC.md")" "| tags/persist |" "the retired row is removed"
	assert_contains "$(cat "$d/.specs/SPEC.md")" "- tags/persist — retired by 002-b" "and listed under Retired"
	assert_contains "$(cat "$d/.specs/SPEC.md")" "| tags/keep |" "other rows stay"
	rm -rf "$d"
}

t_specmerge_collision_without_replaces_exits_1() {
	local d before
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | one | T001 | t | tags/persist |'
	_sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | two | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	before=$(cksum <"$d/.specs/SPEC.md")
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 1 "a key collision with no Replaces: exits 1"
	assert_contains "$ERR" "already in the living file" "the message says why"
	assert_contains "$ERR" "fix:" "and carries a fix"
	assert_eq "$(cksum <"$d/.specs/SPEC.md")" "$before" "the living file is untouched"
	rm -rf "$d"
}

t_specmerge_replaces_a_missing_key_exits_1() {
	local d
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | two | T001 | t | tags/new, Replaces: tags/ghost |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 1 "replacing a behaviour that is not there exits 1"
	assert_file_missing "$d/.specs/SPEC.md" "nothing is written"
	rm -rf "$d"
}

t_specmerge_diverged_base_exits_1() {
	local d before
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | one | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	before=$(cksum <"$d/.specs/SPEC.md")
	_SM_HDR=' · Spec-base: deadbeef0000' _sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | two | T001 | t | tags/other |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 1 "a base hash that does not match the living file exits 1"
	assert_contains "$ERR" "moved on" "the message says the file diverged"
	assert_eq "$(cksum <"$d/.specs/SPEC.md")" "$before" "the living file is untouched"
	rm -rf "$d"
}

t_specmerge_matching_base_merges() {
	local d h
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | one | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	h=$(printf '%s' "$OUT" | sed -n 's/.*hash \([0-9a-f]\{12\}\)).*/\1/p')
	assert_eq "${#h}" "12" "the merge prints the hash to record as Spec-base:"
	_SM_HDR=" · Spec-base: $h" _sm_tasks "$d/.specs/archive/002-b/TASKS.md" '| FR-01 | two | T001 | t | tags/other |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a matching Spec-base: merges"
	assert_contains "$(cat "$d/.specs/SPEC.md")" "| tags/other |" "the second feature's row is in"
	rm -rf "$d"
}

t_specmerge_no_behaviors_rows_leaves_the_file_byte_identical() {
	local d before
	d=$(_sm_proj)
	_sm_tasks "$d/.specs/archive/001-a/TASKS.md" '| FR-01 | one | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	before=$(cksum <"$d/.specs/SPEC.md")
	printf '# Tasks — none\nSpec: s.md · Base: abc1234 · Route: bounded · Test: `true`\n\n## Phase 1 — One\nGoal: g.\nIndependent test: `true`\n- [ ] T001 One — files: a.txt — verify: `true`\n' >"$d/.specs/archive/002-b/TASKS.md"
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/002-b/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a TASKS.md with no Behaviors rows exits 0"
	assert_eq "$(cksum <"$d/.specs/SPEC.md")" "$before" "the living file is byte-identical"
	rm -rf "$d"
}

t_specmerge_legacy_rows_without_a_key_are_not_backfilled() {
	local d
	d=$(_sm_proj)
	{
		printf '# Tasks — legacy\nSpec: s.md · Base: abc1234 · Route: bounded · Test: `true`\n\n'
		printf '## Behaviors\n| ID | Given / When / Then | Task | Proven by |\n|----|----|----|----|\n| B1 | g w t | T001 | t |\n'
	} >"$d/.specs/archive/001-a/TASKS.md"
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "a table with no Key column exits 0"
	assert_file_missing "$d/.specs/SPEC.md" "no living file is created from legacy rows"
	rm -rf "$d"
}

t_specmerge_stealth_symlink_writes_inside_the_store() {
	local d store
	d=$(tmp_dir)
	store=$(tmp_dir)
	mkdir -p "$store/archive/001-a"
	ln -s "$store" "$d/.specs"
	_sm_tasks "$store/archive/001-a/TASKS.md" '| FR-01 | one | T001 | t | tags/persist |'
	run_cmd bash -c 'cd "$1" && python3 -I "$2" .specs/archive/001-a/TASKS.md' _ "$d" "$SPEC_MERGE"
	assert_rc 0 "merging through a .specs symlink exits 0"
	assert_file_exists "$store/SPEC.md" "the living file lands in the store, not the repo"
	rm -rf "$d" "$store"
}

t_specmerge_next_skill_and_template_pinned() {
	local nx tp
	nx=$(cat "$SCAN_DIR/../skills/next/SKILL.md")
	tp=$(cat "$SCAN_DIR/../flow-templates/TASKS.md")
	assert_contains "$nx" "scripts/spec-merge" "the archive step runs spec-merge"
	assert_contains "$nx" ".specs/SPEC.md" "and names the living file"
	assert_contains "$tp" "| Key |" "the template's Behaviors table has a Key column"
	assert_contains "$tp" "Replaces:" "the template documents Replaces:"
	assert_contains "$tp" "Retire:" "the template documents Retire:"
}
