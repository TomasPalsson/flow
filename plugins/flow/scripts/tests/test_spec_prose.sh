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
# --unattended resolves decisions, never the two stored human facts. The one
# sanctioned exception is the "autoApprove" config setting, not --unattended.
t_v8_next_no_unattended_auto_approval() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_not_contains "$content" 'auto (--unattended)' \
		"next/SKILL.md has no auto-approved Approved: variant"
	assert_contains "$content" 'write `Verified:` yourself, in any mode' \
		"next/SKILL.md bans writing Verified: yourself in any mode"
}

# autoApprove setting: the model may write Approved: for the user when it is
# on, but Verified: still needs a human, in every mode.
t_v8_next_autoapprove_setting() {
	local content
	content=$(cat "$NEXT_SKILL")
	assert_contains "$content" 'autoApprove' \
		"next/SKILL.md mentions the autoApprove setting"
	assert_contains "$content" 'Verified:` still needs the human, in every mode' \
		"next/SKILL.md still says Verified: is human-only under autoApprove"
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

# ---------------------------------------------------------------------------
# design.md: USAGE row + shape rule (M20); spec section 3 archived-Ruling lookup (M31)
# ---------------------------------------------------------------------------

DESIGN_REF="$SCAN_DIR/../skills/spec/references/design.md"

t_spec_contract_usage_is_first_row() {
	local first
	first=$(awk '/^## Contract for T007/{f=1;next} f&&NF{print;exit}' "$DESIGN_REF")
	assert_contains "$first" 'USAGE' "design.md: USAGE is the first row of the Contract block"
	assert_contains "$(cat "$DESIGN_REF")" 'RED test' \
		"design.md: the task's RED test starts from the USAGE call"
	assert_contains "$(cat "$DESIGN_REF")" 'change CALLS' \
		"design.md: CALLS follows USAGE when they disagree"
}

t_spec_contract_block_within_25_lines() {
	local n
	n=$(awk '/^## Contract for T007/{f=1} f{c++} f&&/^```$/{print c-1; exit}' "$DESIGN_REF")
	if [ "${n:-99}" -le 25 ]; then
		_pass "design.md: Contract block is $n lines (<= 25)"
	else
		_fail "design.md: Contract block is ${n:-?} lines, over 25"
	fi
}

t_spec_rejected_option_differs_in_shape() {
	local content
	content=$(cat "$DESIGN_REF")
	assert_contains "$content" 'different shape' \
		"design.md: a rejected option must be a different shape"
	assert_contains "$content" 'not a parameter of the chosen one' \
		"design.md: a parameter variant is not a rejected option"
}

t_spec_discovery_cites_archived_rulings() {
	local content cmd d out
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" '.specs/archive/*/NOTES.md' "spec section 3 names the archive NOTES.md glob"
	assert_contains "$content" 'stealth.store' "spec section 3 covers the stealth store"
	cmd=$(printf '%s\n' "$content" | sed -n 's/.*`\(grep -Hn .Ruling:[^`]*\)`.*/\1/p' | head -1)
	assert_contains "$cmd" 'grep -Hn' "spec section 3 gives a runnable grep for Ruling: lines"
	d=$(tmp_dir)
	mkdir -p "$d/.specs/archive/2026-01-01-001-x"
	printf 'Ruling: src/a.ts keeps the retry guard\nRuling: src/b.ts is unrelated\n' \
		> "$d/.specs/archive/2026-01-01-001-x/NOTES.md"
	out=$(cd "$d" && eval "$cmd" | grep 'src/a.ts')
	assert_contains "$out" 'src/a.ts keeps the retry guard' "the documented grep finds the footprint Ruling"
	assert_contains "$out" '.specs/archive/2026-01-01-001-x/NOTES.md:1:' "the documented grep prints the archive path and line even for one archive"
	assert_contains "$content" 'archive path and line' "spec section 3 cites archive path and line"
}

# ---------------------------------------------------------------------------
# mattpocock borrows: vertical slices, slice judging, seams, questionnaire,
# external-contract design, sibling-isolation template
# ---------------------------------------------------------------------------

t_spec_vertical_slice_rule_in_both_drafting_paths() {
	local tpl
	assert_contains "$(cat "$SPEC_SKILL")" 'vertical slice' "spec/SKILL.md tells TASKS.md drafting to cut vertical slices"
	assert_contains "$(cat "$NEXT_SKILL")" 'vertical slice' "next/SKILL.md Drafting tells TASKS.md drafting to cut vertical slices"
	assert_contains "$(cat "$SPEC_SKILL")" 'is its own first task' "spec/SKILL.md makes a prefactor its own first task"
	assert_contains "$(cat "$NEXT_SKILL")" 'one fresh developer context' "next/SKILL.md sizes a task to one fresh context"
	tpl=$(cat "$SCAN_DIR/../flow-templates/TASKS.md")
	assert_not_contains "$tpl" 'untouched' "the TASKS.md template has no layer-only phase"
	assert_contains "$tpl" 'A tag can be added and seen' "the TASKS.md template phase 1 is a vertical slice"
}

t_spec_judges_slices_with_d_slice_only() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$content" 'MODE: issue-breakdown' "spec section 5 runs spec-judge in issue-breakdown mode"
	assert_contains "$content" 'D-Slice' "spec section 5 reads D-Slice"
	assert_contains "$content" 'ignore D-AFK' "spec section 5 ignores D-AFK"
	assert_contains "$content" 'slices: D-Slice X/35' "spec section 5 reports the slice score on the score line"
}

