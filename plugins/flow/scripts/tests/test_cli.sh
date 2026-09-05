#!/usr/bin/env bash
# test_cli.sh — unit U5 (harness-cli) tests for bin/.local/bin/flow.
# Sourced by run.sh; every t_cli_* function below is discovered and run.
set -u

# CLI_PATH per C9/unit map: "$HERE/../../../.." is the repo root.
CLI_PATH=""
CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
CLI_PATH="$CLI_PATH/bin/.local/bin/flow"; [ -x "$SCAN_DIR/../bin/flow" ] && CLI_PATH="$SCAN_DIR/../bin/flow"

# cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>,
# without touching this test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$CLI_PATH" "$@"
}

# _cli_write_hook_files <hooks-dir>
# Creates all 9 C5 hook files (empty stub, executable) under <hooks-dir>.
_cli_write_hook_files() {
	local dir h
	dir=$1
	mkdir -p "$dir"
	for h in session-context.sh turn-stamp.sh rtk-rewrite.sh git-guard.sh \
		format-lint.sh size-guard.sh tamper-notice.sh stop-gate.sh pre-compact-backup.sh; do
		printf '#!/usr/bin/env bash\n' >"$dir/$h"
		chmod +x "$dir/$h"
	done
}

# _cli_write_wired_settings <settings.json-path>
# Writes a settings.json whose "hooks" key matches C5 exactly (every event,
# every matcher, every C5 hook file wired to a command).
_cli_write_wired_settings() {
	cat >"$1" <<'JSON'
{
  "hooks": {
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/session-context.sh", "timeout": 10 } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/turn-stamp.sh", "timeout": 5 } ] } ],
    "PreToolUse":       [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/rtk-rewrite.sh", "timeout": 10 },
                                                            { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh", "timeout": 10 } ] } ],
    "PostToolUse":      [ { "matcher": "Edit|Write|NotebookEdit", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/format-lint.sh", "timeout": 60 },
                                                                              { "type": "command", "command": "$HOME/.claude/hooks/size-guard.sh", "timeout": 20 },
                                                                              { "type": "command", "command": "$HOME/.claude/hooks/tamper-notice.sh", "timeout": 10 } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/stop-gate.sh", "timeout": 600 } ] } ],
    "PreCompact":       [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/pre-compact-backup.sh", "timeout": 20 } ] } ]
  }
}
JSON
}

# ---------------------------------------------------------------------------
# --help
# ---------------------------------------------------------------------------

t_cli_top_help_exits_0() {
	run_cmd node "$CLI_PATH" --help
	assert_rc 0 "t_cli_top_help_exits_0 rc"
	assert_contains "$OUT" "Usage:" "t_cli_top_help_exits_0 usage-line"
	assert_contains "$OUT" "doctor" "t_cli_top_help_exits_0 mentions-doctor"
	assert_contains "$OUT" "init" "t_cli_top_help_exits_0 mentions-init"
}

t_cli_check_help_exits_0() {
	run_cmd node "$CLI_PATH" check --help
	assert_rc 0 "t_cli_check_help_exits_0 rc"
}

t_cli_no_args_exits_0_and_prints_help() {
	run_cmd node "$CLI_PATH"
	assert_rc 0 "t_cli_no_args_exits_0_and_prints_help rc"
	assert_contains "$OUT" "Usage:" "t_cli_no_args_exits_0_and_prints_help usage-line"
}

# ---------------------------------------------------------------------------
# doctor — undeployed state (no ~/.claude at all)
# ---------------------------------------------------------------------------

t_cli_doctor_json_undeployed_reports_fail_checks() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json

	# Assert on JSON content, not exit code (an undeployed HOME always fails,
	# but the spec's contract is the shape/content of the report).
	assert_contains "$OUT" '"id": "symlink:skills"' "t_cli_doctor_json_undeployed_reports_fail_checks skills-check-present"
	assert_contains "$OUT" '"id": "symlink:hooks"' "t_cli_doctor_json_undeployed_reports_fail_checks hooks-check-present"
	assert_contains "$OUT" '"id": "settings:hooks-key"' "t_cli_doctor_json_undeployed_reports_fail_checks hooks-key-check-present"
	assert_contains "$OUT" '"summary"' "t_cli_doctor_json_undeployed_reports_fail_checks summary-object-present"

	local skills_block hooks_key_block
	skills_block=$(printf '%s' "$OUT" | grep -A1 '"id": "symlink:skills"')
	assert_contains "$skills_block" '"status": "FAIL"' "t_cli_doctor_json_undeployed_reports_fail_checks skills-is-fail"

	hooks_key_block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$hooks_key_block" '"status": "FAIL"' "t_cli_doctor_json_undeployed_reports_fail_checks hooks-key-is-fail"

	rm -rf "$home"
}

t_cli_doctor_json_undeployed_workflows_is_warn_not_fail() {
	local home workflows_block
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json
	workflows_block=$(printf '%s' "$OUT" | grep -A1 '"id": "symlink:workflows"')
	assert_contains "$workflows_block" '"status": "WARN"' "t_cli_doctor_json_undeployed_workflows_is_warn_not_fail"

	rm -rf "$home"
}

t_cli_doctor_human_mode_prints_summary_line() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor
	assert_contains "$OUT" "fail" "t_cli_doctor_human_mode_prints_summary_line has-fail-word"
	assert_not_contains "$OUT" '"checks"' "t_cli_doctor_human_mode_prints_summary_line not-json"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# init — node stack
# ---------------------------------------------------------------------------

t_cli_init_node_dry_run_writes_nothing() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test","lint":"echo lint"}}
EOF

	cli_in "$proj" "$home" init --dry-run
	assert_rc 0 "t_cli_init_node_dry_run_writes_nothing rc"
	assert_contains "$OUT" "WOULD WRITE" "t_cli_init_node_dry_run_writes_nothing reports-would-write"
	assert_file_missing "$proj/REVIEW.md" "t_cli_init_node_dry_run_writes_nothing no-review"
	assert_file_missing "$proj/.github/workflows/gates.yml" "t_cli_init_node_dry_run_writes_nothing no-gates"
	assert_file_missing "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_node_dry_run_writes_nothing no-thresholds"

	rm -rf "$home" "$proj"
}

