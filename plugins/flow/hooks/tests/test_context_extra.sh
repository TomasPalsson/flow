#!/usr/bin/env bash
# Worktree/branch mismatch notes in session-context.sh (agent view starts in the main checkout).

t_ctx_extra_flow_worktree_mismatch_note() {
	d=$(tmp_repo)
	mkdir -p "$d/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"flow/x","worktree":"/elsewhere/code-worktrees/flow/x"}\n' >"$d/.claude/flow.json"
	run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-wt"}' CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "worktree mismatch: rc 0"
	assert_contains "$OUT" "flow worktree mismatch" "worktree mismatch: note printed"
	assert_contains "$OUT" "/elsewhere/code-worktrees/flow/x" "worktree mismatch: names the worktree"
}

t_ctx_extra_flow_branch_mismatch_note() {
	d=$(tmp_repo)
	mkdir -p "$d/.claude"
	printf '{"number":"001","slug":"x","spec_dir":".specs/001-x","branch":"flow/x","worktree":null}\n' >"$d/.claude/flow.json"
	run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-br"}' CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "branch mismatch: rc 0"
	# Spec 003 B14 wording (G6): the note states the fact and ends in a runnable
	# command; the old "flow branch mismatch" label is gone. Read the fixture's
	# own current branch so the assertion does not depend on init.defaultBranch.
	cur=$(git -C "$d" rev-parse --abbrev-ref HEAD)
	assert_contains "$OUT" "note: this checkout is on $cur; .claude/flow.json says flow/x — run: git checkout flow/x" "branch mismatch: note printed"
	assert_not_contains "$OUT" "worktree mismatch" "branch mismatch: no worktree note"
}

t_ctx_extra_no_flow_json_no_note() {
	d=$(tmp_repo)
	run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-none"}' CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "no flow.json: rc 0"
	assert_not_contains "$OUT" "mismatch" "no flow.json: no mismatch note"
}

# C23: session-context.sh appends the `flow next` line via the sibling CLI
# at $HERE/../bin/flow (present in this repo layout — hooks/ and bin/
# are siblings under the plugin root). A clean tmp_repo with no PROGRESS.md
# or .claude/flow.json is the CLI's "no flow, clean tree" default line.
#
# Spec 003 C-D/G6: `next` is ALWAYS a runnable command or slash command,
# never prose, and the Next: line comes FIRST in the block. The old prose
# line "Next: /flow <feature> for a feature, or just ask ..." violated both,
# so the prose moved to the Why: line and Next: is the bare slash command.
t_ctx_extra_harness_next_line_appended() {
	d=$(tmp_repo)
	run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-next"}' CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "flow next line: rc 0"
	first=$(printf '%s\n' "$OUT" | head -1)
	assert_eq "$first" "Next: /flow" "flow next line: printed"
	assert_contains "$OUT" "Why: clean tree, no flow in progress" "flow next line: why printed"
}
