#!/usr/bin/env bash
# test_install.sh — unit V5 (harness install) tests for `harness install` (C18).
# Sourced by run.sh; every t_install_* function below is discovered and run.
set -u

# CLI_PATH per C9/unit map: "$HERE/../../../.." is the repo root. Computed
# independently of test_cli.sh so this file also works standalone under
# TEST_ONLY=test_install.sh.
CLI_PATH=""
CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
CLI_PATH="$CLI_PATH/bin/.local/bin/harness"; [ -x "$SCAN_DIR/../bin/harness" ] && CLI_PATH="$SCAN_DIR/../bin/harness"

# _install_cli <home-dir> <harness-args...>
# Runs `node $CLI_PATH <args>` with HOME=<home-dir>, without touching this
# test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
_install_cli() {
	local home
	home=$1
	shift
	run_cmd bash -c 'export HOME="$1"; shift; exec "$@"' _ "$home" node "$CLI_PATH" "$@"
}

# _install_write_stub_dotfiles <dotfiles-dir> [hooks_key_present=1]
# A minimal stub dotfiles tree with the 9 claude/.claude/<x> items `install`
# links, plus a hooks script and a scripts script (both non-executable, so a
# chmod test has something real to observe) and the CLI's own stub location.
_install_write_stub_dotfiles() {
	local d valid_hooks
	d=$1
	valid_hooks=${2:-1}
	mkdir -p "$d/claude/.claude/skills" "$d/claude/.claude/agents" "$d/claude/.claude/commands" \
		"$d/claude/.claude/scripts/tests" "$d/claude/.claude/hooks" "$d/claude/.claude/workflows" \
		"$d/claude/.claude/harness-templates" "$d/bin/.local/bin"
	if [ "$valid_hooks" = "1" ]; then
		printf '{ "hooks": { "SessionStart": [] } }\n' >"$d/claude/.claude/settings.json"
	else
		printf '{ "notHooks": true }\n' >"$d/claude/.claude/settings.json"
	fi
	printf '# CLAUDE\n' >"$d/claude/.claude/CLAUDE.md"
	printf '#!/usr/bin/env bash\necho hook\n' >"$d/claude/.claude/hooks/session-context.sh"
	printf '#!/usr/bin/env bash\necho script\n' >"$d/claude/.claude/scripts/some-script"
	printf 'not a script\n' >"$d/claude/.claude/scripts/tests/test_x.sh"
	printf '#!/usr/bin/env node\nconsole.log("stub")\n' >"$d/bin/.local/bin/harness"
}

# _install_is_symlink <path> → "yes" or "no"
_install_is_symlink() {
	if [ -L "$1" ]; then printf 'yes'; else printf 'no'; fi
}

# _install_write_fully_wired_dotfiles <dotfiles-dir>
# Like _install_write_stub_dotfiles, but with every C5 hook file present,
# executable, and correctly wired in settings.json's "hooks" key, so
# `harness doctor`'s own checklist is fully green on a correct deployment.
# Used by tests that need doctor's own summary.fail to be 0 so an install-step
# FAIL (an item doctor's checklist doesn't independently cover, e.g.
# harness-templates or workflows) is the ONLY thing that can drive the exit
# code non-zero — otherwise an unrelated doctor FAIL (as in the minimal
# _install_write_stub_dotfiles fixture) would mask whether install's own FAIL
# is actually counted (see C18 finding on the missing exit-code contract).
_install_write_fully_wired_dotfiles() {
	local d h
	d=$1
	mkdir -p "$d/claude/.claude/skills" "$d/claude/.claude/agents" "$d/claude/.claude/commands" \
		"$d/claude/.claude/scripts/tests" "$d/claude/.claude/hooks" "$d/claude/.claude/workflows" \
		"$d/claude/.claude/harness-templates" "$d/bin/.local/bin"
	for h in session-context.sh turn-stamp.sh rtk-rewrite.sh git-guard.sh format-lint.sh \
		size-guard.sh tamper-notice.sh stop-gate.sh pre-compact-backup.sh; do
		printf '#!/usr/bin/env bash\nexit 0\n' >"$d/claude/.claude/hooks/$h"
		chmod +x "$d/claude/.claude/hooks/$h"
	done
	cat >"$d/claude/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [{"hooks":[{"command":"session-context.sh"}]}],
    "UserPromptSubmit": [{"hooks":[{"command":"turn-stamp.sh"}]}],
    "PreToolUse": [{"matcher":"Bash","hooks":[{"command":"rtk-rewrite.sh"},{"command":"git-guard.sh"}]}],
    "PostToolUse": [{"matcher":"Edit|Write|NotebookEdit","hooks":[{"command":"format-lint.sh"},{"command":"size-guard.sh"},{"command":"tamper-notice.sh"}]}],
    "Stop": [{"hooks":[{"command":"stop-gate.sh"}]}],
    "PreCompact": [{"hooks":[{"command":"pre-compact-backup.sh"}]}]
  }
}
JSON
	printf '# CLAUDE\n' >"$d/claude/.claude/CLAUDE.md"
	printf '#!/usr/bin/env node\nconsole.log("stub")\n' >"$d/bin/.local/bin/harness"
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