t_cli_init_node_creates_expected_files_and_thresholds() {
	local home proj thresholds gates harness_json
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test","lint":"echo lint"}}
EOF

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_node_creates_expected_files_and_thresholds rc"
	assert_file_exists "$proj/REVIEW.md" "t_cli_init_node_creates_expected_files_and_thresholds review"
	assert_file_exists "$proj/PROGRESS.md" "t_cli_init_node_creates_expected_files_and_thresholds progress"
	assert_file_exists "$proj/.claude/flow.config.json" "t_cli_init_node_creates_expected_files_and_thresholds harness-json"
	assert_file_exists "$proj/.github/workflows/gates.yml" "t_cli_init_node_creates_expected_files_and_thresholds gates"
	assert_file_exists "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_node_creates_expected_files_and_thresholds thresholds-file"
	assert_file_exists "$proj/CLAUDE.md" "t_cli_init_node_creates_expected_files_and_thresholds claude-md"

	thresholds=$(cat "$proj/.flow/eslint.thresholds.mjs")
	assert_contains "$thresholds" "'max-lines': ['error', { max: 400" "t_cli_init_node_creates_expected_files_and_thresholds max-lines-400"
	assert_contains "$thresholds" "'max-lines-per-function': ['error', { max: 60" "t_cli_init_node_creates_expected_files_and_thresholds max-lines-per-function-60"
	assert_contains "$thresholds" "complexity: ['error', 10]" "t_cli_init_node_creates_expected_files_and_thresholds complexity-10"
	assert_contains "$thresholds" "'max-params': ['error', 4]" "t_cli_init_node_creates_expected_files_and_thresholds max-params-4"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-node@v4" "t_cli_init_node_creates_expected_files_and_thresholds gates-uses-setup-node"
	assert_contains "$gates" "run: npm run test" "t_cli_init_node_creates_expected_files_and_thresholds gates-test-cmd"
	assert_contains "$gates" "run: npm run lint" "t_cli_init_node_creates_expected_files_and_thresholds gates-lint-cmd"
	assert_not_contains "$gates" "TYPECHECK_CMD" "t_cli_init_node_creates_expected_files_and_thresholds no-leftover-placeholder"
	assert_not_contains "$gates" "name: typecheck" "t_cli_init_node_creates_expected_files_and_thresholds drops-empty-typecheck-step"
	assert_contains "$gates" "CI: true" "t_cli_init_node_creates_expected_files_and_thresholds ci-true"

	harness_json=$(cat "$proj/.claude/flow.config.json")
	assert_contains "$harness_json" '"maxFileLines": 400' "t_cli_init_node_creates_expected_files_and_thresholds harness-json-max-file-lines"
	assert_contains "$harness_json" '"stopGate": "scoped"' "t_cli_init_node_creates_expected_files_and_thresholds harness-json-stopgate-default"

	rm -rf "$home" "$proj"
}

