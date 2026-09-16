#!/usr/bin/env bash
# test_stealth.sh — `flow stealth` (docs/research/17-stealth-specs-2026.md):
# the private-store setup, its detect() used by next/tick/publish, and the
# two git hooks it installs. t_stealth_* functions, sourced by run.sh.
set -u

ST_CLI_PATH=""
ST_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
ST_CLI_PATH="$ST_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && ST_CLI_PATH="$SCAN_DIR/../bin/flow"

# st_cli_in <project-dir> <home-dir> <args...> — run the CLI with cwd=<dir>,
# HOME=<home> and a git identity (a tmp HOME has no global one), without
# moving this runner's own cwd. Sets RC/OUT/ERR.
st_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export GIT_AUTHOR_NAME="flow-test" GIT_AUTHOR_EMAIL="test@example.com" GIT_COMMITTER_NAME="flow-test" GIT_COMMITTER_EMAIL="test@example.com"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$ST_CLI_PATH" "$@"
}

# ---------------------------------------------------------------------------
# 1 — setup on a fresh tmp_repo
# ---------------------------------------------------------------------------

t_stealth_setup_fresh() {
	local home proj target store
	home=$(tmp_dir)
	home=$(cd "$home" && pwd) # collapse a double slash a trailing-slash TMPDIR can leave in mktemp's own output
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "setup on a fresh repo exits 0"
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	assert_contains "$target" "$home/.flow/stealth/" "default store lands under \$HOME/.flow/stealth"
	assert_contains "$target" "/.specs" ".specs link targets a .specs dir"
	store=${target%/.specs}
	run_cmd git -C "$store" rev-parse --git-dir
	assert_rc 0 "store is a git repo"
	assert_contains "$(cat "$proj/.git/info/exclude" 2>/dev/null)" ".specs" "info/exclude has .specs"
	assert_contains "$(cat "$proj/.git/info/exclude" 2>/dev/null)" ".claude/" "info/exclude has .claude/"
	if [ -x "$proj/.git/hooks/post-checkout" ]; then _pass "post-checkout hook is executable"; else _fail "post-checkout hook is executable" "missing or not executable"; fi
	if [ -x "$proj/.git/hooks/commit-msg" ]; then _pass "commit-msg hook is executable"; else _fail "commit-msg hook is executable" "missing or not executable"; fi
	run_cmd git -C "$proj" status --porcelain
	assert_eq "$OUT" "" "git status is empty after setup"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 2 — second run is idempotent
# ---------------------------------------------------------------------------

t_stealth_setup_idempotent() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "second run exits 0"
	assert_contains "$OUT" "already" "second run says already"
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	local count
	count=$(grep -c '^\.specs$' "$proj/.git/info/exclude" 2>/dev/null || true)
	assert_eq "$count" "1" "exclude has exactly one .specs line"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 3 — tracked .specs refuses, disk untouched
# ---------------------------------------------------------------------------

t_stealth_tracked_specs_refuses() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	printf '# spec\n' >"$proj/.specs/001-a/spec.md"
	(cd "$proj" && git add .specs && git commit -qm "track specs") >/dev/null 2>&1
	st_cli_in "$proj" "$home" stealth
	assert_rc 1 "tracked .specs refuses"
	assert_file_missing "$home/.flow" "nothing created under \$HOME/.flow"
	run_cmd git -C "$proj" status --porcelain
	assert_eq "$OUT" "" "repo unchanged (git status still empty)"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# 4 — untracked .specs/ is migrated into the store
# ---------------------------------------------------------------------------

t_stealth_migrates_untracked_specs() {
	local home proj target store content
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	printf 'hello\n' >"$proj/.specs/001-a/spec.md"
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "migrating untracked .specs exits 0"
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${target%/.specs}
	assert_file_exists "$store/.specs/001-a/spec.md" "migrated spec.md lives in the store"
	content=$(cat "$proj/.specs/001-a/spec.md" 2>/dev/null || true)
	assert_eq "$content" "hello" "spec.md is readable through the link"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 5 — local dir holds only state files, store already has the feature
# ---------------------------------------------------------------------------

t_stealth_local_state_only_store_populated() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	store=$(tmp_dir)
	rm -rf "$store"
	mkdir -p "$proj/.specs" "$store/.specs/002-b"
	printf '0 \n' >"$proj/.specs/.next-call-count"
	printf '# spec\n' >"$store/.specs/002-b/spec.md"
	st_cli_in "$proj" "$home" stealth "$store"
	assert_rc 0 "local state-only + populated store exits 0"
	assert_file_missing "$proj/.specs/.next-call-count" "local state file removed"
	assert_file_exists "$store/.specs/002-b/spec.md" "002-b is visible through the link"
	assert_file_exists "$proj/.specs/002-b/spec.md" "002-b is visible through the link (via .specs)"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 6 — both sides hold real specs: refuse, both untouched
# ---------------------------------------------------------------------------

t_stealth_both_hold_specs_refuses() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	store=$(tmp_dir)
	mkdir -p "$proj/.specs/001-a" "$store/.specs/002-b"
	printf 'local\n' >"$proj/.specs/001-a/spec.md"
	printf 'remote\n' >"$store/.specs/002-b/spec.md"
	st_cli_in "$proj" "$home" stealth "$store"
	assert_rc 1 "both sides holding specs refuses"
	assert_file_exists "$proj/.specs/001-a/spec.md" "local side untouched"
	assert_file_exists "$store/.specs/002-b/spec.md" "store side untouched"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 7 — core.hooksPath managed elsewhere
# ---------------------------------------------------------------------------

t_stealth_hooks_path_managed_elsewhere() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	(cd "$proj" && git config core.hooksPath .husky) >/dev/null 2>&1
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "hooksPath set still exits 0"
	assert_file_missing "$proj/.git/hooks/post-checkout" "no hooks written under .git/hooks"
	assert_contains "$OUT" "warn:" "output contains a warn: line"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# 8 — a foreign, unmarked hook is left byte-identical
# ---------------------------------------------------------------------------

t_stealth_foreign_hook_left_alone() {
	local home proj before after
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.git/hooks"
	printf '#!/bin/sh\necho custom\n' >"$proj/.git/hooks/commit-msg"
	chmod +x "$proj/.git/hooks/commit-msg"
	before=$(cat "$proj/.git/hooks/commit-msg")
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "foreign hook present still exits 0"
	after=$(cat "$proj/.git/hooks/commit-msg")
	assert_eq "$after" "$before" "foreign commit-msg is left byte-identical"
	assert_contains "$OUT" "warn:" "warn: printed for the foreign hook"
	assert_file_exists "$proj/.git/hooks/post-checkout" "post-checkout is still written"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# 9 — git worktree add re-links via post-checkout
# ---------------------------------------------------------------------------

t_stealth_worktree_relinks() {
	local home proj wt store link
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	wt=$(tmp_dir)
	rm -rf "$wt"
	(cd "$proj" && git worktree add -q -b st-wt "$wt") >/dev/null 2>&1
	link=$( [ -L "$wt/.specs" ] && echo yes || echo no)
	assert_eq "$link" "yes" "new worktree's .specs is a symlink"
	st_cli_in "$wt" "$home" next --json
	assert_rc 0 "flow next in the new worktree exits 0"
	assert_not_contains "$OUT" "scan-failed" "worktree next is not scan-failed (no .specs)"
	rm -rf "$home" "$proj" "$wt" "$store"
}

# ---------------------------------------------------------------------------
# 10 — commit-msg hook blocks spec vocabulary
# ---------------------------------------------------------------------------

t_stealth_commit_msg_hook_blocks_vocabulary() {
	local home proj store rc
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	# R6: the hook only refuses REAL ids/slugs read from the store's own
	# TASKS.md files, not any T###-shaped string — so T001 has to be real here.
	mkdir -p "$store/.specs/001-x"
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 a — files: a.js — verify: `true`\n'
	} >"$store/.specs/001-x/TASKS.md"
	(cd "$store" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add -A && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm tasks) >/dev/null 2>&1

	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -q --allow-empty -m "T001: add x") >/dev/null 2>&1
	rc=$?
	assert_eq "$rc" "1" "'T001: add x' is refused"

	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -q --allow-empty -m "per spec 004") >/dev/null 2>&1
	rc=$?
	assert_eq "$rc" "1" "'per spec 004' is refused"

	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -q --allow-empty -m "touch .specs/a") >/dev/null 2>&1
	rc=$?
	assert_eq "$rc" "1" "'.specs/a' mention is refused"

	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -q --allow-empty -m "Add empty-slug check") >/dev/null 2>&1
	rc=$?
	assert_eq "$rc" "0" "a plain message succeeds"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 11 — flow next reports stealth
