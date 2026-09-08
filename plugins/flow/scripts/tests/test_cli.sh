#!/usr/bin/env bash
# test_cli.sh — unit U5 (harness-cli) tests for bin/.local/bin/flow.
# Sourced by run.sh; every t_cli_* function below is discovered and run.
set -u

# CLI_PATH per C9/unit map: "$HERE/../../../.." is the repo root.
CLI_PATH=""
CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
CLI_PATH="$CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && CLI_PATH="$SCAN_DIR/../bin/flow"

# cli_in <project-dir> <home-dir> <harness-args...>
# Runs `node $CLI_PATH <args>` with cwd=<project-dir> and HOME=<home-dir>,
# without touching this test runner's own cwd. Sets RC/OUT/ERR via run_cmd.
# DOTFILES is unset: it is one of the roots `flow install` (and the doctor's
# install-source check) searches, so inheriting a developer's own value would
# make these assertions depend on the machine.
cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; unset DOTFILES; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$CLI_PATH" "$@"
}

# cli_in_path <project-dir> <home-dir> <extra-PATH-dir> <harness-args...>
# Like cli_in, but with <extra-PATH-dir> prepended to PATH so a stub linter
# (FU-12: `flow init` measures thresholds by running the real linter once)
# is what `flow init` finds.
cli_in_path() {
	local dir home extra
	dir=$1
	home=$2
	extra=$3
	shift 3
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; export PATH="$3:$PATH"; unset DOTFILES; shift 3; exec "$@"' \
		_ "$dir" "$home" "$extra" node "$CLI_PATH" "$@"
}

# _cli_stub <path> <body...> — an executable stub script at <path>.
_cli_stub() {
	local p
	p=$1
	shift
	mkdir -p "$(dirname "$p")"
	{
		printf '#!/usr/bin/env bash\n'
		printf '%s\n' "$@"
	} >"$p"
	chmod +x "$p"
}

