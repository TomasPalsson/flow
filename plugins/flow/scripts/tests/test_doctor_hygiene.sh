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

t_hyg_dirty_tracked_edit_reports_count() {
	local repo wt rows
	repo=$(tmp_repo)
	wt="$repo/.claude/worktrees/dirty-tracked"
	hyg_add_worktree "$repo" hyg-dirty-tracked "$wt"
	hyg_commit_extra "$wt" 20
	printf 'edited\n' >>"$wt/extra-dirty-tracked.txt"
	hyg_age_dir "$wt" 20

	hyg_check "$repo"
	rows="$OUT"
	assert_contains "$rows" "tracked edits: 1 files" "t_hyg_dirty_tracked tracked-wording"
	assert_not_contains "$rows" "untracked only" "t_hyg_dirty_tracked not-untracked"
	assert_not_contains "$rows" "safe to remove" "t_hyg_dirty_tracked no-safe-claim"
	assert_not_contains "$rows" "base, dirty)" "t_hyg_dirty_tracked no-bare-dirty"

	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

t_hyg_dirty_untracked_only_names_files() {
	local repo wt rows i
	repo=$(tmp_repo)
	wt="$repo/.claude/worktrees/dirty-untracked"
	hyg_add_worktree "$repo" hyg-dirty-untracked "$wt"
	hyg_commit_extra "$wt" 20
	printf 'new\n' >"$wt/brand-new.txt"
	hyg_age_dir "$wt" 20

	hyg_check "$repo"
	rows="$OUT"
	assert_contains "$rows" "untracked only: brand-new.txt" "t_hyg_dirty_untracked names-file"
	assert_not_contains "$rows" "tracked edits" "t_hyg_dirty_untracked not-tracked"
	assert_not_contains "$rows" "safe to remove" "t_hyg_dirty_untracked no-safe-claim"

	# More than 5 untracked files: five names, then a +K more tail.
	for i in 1 2 3 4 5 6 7; do printf 'x\n' >"$wt/many-$i.txt"; done
	hyg_age_dir "$wt" 20
	hyg_check "$repo"
	rows="$OUT"
	assert_contains "$rows" ", +3 more" "t_hyg_dirty_untracked more-tail"

	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
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

# ---------------------------------------------------------------------------
# personal-paths (T007, B8)
# ---------------------------------------------------------------------------

# pp_check <repoRoot> — calls personalPathsCheck(push, repoRoot) directly,
# collecting rows as a JSON array into OUT.
pp_check() {
	PP_REPO_ROOT="$1" hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.personalPathsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, process.env.PP_REPO_ROOT);
process.stdout.write(JSON.stringify(rows));
'
}

t_doctor_personal_paths_leak_warns_with_location() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/demo/skills"
	printf 'intro\nsee /Users/alice/work for details\n' >"$repo/plugins/demo/skills/LEAK.md"

	pp_check "$repo"
	rows="$OUT"
	assert_contains "$rows" '"status":"WARN"' "t_doctor_personal_paths_leak_warns_with_location warn-status"
	assert_contains "$rows" "plugins/demo/skills/LEAK.md:2: personal path /Users/alice/ — use \$HOME, ~ or \${CLAUDE_PLUGIN_ROOT}" "t_doctor_personal_paths_leak_warns_with_location file-and-line"

	rm -rf "$repo"
}

t_doctor_personal_paths_excluded_names_pass() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/demo/skills"
	printf 'see /Users/you/example\nand /home/runner/example\n' >"$repo/plugins/demo/skills/OK.md"

	pp_check "$repo"
	rows="$OUT"
	assert_not_contains "$rows" "WARN" "t_doctor_personal_paths_excluded_names_pass no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_doctor_personal_paths_excluded_names_pass pass-row"

	rm -rf "$repo"
}

t_doctor_personal_paths_binary_file_ignored() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/demo/skills"
	printf '/Users/alice/work\0binary\n' >"$repo/plugins/demo/skills/BIN.md"

	pp_check "$repo"
	rows="$OUT"
	assert_not_contains "$rows" "WARN" "t_doctor_personal_paths_binary_file_ignored no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_doctor_personal_paths_binary_file_ignored pass-row"

	rm -rf "$repo"
}

t_doctor_personal_paths_real_repo_root_pass() {
	local rows
	hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.personalPathsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, hygiene.REPO_ROOT);