# ---------------------------------------------------------------------------

t_stealth_next_reports_stealth() {
	local home proj proj2 store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}

	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"active": true' "next --json active true in stealth"
	st_cli_in "$proj" "$home" next
	assert_contains "$OUT" "Stealth:" "next plain has a Stealth: line in stealth"

	proj2=$(tmp_repo)
	st_cli_in "$proj2" "$home" next --json
	assert_contains "$OUT" '"active": false' "next --json active false outside stealth"
	st_cli_in "$proj2" "$home" next
	assert_not_contains "$OUT" "Stealth:" "next plain has no Stealth: line outside stealth"
	rm -rf "$home" "$proj" "$proj2" "$store"
}

# ---------------------------------------------------------------------------
# 12 — no-project hint names why a repo looks public
# ---------------------------------------------------------------------------

t_stealth_no_project_hint() {
	local home proj1 proj2 proj3
	home=$(tmp_dir)
	proj1=$(tmp_repo)
	printf 'MIT\n' >"$proj1/LICENSE"
	(cd "$proj1" && git add LICENSE && git commit -qm "license") >/dev/null 2>&1
	st_cli_in "$proj1" "$home" next
	assert_contains "$OUT" "--stealth" "a LICENSE repo's Why: mentions --stealth"

	proj2=$(tmp_repo)
	(cd "$proj2" && git remote add upstream https://example.invalid/x.git) >/dev/null 2>&1
	st_cli_in "$proj2" "$home" next
	assert_contains "$OUT" "an upstream remote" "an upstream remote is named in Why:"

	proj3=$(tmp_repo)
	st_cli_in "$proj3" "$home" next
	assert_not_contains "$OUT" "--stealth" "a bare repo's Why: has no --stealth"
	rm -rf "$home" "$proj1" "$proj2" "$proj3"
}

# ---------------------------------------------------------------------------
# 12b — a CONTRIBUTING guide needs an actual file, not just docs/ or .github/
# existing
# ---------------------------------------------------------------------------

t_stealth_contributing_needs_file() {
	local home proj1 proj2
	home=$(tmp_dir)
	proj1=$(tmp_repo)
	mkdir -p "$proj1/docs" "$proj1/.github"
	printf 'x\n' >"$proj1/docs/keep.md"
	printf 'x\n' >"$proj1/.github/keep.md"
	st_cli_in "$proj1" "$home" next
	assert_not_contains "$OUT" "--stealth" "empty docs/ and .github/ dirs alone do not look public"

	proj2=$(tmp_repo)
	mkdir -p "$proj2/.github"
	printf '# contributing\n' >"$proj2/.github/CONTRIBUTING.md"
	st_cli_in "$proj2" "$home" next
	assert_contains "$OUT" "a CONTRIBUTING guide" ".github/CONTRIBUTING.md is a CONTRIBUTING guide"
	rm -rf "$home" "$proj1" "$proj2"
}

# ---------------------------------------------------------------------------
# 13 — tick commits the store
# ---------------------------------------------------------------------------

t_stealth_tick_commits_store() {
	local home proj store n
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}

	mkdir -p "$proj/.specs/001-demo"
	{
		printf '# Tasks — fixture\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n'
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do the thing — files: a.js — verify: `true`\n'
	} >"$proj/.specs/001-demo/TASKS.md"
	printf '# spec\n' >"$proj/.specs/001-demo/spec.md"
	printf 'x\n' >"$proj/a.js"
	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add a.js && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm "a.js") >/dev/null 2>&1

	st_cli_in "$proj" "$home" use 001-demo
	st_cli_in "$proj" "$home" tick T001
	assert_rc 0 "tick in stealth exits 0"
	assert_contains "$OUT" "store committed" "tick output says store committed"

	run_cmd git -C "$store" log --oneline
	n=$(printf '%s\n' "$OUT" | grep -c .)
	assert_eq "$n" "1" "store git log has 1 commit"

	run_cmd git -C "$proj" status --porcelain
	assert_eq "$OUT" "" "target git status is empty after the tick"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 14 — publish refuses in stealth
