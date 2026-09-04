#!/usr/bin/env bash
# test_cli_plugin.sh — unit M3 (CLI plugin mode) tests for bin/.local/bin/harness.
# Covers C21 M3: `harness install --marketplace <path>` and the plugin-mode
# `harness doctor` checks (plugin-skills-harness, plugin-hooks-json,
# plugin-double-registration, local-bin-harness, plugin-list), plus the
# templates-dir sibling fallback used by the plugin's own bin/harness copy.
# Sourced by run.sh; every t_clip_* function below is discovered and run.
# Written to also work standalone under TEST_ONLY=test_cli_plugin.sh.
set -u

# CLI_PATH per C9/unit map: "$HERE/../../../.." is the repo root. Computed
# independently of test_cli.sh so this file also works standalone.
CLI_PATH=""
CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
REPO_ROOT_FOR_TEST="$CLI_PATH"
CLI_PATH="$CLI_PATH/bin/.local/bin/harness"; [ -x "$SCAN_DIR/../bin/harness" ] && CLI_PATH="$SCAN_DIR/../bin/harness"

# _clip_cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>,
# without touching this test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
# Unsets HARNESS_REPO before exec so an ambient value set in the developer's
# shell (e.g. `export HARNESS_REPO=~/Desktop/Projects/harness`, exactly as
# the CLI's own --help text and C21 prose recommend) never leaks into a test
# that asserts the CLI's *default* (unset-HARNESS_REPO) resolution path.
_clip_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; unset HARNESS_REPO; exec "$@"' \
		_ "$dir" "$home" node "$CLI_PATH" "$@"
}

# _clip_write_stub_dotfiles <dotfiles-dir>
# A minimal stub dotfiles tree with the 9 claude/.claude/<x> items `install`
# links (mirrors test_install.sh's fixture shape; kept private to this file
# to stay standalone-safe under TEST_ONLY).
_clip_write_stub_dotfiles() {
	local d
	d=$1
	mkdir -p "$d/claude/.claude/skills" "$d/claude/.claude/agents" "$d/claude/.claude/commands" \
		"$d/claude/.claude/scripts/tests" "$d/claude/.claude/hooks" "$d/claude/.claude/workflows" \
		"$d/claude/.claude/harness-templates" "$d/bin/.local/bin"
	printf '{ "hooks": { "SessionStart": [] } }\n' >"$d/claude/.claude/settings.json"
	printf '# CLAUDE\n' >"$d/claude/.claude/CLAUDE.md"
	printf '#!/usr/bin/env node\nconsole.log("stub")\n' >"$d/bin/.local/bin/harness"
}

# _clip_write_marketplace_plugin <marketplace-root> <plugin-name>
# A minimal valid plugin dir: .claude-plugin/plugin.json only.
_clip_write_marketplace_plugin() {
	local root name
	root=$1
	name=$2
	mkdir -p "$root/plugins/$name/.claude-plugin"
	printf '{ "name": "%s", "version": "0.1.0" }\n' "$name" >"$root/plugins/$name/.claude-plugin/plugin.json"
}

# _clip_write_plugin_harness <home-dir> [valid_hooks_json=1]
# ~/.claude/skills/harness laid out as a real (non-symlinked, which is fine —
# doctor's plugin-mode checks read through fs calls regardless of symlink vs
# real dir) marketplace plugin root: .claude-plugin/plugin.json,
# hooks/session-context.sh (executable), and — when valid_hooks_json=1 —
# hooks/hooks.json referencing it via ${CLAUDE_PLUGIN_ROOT}.
_clip_write_plugin_harness() {
	local home valid
	home=$1
	valid=${2:-1}
	mkdir -p "$home/.claude/skills/harness/.claude-plugin" "$home/.claude/skills/harness/hooks"
	printf '{ "name": "harness", "version": "0.1.0" }\n' >"$home/.claude/skills/harness/.claude-plugin/plugin.json"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$home/.claude/skills/harness/hooks/session-context.sh"
	chmod +x "$home/.claude/skills/harness/hooks/session-context.sh"
	if [ "$valid" = "1" ]; then
		cat >"$home/.claude/skills/harness/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/session-context.sh" } ] } ]
  }
}
JSON
	fi
}