# _cli_write_hook_files <hooks-dir>
# Creates all 8 C5 hook files (empty stub, executable) under <hooks-dir>.
_cli_write_hook_files() {
	local dir h
	dir=$1
	mkdir -p "$dir"
	for h in session-context.sh turn-stamp.sh git-guard.sh \
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
    "PreToolUse":       [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/git-guard.sh", "timeout": 10 } ] } ],
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
	# FU-12: thresholds are written only when the linter is installed, and at
	# or above what it reports today — this eslint reports a 520-line file.
	_cli_stub "$proj/node_modules/.bin/eslint" \
		'echo "[{\"filePath\":\"a.js\",\"messages\":[{\"ruleId\":\"max-lines\",\"message\":\"File has too many lines (520). Maximum allowed is 400.\"}]}]"' \
		'exit 1'

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_node_creates_expected_files_and_thresholds rc"
	assert_file_exists "$proj/REVIEW.md" "t_cli_init_node_creates_expected_files_and_thresholds review"
	assert_file_exists "$proj/PROGRESS.md" "t_cli_init_node_creates_expected_files_and_thresholds progress"
	assert_file_exists "$proj/.claude/flow.config.json" "t_cli_init_node_creates_expected_files_and_thresholds harness-json"
	assert_file_exists "$proj/.github/workflows/gates.yml" "t_cli_init_node_creates_expected_files_and_thresholds gates"
	assert_file_exists "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_node_creates_expected_files_and_thresholds thresholds-file"
	assert_file_exists "$proj/CLAUDE.md" "t_cli_init_node_creates_expected_files_and_thresholds claude-md"

	thresholds=$(cat "$proj/.flow/eslint.thresholds.mjs")
	assert_contains "$thresholds" "'max-lines': ['error', { max: 520" "t_cli_init_node_creates_expected_files_and_thresholds max-lines-raised-to-measured-max"
	assert_contains "$OUT" "raised to this repo's current maximum" "t_cli_init_node_creates_expected_files_and_thresholds says-it-raised"
	assert_contains "$thresholds" "'max-lines-per-function': ['error', { max: 60" "t_cli_init_node_creates_expected_files_and_thresholds max-lines-per-function-60"
	assert_contains "$thresholds" "complexity: ['error', 10]" "t_cli_init_node_creates_expected_files_and_thresholds complexity-10"
	assert_contains "$thresholds" "'max-params': ['error', 4]" "t_cli_init_node_creates_expected_files_and_thresholds max-params-4"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-node@v4" "t_cli_init_node_creates_expected_files_and_thresholds gates-uses-setup-node"
	assert_contains "$gates" "run: npm ci" "t_cli_init_node_creates_expected_files_and_thresholds gates-installs-with-npm-ci"
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

# FU-12: the measured value is read from each rule's own phrasing, never as
# "the first integer in the message" — real code is full of digit-bearing
# identifiers (sha256Digest, oauth2Login, parse2) whose digits come first.
t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer() {
	local home proj thresholds
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test","lint":"echo lint"}}
EOF
	mkdir -p "$proj/node_modules/.bin"
	cat >"$proj/node_modules/.bin/eslint" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
[{"filePath":"a.js","messages":[
 {"ruleId":"max-lines-per-function","message":"Function 'parse2' has too many lines (520). Maximum allowed is 60."},
 {"ruleId":"complexity","message":"Function 'sha256Digest' has a complexity of 42. Maximum allowed is 10."},
 {"ruleId":"max-params","message":"Function 'oauth2Login' has too many parameters (9). Maximum allowed is 4."}
]}]
JSON
exit 1
STUB
	chmod +x "$proj/node_modules/.bin/eslint"

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer rc"
	thresholds=$(cat "$proj/.flow/eslint.thresholds.mjs")
	assert_contains "$thresholds" "'max-lines-per-function': ['error', { max: 520" "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer func-lines-520"
	assert_contains "$thresholds" "complexity: ['error', 42]" "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer complexity-42"
	assert_contains "$thresholds" "'max-params': ['error', 9]" "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer max-params-9"
	assert_not_contains "$thresholds" "complexity: ['error', 256]" "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer not-256"
	assert_not_contains "$thresholds" "'max-lines-per-function': ['error', { max: 60" "t_cli_init_node_thresholds_read_the_rule_pattern_not_the_first_integer not-defaulted-60"

	rm -rf "$home" "$proj"
}

# A rule whose message does not match its pattern is UNMEASURED: the key falls
# back to the harness default AND init says so, instead of printing a default
# as though it had been measured.
t_cli_init_node_unparsable_lint_message_is_reported_as_unmeasured() {
	local home proj thresholds
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test"}}
EOF
	_cli_stub "$proj/node_modules/.bin/eslint" \
		'echo "[{\"filePath\":\"a.js\",\"messages\":[{\"ruleId\":\"complexity\",\"message\":\"sha256Digest is over budget\"}]}]"' \
		'exit 1'

	cli_in "$proj" "$home" init
	thresholds=$(cat "$proj/.flow/eslint.thresholds.mjs")
	assert_contains "$thresholds" "complexity: ['error', 10]" "t_cli_init_node_unparsable_lint_message_is_reported_as_unmeasured default-kept"
	assert_contains "$OUT" "not a measurement" "t_cli_init_node_unparsable_lint_message_is_reported_as_unmeasured warns"
	assert_not_contains "$thresholds" "complexity: ['error', 256]" "t_cli_init_node_unparsable_lint_message_is_reported_as_unmeasured not-256"

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
	_cli_stub "$proj/.venv/bin/ruff" \
		'echo "[{\"code\":\"C901\",\"message\":\"f is too complex (14 > 10)\"}]"' \
		'exit 1'

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_python_creates_ruff_thresholds rc"
	assert_file_exists "$proj/.flow/ruff.thresholds.toml" "t_cli_init_python_creates_ruff_thresholds thresholds-file"
	assert_file_missing "$proj/clippy.toml" "t_cli_init_python_creates_ruff_thresholds no-clippy"

	thresholds=$(cat "$proj/.flow/ruff.thresholds.toml")
	assert_contains "$thresholds" 'max-complexity = 14' "t_cli_init_python_creates_ruff_thresholds max-complexity-raised-to-measured"
	assert_contains "$thresholds" 'max-branches = 12' "t_cli_init_python_creates_ruff_thresholds max-branches-12"
	assert_contains "$thresholds" 'max-statements = 50' "t_cli_init_python_creates_ruff_thresholds max-statements-50"
	assert_contains "$thresholds" 'select = ["E", "F", "I", "N", "UP", "B", "S", "C90", "PL"]' "t_cli_init_python_creates_ruff_thresholds select-list"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-python@v5" "t_cli_init_python_creates_ruff_thresholds gates-uses-setup-python"
	assert_contains "$gates" "run: pytest" "t_cli_init_python_creates_ruff_thresholds gates-test-cmd"

	rm -rf "$home" "$proj"
}

# FU-12 for ruff: C901 names the function first, and `sha256_digest` puts 256
# in front of the real measurement (42).
t_cli_init_python_ruff_complexity_ignores_digits_in_the_function_name() {
	local home proj thresholds
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/pyproject.toml" <<'EOF'
[project]
name = "x"

[tool.ruff]
EOF
	mkdir -p "$proj/.venv/bin"
	cat >"$proj/.venv/bin/ruff" <<'STUB'
#!/usr/bin/env bash
cat <<'JSON'
[{"code":"C901","message":"`sha256_digest` is too complex (42 > 10)"},
 {"code":"PLR0912","message":"Too many branches (30 > 12)"}]
JSON
exit 1
STUB
	chmod +x "$proj/.venv/bin/ruff"

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_python_ruff_complexity_ignores_digits_in_the_function_name rc"
	thresholds=$(cat "$proj/.flow/ruff.thresholds.toml")
	assert_contains "$thresholds" 'max-complexity = 42' "t_cli_init_python_ruff_complexity_ignores_digits_in_the_function_name complexity-42"
	assert_contains "$thresholds" 'max-branches = 30' "t_cli_init_python_ruff_complexity_ignores_digits_in_the_function_name branches-30"
	assert_not_contains "$thresholds" 'max-complexity = 256' "t_cli_init_python_ruff_complexity_ignores_digits_in_the_function_name not-256"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — rust stack
# ---------------------------------------------------------------------------

t_cli_init_rust_creates_clippy_toml_only_if_absent() {
	local home proj clippy gates fakebin
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/Cargo.toml" <<'EOF'
[package]
name = "x"
EOF
	: >"$proj/Cargo.lock" # detect-project keys its package-manager detection off this
	fakebin=$(tmp_dir)
	_cli_stub "$fakebin/cargo" 'exit 0'
	_cli_stub "$fakebin/cargo-clippy" 'exit 0'

	cli_in_path "$proj" "$home" "$fakebin" init
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
	cli_in_path "$proj" "$home" "$fakebin" init --force
	assert_eq "$(cat "$proj/clippy.toml")" "SENTINEL" "t_cli_init_rust_creates_clippy_toml_only_if_absent never-force-overwritten"

	rm -rf "$home" "$proj" "$fakebin"
}

# ---------------------------------------------------------------------------
# init — go stack
# ---------------------------------------------------------------------------

t_cli_init_go_creates_golangci_yml() {
	local home proj golangci gates fakebin
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/go.mod" <<'EOF'
module example.com/x

go 1.22
EOF
	: >"$proj/go.sum" # detect-project keys its package-manager detection off this
	fakebin=$(tmp_dir)
	_cli_stub "$fakebin/golangci-lint" 'exit 0'

	cli_in_path "$proj" "$home" "$fakebin" init
	assert_rc 0 "t_cli_init_go_creates_golangci_yml rc"
	assert_file_exists "$proj/.golangci.yml" "t_cli_init_go_creates_golangci_yml created"

	golangci=$(cat "$proj/.golangci.yml")
	assert_contains "$golangci" "lines: 60" "t_cli_init_go_creates_golangci_yml funlen-60"
	assert_contains "$golangci" "min-complexity: 10" "t_cli_init_go_creates_golangci_yml gocyclo-10"

	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-go@v5" "t_cli_init_go_creates_golangci_yml gates-uses-setup-go"
	assert_contains "$gates" "run: go test ./..." "t_cli_init_go_creates_golangci_yml gates-test-cmd"

	rm -rf "$home" "$proj" "$fakebin"
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
	local home proj fakebin
	home=$(tmp_dir)
	proj=$(tmp_dir)
	# No manifest at all, but force --stack go.
	fakebin=$(tmp_dir)
	_cli_stub "$fakebin/golangci-lint" 'exit 0'
	cli_in_path "$proj" "$home" "$fakebin" init --stack go
	assert_rc 0 "t_cli_init_explicit_stack_overrides_autodetect rc"
	assert_file_exists "$proj/.golangci.yml" "t_cli_init_explicit_stack_overrides_autodetect golangci-written"
	assert_not_contains "$OUT" "no stack detected" "t_cli_init_explicit_stack_overrides_autodetect no-empty-message"

	rm -rf "$home" "$proj" "$fakebin"
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
# matcher:"Bash" wired only to an unrelated hook file — with every other event wired
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
                            { "matcher": "Bash", "hooks": [ { "type": "command", "command": "$HOME/.claude/hooks/session-context.sh", "timeout": 10 } ] } ],
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

	cli_in "$home" "$home" doctor --json --deep
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

	# B25: skills-lint is slow, so it runs only under --deep.
	cli_in "$home" "$home" doctor --json
	assert_not_contains "$OUT" '"id": "skills-lint"' "t_cli_doctor_skills_lint_present_reports_json skipped-without-deep"

	cli_in "$home" "$home" doctor --json --deep
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

# ---------------------------------------------------------------------------
# init — FU-12: no linter, no thresholds file (and it says why)
# ---------------------------------------------------------------------------

t_cli_init_without_linter_writes_no_thresholds() {
	local home proj empty
	home=$(tmp_dir)
	proj=$(tmp_dir)
	empty=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test"}}
EOF

	# No node_modules/.bin/eslint here; init must write no thresholds file at
	# all and name the reason instead of shipping numbers it never measured.
	cli_in_path "$proj" "$home" "$empty" init
	assert_rc 0 "t_cli_init_without_linter_writes_no_thresholds rc"
	assert_file_missing "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_without_linter_writes_no_thresholds nothing-written"
	assert_contains "$OUT" "no .flow/eslint.thresholds.mjs written" "t_cli_init_without_linter_writes_no_thresholds says-why"
	# The linter really is absent here, so "install it" is advice init can back up.
	assert_contains "$OUT" "install it and re-run flow init" "t_cli_init_without_linter_writes_no_thresholds install-advice"
	assert_file_exists "$proj/.github/workflows/gates.yml" "t_cli_init_without_linter_writes_no_thresholds gates-still-written"

	rm -rf "$home" "$proj" "$empty"
}

# ---------------------------------------------------------------------------
# init — a linter that IS installed but fails is not answered with "install it"
# ---------------------------------------------------------------------------

t_cli_init_linter_error_does_not_prescribe_installing_it() {
	local home proj empty
	home=$(tmp_dir)
	proj=$(tmp_dir)
	empty=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test"}}
EOF
	# Present, executable, and broken: measureLinter's 'error' case.
	_cli_stub "$proj/node_modules/.bin/eslint" 'echo "Failed to parse config" >&2' 'exit 2'

	cli_in_path "$proj" "$home" "$empty" init
	assert_rc 0 "t_cli_init_linter_error_does_not_prescribe_installing_it rc"
	assert_file_missing "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_linter_error_does_not_prescribe_installing_it nothing-written"
	assert_contains "$OUT" "eslint exited 2" "t_cli_init_linter_error_does_not_prescribe_installing_it names-the-failure"
	assert_contains "$OUT" "fix the error above and re-run flow init" "t_cli_init_linter_error_does_not_prescribe_installing_it fix-the-error"
	assert_not_contains "$OUT" "install it and re-run flow init" "t_cli_init_linter_error_does_not_prescribe_installing_it no-install-advice"

	rm -rf "$home" "$proj" "$empty"
}

# ---------------------------------------------------------------------------
# init — FU-11: the CI setup step follows the detected package manager
# ---------------------------------------------------------------------------

t_cli_init_gates_setup_step_follows_pkg_mgr() {
	local home proj gates
	home=$(tmp_dir)

	proj=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"bun test"}}\n' >"$proj/package.json"
	: >"$proj/bun.lock"
	cli_in "$proj" "$home" init
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "oven-sh/setup-bun@v2" "t_cli_init_gates_setup_step_follows_pkg_mgr bun-setup"
	assert_contains "$gates" "run: bun install --frozen-lockfile" "t_cli_init_gates_setup_step_follows_pkg_mgr bun-install"
	rm -rf "$proj"

	proj=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"vitest run"}}\n' >"$proj/package.json"
	: >"$proj/pnpm-lock.yaml"
	cli_in "$proj" "$home" init
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "pnpm/action-setup@v4" "t_cli_init_gates_setup_step_follows_pkg_mgr pnpm-setup"
	assert_contains "$gates" "run: pnpm install --frozen-lockfile" "t_cli_init_gates_setup_step_follows_pkg_mgr pnpm-install"
	rm -rf "$proj"

	proj=$(tmp_dir)
	printf '[project]\nname = "x"\nrequires-python = ">=3.11"\n' >"$proj/pyproject.toml"
	: >"$proj/uv.lock"
	cli_in "$proj" "$home" init
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "astral-sh/setup-uv@v5" "t_cli_init_gates_setup_step_follows_pkg_mgr uv-setup"
	assert_contains "$gates" "run: uv sync" "t_cli_init_gates_setup_step_follows_pkg_mgr uv-install"
	assert_contains "$gates" "python-version: '3.11'" "t_cli_init_gates_setup_step_follows_pkg_mgr python-version-from-requires-python"
	rm -rf "$proj"

	# FU-11 "start green": a python repo without uv still needs its dependencies
	# installed, or the test gate is red on the first CI run.
	proj=$(tmp_dir)
	printf '[project]\nname = "x"\nrequires-python = ">=3.12"\n' >"$proj/pyproject.toml"
	cli_in "$proj" "$home" init
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "actions/setup-python@v5" "t_cli_init_gates_setup_step_follows_pkg_mgr pip-setup-python"
	assert_contains "$gates" "run: pip install -e ." "t_cli_init_gates_setup_step_follows_pkg_mgr pip-install-project"
	rm -rf "$proj"

	proj=$(tmp_dir)
	printf 'pytest\n' >"$proj/requirements.txt"
	printf '[project]\nname = "x"\n' >"$proj/pyproject.toml"
	cli_in "$proj" "$home" init
	gates=$(cat "$proj/.github/workflows/gates.yml")
	assert_contains "$gates" "run: pip install -r requirements.txt" "t_cli_init_gates_setup_step_follows_pkg_mgr pip-install-requirements"
	rm -rf "$proj"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# init — --force keeps a copy of the files it overwrites, and every written
