#!/usr/bin/env bash
# test_flow.sh — tests for U3 scripts-flow: new-spec, task-brief,
# review-package, flow-lint. Sourced by tests/run.sh, which defines
# HERE (this dir) and SCAN_DIR (its parent, where the scripts live).
# All t_flow_* functions run in the same shell as run.sh (no subshell),
# so any test that changes directory restores it before returning.
#
# Spec 004 deleted slice-brief and slice-overlap; the t_flow_slice_brief_* and
# t_flow_slice_overlap_* tests that lived here were not weakened but relocated
# onto their replacements, which cover the same behaviours at task granularity:
#   slice-brief   -> task-brief, tested by t_taskbrief_* in test_flow_lint.sh
#                    (help, one-task cut with its phase, --design contract,
#                     missing task exit 1, default out path, BASE recording)
#   slice-overlap -> flow-lint, tested by t_flowlint_* in test_flow_lint.sh
#                    ([P] overlap in a wave is an ERROR, overlap across waves
#                     is ok, --waves output, fenced decoys, CRLF, --json)

t_flow_new_spec_help() {
	run_cmd "$SCAN_DIR/new-spec" --help
	assert_rc 0 "flow: new-spec --help rc0"
	assert_contains "$OUT" "Usage: new-spec" "flow: new-spec --help usage text"
}

t_flow_review_package_help() {
	run_cmd "$SCAN_DIR/review-package" --help
	assert_rc 0 "flow: review-package --help rc0"
	assert_contains "$OUT" "Usage: review-package" "flow: review-package --help usage text"
}

t_flow_new_spec_creates_dir_and_branch() {
	local repo prevdir
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec creates dir/branch setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "My Feature Title" --dir .specs
	assert_rc 0 "flow: new-spec creates spec dir rc0"
	assert_file_exists ".specs/001-my-feature-title" "flow: new-spec spec dir exists"
	assert_file_exists ".claude/flow.json" "flow: new-spec writes flow.json"
	assert_contains "$OUT" '"number":"001"' "flow: new-spec stdout has number"
	assert_contains "$OUT" '"slug":"my-feature-title"' "flow: new-spec stdout has slug"
	assert_contains "$OUT" '"branch":"flow/my-feature-title"' "flow: new-spec stdout has branch"
	assert_eq "$(git rev-parse --abbrev-ref HEAD)" "flow/my-feature-title" "flow: new-spec checks out the new branch"
	cd "$prevdir" || true
}

t_flow_new_spec_no_branch() {
	local repo prevdir before after
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec --no-branch setup cd"
		cd "$prevdir" || true
		return
	}
	before=$(git rev-parse --abbrev-ref HEAD)
	run_cmd "$SCAN_DIR/new-spec" "No Branch Feature" --no-branch
	assert_rc 0 "flow: new-spec --no-branch rc0"
	after=$(git rev-parse --abbrev-ref HEAD)
	assert_eq "$after" "$before" "flow: new-spec --no-branch does not switch branch"
	assert_contains "$OUT" '"branch":""' "flow: new-spec --no-branch empty branch field"
	assert_contains "$OUT" '"worktree":null' "flow: new-spec --no-branch worktree is null"
	cd "$prevdir" || true
}

t_flow_new_spec_worktree() {
	# The worktree destination is $(git rev-parse --show-toplevel)/../code-worktrees/<branch>
	# (frozen by C8), which for every tmp_repo resolves under the same shared
	# ${TMPDIR:-/tmp} parent. Use a unique title per invocation so repeated
	# runs (or leftovers from a previous run) never collide on that path.
	local repo prevdir hits suffix wtpath
	prevdir=$(pwd)
	repo=$(tmp_repo)
	suffix=$(mktemp -u "${TMPDIR:-/tmp}/wtXXXXXX")
	suffix=${suffix##*/}
	suffix=$(LC_ALL=C printf '%s' "$suffix" | LC_ALL=C tr '[:upper:]' '[:lower:]')
	cd "$repo" || {
		_fail "flow: new-spec --worktree setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "Worktree Feature $suffix" --worktree
	assert_rc 0 "flow: new-spec --worktree rc0"
	assert_contains "$OUT" '"worktree":"' "flow: new-spec --worktree JSON has a worktree path"
	hits=$(git worktree list | grep -c "flow/worktree-feature-$suffix" || true)
	assert_eq "$hits" "1" "flow: new-spec --worktree registers the new worktree"
	wtpath=$(dirname "$repo")/code-worktrees/flow/worktree-feature-$suffix
	git worktree remove --force "$wtpath" >/dev/null 2>&1 || true
	rm -rf "$wtpath" 2>/dev/null || true
	cd "$prevdir" || true
}

t_flow_new_spec_collision_safe() {
	local repo prevdir
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec collision-safe setup cd"
		cd "$prevdir" || true
		return
	}
	mkdir -p .specs/001-existing-thing
	run_cmd "$SCAN_DIR/new-spec" "Second Thing" --no-branch
	assert_rc 0 "flow: new-spec collision-safe rc0"
	assert_file_exists ".specs/002-second-thing" "flow: new-spec computes 002 after existing 001"
	cd "$prevdir" || true
}

t_flow_new_spec_slug_normalizes_title() {
	local repo prevdir slug len
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec slug setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "  Weird!! Title_With CAPS & Punct...uation That Is Definitely Longer Than Forty Characters" --no-branch
	assert_rc 0 "flow: new-spec slug title rc0"
	slug=$(printf '%s' "$OUT" | sed -n 's/.*"slug":"\([^"]*\)".*/\1/p')
	case "$slug" in
	*[!a-z0-9-]*)
		_fail "flow: new-spec slug is lowercase ascii/dash only" "got: $slug"
		;;
	*)
		_pass "flow: new-spec slug is lowercase ascii/dash only"
		;;
	esac
	len=${#slug}
	if [ "$len" -gt 0 ] && [ "$len" -le 40 ]; then
		_pass "flow: new-spec slug length is 1..40"
	else
		_fail "flow: new-spec slug length is 1..40" "len=$len slug=$slug"
	fi
	cd "$prevdir" || true
}

