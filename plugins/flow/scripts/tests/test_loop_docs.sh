#!/usr/bin/env bash
# test_loop_docs.sh — Slice 3 (spec .specs/006-loop-engineering/spec.md) tests
# that the prose deliverables document exactly what the shipped `flow loop`
# CLI prints and stay in sync with it: docs/reference/workflows-and-cli.md,
# docs/reference/hooks.md, the fix skill's /flow:loop path, and the README
# layout tree.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on test_cli.sh's CLI_PATH having been
# sourced in the same run — it defines its own equivalent below.
set -u

LD_CLI_PATH=""
LD_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
LD_CLI_PATH="$LD_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && LD_CLI_PATH="$SCAN_DIR/../bin/flow"

LD_REPO_ROOT=$(cd "$SCAN_DIR/../../.." && pwd -P)
LD_CLI_DOC="$LD_REPO_ROOT/docs/reference/workflows-and-cli.md"
LD_HOOKS_DOC="$LD_REPO_ROOT/docs/reference/hooks.md"
LD_FIX_SKILL="$LD_REPO_ROOT/plugins/flow/skills/fix/SKILL.md"
LD_FIX_PROMPT="$LD_REPO_ROOT/plugins/flow/skills/fix/execution-prompt.md"
LD_README="$LD_REPO_ROOT/plugins/flow/README.md"
LD_LOOP_SKILL="$LD_REPO_ROOT/plugins/flow/skills/loop/SKILL.md"

# _ld_help <args...> → the CLI's --help output for those args, ANSI stripped
# (the CLI always colours output; the docs are plain text, so a doc-drift
# test must strip colour the same way a human transcribing the output would).
_ld_help() {
	node "$LD_CLI_PATH" "$@" --help | sed $'s/\x1b\\[[0-9;]*m//g'
}

# ---------------------------------------------------------------------------
# workflows-and-cli.md documents exactly what the CLI prints (doc-drift guard)
# ---------------------------------------------------------------------------

t_loopdocs_top_help_verbatim_in_cli_doc() {
	local real doc
	real=$(_ld_help)
	doc=$(cat "$LD_CLI_DOC")
	assert_contains "$doc" "$real" "workflows-and-cli.md contains flow --help verbatim"
}

t_loopdocs_loop_help_verbatim_in_cli_doc() {
	local real doc
	real=$(_ld_help loop)
	doc=$(cat "$LD_CLI_DOC")
	assert_contains "$doc" "$real" "workflows-and-cli.md contains flow loop --help verbatim"
}

t_loopdocs_loop_subcommand_help_verbatim_in_cli_doc() {
	local sub real doc
	doc=$(cat "$LD_CLI_DOC")
	for sub in init check tick run status stop log; do
		real=$(_ld_help loop "$sub")
		assert_contains "$doc" "$real" "workflows-and-cli.md contains flow loop $sub --help verbatim"
	done
}

t_loopdocs_cli_doc_has_flow_loop_section() {
	assert_contains "$(cat "$LD_CLI_DOC")" "## flow loop" \
		"workflows-and-cli.md has a flow loop section"
}

# ---------------------------------------------------------------------------
# hooks.md documents loop-gate.sh
# ---------------------------------------------------------------------------

t_loopdocs_hooks_doc_has_loop_gate_row() {
	local doc
	doc=$(cat "$LD_HOOKS_DOC")
	assert_contains "$doc" "## loop-gate.sh" "hooks.md has a loop-gate.sh row"
	assert_contains "$doc" "Stop hook" "hooks.md's loop-gate.sh row names the Stop event"
}

# ---------------------------------------------------------------------------
# fix skill: ralph-loop path replaced by /flow:loop; fallback path kept
# ---------------------------------------------------------------------------

t_loopdocs_fix_skill_drops_ralph_loop() {
	local doc
	doc=$(cat "$LD_FIX_SKILL")
	assert_not_contains "$doc" "ralph-loop" "fix/SKILL.md no longer mentions ralph-loop"
	assert_not_contains "$doc" "ralph-wiggum" "fix/SKILL.md no longer mentions ralph-wiggum"
}

t_loopdocs_fix_skill_uses_flow_loop() {
	local doc
	doc=$(cat "$LD_FIX_SKILL")
	assert_contains "$doc" "/flow:loop" "fix/SKILL.md names /flow:loop"
	assert_contains "$doc" "flow loop init" "fix/SKILL.md shows arming the loop"
	assert_contains "$doc" "flow loop run" "fix/SKILL.md shows starting the fresh driver"
}

t_loopdocs_fix_skill_keeps_fallback_path() {
	assert_contains "$(cat "$LD_FIX_SKILL")" "Direct execution above is the default" \
		"fix/SKILL.md keeps a direct (no-loop) execution path"
}

t_loopdocs_fix_execution_prompt_drops_promise() {
	local doc
	doc=$(cat "$LD_FIX_PROMPT")
	assert_not_contains "$doc" "<promise>" "execution-prompt.md no longer emits a <promise> tag"
	assert_not_contains "$doc" "ralph-loop" "execution-prompt.md no longer mentions ralph-loop"
}

t_loopdocs_fix_execution_prompt_names_blocked_md() {
	assert_contains "$(cat "$LD_FIX_PROMPT")" "BLOCKED.md" \
		"execution-prompt.md names the honest-exit BLOCKED.md path"
}

# ---------------------------------------------------------------------------
# README.md layout tree lists the loop files
# ---------------------------------------------------------------------------

t_loopdocs_readme_layout_lists_loop_skill() {
	assert_contains "$(cat "$LD_README")" "fix, loop, no-slop," \
		"README.md layout lists the loop skill"
}

t_loopdocs_readme_layout_lists_loop_bin() {
	assert_contains "$(cat "$LD_README")" "bin/lib/loop/ (contract, tick, verify, tamper, CLI)" \
		"README.md layout lists bin/lib/loop/"
}

# ---------------------------------------------------------------------------
# Step 0 tells the operator what --yolo bootstraps, refuses, and arms
# (B8, FR-03, FR-06, FR-08, FR-10, FR-13; .specs/010-autonomous-loop-on-ramp-yolo)
# ---------------------------------------------------------------------------

t_loop_docs_yolo() {
	local doc
	doc=$(cat "$LD_LOOP_SKILL")
	assert_contains "$doc" "## Step 0" "SKILL.md has a Step 0 section"
	assert_contains "$doc" "--yolo" "Step 0 names the --yolo flag"
	assert_contains "$doc" "no question asked" "Step 0 states zero questions are asked (FR-03)"
	assert_contains "$doc" "unproven" "Step 0 states every task item starts unproven (FR-06)"
	assert_contains "$doc" "own working copy" "Step 0 states the run uses its own branch and working copy (FR-08)"
	assert_contains "$doc" "draft pull request" "Step 0 names the draft pull request outcome (FR-10)"
	assert_contains "$doc" "scoped to the files" "Step 0 states the verifier is scoped to touched files (FR-13)"
	assert_contains "$doc" "240 minutes" "Step 0 states the --yolo minutes cap"
	assert_contains "$doc" "40 iterations" "Step 0 states the --yolo iterations cap"
	assert_contains "$doc" "no money cap" "Step 0 states --yolo sets no money cap"
	assert_contains "$doc" "stops the run" "Step 0 states a tamper finding stops the run"
}