# path is named in one `git add` line
# ---------------------------------------------------------------------------

t_cli_init_force_backs_up_and_prints_git_add() {
	local home proj backup
	home=$(tmp_dir)
	proj=$(tmp_dir)
	printf 'MY REVIEW\n' >"$proj/REVIEW.md"
	printf 'MY PROGRESS\n' >"$proj/PROGRESS.md"

	cli_in "$proj" "$home" init --force
	assert_rc 0 "t_cli_init_force_backs_up_and_prints_git_add rc"
	assert_contains "$OUT" "git add REVIEW.md PROGRESS.md" "t_cli_init_force_backs_up_and_prints_git_add git-add-line"

	backup=$(find "$proj" -maxdepth 1 -name 'REVIEW.md.pre-flow.*' | head -1)
	assert_eq "$(cat "$backup")" "MY REVIEW" "t_cli_init_force_backs_up_and_prints_git_add review-backup"
	backup=$(find "$proj" -maxdepth 1 -name 'PROGRESS.md.pre-flow.*' | head -1)
	assert_eq "$(cat "$backup")" "MY PROGRESS" "t_cli_init_force_backs_up_and_prints_git_add progress-backup"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# init — FU-21: .claude/settings.json gains permissions.deny, but an existing
# permissions block is never clobbered
# ---------------------------------------------------------------------------

t_cli_init_writes_permissions_deny() {
	local home proj settings
	home=$(tmp_dir)
	proj=$(tmp_dir)

	cli_in "$proj" "$home" init
	settings=$(cat "$proj/.claude/settings.json")
	assert_contains "$settings" 'Bash(git push --force*)' "t_cli_init_writes_permissions_deny force-push"
	assert_contains "$settings" 'Bash(git reset --hard*)' "t_cli_init_writes_permissions_deny reset-hard"
	assert_contains "$settings" 'Bash(rm -rf ~*)' "t_cli_init_writes_permissions_deny rm-rf-home"

	# A settings.json with other keys but no permissions: merged, not clobbered.
	rm -f "$proj/.claude/settings.json"
	printf '{ "model": "opus" }\n' >"$proj/.claude/settings.json"
	cli_in "$proj" "$home" init
	settings=$(cat "$proj/.claude/settings.json")
	assert_contains "$settings" '"model": "opus"' "t_cli_init_writes_permissions_deny keeps-other-keys"
	assert_contains "$settings" 'Bash(git push -f*)' "t_cli_init_writes_permissions_deny merged-deny"

	# An existing permissions block is left exactly as it was.
	printf '{ "permissions": { "allow": ["Bash(ls*)"] } }\n' >"$proj/.claude/settings.json"
	cli_in "$proj" "$home" init
	assert_eq "$(cat "$proj/.claude/settings.json")" '{ "permissions": { "allow": ["Bash(ls*)"] } }' "t_cli_init_writes_permissions_deny never-clobbers"
	assert_contains "$OUT" "has its own permissions key, skip" "t_cli_init_writes_permissions_deny says-it-skipped"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor — config-schema (B25): unknown key WARNs, a wrong type FAILs
# ---------------------------------------------------------------------------

t_cli_doctor_config_schema_unknown_key_warns() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$proj/.claude"
	printf '{ "stopGate": "scoped", "stopGait": true }\n' >"$proj/.claude/flow.config.json"

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "config-schema"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_config_schema_unknown_key_warns status-warn"
	assert_contains "$block" 'stopGait' "t_cli_doctor_config_schema_unknown_key_warns names-the-key"

	rm -rf "$home" "$proj"
}

t_cli_doctor_config_schema_wrong_type_fails() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$proj/.claude"
	printf '{ "stopGate": "sometimes", "maxFileLines": "400", "ignore": "build/", "weirdKey": 1 }\n' >"$proj/.claude/flow.config.json"

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "config-schema"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_config_schema_wrong_type_fails status-fail"
	assert_contains "$block" 'stopGate must be one of' "t_cli_doctor_config_schema_wrong_type_fails names-stopgate"
	assert_contains "$block" 'maxFileLines must be a positive number' "t_cli_doctor_config_schema_wrong_type_fails names-maxfilelines"
	assert_contains "$block" 'ignore must be an array' "t_cli_doctor_config_schema_wrong_type_fails names-ignore"
	# One run reports every problem: a type error must not hide the unknown key.
	assert_contains "$block" 'weirdKey' "t_cli_doctor_config_schema_wrong_type_fails names-the-unknown-key-too"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor — project-hooks (FU-16): a project registering its own hooks on a
# flow-owned event is a WARN naming the event
# ---------------------------------------------------------------------------

t_cli_doctor_project_hooks_warns_on_shared_event() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	mkdir -p "$proj/.claude"
	printf '{ "hooks": { "PostToolUse": [ { "hooks": [ { "type": "command", "command": "./x.sh" } ] } ] } }\n' \
		>"$proj/.claude/settings.json"

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "project-hooks"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_project_hooks_warns_on_shared_event status-warn"
	assert_contains "$block" 'PostToolUse' "t_cli_doctor_project_hooks_warns_on_shared_event names-the-event"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor — gates-runnable (R1): WARN with no ecosystem, FAIL when a gate's
# runner cannot be executed (check-all reports status "unavailable", C-C)
# ---------------------------------------------------------------------------

t_cli_doctor_gates_runnable_warns_without_ecosystem() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "gates-runnable"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_gates_runnable_warns_without_ecosystem status-warn"
	assert_contains "$block" 'no ecosystem' "t_cli_doctor_gates_runnable_warns_without_ecosystem names-reason"

	rm -rf "$home" "$proj"
}