t_cli_init_existing_review_md_never_overwritten_without_force() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test"}}
EOF
	printf 'SENTINEL\n' >"$proj/REVIEW.md"

	cli_in "$proj" "$home" init
	assert_eq "$(cat "$proj/REVIEW.md")" "SENTINEL" "t_cli_init_existing_review_md_never_overwritten_without_force unchanged"

	cli_in "$proj" "$home" init --force
	assert_contains "$(cat "$proj/REVIEW.md")" "# Review guide" "t_cli_init_existing_review_md_never_overwritten_without_force force-overwrites"

	rm -rf "$home" "$proj"
}

t_cli_init_claude_md_never_overwritten_even_with_force() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test"}}
EOF
	printf 'MY OWN CLAUDE MD\n' >"$proj/CLAUDE.md"

	cli_in "$proj" "$home" init --force
	assert_eq "$(cat "$proj/CLAUDE.md")" "MY OWN CLAUDE MD" "t_cli_init_claude_md_never_overwritten_even_with_force"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — python stack
# ---------------------------------------------------------------------------

t_cli_init_python_creates_ruff_thresholds() {
	local home proj thresholds gates
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/pyproject.toml" <<'EOF'
[project]
name = "x"

[tool.pytest.ini_options]

[tool.ruff]
EOF

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_python_creates_ruff_thresholds rc"
	assert_file_exists "$proj/.flow/ruff.thresholds.toml" "t_cli_init_python_creates_ruff_thresholds thresholds-file"
	assert_file_missing "$proj/clippy.toml" "t_cli_init_python_creates_ruff_thresholds no-clippy"

	thresholds=$(cat "$proj/.flow/ruff.thresholds.toml")
	assert_contains "$thresholds" 'max-complexity = 10' "t_cli_init_python_creates_ruff_thresholds max-complexity-10"
	assert_contains "$thresholds" 'max-branches = 12' "t_cli_init_python_creates_ruff_thresholds max-branches-12"
	assert_contains "$thresholds" 'max-statements = 50' "t_cli_init_python_creates_ruff_thresholds max-statements-50"
	assert_contains "$thresholds" 'select = ["E", "F", "I", "N", "UP", "B", "S", "C90", "PL"]' "t_cli_init_python_creates_ruff_thresholds select-list"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-python@v5" "t_cli_init_python_creates_ruff_thresholds gates-uses-setup-python"
	assert_contains "$gates" "run: pytest" "t_cli_init_python_creates_ruff_thresholds gates-test-cmd"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — rust stack
# ---------------------------------------------------------------------------

t_cli_init_rust_creates_clippy_toml_only_if_absent() {
	local home proj clippy gates
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/Cargo.toml" <<'EOF'
[package]
name = "x"
EOF
	: >"$proj/Cargo.lock" # detect-project keys its package-manager detection off this

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_rust_creates_clippy_toml_only_if_absent rc"
	assert_file_exists "$proj/clippy.toml" "t_cli_init_rust_creates_clippy_toml_only_if_absent clippy-created"

	clippy=$(cat "$proj/clippy.toml")
	assert_contains "$clippy" "too-many-lines-threshold = 60" "t_cli_init_rust_creates_clippy_toml_only_if_absent lines-threshold"
	assert_contains "$clippy" "cognitive-complexity-threshold = 15" "t_cli_init_rust_creates_clippy_toml_only_if_absent cognitive-threshold"
	assert_contains "$clippy" "too-many-arguments-threshold = 5" "t_cli_init_rust_creates_clippy_toml_only_if_absent args-threshold"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "dtolnay/rust-toolchain@stable" "t_cli_init_rust_creates_clippy_toml_only_if_absent gates-uses-rust-toolchain"
	assert_contains "$gates" "run: cargo test" "t_cli_init_rust_creates_clippy_toml_only_if_absent gates-test-cmd"

	# clippy.toml is documented as "only if absent" even with --force.
	printf 'SENTINEL\n' >"$proj/clippy.toml"
	cli_in "$proj" "$home" init --force
	assert_eq "$(cat "$proj/clippy.toml")" "SENTINEL" "t_cli_init_rust_creates_clippy_toml_only_if_absent never-force-overwritten"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — go stack
# ---------------------------------------------------------------------------

t_cli_init_go_creates_golangci_yml() {
	local home proj golangci gates
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/go.mod" <<'EOF'
module example.com/x

go 1.22
EOF
	: >"$proj/go.sum" # detect-project keys its package-manager detection off this

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_go_creates_golangci_yml rc"
	assert_file_exists "$proj/.golangci.yml" "t_cli_init_go_creates_golangci_yml created"

	golangci=$(cat "$proj/.golangci.yml")
	assert_contains "$golangci" "lines: 60" "t_cli_init_go_creates_golangci_yml funlen-60"
	assert_contains "$golangci" "min-complexity: 10" "t_cli_init_go_creates_golangci_yml gocyclo-10"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-go@v5" "t_cli_init_go_creates_golangci_yml gates-uses-setup-go"
	assert_contains "$gates" "run: go test ./..." "t_cli_init_go_creates_golangci_yml gates-test-cmd"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — no stack detected
# ---------------------------------------------------------------------------

t_cli_init_empty_repo_skips_gates_and_thresholds() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)

	cli_in "$proj" "$home" init --dry-run
	assert_rc 0 "t_cli_init_empty_repo_skips_gates_and_thresholds dry-run-rc"
	assert_contains "$OUT" "no stack detected" "t_cli_init_empty_repo_skips_gates_and_thresholds dry-run-message"
	assert_file_missing "$proj/REVIEW.md" "t_cli_init_empty_repo_skips_gates_and_thresholds dry-run-writes-nothing"

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_empty_repo_skips_gates_and_thresholds rc"
	assert_contains "$OUT" "no stack detected — governance files written, gates skipped" "t_cli_init_empty_repo_skips_gates_and_thresholds exact-message"
	assert_file_exists "$proj/REVIEW.md" "t_cli_init_empty_repo_skips_gates_and_thresholds review-written"
	assert_file_exists "$proj/PROGRESS.md" "t_cli_init_empty_repo_skips_gates_and_thresholds progress-written"
	assert_file_exists "$proj/.claude/flow.config.json" "t_cli_init_empty_repo_skips_gates_and_thresholds harness-json-written"
	assert_file_missing "$proj/.github/workflows/gates.yml" "t_cli_init_empty_repo_skips_gates_and_thresholds no-gates"
	assert_file_missing "$proj/.flow" "t_cli_init_empty_repo_skips_gates_and_thresholds no-harness-dir"
	assert_file_missing "$proj/CLAUDE.md" "t_cli_init_empty_repo_skips_gates_and_thresholds no-claude-md"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — explicit --stack overrides auto-detection
# ---------------------------------------------------------------------------

t_cli_init_explicit_stack_overrides_autodetect() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)
	# No manifest at all, but force --stack go.
	cli_in "$proj" "$home" init --stack go
	assert_rc 0 "t_cli_init_explicit_stack_overrides_autodetect rc"
	assert_file_exists "$proj/.golangci.yml" "t_cli_init_explicit_stack_overrides_autodetect golangci-written"
	assert_not_contains "$OUT" "no stack detected" "t_cli_init_explicit_stack_overrides_autodetect no-empty-message"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — invalid --stack value is rejected, not silently treated as "no stack"
# ---------------------------------------------------------------------------

t_cli_init_invalid_stack_value_is_rejected() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_dir)

	cli_in "$proj" "$home" init --stack java
	assert_rc 1 "t_cli_init_invalid_stack_value_is_rejected rc"
	assert_contains "$ERR" "invalid --stack value 'java'" "t_cli_init_invalid_stack_value_is_rejected names-the-bad-value"
	assert_not_contains "$OUT" "no stack detected" "t_cli_init_invalid_stack_value_is_rejected does-not-claim-no-stack"
	assert_file_missing "$proj/REVIEW.md" "t_cli_init_invalid_stack_value_is_rejected writes-nothing"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor — settings:hooks-key must verify actual C5 wiring, not just presence