# ---------------------------------------------------------------------------
# install --marketplace: creates ~/.claude/skills/<name> symlinks
# ---------------------------------------------------------------------------





t_clip_install_marketplace_help_mentions_flag() {
	local home
	home=$(tmp_dir)
	_clip_cli_in "$home" "$home" install --help
	assert_rc 0 "t_clip_install_marketplace_help_mentions_flag rc"
	assert_contains "$OUT" "--marketplace" "t_clip_install_marketplace_help_mentions_flag flag-documented"
	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor: plugin-skills-harness
# ---------------------------------------------------------------------------

t_clip_doctor_plugin_skills_harness_skipped_when_absent() {
	local home
	home=$(tmp_dir)

	_clip_cli_in "$home" "$home" doctor --json
	assert_not_contains "$OUT" '"id": "plugin-skills-harness"' \
		"t_clip_doctor_plugin_skills_harness_skipped_when_absent no-check-line"

	rm -rf "$home"
}

t_clip_doctor_plugin_skills_harness_warns_when_real_dir() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude/skills/harness"
	printf 'not a plugin\n' >"$home/.claude/skills/harness/README.md"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-skills-harness"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_plugin_skills_harness_warns_when_real_dir status-warn"
	assert_contains "$block" 'real directory' "t_clip_doctor_plugin_skills_harness_warns_when_real_dir names-real-dir"

	rm -rf "$home"
}

t_clip_doctor_plugin_skills_harness_pass_when_symlink_into_plugin_root() {
	local home mkt block
	home=$(tmp_dir)
	mkt=$(tmp_dir)
	_clip_write_marketplace_plugin "$mkt" "harness"
	mkdir -p "$home/.claude/skills"
	ln -s "$mkt/plugins/harness" "$home/.claude/skills/harness"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-skills-harness"')
	assert_contains "$block" '"status": "PASS"' "t_clip_doctor_plugin_skills_harness_pass_when_symlink_into_plugin_root status-pass"

	rm -rf "$home" "$mkt"
}

# ---------------------------------------------------------------------------
# doctor: plugin-hooks-json
# ---------------------------------------------------------------------------

t_clip_doctor_hooks_json_missing_fails() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude/skills/harness"
	printf 'placeholder\n' >"$home/.claude/skills/harness/README.md"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-hooks-json"')
	assert_contains "$block" '"status": "FAIL"' "t_clip_doctor_hooks_json_missing_fails status-fail"
	assert_contains "$block" 'not found' "t_clip_doctor_hooks_json_missing_fails names-not-found"

	rm -rf "$home"
}

t_clip_doctor_hooks_json_malformed_fails() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 0
	printf '{ this is not json\n' >"$home/.claude/skills/harness/hooks/hooks.json"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-hooks-json"')
	assert_contains "$block" '"status": "FAIL"' "t_clip_doctor_hooks_json_malformed_fails status-fail"
	assert_contains "$block" 'does not parse' "t_clip_doctor_hooks_json_malformed_fails names-parse-error"

	rm -rf "$home"
}

t_clip_doctor_hooks_json_valid_hooks_pass() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 1

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-hooks-json"')
	assert_contains "$block" '"status": "PASS"' "t_clip_doctor_hooks_json_valid_hooks_pass status-pass"

	rm -rf "$home"
}

t_clip_doctor_hooks_json_missing_hook_file_fails() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 0
	rm -f "$home/.claude/skills/harness/hooks/session-context.sh"
	cat >"$home/.claude/skills/harness/hooks/hooks.json" <<'JSON'
{
  "hooks": {
    "SessionStart": [ { "hooks": [ { "type": "command", "command": "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/session-context.sh" } ] } ]
  }
}
JSON

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-hooks-json"')
	assert_contains "$block" '"status": "FAIL"' "t_clip_doctor_hooks_json_missing_hook_file_fails status-fail"
	assert_contains "$block" 'session-context.sh missing' "t_clip_doctor_hooks_json_missing_hook_file_fails names-missing-hook"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor: plugin-double-registration
# ---------------------------------------------------------------------------