t_cli_doctor_gates_runnable_fails_on_unavailable_gate() {
	local home proj shared block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	shared=$(tmp_dir)
	cat >"$shared/check-all" <<'EOF'
console.log(JSON.stringify({
  ecosystem: 'node',
  gates: [{ name: 'test', status: 'unavailable', message: 'bun: not found' }],
}));
EOF
	chmod +x "$shared/check-all"

	export FLOW_SHARED_SCRIPTS_DIR="$shared"
	cli_in "$proj" "$home" doctor --json
	unset FLOW_SHARED_SCRIPTS_DIR
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "gates-runnable"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_gates_runnable_fails_on_unavailable_gate status-fail"
	assert_contains "$block" 'bun: not found' "t_cli_doctor_gates_runnable_fails_on_unavailable_gate names-the-runner"
	# Rewritten from the old `run: flow check` assertion: `flow check` re-runs
	# the very command that could not start, so it cannot clear this FAIL. With
	# no package.json here there is no install to name either, so the line
	# carries no `→ run:` at all (the spec's "where one exists" clause).
	assert_not_contains "$block" 'run: flow check' "t_cli_doctor_gates_runnable_fails_on_unavailable_gate no-rerun-command"
	assert_not_contains "$block" '→ run:' "t_cli_doctor_gates_runnable_fails_on_unavailable_gate no-fix-command"
	assert_contains "$block" 'install it, or correct the script it names' "t_cli_doctor_gates_runnable_fails_on_unavailable_gate says-what-would-help"

	rm -rf "$home" "$proj" "$shared"
}