# ---------------------------------------------------------------------------

t_stealth_publish_refuses() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	st_cli_in "$proj" "$home" publish --dry-run
	assert_rc 1 "publish --dry-run in stealth exits 1"
	assert_contains "$ERR" "stealth" "publish stderr mentions stealth"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 15 — flow stealth --check --offline --json
# ---------------------------------------------------------------------------

t_stealth_check_json() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	printf 'MIT\n' >"$proj/LICENSE"
	(cd "$proj" && git add LICENSE && git commit -qm "license") >/dev/null 2>&1
	st_cli_in "$proj" "$home" stealth --check --offline --json
	assert_contains "$OUT" '"suggest": true' "check --offline --json suggests before setup"

	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	st_cli_in "$proj" "$home" stealth --check --offline --json
	assert_contains "$OUT" '"active": true' "check --offline --json active after setup"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# 16 — explicit store arg: relative resolves absolute; inside-repo refuses
# ---------------------------------------------------------------------------

t_stealth_explicit_store_arg() {
	local home proj store storeName target proj2
	home=$(tmp_dir)
	proj=$(tmp_repo)
	store=$(tmp_dir)
	store=$(cd "$store" && pwd -P) # match stealth's own fully-resolved form of the store arg
	rm -rf "$store"
	storeName=$(basename "$store")
	st_cli_in "$proj" "$home" stealth "../$storeName"
	assert_rc 0 "explicit relative store arg exits 0"
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	assert_eq "$target" "$store/.specs" "link points at the absolute resolved store path"

	proj2=$(tmp_repo)
	st_cli_in "$proj2" "$home" stealth "$proj2/inside"
	assert_rc 1 "a store inside the repo refuses"
	rm -rf "$home" "$proj" "$proj2" "$store"
}