# SPEC.md C21 M3 (line 319): "settings.json has NO `hooks` key (WARN
# \"double registration\" if both present)" — a machine mid-cutover (plugin
# loaded, settings.json not yet edited by the orchestrator) is an expected,
# spec-acknowledged transient state, not a fatal deployment error, so this
# must be WARN, not FAIL.
t_clip_doctor_double_registration_warns_when_settings_has_hooks_key() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 1
	mkdir -p "$home/.claude"
	printf '{ "hooks": { "SessionStart": [] } }\n' >"$home/.claude/settings.json"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-double-registration"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_double_registration_warns_when_settings_has_hooks_key status-warn"

	rm -rf "$home"
}

t_clip_doctor_double_registration_pass_when_settings_has_no_hooks_key() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 1
	mkdir -p "$home/.claude"
	printf '{ "notHooks": true }\n' >"$home/.claude/settings.json"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-double-registration"')
	assert_contains "$block" '"status": "PASS"' "t_clip_doctor_double_registration_pass_when_settings_has_no_hooks_key status-pass"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor: settings:hooks-key must not FAIL in the fully-migrated plugin
# end-state (valid plugin hooks.json + settings.json with no "hooks" key).
# This is the combined/integration case: settings:hooks-key and
# plugin-double-registration both read the SAME settings.json in the SAME
# doctor run, so a fix that only patches one check in isolation would still
# leave doctor unable to reach 0 FAIL after a completed C21 cut-over.
# ---------------------------------------------------------------------------

t_clip_doctor_settings_hooks_key_pass_in_fully_migrated_plugin_state() {
	local home block
	home=$(tmp_dir)
	_clip_write_plugin_harness "$home" 1
	mkdir -p "$home/.claude"
	printf '{ "notHooks": true }\n' >"$home/.claude/settings.json"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "PASS"' \
		"t_clip_doctor_settings_hooks_key_pass_in_fully_migrated_plugin_state hooks-key-pass"

	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-double-registration"')
	assert_not_contains "$block" '"status": "FAIL"' \
		"t_clip_doctor_settings_hooks_key_pass_in_fully_migrated_plugin_state double-registration-not-fail"

	rm -rf "$home"
}

# Guard against an over-broad fix: without plugin mode (no plugin
# hooks/hooks.json deployed at all), a missing settings.json "hooks" key must
# still FAIL exactly as it did before C21 M3.
t_clip_doctor_settings_hooks_key_still_fails_without_plugin_mode() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude"
	printf '{ "notHooks": true }\n' >"$home/.claude/settings.json"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "FAIL"' \
		"t_clip_doctor_settings_hooks_key_still_fails_without_plugin_mode status-fail"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor: local-bin-harness
# ---------------------------------------------------------------------------

t_clip_doctor_local_bin_harness_warns_when_missing() {
	local home block
	home=$(tmp_dir)

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "local-bin-harness"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_local_bin_harness_warns_when_missing status-warn"

	rm -rf "$home"
}

t_clip_doctor_local_bin_harness_pass_when_symlink() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.local/bin" "$home/somewhere"
	printf '#!/usr/bin/env node\n' >"$home/somewhere/harness"
	ln -s "$home/somewhere/harness" "$home/.local/bin/harness"

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "local-bin-harness"')
	assert_contains "$block" '"status": "PASS"' "t_clip_doctor_local_bin_harness_pass_when_symlink status-pass"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor: plugin-list (`claude plugin list --json`)
# ---------------------------------------------------------------------------

t_clip_doctor_plugin_list_warns_when_claude_absent() {
	local home fakebin restricted_path block
	home=$(tmp_dir)
	fakebin=$(tmp_dir)
	ln -s "$(command -v node)" "$fakebin/node"
	restricted_path="$fakebin"

	run_cmd bash -c 'export PATH="$1"; command -v claude' _ "$restricted_path"
	assert_rc 1 "t_clip_doctor_plugin_list_warns_when_claude_absent sanity-no-claude-on-path"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$restricted_path" node "$CLI_PATH" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-list"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_plugin_list_warns_when_claude_absent status-warn"
	assert_contains "$block" 'not found on PATH' "t_clip_doctor_plugin_list_warns_when_claude_absent names-reason"

	rm -rf "$home" "$fakebin"
}