# A missing runner in a node project that never installed its dependencies has
# exactly one command that must happen first, and it is not a flow command.
t_cli_doctor_gates_runnable_fail_names_dependency_install() {
	local home proj shared block
	home=$(tmp_dir)
	proj=$(tmp_dir)
	shared=$(tmp_dir)
	printf '{"name":"x","scripts":{"lint":"eslint ."}}\n' >"$proj/package.json"
	cat >"$shared/check-all" <<'EOF'
console.log(JSON.stringify({
  ecosystem: 'node',
  gates: [{ name: 'lint', status: 'unavailable', message: 'cannot run: npm run lint' }],
}));
EOF
	chmod +x "$shared/check-all"

	export FLOW_SHARED_SCRIPTS_DIR="$shared"
	cli_in "$proj" "$home" doctor --json
	unset FLOW_SHARED_SCRIPTS_DIR
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "gates-runnable"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_gates_runnable_fail_names_dependency_install status-fail"
	assert_contains "$block" 'no node_modules/' "t_cli_doctor_gates_runnable_fail_names_dependency_install states-the-fact"
	assert_contains "$block" 'run: npm install' "t_cli_doctor_gates_runnable_fail_names_dependency_install names-the-install"
	assert_not_contains "$block" 'run: flow check' "t_cli_doctor_gates_runnable_fail_names_dependency_install no-rerun-command"

	rm -rf "$home" "$proj" "$shared"
}