t_install_help_exits_0() {
	local home
	home=$(tmp_dir)

	_install_cli "$home" install --help
	assert_rc 0 "t_install_help_exits_0 rc"
	assert_contains "$OUT" "Usage:" "t_install_help_exits_0 usage-line"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# Symlink style: relative when dotfiles == $HOME/.dotfiles, else absolute
# ---------------------------------------------------------------------------

t_install_relative_symlinks_when_dotfiles_is_home_dotfiles() {
	local home link
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install
	link=$(readlink "$home/.claude/skills")
	assert_eq "$link" "../.dotfiles/claude/.claude/skills" "t_install_relative_symlinks_when_dotfiles_is_home_dotfiles skills"

	link=$(readlink "$home/.claude/settings.json")
	assert_eq "$link" "../.dotfiles/claude/.claude/settings.json" "t_install_relative_symlinks_when_dotfiles_is_home_dotfiles settings"

	link=$(readlink "$home/.local/bin/harness")
	assert_eq "$link" "../../.dotfiles/bin/.local/bin/harness" "t_install_relative_symlinks_when_dotfiles_is_home_dotfiles harness-bin"

	rm -rf "$home"
}

t_install_absolute_symlinks_when_dotfiles_elsewhere() {
	local home dotfiles link
	home=$(tmp_dir)
	dotfiles=$(tmp_dir)
	_install_write_stub_dotfiles "$dotfiles"

	_install_cli "$home" install --dotfiles "$dotfiles"
	link=$(readlink "$home/.claude/skills")
	assert_eq "$link" "$dotfiles/claude/.claude/skills" "t_install_absolute_symlinks_when_dotfiles_elsewhere skills"

	link=$(readlink "$home/.local/bin/harness")
	assert_eq "$link" "$dotfiles/bin/.local/bin/harness" "t_install_absolute_symlinks_when_dotfiles_elsewhere harness-bin"

	rm -rf "$home" "$dotfiles"
}

# A correct, fully-wired deployment with --dotfiles pointing away from
# $HOME/.dotfiles must exit 0 and doctor's own symlink recheck must PASS every
# item, not FAIL. This guards the C18 fix that threads dotfilesRoot from
# cmdInstall through cmdDoctor/buildDoctorChecks into doctorSymlinkChecks: if
# a later refactor drops that argument on the cmdDoctor(...) call inside
# cmdInstall, doctorSymlinkChecks falls back to its $HOME/.dotfiles default,
# which does not exist under this test's isolated $HOME, and every
# symlink:* check flips to FAIL with a "(not under ...)" or "does not exist"
# detail — exactly the round-1 regression this test is written to catch.
t_install_dotfiles_elsewhere_fully_wired_exits_0() {
	local home dotfiles
	home=$(tmp_dir)
	dotfiles=$(tmp_dir)
	_install_write_fully_wired_dotfiles "$dotfiles"

	_install_cli "$home" install --dotfiles "$dotfiles"
	assert_rc 0 "t_install_dotfiles_elsewhere_fully_wired_exits_0 rc"
	assert_contains "$OUT" "0 fail" "t_install_dotfiles_elsewhere_fully_wired_exits_0 doctor-checklist-clean"
	assert_not_contains "$OUT" "not under" "t_install_dotfiles_elsewhere_fully_wired_exits_0 no-symlink-root-mismatch"
	assert_not_contains "$OUT" "does not exist" "t_install_dotfiles_elsewhere_fully_wired_exits_0 no-missing-symlink"
	assert_not_contains "$OUT" "not a symlink" "t_install_dotfiles_elsewhere_fully_wired_exits_0 no-non-symlink-conflict"

	rm -rf "$home" "$dotfiles"
}

# ---------------------------------------------------------------------------
# Idempotence: a second run reports ok, not create, for already-correct links
# ---------------------------------------------------------------------------

t_install_second_run_reports_ok() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install
	_install_cli "$home" install
	assert_contains "$OUT" "ok $home/.claude/skills" "t_install_second_run_reports_ok skills-ok"
	assert_contains "$OUT" "ok $home/.local/bin/harness" "t_install_second_run_reports_ok harness-bin-ok"
	assert_not_contains "$OUT" "create $home/.claude/skills " "t_install_second_run_reports_ok skills-not-recreated"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# Existing real file/dir: FAIL without --force, moved+linked with --force
# ---------------------------------------------------------------------------

t_install_existing_real_dir_without_force_fails() {
	local home is_link
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	mkdir -p "$home/.claude/skills"
	printf 'sentinel\n' >"$home/.claude/skills/sentinel.txt"

	_install_cli "$home" install
	assert_rc 1 "t_install_existing_real_dir_without_force_fails rc"
	assert_contains "$OUT" "FAIL $home/.claude/skills exists (not a symlink)" "t_install_existing_real_dir_without_force_fails fail-line"
	assert_file_exists "$home/.claude/skills/sentinel.txt" "t_install_existing_real_dir_without_force_fails untouched"

	is_link=$(_install_is_symlink "$home/.claude/skills")
	assert_eq "$is_link" "no" "t_install_existing_real_dir_without_force_fails still-a-real-dir"

	rm -rf "$home"
}

# harness-templates and workflows are the two of the 9 ~/.claude/<x> items
# that doctor's own symlink checklist does NOT independently FAIL on
# (harness-templates isn't in that checklist at all; workflows is WARN-only
# there), so a conflict on either of them is invisible to doctor's own
# summary.fail count. `harness install`'s own step-1 FAIL for the conflict
# must still be ORed into the final exit code (C18 step 7: "exit 1 if any
# FAIL") independently of whatever doctor's checklist happens to report.
t_install_harness_templates_conflict_without_force_exits_1() {
	local home is_link
	home=$(tmp_dir)
	_install_write_fully_wired_dotfiles "$home/.dotfiles"
	mkdir -p "$home/.claude/harness-templates"
	printf 'sentinel\n' >"$home/.claude/harness-templates/sentinel.txt"

	_install_cli "$home" install
	assert_rc 1 "t_install_harness_templates_conflict_without_force_exits_1 rc"
	assert_contains "$OUT" "FAIL $home/.claude/harness-templates exists (not a symlink)" "t_install_harness_templates_conflict_without_force_exits_1 fail-line"
	# harness-templates is not in doctor's own symlink checklist at all, so
	# its checklist-derived summary must show 0 fail here — proving the
	# non-zero exit code above comes from install's own FAIL tracking, not
	# from doctor coincidentally catching the same conflict.
	assert_contains "$OUT" "0 fail" "t_install_harness_templates_conflict_without_force_exits_1 doctor-checklist-itself-clean"

	is_link=$(_install_is_symlink "$home/.claude/harness-templates")
	assert_eq "$is_link" "no" "t_install_harness_templates_conflict_without_force_exits_1 still-a-real-dir"

	rm -rf "$home"
}

t_install_workflows_conflict_without_force_exits_1() {
	local home is_link
	home=$(tmp_dir)
	_install_write_fully_wired_dotfiles "$home/.dotfiles"
	mkdir -p "$home/.claude/workflows"
	printf 'sentinel\n' >"$home/.claude/workflows/sentinel.txt"

	_install_cli "$home" install
	assert_rc 1 "t_install_workflows_conflict_without_force_exits_1 rc"
	assert_contains "$OUT" "FAIL $home/.claude/workflows exists (not a symlink)" "t_install_workflows_conflict_without_force_exits_1 fail-line"
	# workflows is WARN-only in doctor's own symlink checklist, so its
	# checklist-derived summary must show 0 fail here too — same isolation
	# as the harness-templates case above.
	assert_contains "$OUT" "0 fail" "t_install_workflows_conflict_without_force_exits_1 doctor-checklist-itself-clean"

	is_link=$(_install_is_symlink "$home/.claude/workflows")
	assert_eq "$is_link" "no" "t_install_workflows_conflict_without_force_exits_1 still-a-real-dir"

	rm -rf "$home"
}

t_install_existing_real_dir_with_force_moves_and_links() {
	local home is_link backup
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	mkdir -p "$home/.claude/skills"
	printf 'sentinel\n' >"$home/.claude/skills/sentinel.txt"

	_install_cli "$home" install --force
	assert_contains "$OUT" "create $home/.claude/skills" "t_install_existing_real_dir_with_force_moves_and_links create-line"

	is_link=$(_install_is_symlink "$home/.claude/skills")
	assert_eq "$is_link" "yes" "t_install_existing_real_dir_with_force_moves_and_links now-a-symlink"

	backup=$(find "$home/.claude" -maxdepth 1 -name 'skills.pre-harness.*' 2>/dev/null | head -1)
	assert_contains "$backup" "skills.pre-harness." "t_install_existing_real_dir_with_force_moves_and_links backup-exists"
	assert_file_exists "$backup/sentinel.txt" "t_install_existing_real_dir_with_force_moves_and_links backup-content-preserved"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# --dry-run: prints actions, writes nothing
# ---------------------------------------------------------------------------

t_install_dry_run_creates_nothing() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install --dry-run
	assert_file_missing "$home/.claude/skills" "t_install_dry_run_creates_nothing no-skills-link"
	assert_file_missing "$home/.local/bin/harness" "t_install_dry_run_creates_nothing no-harness-link"
	assert_file_missing "$home/.claude/transcript-backups" "t_install_dry_run_creates_nothing no-transcript-dir"
	assert_contains "$OUT" "skip" "t_install_dry_run_creates_nothing prints-skip"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# Missing hooks key in the dotfiles copy of settings.json: FAIL + exit 1,
# and settings.json itself is never written by install.
# ---------------------------------------------------------------------------

t_install_missing_hooks_key_fails_and_exits_1() {
	local home settings_before settings_after
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles" 0
	settings_before=$(cat "$home/.dotfiles/claude/.claude/settings.json")

	_install_cli "$home" install
	assert_rc 1 "t_install_missing_hooks_key_fails_and_exits_1 rc"
	assert_contains "$OUT" "has no hooks key" "t_install_missing_hooks_key_fails_and_exits_1 message"

	settings_after=$(cat "$home/.dotfiles/claude/.claude/settings.json")
	assert_eq "$settings_after" "$settings_before" "t_install_missing_hooks_key_fails_and_exits_1 settings-json-never-written"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# chmod +x: hooks/*.sh, scripts/* (non-test), and the CLI itself
# ---------------------------------------------------------------------------

t_install_chmod_sets_executable_bits() {
	local home hook_x script_x test_x cli_x
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install

	hook_x=no
	[ -x "$home/.dotfiles/claude/.claude/hooks/session-context.sh" ] && hook_x=yes
	assert_eq "$hook_x" "yes" "t_install_chmod_sets_executable_bits hook-script"

	script_x=no
	[ -x "$home/.dotfiles/claude/.claude/scripts/some-script" ] && script_x=yes
	assert_eq "$script_x" "yes" "t_install_chmod_sets_executable_bits scripts-script"

	cli_x=no
	[ -x "$home/.dotfiles/bin/.local/bin/harness" ] && cli_x=yes
	assert_eq "$cli_x" "yes" "t_install_chmod_sets_executable_bits cli"

	# scripts/tests/test_x.sh is one level down under scripts/tests/ — the
	# non-recursive "scripts/* (non-test)" walk must never reach into it.
	test_x=no
	[ -x "$home/.dotfiles/claude/.claude/scripts/tests/test_x.sh" ] && test_x=yes
	assert_eq "$test_x" "no" "t_install_chmod_sets_executable_bits leaves-nested-tests-dir-alone"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# ~/.claude/transcript-backups and ~/.claude/subagent-log are mkdir -p'd
# ---------------------------------------------------------------------------

t_install_creates_transcript_and_subagent_dirs() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install
	assert_file_exists "$home/.claude/transcript-backups" "t_install_creates_transcript_and_subagent_dirs transcript-backups"
	assert_file_exists "$home/.claude/subagent-log" "t_install_creates_transcript_and_subagent_dirs subagent-log"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# ~/.local/bin not on PATH → warned about
# ---------------------------------------------------------------------------

t_install_warns_when_local_bin_not_on_path() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"

	_install_cli "$home" install
	assert_contains "$OUT" "not on PATH" "t_install_warns_when_local_bin_not_on_path"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# Existing real ~/.claude/agents, /commands, settings.json, CLAUDE.md are
# merged / kept, not refused (the Mac had all four as real files).
# ---------------------------------------------------------------------------

t_install_merges_real_agents_dir_keeping_own_files() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	printf 'dev\n' >"$home/.dotfiles/claude/.claude/agents/developer.md"
	mkdir -p "$home/.claude/agents"
	printf 'mine\n' >"$home/.claude/agents/mine.md"
	_install_cli "$home" install
	assert_contains "$OUT" "merged: 1 linked" "merge: summary line"
	assert_eq "$(_install_is_symlink "$home/.claude/agents/developer.md")" "yes" "merge: dotfiles agent linked in"
	assert_eq "$(readlink "$home/.claude/agents/developer.md")" "../../.dotfiles/claude/.claude/agents/developer.md" "merge: relative link under ~/.dotfiles"
	assert_eq "$(cat "$home/.claude/agents/mine.md")" "mine" "merge: own agent untouched"
	assert_eq "$(_install_is_symlink "$home/.claude/agents")" "no" "merge: directory itself stays real"
	assert_not_contains "$OUT" "FAIL $home/.claude/agents" "merge: not reported as a conflict"
	# doctor accepts the merged layout
	_install_cli "$home" doctor --json
	assert_contains "$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:agents"')" '"status": "PASS"' "merge: doctor PASS on merged agents"
	rm -rf "$home"
}

t_install_merge_keeps_differing_file_unless_force() {
	local home backup
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	printf 'theirs\n' >"$home/.dotfiles/claude/.claude/commands/wrap.md"
	mkdir -p "$home/.claude/commands"
	printf 'ours\n' >"$home/.claude/commands/wrap.md"
	_install_cli "$home" install
	assert_contains "$OUT" "skip $home/.claude/commands/wrap.md differs" "merge: differing file reported"
	assert_eq "$(cat "$home/.claude/commands/wrap.md")" "ours" "merge: differing file kept without --force"
	_install_cli "$home" doctor --json
	assert_contains "$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:commands"')" '"status": "WARN"' "merge: doctor WARN names the unlinked entry"
	_install_cli "$home" install --force
	assert_eq "$(_install_is_symlink "$home/.claude/commands/wrap.md")" "yes" "merge --force: linked"
	backup=$(find "$home/.claude/commands" -maxdepth 1 -name 'wrap.md.pre-harness.*' | head -1)
	assert_eq "$(cat "$backup")" "ours" "merge --force: backup keeps the old content"
	rm -rf "$home"
}

t_install_identical_real_claude_md_is_linked_differing_is_kept() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	mkdir -p "$home/.claude"
	cp "$home/.dotfiles/claude/.claude/CLAUDE.md" "$home/.claude/CLAUDE.md"
	_install_cli "$home" install
	assert_eq "$(_install_is_symlink "$home/.claude/CLAUDE.md")" "yes" "identical CLAUDE.md: replaced by the link"
	assert_contains "$OUT" "was an identical copy" "identical CLAUDE.md: reported"
	rm -f "$home/.claude/CLAUDE.md"; printf '# mine\n' >"$home/.claude/CLAUDE.md"
	_install_cli "$home" install
	assert_eq "$(cat "$home/.claude/CLAUDE.md")" "# mine" "differing CLAUDE.md: kept"
	assert_not_contains "$OUT" "FAIL $home/.claude/CLAUDE.md" "differing CLAUDE.md: not a FAIL"
	_install_cli "$home" doctor --json
	assert_contains "$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:CLAUDE.md"')" '"status": "WARN"' "differing CLAUDE.md: doctor WARN"
	rm -rf "$home"
}

t_install_real_settings_json_is_kept_and_validated() {
	local home
	home=$(tmp_dir)
	_install_write_stub_dotfiles "$home/.dotfiles"
	rm -f "$home/.dotfiles/claude/.claude/settings.json"
	mkdir -p "$home/.claude"
	printf '{ "model": "opus", "hooks": { "SessionStart": [] } }\n' >"$home/.claude/settings.json"
	_install_cli "$home" install
	assert_contains "$OUT" "settings.json kept (machine-specific" "real settings: kept"
	assert_eq "$(_install_is_symlink "$home/.claude/settings.json")" "no" "real settings: not replaced"
	assert_contains "$OUT" "ok $home/.claude/settings.json parses and has a hooks key" "real settings: the live file is what step 4 validates"
	_install_cli "$home" doctor --json
	assert_contains "$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:settings.json"')" '"status": "PASS"' "real settings: doctor PASS"
	rm -rf "$home"
}