t_clip_doctor_plugin_list_pass_when_harness_skills_dir_present() {
	local home fakebin restricted_path block
	home=$(tmp_dir)
	fakebin=$(tmp_dir)
	ln -s "$(command -v node)" "$fakebin/node"
	cat >"$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  echo '[{"id":"harness@skills-dir","enabled":true}]'
  exit 0
fi
exit 1
EOF
	chmod +x "$fakebin/claude"
	# The fake claude script needs a working #!/usr/bin/env bash shebang to
	# actually execute when spawnSync's execvp-style PATH lookup finds it
	# (unlike have(), which only stats the file); include the real /bin so
	# `env` resolves, while fakebin (listed first) still wins for `claude`
	# and `node` themselves.
	restricted_path="$fakebin:/bin:/usr/bin"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$restricted_path" node "$CLI_PATH" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-list"')
	assert_contains "$block" '"status": "PASS"' "t_clip_doctor_plugin_list_pass_when_harness_skills_dir_present status-pass"

	rm -rf "$home" "$fakebin"
}

# SPEC.md C21 M3 (line 319): "claude plugin list --json (if available) shows
# harness@skills-dir enabled". A substring match on the raw JSON only proves
# the id is mentioned somewhere; it must also read the per-entry `enabled`
# boolean (verified real `claude` v2.1.260 schema) so a disabled/partially-
# loaded plugin is not misreported as healthy.
t_clip_doctor_plugin_list_warns_when_harness_skills_dir_disabled() {
	local home fakebin restricted_path block
	home=$(tmp_dir)
	fakebin=$(tmp_dir)
	ln -s "$(command -v node)" "$fakebin/node"
	cat >"$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "plugin" ] && [ "$2" = "list" ]; then
  echo '[{"id":"harness@skills-dir","enabled":false}]'
  exit 0
fi
exit 1
EOF
	chmod +x "$fakebin/claude"
	# See t_clip_doctor_plugin_list_pass_when_harness_skills_dir_present for
	# why /bin is included (the fake script's #!/usr/bin/env bash shebang
	# must actually resolve when spawnSync executes it).
	restricted_path="$fakebin:/bin:/usr/bin"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$restricted_path" node "$CLI_PATH" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-list"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_plugin_list_warns_when_harness_skills_dir_disabled status-warn"
	assert_contains "$block" 'not enabled' "t_clip_doctor_plugin_list_warns_when_harness_skills_dir_disabled names-reason"

	rm -rf "$home" "$fakebin"
}

t_clip_doctor_plugin_list_warns_when_claude_errors() {
	local home fakebin restricted_path block
	home=$(tmp_dir)
	fakebin=$(tmp_dir)
	ln -s "$(command -v node)" "$fakebin/node"
	cat >"$fakebin/claude" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
	chmod +x "$fakebin/claude"
	# See t_clip_doctor_plugin_list_pass_when_harness_skills_dir_present for
	# why /bin is included (the fake script's #!/usr/bin/env bash shebang
	# must actually resolve when spawnSync executes it).
	restricted_path="$fakebin:/bin:/usr/bin"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$restricted_path" node "$CLI_PATH" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "plugin-list"')
	assert_contains "$block" '"status": "WARN"' "t_clip_doctor_plugin_list_warns_when_claude_errors status-warn"
	assert_contains "$block" 'failed (exit 1)' "t_clip_doctor_plugin_list_warns_when_claude_errors names-exit-code"

	rm -rf "$home" "$fakebin"
}

# ---------------------------------------------------------------------------
# templates dir: sibling-of-CLI-real-path fallback (C21 M3: "${CLAUDE_PLUGIN_
# ROOT} is not set for the CLI; resolve templates relative to the CLI's own
# real path: ../harness-templates" — the plugin layout is
# plugins/harness/bin/harness with plugins/harness/harness-templates/ as its
# sibling).
# ---------------------------------------------------------------------------