# ---------------------------------------------------------------------------

t_cli_doctor_hooks_key_vacuous_hooks_object_is_fail() {
	local home block
	home=$(tmp_dir)
	_cli_write_hook_files "$home/.claude/hooks"
	printf '{ "hooks": {} }\n' >"$home/.claude/settings.json"

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_hooks_key_vacuous_hooks_object_is_fail status-fail"
	assert_contains "$OUT" "not wired" "t_cli_doctor_hooks_key_vacuous_hooks_object_is_fail names-not-wired"

	rm -rf "$home"
}

t_cli_doctor_hooks_key_fully_wired_settings_is_pass() {
	local home block
	home=$(tmp_dir)
	_cli_write_hook_files "$home/.claude/hooks"
	_cli_write_wired_settings "$home/.claude/settings.json"

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_hooks_key_fully_wired_settings_is_pass status-pass"

	rm -rf "$home"
}

t_cli_doctor_hooks_key_wrong_event_names_is_fail() {
	local home block
	home=$(tmp_dir)
	_cli_write_hook_files "$home/.claude/hooks"
	cat >"$home/.claude/settings.json" <<'JSON'
{ "hooks": { "SomeUnrelatedKey": [ { "hooks": [ { "type": "command", "command": "/bin/true" } ] } ] } }
JSON

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_hooks_key_wrong_event_names_is_fail status-fail"
	assert_contains "$OUT" "SessionStart: not wired" "t_cli_doctor_hooks_key_wrong_event_names_is_fail names-sessionstart"

	rm -rf "$home"
}