# ---------------------------------------------------------------------------
# 17 — a dangling stealth link (store deleted) is loud, not no-project
# ---------------------------------------------------------------------------

t_stealth_dangling_link_scan_failed() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	store=$(tmp_dir)
	rm -rf "$store"
	st_cli_in "$proj" "$home" stealth "$store"
	assert_rc 0 "stealth setup with an explicit store exits 0"
	rm -rf "$store"

	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"state": "scan-failed"' "next --json is scan-failed once the store is gone"
	st_cli_in "$proj" "$home" next
	assert_contains "$OUT" "does not exist" "next plain output says the link target does not exist"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# 18 — in stealth, the flow/<slug> branch outranks a shared .current across
# worktrees; $FLOW_SPEC still wins over everything; non-stealth regression
# keeps the pointer authoritative
# ---------------------------------------------------------------------------

_stealth_two_feature_tasks() {
	local proj slug
	proj=$1
	slug=$2
	mkdir -p "$proj/.specs/$slug"
	{
		printf '# Tasks — %s\n' "$slug"
		printf 'Spec: spec.md · Base: none · Route: bounded · Test: `true`\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do the thing — files: a.js — verify: `true`\n'
	} >"$proj/.specs/$slug/TASKS.md"
}

t_stealth_branch_wins_over_shared_current() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}

	_stealth_two_feature_tasks "$proj" 001-aaa
	_stealth_two_feature_tasks "$proj" 002-bbb
	printf '002-bbb\n' >"$proj/.specs/.current"
	(cd "$proj" && git checkout -qb flow/aaa) >/dev/null 2>&1

	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"slug": "001-aaa"' "stealth: branch flow/aaa outranks .current=002-bbb"

	export FLOW_SPEC=002-bbb
	st_cli_in "$proj" "$home" next --json
	unset FLOW_SPEC
	assert_contains "$OUT" '"slug": "002-bbb"' "stealth: \$FLOW_SPEC still wins over the branch"
	rm -rf "$home" "$proj" "$store"
}

t_stealth_nonstealth_current_stays_authoritative() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	_stealth_two_feature_tasks "$proj" 001-aaa
	_stealth_two_feature_tasks "$proj" 002-bbb
	printf '002-bbb\n' >"$proj/.specs/.current"
	(cd "$proj" && git checkout -qb flow/aaa) >/dev/null 2>&1

	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"slug": "002-bbb"' "non-stealth: .current stays authoritative over branch flow/aaa"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# R4 — a branch slug must match a feature dir's NNN- stripped name EXACTLY
# (flow/login must not pick 001-auth-login over 002-login). Confirms the
# router already gets this right (matchSlug: d.slice(4) === slug); the bug
# was only in the bash resolvers (flow-lint, specgate), fixed separately.
# ---------------------------------------------------------------------------

t_stealth_router_slug_prefix_disambiguation() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-auth-login" "$proj/.specs/002-login" "$proj/.specs/003-other"
	(cd "$proj" && git checkout -qb flow/login) >/dev/null 2>&1
	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"slug": "002-login"' "router: branch flow/login resolves 002-login, not 001-auth-login"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# R1 — the store must be its OWN git repo, not swallowed by an outer one
# (e.g. HOME is a dotfiles repo); tick must only ever commit into a store
# that really is its own toplevel, and its commit carries a pathspec.
# ---------------------------------------------------------------------------

_stealth_r1_tasks_fixture() {
	local dir=$1
	{
		printf '# Tasks — fixture\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n'
		printf '\n## Behaviors\n'
		printf '| ID | Given / When / Then | Task | Proven by |\n'
		printf '|----|---------------------|------|-----------|\n'
		printf '| B1 | given / when / then | T001 | t1 |\n'
		printf '\n## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 do the thing — files: a.js — verify: `true`\n'
	} >"$dir/TASKS.md"
	printf '# spec\n' >"$dir/spec.md"
}

t_stealth_store_is_own_repo_when_home_is_a_repo() {
	local home proj target store home_count store_count
	home=$(tmp_repo) # HOME is itself a git repo (e.g. a dotfiles checkout)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "setup with HOME as a git repo exits 0"
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${target%/.specs}
	assert_file_exists "$store/.git" "store has its own .git, not just HOME's"

	mkdir -p "$proj/.specs/001-demo"
	_stealth_r1_tasks_fixture "$proj/.specs/001-demo"
	printf 'x\n' >"$proj/a.js"
	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add a.js && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm "a.js") >/dev/null 2>&1

	st_cli_in "$proj" "$home" use 001-demo
	run_cmd git -C "$home" log --oneline
	home_count=$(printf '%s\n' "$OUT" | grep -c .)

	st_cli_in "$proj" "$home" tick T001
	assert_rc 0 "tick with HOME as a git repo exits 0"
	assert_contains "$OUT" "store committed" "tick reports the store (not HOME) committed"

	run_cmd git -C "$home" log --oneline
	assert_eq "$(printf '%s\n' "$OUT" | grep -c .)" "$home_count" "HOME's own log gets no new commit from the tick"

	run_cmd git -C "$store" log --oneline
	store_count=$(printf '%s\n' "$OUT" | grep -c .)
	assert_eq "$store_count" "1" "the store's own log has exactly one commit"
	rm -rf "$home" "$proj" "$store"
}