t_clip_templates_dir_falls_back_to_sibling_of_cli_real_path() {
	local plugroot home proj out
	plugroot=$(tmp_dir)
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$plugroot/bin" "$plugroot/harness-templates"
	cp "$CLI_PATH" "$plugroot/bin/harness"
	chmod +x "$plugroot/bin/harness"
	printf '# Review guide\nMARKER-SIBLING-TEMPLATE-C21-M3\n' >"$plugroot/harness-templates/REVIEW.md"
	printf '# Progress\n' >"$plugroot/harness-templates/PROGRESS.md"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$proj" "$home" node "$plugroot/bin/harness" init
	assert_rc 0 "t_clip_templates_dir_falls_back_to_sibling_of_cli_real_path rc"

	out=$(cat "$proj/REVIEW.md" 2>/dev/null || true)
	assert_contains "$out" "MARKER-SIBLING-TEMPLATE-C21-M3" \
		"t_clip_templates_dir_falls_back_to_sibling_of_cli_real_path uses-sibling-template"

	rm -rf "$plugroot" "$home" "$proj"
}

# ---------------------------------------------------------------------------
# skill-index-cost: counts marketplace plugin roots' nested skills too
# ---------------------------------------------------------------------------

t_clip_doctor_skill_index_cost_counts_plugin_skills() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude/skills/harness/.claude-plugin" "$home/.claude/skills/harness/skills/flow"
	printf '{ "name": "harness" }\n' >"$home/.claude/skills/harness/.claude-plugin/plugin.json"
	cat >"$home/.claude/skills/harness/skills/flow/SKILL.md" <<'EOF'
---
name: flow
description: A test plugin skill used only to exercise doctor's skill-index-cost accounting for marketplace plugin roots.
---
# Flow
EOF

	_clip_cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "skill-index-cost"')
	assert_contains "$block" 'harness/flow (' "t_clip_doctor_skill_index_cost_counts_plugin_skills names-nested-skill"

	rm -rf "$home"
}

# C21 (single-symlink live loading): ~/.claude/skills -> <marketplace>/plugins;
# hooks/scripts/harness-templates -> the core plugin; no ~/.claude/workflows.
_clip_write_core_plugin() {
  mkdir -p "$1/plugins/harness/.claude-plugin" "$1/plugins/harness/hooks" "$1/plugins/harness/scripts" "$1/plugins/harness/harness-templates" "$1/plugins/harness/workflows" "$1/plugins/harness/bin" "$1/.claude-plugin"
  printf '{"name":"harness","version":"0.1.0","skills":["./skills/"]}\n' >"$1/plugins/harness/.claude-plugin/plugin.json"
  printf '{"name":"harness","owner":{"name":"t"},"plugins":[{"name":"harness","source":"./plugins/harness"}]}\n' >"$1/.claude-plugin/marketplace.json"
  printf '{"hooks":{}}\n' >"$1/plugins/harness/hooks/hooks.json"
  printf '#!/usr/bin/env node\nconsole.log("stub")\n' >"$1/plugins/harness/bin/harness"
}

t_clip_install_plugin_mode_links_skills_to_plugins_dir() {
	local home dotfiles mkt
	home=$(tmp_dir); dotfiles=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	_clip_write_core_plugin "$mkt"
	_clip_write_marketplace_plugin "$mkt" "widget"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt"
	assert_eq "$(readlink "$home/.claude/skills")" "$mkt/plugins" "plugin mode: ~/.claude/skills -> plugins dir"
	assert_eq "$(readlink "$home/.claude/hooks")" "$mkt/plugins/harness/hooks" "plugin mode: hooks -> core plugin"
	assert_eq "$(readlink "$home/.claude/scripts")" "$mkt/plugins/harness/scripts" "plugin mode: scripts -> core plugin"
	assert_eq "$(readlink "$home/.claude/harness-templates")" "$mkt/plugins/harness/harness-templates" "plugin mode: templates -> core plugin"
	assert_file_missing "$home/.claude/workflows" "plugin mode: no bare workflows link"
	assert_eq "$(readlink "$home/.local/bin/harness")" "$mkt/plugins/harness/bin/harness" "plugin mode: CLI links to the plugin copy"
	rm -rf "$home" "$dotfiles" "$mkt"
}

