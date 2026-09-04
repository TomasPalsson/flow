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
  assert_contains "$OUT" "flow branch mismatch" "branch mismatch: note printed"
  assert_not_contains "$OUT" "worktree mismatch" "branch mismatch: no worktree note"
}

t_ctx_extra_no_flow_json_no_note() {
  d=$(tmp_repo)
  run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-none"}' CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "no flow.json: rc 0"
  assert_not_contains "$OUT" "mismatch" "no flow.json: no mismatch note"
}

# C23: session-context.sh appends the `harness next` line via the sibling CLI
# at $HERE/../bin/harness (present in this repo layout — hooks/ and bin/
# are siblings under the plugin root). A clean tmp_repo with no PROGRESS.md
# or .claude/flow.json is the CLI's "no flow, clean tree" default line.
t_ctx_extra_harness_next_line_appended() {
  d=$(tmp_repo)
  run_hook "$SCAN_DIR/session-context.sh" '{"session_id":"ctx-next"}' CLAUDE_PROJECT_DIR="$d"
  assert_rc 0 "harness next line: rc 0"
  assert_contains "$OUT" "Next: /flow <feature> for a feature, or just ask for a one-sentence change" "harness next line: printed"
}