t_stealth_tick_commit_pathspec_leaves_other_staged() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}

	mkdir -p "$proj/.specs/001-demo"
	_stealth_r1_tasks_fixture "$proj/.specs/001-demo"
	printf 'x\n' >"$proj/a.js"
	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add a.js && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm "a.js") >/dev/null 2>&1

	mkdir -p "$store/.specs/002-other"
	printf 'other\n' >"$store/.specs/002-other/note.md"
	(cd "$store" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add .specs/002-other/note.md) >/dev/null 2>&1

	st_cli_in "$proj" "$home" use 001-demo
	st_cli_in "$proj" "$home" tick T001
	assert_rc 0 "tick still exits 0 with an unrelated pre-staged file in the store"

	run_cmd git -C "$store" status --porcelain -- .specs/002-other/note.md
	assert_contains "$OUT" "A  .specs/002-other/note.md" "the pre-staged unrelated file is still staged, not swept into the tick's commit"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# R2 — adopting an existing .specs link must pass the same validation as an
# explicit --store arg: no shell-unsafe path, basename must be .specs, and
# the target must resolve outside the repo.
# ---------------------------------------------------------------------------

t_stealth_adopt_link_quote_in_path_refuses() {
	local home proj outside
	home=$(tmp_dir)
	proj=$(tmp_repo)
	outside=$(tmp_dir)
	mkdir -p "$outside/q'x/.specs"
	ln -s "$outside/q'x/.specs" "$proj/.specs"
	st_cli_in "$proj" "$home" stealth
	assert_rc 1 "adopting a link through a quote in the path refuses"
	assert_file_missing "$proj/.git/hooks/post-checkout" "no hook written on refusal"
	rm -rf "$home" "$proj" "$outside"
}

t_stealth_adopt_link_inside_repo_wrong_name_refuses() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/docs/specs"
	ln -s "$proj/docs/specs" "$proj/.specs"
	st_cli_in "$proj" "$home" stealth
	assert_rc 1 "a link to docs/specs (in-tree, wrong name) refuses"
	assert_file_missing "$proj/docs/specs/.gitignore" "nothing created in docs/"
	rm -rf "$home" "$proj"
}

t_stealth_adopt_link_wrong_basename_outside_refuses() {
	local home proj outside
	home=$(tmp_dir)
	proj=$(tmp_repo)
	outside=$(tmp_dir)
	mkdir -p "$outside/myspecs"
	ln -s "$outside/myspecs" "$proj/.specs"
	st_cli_in "$proj" "$home" stealth
	assert_rc 1 "a link to <outside>/myspecs (wrong basename, not .specs) refuses"
	rm -rf "$home" "$proj" "$outside"
}

# ---------------------------------------------------------------------------
# R3 — a dangling IN-TREE link is not stealth (bash's is-stealth test agrees:
# it already requires the resolved target to be outside root).
# ---------------------------------------------------------------------------

t_stealth_dangling_intree_link_not_stealth() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	ln -s "docs/specs" "$proj/.specs" # dangling: docs/specs does not exist, and is IN-TREE
	st_cli_in "$proj" "$home" next --json
	assert_not_contains "$OUT" '"state": "scan-failed"' "a dangling in-tree link is not scan-failed"
	assert_not_contains "$OUT" '"active": true' "a dangling in-tree link is not stealth-active"
	st_cli_in "$proj" "$home" next
	assert_not_contains "$OUT" "Stealth:" "no Stealth: line for a dangling in-tree link"
	rm -rf "$home" "$proj"
}

t_stealth_self_loop_link_not_stealth() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	ln -s ".specs" "$proj/.specs" # .specs -> .specs, a self-loop
	st_cli_in "$proj" "$home" next --json
	# a broken tree stays loud (row 0), it just is not stealth
	assert_contains "$OUT" '"state": "scan-failed"' "a .specs -> .specs self-loop still refuses to report clean"
	assert_not_contains "$OUT" '"active": true' "a .specs -> .specs self-loop is not stealth-active"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# R6 — commit-msg hook: precise real-id/slug matching from the store, not a
# broad generic-id regex. Real ids: T001, T002, G001 in 001-auth-flow.
# ---------------------------------------------------------------------------