t_clip_install_plugin_mode_is_idempotent() {
	local home dotfiles mkt
	home=$(tmp_dir); dotfiles=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	_clip_write_core_plugin "$mkt"
	printf '{}\n' >"$dotfiles/claude/.claude/settings.json"   # plugin mode: no hooks block in settings
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt"
	assert_not_contains "$OUT" "FAIL $home/.claude" "plugin mode second run: no install FAIL line"
	assert_eq "$(readlink "$home/.claude/skills")" "$mkt/plugins" "plugin mode second run: link intact"
	rm -rf "$home" "$dotfiles" "$mkt"
}

t_clip_install_plugin_mode_settings_hooks_key_is_a_fail() {
	local home dotfiles mkt
	home=$(tmp_dir); dotfiles=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	_clip_write_core_plugin "$mkt"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt"
	assert_contains "$OUT" "hooks key AND the plugin provides hooks.json" "plugin mode: settings hooks block is reported as double registration"
	rm -rf "$home" "$dotfiles" "$mkt"
}

t_clip_install_no_marketplace_checkout_prints_alternative() {
	local home dotfiles
	home=$(tmp_dir); dotfiles=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$home/nope"
	assert_contains "$OUT" "no marketplace checkout" "no checkout: note printed"
	assert_contains "$OUT" "claude plugin marketplace add TomasPalsson/harness" "no checkout: alternative command printed"
	rm -rf "$home" "$dotfiles"
}

# The Mac regression: a plugin CLI with no ~/.dotfiles must refuse to install
# rather than treat the marketplace checkout (which has no claude/.claude) as
# the dotfiles root and then FAIL on a settings.json that was never there.
t_clip_install_no_dotfiles_refuses_instead_of_using_marketplace() {
	local home mkt
	home=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_core_plugin "$mkt"
	_clip_cli_in "$home" "$home" install --marketplace "$mkt"
	assert_rc 1 "no dotfiles: install exits 1"
	assert_contains "$OUT" "no dotfiles checkout found" "no dotfiles: names the problem"
	assert_contains "$OUT" "--dotfiles" "no dotfiles: says how to fix it"
	assert_not_contains "$OUT" "does not parse" "no dotfiles: no misleading settings.json failure"
	assert_eq "$(_install_is_symlink_clip "$home/.claude/skills")" "no" "no dotfiles: nothing was linked"
	rm -rf "$home" "$mkt"
}
_install_is_symlink_clip() { if [ -L "$1" ]; then printf 'yes'; else printf 'no'; fi; }

t_clip_install_dotfiles_env_var_is_honoured() {
	local home dotfiles mkt
	home=$(tmp_dir); dotfiles=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	_clip_write_core_plugin "$mkt"
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2" DOTFILES="$3"; shift 3; unset HARNESS_REPO; exec "$@"' \
		_ "$home" "$home" "$dotfiles" node "$CLI_PATH" install --marketplace "$mkt"
	assert_contains "$OUT" "(dotfiles: $dotfiles)" "DOTFILES env: used as the dotfiles root"
	rm -rf "$home" "$dotfiles" "$mkt"
}

# settings.json is gitignored in the dotfiles (machine-specific), so a fresh
# checkout has none: plugin mode seeds a minimal parseable one instead of FAIL.
t_clip_install_plugin_mode_seeds_missing_settings() {
	local home dotfiles mkt
	home=$(tmp_dir); dotfiles=$(tmp_dir); mkt=$(tmp_dir)
	_clip_write_stub_dotfiles "$dotfiles"
	rm -f "$dotfiles/claude/.claude/settings.json"
	_clip_write_core_plugin "$mkt"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt"
	assert_contains "$OUT" "settings.json seeded" "missing settings: seeded"
	assert_not_contains "$OUT" "does not parse" "missing settings: no parse failure"
	assert_eq "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1],"utf8")).skillListingBudgetFraction)' "$dotfiles/claude/.claude/settings.json")" "0.02" "missing settings: seeded file carries the skill index budget"
	_clip_cli_in "$home" "$home" install --dotfiles "$dotfiles" --marketplace "$mkt" --dry-run
	assert_not_contains "$OUT" "seeded" "existing settings: not re-seeded"
	rm -rf "$home" "$dotfiles" "$mkt"
}
