#!/usr/bin/env bash
# test_doctor_hygiene.sh — unit T006 (flow doctor worktree-hygiene check, B7).
# Sourced by run.sh; every t_hyg_* function below is discovered and run.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on any other test_*.sh having been
# sourced in the same run. $HERE and $SCAN_DIR come from run.sh itself.
set -u

HYG_LIB_DIR=$(cd "$SCAN_DIR/../bin/lib" && pwd -P)
export HYG_LIB_DIR

HYG_CLI_PATH=""
HYG_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
HYG_CLI_PATH="$HYG_CLI_PATH/bin/.local/bin/flow"; [ -x "$SCAN_DIR/../bin/flow" ] && HYG_CLI_PATH="$SCAN_DIR/../bin/flow"

# hyg_node <js> — run node with HYG_LIB_DIR in the environment for require().
hyg_node() {
	run_cmd node -e "$1"
}

# hyg_check <cwd> — calls worktreeHygieneCheck(push, cwd) directly (bypasses
# flow doctor's other ~20 checks), collecting rows as a JSON array into OUT.
hyg_check() {
	HYG_CWD="$1" hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.worktreeHygieneCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, process.env.HYG_CWD);
process.stdout.write(JSON.stringify(rows));
'
}

# hyg_cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $HYG_CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>.
hyg_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$HYG_CLI_PATH" "$@"
}

# hyg_days_ago_touch_stamp <days> — touch -t timestamp (local time,
# CCYYMMDDhhmm.SS) for `now - <days>`. Computed with node, never date -d/-v.
hyg_days_ago_touch_stamp() {
	node -e '
const d = new Date(Date.now() - Number(process.argv[1]) * 86400000);
const p = function (n) { return String(n).padStart(2, "0"); };
process.stdout.write(
  String(d.getFullYear()) + p(d.getMonth() + 1) + p(d.getDate()) +
  p(d.getHours()) + p(d.getMinutes()) + "." + p(d.getSeconds())
);
' "$1"
}

# hyg_days_ago_git_date <days> — "<epoch-seconds> +0000" for
# GIT_AUTHOR_DATE/GIT_COMMITTER_DATE, `now - <days>`. Computed with node.
hyg_days_ago_git_date() {
	node -e '
process.stdout.write(String(Math.floor((Date.now() - Number(process.argv[1]) * 86400000) / 1000)) + " +0000");
' "$1"
}

# hyg_add_worktree <repo> <branch> <path> — a clean worktree at the repo's
# current HEAD (merged with base by construction: same commit).
hyg_add_worktree() {
	local repo branch path
	repo=$1
	branch=$2
	path=$3
	(cd "$repo" && git worktree add -q -b "$branch" "$path") >/dev/null 2>&1
}

# hyg_commit_extra <path> <days-ago> — one extra commit ahead of base in the
# worktree at <path>, dated <days-ago> days back. The added file is named
# after <path>'s own basename so sibling worktrees branched from each other
# (e.g. unmerged-old branching from merged's fast-forwarded tip) always add
# genuinely new content instead of silently no-op-ing on a file that already
# exists in their history.
hyg_commit_extra() {
	local path days gitdate marker
	path=$1
	days=$2
	gitdate=$(hyg_days_ago_git_date "$days")
	marker=$(basename "$path")
	printf '%s\n' "$marker" >"$path/extra-$marker.txt"
	(cd "$path" && git add "extra-$marker.txt") >/dev/null 2>&1
	(cd "$path" && GIT_AUTHOR_DATE="$gitdate" GIT_COMMITTER_DATE="$gitdate" git commit -q -m "extra work ($marker)") >/dev/null 2>&1
}

# hyg_age_dir <path> <days-ago> — sets <path>'s own mtime; call last, after
# any commits/checkouts that would otherwise bump it back to "now".
hyg_age_dir() {
	local path days stamp
	path=$1
	days=$2
	stamp=$(hyg_days_ago_touch_stamp "$days")
	touch -t "$stamp" "$path"
}

# ---------------------------------------------------------------------------
# worktree-hygiene (T006, B7)
# ---------------------------------------------------------------------------