t_stealth_commit_msg_hook_precise() {
	local home proj store gitenv
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}

	mkdir -p "$store/.specs/001-auth-flow"
	{
		printf '# Tasks — auth-flow\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 a — files: a.js — verify: `true`\n'
		printf -- '- [ ] T002 b — files: b.js — verify: `true`\n'
		printf '\n## Gates\n- [ ] G001 clean — verify: `true`\n'
	} >"$store/.specs/001-auth-flow/TASKS.md"
	(cd "$store" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add -A && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm tasks) >/dev/null 2>&1

	gitenv='GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com'

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "finish 001-auth-flow") >/dev/null 2>&1
	assert_eq "$?" "1" "'finish 001-auth-flow' (a real slug) is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "closes T002") >/dev/null 2>&1
	assert_eq "$?" "1" "'closes T002' (a real id) is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "#G001 done") >/dev/null 2>&1
	assert_eq "$?" "1" "'#G001 done' via -m (git keeps the # line for -m) is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "touch .specs/x") >/dev/null 2>&1
	assert_eq "$?" "1" "'touch .specs/x' is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "see TASKS.md") >/dev/null 2>&1
	assert_eq "$?" "1" "'see TASKS.md' is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "Ruling: use sqlite") >/dev/null 2>&1
	assert_eq "$?" "1" "'Ruling: use sqlite' is refused"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "Bump G123 driver") >/dev/null 2>&1
	assert_eq "$?" "0" "'Bump G123 driver' (G123 is not a real id) is allowed"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "HTTP T100 support") >/dev/null 2>&1
	assert_eq "$?" "0" "'HTTP T100 support' (T100 is not a real id) is allowed"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "data flow use cases") >/dev/null 2>&1
	assert_eq "$?" "0" "'data flow use cases' is allowed"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "Add empty-slug check") >/dev/null 2>&1
	assert_eq "$?" "0" "'Add empty-slug check' is allowed"

	local msgfile
	msgfile=$(tmp_dir)/msg.txt
	mkdir -p "$(dirname "$msgfile")"
	printf 'Add constant\n# ------------------------ >8 ------------------------\n+T001\n' >"$msgfile"
	run_cmd "$proj/.git/hooks/commit-msg" "$msgfile"
	assert_rc 0 "a -v-style diff appended after the scissors line is ignored"
	rm -rf "$home" "$proj" "$store" "$(dirname "$msgfile")"
}

# ---------------------------------------------------------------------------
# T4a — slug tail-strip only applies to archive dirs; a top-level dir not
# shaped NNN-slug is never a slug at all (no *-*-*-* fallback stripping).
# ---------------------------------------------------------------------------

t_stealth_commit_msg_hook_slug_tail_strip_only_for_archive() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	mkdir -p "$store/.specs/my-draft-notes-v2"
	printf 'notes\n' >"$store/.specs/my-draft-notes-v2/notes.md"
	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -q --allow-empty -m "bump to v2 of the api") >/dev/null 2>&1
	assert_eq "$?" "0" "a non-NNN- top-level store dir does not fall back to a stripped tail slug"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# T4b — pure-shell whole-token matching: no id/slug is ever interpolated
# into a regex (a slug with regex metacharacters still refuses), and the
# boundary class is [A-Za-z0-9_] only — a '-' no longer breaks a token.
# ---------------------------------------------------------------------------

t_stealth_commit_msg_hook_pure_shell_token_boundary() {
	local home proj store gitenv
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	gitenv='GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com'

	mkdir -p "$store/.specs/005-c++"
	printf 'notes\n' >"$store/.specs/005-c++/notes.md"
	mkdir -p "$store/.specs/001-x"
	{
		printf '# Tasks — x\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 a — files: a.js — verify: `true`\n'
	} >"$store/.specs/001-x/TASKS.md"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "port 005-c++ code") >/dev/null 2>&1
	assert_eq "$?" "1" "a slug with regex metacharacters (005-c++) is refused via pure shell matching"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "fix T001-regression") >/dev/null 2>&1
	assert_eq "$?" "1" "'fix T001-regression' is refused (a dash no longer counts as a boundary)"

	(cd "$proj" && env $gitenv git commit -q --allow-empty -m "Bump G123 driver") >/dev/null 2>&1
	assert_eq "$?" "0" "'Bump G123 driver' (G123 is not a real id) is still allowed"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# T4c — git's own comment lines ('#', '# ...', '#<TAB>...') are not scanned;
# a real line that merely starts with '#' (e.g. "#T001 done") still is.
# ---------------------------------------------------------------------------

