#!/usr/bin/env bash
# test_git_guard_worktree.sh — F06: git-guard denies `git worktree remove
# --force/-f` (it deletes untracked work in that tree) and any push refspec
# that starts with "+" (a per-ref force push), on the parsed path and on the
# coarse fallback path.

_t_ggw_run() { run_hook "$SCAN_DIR/git-guard.sh" "{\"tool_input\":{\"command\":\"$1\"}}"; }

_t_ggw_pad() {
	local s='' i=0
	while [ "$i" -lt 21000 ]; do
		s="${s}x"
		i=$((i + 1))
	done
	printf '%s' "$s"
}

t_ggw_worktree_remove_force_denied() {
	_t_ggw_run "git worktree remove --force /tmp/x"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_worktree_remove_force_denied long form"
	assert_contains "$OUT" 'status --porcelain' "t_ggw_worktree_remove_force_denied suggests the status check"
	_t_ggw_run "git worktree remove -f /tmp/x"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_worktree_remove_force_denied short form"
	_t_ggw_run "git worktree remove /tmp/x --force"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_worktree_remove_force_denied flag after path"
	_t_ggw_run "git -C /repo worktree remove -f /tmp/x"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_worktree_remove_force_denied with -C"
}

t_ggw_worktree_plain_forms_allowed() {
	_t_ggw_run "git worktree remove /tmp/x"
	assert_eq "$OUT" "" "t_ggw_worktree_plain_forms_allowed plain remove"
	_t_ggw_run "git worktree add /tmp/y -b feature-f"
	assert_eq "$OUT" "" "t_ggw_worktree_plain_forms_allowed add"
	_t_ggw_run "git worktree list"
	assert_eq "$OUT" "" "t_ggw_worktree_plain_forms_allowed list"
}

t_ggw_push_plus_refspec_denied() {
	_t_ggw_run "git push origin +main"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_push_plus_refspec_denied +main"
	_t_ggw_run "git push origin +HEAD:main"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_push_plus_refspec_denied +HEAD:main"
	_t_ggw_run "git push origin main +dev"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_push_plus_refspec_denied plus on a later refspec"
}

t_ggw_push_without_plus_allowed() {
	_t_ggw_run "git push origin main"
	assert_eq "$OUT" "" "t_ggw_push_without_plus_allowed plain"
	_t_ggw_run "git push --force-with-lease origin main"
	assert_eq "$OUT" "" "t_ggw_push_without_plus_allowed force-with-lease"
	_t_ggw_run "git push origin HEAD:refs/heads/a+b"
	assert_eq "$OUT" "" "t_ggw_push_without_plus_allowed plus inside a ref name"
}

t_ggw_coarse_path_learns_the_new_rules() {
	local pad
	pad=$(_t_ggw_pad)
	_t_ggw_run "git worktree remove --force /tmp/x; echo $pad"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_coarse_path_learns_the_new_rules worktree remove --force"
	_t_ggw_run "git push origin +main; echo $pad"
	assert_contains "$OUT" '"permissionDecision":"deny"' "t_ggw_coarse_path_learns_the_new_rules push +main"
	_t_ggw_run "git worktree remove /tmp/x; git push origin main; echo $pad"
	assert_eq "$OUT" "" "t_ggw_coarse_path_learns_the_new_rules plain forms stay allowed"
}