# ---------------------------------------------------------------------------
# doctor — every FAIL that has a fix names it (B25)
# ---------------------------------------------------------------------------

t_cli_doctor_fail_lines_name_a_fix_command() {
	local home block
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:skills"')
	assert_contains "$block" 'run: flow install --force' "t_cli_doctor_fail_lines_name_a_fix_command symlink-fix"
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "settings:hooks-key"')
	assert_contains "$block" 'run: flow install' "t_cli_doctor_fail_lines_name_a_fix_command hooks-key-fix"

	rm -rf "$home"
}

# ---------------------------------------------------------------------------
# doctor — permissions-deny (FU-16)
# ---------------------------------------------------------------------------

# A symlink FAIL only answers with `flow install --force` when install has
# something to link from: with no dotfiles checkout it skips these items, so
# the rerun would leave the same FAIL standing.
t_cli_doctor_symlink_fail_without_install_source_offers_no_rerun() {
	local home block
	home=$(tmp_dir)

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:agents"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_symlink_fail_without_install_source_offers_no_rerun status-fail"
	assert_contains "$block" 'install has no source for it either' "t_cli_doctor_symlink_fail_without_install_source_offers_no_rerun states-the-fact"
	assert_not_contains "$block" 'run: flow install --force' "t_cli_doctor_symlink_fail_without_install_source_offers_no_rerun no-useless-rerun"

	rm -rf "$home"
}