# A hook file's command string appearing *somewhere* in the event is not
# enough: it must appear inside the block whose matcher equals the C5-required
# matcher for that event. Here PreToolUse has two blocks — matcher:"Write"
# wired to git-guard.sh (wrong matcher; git-guard.sh needs "Bash" per C5) and
# matcher:"Bash" wired only to rtk-rewrite.sh — with every other event wired
# correctly. This must FAIL and name git-guard.sh as not wired to PreToolUse,
# not report a clean PASS.
t_cli_doctor_hooks_key_wrong_matcher_within_multiblock_event_is_fail() {
	local home block
	home=$(tmp_dir)
	_cli_write_hook_files "$home/.claude/hooks"
	cat >"$home/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/session-context.sh", "timeout": 10 } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/turn-stamp.sh", "timeout": 5 } ] } ],
    "PreToolUse":       [ { "matcher": "Write", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh", "timeout": 10 } ] },
                            { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/rtk-rewrite.sh", "timeout": 10 } ] } ],
    "PostToolUse":      [ { "matcher": "Edit|Write|NotebookEdit", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/format-lint.sh", "timeout": 60 },
                                                                              { "type": "command", "command": "$HOME/.claude/hooks/size-guard.sh", "timeout": 20 },
                                                                              { "type": "command", "command": "$HOME/.claude/hooks/tamper-notice.sh", "timeout": 10 } ] } ],
    "Stop":             [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/stop-gate.sh", "timeout": 600 } ] } ],
    "PreCompact":       [ { "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/pre-compact-backup.sh", "timeout": 20 } ] } ]
  }
}
JSON

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "settings:hooks-key"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_hooks_key_wrong_matcher_within_multiblock_event_is_fail status-fail"
	assert_contains "$OUT" "PreToolUse: git-guard.sh not wired" "t_cli_doctor_hooks_key_wrong_matcher_within_multiblock_event_is_fail names-git-guard"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor — symlink checks must resolve a symlinked ancestor of $HOME the same
