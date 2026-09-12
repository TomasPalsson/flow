#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_wave5_prose.sh — unit V2 (flow v2 prose: wave dispatch, Discovered,
# /wrap) tests for C17. Sourced by run.sh; HERE (this dir) and SCAN_DIR (its
# parent, "scripts/") are already set. Tests prefixed t_v2_.
#
# Spec 004 deleted the three files this unit used to read — skills/flow's
# planning.md, steps/04-build.md and orchestration/workflow.md — because
# routing and wave computation moved out of skill prose into bin/flow and
# scripts/flow-lint. Every assertion below was rewritten onto the replacement
# (skills/next/SKILL.md) rather than dropped; the behaviours under test are the
# same ones, at task granularity instead of slice granularity:
#   slice-overlap --waves  ->  the router's own wave: field, proved by flow lint
#   ## Discovered in the plan  ->  a Discovered: line in NOTES.md
#   orchestration/workflow.md's never-paste-the-doctrine rule  ->  next's NEVER list
# The deps/files-are-optional assertions are gone with the args they described:
# build-slices no longer takes deps/files at all (test_workflows.sh covers the
# flow-lint --json schedule that replaced them).

NEXT_SKILL="$SCAN_DIR/../skills/next/SKILL.md"
CMD_DIR="${COMMANDS_DIR:-$SCAN_DIR/../commands}"
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

# ---------------------------------------------------------------------------
# next/SKILL.md: the wave comes from the router, dispatch caps, the Workflow
# threshold, and the out-of-plan record (C17 at task granularity)
# ---------------------------------------------------------------------------

t_v2_next_wave_comes_from_the_router() {
	local body
	body=$(cat "$NEXT_SKILL")
	assert_contains "$body" 'wave: {ids, parallel}' \
		"next/SKILL.md takes the wave from flow next --json, not from its own overlap guess"
	assert_contains "$body" 'Wave N+1 never starts before wave N reports' \
		"next/SKILL.md states the wave barrier"
}

t_v2_next_dispatch_caps() {
	local body
	body=$(cat "$NEXT_SKILL")
	assert_contains "$body" 'in one message' \
		"next/SKILL.md dispatches a wave's [P] tasks in one message"
	assert_contains "$body" '4 in parallel' \
		"next/SKILL.md caps a wave at 4 parallel subagents"
	assert_contains "$body" 'only the brief path' \
		"next/SKILL.md hands a subagent only its brief path"
}

t_v2_next_workflow_threshold() {
	local body
	body=$(cat "$NEXT_SKILL")
	assert_contains "$body" "Workflow({ name: 'flow:build-slices'" \
		"next/SKILL.md names the build-slices Workflow call"
	assert_contains "$body" '3 ready `[P]` tasks' \
		"next/SKILL.md runs the Workflow only at three or more ready [P] tasks"
	assert_contains "$body" 'costs more than it schedules' \
		"next/SKILL.md says why a two-task workflow is not worth it"
}

t_v2_next_discovered_line_shape() {
	local body
	body=$(cat "$NEXT_SKILL")
	assert_contains "$body" 'Discovered: <what> — <defer | fold into T0NN>' \
		"next/SKILL.md documents the Discovered bullet shape"
	assert_contains "$body" 'NOTES.md' \
		"next/SKILL.md records out-of-plan work in NOTES.md"
}

t_v2_next_never_pastes_the_design() {
	assert_contains "$(cat "$NEXT_SKILL")" 'never paste anything from it but that task' \
		"next/SKILL.md keeps the never-paste-the-design rule that orchestration/workflow.md carried"
}

t_v2_next_reruns_verify_itself() {
	local body
	body=$(cat "$NEXT_SKILL")
	assert_contains "$body" 'The agent'"'"'s report is never the gate' \
		"next/SKILL.md re-runs each task's verify: rather than trusting the report"
	assert_contains "$body" 'missing, not passing' \
		"next/SKILL.md keeps the matrix rule: a test that did not run is missing"
}

t_v2_next_line_budget() {
	local n
	n=$(_v2_line_count "$NEXT_SKILL")
	if [ "$n" -le 200 ]; then
		_pass "next/SKILL.md is <= 200 lines (got $n)"
	else
		_fail "next/SKILL.md is <= 200 lines (got $n)" "over the spec 004 cap"
	fi
}


# The dotfiles' commands/ directory (C21: "stays in the dotfiles forever,
# never plugin content") is not present in every checkout. Skip the wrap.md
# assertions rather than reporting a permanent red for a file this repo does
# not and will not contain; they still run against the real file in the
# dotfiles' own scripts/tests/ suite.
_v2_have_wrap() { [ -f "$WRAP_MD" ]; }

# ---------------------------------------------------------------------------
# commands/wrap.md: drains Discovered defer bullets, collapses old Done
# bullets, body cap (C17 delta to C14)
# ---------------------------------------------------------------------------

t_v2_wrap_drains_discovered_defer_bullets() {
	if ! _v2_have_wrap; then printf '  skip %s (no commands/wrap.md in this checkout)\n' "t_v2_wrap_drains_discovered_defer_bullets"; return 0; fi
	local body
	body=$(cat "$WRAP_MD")
	assert_contains "$body" "Discovered" "wrap.md reads the plan's Discovered section"
	assert_contains "$body" "defer" "wrap.md drains defer bullets"
	assert_contains "$body" "## Next" "wrap.md drains Discovered bullets into ## Next"
	assert_contains "$body" "dedup" "wrap.md dedups drained bullets"
}

