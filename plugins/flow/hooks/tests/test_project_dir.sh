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

# _pd_scripts_dir / _pd_approved_tasks — self-contained copies of the
# plan-writing pattern in test_spec_gate.sh's _spec_scripts_dir /
# _spec_approved_tasks, so this file passes on its
# own under TEST_ONLY=test_project_dir.sh (test_spec_gate.sh is not sourced
# in that run) as well as inside the full suite.
_pd_scripts_dir() {
	(cd "$SCAN_DIR/../scripts" && pwd -P)
}

# _pd_approved_tasks <repo> — the active feature the way spec 004 shapes it:
# .specs/001-x/TASKS.md (approved, lint-clean) plus .specs/.current.
_pd_approved_tasks() {
	local repo=$1 base
	base=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)
	mkdir -p "$repo/.specs/001-x"
	cat >"$repo/.specs/001-x/TASKS.md" <<EOF
# Tasks — X
Spec: spec.md · Design: none · Base: $base · Route: oneshot · Test: \`true\`
Approved: 2026-01-01 by user

## Phase 1 — Thing
Goal: the thing works.
Independent test: \`true\`
- [ ] T001 do the thing — files: src/a.ts — verify: \`true\`
EOF
	printf '001-x\n' >"$repo/.specs/.current"
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
	b=$(tmp_dir)
	rm -rf "$b"
	git -C "$a" worktree add "$b" -b wt-prefers >/dev/null 2>&1
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","cwd":"%s","tool_input":{"file_path":"%s/src/new/file.sh"}}' "$a" "$b")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	expected=$(cd "$b" && pwd -P)
	assert_rc 0 "prefers-edited-repo: rc 0"
	assert_eq "$OUT" "$expected" "prefers-edited-repo: resolves to B's worktree, not A (session start dir)"
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
	local scriptdir a nongit s json expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	nongit=$(tmp_dir)
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/x.sh"}}' "$nongit")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	assert_rc 0 "falls-back-to-session-dir: rc 0 (non-git file_path)"
	assert_eq "$OUT" "$(cd "$a" && pwd -P)" "falls-back-to-session-dir: non-git file_path falls back to CLAUDE_PROJECT_DIR"

	# No cwd field, no CLAUDE_PROJECT_DIR: must fall back to the hook process's
	# own $PWD — run it with the working directory pinned to scriptdir so the
	# assertion is meaningful (run_hook alone would inherit this test's cwd).
	expected=$(cd "$scriptdir" && pwd -P)
	run_cmd bash -c 'cd "$1" && printf "{\"session_id\":\"s\"}" | bash "$2"' _ "$scriptdir" "$s"
	assert_rc 0 "falls-back-to-session-dir: rc 0 (no cwd, no CLAUDE_PROJECT_DIR)"
	assert_eq "$OUT" "$expected" "falls-back-to-session-dir: no cwd/CLAUDE_PROJECT_DIR falls back to hook's \$PWD"
	rm -rf "$scriptdir" "$a" "$nongit"
}

t_spec_gate_reads_the_plan_from_the_files_repo() {
	local a b scripts json
	a=$(tmp_repo)
	b=$(tmp_dir)
	rm -rf "$b"
	git -C "$a" worktree add "$b" -b wt-spec >/dev/null 2>&1
	scripts=$(_pd_scripts_dir)

	# B: requireSpec true, approved lint-clean plan; A: requireSpec true, no plan.
	mkdir -p "$a/.claude" "$b/.claude" "$b/src"
	printf '{"requireSpec": true}\n' >"$a/.claude/flow.config.json"
	printf '{"requireSpec": true}\n' >"$b/.claude/flow.config.json"
	_pd_approved_tasks "$b"
	printf 'export const a = 1;\n' >"$b/src/a.ts"
	git -C "$b" add "$b/src/a.ts" >/dev/null 2>&1

	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/src/a.ts"}}' "$b")
	run_hook "$SCAN_DIR/spec-gate.sh" "$json" CLAUDE_PROJECT_DIR="$a" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "spec-gate-reads-files-repo: rc 0 (B has approved plan)"
	assert_not_contains "$OUT" '"deny"' "spec-gate-reads-files-repo: B's approved plan allows the edit, A's missing plan is not consulted"

	# Inverse: A has the approved plan, B has none.
	_pd_approved_tasks "$a"
	rm -rf "$b/.specs"

	run_hook "$SCAN_DIR/spec-gate.sh" "$json" CLAUDE_PROJECT_DIR="$a" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "spec-gate-reads-files-repo inverse: rc 0"
	assert_contains "$OUT" '"deny"' "spec-gate-reads-files-repo inverse: B has no plan, A's plan is not consulted"

	rm -rf "$a" "$b"
}

# A nested git repo inside the project (e.g. a scratch checkout under the
# tree) must never make hook_project_dir report the nested repo's toplevel:
# the fast base-prefix path wins before any git lookup runs.
t_project_dir_nested_repo_inside_project_stays_project() {
	local scriptdir a scripts s json expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	scripts=$(_pd_scripts_dir)
	mkdir -p "$a/.claude" "$a/scratch/src"
	printf '{"requireSpec": true}\n' >"$a/.claude/flow.config.json"
	(
		cd "$a/scratch" || exit 1
		git init -q
		git config user.email "test@example.com"
		git config user.name "harness-test"
		git config commit.gpgsign false
	) >/dev/null 2>&1

	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/scratch/src/x.ts"}}' "$a")
	run_hook "$SCAN_DIR/spec-gate.sh" "$json" CLAUDE_PROJECT_DIR="$a" CC_SCRIPTS_DIR="$scripts"
	assert_rc 0 "nested-repo-inside-project: spec-gate rc 0"
	assert_contains "$OUT" '"deny"' "nested-repo-inside-project: nested scratch repo does not switch spec-gate off for the project"

	s=$(_pd_probe_script "$scriptdir")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	expected=$(cd "$a" && pwd -P)
	assert_rc 0 "nested-repo-inside-project: probe rc 0"
	assert_eq "$OUT" "$expected" "nested-repo-inside-project: hook_project_dir resolves to A, not the nested scratch repo"

	rm -rf "$scriptdir" "$a"
}

# A worktree of the session's own repo legitimately wins over
# CLAUDE_PROJECT_DIR — same repository, different checkout.
t_project_dir_worktree_of_same_repo_is_accepted() {
	local scriptdir a b s json expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	b=$(tmp_dir)
	rm -rf "$b"
	git -C "$a" worktree add "$b" -b wt-accepted >/dev/null 2>&1
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/src/new/file.sh"}}' "$b")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	expected=$(cd "$b" && pwd -P)
	assert_rc 0 "worktree-of-same-repo: rc 0"
	assert_eq "$OUT" "$expected" "worktree-of-same-repo: same-repo worktree B wins over session's CLAUDE_PROJECT_DIR A"
	rm -rf "$scriptdir" "$a" "$b"
}

# An unrelated repo (not a worktree of the session's repo) must not hijack
# the project dir: falls back to CLAUDE_PROJECT_DIR.
t_project_dir_unrelated_repo_falls_back_to_session_dir() {
	local scriptdir a b s json
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	b=$(tmp_repo)
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/src/new/file.sh"}}' "$b")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a"
	assert_rc 0 "unrelated-repo-falls-back: rc 0"
	assert_eq "$OUT" "$(cd "$a" && pwd -P)" "unrelated-repo-falls-back: an unrelated repo does not override the session's project dir"
	rm -rf "$scriptdir" "$a" "$b"
}

# A relative file_path must resolve against the .cwd field, not the hook
# process's own $PWD (which is the session's start directory, not
# necessarily where the tool call actually ran).
t_project_dir_relative_path_resolves_against_cwd_field() {
	local scriptdir a b s json expected
	scriptdir=$(tmp_dir)
	a=$(tmp_repo)
	b=$(tmp_dir)
	rm -rf "$b"
	git -C "$a" worktree add "$b" -b wt-relative >/dev/null 2>&1
	s=$(_pd_probe_script "$scriptdir")
	json=$(printf '{"session_id":"s","cwd":"%s","tool_input":{"file_path":"src/new/file.sh"}}' "$b")
	run_cmd bash -c 'cd "$1" && printf "%s" "$2" | bash "$3"' _ "$a" "$json" "$s"
	expected=$(cd "$b" && pwd -P)
	assert_rc 0 "relative-path-resolves-against-cwd: rc 0"
	assert_eq "$OUT" "$expected" "relative-path-resolves-against-cwd: relative file_path resolves against the .cwd field (B), not the hook's own \$PWD (A)"
	rm -rf "$scriptdir" "$a" "$b"
}

# The fast base-prefix path never spawns git: shim PATH with a `git` that
# marks itself as having run and fails, and prove the marker never appears.
t_project_dir_fast_path_needs_no_git() {
	local scriptdir a s json fakebin marker
	scriptdir=$(tmp_dir)
	a=$(tmp_dir)
	mkdir -p "$a/src"
	s=$(_pd_probe_script "$scriptdir")
	fakebin=$(tmp_dir)
	marker="$fakebin/called"
	cat >"$fakebin/git" <<EOF
#!/usr/bin/env bash
touch "$marker"
exit 1
EOF
	chmod +x "$fakebin/git"
	json=$(printf '{"session_id":"s","tool_input":{"file_path":"%s/src/new/file.sh"}}' "$a")
	run_hook "$s" "$json" CLAUDE_PROJECT_DIR="$a" PATH="$fakebin:$PATH"
	assert_rc 0 "fast-path-no-git: rc 0"
	assert_eq "$OUT" "$(cd "$a" && pwd -P)" "fast-path-no-git: candidate under base resolves without a git lookup"
	assert_file_missing "$marker" "fast-path-no-git: git was never spawned"
	rm -rf "$scriptdir" "$a" "$fakebin"
}