t_stealth_commit_msg_hook_ignores_git_comment_lines() {
	local home proj store msgfile
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	mkdir -p "$store/.specs/001-auth-flow"
	printf 'spec\n' >"$store/.specs/001-auth-flow/spec.md"

	msgfile=$(tmp_dir)/msg.txt
	mkdir -p "$(dirname "$msgfile")"
	printf 'Add constant\n# On branch flow/001-auth-flow\n' >"$msgfile"
	run_cmd "$proj/.git/hooks/commit-msg" "$msgfile"
	assert_rc 0 "git's own '# On branch ...' comment line is not scanned"

	mkdir -p "$store/.specs/002-y"
	{
		printf '# Tasks — y\n'
		printf 'Spec: spec.md · Base: none · Route: dispatch · Test: `true`\n\n'
		printf '## Phase 1 — p\nGoal: g\nIndependent test: `true`\n'
		printf -- '- [ ] T001 a — files: a.js — verify: `true`\n'
	} >"$store/.specs/002-y/TASKS.md"
	printf '#T001 done\n' >"$msgfile"
	run_cmd "$proj/.git/hooks/commit-msg" "$msgfile"
	assert_rc 1 "a line like '#T001 done' (not git's template form) is still scanned"
	rm -rf "$home" "$proj" "$store" "$(dirname "$msgfile")"
}

# ---------------------------------------------------------------------------
# R8 — hooks silently disabled later: hooksActive(root), surfaced by
# `flow next` and `flow stealth --check`.
# ---------------------------------------------------------------------------

t_stealth_hooks_active_flag_goes_false_when_hookspath_set() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	(cd "$proj" && git config core.hooksPath .husky) >/dev/null 2>&1
	st_cli_in "$proj" "$home" next
	assert_contains "$OUT" "hooks are not active" "next plain: hooks are not active once core.hooksPath is set"
	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"hooks": false' "next --json: stealth.hooks is false"
	rm -rf "$home" "$proj"
}

t_stealth_check_reports_hooks_active() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	store=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${store%/.specs}
	st_cli_in "$proj" "$home" stealth --check --offline --json
	assert_contains "$OUT" '"hooks": true' "check --json: hooks true right after setup"
	st_cli_in "$proj" "$home" stealth --check --offline
	assert_contains "$OUT" "hooks: active" "check plain: hooks: active right after setup"
	rm -rf "$home" "$proj" "$store"
}

# ---------------------------------------------------------------------------
# R9 — refusals and store placement.
# ---------------------------------------------------------------------------

t_stealth_store_ancestor_of_repo_refuses() {
	local home parent proj
	home=$(tmp_dir)
	parent=$(tmp_dir)
	proj="$parent/repo"
	mkdir -p "$proj"
	(cd "$proj" && git init -q && git config user.email t@e.com && git config user.name t && printf '# f\n' >README.md && git add README.md && git commit -qm init) >/dev/null 2>&1
	st_cli_in "$proj" "$home" stealth "$parent"
	assert_rc 1 "a store that is an ancestor of the repo refuses"
	rm -rf "$home" "$parent"
}

t_stealth_dotfiles_only_store_specs_counts_as_empty() {
	local home proj store
	home=$(tmp_dir)
	proj=$(tmp_repo)
	store=$(tmp_dir)
	mkdir -p "$store/.specs" "$proj/.specs/001-a"
	printf 'ignored\n' >"$store/.specs/.gitignore"
	printf 'local\n' >"$proj/.specs/001-a/spec.md"
	st_cli_in "$proj" "$home" stealth "$store"
	assert_rc 0 "a store .specs holding only dotfiles counts as empty for the move"
	assert_file_exists "$store/.specs/001-a/spec.md" "the local feature dir migrated into the store"
	rm -rf "$home" "$proj" "$store"
}

t_stealth_default_store_dir_mode_0700() {
	local home proj target store parent mode parentmode
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${target%/.specs}
	parent=$(dirname "$store")
	mode=$(ls -ld "$store" 2>/dev/null | cut -c1-10)
	assert_eq "$mode" "drwx------" "the default store dir is mode 700"
	parentmode=$(ls -ld "$parent" 2>/dev/null | cut -c1-10)
	assert_eq "$parentmode" "drwx------" "<HOME>/.flow/stealth is mode 700"
	rm -rf "$home" "$proj" "$store"
}

t_stealth_explicit_store_specs_symlinked_into_repo_refuses() {
	local home proj out
	home=$(tmp_dir)
	proj=$(tmp_repo)
	out=$(tmp_dir)
	mkdir -p "$proj/docs/specs"
	ln -s "$proj/docs/specs" "$out/.specs"
	st_cli_in "$proj" "$home" stealth "$out"
	assert_rc 1 "an explicit store whose .specs symlinks into the repo refuses"
	assert_file_missing "$proj/docs/specs/.gitignore" "no .gitignore written into repo/docs/specs"
	assert_file_missing "$proj/.specs" "no .specs link created in the repo"
	rm -rf "$home" "$proj" "$out"
}

t_stealth_adopt_link_two_hops_into_repo_refuses() {
	local home proj out
	home=$(tmp_dir)
	proj=$(tmp_repo)
	out=$(tmp_dir)
	mkdir -p "$proj/docs/specs"
	ln -s "$proj/docs/specs" "$out/.specs"
	ln -s "$out/.specs" "$proj/.specs"
	st_cli_in "$proj" "$home" stealth
	assert_rc 1 "adopting a link whose store resolves (one more hop) into the repo refuses"
	assert_file_missing "$proj/docs/specs/.gitignore" "no .gitignore written into repo/docs/specs"
	rm -rf "$home" "$proj" "$out"
}