t_spec_test_seam_position_and_template_line() {
	assert_contains "$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")" 'highest available' \
		"question-bank category 8 takes the highest available seam"
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'catches:' \
		"spec.md section 6 carries a seam line with catches:"
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'misses:' \
		"spec.md section 6 carries a seam line with misses:"
}

t_spec_questionnaire_offer_needs_a_non_user_owner() {
	local content
	content=$(cat "$SPEC_SKILL")
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'owner: user|<name/role>' \
		"spec.md Open Questions carry an owner field"
	assert_contains "$content" "owner:\` is not the user" "the questionnaire offer is conditioned on a non-user owner"
	assert_contains "$content" 'references/questionnaire.md' "spec/SKILL.md loads the questionnaire reference"
	assert_contains "$content" 'only on a yes' "the questionnaire is written only on a yes"
	assert_contains "$(cat "$SCAN_DIR/../skills/spec/references/questionnaire.md")" 'icelandic-professor' \
		"the questionnaire reference routes Icelandic through icelandic-professor"
}

t_spec_design_it_twice_for_external_contracts() {
	local content
	content=$(cat "$DESIGN_REF")
	assert_contains "$content" 'external contract' "design.md: the trigger is a decision with outside callers"
	assert_contains "$content" 'model: sonnet' "design.md: the three designers are pinned to sonnet"
	assert_contains "$content" 'fewest entry points' "design.md: constraint 1"
	assert_contains "$content" 'most common caller made trivial' "design.md: constraint 2"
	assert_contains "$content" 'ports and adapters at the seam' "design.md: constraint 3"
}

t_spec_depcruise_template_and_bite_proof() {
	local content tpl
	content=$(cat "$DESIGN_REF")
	tpl=$(cat "$SCAN_DIR/../skills/spec/references/depcruise.template.cjs")
	assert_contains "$content" 'depcruise.template.cjs' "design.md row 4 points at the template"
	assert_contains "$content" 'never overwrite' "design.md: merge into an existing config"
	assert_contains "$content" 'a deliberate violation' "design.md: the confirmation field requires a bite-proof receipt"
	assert_contains "$tpl" '$1' "the template uses the sibling back-reference"
	assert_contains "$tpl" 'never overwrite' "the template header says merge, never overwrite"
	assert_contains "$tpl" 'mattpocock/skills' "the template credits its source"
	if node -e 'require(process.argv[1])' "$SCAN_DIR/../skills/spec/references/depcruise.template.cjs" 2>/dev/null; then
		_pass "the depcruise template loads as CommonJS"
	else
		_fail "the depcruise template loads as CommonJS"
	fi
}