# way as the deployed symlink target (macOS /var -> /private/var pattern).
# ---------------------------------------------------------------------------

t_cli_doctor_symlink_pass_through_symlinked_home_ancestor() {
	local work real_root symlinked_root home item block
	work=$(tmp_dir)
	real_root="$work/real_root"
	symlinked_root="$work/symlinked_root"
	mkdir -p "$real_root"
	ln -s "$real_root" "$symlinked_root"
	home="$symlinked_root/home_actual"

	mkdir -p "$home/.dotfiles/claude/.claude/skills" \
		"$home/.dotfiles/claude/.claude/agents" \
		"$home/.dotfiles/claude/.claude/commands" \
		"$home/.dotfiles/claude/.claude/scripts" \
		"$home/.dotfiles/claude/.claude/hooks"
	: >"$home/.dotfiles/claude/.claude/settings.json"
	: >"$home/.dotfiles/claude/.claude/CLAUDE.md"
	mkdir -p "$home/.claude"
	for item in skills agents commands scripts hooks settings.json CLAUDE.md; do
		ln -s "$home/.dotfiles/claude/.claude/$item" "$home/.claude/$item"
	done

	cli_in "$home" "$home" doctor --json
	for item in skills agents commands scripts hooks settings.json CLAUDE.md; do
		block=$(printf '%s' "$OUT" | grep -A1 "\"id\": \"symlink:$item\"")
		assert_contains "$block" '"status": "PASS"' "t_cli_doctor_symlink_pass_through_symlinked_home_ancestor $item-pass"
	done

	rm -rf "$work"
}

# ---------------------------------------------------------------------------
# doctor — tool checks, hooks-drift, flow-config-overrides,
# flow-thresholds-referenced, skill-index-cost: presence and shape.
# ---------------------------------------------------------------------------

t_cli_doctor_json_includes_all_c9_check_families() {
	local home block
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json
	assert_contains "$OUT" '"id": "hooks-drift"' "t_cli_doctor_json_includes_all_c9_check_families hooks-drift-present"
	assert_contains "$OUT" '"id": "flow-config-overrides"' "t_cli_doctor_json_includes_all_c9_check_families overrides-present"
	assert_contains "$OUT" '"id": "flow-thresholds-referenced"' "t_cli_doctor_json_includes_all_c9_check_families thresholds-present"
	assert_contains "$OUT" '"id": "skill-index-cost"' "t_cli_doctor_json_includes_all_c9_check_families skill-index-present"

	block=$(printf '%s' "$OUT" | grep -A1 '"id": "tool:git"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_json_includes_all_c9_check_families tool-git-pass"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "tool:jq"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_json_includes_all_c9_check_families tool-jq-pass"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "tool:node"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_json_includes_all_c9_check_families tool-node-pass"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "tool:python3"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_json_includes_all_c9_check_families tool-python3-pass"

	rm -rf "$home"
}

t_cli_doctor_harness_json_overrides_warns_on_diff() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$proj/.claude"
	printf '{ "stopGate": false }\n' >"$proj/.claude/flow.config.json"

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "flow-config-overrides"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_harness_json_overrides_warns_on_diff status-warn"
	assert_contains "$OUT" 'overrides C4 defaults: stopGate' "t_cli_doctor_harness_json_overrides_warns_on_diff names-field"

	rm -rf "$home" "$proj"
}

