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
# correctness/gaming in both the initial review and the fix-ladder relook,
# and implementPrompt names the search receipt and slop-check.
# ---------------------------------------------------------------------------

t_slopseam_build_slices_slop_lens_in_both_arrays() {
	run_cmd grep -c "adversaryPrompt('slop'" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js calls adversaryPrompt('slop', ...)"
	assert_eq "$OUT" "2" "wf: adversaryPrompt('slop', ...) appears once per parallel array (initial + relook)"
}

t_slopseam_build_slices_slop_label_format() {
	run_cmd grep -c "'adv:slop:'" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js labels the slop lens 'adv:slop:'"
	assert_eq "$OUT" "2" "wf: 'adv:slop:' label appears once per parallel array (initial + relook)"
}

t_slopseam_build_slices_implement_prompt_names_receipt_and_slopcheck() {
	run_cmd grep -c "const implementPrompt" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js still declares implementPrompt"
	local block
	block=$(sed -n '/const implementPrompt/,/agent(implementPrompt/p' "$WF_DIR/build-slices.js")
	assert_contains "$block" "receipt" "wf: implementPrompt names the search receipt"
	assert_contains "$block" "slop-check" "wf: implementPrompt names slop-check"
}

t_slopseam_build_slices_still_lints_ok() {
	run_cmd bash "$SCAN_DIR/workflow-lint" "$WF_DIR/build-slices.js"
	assert_rc 0 "wf: build-slices.js with the slop lens still lints clean"
	assert_contains "$OUT" "OK " "wf: build-slices.js with the slop lens prints OK"
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