t_spec_prep_not_yet_specified_is_deferred_nongoal() {
	assert_contains "$(cat "$SPEC_SKILL")" \
		'`## Not yet specified` lines go to §2.2 Non-goals as "deferred: <line>", never into scope' \
		"spec/SKILL.md §1 sends PREP.md's Not yet specified lines to §2.2 Non-goals as deferred"
}

t_famousd1_archived_behaviors_join_on_files() {
	local s
	s=$(cat "$SPEC_SKILL")
	assert_contains "$s" 'Behaviors rows' "spec/SKILL.md: archived Behaviors rows are cited"
	assert_contains "$s" 'overlapping the footprint' "spec/SKILL.md: the Behaviors join runs through the task files: overlap"
	assert_contains "$s" 'Keeps <id> from' "spec/SKILL.md: the prior-behavior position has a fixed shape"
	assert_contains "$s" 'legacy `B' "spec/SKILL.md: archived rows may carry legacy B-ids as well as FR-NN"
	assert_contains "$s" 'at most 5' "spec/SKILL.md: prior-behavior positions are capped"
}

t_famousd1_reader_pass_beside_judge() {
	local s
	s=$(cat "$SPEC_SKILL")
	assert_contains "$s" 'cold reader' "spec/SKILL.md §5: a cold-reader subagent is spawned"
	assert_contains "$s" 'at most 8' "spec/SKILL.md §5: the reader returns at most 8 questions"
	assert_contains "$s" 'reader: N asked, N answered, N open' "spec/SKILL.md §5: the score line carries the reader counts"
	assert_contains "$s" 'never run it' "spec/SKILL.md §5: oneshot and bounded never run the reader"
}

t_famousd1_must_never_break_item() {
	local s q
	s=$(cat "$SPEC_SKILL")
	q=$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")
	assert_contains "$s" 'Three items are never dropped' "spec/SKILL.md names three never-dropped items"
	assert_contains "$s" 'must-never-break' "spec/SKILL.md names the must-never-break item"
	assert_contains "$q" 'Must never break:' "question-bank lists the must-never-break position"
	assert_not_contains "$s" 'Behaviors row B1' "spec/SKILL.md does not number the must-never-break row B1"
	assert_not_contains "$q" 'Behaviors row B1' "question-bank does not number the must-never-break row B1"
	assert_contains "$s" 'FR-01' "spec/SKILL.md ties must-never-break to the spec's FR id"
	assert_contains "$s" 'On `dispatch` it is the P0 MUST requirement (FR-01 in spec §4.1)' "spec/SKILL.md: FR-01 anchor is dispatch only"
	assert_contains "$s" 'on `oneshot` it is the first P0 Behaviors row in `TASKS.md`' "spec/SKILL.md: oneshot has no spec to cite"
	assert_contains "$q" 'on `oneshot` it is the first P0 Behaviors row' "question-bank: oneshot has no spec to cite"
	assert_not_contains "$s" 'On `oneshot` and `dispatch` it is the P0' "spec/SKILL.md does not send oneshot to a spec FR"
	assert_not_contains "$q" 'On `oneshot` and `dispatch` it becomes' "question-bank does not send oneshot to a spec FR"
	assert_contains "$s" 'still run the cold reader on its own' "spec/SKILL.md says what the cold reader does without spec-judge"
	assert_contains "$q" 'Budget: 4 items on `bounded`' "question-bank keeps the bounded budget at 4"
}

t_famousd1_no_invented_content() {
	assert_contains "$(cat "$SPEC_SKILL")" 'Never invent content to clear a lint error' \
		"spec/SKILL.md §6 step 2 forbids inventing content for lint or the judge"
}

t_famousd1_revert_grep_install_channel_llm_failures() {
	local s q
	s=$(cat "$SPEC_SKILL")
	q=$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")
	assert_contains "$s" '--grep=revert' "spec/SKILL.md greps the footprint's history for reverts"
	assert_contains "$q" 'install channel' "question-bank row 7 asks for the install channel"
	assert_contains "$q" 'malformed' "question-bank row 5 names malformed model output"
	assert_contains "$q" 'refusal' "question-bank row 5 names refusal"
}