t_cli_doctor_thresholds_referenced_warns_when_unreferenced() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$proj/.flow"
	printf 'export default {};\n' >"$proj/.flow/eslint.thresholds.mjs"

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "flow-thresholds-referenced"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_thresholds_referenced_warns_when_unreferenced status-warn"
	assert_contains "$OUT" 'eslint.thresholds.mjs' "t_cli_doctor_thresholds_referenced_warns_when_unreferenced names-file"

	rm -rf "$home" "$proj"
}

t_cli_doctor_skill_index_cost_reports_chars_and_fattest() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude/skills/foo"
	cat >"$home/.claude/skills/foo/SKILL.md" <<'EOF'
---
name: foo
description: A test skill used only to exercise doctor's skill-index-cost accounting.
---
# Foo
EOF

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "skill-index-cost"')
	assert_contains "$block" 'chars' "t_cli_doctor_skill_index_cost_reports_chars_and_fattest has-chars"
	assert_contains "$block" 'foo (' "t_cli_doctor_skill_index_cost_reports_chars_and_fattest names-fattest-skill"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor — tool checks (`have`) must work on a PATH with no `which` binary at
# all (C15 fix-only packet U5: PATH walk with fs.accessSync(X_OK), not
# spawnSync('which', ...)).
# ---------------------------------------------------------------------------

t_cli_have_works_without_which_on_path() {
	local home fakebin restricted_path block
	home=$(tmp_dir)
	fakebin=$(tmp_dir)

	# A fake, executable "git" so have('git') has a real match to find.
	printf '#!/usr/bin/env bash\necho fake-git\n' >"$fakebin/git"
	chmod +x "$fakebin/git"

	# Symlink the real node binary into fakebin instead of adding node's whole
	# directory to PATH — its directory (e.g. /bin) also ships `which`, which
	# would defeat the point of this test.
	ln -s "$(command -v node)" "$fakebin/node"

	restricted_path="$fakebin"

	# Sanity: this restricted PATH truly has no `which` binary anywhere on it —
	# have() cannot fall back to spawning `which` and get lucky. (bash itself is
	# resolved via the test runner's own PATH here; only the inner PATH used by
	# `command -v` is restricted.)
	run_cmd bash -c 'export PATH="$1"; command -v which' _ "$restricted_path"
	assert_rc 1 "t_cli_have_works_without_which_on_path sanity-no-which-on-path"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$restricted_path" node "$CLI_PATH" doctor --json

	block=$(printf '%s' "$OUT" | grep -A1 '"id": "tool:git"')
	assert_contains "$block" '"status": "PASS"' "t_cli_have_works_without_which_on_path tool-git-pass-without-which"

	rm -rf "$home" "$fakebin"
}

# ---------------------------------------------------------------------------
# doctor — skills-lint summary line: skip when absent (per unit map), real
# JSON content when present.
# ---------------------------------------------------------------------------

t_cli_doctor_skills_lint_skipped_when_absent() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json
	assert_not_contains "$OUT" '"id": "skills-lint"' "t_cli_doctor_skills_lint_skipped_when_absent no-check-line"

	rm -rf "$home"
}

t_cli_doctor_skills_lint_present_reports_json() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/.claude/scripts"
	cat >"$home/.claude/scripts/skills-lint" <<'EOF'
