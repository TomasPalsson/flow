#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_spec_prose.sh — unit V8 (flow v2 prose: the Approved line, C20) tests.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set. Tests prefixed t_v8_.
#
# Spec 004 moved the Approved: line's owner: routing left skills/flow/steps/
# (deleted) for bin/flow, so the instruction that used to live in
# 03-plan.md/planning.md now lives in the /flow:next skill's `unapproved`
# state, and /flow:spec is banned from writing the line at all. These tests
# were rewritten onto those two files rather than deleted — the behaviour
# under test (only a human's word writes Approved:) is unchanged and got
# strictly stricter: the old `auto (--unattended)` variant is gone, because
# spec 004 forbids an unattended run from approving its own plan.

NEXT_SKILL="$SCAN_DIR/../skills/next/SKILL.md"
SPEC_SKILL="$SCAN_DIR/../skills/spec/SKILL.md"
WRAP="${COMMANDS_DIR:-$SCAN_DIR/../commands}/wrap.md"

# ---------------------------------------------------------------------------
# next/SKILL.md: exact "Approved:" instructions (C20)
# ---------------------------------------------------------------------------

t_v8_next_approved_by_user_line() {
	assert_contains "$(cat "$NEXT_SKILL")" \
		'Approved: <YYYY-MM-DD> by user' \
		"next/SKILL.md instructs the exact 'Approved: <YYYY-MM-DD> by user' line"
}

t_v8_next_approved_only_on_user_word() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" 'HARD GATE' \
		"next/SKILL.md marks the unapproved state a HARD GATE"
	assert_contains "$content" 'never write it yourself' \
		"next/SKILL.md states the model never writes the Approved line itself"
}

# The unattended auto-approval variant is deliberately deleted by spec 004:
# --unattended resolves decisions, never the two stored human facts.
t_v8_next_no_unattended_auto_approval() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_not_contains "$content" 'auto (--unattended)' \
		"next/SKILL.md has no auto-approved Approved: variant"
	assert_contains "$content" 'Approved:` or `Verified:` yourself, in any mode' \
		"next/SKILL.md bans writing Approved:/Verified: in any mode"
}

# ---------------------------------------------------------------------------
# spec/SKILL.md never writes the line — that is the build verb's gate
# ---------------------------------------------------------------------------

t_v8_spec_skill_never_writes_approved() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'Do **not** write `Approved:`' \
		"spec/SKILL.md tells the drafting step not to write Approved:"
	assert_contains "$content" 'write `Approved:` yourself, on any route' \
		"spec/SKILL.md's NEVER list bans writing the Approved line"
}

# ---------------------------------------------------------------------------
# wrap.md keeps the line intact
# ---------------------------------------------------------------------------

# See the note in test_wave5_prose.sh: commands/ lives in the dotfiles (C21)
# and is absent from some checkouts; skip rather than report a permanent red.
t_v8_wrap_keeps_approved_line_intact() {
	if [ ! -f "$WRAP" ]; then printf '  skip t_v8_wrap_keeps_approved_line_intact (no commands/wrap.md in this checkout)\n'; return 0; fi
	assert_contains "$(cat "$WRAP")" \
		"Never touch the plan's" \
		"wrap.md instructs never touching the plan's Approved line"
}

# ---------------------------------------------------------------------------
# line-budget caps (C12)
# ---------------------------------------------------------------------------

t_v8_line_caps() {
	local n
	n=$(wc -l <"$NEXT_SKILL" | tr -d ' ')
	if [ "$n" -le 200 ]; then _pass "next/SKILL.md is <= 200 lines (got $n)"; else _fail "next/SKILL.md is <= 200 lines (got $n)" "over the spec 004 cap"; fi

	n=$(wc -l <"$SPEC_SKILL" | tr -d ' ')
	if [ "$n" -le 150 ]; then _pass "spec/SKILL.md is <= 150 lines (got $n)"; else _fail "spec/SKILL.md is <= 150 lines (got $n)" "over the spec 004 cap"; fi

	if [ -f "$WRAP" ]; then
		n=$(wc -l <"$WRAP" | tr -d ' ')
		if [ "$n" -le 35 ]; then _pass "wrap.md is <= 35 lines (got $n)"; else _fail "wrap.md is <= 35 lines (got $n)" "over the C12 cap"; fi
	fi
}

# ---------------------------------------------------------------------------
# the deleted files stay deleted (routing lives in bin/flow now)
# ---------------------------------------------------------------------------

t_v8_old_step_files_deleted() {
	assert_file_missing "$SCAN_DIR/../skills/flow" "skills/flow is renamed to skills/next"
	assert_file_missing "$SCAN_DIR/../skills/next/steps" "next/steps/ is deleted; routing lives in bin/flow"
	assert_file_missing "$SCAN_DIR/../skills/next/planning.md" "next/planning.md is deleted"
	assert_file_missing "$SCAN_DIR/../skills/next/orchestration.md" "next/orchestration.md is deleted"
}

# ---------------------------------------------------------------------------
# spec/SKILL.md: the rest of the F4 contract — route as a stated fact, one
# batched discovery turn, the per-route write matrix, the judge cap, the
# hand-off order, and the three flags.
# ---------------------------------------------------------------------------