# ...but ~/dotfiles (no leading dot) is one of the roots `flow install`
# searches, so on such a machine install DOES have a source and the FAIL
# keeps the `→ run:` line that fixes it.
t_cli_doctor_symlink_fail_with_home_dotfiles_root_offers_the_rerun() {
	local home block
	home=$(tmp_dir)
	mkdir -p "$home/dotfiles/claude/.claude/agents"

	cli_in "$home" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:agents"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_symlink_fail_with_home_dotfiles_root_offers_the_rerun status-fail"
	assert_contains "$block" 'run: flow install --force' "t_cli_doctor_symlink_fail_with_home_dotfiles_root_offers_the_rerun offers-the-rerun"
	assert_not_contains "$block" 'install has no source' "t_cli_doctor_symlink_fail_with_home_dotfiles_root_offers_the_rerun no-false-claim"

	rm -rf "$home"
}

# Same for $DOTFILES: install resolves its root from that env var too, so the
# doctor must not answer "install has no source for it either".
t_cli_doctor_symlink_fail_with_dotfiles_env_root_offers_the_rerun() {
	local home dots block
	home=$(tmp_dir)
	dots=$(tmp_dir)
	mkdir -p "$dots/claude/.claude/agents"

	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2" DOTFILES="$3"; shift 3; exec "$@"' \
		_ "$home" "$home" "$dots" node "$CLI_PATH" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "symlink:agents"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_symlink_fail_with_dotfiles_env_root_offers_the_rerun status-fail"
	assert_contains "$block" 'run: flow install --force' "t_cli_doctor_symlink_fail_with_dotfiles_env_root_offers_the_rerun offers-the-rerun"
	assert_not_contains "$block" 'install has no source' "t_cli_doctor_symlink_fail_with_dotfiles_env_root_offers_the_rerun no-false-claim"

	rm -rf "$home" "$dots"
}

# ---------------------------------------------------------------------------
# help — doctor executes this project's own gates, so both commands that can
# trigger that (doctor, and install's step-7 recheck) say so.
# ---------------------------------------------------------------------------

t_cli_help_names_the_project_gates_doctor_executes() {
	local home
	home=$(tmp_dir)

	cli_in "$home" "$home" --help
	assert_contains "$OUT" "EXECUTES this" "t_cli_help_names_the_project_gates_doctor_executes top-help"
	assert_contains "$OUT" "120s cap per gate" "t_cli_help_names_the_project_gates_doctor_executes top-help-budget"

	cli_in "$home" "$home" install --help
	assert_contains "$OUT" "gates-runnable check, which EXECUTES" "t_cli_help_names_the_project_gates_doctor_executes install-help"

	rm -rf "$home"
}

t_cli_doctor_permissions_deny_warns_then_passes() {
	local home proj block
	home=$(tmp_dir)
	proj=$(tmp_dir)

	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "permissions-deny"')
	assert_contains "$block" '"status": "WARN"' "t_cli_doctor_permissions_deny_warns_then_passes warn-when-absent"

	mkdir -p "$proj/.claude"
	printf '{ "permissions": { "deny": ["Bash(git push --force*)"] } }\n' >"$proj/.claude/settings.json"
	cli_in "$proj" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "permissions-deny"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_permissions_deny_warns_then_passes pass-when-denied"

	rm -rf "$home" "$proj"
}

# ---------------------------------------------------------------------------
# doctor — live-hooks-match-cwd (R1): hook edits in one checkout are not live
# while ~/.claude/hooks resolves into another
# ---------------------------------------------------------------------------

