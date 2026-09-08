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