t_famousd1_external_check() {
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'External check:' "spec.md §6 carries an External check line"
	assert_contains "$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")" 'external check' "question-bank row 8 asks for an external check"
}

t_famousd2_spec_or_not_test() {
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'without changing what a caller observes' \
		"spec.md §4.1 carries the spec-or-not test for requirement lines"
}

t_famousd2_screen_states_table() {
	local t
	t=$(cat "$SCAN_DIR/../flow-templates/spec.md")
	assert_contains "$t" '### Screen states' "spec.md §3 has an optional Screen states section"
	assert_contains "$t" '| Screen | Loading | Empty | Error | Success | Partial |' "Screen states table has the five state columns"
	assert_contains "$t" 'delete the section otherwise' "Screen states is conditional on a journey having a screen"
}

# famous-borrows Z4: F94 (blocks: tasks), F98 (discovery is not a task), F112 (Ask first), F04, F93
t_z4_spec_template_blocks_marker() {
	assert_contains "$(cat "$SCAN_DIR/../flow-templates/spec.md")" 'blocks: tasks]' \
		"spec.md §8 shows the optional blocks: tasks marker"
}

t_z4_spec_template_ask_first_section() {
	local t
	t=$(cat "$SCAN_DIR/../flow-templates/spec.md")
	assert_contains "$t" '### 2.3 Ask first' "spec.md carries the Ask first tier"
	assert_contains "$t" 'new runtime dependency' "default bullet: new runtime dependency"
	assert_contains "$t" 'CI/workflow config' "default bullet: CI/workflow config"
	assert_contains "$t" 'schema migration' "default bullet: schema migration"
}

t_z4_execution_prompt_ask_first_row() {
	assert_contains "$(cat "$SCAN_DIR/../skills/next/execution-prompt.md")" 'Ask-first' \
		"the failure table stops on an Ask-first item"
	assert_contains "$(cat "$SCAN_DIR/../skills/next/execution-prompt.md")" 'report BLOCKED naming it' \
		"and reports BLOCKED naming it"
}

t_z4_question_bank_observed_or_assumed() {
	assert_contains "$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")" 'observed:' \
		"a position about current code cites observed: path:line or says assumed"
	assert_contains "$(cat "$SCAN_DIR/../skills/spec/references/question-bank.md")" 'assumed' \
		"question-bank names the assumed marker"
}

t_z4_next_drafting_rules() {
	local n
	n=$(cat "$NEXT_SKILL")
	assert_contains "$n" 'Discovery happens while drafting, never as a task' "F98: discovery is not a task"
	assert_contains "$n" 'read `spec.md` §8 first' "F94: drafting reads the open questions first"
	assert_contains "$n" 'baseline-tests.txt' "F04: T000 writes the Test: baseline"
	assert_contains "$n" 'git worktree add --detach' "F04: a red at Base needs a baseline or a Base rerun"
	assert_contains "$n" 'is `unverified`' "F04: an unproven red at Base is unverified"
	assert_contains "$n" 'spec-criterion-changed' "F93: gating names the rule"
}

t_z4_review_cross_file_diffs_the_contract() {
	assert_contains "$(cat "$SCAN_DIR/../skills/next/review.md")" 'diffs `spec.md` and `design.md` against Base' \
		"F93: the cross-file lens diffs the contract files against Base"
}

t_z4_fix_skill_red_needs_baseline() {
	assert_contains "$(cat "$SCAN_DIR/../skills/fix/SKILL.md")" 'git worktree add --detach' \
		"F04: fix calls a red pre-existing only with a Base rerun"
}

t_famousd2_split_position_in_discovery() {
	assert_contains "$(cat "$SPEC_SKILL")" "split: <A> / <B>" \
		"spec/SKILL.md discovery carries the split position"
	assert_contains "$(cat "$SPEC_SKILL")" "one feature because <reason>" \
		"spec/SKILL.md discovery lets the split position resolve to one feature"
}
