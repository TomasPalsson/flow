#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_wave5_prose.sh — unit V2 (flow prose: waves wording, Discovered,
# /wrap) tests for C17. Sourced by run.sh; HERE (this dir) and SCAN_DIR
# (its parent, "scripts/") are already set. Tests prefixed t_v2_.

FLOW_DIR="$SCAN_DIR/../skills/flow"
CMD_DIR="${COMMANDS_DIR:-$SCAN_DIR/../commands}"

PLANNING_MD="$FLOW_DIR/planning.md"
BUILD_MD="$FLOW_DIR/steps/04-build.md"
WORKFLOW_MD="$FLOW_DIR/orchestration/workflow.md"
WRAP_MD="$CMD_DIR/wrap.md"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# _v2_line_count <file> → total lines in the file
_v2_line_count() {
	wc -l <"$1" | tr -d ' '
}

# _v2_body_line_count <file> → lines strictly after the closing frontmatter ---
_v2_body_line_count() {
	awk '
    /^---$/ { n++; if (n == 2) { start = 1; next } }
    start { count++ }
    END { print count + 0 }
  ' "$1"
}

# _v2_workflow_args_block <file> → the Workflow({ name: 'build-slices', ... } })
# call, extracted verbatim, or empty if not found
_v2_workflow_args_block() {
	sed -n "/Workflow({ name: '\(harness:\)\{0,1\}build-slices'/,/^} })/p" "$1"
}

# _v2_lines_mentioning_deps_files <file> → lines mentioning deps or files
# (case-insensitive), used to check no "mandatory"/"not optional" sits next
# to them
_v2_lines_mentioning_deps_files() {
	grep -inE 'deps|files' "$1" || true
}

# ---------------------------------------------------------------------------
# planning.md documents the optional ## Discovered section (C17)
# ---------------------------------------------------------------------------

t_v2_planning_discovered_heading_present() {
	assert_contains "$(cat "$PLANNING_MD")" "## Discovered" \
		"planning.md documents the ## Discovered section"
}

t_v2_planning_discovered_bullet_shape() {
	assert_contains "$(cat "$PLANNING_MD")" \
		"discovered in Slice <N> — <defer|fold into Slice M>" \
		"planning.md documents the Discovered bullet shape"
}

t_v2_planning_discovered_placement_rule() {
	local body
	body=$(cat "$PLANNING_MD")
	assert_contains "$body" "after the last" "planning.md states Discovered sits after the last slice"
	assert_contains "$body" "before" "planning.md mentions Discovered's placement before Gate Phases"
}

t_v2_planning_line_budget() {
	local n
	n=$(_v2_line_count "$PLANNING_MD")
	if [ "$n" -le 110 ]; then
		_pass "planning.md is <= 110 lines (got $n)"
	else
		_fail "planning.md is <= 110 lines (got $n)" "over the C12 cap"
	fi
}

# ---------------------------------------------------------------------------
# 04-build.md: slice-overlap --waves wording, Discovered instruction,
# Workflow call args, deps/files optional (C17 delta to C13)
# ---------------------------------------------------------------------------

t_v2_build_slice_overlap_waves_sentence() {
	local body
	body=$(cat "$BUILD_MD")
	assert_contains "$body" 'slice-overlap --waves' \
		"04-build.md runs slice-overlap --waves first"
	assert_contains "$body" "launch the waves it prints" \
		"04-build.md says to launch the waves slice-overlap --waves prints"
}

t_v2_build_discovered_instruction() {
	assert_contains "$(cat "$BUILD_MD")" "## Discovered" \
		"04-build.md tells implementers to record out-of-plan work as a Discovered bullet"
}

t_v2_build_workflow_args_no_deps_files_keys() {
	local block
	block=$(_v2_workflow_args_block "$BUILD_MD")
	assert_contains "$block" "plan:" "04-build.md Workflow call passes plan"
	assert_contains "$block" "design:" "04-build.md Workflow call passes design"
	assert_contains "$block" "base:" "04-build.md Workflow call passes base"
	assert_contains "$block" "slices:" "04-build.md Workflow call passes slices"
	assert_contains "$block" "testCmd:" "04-build.md Workflow call passes testCmd"
	assert_not_contains "$block" "deps:" "04-build.md Workflow call does not hardcode deps"
	assert_not_contains "$block" "files:" "04-build.md Workflow call does not hardcode files"
}

t_v2_build_deps_files_may_be_omitted() {
	assert_contains "$(cat "$BUILD_MD")" "MAY be omitted" \
		"04-build.md says deps/files MAY be omitted because build-slices computes them"
}

t_v2_build_no_mandatory_near_deps_files() {
	local hits
	hits=$(_v2_lines_mentioning_deps_files "$BUILD_MD")
	assert_not_contains "$hits" "not optional" \
		"04-build.md: no 'not optional' wording next to deps/files"
	assert_not_contains "$hits" "mandatory" \
		"04-build.md: no 'mandatory' wording next to deps/files"
}