process.stdout.write(JSON.stringify(rows));
'
	rows="$OUT"
	assert_not_contains "$rows" '"status":"WARN"' "t_doctor_personal_paths_real_repo_root_pass no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_doctor_personal_paths_real_repo_root_pass pass-row"
}

# The exclusion is a path-segment match (a dir literally named "fixtures"
# whose parent is literally named "tests"), not a string suffix — a dir that
# merely ends in "tests/fixtures" (e.g. .../unittests/fixtures) must still be
# walked and its leaks reported.
t_doctor_personal_paths_fixture_exclusion_is_segment_exact() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/demo/skills/unittests/fixtures"
	printf 'see /Users/alice/work\n' >"$repo/plugins/demo/skills/unittests/fixtures/LEAK.md"
	mkdir -p "$repo/plugins/demo/hooks/tests/fixtures"
	printf 'see /Users/alice/work\n' >"$repo/plugins/demo/hooks/tests/fixtures/LEAK.md"

	pp_check "$repo"
	rows="$OUT"
	assert_contains "$rows" "plugins/demo/skills/unittests/fixtures/LEAK.md:1: personal path /Users/alice/ — use \$HOME, ~ or \${CLAUDE_PLUGIN_ROOT}" "t_doctor_personal_paths_fixture_exclusion_is_segment_exact suffix-match-still-warns"
	assert_not_contains "$rows" "plugins/demo/hooks/tests/fixtures/LEAK.md" "t_doctor_personal_paths_fixture_exclusion_is_segment_exact exact-tests-fixtures-ignored"

	rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# reference-docs (T008, B9)
# ---------------------------------------------------------------------------

# rd_check <repoRoot> — calls referenceDocsCheck(push, repoRoot) directly,
# collecting rows as a JSON array into OUT.
rd_check() {
	RD_REPO_ROOT="$1" hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.referenceDocsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, process.env.RD_REPO_ROOT);
process.stdout.write(JSON.stringify(rows));
'
}

t_doctor_reference_docs_missing_section_warns() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/flow/hooks" "$repo/docs/reference"
	printf '#!/usr/bin/env bash\n' >"$repo/plugins/flow/hooks/foo.sh"
	printf '# Hooks\n' >"$repo/docs/reference/hooks.md"

	rd_check "$repo"
	rows="$OUT"
	assert_contains "$rows" '"status":"WARN"' "t_doctor_reference_docs_missing_section_warns warn-status"
	assert_contains "$rows" "hooks.md has no section for foo.sh" "t_doctor_reference_docs_missing_section_warns wording"

	rm -rf "$repo"
}

t_doctor_reference_docs_stale_section_warns() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/docs/reference"
	printf '# Hooks\n' >"$repo/docs/reference/hooks.md"
	printf '# Scripts\n\n## ghost\n\n```\nghost --help\n```\n' >"$repo/docs/reference/scripts.md"

	rd_check "$repo"
	rows="$OUT"
	assert_contains "$rows" '"status":"WARN"' "t_doctor_reference_docs_stale_section_warns warn-status"
	assert_contains "$rows" "scripts.md documents ghost, which does not exist" "t_doctor_reference_docs_stale_section_warns wording"

	rm -rf "$repo"
}

t_doctor_reference_docs_matched_fixture_pass() {
	local repo rows
	repo=$(tmp_dir)
	mkdir -p "$repo/plugins/flow/hooks" "$repo/plugins/flow/scripts" "$repo/docs/reference"
	printf '#!/usr/bin/env bash\n' >"$repo/plugins/flow/hooks/a.sh"
	printf '#!/usr/bin/env bash\n' >"$repo/plugins/flow/hooks/b.sh"
	printf '#!/usr/bin/env bash\necho c\n' >"$repo/plugins/flow/scripts/c"
	printf '#!/usr/bin/env bash\necho d\n' >"$repo/plugins/flow/scripts/d"
	chmod +x "$repo/plugins/flow/scripts/c" "$repo/plugins/flow/scripts/d"
	printf '# Hooks\n\n## a.sh\n\n```\na.sh — PreToolUse hook.\n```\n\n## b.sh\n\n```\nb.sh — PreToolUse hook.\n```\n' >"$repo/docs/reference/hooks.md"
	printf '# Scripts\n\n## c\n\n```\nUsage: c\n```\n\n## d\n\n```\nUsage: d\n```\n' >"$repo/docs/reference/scripts.md"

	rd_check "$repo"
	rows="$OUT"
	assert_not_contains "$rows" "WARN" "t_doctor_reference_docs_matched_fixture_pass no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_doctor_reference_docs_matched_fixture_pass pass-row"

	rm -rf "$repo"
}