t_flow_new_spec_requires_git_for_branch() {
	local d prevdir
	prevdir=$(pwd)
	d=$(tmp_dir)
	cd "$d" || {
		_fail "flow: new-spec no-repo setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "No Repo Feature"
	assert_rc 1 "flow: new-spec exits 1 outside a git repo when a branch is requested"
	cd "$prevdir" || true
}

t_flow_new_spec_no_branch_works_outside_git() {
	local d prevdir
	prevdir=$(pwd)
	d=$(tmp_dir)
	cd "$d" || {
		_fail "flow: new-spec --no-branch outside-repo setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "No Repo No Branch" --no-branch
	assert_rc 0 "flow: new-spec --no-branch works outside a git repo"
	assert_file_exists ".specs/001-no-repo-no-branch" "flow: new-spec --no-branch creates spec dir outside a repo"
	cd "$prevdir" || true
}

t_flow_new_spec_unwritable_dir_exit1() {
	local d prevdir target
	prevdir=$(pwd)
	if [ "$(id -u)" = "0" ]; then
		_pass "flow: new-spec exits 1 when the target dir is not writable (skipped: running as root)"
		return
	fi
	d=$(tmp_dir)
	target="$d/locked"
	mkdir -p "$target"
	chmod 555 "$target"
	cd "$d" || {
		_fail "flow: new-spec unwritable-dir setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "Locked Dir Feature" --dir locked --no-branch
	assert_rc 1 "flow: new-spec exits 1 when the target dir is not writable"
	chmod 755 "$target"
	cd "$prevdir" || true
}

t_flow_new_spec_unwritable_dir_no_branch_created() {
	# Regression guard: an unwritable --dir must fail BEFORE the
	# branch/worktree step runs, so a run WITHOUT --no-branch leaves the
	# checkout on its original branch with no new branch created.
	local repo prevdir target before_branch
	prevdir=$(pwd)
	if [ "$(id -u)" = "0" ]; then
		_pass "flow: new-spec unwritable dir leaves no new branch (skipped: running as root)"
		return
	fi
	repo=$(tmp_repo)
	target="$repo/locked"
	mkdir -p "$target"
	chmod 555 "$target"
	cd "$repo" || {
		_fail "flow: new-spec unwritable-dir no-branch-created setup cd"
		cd "$prevdir" || true
		return
	}
	before_branch=$(git rev-parse --abbrev-ref HEAD)
	run_cmd "$SCAN_DIR/new-spec" "Locked Dir Branch Feature" --dir locked
	assert_rc 1 "flow: new-spec exits 1 when the target dir is not writable and a branch was requested"
	assert_eq "$(git rev-parse --abbrev-ref HEAD)" "$before_branch" "flow: new-spec does not switch branch when the target dir write fails"
	assert_eq "$(git branch --list 'flow/locked-dir-branch-feature')" "" "flow: new-spec does not leave a stray branch when the target dir write fails"
	chmod 755 "$target"
	cd "$prevdir" || true
}

t_flow_new_spec_number_scans_worktrees() {
	local repo prevdir wtpath
	prevdir=$(pwd)
	repo=$(tmp_repo)
	wtpath="${repo}-wt-a"
	cd "$repo" || {
		_fail "flow: new-spec scans worktrees setup cd"
		cd "$prevdir" || true
		return
	}
	git worktree add -b wt-a "$wtpath" >/dev/null 2>&1
	mkdir -p "$wtpath/.specs/001-a"
	run_cmd "$SCAN_DIR/new-spec" "Second" --no-branch
	assert_rc 0 "flow: new-spec scans worktrees rc0"
	assert_file_exists ".specs/002-second" "flow: new-spec scans worktrees creates 002-second"
	assert_contains "$OUT" '"number":"002"' "flow: new-spec scans worktrees stdout has number 002"
	git worktree remove --force "$wtpath" >/dev/null 2>&1 || true
	rm -rf "$wtpath" 2>/dev/null || true
	cd "$prevdir" || true
}

t_flow_new_spec_number_scans_refs() {
	local repo prevdir base
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec scans refs setup cd"
		cd "$prevdir" || true
		return
	}
	base=$(git rev-parse --abbrev-ref HEAD)
	git checkout -q -b b
	mkdir -p .specs/003-b
	printf '# spec\n' >.specs/003-b/spec.md
	git add .specs/003-b/spec.md
	git commit -q -m spec
	git checkout -q "$base"
	run_cmd "$SCAN_DIR/new-spec" "Fourth" --no-branch
	assert_rc 0 "flow: new-spec scans refs rc0"
	assert_contains "$OUT" '"number":"004"' "flow: new-spec scans refs stdout has number 004"
	cd "$prevdir" || true
}

t_flow_new_spec_number_no_git() {
	local d prevdir
	prevdir=$(pwd)
	d=$(tmp_dir)
	mkdir -p "$d/.specs/005-x"
	cd "$d" || {
		_fail "flow: new-spec no-git number setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "Six" --no-branch
	assert_rc 0 "flow: new-spec no-git number rc0"
	assert_contains "$OUT" '"number":"006"' "flow: new-spec no-git number stdout has number 006"
	cd "$prevdir" || true
}

t_flow_new_spec_renames_zellij_pane() {
	local repo prevdir stub
	prevdir=$(pwd)
	repo=$(tmp_repo)
	stub=$(tmp_dir)
	cat >"$stub/zellij" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$(dirname "$0")/calls.log"
exit 0
STUBEOF
	chmod +x "$stub/zellij"
	cd "$repo" || {
		_fail "flow: new-spec renames zellij pane setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd env PATH="$stub:$PATH" ZELLIJ_PANE_ID=7 "$SCAN_DIR/new-spec" "Pane Feature" --no-branch
	assert_rc 0 "flow: new-spec renames zellij pane rc0"
	assert_contains "$(cat "$stub/calls.log" 2>/dev/null)" "action rename-pane 001-pane-feature" "flow: new-spec renames zellij pane calls zellij action rename-pane"
	assert_contains "$OUT" '"number":"001"' "flow: new-spec renames zellij pane stdout has number"
	assert_contains "$OUT" '"slug":"pane-feature"' "flow: new-spec renames zellij pane stdout has slug"
	cd "$prevdir" || true
}

t_flow_new_spec_zellij_failure_is_silent() {
	local repo prevdir stub
	prevdir=$(pwd)
	repo=$(tmp_repo)
	stub=$(tmp_dir)
	cat >"$stub/zellij" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$(dirname "$0")/calls.log"
exit 1
STUBEOF
	chmod +x "$stub/zellij"
	cd "$repo" || {
		_fail "flow: new-spec zellij failure is silent setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd env PATH="$stub:$PATH" ZELLIJ_PANE_ID=7 "$SCAN_DIR/new-spec" "Pane Feature" --no-branch
	assert_rc 0 "flow: new-spec zellij failure is silent rc0"
	assert_contains "$OUT" '"number":"001"' "flow: new-spec zellij failure is silent stdout has number"
	assert_eq "$OUT" "$(printf '%s' "$OUT" | head -1)" "flow: new-spec zellij failure is silent stdout is exactly one line"
	cd "$prevdir" || true
}

t_flow_new_spec_no_zellij_no_rename() {
	local repo prevdir stub
	prevdir=$(pwd)
	repo=$(tmp_repo)
	stub=$(tmp_dir)
	cat >"$stub/zellij" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$(dirname "$0")/calls.log"
exit 0
STUBEOF
	chmod +x "$stub/zellij"
	cd "$repo" || {
		_fail "flow: new-spec no zellij no rename setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd env PATH="$stub:$PATH" ZELLIJ_PANE_ID= "$SCAN_DIR/new-spec" "Pane Feature" --no-branch
	assert_rc 0 "flow: new-spec no zellij no rename rc0"
	assert_file_missing "$stub/calls.log" "flow: new-spec no zellij no rename does not call zellij"
	cd "$prevdir" || true
}

t_flow_new_spec_empty_slug_exit1() {
	local repo prevdir before_specs before_flow
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec empty-slug setup cd"
		cd "$prevdir" || true
		return
	}
	before_specs=$(ls -A .specs 2>/dev/null || true)
	before_flow=$([ -f .claude/flow.json ] && echo yes || echo no)
	run_cmd "$SCAN_DIR/new-spec" "!!! ... ---" --no-branch
	assert_rc 1 "flow: new-spec exits 1 for a title with no ASCII letter or digit"
	assert_contains "$ERR" "title must contain at least one ASCII letter or digit" "flow: new-spec empty-slug error names the rule"
	assert_eq "$(ls -A .specs 2>/dev/null || true)" "$before_specs" "flow: new-spec empty-slug does not create a spec dir"
	assert_eq "$([ -f .claude/flow.json ] && echo yes || echo no)" "$before_flow" "flow: new-spec empty-slug does not write flow.json"
	cd "$prevdir" || true
}

t_flow_new_spec_checkout_failure_no_writes() {
	local repo prevdir
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec checkout-failure setup cd"
		cd "$prevdir" || true
		return
	}
	# Pre-create the branch new-spec will try to `checkout -b`, so git fails.
	git branch flow/dup-title-feature >/dev/null 2>&1
	run_cmd "$SCAN_DIR/new-spec" "Dup Title Feature"
	assert_rc 1 "flow: new-spec exits 1 when git checkout -b fails"
	assert_contains "$ERR" "git checkout -b failed" "flow: new-spec prints the checkout failure"
	assert_file_missing ".specs/001-dup-title-feature" "flow: new-spec does not create the spec dir on checkout failure"
	assert_file_missing ".claude/flow.json" "flow: new-spec does not write flow.json on checkout failure"
	cd "$prevdir" || true
}

t_flow_new_spec_worktree_failure_no_writes() {
	local repo prevdir toplevel wtpath
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: new-spec worktree-failure setup cd"
		cd "$prevdir" || true
		return
	}
	toplevel=$(git rev-parse --show-toplevel)
	wtpath="$toplevel/../code-worktrees/flow/dup-worktree-feature"
	mkdir -p "$wtpath"
	printf 'occupied\n' >"$wtpath/blocker.txt"
	run_cmd "$SCAN_DIR/new-spec" "Dup Worktree Feature" --worktree
	assert_rc 1 "flow: new-spec exits 1 when git worktree add fails"
	assert_contains "$ERR" "git worktree add failed" "flow: new-spec prints the worktree-add failure"
	assert_file_missing ".specs/001-dup-worktree-feature" "flow: new-spec does not create the spec dir on worktree failure"
	assert_file_missing ".claude/flow.json" "flow: new-spec does not write flow.json on worktree failure"
	rm -rf "$wtpath" 2>/dev/null || true
	cd "$prevdir" || true
}

t_flow_new_spec_worktree_records_physical_path() {
	local repo prevdir suffix wtpath json_wt
	prevdir=$(pwd)
	repo=$(tmp_repo)
	suffix=$(mktemp -u "${TMPDIR:-/tmp}/wtphysXXXXXX")
	suffix=${suffix##*/}
	suffix=$(LC_ALL=C printf '%s' "$suffix" | LC_ALL=C tr '[:upper:]' '[:lower:]')
	cd "$repo" || {
		_fail "flow: new-spec worktree-physical-path setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/new-spec" "Physical Path Feature $suffix" --worktree
	assert_rc 0 "flow: new-spec --worktree physical-path rc0"
	json_wt=$(printf '%s' "$OUT" | sed -n 's/.*"worktree":"\([^"]*\)".*/\1/p')
	assert_not_contains "$json_wt" "/../" "flow: new-spec records the resolved physical worktree path, not a raw \"/../\" string"
	wtpath=$(dirname "$repo")/code-worktrees/flow/physical-path-feature-$suffix
	git worktree remove --force "$wtpath" >/dev/null 2>&1 || true
	rm -rf "$wtpath" 2>/dev/null || true
	cd "$prevdir" || true
}

t_flow_review_package_two_commits_writes_diff_no_stdout_leak() {
	local repo prevdir base out content expected_lines
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package two-commits setup cd"
		cd "$prevdir" || true
		return
	}
	base=$(git rev-parse HEAD)
	printf 'line one\nline two\n' >feature.txt
	git add feature.txt
	git commit -q -m "add feature.txt"
	out="$repo/review-out.diff"
	run_cmd "$SCAN_DIR/review-package" "$base" HEAD --out "$out"
	assert_rc 0 "flow: review-package two commits rc0"
	assert_file_exists "$out" "flow: review-package writes the diff file"
	assert_contains "$OUT" "$out" "flow: review-package prints the out path on stdout"
	assert_not_contains "$OUT" "diff --git" "flow: review-package never prints the diff body to stdout"
	content=$(cat "$out")
	assert_contains "$content" "add feature.txt" "flow: review-package diff file has the commit log"
	assert_contains "$content" "diff --git" "flow: review-package diff file has the diff body"
	expected_lines=$(wc -l <"$out" | tr -d ' ')
	assert_contains "$OUT" "$expected_lines lines" "flow: review-package prints the written file's line count on stdout"
	cd "$prevdir" || true
}

t_flow_review_package_accepts_a_dotdot_range() {
	local repo prevdir base out content
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package dotdot setup cd"
		cd "$prevdir" || true
		return
	}
	base=$(git rev-parse HEAD)
	printf 'one\n' >feature.txt
	git add feature.txt
	git commit -q -m "add feature.txt"
	out="$repo/range-out.diff"
	run_cmd "$SCAN_DIR/review-package" "$base..HEAD" --out "$out"
	assert_rc 0 "flow: review-package A..B rc0"
	content=$(cat "$out" 2>/dev/null)
	assert_contains "$content" "add feature.txt" "flow: review-package A..B reviews the range (commit log)"
	assert_contains "$content" "diff --git" "flow: review-package A..B reviews the range (diff body)"
	run_cmd "$SCAN_DIR/review-package" "$base.." --out "$out"
	assert_rc 0 "flow: review-package A.. defaults the head to HEAD"
	run_cmd "$SCAN_DIR/review-package" "$base...HEAD" --out "$out"
	assert_rc 1 "flow: review-package A...B is refused, not turned into a bad ref"
	assert_contains "$ERR$OUT" "three-dot" "flow: review-package A...B says why"
	cd "$prevdir" || true
}

t_flow_review_package_bad_ref_exit1() {
	local repo prevdir
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package bad-ref setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/review-package" "totally-bogus-ref-xyz"
	assert_rc 1 "flow: review-package exits 1 for an unresolved ref"
	cd "$prevdir" || true
}

t_flow_review_package_removes_stale_out_and_stamps_range() {
	local repo prevdir base out first
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package stale setup cd"
		cd "$prevdir" || true
		return
	}
	mkdir -p r
	printf 'STALE\n' >r/T1.diff
	run_cmd "$SCAN_DIR/review-package" HEAD HEAD --out r/T1.diff
	assert_rc 1 "flow: review-package empty diff exits 1 even with a stale --out file"
	assert_file_missing r/T1.diff "flow: review-package removes a stale --out file before it can fail"
	base=$(git rev-parse HEAD)
	printf 'y\n' >y.txt
	git add y.txt
	git commit -q -m "add y"
	out="$repo/r/T2.diff"
	run_cmd "$SCAN_DIR/review-package" "$base" HEAD --out "$out"
	assert_rc 0 "flow: review-package real range rc0 (stamp)"
	first=$(head -1 "$out")
	if printf '%s\n' "$first" | grep -Eq '^# review-package base=[0-9a-f]{40} head=[0-9a-f]{40}$'; then
		_pass "flow: review-package line 1 names the full base and head shas"
	else
		_fail "flow: review-package line 1 names the full base and head shas (got: $first)"
	fi
	cd "$prevdir" || true
}

t_flow_review_package_refuses_non_ancestor_base() {
	local repo prevdir sib out
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package ancestor setup cd"
		cd "$prevdir" || true
		return
	}
	git checkout -q -b sibling
	printf 's\n' >s.txt
	git add s.txt
	git commit -q -m "sibling work"
	sib=$(git rev-parse HEAD)
	git checkout -q -
	printf 'm\n' >m.txt
	git add m.txt
	git commit -q -m "main work"
	out="$repo/anc.diff"
	run_cmd "$SCAN_DIR/review-package" "$sib" HEAD --out "$out"
	assert_rc 3 "flow: review-package exits 3 when BASE is not an ancestor of HEAD"
	assert_contains "$ERR" "merge-base" "flow: review-package names merge-base on stderr"
	assert_file_missing "$out" "flow: review-package writes no file for a non-ancestor base"
	run_cmd "$SCAN_DIR/review-package" --help
	assert_contains "$OUT" "Exit 3" "flow: review-package --help documents exit 3"
	cd "$prevdir" || true
}

t_flow_review_package_default_out_path() {
	local repo prevdir base short_base short_head
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || {
		_fail "flow: review-package default-out setup cd"
		cd "$prevdir" || true
		return
	}
	base=$(git rev-parse HEAD)
	printf 'x\n' >x.txt
	git add x.txt
	git commit -q -m "add x"
	run_cmd "$SCAN_DIR/review-package" "$base"
	assert_rc 0 "flow: review-package default out rc0"
	short_base=$(git rev-parse --short "$base")
	short_head=$(git rev-parse --short HEAD)
	assert_file_exists ".claude/review/${short_base}..${short_head}.diff" "flow: review-package default out path matches convention"
	cd "$prevdir" || true
}

t_flow_scripts_are_well_formed() {
	local scripts s
	scripts="new-spec task-brief review-package flow-lint"
	for s in $scripts; do
		if [ -x "$SCAN_DIR/$s" ]; then
			_pass "flow: $s is executable"
		else
			_fail "flow: $s is executable" "not executable: $SCAN_DIR/$s"
		fi
		if head -1 "$SCAN_DIR/$s" | grep -q '^#!/usr/bin/env bash$'; then
			_pass "flow: $s has a portable shebang"
		else
			_fail "flow: $s has a portable shebang"
		fi
		if grep -q '^set -u' "$SCAN_DIR/$s"; then
			_pass "flow: $s sets -u"
		else
			_fail "flow: $s sets -u"
		fi
		run_cmd bash -n "$SCAN_DIR/$s"
		assert_rc 0 "flow: $s passes bash -n"
	done
}

# --reuse: a /flow:prep directory keeps its number; nothing new is created
t_flow_new_spec_reuse_prep_dir() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.specs/003-entry-tagging"
	printf '# Prep\n' >"$repo/.specs/003-entry-tagging/PREP.md"
	run_cmd bash -c 'cd "$1" && "$2" "Entry tagging" --reuse .specs/003-entry-tagging --no-branch' _ "$repo" "$SCAN_DIR/new-spec"
	assert_rc 0 "flow: new-spec --reuse rc0"
	assert_contains "$OUT" '"number":"003"' "flow: new-spec --reuse keeps the number"
	assert_contains "$OUT" '"slug":"entry-tagging"' "flow: new-spec --reuse reads the slug from the dir"
	assert_contains "$OUT" '"spec_dir":".specs/003-entry-tagging"' "flow: new-spec --reuse spec_dir is the prep dir"
	assert_eq "$(ls "$repo/.specs" | wc -l | tr -d ' ')" "1" "flow: new-spec --reuse allocates no new directory"
	run_cmd bash -c 'cd "$1" && "$2" "X" --reuse .specs/nope --no-branch' _ "$repo" "$SCAN_DIR/new-spec"
	assert_rc 1 "flow: new-spec --reuse on a missing dir exits 1"
	rm -rf "$repo"
}