t_v2_build_line_budget() {
	local n
	n=$(_v2_line_count "$BUILD_MD")
	if [ "$n" -le 80 ]; then
		_pass "04-build.md is <= 80 lines (got $n)"
	else
		_fail "04-build.md is <= 80 lines (got $n)" "over the C12 per-step-file cap"
	fi
}

# ---------------------------------------------------------------------------
# orchestration/workflow.md: same optional wording as 04-build.md
# ---------------------------------------------------------------------------

t_v2_workflow_md_deps_files_may_be_omitted() {
	assert_contains "$(cat "$WORKFLOW_MD")" "MAY be omitted" \
		"orchestration/workflow.md says deps/files MAY be omitted"
}

t_v2_workflow_md_no_mandatory_near_deps_files() {
	local hits
	hits=$(_v2_lines_mentioning_deps_files "$WORKFLOW_MD")
	assert_not_contains "$hits" "not optional" \
		"orchestration/workflow.md: no 'not optional' wording next to deps/files"
	assert_not_contains "$hits" "mandatory" \
		"orchestration/workflow.md: no 'mandatory' wording next to deps/files"
}

t_v2_workflow_md_line_budget() {
	local n
	n=$(_v2_line_count "$WORKFLOW_MD")
	if [ "$n" -le 70 ]; then
		_pass "orchestration/workflow.md is <= 70 lines (got $n)"
	else
		_fail "orchestration/workflow.md is <= 70 lines (got $n)" "over the C12 per-orchestration-file cap"
	fi
}

# ---------------------------------------------------------------------------
# commands/wrap.md: drains Discovered defer bullets, collapses old Done
# bullets, body cap (C17 delta to C14)
# ---------------------------------------------------------------------------

t_v2_wrap_drains_discovered_defer_bullets() {
	local body
	body=$(cat "$WRAP_MD")
	assert_contains "$body" "Discovered" "wrap.md reads the plan's Discovered section"
	assert_contains "$body" "defer" "wrap.md drains defer bullets"
	assert_contains "$body" "## Next" "wrap.md drains Discovered bullets into ## Next"
	assert_contains "$body" "dedup" "wrap.md dedups drained bullets"
}

t_v2_wrap_removes_discovered_from_plan() {
	assert_contains "$(cat "$WRAP_MD")" "remove" \
		"wrap.md removes the Discovered section from the plan after draining"
}

# Findings 1+2 (fix round 1): step 3 must not tell the agent to delete the
# whole ## Discovered section (including fold-into-Slice-M bullets) in one
# clause and then tell it to leave fold-into-Slice-M bullets in the plan in
# the next — that is unsatisfiable as written. Reconciled wording: only the
# drained `defer` bullets are removed; `fold into Slice M` bullets stay;
# the heading itself goes only once nothing remains under it.
t_v2_wrap_discovered_removal_is_selective_not_whole_section() {
	local body
	body=$(cat "$WRAP_MD")
	assert_contains "$body" "only those drained" \
		"wrap.md step 3 removes only the drained defer bullets, not the whole section"
	assert_contains "$body" "Leave every \`fold into Slice M\` bullet in place" \
		"wrap.md step 3 keeps fold-into-Slice-M bullets in the plan"
	assert_contains "$body" "once no bullets remain" \
		"wrap.md step 3 removes the Discovered heading only when it is empty"
	assert_not_contains "$body" "then remove \`## Discovered\` from the plan file. Leave" \
		"wrap.md step 3 no longer gives the self-contradictory unconditional-removal instruction"
}

t_v2_wrap_collapses_old_done_bullets() {
	local body
	body=$(cat "$WRAP_MD")
	assert_contains "$body" "30 days" "wrap.md names the 30-day collapse threshold"
	assert_contains "$body" "collapse" "wrap.md collapses old ## Done bullets"
}

t_v2_wrap_body_line_cap() {
	local n
	n=$(_v2_body_line_count "$WRAP_MD")
	if [ "$n" -le 35 ]; then
		_pass "wrap.md body is <= 35 lines (got $n)"
	else
		_fail "wrap.md body is <= 35 lines (got $n)" "over the C17 cap"
	fi
}

# ---------------------------------------------------------------------------
# sanity: files exist
# ---------------------------------------------------------------------------

t_v2_files_exist() {
	assert_file_exists "$PLANNING_MD" "flow/planning.md exists"
	assert_file_exists "$BUILD_MD" "flow/steps/04-build.md exists"
	assert_file_exists "$WORKFLOW_MD" "flow/orchestration/workflow.md exists"
	assert_file_exists "$WRAP_MD" "commands/wrap.md exists"
}