t_hyg_three_worktrees_exactly_two_warn() {
	local repo merged unmerged_old fresh rows warn_count merged_rel unmerged_rel fresh_rel
	repo=$(tmp_repo)
	merged="$repo/.claude/worktrees/merged"
	unmerged_old="$repo/.claude/worktrees/unmerged-old"
	fresh="$repo/.claude/worktrees/fresh"

	# merged + clean, idle 2 days: a commit dated 2 days back, then
	# fast-forwarded into base so it stays an ancestor of base's HEAD.
	hyg_add_worktree "$repo" hyg-merged "$merged"
	hyg_commit_extra "$merged" 2
	git -C "$repo" merge -q --ff-only hyg-merged >/dev/null 2>&1
	hyg_age_dir "$merged" 2

	# unmerged, idle 20 days: one commit ahead of base.
	hyg_add_worktree "$repo" hyg-unmerged-old "$unmerged_old"
	hyg_commit_extra "$unmerged_old" 20
	hyg_age_dir "$unmerged_old" 20

	# unmerged, fresh: one commit ahead of base, no aging — must not warn.
	hyg_add_worktree "$repo" hyg-fresh "$fresh"
	hyg_commit_extra "$fresh" 0

	hyg_check "$repo"
	rows="$OUT"
	# git canonicalizes worktree paths (/var -> /private/var on macOS), so
	# assertions match the path's stable suffix, never the raw bash variable.
	merged_rel=${merged#"$repo"}
	unmerged_rel=${unmerged_old#"$repo"}
	fresh_rel=${fresh#"$repo"}
	warn_count=$(printf '%s' "$rows" | grep -o '"status":"WARN"' | wc -l | tr -d ' ')
	assert_eq "$warn_count" "2" "t_hyg_three_worktrees_exactly_two_warn warn-count"
	assert_contains "$rows" "$merged_rel (branch hyg-merged) is merged and clean" "t_hyg_three_worktrees_exactly_two_warn merged-clean-wording"
	assert_contains "$rows" "safe to remove: git worktree remove" "t_hyg_three_worktrees_exactly_two_warn merged-fix-command"
	assert_contains "$rows" "$unmerged_rel idle 20d (1 commits not in base, clean)" "t_hyg_three_worktrees_exactly_two_warn commits-not-in-base-wording"
	assert_contains "$rows" "review, then: git worktree remove" "t_hyg_three_worktrees_exactly_two_warn unmerged-fix-command"
	assert_not_contains "$rows" "$fresh_rel" "t_hyg_three_worktrees_exactly_two_warn fresh-worktree-not-reported"

	git -C "$repo" worktree remove --force "$merged" >/dev/null 2>&1 || true
	git -C "$repo" worktree remove --force "$unmerged_old" >/dev/null 2>&1 || true
	git -C "$repo" worktree remove --force "$fresh" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

t_hyg_cwd_worktree_excluded_yields_pass() {
	# The same merged+clean+idle fixture that warns in the test above must
	# yield zero WARNs, and a single PASS row, when cwd IS that worktree.
	local repo self rows
	repo=$(tmp_repo)
	self="$repo/.claude/worktrees/self"
	hyg_add_worktree "$repo" hyg-self "$self"
	hyg_age_dir "$self" 2

	hyg_check "$self"
	rows="$OUT"
	assert_not_contains "$rows" "WARN" "t_hyg_cwd_worktree_excluded_yields_pass no-warn-for-own-worktree"
	assert_contains "$rows" '"status":"PASS"' "t_hyg_cwd_worktree_excluded_yields_pass pass-row-present"

	git -C "$repo" worktree remove --force "$self" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

t_hyg_non_git_dir_gives_no_rows() {
	local dir
	dir=$(tmp_dir)
	hyg_check "$dir"
	assert_eq "$OUT" "[]" "t_hyg_non_git_dir_gives_no_rows empty-rows"
	rm -rf "$dir"
}

t_hyg_doctor_json_carries_row() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	hyg_cli_in "$proj" "$home" doctor --json
	assert_contains "$OUT" '"id": "worktree-hygiene"' "t_hyg_doctor_json_carries_row row-present"
	rm -rf "$home" "$proj"
}