t_doctor_reference_docs_real_repo_root_pass() {
	local rows
	hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.referenceDocsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, hygiene.REPO_ROOT);
process.stdout.write(JSON.stringify(rows));
'
	rows="$OUT"
	assert_not_contains "$rows" '"status":"WARN"' "t_doctor_reference_docs_real_repo_root_pass no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_doctor_reference_docs_real_repo_root_pass pass-row"
}

t_hyg_squash_merged_clean_worktree_is_safe_to_prune() {
	# A squash-merged branch is not an ancestor of base, but its changes are
	# already there; git cherry sees that without network or gh.
	local repo wt rows rel
	repo=$(tmp_repo)
	wt="$repo/.claude/worktrees/squashed"
	hyg_add_worktree "$repo" hyg-squashed "$wt"
	hyg_commit_extra "$wt" 2
	(cd "$repo" && git merge -q --squash hyg-squashed && git commit -q -m "squash hyg-squashed") >/dev/null 2>&1
	hyg_age_dir "$wt" 2

	hyg_check "$repo"
	rows="$OUT"
	rel=${wt#"$repo"}
	assert_contains "$rows" "$rel (branch hyg-squashed) is merged and clean" "t_hyg_squash_merged safe-to-prune"
	assert_contains "$rows" "safe to remove: git worktree remove" "t_hyg_squash_merged fix-command"

	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

t_hyg_multi_commit_squash_merged_is_safe_to_prune() {
	# Several branch commits squashed into one base commit (plus an unrelated
	# base commit afterwards): per-commit git cherry sees nothing, the whole
	# branch diff's patch-id still matches the squash commit.
	local repo wt rows rel
	repo=$(tmp_repo)
	wt="$repo/.claude/worktrees/multisq"
	hyg_add_worktree "$repo" hyg-multisq "$wt"
	hyg_commit_extra "$wt" 2
	printf 'second\n' >"$wt/second.txt"
	(cd "$wt" && git add second.txt && GIT_AUTHOR_DATE="$(hyg_days_ago_git_date 2)" GIT_COMMITTER_DATE="$(hyg_days_ago_git_date 2)" git commit -q -m "second commit") >/dev/null 2>&1
	(cd "$repo" && git merge -q --squash hyg-multisq && git commit -q -m "squash hyg-multisq") >/dev/null 2>&1
	printf 'unrelated\n' >"$repo/unrelated.txt"
	(cd "$repo" && git add unrelated.txt && git commit -q -m "unrelated main work") >/dev/null 2>&1
	hyg_age_dir "$wt" 2

	hyg_check "$repo"
	rows="$OUT"
	rel=${wt#"$repo"}
	assert_contains "$rows" "$rel (branch hyg-multisq) is merged and clean" "t_hyg_multi_commit_squash safe-to-prune"

	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

t_hyg_squash_merged_but_extra_commit_is_not_safe() {
	local repo wt rows
	repo=$(tmp_repo)
	wt="$repo/.claude/worktrees/partial"
	hyg_add_worktree "$repo" hyg-partial "$wt"
	hyg_commit_extra "$wt" 2
	(cd "$repo" && git merge -q --squash hyg-partial && git commit -q -m "squash hyg-partial") >/dev/null 2>&1
	printf 'later\n' >"$wt/later.txt"
	(cd "$wt" && git add later.txt && git commit -q -m "later work") >/dev/null 2>&1
	hyg_age_dir "$wt" 2

	hyg_check "$repo"
	rows="$OUT"
	assert_not_contains "$rows" "is merged and clean" "t_hyg_squash_partial not-reported-safe"

	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
	rm -rf "$repo"
}

# ---------------------------------------------------------------------------
# duplicate-skills (F24): the same skill name loaded from two on-disk sources
# ---------------------------------------------------------------------------

# dup_check <home> <project> — calls duplicateSkillsCheck(push, home, project).
dup_check() {
	DUP_HOME="$1" DUP_PROJ="$2" hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.duplicateSkillsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, process.env.DUP_HOME, process.env.DUP_PROJ);
process.stdout.write(JSON.stringify(rows));
'
}

# dup_skill <plugin-dir> <skill...> — a plugin dir exposing the named skills.
dup_skill() {
	local dir n
	dir=$1
	shift
	for n in "$@"; do
		mkdir -p "$dir/skills/$n"
		printf -- '---\nname: %s\ndescription: x\n---\n' "$n" >"$dir/skills/$n/SKILL.md"
	done
}

# dup_install <home> <key> <installPath> — one installed_plugins.json entry.
dup_install() {
	mkdir -p "$1/.claude/plugins"
	printf '{"version":2,"plugins":{"%s":[{"scope":"user","installPath":"%s"}]}}\n' "$2" "$3" >"$1/.claude/plugins/installed_plugins.json"
}

# dup_warn_count <rows-json> — number of WARN rows.
dup_warn_count() {
	printf '%s' "$1" | grep -o '"status":"WARN"' | wc -l | tr -d ' '
}

t_dup_skills_same_name_in_two_plugins_warns_once_naming_both() {
	local home proj rows
	home=$(tmp_dir)
	proj=$(tmp_dir)
	dup_skill "$home/store/alpha" audit
	dup_skill "$home/store/beta" audit
	mkdir -p "$home/.claude/skills"
	ln -s "$home/store/alpha" "$home/.claude/skills/alpha"
	dup_install "$home" "beta@mkt" "$home/store/beta"

	dup_check "$home" "$proj"
	rows="$OUT"
	assert_contains "$rows" "skill audit loads from both" "t_dup_skills_two_plugins row"
	assert_contains "$rows" "skills-dir alpha" "t_dup_skills_two_plugins source-a"
	assert_contains "$rows" "beta@mkt" "t_dup_skills_two_plugins source-b"
	assert_eq "$(dup_warn_count "$rows")" "1" "t_dup_skills_two_plugins one-row"
	rm -rf "$home" "$proj"
}

t_dup_skills_whole_plugin_duplicated_collapses_to_one_row() {
	local home proj rows
	home=$(tmp_dir)
	proj=$(tmp_dir)
	dup_skill "$home/src/tooling" lint fmt test
	dup_skill "$home/cache/tooling" lint fmt test
	mkdir -p "$home/.claude/skills"
	ln -s "$home/src/tooling" "$home/.claude/skills/tooling"
	dup_install "$home" "tooling@flow" "$home/cache/tooling"

	dup_check "$home" "$proj"
	rows="$OUT"
	assert_contains "$rows" "plugin tooling loads from both skills-dir and tooling@flow" "t_dup_skills_collapse row"
	assert_eq "$(dup_warn_count "$rows")" "1" "t_dup_skills_collapse one-row"
	rm -rf "$home" "$proj"
}

t_dup_skills_same_directory_twice_is_not_a_duplicate() {
	local home proj rows
	home=$(tmp_dir)
	proj=$(tmp_dir)
	dup_skill "$home/store/alpha" audit
	mkdir -p "$home/.claude/skills"
	ln -s "$home/store/alpha" "$home/.claude/skills/alpha"
	dup_install "$home" "alpha@mkt" "$home/store/alpha"

	dup_check "$home" "$proj"
	rows="$OUT"
	assert_not_contains "$rows" '"status":"WARN"' "t_dup_skills_same_dir no-warn"
	assert_contains "$rows" '"status":"PASS"' "t_dup_skills_same_dir pass"
	rm -rf "$home" "$proj"
}

t_dup_skills_project_skill_clashing_with_plugin_warns() {
	local home proj rows
	home=$(tmp_dir)
	proj=$(tmp_dir)
	dup_skill "$home/store/beta" audit
	dup_install "$home" "beta@mkt" "$home/store/beta"
	mkdir -p "$proj/.claude/skills/audit"
	printf -- '---\nname: audit\ndescription: x\n---\n' >"$proj/.claude/skills/audit/SKILL.md"

	dup_check "$home" "$proj"
	rows="$OUT"
	assert_contains "$rows" "skill audit loads from both" "t_dup_skills_project warn"
	assert_contains "$rows" "project .claude/skills" "t_dup_skills_project source"
	rm -rf "$home" "$proj"
}

t_dup_skills_no_sources_passes() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)
	dup_check "$home" "$proj"
	assert_contains "$OUT" '"status":"PASS"' "t_dup_skills_none pass"
	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# Text rules from the famous-repos round (F153, F169, F190, F191)
# ---------------------------------------------------------------------------

t_famous_babysit_bans_empty_commit_retrigger() {
	local f
	f="$SCAN_DIR/../../flow-extras/skills/babysit/SKILL.md"
	assert_contains "$(cat "$f")" "Never push an empty commit" "t_famous_babysit empty-commit rule"
	assert_contains "$(cat "$f")" "gh run rerun --failed" "t_famous_babysit flake path"
}

t_famous_benchmark_checklist_carries_rules() {
	local f w n
	f="$SCAN_DIR/../../flow-extras/skills/benchmark-checklist/SKILL.md"
	for w in 'N/A, never 0' 'is reverted' 'attempt ledger' 'geomean' 'worst shape' 'cache key correctness' 'randomized differential' 'like coverage' 'range with its assumptions' 'Say where the clock starts'; do
		assert_contains "$(cat "$f")" "$w" "t_famous_benchmark_checklist $w"
	done
	n=$(wc -l <"$f" | tr -d ' ')
	[ "$n" -le 75 ] || assert_eq "$n" "<=75" "t_famous_benchmark_checklist line-budget"
}

t_famous_find_skills_recommends_only_fetched() {
	local f
	f="$SCAN_DIR/../../flow-extras/skills/find-skills/SKILL.md"
	assert_contains "$(cat "$f")" "fetched this conversation" "t_famous_find_skills fetched rule"
	assert_contains "$(cat "$f")" "drop it and say none was found" "t_famous_find_skills caveat rule"
	assert_not_contains "$(cat "$f")" "might help" "t_famous_find_skills no-might-help"
	assert_not_contains "$(cat "$f")" "185K" "t_famous_find_skills no-remembered-count"
}

t_famous_rubric_reviewer_safety_rules() {
	local f
	f="$SCAN_DIR/../../../docs/research/23-pstack-rubric.md"
	assert_contains "$(cat "$f")" "Never invoke a git transport" "t_famous_rubric no-transports"
	assert_contains "$(cat "$f")" "python3 -I -S" "t_famous_rubric isolated-python"
	assert_contains "$(cat "$f")" "Trust only goes down" "t_famous_rubric trust-down"
	assert_contains "$(cat "$f")" "gh api repos/<o>/<r>/compare/<sha>...HEAD --method GET" "t_famous_rubric compare-api"
	assert_contains "$(cat "$f")" "layout assumptions" "t_famous_rubric b5-layout"
}

# ---------------------------------------------------------------------------
# referenced-paths (F22): backticked paths and Ruling lines that point nowhere
# ---------------------------------------------------------------------------

# rp_check <projectDir> — calls referencedPathsCheck(push, projectDir).
rp_check() {
	RP_DIR="$1" hyg_node '
const hygiene = require(process.env.HYG_LIB_DIR + "/doctor-hygiene.js");
const rows = [];
hygiene.referencedPathsCheck(function (id, status, detail) {
  rows.push({ id: id, status: status, detail: detail });
}, process.env.RP_DIR);
process.stdout.write(JSON.stringify(rows));
'
}

t_hyg_referenced_paths_missing_ruling_path_is_one_warn() {
	local d
	d=$(tmp_dir)
	printf '# Progress\nRuling: keep scripts/old.sh\n' >"$d/PROGRESS.md"
	rp_check "$d"
	assert_eq "$(dup_warn_count "$OUT")" "1" "t_hyg_referenced_paths one WARN for a Ruling line citing a missing path"
	assert_contains "$OUT" "scripts/old.sh" "t_hyg_referenced_paths WARN names the path"
	assert_contains "$OUT" '"id":"referenced-paths"' "t_hyg_referenced_paths row id"
	rm -rf "$d"
}

t_hyg_referenced_paths_existing_and_pattern_paths_pass() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/scripts"
	printf 'x\n' >"$d/scripts/old.sh"
	printf '# Progress\nRuling: keep scripts/old.sh\n' >"$d/PROGRESS.md"
	printf 'Use `src/**/*.ts` and `<path>/x.md`; entry is `scripts/old.sh`.\n' >"$d/CLAUDE.md"
	rp_check "$d"
	assert_eq "$(dup_warn_count "$OUT")" "0" "t_hyg_referenced_paths no WARN when paths exist or are patterns"
	assert_contains "$OUT" '"status":"PASS"' "t_hyg_referenced_paths PASS row"
	rm -rf "$d"
}

t_hyg_referenced_paths_silent_without_any_instruction_file() {
	local d
	d=$(tmp_dir)
	rp_check "$d"
	assert_eq "$OUT" "[]" "t_hyg_referenced_paths no row when there is no CLAUDE.md, rules or PROGRESS.md"
	rm -rf "$d"
}