t_stealth_store_root_refuses() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	st_cli_in "$proj" "$home" stealth /
	assert_rc 1 "flow stealth / refuses"
	assert_contains "$ERR" "above this repo" "refusal message says above this repo"
	rm -rf "$home" "$proj"
}

t_stealth_dangling_target_through_alias_not_stealth() {
	local home proj tmp alias
	home=$(tmp_dir)
	proj=$(tmp_repo)
	tmp=$(tmp_dir)
	alias="$tmp/alias"
	ln -s "$proj" "$alias"
	ln -s "$alias/nope/.specs" "$proj/.specs"
	st_cli_in "$proj" "$home" next --json
	assert_contains "$OUT" '"active": false' "a dangling target reachable back into the repo through an alias is not stealth"
	rm -rf "$home" "$proj" "$tmp"
}

t_stealth_default_store_dir_mode_0700_migration() {
	local home proj target store parent mode parentmode
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	printf 'hello\n' >"$proj/.specs/001-a/spec.md"
	st_cli_in "$proj" "$home" stealth
	assert_rc 0 "migration onto the default store exits 0"
	target=$(readlink "$proj/.specs" 2>/dev/null || true)
	store=${target%/.specs}
	parent=$(dirname "$store")
	mode=$(ls -ld "$store" 2>/dev/null | cut -c1-10)
	assert_eq "$mode" "drwx------" "the migrated default store dir is mode 700"
	parentmode=$(ls -ld "$parent" 2>/dev/null | cut -c1-10)
	assert_eq "$parentmode" "drwx------" "<HOME>/.flow/stealth is mode 700 after migration"
	rm -rf "$home" "$proj" "$store"
}

t_stealth_exdev_refusal_cleans_up_and_fix_line_works() {
	local home proj preloaddir preload fixline fixcmd
	home=$(tmp_dir)
	proj=$(tmp_repo)
	mkdir -p "$proj/.specs/001-a"
	printf 'hello\n' >"$proj/.specs/001-a/spec.md"
	preloaddir=$(tmp_dir)
	preload="$preloaddir/exdev-preload.js"
	cat >"$preload" <<'EOF'
const fs = require('fs');
const path = require('path');
const orig = fs.renameSync;
fs.renameSync = function (src, dest) {
	if (path.basename(src) === '.specs') {
		const e = new Error('simulated EXDEV');
		e.code = 'EXDEV';
		throw e;
	}
	return orig(src, dest);
};
EOF
	export NODE_OPTIONS="--require $preload"
	st_cli_in "$proj" "$home" stealth
	unset NODE_OPTIONS
	assert_rc 1 "EXDEV refusal exits 1"
	assert_file_missing "$home/.flow" "no leftover <HOME>/.flow after EXDEV refusal"
	assert_file_exists "$proj/.specs/001-a/spec.md" "spec.md still lives at the original path after EXDEV refusal"

	fixline=$(printf '%s\n' "$ERR" | grep '  fix: mkdir -p')
	fixcmd=${fixline#*fix: }
	run_cmd env HOME="$home" PATH="$(dirname "$ST_CLI_PATH"):$PATH" bash -c "cd '$proj' && $fixcmd"
	assert_rc 0 "the fix line, run in a shell without the preload, succeeds"

	st_cli_in "$proj" "$home" stealth --check --offline --json
	assert_contains "$OUT" '"active": true' "stealth is active after running the fix line"
	rm -rf "$home" "$proj" "$preloaddir"
}

t_stealth_tick_nonstealth_symlinked_feature_dir_no_store_line() {
	local proj other home before after
	proj=$(tmp_repo)
	other=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$other/001-x" "$proj/.specs"
	_stealth_r1_tasks_fixture "$other/001-x"
	printf 'x\n' >"$proj/a.js"
	(cd "$proj" && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git add a.js && GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e.com git commit -qm "a.js") >/dev/null 2>&1
	ln -s "$other/001-x" "$proj/.specs/001-x"

	st_cli_in "$proj" "$home" use 001-x
	run_cmd git -C "$other" rev-parse HEAD
	before=$OUT
	st_cli_in "$proj" "$home" tick T001
	assert_rc 0 "tick on a non-stealth repo with one symlinked feature dir exits 0"
	assert_not_contains "$OUT" "store" "tick output has no store line outside stealth (.specs itself is a real dir)"
	run_cmd git -C "$other" rev-parse HEAD
	after=$OUT
	assert_eq "$after" "$before" "the symlink's target repo gets no commit"
	rm -rf "$proj" "$other" "$home"
}
