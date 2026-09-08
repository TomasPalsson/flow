#!/usr/bin/env bash
# test_flow.sh — tests for U3 scripts-flow: new-spec, slice-brief,
# review-package, slice-overlap. Sourced by tests/run.sh, which defines
# HERE (this dir) and SCAN_DIR (its parent, where the scripts live).
# All t_flow_* functions run in the same shell as run.sh (no subshell),
# so any test that changes directory restores it before returning.

t_flow_new_spec_help() {
	run_cmd "$SCAN_DIR/new-spec" --help
	assert_rc 0 "flow: new-spec --help rc0"
	assert_contains "$OUT" "Usage: new-spec" "flow: new-spec --help usage text"
}

t_flow_slice_brief_help() {
	run_cmd "$SCAN_DIR/slice-brief" --help
	assert_rc 0 "flow: slice-brief --help rc0"
	assert_contains "$OUT" "Usage: slice-brief" "flow: slice-brief --help usage text"
}

t_flow_review_package_help() {
	run_cmd "$SCAN_DIR/review-package" --help
	assert_rc 0 "flow: review-package --help rc0"
	assert_contains "$OUT" "Usage: review-package" "flow: review-package --help usage text"
}

t_flow_slice_overlap_help() {
	run_cmd "$SCAN_DIR/slice-overlap" --help
	assert_rc 0 "flow: slice-overlap --help rc0"
	assert_contains "$OUT" "Usage: slice-overlap" "flow: slice-overlap --help usage text"
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

t_flow_slice_brief_extracts_slice1() {
	local outdir out content
	outdir=$(tmp_dir)
	out="$outdir/slice1.md"
	run_cmd "$SCAN_DIR/slice-brief" "$HERE/fixtures/plan.md" 1 --out "$out"
	assert_rc 0 "flow: slice-brief extracts slice 1 rc0"
	assert_contains "$OUT" "$out" "flow: slice-brief prints the output path"
	assert_file_exists "$out" "flow: slice-brief writes the output file"
	content=$(cat "$out")
	assert_contains "$content" "## Slice 1 — Login flow" "flow: slice-brief slice1 heading present"
	assert_contains "$content" "### Slice 1 — RED" "flow: slice-brief slice1 RED present"
	assert_contains "$content" "### Slice 1 — GREEN" "flow: slice-brief slice1 GREEN present"
	assert_contains "$content" "### Slice 1 — REFACTOR" "flow: slice-brief slice1 REFACTOR present"
	assert_not_contains "$content" "## Slice 2" "flow: slice-brief slice1 excludes slice2"
}

t_flow_slice_brief_slice2_fence_decoy_boundaries() {
	local outdir out content
	outdir=$(tmp_dir)
	out="$outdir/slice2.md"
	run_cmd "$SCAN_DIR/slice-brief" "$HERE/fixtures/plan.md" 2 --out "$out"
	assert_rc 0 "flow: slice-brief extracts slice 2 rc0"
	content=$(cat "$out")
	assert_contains "$content" "## Slice 2 — Logout flow" "flow: slice-brief slice2 heading present"
	assert_contains "$content" "## Slice 9 — decoy" "flow: slice-brief slice2 includes the fenced decoy line verbatim"
	assert_contains "$content" "### Slice 2 — REFACTOR" "flow: slice-brief slice2 REFACTOR present after the fence"
	assert_not_contains "$content" "## Slice 3" "flow: slice-brief slice2 excludes slice3 (fence did not shift the boundary)"
}

t_flow_slice_brief_appends_design_contract() {
	local outdir out content
	outdir=$(tmp_dir)
	out="$outdir/slice2-with-design.md"
	run_cmd "$SCAN_DIR/slice-brief" "$HERE/fixtures/plan.md" 2 --design "$HERE/fixtures/code-design.md" --out "$out"
	assert_rc 0 "flow: slice-brief with --design rc0"
	content=$(cat "$out")
	assert_contains "$content" "## Contract for this slice — Slice 2" "flow: slice-brief appends the matching design contract"
	assert_not_contains "$content" "## Contract for this slice — Slice 1" "flow: slice-brief does not append a non-matching contract"
}

t_flow_slice_brief_missing_slice_exit1() {
	local outdir out
	outdir=$(tmp_dir)
	out="$outdir/missing.md"
	run_cmd "$SCAN_DIR/slice-brief" "$HERE/fixtures/plan.md" 99 --out "$out"
	assert_rc 1 "flow: slice-brief exits 1 for a missing slice"
}

t_flow_slice_brief_default_out_path() {
	local prevdir d
	prevdir=$(pwd)
	d=$(tmp_dir)
	cd "$d" || {
		_fail "flow: slice-brief default-out setup cd"
		cd "$prevdir" || true
		return
	}
	run_cmd "$SCAN_DIR/slice-brief" "$HERE/fixtures/plan.md" 1
	assert_rc 0 "flow: slice-brief default out rc0"
	assert_contains "$OUT" ".claude/slices/1-brief.md" "flow: slice-brief prints the default out path"
	assert_file_exists ".claude/slices/1-brief.md" "flow: slice-brief default out file exists"
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

t_flow_slice_overlap_clean_fixture_rc0() {
	run_cmd "$SCAN_DIR/slice-overlap" "$HERE/fixtures/plan.md"
	assert_rc 0 "flow: slice-overlap rc0 on non-overlapping fixture"
	assert_eq "$OUT" "" "flow: slice-overlap prints nothing when there is no overlap"
}

t_flow_slice_overlap_fence_decoy_ignored() {
	run_cmd "$SCAN_DIR/slice-overlap" "$HERE/fixtures/plan.md"
	assert_not_contains "$OUT" "decoy" "flow: slice-overlap does not react to the fenced decoy heading"
	assert_not_contains "$OUT" "Slice 9" "flow: slice-overlap does not create a bogus Slice 9 grouping"
}

t_flow_slice_overlap_fence_decoy_files_bullet_ignored() {
	# The shared fixtures/plan.md's fenced decoy has no "- **Files**:" bullet,
	# so a fence-unaware slice-overlap produces byte-identical (empty) output
	# against it and the test above never actually exercises the fence logic.
	# Build a fixture whose fenced decoy DOES carry a "- **Files**:" bullet
	# naming a file already owned by the real slice, so fence-blindness would
	# manufacture a bogus "Slice 1, Slice 9" overlap and flip both the exit
	# code and the output.
	local d f
	d=$(tmp_dir)
	f="$d/fence-files-plan.md"
	cat >"$f" <<PLANEOF
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 — First thing

- **Files**: src/real.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

Fenced block with a decoy heading and a Files bullet that a naive
line-scanner would misread as a second owner of src/real.py:

\`\`\`text
## Slice 9 — decoy
- **Files**: src/real.py
### Slice 9 — RED
### Slice 9 — GREEN
### Slice 9 — REFACTOR
\`\`\`

### Slice 1 — REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	run_cmd "$SCAN_DIR/slice-overlap" "$f"
	assert_rc 0 "flow: slice-overlap ignores a fenced decoy Files bullet (rc0, no bogus overlap)"
	assert_eq "$OUT" "" "flow: slice-overlap prints nothing when the only overlap candidate is fenced"
}

t_flow_slice_overlap_detects_real_overlap() {
	local d f
	d=$(tmp_dir)
	f="$d/overlap-plan.md"
	cat >"$f" <<PLANEOF
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 — First thing

- **Files**: src/shared.py, src/one.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

### Slice 1 — REFACTOR

refactor

## Slice 2 — Second thing

- **Files**: src/shared.py, src/two.py
- **Depends-on**: Slice 1

### Slice 2 — RED

red

### Slice 2 — GREEN

green

### Slice 2 — REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	run_cmd "$SCAN_DIR/slice-overlap" "$f"
	assert_rc 1 "flow: slice-overlap exits 1 when a file is shared"
	assert_contains "$OUT" "src/shared.py: Slice 1, Slice 2" "flow: slice-overlap reports the shared file and owning slices"
}

t_flow_slice_overlap_json_output() {
	local d f
	d=$(tmp_dir)
	f="$d/overlap-plan-json.md"
	cat >"$f" <<PLANEOF
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 — First thing

- **Files**: src/shared.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

### Slice 1 — REFACTOR

refactor

## Slice 2 — Second thing

- **Files**: src/shared.py

### Slice 2 — RED

red

### Slice 2 — GREEN

green

### Slice 2 — REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	run_cmd "$SCAN_DIR/slice-overlap" "$f" --json
	assert_rc 1 "flow: slice-overlap --json exits 1 on overlap"
	assert_contains "$OUT" '"overlaps":[{"file":"src/shared.py","slices":["Slice 1","Slice 2"]}]' "flow: slice-overlap --json emits the expected structure"
}

t_flow_slice_overlap_repeated_file_within_one_slice_no_false_positive() {
	local d f
	d=$(tmp_dir)
	f="$d/dup-within-slice-plan.md"
	cat >"$f" <<PLANEOF
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 — Only thing

- **Files**: src/a.py, src/a.py

### Slice 1 — RED

red

### Slice 1 — GREEN

green

### Slice 1 — REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	run_cmd "$SCAN_DIR/slice-overlap" "$f"
	assert_rc 0 "flow: slice-overlap rc0 when a single slice lists the same file twice"
	assert_eq "$OUT" "" "flow: slice-overlap prints nothing for a file repeated within one slice's own Files list"
}

t_flow_slice_overlap_strips_crlf() {
	# The shared file is the LAST token on each "- **Files**:" line, so an
	# awk that does not strip a trailing \r from the whole line (only
	# trims [ \t] from each split field) attaches the CR to this exact
	# token on both slices, producing a byte-identical overlap key
	# ("src/shared.py\r") on both sides — same rc=1, but the printed line
	# carries the raw CR and never equals the clean assertion below. That
	# distinguishes the fixed awk (line-level `sub(/\r$/, "", line)`) from
	# the unfixed one, unlike a fixture where the shared file is first.
	local d f lf
	d=$(tmp_dir)
	lf="$d/crlf-plan.lf.md"
	f="$d/crlf-plan.md"
	cat >"$lf" <<'PLANEOF'
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 - First thing

- **Files**: src/one.py, src/shared.py

### Slice 1 - RED

red

### Slice 1 - GREEN

green

### Slice 1 - REFACTOR

refactor

## Slice 2 - Second thing

- **Files**: src/two.py, src/shared.py
- **Depends-on**: Slice 1

### Slice 2 - RED

red

### Slice 2 - GREEN

green

### Slice 2 - REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	awk '{ printf "%s\r\n", $0 }' "$lf" >"$f"
	run_cmd "$SCAN_DIR/slice-overlap" "$f"
	assert_rc 1 "flow: slice-overlap strips CRLF and still detects a real overlap"
	assert_contains "$OUT" "src/shared.py: Slice 1, Slice 2" "flow: slice-overlap CRLF file overlap output has no trailing CR on the file name"
	assert_not_contains "$OUT" "$(printf '\r')" "flow: slice-overlap output contains no raw CR byte"
}

t_flow_slice_overlap_strips_crlf_waves() {
	# --waves runs the same OVERLAP_AWK gate first. Put the shared file
	# LAST on Slice 1's line only (Slice 2's line ends in a different
	# file), so an unfixed awk attaches a trailing CR to Slice 1's
	# "src/shared.py" but leaves Slice 2's clean copy untouched: the two
	# keys ("src/shared.py\r" vs "src/shared.py") would then look like
	# DIFFERENT files, the overlap would be missed (rc 0), and --waves
	# would wrongly compute waves for what is really one shared file.
	# The fixed awk strips the CR before the Files bullet is parsed, so
	# both copies collapse to the same key and the overlap gate blocks
	# wave computation (rc 1) — a token position where the CR fix is
	# load-bearing for the --waves entry point too.
	local d f lf
	d=$(tmp_dir)
	lf="$d/crlf-waves-plan.lf.md"
	f="$d/crlf-waves-plan.md"
	cat >"$lf" <<'PLANEOF'
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | test_thing.py::test_it |

## Slice 1 - First thing

- **Files**: src/one.py, src/shared.py

### Slice 1 - RED

red

### Slice 1 - GREEN

green

### Slice 1 - REFACTOR

refactor

## Slice 2 - Second thing

- **Files**: src/shared.py, src/two.py
- **Depends-on**: Slice 1

### Slice 2 - RED

red

### Slice 2 - GREEN

green

### Slice 2 - REFACTOR

refactor

## Gate Phases

- Phase 1: lint
PLANEOF
	awk '{ printf "%s\r\n", $0 }' "$lf" >"$f"
	run_cmd "$SCAN_DIR/slice-overlap" "$f" --waves
	assert_rc 1 "flow: slice-overlap --waves strips CRLF and still catches the overlap before computing waves"
	assert_contains "$OUT" "src/shared.py: Slice 1, Slice 2" "flow: slice-overlap --waves CRLF overlap output has no trailing CR on the file name"
	assert_not_contains "$OUT" "wave " "flow: slice-overlap --waves does not compute waves when the CRLF-hidden overlap is caught"
}

t_flow_scripts_are_well_formed() {
	local scripts s
	scripts="new-spec slice-brief review-package slice-overlap"
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