t_v8_spec_states_the_route_never_asks_it() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'State the route; do not ask it' \
		"spec/SKILL.md states the route rather than asking for it"
	assert_contains "$content" 'intent gaps' \
		"spec/SKILL.md counts intent gaps"
	assert_contains "$content" 'irreversibles' \
		"spec/SKILL.md counts irreversibles"
	assert_contains "$content" 'footprint' \
		"spec/SKILL.md counts footprint"
}

t_v8_spec_discovery_is_one_batched_turn() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'ONE turn' \
		"spec/SKILL.md runs exactly one discovery turn"
	assert_contains "$content" 'references/question-bank.md' \
		"spec/SKILL.md loads the question bank for that turn"
	assert_contains "$content" 'NEVER** ask more than one discovery turn' \
		"spec/SKILL.md's NEVER list bans a second discovery turn"
}

t_v8_spec_write_matrix_per_route() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" '**nothing under `.specs/NNN-slug/`**' \
		"spec/SKILL.md writes nothing on bounded"
	assert_contains "$content" '`TASKS.md` only' \
		"spec/SKILL.md writes TASKS.md only on oneshot"
	assert_contains "$content" '`spec.md` + `TASKS.md` (+ `design.md` on the seam trigger)' \
		"spec/SKILL.md writes spec.md + TASKS.md (+ design.md) on dispatch"
	assert_contains "$content" 'NEVER** write a `spec.md` on `bounded` or `oneshot`' \
		"spec/SKILL.md's NEVER list bans a spec.md on the light routes"
}

t_v8_spec_judge_is_capped_and_dispatch_only() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'capped at one iteration' \
		"spec/SKILL.md caps spec-judge at one iteration"
	assert_contains "$content" '`oneshot` and `bounded` never invoke it' \
		"spec/SKILL.md runs spec-judge on dispatch only"
	assert_contains "$content" 'never self-score' \
		"spec/SKILL.md refuses to self-score when spec-judge is missing"
}

t_v8_spec_handoff_order_and_manifest() {
	local content use_at lint_at
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'This run will stop for you N times' \
		"spec/SKILL.md prints the truthful gate manifest"
	assert_contains "$content" "end with the router's own line" \
		"spec/SKILL.md ends with the router's own Next: line"
	use_at=$(grep -n '`flow use <NNN-slug>`' "$SPEC_SKILL" | head -1 | cut -d: -f1)
	lint_at=$(grep -n '^2\. `flow lint`' "$SPEC_SKILL" | head -1 | cut -d: -f1)
	if [ -n "$use_at" ] && [ -n "$lint_at" ] && [ "$use_at" -lt "$lint_at" ]; then
		_pass "spec/SKILL.md runs flow use before flow lint"
	else
		_fail "spec/SKILL.md runs flow use before flow lint" \
			"flow use at line '$use_at', flow lint at line '$lint_at'"
	fi
}

# The approval gate is approvable without opening TASKS.md: both doors print
# the same plain-words plan, and neither tells the user to read the file first.
t_v8_approval_gate_prints_plain_plan() {
	local skill row
	for skill in "$SPEC_SKILL" "$NEXT_SKILL"; do
		assert_contains "$(cat "$skill")" 'no task IDs, no file paths' \
			"$(basename "$(dirname "$skill")")/SKILL.md carries the plain-plan rule"
		assert_not_contains "$(cat "$skill")" 'Next: read .specs/003-entry-tagging/TASKS.md' \
			"$(basename "$(dirname "$skill")")/SKILL.md no longer tells the user to read TASKS.md"
	done
	assert_contains "$(cat "$SPEC_SKILL")" '**What will happen**' \
		"spec/SKILL.md hands off with the plain-words plan"
	row=$(grep '^| `unapproved`' "$NEXT_SKILL")
	assert_contains "$row" '**What will happen**' \
		"next/SKILL.md prints the plain-words plan at the unapproved gate"
	assert_not_contains "$(cat "$SCAN_DIR/../skills/flow-deepen/SKILL.md")" 'read TASKS.md and reply' \
		"flow-deepen/SKILL.md, the third door into the gate, no longer tells the user to read TASKS.md"
}

t_v8_spec_amend_is_append_only_and_clears_approved() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'append-only' \
		"spec/SKILL.md's --amend re-plans append-only"
	assert_contains "$content" '`Approved:` is **cleared**' \
		"spec/SKILL.md's --amend clears Approved:"
	assert_contains "$content" 'byte-for-byte identical' \
		"spec/SKILL.md's --amend is a byte-for-byte no-op when nothing changed"
}

t_v8_spec_documents_its_three_flags() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" '`--interview` restores the serial one-question-per-turn form' \
		"spec/SKILL.md documents --interview"
	assert_contains "$content" '`--unattended` proceeds on the stated positions' \
		"spec/SKILL.md documents --unattended"
	assert_contains "$content" '## 7. `--amend "<change>"`' \
		"spec/SKILL.md documents --amend"
}

# ---------------------------------------------------------------------------
# spec/SKILL.md: stealth mode (--stealth, flow stealth --check)
# ---------------------------------------------------------------------------

t_v8_spec_documents_stealth() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" '--stealth' \
		"spec/SKILL.md's description Flags: list names --stealth"
	assert_contains "$content" '## 4a. Stealth' \
		"spec/SKILL.md has a Stealth section"
	assert_contains "$content" '`flow stealth --check' \
		"spec/SKILL.md documents flow stealth --check"
	assert_contains "$content" 'NEVER** commit, link or name a spec in a repo where `stealth.active` is true' \
		"spec/SKILL.md's NEVER list bans naming a spec under stealth"
}