# A USAGE row inside the per-task Contract block reaches the generated brief
# with no change to task-brief (it appends the whole block).
t_flow_task_brief_carries_contract_usage_row() {
	local d
	d=$(tmp_repo)
	cat >"$d/TASKS.md" <<'TASKS'
# Tasks — Usage brief
Spec: spec.md · Design: design.md · Base: HEAD · Route: dispatch · Test: `true`

## Phase 1 — Core
Goal: a thing works.
Independent test: `true`
- [ ] T007 Add the thing — files: a.py — verify: `true`
TASKS
	cat >"$d/design.md" <<'DESIGN'
# Design

## Contract for T007
```
USAGE
  out = add_thing(3)
CALLS add_thing(n) -> int
```
DESIGN
	run_cmd bash -c 'cd "$1" && "$2" TASKS.md T007 --design design.md' _ "$d" "$SCAN_DIR/task-brief"
	assert_rc 0 "flow: task-brief with a Contract block exits 0"
	assert_contains "$(cat "$d/review/T007-brief.md")" "USAGE" "flow: the brief carries the Contract's USAGE row"
	rm -rf "$d"
}

# Prior art: the brief names an existing test file to copy fixtures and style from.
_flow_prior_art_brief() { # <repo> <files-value>; prints the brief text
	local d=$1
	cat >"$d/TASKS.md" <<TASKS
# Tasks — Prior art
Spec: spec.md · Design: design.md · Base: HEAD · Route: dispatch · Test: \`true\`

## Phase 1 — Core
Goal: a thing works.
Independent test: \`true\`
- [ ] T001 Add the thing — files: $2 — verify: \`true\`
TASKS
	(cd "$d" && "$SCAN_DIR/task-brief" TASKS.md T001 >/dev/null) && cat "$d/review/T001-brief.md"
}

_flow_commit_file() { # <repo> <path>
	mkdir -p "$1/$(dirname "$2")"
	printf 'x\n' >"$1/$2"
	(cd "$1" && git add "$2" && git commit -q -m "add $2")
}

t_flow_task_brief_prior_art_matches_stem() {
	local d out
	d=$(tmp_repo)
	_flow_commit_file "$d" tests/test_tags.py
	_flow_commit_file "$d" tests/test_other.py
	out=$(_flow_prior_art_brief "$d" src/api/tags.py)
	assert_contains "$out" "Prior art: tests/test_tags.py" "flow: brief names the test whose stem matches the file"
	assert_not_contains "$out" "tests/test_other.py" "flow: an unrelated test is not named when the stem matches"
	assert_contains "$out" "copy its fixtures and style" "flow: prior art line says what to copy"
	rm -rf "$d"
}

t_flow_task_brief_prior_art_other_patterns_cap_two() {
	local d out n
	d=$(tmp_repo)
	_flow_commit_file "$d" web/tags_test.go
	_flow_commit_file "$d" web/tags.test.ts
	_flow_commit_file "$d" web/tags.spec.ts
	out=$(_flow_prior_art_brief "$d" web/tags.ts)
	n=$(printf '%s\n' "$out" | grep -c '^Prior art: ')
	assert_eq "$n" "2" "flow: at most two prior art lines"
	assert_contains "$out" "Prior art: web/tags.spec.ts" "flow: <stem>.spec.* matches"
	rm -rf "$d"
}

t_flow_task_brief_prior_art_falls_back_to_recent_test() {
	local d out
	d=$(tmp_repo)
	_flow_commit_file "$d" src/test_old.py
	_flow_commit_file "$d" src/test_new.py
	_flow_commit_file "$d" lib/test_elsewhere.py
	out=$(_flow_prior_art_brief "$d" src/zzz.py)
	assert_contains "$out" "Prior art: src/test_new.py" "flow: no stem match falls back to the newest test under the same top dir"
	assert_not_contains "$out" "lib/test_elsewhere.py" "flow: fallback stays inside the top-level dir"
	rm -rf "$d"
}

t_flow_task_brief_prior_art_none_found() {
	local d out
	d=$(tmp_repo)
	out=$(_flow_prior_art_brief "$d" src/api/tags.py)
	assert_contains "$out" "Prior art: none found" "flow: a repo with no tests says none found"
	rm -rf "$d"
}

t_flow_task_brief_prior_art_skips_test_paths() {
	local d out
	d=$(tmp_repo)
	_flow_commit_file "$d" tests/test_tags.py
	out=$(_flow_prior_art_brief "$d" tests/test_tags.py)
	assert_not_contains "$out" "Prior art: tests/test_tags.py" "flow: a test path in files: is not its own prior art"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# new-spec slug transliteration (F133)
# ---------------------------------------------------------------------------

_flow_slug_of() { # <title>; prints the slug new-spec computes, or "rc=<n>"
	local repo prevdir
	prevdir=$(pwd)
	repo=$(tmp_repo)
	cd "$repo" || return
	run_cmd "$SCAN_DIR/new-spec" "$1" --no-branch
	if [ "$RC" -eq 0 ]; then
		printf '%s' "$OUT" | sed -n 's/.*"slug":"\([^"]*\)".*/\1/p'
	else
		printf 'rc=%s' "$RC"
	fi
	cd "$prevdir" || true
}

t_flow_new_spec_slug_transliterates_icelandic() {
	assert_eq "$(_flow_slug_of 'Skráning þjónustu')" "skraning-thjonustu" "flow: new-spec slug maps Icelandic letters to ascii"
	assert_eq "$(_flow_slug_of 'ÞÐÆÖ')" "thdaeo" "flow: new-spec slug of an all-Icelandic-capitals title is not empty"
	assert_eq "$(_flow_slug_of 'Hún fór út í bæ ýmis')" "hun-for-ut-i-bae-ymis" "flow: new-spec slug maps accented vowels and ae"
}

t_flow_new_spec_slug_does_not_duplicate_input_when_iconv_fails() {
	assert_eq "$(_flow_slug_of "$(printf 'abc def \351 tail')")" "abc-def-tail" "flow: new-spec slug does not duplicate the title when iconv fails on a Latin-1 byte"
}

t_flow_new_spec_slug_still_exits_1_when_nothing_survives() {
	assert_eq "$(_flow_slug_of '!!! ... ---')" "rc=1" "flow: new-spec still exits 1 when nothing survives the ascii filter"
}

t_flow_new_spec_usage_names_transliteration() {
	run_cmd "$SCAN_DIR/new-spec" --help
	assert_contains "$OUT" "Icelandic letters are transliterated" "flow: new-spec usage documents transliteration"
}

# ---------------------------------------------------------------------------
# gates.yml secrets step (F131)
# ---------------------------------------------------------------------------

t_flow_gates_template_has_redacted_secrets_step() {
	local proj home gates
	proj=$(tmp_dir)
	home=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"vitest run"}}\n' >"$proj/package.json"
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; unset DOTFILES; node "$3" init' _ "$proj" "$home" "$SCAN_DIR/../bin/flow"
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "- name: secrets" "flow: rendered gates.yml has a secrets step"
	assert_contains "$(printf '%s\n' "$gates" | sed -n '/- name: secrets/,$p')" "gitleaks detect" "flow: secrets step runs gitleaks detect"
	assert_contains "$(printf '%s\n' "$gates" | sed -n '/- name: secrets/,$p')" "--redact" "flow: secrets step redacts findings"
	assert_not_contains "$gates" "gitleaks-action" "flow: secrets step avoids gitleaks-action (needs a licence secret on orgs)"
	assert_not_contains "$gates" "osv-scanner" "flow: dependency scan is not a blocking gate"
	rm -rf "$proj" "$home"
}

t_flow_audit_gitleaks_commands_are_redacted() {
	local bad
	bad=$(grep -rnE 'gitleaks (detect|git|dir|protect)' "$SCAN_DIR/../../flow-extras/skills/audit" | grep -v -e '--redact' || true)
	assert_eq "$bad" "" "flow: every gitleaks command under audit passes --redact"
}

# ---------------------------------------------------------------------------
# audit coverage ledger and test prefilter (F170, F171)
# ---------------------------------------------------------------------------

_flow_audit_dir() { printf '%s' "$SCAN_DIR/../../flow-extras/skills/audit"; }

_flow_audit_fixture() { # prints a git repo with dirs src/, lib/ and a root file
	local d
	d=$(tmp_repo)
	mkdir -p "$d/src" "$d/lib"
	printf 'x\n' >"$d/src/a.ts"
	printf 'y\n' >"$d/lib/b.ts"
	printf 'z\n' >"$d/README.md"
	git -C "$d" add -A >/dev/null 2>&1
	git -C "$d" -c user.email=t@t -c user.name=t commit -qm fixture >/dev/null 2>&1
	printf '%s' "$d"
}

t_flow_audit_coverage_names_unlisted_dir() {
	local d
	d=$(_flow_audit_fixture)
	cat >"$d/plan.md" <<'EOF'
## Scanned
| Dir | Why |
|-----|-----|
| src | hot-spot |
| . | root files |

## Skipped
| Dir | Reason |
|-----|--------|
EOF
	run_cmd bash "$(_flow_audit_dir)/scripts/audit-coverage.sh" "$d/plan.md" "$d"
	assert_rc 1 "flow: audit-coverage exits 1 when a top-level dir is in neither table"
	assert_contains "$OUT$ERR" "lib" "flow: audit-coverage names the unlisted dir"
	rm -rf "$d"
}

t_flow_audit_coverage_accepts_skipped_with_reason() {
	local d
	d=$(_flow_audit_fixture)
	cat >"$d/plan.md" <<'EOF'
## Scanned
| Dir | Why |
|-----|-----|
| `src/` | hot-spot |
| . | root files |

## Skipped
| Dir | Reason |
|-----|--------|
| lib | sampled out: medium tier, no churn |
EOF
	run_cmd bash "$(_flow_audit_dir)/scripts/audit-coverage.sh" "$d/plan.md" "$d"
	assert_rc 0 "flow: audit-coverage exits 0 when the dir is listed as Skipped with a reason"
	rm -rf "$d"
}

t_flow_audit_coverage_accepts_bold_labels() {
	local d
	d=$(_flow_audit_fixture)
	cat >"$d/plan.md" <<'EOF'
- **Scanned**:

| Dir | Why |
|-----|-----|
| src | hot |
| . | root |

- **Skipped**:

| Dir | Reason |
|-----|--------|
| lib | sampled out |
EOF
	run_cmd bash "$(_flow_audit_dir)/scripts/audit-coverage.sh" "$d/plan.md" "$d"
	assert_rc 0 "flow: audit-coverage reads tables under bold Scanned/Skipped labels"
	rm -rf "$d"
}

t_flow_audit_coverage_handles_space_and_non_ascii_dirs() {
	local d
	d=$(_flow_audit_fixture)
	mkdir -p "$d/my docs" "$d/þjónusta"
	printf 'q\n' >"$d/my docs/a.md"
	printf 'q\n' >"$d/þjónusta/b.md"
	git -C "$d" add -A >/dev/null 2>&1
	git -C "$d" -c user.email=t@t -c user.name=t commit -qm more >/dev/null 2>&1
	cat >"$d/plan.md" <<'EOF'
## Scanned
| Dir | Why |
|-----|-----|
| src | hot |
| my docs | docs |
| þjónusta | service |
| . | root |

## Skipped
| Dir | Reason |
|-----|--------|
| lib | sampled out |
EOF
	run_cmd bash "$(_flow_audit_dir)/scripts/audit-coverage.sh" "$d/plan.md" "$d"
	assert_rc 0 "flow: audit-coverage matches dirs with spaces and non-ASCII names"
	rm -rf "$d"
}

t_flow_audit_coverage_rejects_skipped_without_reason() {
	local d
	d=$(_flow_audit_fixture)
	cat >"$d/plan.md" <<'EOF'
## Scanned
| Dir | Why |
|-----|-----|
| src | hot-spot |
| . | root |

## Skipped
| Dir | Reason |
|-----|--------|
| lib | |
EOF
	run_cmd bash "$(_flow_audit_dir)/scripts/audit-coverage.sh" "$d/plan.md" "$d"
	assert_rc 1 "flow: audit-coverage exits 1 when a Skipped row has no reason"
	assert_contains "$OUT$ERR" "lib" "flow: audit-coverage names the dir with no reason"
	rm -rf "$d"
}

t_flow_audit_test_prefilter_prints_leads() {
	local d lines
	d=$(tmp_dir)
	mkdir -p "$d/tests"
	printf 'test("a", () => {\n  doThing()\n})\n' >"$d/tests/empty.test.ts"
	printf 'test("b", () => {\n  expect(f(1)).toBe(2)\n})\n' >"$d/tests/one.test.ts"
	printf 'test("b", () => {\n  expect(f(1)).toBe(2)\n})\n' >"$d/tests/two.test.ts"
	run_cmd bash "$(_flow_audit_dir)/scripts/test-prefilter.sh" "$d"
	assert_rc 0 "flow: test-prefilter exits 0"
	lines=$(printf '%s\n' "$OUT" | grep -c '^NO_ASSERTION:' || true)
	assert_eq "$lines" "1" "flow: test-prefilter prints exactly one NO_ASSERTION line"
	assert_contains "$OUT" "NO_ASSERTION:tests/empty.test.ts" "flow: test-prefilter names the assertion-free file relative to the dir"
	lines=$(printf '%s\n' "$OUT" | grep -c '^NEAR_DUPLICATE:' || true)
	assert_eq "$lines" "1" "flow: test-prefilter prints exactly one NEAR_DUPLICATE line"
	assert_contains "$OUT" "NEAR_DUPLICATE:tests/one.test.ts tests/two.test.ts" "flow: test-prefilter pairs the identical files"
	rm -rf "$d"
}

t_flow_audit_templates_and_rules_carry_new_sections() {
	local a
	a=$(_flow_audit_dir)
	assert_contains "$(cat "$a/references/finding-schema.md")" "Not investigated" "flow: audit report templates have a Not investigated section"
	assert_eq "$(grep -c 'Not investigated' "$a/references/finding-schema.md" | tr -d ' ')" "2" "flow: Not investigated appears in both report templates"
	assert_contains "$(cat "$a/references/fix-safety.md")" "worktree" "flow: fix-safety asks for a scratch worktree build proof"
	assert_contains "$(cat "$a/references/finding-schema.md")" "retirement card" "flow: finding-schema defines the test retirement card"
	assert_contains "$(cat "$a/SKILL.md")" "audit-coverage.sh" "flow: audit SKILL runs the coverage ledger check"
	assert_contains "$(cat "$a/SKILL.md")" "second-look" "flow: audit SKILL has a second-look pass"
	assert_contains "$(cat "$a/SKILL.md")" "refute" "flow: audit SKILL has a refute pass"
	assert_contains "$(cat "$a/references/orchestration.md")" "test-prefilter.sh" "flow: orchestration passes prefilter leads to the tests agent"
}

# ---------------------------------------------------------------------------
# playbook additions (F172, F173)
# ---------------------------------------------------------------------------

t_flow_audit_playbooks_carry_vercel_entries() {
	local a lp ts py
	a=$(_flow_audit_dir)
	lp=$(cat "$a/references/language-playbooks.md")
	ts=$(printf '%s\n' "$lp" | sed -n '/^## TypeScript/,/^## Rust/p')
	py=$(printf '%s\n' "$lp" | sed -n '/^## Python/,/^## TypeScript/p')
	assert_contains "$ts" "per-item" "flow: TS playbook has per-item promise chaining"
	assert_contains "$ts" "optimizePackageImports" "flow: TS playbook has optimizePackageImports"
	assert_contains "$ts" "lastIndex" "flow: TS playbook has the /g regex lastIndex trap"
	assert_contains "$py" "TaskGroup" "flow: Python playbook keeps TaskGroup"
	assert_contains "$py" "start-early" "flow: Python playbook has the start-early entry"
	assert_eq "$(printf '%s\n' "$py" | grep -c 'gather(' | tr -d ' ')" "4" "flow: Python playbook adds no new gather( call (4 existing)"
	assert_contains "$lp" "vercel-labs/agent-skills" "flow: playbook credits vercel-labs/agent-skills"
	assert_contains "$lp" "module-level" "flow: language-playbooks flags module-level shared state"
}

t_flow_server_action_and_module_state_entries() {
	local a vc
	a=$(_flow_audit_dir)
	vc="$SCAN_DIR/../../tooling/skills/pentest/references/vuln-cookbook.md"
	assert_contains "$(cat "$a/references/security-playbook.md")" "use server" "flow: security playbook has the Server Action auth rule"
	assert_contains "$(cat "$vc")" "use server" "flow: vuln-cookbook has the Server Action auth entry"
	assert_contains "$(cat "$vc")" "module-level" "flow: vuln-cookbook has the module-level shared state entry"
}
