#!/usr/bin/env bash
# test_no_slop_seams.sh — Slice 2: developer briefs carry the no-slop
# developer block, and the slop lens runs per task in build-slices.js.
# (B6 to B8). t_slopseam_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

TASK_BRIEF="$SCAN_DIR/task-brief"
DEV_BLOCK="$SCAN_DIR/../skills/no-slop/references/developer-block.md"
WF_DIR="$SCAN_DIR/../workflows"
EXEC_PROMPT="$SCAN_DIR/../skills/next/execution-prompt.md"
FIX="$HERE/fixtures"

# fenced_block_of <file> — the first ```...``` fenced block, fence lines
# included, exactly as task-brief must copy it.
fenced_block_of() {
	awk '
    /^```/ { infence = !infence; print; if (!infence) exit; next }
    infence { print }
  ' "$1"
}

# ---------------------------------------------------------------------------
# B6 — task-brief appends the "## Before you write" heading plus the
# no-slop developer block's fenced instructions verbatim, after the task
# section and before any design contract.
# ---------------------------------------------------------------------------

t_slopseam_brief_appends_before_you_write_heading() {
	local d out
	d=$(tmp_dir)
	out="$d/brief.md"
	run_cmd bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --out "$out"
	assert_rc 0 "task-brief exits 0"
	assert_contains "$(cat "$out")" "## Before you write" "task-brief output has the Before you write heading"
}

t_slopseam_brief_appends_developer_block_verbatim() {
	local d out block
	d=$(tmp_dir)
	out="$d/brief.md"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --out "$out" >/dev/null
	block=$(fenced_block_of "$DEV_BLOCK")
	case "$(cat "$out")" in
	*"$block"*) _pass "task-brief output contains the developer-block.md fenced block verbatim" ;;
	*) _fail "task-brief output contains the developer-block.md fenced block verbatim" "block missing from $out" ;;
	esac
}

t_slopseam_brief_places_block_before_design_contract() {
	local d design out before_pos after_pos content
	d=$(tmp_dir)
	design="$d/design.md"
	cat >"$design" <<'EOF'
## Contract — T002
some contract text
EOF
	out="$d/brief.md"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --design "$design" --out "$out" >/dev/null
	content=$(cat "$out")
	assert_contains "$content" "some contract text" "task-brief output still carries the design contract"
	before_pos=$(printf '%s' "$content" | grep -n "## Before you write" | head -1 | cut -d: -f1)
	after_pos=$(printf '%s' "$content" | grep -n "some contract text" | head -1 | cut -d: -f1)
	if [ -n "$before_pos" ] && [ -n "$after_pos" ] && [ "$before_pos" -lt "$after_pos" ]; then
		_pass "developer block appears before the design contract"
	else
		_fail "developer block appears before the design contract" "before_pos=$before_pos after_pos=$after_pos"
	fi
}

# ---------------------------------------------------------------------------
# B7 — build-slices.js runs a third adversary lens, 'slop', alongside
# correctness/gaming in the initial review. Since F51 the fix-ladder relook is
# one scoped re-review (not a three-lens parallel array) whose prompt names all
# three lenses, and implementPrompt names the search receipt and slop-check.
# ---------------------------------------------------------------------------

# Since the parent/child split, the per-task chain (lenses, relook, implement prompt) lives in
# the child workflow build-slices-task.js, so the assertions below read that file.
# Changed with F51 (the post-fix relook is one scoped re-review): the slop
# lens now appears once, in the initial review array, not once per array.
t_slopseam_build_slices_each_lens_once_in_initial_review() {
	run_cmd grep -c "adversaryPrompt('slop'" "$WF_DIR/build-slices-task.js"
	assert_rc 0 "wf: build-slices-task.js calls adversaryPrompt('slop', ...)"
	assert_eq "$OUT" "1" "wf: adversaryPrompt('slop', ...) appears once, in the initial review array"
	run_cmd grep -c "adversaryPrompt('correctness'" "$WF_DIR/build-slices-task.js"
	assert_eq "$OUT" "1" "wf: adversaryPrompt('correctness', ...) appears once, in the initial review array"
	run_cmd grep -c "adversaryPrompt('gaming'" "$WF_DIR/build-slices-task.js"
	assert_eq "$OUT" "1" "wf: adversaryPrompt('gaming', ...) appears once, in the initial review array"
}

# Changed with F51: one label per lens in the initial review; the relook carries
# its own 'relook:' label instead of a second adv:slop: entry.
t_slopseam_build_slices_slop_label_format() {
	run_cmd grep -c "'adv:slop:'" "$WF_DIR/build-slices-task.js"
	assert_rc 0 "wf: build-slices-task.js labels the slop lens 'adv:slop:'"
	assert_eq "$OUT" "1" "wf: 'adv:slop:' label appears once, in the initial review array"
	run_cmd grep -c "'adv:correctness:'" "$WF_DIR/build-slices-task.js"
	assert_eq "$OUT" "1" "wf: 'adv:correctness:' label appears once, in the initial review array"
	run_cmd grep -c "'adv:gaming:'" "$WF_DIR/build-slices-task.js"
	assert_eq "$OUT" "1" "wf: 'adv:gaming:' label appears once, in the initial review array"
	run_cmd grep -c "'relook:'" "$WF_DIR/build-slices-task.js"
	assert_eq "$OUT" "1" "wf: the scoped relook has its own 'relook:' label"
}

# Added with F51: the scoped relook checks the fix diff through all three lenses.
# The sentence lives in workflows/prompts/build-slices-relook.md.
t_slopseam_build_slices_relook_names_all_three_lenses() {
	local relook
	relook=$(cat "$WF_DIR/prompts/build-slices-relook.md")
	assert_contains "$(cat "$WF_DIR/build-slices-task.js")" "promptRef('relook')" "wf: the relook prompt points at its prompt file"
	assert_contains "$relook" "all three lenses" "wf: the scoped relook is told to check through all three lenses"
	assert_contains "$relook" "correctness" "wf: the scoped relook names the correctness lens"
	assert_contains "$relook" "gaming" "wf: the scoped relook names the gaming lens"
	assert_contains "$relook" "slop" "wf: the scoped relook names the slop lens"
}

# Changed with F51 (implementPrompt is now a let, so a gap block can be appended)
# and with the prompt-file move: the prose sits in
# workflows/prompts/build-slices-implement.md, so the receipt and slop-check
# assertions read that file; the JS must still declare implementPrompt (let or
# const) from promptRef('implement') and hand it to the developer agent.
t_slopseam_build_slices_implement_prompt_names_receipt_and_slopcheck() {
	run_cmd grep -cE "(let|const) implementPrompt" "$WF_DIR/build-slices-task.js"
	assert_rc 0 "wf: build-slices-task.js still declares implementPrompt"
	local block prose
	block=$(sed -n '/implementPrompt = promptRef/,/agent(implementPrompt/p' "$WF_DIR/build-slices-task.js")
	assert_contains "$block" "promptRef('implement')" "wf: implementPrompt points at the implement prompt file"
	prose=$(cat "$WF_DIR/prompts/build-slices-implement.md")
	assert_contains "$prose" "receipt" "wf: the implement prompt file names the search receipt"
	assert_contains "$prose" "slop-check" "wf: the implement prompt file names slop-check"
}

# The slop lens runs in the child, so the parent and the child are both linted.
t_slopseam_build_slices_still_lints_ok() {
	run_cmd bash "$SCAN_DIR/workflow-lint" "$WF_DIR/build-slices.js" "$WF_DIR/build-slices-task.js"
	assert_rc 0 "wf: build-slices.js and build-slices-task.js with the slop lens still lint clean"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c '^OK ')" "2" "wf: build-slices.js and build-slices-task.js with the slop lens print OK"
}

# The seams table describes the F51 structure: three lenses once, then a scoped re-look naming all three.
t_slopseam_integration_seams_describe_f51_review() {
	local row
	row=$(grep '^| Per-slice review |' "$SCAN_DIR/../skills/no-slop/references/integration-seams.md")
	assert_contains "$row" "build-slices-task.js" "seams: the per-task review row names the child workflow that holds it"
	assert_contains "$row" "the initial review is one \`parallel([...])\` of three lenses, correctness, gaming and slop" "seams: the initial review runs the three lenses once"
	assert_contains "$row" "after each fix round one scoped re-look" "seams: the fix ladder re-looks once per round, scoped to that round"
	assert_contains "$row" "names all three lenses" "seams: the scoped re-look names all three lenses"
	assert_not_contains "$row" "both \`parallel([...])\` review arrays" "seams: the pre-F51 two-array wording is gone"
}

# ---------------------------------------------------------------------------
# B8 — execution-prompt.md: GREEN gains the search-receipt sentence,
# REFACTOR gains the slop-check run.
# ---------------------------------------------------------------------------

# section_of <file> <heading> — lines from "### <heading>" up to (not
# including) the next "### " heading.
section_of() {
	awk -v h="### $2" '
    $0 == h { capturing = 1; next }
    capturing && /^### / { exit }
    capturing { print }
  ' "$1"
}

t_slopseam_execution_prompt_green_receipt_sentence() {
	local section
	section=$(section_of "$EXEC_PROMPT" "GREEN")
	assert_contains "$section" "receipt" "execution-prompt.md GREEN names the search receipt"
}

t_slopseam_execution_prompt_refactor_slopcheck_run() {
	local section
	section=$(section_of "$EXEC_PROMPT" "REFACTOR")
	assert_contains "$section" "slop-check" "execution-prompt.md REFACTOR names the slop-check run"
}

# O5 — the brief carries the RED rule and an absolute slop-check path.
t_slopseam_brief_has_a_tests_section_with_the_red_rule() {
	local d out
	d=$(tmp_dir)
	out="$d/brief.md"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --out "$out" >/dev/null
	assert_contains "$(cat "$out")" "## Tests" "task-brief output has a Tests section"
	assert_contains "$(cat "$out")" "ONE assertion per item" "the Tests section states one assertion per boundary case"
	assert_contains "$(cat "$out")" "> for >=" "the Tests section names the wrong implementations to catch"
}

t_slopseam_brief_names_slop_check_by_absolute_path() {
	local d out line
	d=$(tmp_dir)
	out="$d/brief.md"
	bash "$TASK_BRIEF" "$FIX/tasks-good.md" T002 --out "$out" >/dev/null
	line=$(grep -- '--base' "$out" | grep 'slop-check' | tail -1)
	case "$line" in
	/*/skills/no-slop/scripts/slop-check\ --base\ *) _pass "slop-check command is absolute" ;;
	*) _fail "slop-check command is absolute" "got: $line" ;;
	esac
	if [ -x "${line%% --base*}" ]; then
		_pass "the named slop-check exists and is executable"
	else
		_fail "the named slop-check exists and is executable" "$line"
	fi
}