t_cli_doctor_live_hooks_match_cwd() {
	local home live other block
	home=$(tmp_dir)
	live=$(tmp_repo)
	other=$(tmp_repo)
	mkdir -p "$live/plugins/flow/hooks" "$other/plugins/flow/hooks" "$home/.claude"
	ln -s "$live/plugins/flow/hooks" "$home/.claude/hooks"

	cli_in "$other" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A3 '"id": "live-hooks-match-cwd"')
	assert_contains "$block" '"status": "FAIL"' "t_cli_doctor_live_hooks_match_cwd fail-in-other-checkout"
	assert_contains "$block" 'edits here are not live until merged into' "t_cli_doctor_live_hooks_match_cwd names-the-problem"
	# The suggested run repoints this machine at the cwd checkout; the detail
	# must say so, and say how to undo it, in the same line.
	assert_contains "$block" 'the run below repoints this machine at' "t_cli_doctor_live_hooks_match_cwd states-the-consequence"
	assert_contains "$block" 'revert it with: flow install --marketplace' "t_cli_doctor_live_hooks_match_cwd states-the-reversal"
	assert_contains "$block" "$(basename "$live")" "t_cli_doctor_live_hooks_match_cwd reversal-names-the-live-checkout"

	cli_in "$live" "$home" doctor --json
	block=$(printf '%s' "$OUT" | grep -A2 '"id": "live-hooks-match-cwd"')
	assert_contains "$block" '"status": "PASS"' "t_cli_doctor_live_hooks_match_cwd pass-in-the-live-checkout"

	rm -rf "$home" "$live" "$other"
}

# ---------------------------------------------------------------------------
# G10 round-2 — C5_HOOK_FILES / C5_WIRING may only name hook files this repo
# actually ships. `flow doctor` answers a missing C5 file with "→ run: flow
# install", and install can only link a file that exists in the source tree:
# a stale name there is an unfixable FAIL for every legacy (settings.json)
# deployment.
# ---------------------------------------------------------------------------

t_cli_doctor_c5_hook_files_all_ship_in_repo() {
	local hooks_dir names h missing
	hooks_dir="$SCAN_DIR/../hooks"
	# Every *.sh name inside the C5_HOOK_FILES array and the C5_WIRING map.
	names=$(sed -n '/^const C5_HOOK_FILES = \[/,/^};$/p' "$CLI_PATH" | grep -o "[A-Za-z0-9_-]*\.sh" | sort -u)
	if [ -z "$names" ]; then
		_fail "t_cli_doctor_c5_hook_files_all_ship_in_repo found-names" "no hook names parsed out of $CLI_PATH"
		return
	fi
	missing=""
	for h in $names; do
		[ -f "$hooks_dir/$h" ] || missing="$missing $h"
	done
	if [ -n "$missing" ]; then
		_fail "t_cli_doctor_c5_hook_files_all_ship_in_repo every-c5-file-exists" "not in plugins/flow/hooks/:$missing"
	else
		_pass "t_cli_doctor_c5_hook_files_all_ship_in_repo every-c5-file-exists"
	fi
}

# FU-12 — a linter that reports nothing has measured nothing: the defaults it
# falls back to must be stated as defaults, because they can sit BELOW what
# this repo does today (spreading them into the lint config then starts the
# gate red, which is exactly what the note has to warn about).
t_cli_init_node_unmeasured_thresholds_are_named_as_defaults() {
	local home proj thresholds
	home=$(tmp_dir)
	proj=$(tmp_dir)
	cat >"$proj/package.json" <<'EOF'
{"name":"x","scripts":{"test":"echo test","lint":"echo lint"}}
EOF
	# eslint runs, finds no violations of the measured rules (the repo's own
	# config does not enable them), and exits 0.
	_cli_stub "$proj/node_modules/.bin/eslint" 'echo "[]"' 'exit 0'

	cli_in "$proj" "$home" init
	assert_rc 0 "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults rc"
	assert_file_exists "$proj/.flow/eslint.thresholds.mjs" "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults thresholds-file"

	thresholds=$(cat "$proj/.flow/eslint.thresholds.mjs")
	assert_contains "$thresholds" "'max-lines': ['error', { max: 400" "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults default-written"
	assert_not_contains "$OUT" "raised to this repo's current maximum" "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults nothing-was-measured"
	assert_contains "$OUT" "eslint reported no max-lines, max-lines-per-function, complexity, max-params, max-depth today" \
		"t_cli_init_node_unmeasured_thresholds_are_named_as_defaults names-unmeasured-keys"
	assert_contains "$OUT" "the harness default, not a measurement" "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults says-default-not-measurement"
	assert_contains "$OUT" "the gate can start red" "t_cli_init_node_unmeasured_thresholds_are_named_as_defaults says-gate-may-start-red"

	rm -rf "$home" "$proj"
}