#!/usr/bin/env bash
echo "MISSING file.md:3 ~/.claude/skills/x/y.md"
echo "MISSING file.md:9 ~/.claude/skills/x/z.md"
echo "TOOL file.md:4 rtk"
exit 1
EOF
	chmod +x "$home/.claude/scripts/skills-lint"

	cli_in "$home" "$home" doctor --json
	assert_contains "$OUT" '"id": "skills-lint"' "t_cli_doctor_skills_lint_present_reports_json check-line-present"
	block=$(printf '%s' "$OUT" | grep -A1 '"id": "skills-lint"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_skills_lint_present_reports_json status-fail"
	assert_contains "$OUT" "2 missing reference(s), 1 tool note(s)" "t_cli_doctor_skills_lint_present_reports_json detail-counts"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# check — real (non---help) exec/CI=true/exit-passthrough behavior
# ---------------------------------------------------------------------------

t_cli_check_execs_check_all_with_ci_true_and_passes_through_exit_code() {
	local home
	home=$(tmp_dir)
	mkdir -p "$home/.claude/skills/shared/scripts"
	cat >"$home/.claude/skills/shared/scripts/check-all" <<'EOF'
#!/usr/bin/env bash
echo "CI=${CI:-unset}"
echo "args=$*"
exit 3
EOF
	chmod +x "$home/.claude/skills/shared/scripts/check-all"

	cli_in "$home" "$home" check --fix
	assert_rc 3 "t_cli_check_execs_check_all_with_ci_true_and_passes_through_exit_code rc-passthrough"
	assert_contains "$OUT" "CI=true" "t_cli_check_execs_check_all_with_ci_true_and_passes_through_exit_code ci-true-env"
	assert_contains "$OUT" "args=--fix" "t_cli_check_execs_check_all_with_ci_true_and_passes_through_exit_code flag-passthrough"

	rm -rf "$home"
}

t_cli_check_missing_check_all_prints_message_and_exits_1() {
	local home
	home=$(tmp_dir)

	export FLOW_SHARED_SCRIPTS_DIR=/nonexistent
	cli_in "$home" "$home" check
	unset FLOW_SHARED_SCRIPTS_DIR
	assert_rc 1 "t_cli_check_missing_check_all_prints_message_and_exits_1 rc"
	assert_contains "$ERR" "not found" "t_cli_check_missing_check_all_prints_message_and_exits_1 message"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# skills-lint (subcommand) — real exec/exit-passthrough behavior
# ---------------------------------------------------------------------------

t_cli_skills_lint_subcommand_execs_and_passes_through_exit_code() {
	local home
	home=$(tmp_dir)
	mkdir -p "$home/.claude/scripts"
	cat >"$home/.claude/scripts/skills-lint" <<'EOF'
#!/usr/bin/env bash
echo "skills-lint ran with args: $*"
exit 5
EOF
	chmod +x "$home/.claude/scripts/skills-lint"

	cli_in "$home" "$home" skills-lint --foo
	assert_rc 5 "t_cli_skills_lint_subcommand_execs_and_passes_through_exit_code rc-passthrough"
	assert_contains "$OUT" "skills-lint ran with args: --foo" "t_cli_skills_lint_subcommand_execs_and_passes_through_exit_code flag-passthrough"

	rm -rf "$home"
}

t_cli_skills_lint_subcommand_missing_prints_message_and_exits_1() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" skills-lint
	assert_rc 1 "t_cli_skills_lint_subcommand_missing_prints_message_and_exits_1 rc"
	assert_contains "$ERR" "not found" "t_cli_skills_lint_subcommand_missing_prints_message_and_exits_1 message"

	rm -rf "$home"
}

t_cli_skills_lint_subcommand_help_exits_0() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" skills-lint --help
	assert_rc 0 "t_cli_skills_lint_subcommand_help_exits_0 rc"
	assert_contains "$OUT" "Usage:" "t_cli_skills_lint_subcommand_help_exits_0 usage-line"

	rm -rf "$home"
}
