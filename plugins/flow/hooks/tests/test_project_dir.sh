#!/usr/bin/env bash
# test_project_dir.sh — hook_project_dir() must resolve the project from the
# repo that owns the edited file (tool_input.file_path, then cwd), not from
# the session's start directory — a Claude Code session started in checkout A
# that edits files inside git worktree B must have every hook read B's
# .claude/ state, not A's.
set -u

# _spec_scripts_dir / _spec_write_plan / _spec_write_approved_plan are shared
# helpers from test_spec_gate.sh (same run.sh, same test process); reuse them
# rather than duplicating the plan-writing pattern.

# _pd_scripts_dir / _pd_write_approved_plan — self-contained copies of the
# plan-writing pattern in test_spec_gate.sh's _spec_scripts_dir /
# _spec_write_plan / _spec_write_approved_plan, so this file passes on its
# own under TEST_ONLY=test_project_dir.sh (test_spec_gate.sh is not sourced
# in that run) as well as inside the full suite.
_pd_scripts_dir() {
	(cd "$SCAN_DIR/../scripts" && pwd -P)
}

_pd_write_approved_plan() {
	mkdir -p "$(dirname "$1")"
	cat >"$1" <<'PLANEOF'
Approved: 2026-09-05 by user

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing works | Slice 1 | `test_thing` |

## Slice 1 — Thing

- **Files**: src/a.ts

### Slice 1 — RED

Write a failing test.

### Slice 1 — GREEN

Make it pass.

### Slice 1 — REFACTOR

Clean up.

## Gate Phases

1. Run tests.
PLANEOF
}

# A throwaway hook that prints hook_project_dir's output.
_pd_probe_script() {
	local d=$1
	cat >"$d/probe-pd.sh" <<SH
#!/usr/bin/env bash
. "$SCAN_DIR/lib/hookout.sh"
printf '%s' "\$(hook_project_dir)"
SH
	printf '%s' "$d/probe-pd.sh"
}

t_project_dir_prefers_the_edited_files_repo() {
	local scriptdir a b s json expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	b=$(tmp_repo)
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","cwd":"%s","tool_input":{"file_path":"%s/src/new/file.sh"}}' "$a" "$b")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	expected=$(cd "$b" && pwd -P)
	assert_rc 0 "prefers-edited-repo: rc 0"
	assert_eq "$OUT" "$expected" "prefers-edited-repo: resolves to B, not A (session start dir)"
	rm -rf "$scriptdir" "$a" "$b"
}

t_project_dir_uses_cwd_for_bash() {
	local scriptdir b s json expected subdir
	scriptdir=$(tmp_dir)
	b=$(tmp_repo)
	subdir="$b/sub/dir"
	mkdir -p "$subdir"
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","cwd":"%s"}' "$subdir")
	run_hook "$s" "$json"
	expected=$(cd "$b" && pwd -P)
	assert_rc 0 "uses-cwd-for-bash: rc 0"
	assert_eq "$OUT" "$expected" "uses-cwd-for-bash: resolves to B via cwd (no tool_input)"
	rm -rf "$scriptdir" "$b"
}

t_project_dir_falls_back_to_session_dir() {
	local scriptdir a nongit s json errf expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	nongit=$(tmp_dir)
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/x.sh"}}' "$nongit")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	assert_rc 0 "falls-back-to-session-dir: rc 0 (non-git file_path)"
	assert_eq "$OUT" "$a" "falls-back-to-session-dir: non-git file_path falls back to CLAUDE_PROJECT_DIR"

	# No cwd field, no CLAUDE_PROJECT_DIR: must fall back to the hook process's
	# own $PWD — run it with the working directory pinned to scriptdir so the
	# assertion is meaningful (run_hook alone would inherit this test's cwd).
	expected=$(cd "$scriptdir" && pwd -P)
	errf=$(mktemp "${TMPDIR:-/tmp}/flow-err.XXXXXX")
	OUT=$(cd "$scriptdir" && printf '{"session_id":"s"}' | bash "$s" 2>"$errf")
	RC=$?
	ERR=$(cat "$errf")
	rm -f "$errf"
	assert_rc 0 "falls-back-to-session-dir: rc 0 (no cwd, no CLAUDE_PROJECT_DIR)"
	assert_eq "$OUT" "$expected" "falls-back-to-session-dir: no cwd/CLAUDE_PROJECT_DIR falls back to hook's \$PWD"
	rm -rf "$scriptdir" "$a" "$nongit"
}

t_spec_gate_reads_the_plan_from_the_files_repo() {
	local a b scripts json
	a=$(tmp_repo)
	b=$(tmp_repo)
	scripts=$(_pd_scripts_dir)

	# B: requireSpec true, approved lint-clean plan; A: requireSpec true, no plan.
	mkdir -p "$a/.claude" "$b/.claude" "$b/src"
	printf '{"requireSpec": true}\n' >"$a/.claude/flow.config.json"
	printf '{"requireSpec": true}\n' >"$b/.claude/flow.config.json"
	_pd_write_approved_plan "$b/.claude/feature-plan.local.md"
	printf 'export const a = 1;\n' >"$b/src/a.ts"
	git -C "$b" add "$b/src/a.ts" >/dev/null 2>&1

	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/src/a.ts"}}' "$b")
	run_hook "$SCAN_DIR/spec-gate.sh" "$json" CLAUDE_PROJECT_DIR="$a" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "spec-gate-reads-files-repo: rc 0 (B has approved plan)"
	assert_not_contains "$OUT" '"deny"' "spec-gate-reads-files-repo: B's approved plan allows the edit, A's missing plan is not consulted"

	# Inverse: A has the approved plan, B has none.
	_pd_write_approved_plan "$a/.claude/feature-plan.local.md"
	rm -f "$b/.claude/feature-plan.local.md"

	run_hook "$SCAN_DIR/spec-gate.sh" "$json" CLAUDE_PROJECT_DIR="$a" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "spec-gate-reads-files-repo inverse: rc 0"
	assert_contains "$OUT" '"deny"' "spec-gate-reads-files-repo inverse: B has no plan, A's plan is not consulted"

	rm -rf "$a" "$b"
}