t_v2_wrap_removes_discovered_from_plan() {
	if ! _v2_have_wrap; then printf '  skip %s (no commands/wrap.md in this checkout)\n' "t_v2_wrap_removes_discovered_from_plan"; return 0; fi
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
	if ! _v2_have_wrap; then printf '  skip %s (no commands/wrap.md in this checkout)\n' "t_v2_wrap_discovered_removal_is_selective_not_whole_section"; return 0; fi
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
	if ! _v2_have_wrap; then printf '  skip %s (no commands/wrap.md in this checkout)\n' "t_v2_wrap_collapses_old_done_bullets"; return 0; fi
	local body
	body=$(cat "$WRAP_MD")
	assert_contains "$body" "30 days" "wrap.md names the 30-day collapse threshold"
	assert_contains "$body" "collapse" "wrap.md collapses old ## Done bullets"
}

t_v2_wrap_body_line_cap() {
	if ! _v2_have_wrap; then printf '  skip %s (no commands/wrap.md in this checkout)\n' "t_v2_wrap_body_line_cap"; return 0; fi
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
	assert_file_exists "$NEXT_SKILL" "skills/next/SKILL.md exists"
	assert_file_exists "$SCAN_DIR/../skills/next/execution-prompt.md" "next/execution-prompt.md moved over from feature/"
	assert_file_exists "$SCAN_DIR/../skills/next/review.md" "next/review.md is kept"
	if _v2_have_wrap; then assert_file_exists "$WRAP_MD" "commands/wrap.md exists"; else printf '  skip commands/wrap.md exists (not in this checkout)\n'; fi
}

# ---------------------------------------------------------------------------
# next/SKILL.md: the state table matches the router, and the turn contract
# (spec 004 requirement 3 and F4's owned sections) is actually asserted.
# ---------------------------------------------------------------------------

# Every state bin/flow can emit needs a row, or /flow:next lands on an
# undefined state with "do that and nothing else" as its only instruction.
t_v2_next_state_table_covers_every_router_state() {
	local router states st missing
	router="$SCAN_DIR/../bin/lib/router.js"
	if [ ! -f "$router" ]; then
		printf '  skip next/SKILL.md state table vs router (no bin/lib/router.js)\n'
		return 0
	fi
	states=$(sed -n "/^const STATE_NO = {/,/^};/p" "$router" |
		sed -n "s/^  '\{0,1\}\([a-z-]*\)'\{0,1\}:.*/\1/p")
	missing=""
	for st in $states; do
		grep -q "^| \`$st\` |" "$NEXT_SKILL" || missing="$missing $st"
	done
	if [ -z "$missing" ]; then
		_pass "next/SKILL.md has a row for every router STATE_NO state"
	else
		_fail "next/SKILL.md has a row for every router STATE_NO state" \
			"no row for:$missing"
	fi
}

t_v2_next_ends_every_turn_with_the_clear_line() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" 'Next: /clear, then /flow:next' \
		"next/SKILL.md states the exact end-of-turn line"
	assert_contains "$content" 'NEVER** end a turn without a last `Next:` line' \
		"next/SKILL.md bans ending a turn without a Next: line"
}

t_v2_next_gates_write_pass_sha_file() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" 'PASS-<HEAD-sha>.md' \
		"next/SKILL.md's gates write PASS-<HEAD-sha>.md"
	assert_contains "$content" 'flow check --fix' \
		"next/SKILL.md's gates run flow check --fix"
}

t_v2_next_checkpoint_evidence_goes_to_verify_dir() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" '.specs/<NNN-slug>/verify/' \
		"next/SKILL.md writes CHK evidence into the feature's verify/"
	assert_contains "$content" 'a verification claim with no file there does not count' \
		"next/SKILL.md states that an unevidenced verification claim does not count"
}

t_v2_next_ships_draft_then_ready() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" 'gh pr create --draft' \
		"next/SKILL.md opens the PR as a draft"
	assert_contains "$content" 'gh pr ready' \
		"next/SKILL.md promotes the draft with gh pr ready"
	assert_contains "$content" 'the PR **stays draft**' \
		"next/SKILL.md keeps an unattended PR in draft"
}

t_v2_next_archives_with_git_mv() {
	assert_contains "$(cat "$NEXT_SKILL")" \
		'git mv .specs/<NNN-slug> .specs/archive/<YYYY-MM-DD>-<NNN-slug>' \
		"next/SKILL.md archives a merged feature with an atomic git mv"
}

t_v2_next_flags_table_documents_every_flag() {
	local content flag
	content=$(cat "$NEXT_SKILL")
	for flag in --force --escalate --qa --unattended; do
		assert_contains "$content" "| \`$flag\` |" \
			"next/SKILL.md's flag table has a row for $flag"
	done
	assert_contains "$content" 'It resolves decisions, **never evidence**' \
		"next/SKILL.md states --unattended resolves decisions but never evidence"
}

# The per-task loop the skill hands to every developer subagent must not name
# state files spec 004 abolished (K-A/K-E), or every task agent goes looking
# for them.
t_v2_next_execution_prompt_has_no_v1_state_files() {
	local content pat
	content=$(cat "$SCAN_DIR/../skills/next/execution-prompt.md")
	for pat in 'workflow-state.local.md' 'feature-plan.local.md' '.claude/verification/' '.claude/quality/' 'skills/feature/'; do
		assert_not_contains "$content" "$pat" \
			"next/execution-prompt.md does not reference $pat"
	done
}
