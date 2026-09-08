#!/usr/bin/env bash
# test_quality.sh — unit U2 (hooks-quality) tests for format-lint.sh,
# size-guard.sh + size_guard.py, tamper-notice.sh and stop-gate.sh.
# Sourced by run.sh; every t_quality_* function below is discovered and run.
set -u

_FIXTURES="$SCAN_DIR/tests/fixtures"

# ---------------------------------------------------------------------------
# format-lint.sh
# ---------------------------------------------------------------------------

t_quality_format_lint_missing_file_path_ok() {
	run_hook "$SCAN_DIR/format-lint.sh" '{"tool_input":{}}'
	assert_rc 0 "t_quality_format_lint_missing_file_path_ok rc"
}

t_quality_format_lint_ignored_path_rc0() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/generated"
	printf 'def foo(:\n    pass\n' >"$d/generated/bad.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/generated/bad.py\"}}"
	assert_rc 0 "t_quality_format_lint_ignored_path_rc0 rc"
	rm -rf "$d"
}

t_quality_format_lint_format_on_edit_false_rc0() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	printf '{"formatOnEdit": false}\n' >"$d/.claude/flow.config.json"
	printf 'def foo(:\n    pass\n' >"$d/bad.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/bad.py\"}}" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_quality_format_lint_format_on_edit_false_rc0 rc"
	rm -rf "$d"
}

# Rewritten for G4: a formatter that exits non-zero is ADVISORY (a systemMessage
# note, rc 0) — it used to be hook_feedback/rc 2. And ruff only runs at all when
# the project has ruff config, so the fixture now carries a ruff.toml.
t_quality_format_lint_py_syntax_error_advisory() {
	local d
	if ! have_ruff; then
		printf '  skip t_quality_format_lint_py_syntax_error_advisory (ruff not installed)\n'
		return 0
	fi
	d=$(tmp_repo)
	: >"$d/ruff.toml"
	printf 'def foo(:\n    pass\n' >"$d/bad.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/bad.py\"}}"
	assert_rc 0 "t_quality_format_lint_py_syntax_error_advisory rc"
	assert_eq "$ERR" "" "t_quality_format_lint_py_syntax_error_advisory nothing-on-stderr"
	assert_contains "$OUT" "formatter ruff failed on" "t_quality_format_lint_py_syntax_error_advisory message"
	assert_contains "$OUT" "bad.py" "t_quality_format_lint_py_syntax_error_advisory filename"
	rm -rf "$d"
}

t_quality_format_lint_py_clean_format_rc0() {
	local d
	if ! have_ruff; then
		printf '  skip t_quality_format_lint_py_clean_format_rc0 (ruff not installed)\n'
		return 0
	fi
	d=$(tmp_repo)
	: >"$d/ruff.toml"
	printf 'def   foo( ):\n  return   1\n' >"$d/ok.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/ok.py\"}}"
	assert_rc 0 "t_quality_format_lint_py_clean_format_rc0 rc"
	assert_contains "$(cat "$d/ok.py")" "def foo():" "t_quality_format_lint_py_clean_format_rc0 reformatted"
	rm -rf "$d"
}

have_ruff() { command -v ruff >/dev/null 2>&1; }

# _q_recorder <dir> <name> <marker> [rc] [stderr-text] — an executable stub that
# appends "<cwd> | <args>" to <marker> so a test can prove which formatter ran,
# from which directory, with which arguments.
_q_recorder() {
	mkdir -p "$1"
	{
		printf '#!/usr/bin/env bash\n'
		printf 'printf "%%s | %%s\\n" "$PWD" "$*" >>%s\n' "$3"
		if [ -n "${5:-}" ]; then printf 'printf "%%s\\n" %s >&2\n' "'$5'"; fi
		printf 'exit %s\n' "${4:-0}"
	} >"$1/$2"
	chmod +x "$1/$2"
}

# _q_marker <file> — the recorded invocations, or "" when the stub never ran.
_q_marker() { cat "$1" 2>/dev/null || printf ''; }

t_quality_format_ruff_without_config_not_run() {
	local d bin
	d=$(tmp_repo)
	bin="$d/.venv/bin"
	_q_recorder "$bin" ruff "$d/ran.log"
	printf 'x=1\n' >"$d/a.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_format_ruff_without_config_not_run rc"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_ruff_without_config_not_run ruff-not-invoked"
	rm -rf "$d"
}

t_quality_format_ruff_venv_preferred_and_cwd_is_config_dir() {
	local d bin
	d=$(tmp_repo)
	mkdir -p "$d/pkg/src"
	: >"$d/pkg/ruff.toml"
	bin="$d/pkg/.venv/bin"
	_q_recorder "$bin" ruff "$d/ran.log"
	printf 'x=1\n' >"$d/pkg/src/a.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/pkg/src/a.py\"}}"
	assert_rc 0 "t_quality_format_ruff_venv_preferred_and_cwd_is_config_dir rc"
	assert_contains "$(_q_marker "$d/ran.log")" "format $d/pkg/src/a.py" "t_quality_format_ruff_venv_preferred_and_cwd_is_config_dir ran"
	assert_contains "$(_q_marker "$d/ran.log")" "$(cd "$d/pkg" && pwd -P) |" "t_quality_format_ruff_venv_preferred_and_cwd_is_config_dir cwd-is-nearest-config-dir"
	rm -rf "$d"
}

t_quality_format_ruff_uv_run_when_uv_lock() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	: >"$d/ruff.toml"
	: >"$d/uv.lock"
	_q_recorder "$bin" uv "$d/ran.log"
	printf 'x=1\n' >"$d/a.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_ruff_uv_run_when_uv_lock rc"
	assert_contains "$(_q_marker "$d/ran.log")" "run --no-sync ruff format" "t_quality_format_ruff_uv_run_when_uv_lock uv-run"
	rm -rf "$d"
}

t_quality_format_failure_is_advisory_note() {
	local d bin
	d=$(tmp_repo)
	bin="$d/.venv/bin"
	: >"$d/ruff.toml"
	_q_recorder "$bin" ruff "$d/ran.log" 3 "boom: cannot parse a.py"
	printf 'x=1\n' >"$d/a.py"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_format_failure_is_advisory_note rc"
	assert_eq "$ERR" "" "t_quality_format_failure_is_advisory_note nothing-on-stderr"
	assert_contains "$OUT" "systemMessage" "t_quality_format_failure_is_advisory_note note-channel"
	assert_contains "$OUT" "formatter ruff failed on a.py" "t_quality_format_failure_is_advisory_note names-tool-and-file"
	assert_contains "$OUT" "boom: cannot parse a.py" "t_quality_format_failure_is_advisory_note includes-output"
	rm -rf "$d"
}

t_quality_format_shfmt_needs_editorconfig() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	_q_recorder "$bin" shfmt "$d/ran.log"
	printf '#!/usr/bin/env bash\necho hi\n' >"$d/s.sh"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/s.sh\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_shfmt_needs_editorconfig rc"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_shfmt_needs_editorconfig not-invoked"
	printf 'root = true\n\n[*.sh]\nindent_style = tab\n' >"$d/.editorconfig"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/s.sh\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_shfmt_needs_editorconfig configured-rc"
	assert_contains "$(_q_marker "$d/ran.log")" "-w $d/s.sh" "t_quality_format_shfmt_needs_editorconfig configured-invoked"
	rm -rf "$d"
}

t_quality_format_shfmt_via_flow_config() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	mkdir -p "$d/.claude"
	printf '{"shfmt": true}\n' >"$d/.claude/flow.config.json"
	_q_recorder "$bin" shfmt "$d/ran.log"
	printf '#!/usr/bin/env bash\necho hi\n' >"$d/s.sh"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/s.sh\"}}" PATH="$bin:$PATH" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_quality_format_shfmt_via_flow_config rc"
	assert_contains "$(_q_marker "$d/ran.log")" "-w $d/s.sh" "t_quality_format_shfmt_via_flow_config invoked"
	rm -rf "$d"
}

t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	mkdir -p "$d/src"
	printf '[package]\nname = "x"\n' >"$d/Cargo.toml"
	_q_recorder "$bin" cargo "$d/ran.log"
	printf 'fn main() {}\n' >"$d/src/main.rs"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/src/main.rs\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt unconfigured-rc"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt not-invoked-without-config"
	: >"$d/rustfmt.toml"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/src/main.rs\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt configured-rc"
	assert_contains "$(_q_marker "$d/ran.log")" "| fmt" "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt cargo-fmt"
	assert_not_contains "$(_q_marker "$d/ran.log")" "--edition" "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt no-edition-flag"
	assert_contains "$(_q_marker "$d/ran.log")" "$(cd "$d" && pwd -P) |" "t_quality_format_rust_needs_rustfmt_toml_and_uses_cargo_fmt cwd-is-cargo-dir"
	rm -rf "$d"
}

t_quality_format_markdown_never_biome() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	printf '{}\n' >"$d/biome.json"
	_q_recorder "$bin" bun "$d/ran.log"
	_q_recorder "$bin" bunx "$d/ran.log"
	_q_recorder "$bin" npx "$d/ran.log"
	# A biome on PATH is now used directly (node_modules/.bin, then PATH, and
	# only then bunx), so stubbing it keeps this test independent of whether the
	# machine happens to have biome installed.
	_q_recorder "$bin" biome "$d/biome.log"
	printf '# title\n' >"$d/README.md"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/README.md\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_markdown_never_biome rc"
	assert_eq "$(_q_marker "$d/biome.log")" "" "t_quality_format_markdown_never_biome no-biome-for-md"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_markdown_never_biome no-formatter-for-md"
	printf 'const a = 1;\n' >"$d/a.ts"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/a.ts\"}}" PATH="$bin:$PATH"
	assert_contains "$(_q_marker "$d/biome.log")" "format --write $d/a.ts" "t_quality_format_markdown_never_biome ts-still-biome"
	rm -rf "$d"
}

# G4 fix round 1: a node formatter that is already installed is never reached
# through bunx, which has no --no-install and would download the package
# mid-edit.
t_quality_format_node_prefers_local_node_modules_bin() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	printf '{}\n' >"$d/biome.json"
	_q_recorder "$bin" bun "$d/ran.log"
	_q_recorder "$bin" bunx "$d/ran.log"
	_q_recorder "$bin" npx "$d/ran.log"
	_q_recorder "$bin" biome "$d/path.log"
	_q_recorder "$d/node_modules/.bin" biome "$d/local.log"
	printf 'const a = 1;\n' >"$d/a.ts"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/a.ts\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_node_prefers_local_node_modules_bin rc"
	assert_contains "$(_q_marker "$d/local.log")" "format --write $d/a.ts" "t_quality_format_node_prefers_local_node_modules_bin local-bin-ran"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_node_prefers_local_node_modules_bin no-bunx-download"
	assert_eq "$(_q_marker "$d/path.log")" "" "t_quality_format_node_prefers_local_node_modules_bin path-copy-not-used"
	rm -rf "$d"
}

t_quality_format_markdown_prettier_when_configured() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	printf '{}\n' >"$d/.prettierrc"
	_q_recorder "$bin" bun "$d/ran.log"
	_q_recorder "$bin" bunx "$d/ran.log"
	_q_recorder "$bin" npx "$d/ran.log"
	_q_recorder "$bin" prettier "$d/prettier.log"
	printf '# title\n' >"$d/README.md"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/README.md\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_markdown_prettier_when_configured rc"
	assert_contains "$(_q_marker "$d/prettier.log")" "--write $d/README.md" "t_quality_format_markdown_prettier_when_configured invoked"
	assert_eq "$(_q_marker "$d/ran.log")" "" "t_quality_format_markdown_prettier_when_configured no-bunx-download"
	rm -rf "$d"
}

t_quality_format_terraform_fmt_on_tf() {
	local d bin
	d=$(tmp_repo)
	bin="$d/stub"
	_q_recorder "$bin" terraform "$d/ran.log"
	printf 'resource "null_resource" "a" {}\n' >"$d/main.tf"
	run_hook "$SCAN_DIR/format-lint.sh" "{\"tool_input\":{\"file_path\":\"$d/main.tf\"}}" PATH="$bin:$PATH"
	assert_rc 0 "t_quality_format_terraform_fmt_on_tf rc"
	assert_contains "$(_q_marker "$d/ran.log")" "fmt $d/main.tf" "t_quality_format_terraform_fmt_on_tf invoked"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# size-guard.sh + size_guard.py
# ---------------------------------------------------------------------------

t_quality_size_guard_react_component_no_problem() {
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/react-component.tsx" 400 60
	assert_rc 0 "t_quality_size_guard_react_component_no_problem rc"
	assert_eq "$ERR" "" "t_quality_size_guard_react_component_no_problem no-stderr"
}

t_quality_size_guard_long_function_flagged() {
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/long-function.py" 400 60
	assert_rc 2 "t_quality_size_guard_long_function_flagged rc"
	assert_contains "$ERR" "process_large_batch" "t_quality_size_guard_long_function_flagged names-function"
	assert_contains "$ERR" "70 lines" "t_quality_size_guard_long_function_flagged line-count"
}

t_quality_size_guard_long_file_flagged() {
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$_FIXTURES/long-file.js" 400 60
	assert_rc 2 "t_quality_size_guard_long_file_flagged rc"
	assert_contains "$ERR" "449 lines" "t_quality_size_guard_long_file_flagged line-count"
	assert_not_contains "$ERR" "function '" "t_quality_size_guard_long_file_flagged no-function-problem"
}

t_quality_size_guard_binary_file_never_crashes() {
	local d
	d=$(tmp_dir)
	printf '\x00\x01\x02binary\xff\xfe' >"$d/blob.bin"
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$d/blob.bin" 400 60
	assert_rc 0 "t_quality_size_guard_binary_file_never_crashes rc"
	rm -rf "$d"
}

t_quality_size_guard_sh_ignore_default_locales_rc0() {
	# The fixture itself lives under hooks/tests/fixtures/, which the hook
	# would (correctly) also skip as "under tests/"; copy its content to a
	# path that is ignored only via the C4 default "locales/" entry, to test
	# that skip path in isolation.
	local d
	d=$(tmp_dir)
	mkdir -p "$d/locales"
	cp "$_FIXTURES/locales/en-strings.txt" "$d/locales/en-strings.txt"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/locales/en-strings.txt\"}}"
	assert_rc 0 "t_quality_size_guard_sh_ignore_default_locales_rc0 rc"
	rm -rf "$d"
}

t_quality_size_guard_sh_missing_file_rc0() {
	run_hook "$SCAN_DIR/size-guard.sh" '{"tool_input":{"file_path":"/no/such/file.py"}}'
	assert_rc 0 "t_quality_size_guard_sh_missing_file_rc0 rc"
}

t_quality_size_guard_sh_size_guard_false_rc0() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	printf '{"sizeGuard": false}\n' >"$d/.claude/flow.config.json"
	cp "$_FIXTURES/long-function.py" "$d/big.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_quality_size_guard_sh_size_guard_false_rc0 rc"
	rm -rf "$d"
}

t_quality_size_guard_sh_cc_no_size_guard_env_rc0() {
	local d
	d=$(tmp_dir)
	cp "$_FIXTURES/long-function.py" "$d/big.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}" CC_NO_SIZE_GUARD=1
	assert_rc 0 "t_quality_size_guard_sh_cc_no_size_guard_env_rc0 rc"
	rm -rf "$d"
}

t_quality_size_guard_sh_test_file_skip_rc0() {
	local d
	d=$(tmp_dir)
	cp "$_FIXTURES/long-function.py" "$d/big_test.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big_test.py\"}}"
	assert_rc 0 "t_quality_size_guard_sh_test_file_skip_rc0 rc"
	rm -rf "$d"
}

t_quality_size_guard_sh_triggers_on_real_invocation_rc2() {
	local d
	d=$(tmp_repo)
	cp "$_FIXTURES/long-function.py" "$d/big.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/big.py\"}}"
	assert_rc 2 "t_quality_size_guard_sh_triggers_on_real_invocation_rc2 rc"
	assert_contains "$ERR" "process_large_batch" "t_quality_size_guard_sh_triggers_on_real_invocation_rc2 names-function"
	rm -rf "$d"
}

t_quality_size_guard_sh_env_threshold_override_rc2() {
	local d
	d=$(tmp_repo)
	# .py, not .txt: G4 measures source extensions only, so the fixture that
	# proves the env override has to be a source file.
	printf 'line one\nline two\nline three\n' >"$d/small.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/small.py\"}}" CC_MAX_FILE_LINES=2
	assert_rc 2 "t_quality_size_guard_sh_env_threshold_override_rc2 rc"
	assert_contains "$ERR" "3 lines" "t_quality_size_guard_sh_env_threshold_override_rc2 message"
	rm -rf "$d"
}

t_quality_size_guard_sh_config_threshold_override_rc2() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/.claude"
	printf '{"maxFuncLines": 5}\n' >"$d/.claude/flow.config.json"
	printf 'def tiny():\n    a = 1\n    b = 2\n    c = 3\n    d = 4\n    e = 5\n    return a + b + c + d + e\n' >"$d/tiny.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/tiny.py\"}}" CLAUDE_PROJECT_DIR="$d"
	assert_rc 2 "t_quality_size_guard_sh_config_threshold_override_rc2 rc"
	assert_contains "$ERR" "tiny" "t_quality_size_guard_sh_config_threshold_override_rc2 names-function"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# tamper-notice.sh
# ---------------------------------------------------------------------------

t_quality_tamper_notice_no_file_path_rc0() {
	run_hook "$SCAN_DIR/tamper-notice.sh" '{"tool_input":{}}'
	assert_rc 0 "t_quality_tamper_notice_no_file_path_rc0 rc"
}

t_quality_tamper_notice_non_test_non_config_rc0() {
	local repo
	repo=$(tmp_repo)
	printf 'console.log(1);\n' >"$repo/app.js"
	(cd "$repo" && git add app.js && git commit -q -m app) >/dev/null 2>&1
	printf 'console.log(2);\n' >"$repo/app.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$repo/app.js\"}}"
	assert_rc 0 "t_quality_tamper_notice_non_test_non_config_rc0 rc"
	rm -rf "$repo"
}

t_quality_tamper_notice_test_skip_added_rc2() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/tests"
	printf 'def test_a():\n    assert True\n\ndef test_b():\n    assert True\n' >"$repo/tests/foo_test.py"
	(cd "$repo" && git add tests/foo_test.py && git commit -q -m t) >/dev/null 2>&1
	printf 'def test_a():\n    assert True\n\n@pytest.mark.skip\ndef test_b():\n    assert True\n' >"$repo/tests/foo_test.py"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n1\",\"tool_input\":{\"file_path\":\"$repo/tests/foo_test.py\"}}"
	assert_rc 2 "t_quality_tamper_notice_test_skip_added_rc2 rc"
	assert_contains "$ERR" "pytest.mark.skip" "t_quality_tamper_notice_test_skip_added_rc2 matched-line"
	assert_contains "$ERR" "You just disabled or weakened a check" "t_quality_tamper_notice_test_skip_added_rc2 message"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n1"
}

t_quality_tamper_notice_test_harmless_edit_rc0() {
	local repo
	repo=$(tmp_repo)
	printf 'def test_a():\n    assert True\n' >"$repo/foo.test.js"
	(cd "$repo" && git add foo.test.js && git commit -q -m t) >/dev/null 2>&1
	printf 'def test_a():\n    assert 1 == 1\n' >"$repo/foo.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n2\",\"tool_input\":{\"file_path\":\"$repo/foo.test.js\"}}"
	assert_rc 0 "t_quality_tamper_notice_test_harmless_edit_rc0 rc"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n2"
}

t_quality_tamper_notice_untracked_new_test_with_skip_rc2() {
	local repo
	repo=$(tmp_repo)
	printf "it.skip('does a thing', () => {});\n" >"$repo/new.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n3\",\"tool_input\":{\"file_path\":\"$repo/new.test.js\"}}"
	assert_rc 2 "t_quality_tamper_notice_untracked_new_test_with_skip_rc2 rc"
	assert_contains "$ERR" "it.skip" "t_quality_tamper_notice_untracked_new_test_with_skip_rc2 matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n3"
}

t_quality_tamper_notice_gate_config_threshold_weaken_rc2() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"maxFileLines": 400}\n' >"$repo/.claude/flow.config.json"
	(cd "$repo" && git add .claude/flow.config.json && git commit -q -m cfg) >/dev/null 2>&1
	printf '{"maxFileLines": 4000}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n4\",\"tool_input\":{\"file_path\":\"$repo/.claude/flow.config.json\"}}"
	assert_rc 2 "t_quality_tamper_notice_gate_config_threshold_weaken_rc2 rc"
	assert_contains "$ERR" "4000" "t_quality_tamper_notice_gate_config_threshold_weaken_rc2 matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n4"
}

t_quality_tamper_notice_gate_config_stopgate_false_rc2() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"maxFileLines": 400}\n' >"$repo/.claude/flow.config.json"
	(cd "$repo" && git add .claude/flow.config.json && git commit -q -m cfg) >/dev/null 2>&1
	printf '{"maxFileLines": 400, "stopGate": false}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n5\",\"tool_input\":{\"file_path\":\"$repo/.claude/flow.config.json\"}}"
	assert_rc 2 "t_quality_tamper_notice_gate_config_stopgate_false_rc2 rc"
	assert_contains "$ERR" "stopGate" "t_quality_tamper_notice_gate_config_stopgate_false_rc2 matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n5"
}

t_quality_tamper_notice_gate_config_harmless_change_rc0() {
	local repo
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '{"maxFileLines": 400}\n' >"$repo/.claude/flow.config.json"
	(cd "$repo" && git add .claude/flow.config.json && git commit -q -m cfg) >/dev/null 2>&1
	printf '{"maxFileLines": 400, "sizeGuard": true}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-n6\",\"tool_input\":{\"file_path\":\"$repo/.claude/flow.config.json\"}}"
	assert_rc 0 "t_quality_tamper_notice_gate_config_harmless_change_rc0 rc"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-n6"
}

t_quality_tamper_notice_not_git_repo_rc0() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/tests"
	printf "it.skip('x', () => {});\n" >"$d/tests/foo.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"tool_input\":{\"file_path\":\"$d/tests/foo.test.js\"}}"
	assert_rc 0 "t_quality_tamper_notice_not_git_repo_rc0 rc"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# G4: baseline-aware size-guard
# ---------------------------------------------------------------------------

# _q_lines <file> <n> — a file of n trivial python assignments.
_q_lines() {
	local i=0
	: >"$1"
	while [ "$i" -lt "$2" ]; do
		printf 'x%s = %s\n' "$i" "$i" >>"$1"
		i=$((i + 1))
	done
}

# _q_func <file> <n> — a python file holding one function with n body lines.
_q_func() {
	local i=0
	printf 'def big():\n' >"$1"
	while [ "$i" -lt "$2" ]; do
		printf '    y%s = %s\n' "$i" "$i" >>"$1"
		i=$((i + 1))
	done
}

_q_commit() { (cd "$1" && git add -A && git commit -q -m "$2") >/dev/null 2>&1; }

# _q_size_snapdir <repo> — where size-guard keeps that repo's baselines. Keyed
# by the repo, not by a session id, so tests derive it from their fixture.
_q_size_snapdir() {
	local t top
	t="${TMPDIR:-/tmp}"
	top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null || true)
	[ -z "$top" ] && top="$1"
	printf '%s/claude-size-%s\n' "${t%/}" "$(printf '%s' "$top" | cksum | awk '{print $1}')"
}

t_quality_size_data_file_never_measured() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/data.txt" 500
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/data.txt\"}}"
	assert_rc 0 "t_quality_size_data_file_never_measured txt-rc"
	_q_lines "$d/data.json" 500
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/data.json\"}}"
	assert_rc 0 "t_quality_size_data_file_never_measured json-rc"
	rm -rf "$d"
}

t_quality_size_over_limit_unchanged_silent() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/a.py" 500
	_q_commit "$d" big
	_q_lines "$d/a.py" 500
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_size_over_limit_unchanged_silent rc"
	assert_eq "$ERR" "" "t_quality_size_over_limit_unchanged_silent silent"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_over_limit_shrink_silent() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/a.py" 500
	_q_commit "$d" big
	_q_lines "$d/a.py" 450
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_size_over_limit_shrink_silent rc"
	assert_eq "$ERR" "" "t_quality_size_over_limit_shrink_silent silent"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_over_limit_growth_fires() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/a.py" 500
	_q_commit "$d" big
	_q_lines "$d/a.py" 520
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 2 "t_quality_size_over_limit_growth_fires rc"
	assert_contains "$ERR" "520 lines" "t_quality_size_over_limit_growth_fires message"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_crossing_limit_fires() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/a.py" 390
	_q_commit "$d" small
	_q_lines "$d/a.py" 410
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 2 "t_quality_size_crossing_limit_fires rc"
	assert_contains "$ERR" "410 lines" "t_quality_size_crossing_limit_fires message"
	assert_contains "$ERR" "CC_NO_SIZE_GUARD" "t_quality_size_crossing_limit_fires names-escape-hatch"
	assert_contains "$ERR" "sizeGuard" "t_quality_size_crossing_limit_fires names-config-key"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_func_already_over_unchanged_silent() {
	local d
	d=$(tmp_repo)
	_q_func "$d/f.py" 70
	_q_commit "$d" fn
	printf '\ndef small():\n    return 1\n' >>"$d/f.py"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/f.py\"}}"
	assert_rc 0 "t_quality_size_func_already_over_unchanged_silent rc"
	assert_eq "$ERR" "" "t_quality_size_func_already_over_unchanged_silent silent"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_func_growth_fires() {
	local d
	d=$(tmp_repo)
	_q_func "$d/f.py" 70
	_q_commit "$d" fn
	_q_func "$d/f.py" 80
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/f.py\"}}"
	assert_rc 2 "t_quality_size_func_growth_fires rc"
	assert_contains "$ERR" "'big'" "t_quality_size_func_growth_fires names-function"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

t_quality_size_jsx_single_return_exempt() {
	local d i
	d=$(tmp_repo)
	printf 'export function Widget() {\n  return (\n    <div className="w">\n' >"$d/w.tsx"
	i=0
	while [ "$i" -lt 80 ]; do
		printf '      <span>%s</span>\n' "$i" >>"$d/w.tsx"
		i=$((i + 1))
	done
	printf '    </div>\n  );\n}\n' >>"$d/w.tsx"
	run_hook "$SCAN_DIR/size-guard.sh" "{\"tool_input\":{\"file_path\":\"$d/w.tsx\"}}"
	assert_rc 0 "t_quality_size_jsx_single_return_exempt rc"
	assert_eq "$ERR" "" "t_quality_size_jsx_single_return_exempt silent"
	rm -rf "$d"
}

t_quality_size_py_baseline_flag_direct() {
	local d
	d=$(tmp_dir)
	_q_lines "$d/base.py" 500
	_q_lines "$d/cur.py" 500
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$d/cur.py" 400 60 --baseline "$d/base.py"
	assert_rc 0 "t_quality_size_py_baseline_flag_direct unchanged-rc"
	_q_lines "$d/cur.py" 501
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$d/cur.py" 400 60 --baseline "$d/base.py"
	assert_rc 2 "t_quality_size_py_baseline_flag_direct grown-rc"
	run_cmd python3 "$SCAN_DIR/size_guard.py" "$d/cur.py" 400 60 --baseline ""
	assert_rc 2 "t_quality_size_py_baseline_flag_direct empty-baseline-rc"
	rm -rf "$d"
}

# _q_two_methods <file> <name-a> <n-a> <name-b> <n-b> — two classes with one
# method each, so one method name can legitimately occur twice in a file.
_q_two_methods() {
	local f=$1 i
	printf 'class A:\n    def %s(self):\n' "$2" >"$f"
	i=0
	while [ "$i" -lt "$3" ]; do
		printf '        a%s = %s\n' "$i" "$i" >>"$f"
		i=$((i + 1))
	done
	printf 'class B:\n    def %s(self):\n' "$4" >>"$f"
	i=0
	while [ "$i" -lt "$5" ]; do
		printf '        b%s = %s\n' "$i" "$i" >>"$f"
		i=$((i + 1))
	done
}

# A baseline keyed by bare function name would let a brand-new over-limit
# method hide behind an unrelated one that shares its name.
t_quality_size_func_same_name_new_over_limit_fires() {
	local d
	d=$(tmp_repo)
	_q_two_methods "$d/svc.py" run 80 other 2
	_q_commit "$d" svc
	_q_two_methods "$d/svc.py" run 80 run 70
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-same\",\"tool_input\":{\"file_path\":\"$d/svc.py\"}}"
	assert_rc 2 "t_quality_size_func_same_name_new_over_limit_fires rc"
	assert_contains "$ERR" "'run' is 71 lines" "t_quality_size_func_same_name_new_over_limit_fires names-the-new-one"
	assert_not_contains "$ERR" "'run' is 81 lines" "t_quality_size_func_same_name_new_over_limit_fires spares-the-old-one"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

# git C-quotes a non-ASCII path unless core.quotePath=false; the quoted name
# does not resolve in `git show`, which used to make a shrunk file look new.
t_quality_size_non_ascii_filename_shrink_silent() {
	local d
	d=$(tmp_repo)
	_q_lines "$d/café_utils.py" 500
	_q_commit "$d" cafe
	_q_lines "$d/café_utils.py" 450
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-utf8\",\"tool_input\":{\"file_path\":\"$d/café_utils.py\"}}"
	assert_rc 0 "t_quality_size_non_ascii_filename_shrink_silent rc"
	assert_eq "$ERR" "" "t_quality_size_non_ascii_filename_shrink_silent silent"
	rm -rf "$d" "$(_q_size_snapdir "$d")"
}

# FU-30: once a file is oversized but uncommitted, HEAD alone would re-fire on
# every later edit — including the shrinking ones the hook just asked for.
t_quality_size_shrink_after_fire_does_not_renag() {
	local d json snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	json="{\"session_id\":\"sz-nag\",\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	_q_lines "$d/a.py" 390
	_q_commit "$d" small
	_q_lines "$d/a.py" 600
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 2 "t_quality_size_shrink_after_fire_does_not_renag crossing-fires"
	_q_lines "$d/a.py" 500
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 0 "t_quality_size_shrink_after_fire_does_not_renag first-shrink-rc"
	assert_eq "$ERR" "" "t_quality_size_shrink_after_fire_does_not_renag first-shrink-silent"
	_q_lines "$d/a.py" 450
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 0 "t_quality_size_shrink_after_fire_does_not_renag second-shrink-rc"
	_q_lines "$d/a.py" 470
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 2 "t_quality_size_shrink_after_fire_does_not_renag regrowth-fires"
	rm -rf "$d" "$snap"
}

# FU-30 across a session boundary: /clear, a resume or a new session must not
# resurrect the nag on work that is still uncommitted. The baseline is the last
# content this hook measured for the file in this repo, whoever measured it.
t_quality_size_shrink_in_a_later_session_silent() {
	local d snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_lines "$d/carry.py" 390
	_q_commit "$d" carry
	_q_lines "$d/carry.py" 600
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-sesA\",\"tool_input\":{\"file_path\":\"$d/carry.py\"}}"
	assert_rc 2 "t_quality_size_shrink_in_a_later_session_silent session-a-fires"
	_q_lines "$d/carry.py" 560
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-sesC\",\"tool_input\":{\"file_path\":\"$d/carry.py\"}}"
	assert_rc 0 "t_quality_size_shrink_in_a_later_session_silent later-session-rc"
	assert_eq "$ERR" "" "t_quality_size_shrink_in_a_later_session_silent later-session-silent"
	rm -rf "$d" "$snap"
}

# _q_named_func <file> <name> <n> — one python function of n body lines.
_q_named_func() {
	local f=$1 i=0
	printf 'def %s():\n' "$2" >"$f"
	while [ "$i" -lt "$3" ]; do
		printf '    y%s = %s\n' "$i" "$i" >>"$f"
		i=$((i + 1))
	done
}

# Renaming an already-over-limit function crosses no limit and grows nothing:
# the baseline match must not be keyed on the name alone.
t_quality_size_pure_rename_over_limit_func_silent() {
	local d snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_named_func "$d/svc.py" run 80
	_q_commit "$d" svc
	_q_named_func "$d/svc.py" execute 80
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-rename\",\"tool_input\":{\"file_path\":\"$d/svc.py\"}}"
	assert_rc 0 "t_quality_size_pure_rename_over_limit_func_silent rc"
	assert_eq "$ERR" "" "t_quality_size_pure_rename_over_limit_func_silent silent"
	rm -rf "$d" "$snap"
}

# A renamed function still gets no free pass for growing.
t_quality_size_pure_rename_with_growth_fires() {
	local d snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_named_func "$d/svc.py" run 80
	_q_commit "$d" svc
	_q_named_func "$d/svc.py" execute 95
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-rengrow\",\"tool_input\":{\"file_path\":\"$d/svc.py\"}}"
	assert_rc 2 "t_quality_size_pure_rename_with_growth_fires rc"
	assert_contains "$ERR" "'execute' is 96 lines" "t_quality_size_pure_rename_with_growth_fires names-function"
	rm -rf "$d" "$snap"
}

# No writable TMPDIR: no baseline can be materialised, and stderr — the channel
# the model reads on exit 2 — must stay free of shell plumbing errors.
t_quality_size_no_writable_tmpdir_baseline_silent() {
	local d
	d=$(tmp_repo)
	printf 'def small():\n    return 1\n' >"$d/s.py"
	_q_commit "$d" s
	printf 'def small():\n    return 2\n' >"$d/s.py"
	run_hook "$SCAN_DIR/size-guard.sh" \
		"{\"session_id\":\"sz-notmp\",\"tool_input\":{\"file_path\":\"$d/s.py\"}}" \
		"TMPDIR=$d/no-such-tmp"
	assert_rc 0 "t_quality_size_no_writable_tmpdir_baseline_silent rc"
	assert_eq "$ERR" "" "t_quality_size_no_writable_tmpdir_baseline_silent silent"
	rm -rf "$d"
}

# Pins the accepted trade documented in size-guard.sh's header: the session
# snapshot outranks HEAD all session, so a revert made outside the edit hooks
# leaves a stale larger baseline and the next crossing in that file is silent.
# Firing here instead would re-nag every shrink (FU-30). Deliberate — a later
# slice changing this must change the header comment with it.
t_quality_size_snapshot_outranks_head_after_out_of_band_revert() {
	local d json snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	json="{\"session_id\":\"sz-oob\",\"tool_input\":{\"file_path\":\"$d/big.py\"}}"
	_q_lines "$d/big.py" 390
	_q_commit "$d" big
	_q_lines "$d/big.py" 700
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 2 "t_quality_size_snapshot_outranks_head_after_out_of_band_revert first-fires"
	(cd "$d" && git checkout -q -- big.py) >/dev/null 2>&1
	_q_lines "$d/big.py" 450
	run_hook "$SCAN_DIR/size-guard.sh" "$json"
	assert_rc 0 "t_quality_size_snapshot_outranks_head_after_out_of_band_revert accepted-silence"
	rm -rf "$d" "$snap"
}

# _q_repo_at <dir> — make <dir> a git repo (tmp_repo picks its own path; these
# tests need a FIXED path, because that is what keys the snapshot directory).
_q_repo_at() {
	(
		cd "$1" || exit 1
		git init -q
		git config user.email "test@example.com"
		git config user.name "harness-test"
		git config commit.gpgsign false
	) >/dev/null 2>&1
}

# _q_size_snapname <file> — the snapshot file size-guard would keep for <file>.
_q_size_snapname() { printf '%s' "$1" | cksum | awk '{print $1}'; }

# The spec's frozen contract: for an untracked file the baseline is empty. A
# file deleted and re-created at the same path is a new file, and a snapshot
# left by its namesake must not vouch for it.
t_quality_size_untracked_recreated_file_fires() {
	local d snap
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_lines "$d/mod.py" 600
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-untr\",\"tool_input\":{\"file_path\":\"$d/mod.py\"}}"
	assert_rc 2 "t_quality_size_untracked_recreated_file_fires first-fires"
	rm -f "$d/mod.py"
	_q_lines "$d/mod.py" 500
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-untr\",\"tool_input\":{\"file_path\":\"$d/mod.py\"}}"
	assert_rc 2 "t_quality_size_untracked_recreated_file_fires recreated-fires"
	assert_contains "$ERR" "500 lines" "t_quality_size_untracked_recreated_file_fires message"
	assert_file_missing "$snap" "t_quality_size_untracked_recreated_file_fires no-snapshot-for-untracked"
	rm -rf "$d" "$snap"
}

# The snapshot dir is keyed by the repo's path, and paths get reused (worktrees,
# /tmp fixtures, CI checkouts). A repo re-created at the same path has a
# different root commit and must not inherit the old one's baselines.
t_quality_size_repo_recreated_at_same_path_fires() {
	local d snap
	d="${TMPDIR:-/tmp}/flow-test-size-reuse.$$"
	rm -rf "$d"
	mkdir -p "$d"
	_q_repo_at "$d"
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_lines "$d/svc.py" 390
	_q_commit "$d" first-repo
	_q_lines "$d/svc.py" 600
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-reuse\",\"tool_input\":{\"file_path\":\"$d/svc.py\"}}"
	assert_rc 2 "t_quality_size_repo_recreated_at_same_path_fires first-repo-fires"
	rm -rf "$d"
	mkdir -p "$d"
	_q_repo_at "$d"
	_q_lines "$d/svc.py" 390
	_q_commit "$d" second-repo
	_q_lines "$d/svc.py" 500
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-reuse\",\"tool_input\":{\"file_path\":\"$d/svc.py\"}}"
	assert_rc 2 "t_quality_size_repo_recreated_at_same_path_fires new-repo-fires"
	assert_contains "$ERR" "500 lines" "t_quality_size_repo_recreated_at_same_path_fires message"
	rm -rf "$d" "$snap"
}

# The dir name is cksum(repo path): guessable on a shared /tmp. A symlink
# planted there must not be followed, and the run must still judge the file.
t_quality_size_snapshot_dir_symlink_refused() {
	local d snap victim
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	victim=$(tmp_dir)
	printf 'VICTIM\n' >"$victim/secret"
	ln -s "$victim" "$snap"
	_q_lines "$d/a.py" 390
	_q_commit "$d" a
	_q_lines "$d/a.py" 410
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-link\",\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 2 "t_quality_size_snapshot_dir_symlink_refused still-judges"
	assert_eq "$(cat "$victim/secret")" "VICTIM" "t_quality_size_snapshot_dir_symlink_refused victim-intact"
	assert_file_missing "$victim/$(_q_size_snapname "$d/a.py")" \
		"t_quality_size_snapshot_dir_symlink_refused no-copy-through-the-link"
	rm -f "$snap"
	rm -rf "$d" "$victim"
}

# Same attack one level down: a symlink at the snapshot's own name. The copy
# unlinks the name first, so it replaces the link instead of writing through it.
t_quality_size_snapshot_file_symlink_not_written_through() {
	local d snap victim root
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	victim=$(tmp_dir)
	printf 'VICTIM\n' >"$victim/secret"
	_q_lines "$d/a.py" 10
	_q_commit "$d" a
	mkdir -p "$snap"
	root=$(git -C "$d" rev-list --max-parents=0 HEAD | tail -1)
	printf '%s\n%s\n' "$root" "$(git -C "$d" rev-parse --show-toplevel)" >"$snap/.repo"
	ln -s "$victim/secret" "$snap/$(_q_size_snapname "$d/a.py")"
	_q_lines "$d/a.py" 12
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-flink\",\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_size_snapshot_file_symlink_not_written_through rc"
	assert_eq "$(cat "$victim/secret")" "VICTIM" "t_quality_size_snapshot_file_symlink_not_written_through victim-intact"
	assert_contains "$(ls -ld "$snap" | cut -c1-10)" "drwx------" \
		"t_quality_size_snapshot_file_symlink_not_written_through private-dir"
	rm -rf "$d" "$snap" "$victim"
}

# Snapshot dirs outlive their repos (a /tmp fixture, a removed worktree). The
# next repo that needs a new dir sweeps the ones whose repo path is gone.
t_quality_size_snapdir_pruned_when_repo_is_gone() {
	local d snap ghost
	ghost="${TMPDIR:-/tmp}/claude-size-ghost-$$"
	rm -rf "$ghost"
	mkdir -p "$ghost"
	printf 'deadbeefdeadbeef\n%s\n' "${TMPDIR:-/tmp}/flow-test-no-such-repo-$$" >"$ghost/.repo"
	: >"$ghost/12345"
	d=$(tmp_repo)
	snap=$(_q_size_snapdir "$d")
	rm -rf "$snap"
	_q_lines "$d/a.py" 10
	_q_commit "$d" a
	_q_lines "$d/a.py" 12
	run_hook "$SCAN_DIR/size-guard.sh" "{\"session_id\":\"sz-prune\",\"tool_input\":{\"file_path\":\"$d/a.py\"}}"
	assert_rc 0 "t_quality_size_snapdir_pruned_when_repo_is_gone rc"
	assert_file_missing "$ghost" "t_quality_size_snapdir_pruned_when_repo_is_gone dead-repo-swept"
	assert_file_exists "$snap/.repo" "t_quality_size_snapdir_pruned_when_repo_is_gone own-dir-stamped"
	rm -rf "$d" "$snap" "$ghost"
}

# ---------------------------------------------------------------------------
# G4: tamper-notice content detection and turn-start snapshots
# ---------------------------------------------------------------------------

t_quality_tamper_content_detects_py_test() {
	local repo
	repo=$(tmp_repo)
	printf 'def test_a():\n    assert True\n' >"$repo/helpers.py"
	_q_commit "$repo" h
	printf 'def test_a():\n    assert True\n\n@pytest.mark.skip\ndef test_b():\n    assert True\n' >"$repo/helpers.py"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-py\",\"tool_input\":{\"file_path\":\"$repo/helpers.py\"}}"
	assert_rc 2 "t_quality_tamper_content_detects_py_test rc"
	assert_contains "$ERR" "pytest.mark.skip" "t_quality_tamper_content_detects_py_test matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-py"
}

t_quality_tamper_content_detects_rust_test() {
	local repo
	repo=$(tmp_repo)
	printf '#[cfg(test)]\nmod tests {\n    #[test]\n    fn a() {}\n}\n' >"$repo/lib.rs"
	_q_commit "$repo" r
	printf '#[cfg(test)]\nmod tests {\n    #[test]\n    #[ignore]\n    fn a() {}\n}\n' >"$repo/lib.rs"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-rs\",\"tool_input\":{\"file_path\":\"$repo/lib.rs\"}}"
	assert_rc 2 "t_quality_tamper_content_detects_rust_test rc"
	assert_contains "$ERR" "#[ignore]" "t_quality_tamper_content_detects_rust_test matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-rs"
}

t_quality_tamper_content_detects_go_test() {
	local repo
	repo=$(tmp_repo)
	printf 'package main\n\nfunc TestA(t *testing.T) {\n\tif false {\n\t\tt.Fatal("x")\n\t}\n}\n' >"$repo/svc.go"
	_q_commit "$repo" g
	printf 'package main\n\nfunc TestA(t *testing.T) {\n\tt.Skip("flaky")\n}\n' >"$repo/svc.go"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-go\",\"tool_input\":{\"file_path\":\"$repo/svc.go\"}}"
	assert_rc 2 "t_quality_tamper_content_detects_go_test rc"
	assert_contains "$ERR" "t.Skip(" "t_quality_tamper_content_detects_go_test matched-line"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-go"
}

t_quality_tamper_content_plain_source_ignored() {
	local repo
	repo=$(tmp_repo)
	printf 'def add(a, b):\n    return a + b\n' >"$repo/calc.py"
	_q_commit "$repo" c
	printf 'def add(a, b):\n    return queue.skip(a) + b\n' >"$repo/calc.py"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-plain\",\"tool_input\":{\"file_path\":\"$repo/calc.py\"}}"
	assert_rc 0 "t_quality_tamper_content_plain_source_ignored rc"
	rm -rf "$repo" "${TMPDIR:-/tmp}/claude-tamper-tam-plain"
}

t_quality_tamper_pre_existing_skip_does_not_renag() {
	local repo snap
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-snap"
	rm -rf "$snap"
	printf "it.skip('does a thing', () => {});\n" >"$repo/new.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-snap\",\"tool_input\":{\"file_path\":\"$repo/new.test.js\"}}"
	assert_rc 2 "t_quality_tamper_pre_existing_skip_does_not_renag first-rc"
	assert_file_exists "$snap" "t_quality_tamper_pre_existing_skip_does_not_renag snapshot-dir"
	printf "console.log('unrelated');\n" >>"$repo/new.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-snap\",\"tool_input\":{\"file_path\":\"$repo/new.test.js\"}}"
	assert_rc 0 "t_quality_tamper_pre_existing_skip_does_not_renag second-rc"
	assert_eq "$ERR" "" "t_quality_tamper_pre_existing_skip_does_not_renag second-silent"
	printf "it.skip('another', () => {});\n" >>"$repo/new.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-snap\",\"tool_input\":{\"file_path\":\"$repo/new.test.js\"}}"
	assert_rc 2 "t_quality_tamper_pre_existing_skip_does_not_renag new-skip-rc"
	rm -rf "$repo" "$snap"
}

# First sight of a TRACKED file: `git diff HEAD` also shows dirt that predates
# the session. Only what this tool call wrote may be attributed to this edit.
t_quality_tamper_first_sight_only_lines_this_edit_wrote() {
	local repo snap json
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-fs"
	rm -rf "$snap"
	printf 'def test_a():\n    assert 1\n' >"$repo/svc_test.py"
	_q_commit "$repo" t
	# Left over from before this session: uncommitted, not ours.
	printf 'def test_a():\n    assert 1\n\n@pytest.mark.skip\ndef test_b():\n    assert 1\n' >"$repo/svc_test.py"
	# This edit appends an unrelated helper and says so in its payload.
	printf 'def helper():\n    return 1\n' >>"$repo/svc_test.py"
	json="{\"session_id\":\"tam-fs\",\"tool_input\":{\"file_path\":\"$repo/svc_test.py\",\"new_string\":\"def helper():\\n    return 1\"}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 0 "t_quality_tamper_first_sight_only_lines_this_edit_wrote rc"
	assert_eq "$ERR" "" "t_quality_tamper_first_sight_only_lines_this_edit_wrote silent"
	rm -rf "$snap"
	# Same first-sight situation, but the payload IS the weakening line.
	printf 'def test_c():\n    assert 1\n' >>"$repo/svc_test.py"
	json="{\"session_id\":\"tam-fs\",\"tool_input\":{\"file_path\":\"$repo/svc_test.py\",\"content\":\"@pytest.mark.skip\\ndef test_c():\\n    assert 1\"}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 2 "t_quality_tamper_first_sight_only_lines_this_edit_wrote own-skip-rc"
	assert_contains "$ERR" "pytest.mark.skip" "t_quality_tamper_first_sight_only_lines_this_edit_wrote own-skip-line"
	rm -rf "$repo" "$snap"
}

# The cheapest way to disable a test is a one-token Edit: `it(` → `it.skip(`.
# The line that lands in the file equals no line of the payload, so first-sight
# narrowing may only ask whether the payload appears IN the added line.
t_quality_tamper_partial_edit_adds_skip_rc2() {
	local repo snap
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-pe"
	rm -rf "$snap"
	mkdir -p "$repo/tests"
	printf "it('does a thing', () => { expect(1).toBe(1); });\n" >"$repo/tests/a.test.js"
	_q_commit "$repo" a
	printf "it.skip('does a thing', () => { expect(1).toBe(1); });\n" >"$repo/tests/a.test.js"
	run_hook "$SCAN_DIR/tamper-notice.sh" \
		"{\"session_id\":\"tam-pe\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$repo/tests/a.test.js\",\"old_string\":\"it(\",\"new_string\":\"it.skip(\"}}"
	assert_rc 2 "t_quality_tamper_partial_edit_adds_skip_rc2 rc"
	assert_contains "$ERR" "it.skip" "t_quality_tamper_partial_edit_adds_skip_rc2 matched-line"
	rm -rf "$repo" "$snap"
}

# Same shape against a gate config: `true` → `false` on the stopGate line.
t_quality_tamper_partial_edit_flips_gate_config_rc2() {
	local repo snap
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-gc"
	rm -rf "$snap"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_q_commit "$repo" cfg
	printf '{"stopGate": false}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/tamper-notice.sh" \
		"{\"session_id\":\"tam-gc\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$repo/.claude/flow.config.json\",\"old_string\":\"true\",\"new_string\":\"false\"}}"
	assert_rc 2 "t_quality_tamper_partial_edit_flips_gate_config_rc2 rc"
	assert_contains "$ERR" "stopGate" "t_quality_tamper_partial_edit_flips_gate_config_rc2 matched-line"
	rm -rf "$repo" "$snap"
}

# A blocking message must name its own escape hatch.
t_quality_tamper_block_names_escape_hatch() {
	local repo snap
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-esc"
	rm -rf "$snap"
	mkdir -p "$repo/tests"
	printf 'def test_a():\n    assert 1\n' >"$repo/tests/foo_test.py"
	_q_commit "$repo" e
	printf 'import pytest\n\n@pytest.mark.skip\ndef test_a():\n    assert 1\n' >"$repo/tests/foo_test.py"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-esc\",\"tool_input\":{\"file_path\":\"$repo/tests/foo_test.py\"}}"
	assert_rc 2 "t_quality_tamper_block_names_escape_hatch rc"
	assert_contains "$ERR" "flow off" "t_quality_tamper_block_names_escape_hatch names-hatch"
	rm -rf "$repo" "$snap"
}

# First sight of a file an earlier session already dirtied: the pre-edit content
# is reconstructed from old_string/new_string, so only the lines THIS Edit wrote
# can be reported — the leftover skip is not this turn's doing.
t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content() {
	local repo snap json
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-rec"
	rm -rf "$snap"
	printf 'def test_a():\n    assert 1\n' >"$repo/svc_test.py"
	_q_commit "$repo" t
	# Uncommitted before this session started: a skip that is not ours.
	printf 'def test_a():\n    assert 1\n\n@pytest.mark.skip\ndef test_b():\n    assert 1\n' >"$repo/svc_test.py"
	# This turn's Edit appends a test after test_b.
	printf 'def test_c():\n    assert 2\n' >>"$repo/svc_test.py"
	json="{\"session_id\":\"tam-rec\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$repo/svc_test.py\",\"old_string\":\"def test_b():\\n    assert 1\\n\",\"new_string\":\"def test_b():\\n    assert 1\\ndef test_c():\\n    assert 2\\n\"}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 0 "t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content rc"
	assert_eq "$ERR" "" "t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content silent"
	# Same first sight, but this Edit's own text mentions the pattern. Only the
	# line this Edit wrote may be listed — never the leftover decorator, whose
	# text a payload-substring match would drag in.
	rm -rf "$snap"
	printf 'def test_d():\n    # covers @pytest.mark.skip handling\n    assert 3\n' >>"$repo/svc_test.py"
	json="{\"session_id\":\"tam-rec\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$repo/svc_test.py\",\"old_string\":\"def test_c():\\n    assert 2\\n\",\"new_string\":\"def test_c():\\n    assert 2\\ndef test_d():\\n    # covers @pytest.mark.skip handling\\n    assert 3\\n\"}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 2 "t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content own-line-rc"
	assert_contains "$ERR" "# covers @pytest.mark.skip handling" \
		"t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content names-own-line"
	assert_not_contains "$ERR" "+@pytest.mark.skip" \
		"t_quality_tamper_first_sight_edit_reconstructs_pre_edit_content spares-yesterdays-line"
	rm -rf "$repo" "$snap"
}

# When new_string occurs more than once the reconstruction is ambiguous: the
# hook cannot prove which line this Edit wrote, so it names none. Here an
# earlier session left stopGate:false behind and this Edit flips requireSpec.
t_quality_tamper_first_sight_ambiguous_edit_stays_silent() {
	local repo snap json
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-amb"
	rm -rf "$snap"
	mkdir -p "$repo/.claude"
	printf '{\n  "stopGate": true,\n  "requireSpec": true\n}\n' >"$repo/.claude/flow.config.json"
	_q_commit "$repo" cfg
	printf '{\n  "stopGate": false,\n  "requireSpec": true\n}\n' >"$repo/.claude/flow.config.json"
	printf '{\n  "stopGate": false,\n  "requireSpec": false\n}\n' >"$repo/.claude/flow.config.json"
	json="{\"session_id\":\"tam-amb\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$repo/.claude/flow.config.json\",\"old_string\":\"true\",\"new_string\":\"false\"}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_not_contains "$ERR" "stopGate" "t_quality_tamper_first_sight_ambiguous_edit_stays_silent spares-yesterdays-line"
	assert_rc 0 "t_quality_tamper_first_sight_ambiguous_edit_stays_silent rc"
	rm -rf "$repo" "$snap"
}

# MultiEdit reverses its edits in reverse order: the pre-existing skip stays out
# of the report, and a skip this MultiEdit writes is still named.
t_quality_tamper_multiedit_reconstructs_pre_edit_content() {
	local repo snap f json
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-me"
	rm -rf "$snap"
	mkdir -p "$repo/tests"
	f="$repo/tests/m.test.js"
	printf "it('a', () => {});\nit('b', () => {});\n" >"$f"
	_q_commit "$repo" m
	# Left over from an earlier session: 'a' is already skipped.
	printf "it.skip('a', () => {});\nit('b', () => {});\n" >"$f"
	# This turn's MultiEdit renames 'b' and appends a log line.
	printf "it.skip('a', () => {});\nit('bee', () => {});\nconsole.log('x');\n" >"$f"
	json="{\"session_id\":\"tam-me\",\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"$f\",\"edits\":[{\"old_string\":\"it('b'\",\"new_string\":\"it('bee'\"},{\"old_string\":\"it('bee', () => {});\",\"new_string\":\"it('bee', () => {});\\nconsole.log('x');\"}]}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 0 "t_quality_tamper_multiedit_reconstructs_pre_edit_content harmless-rc"
	assert_eq "$ERR" "" "t_quality_tamper_multiedit_reconstructs_pre_edit_content harmless-silent"
	# Same first sight, but this MultiEdit writes the skip itself.
	rm -rf "$snap"
	printf "it.skip('a', () => {});\nit('bee', () => {});\nconsole.log('x');\nit.skip('c', () => {});\n" >"$f"
	json="{\"session_id\":\"tam-me\",\"tool_name\":\"MultiEdit\",\"tool_input\":{\"file_path\":\"$f\",\"edits\":[{\"old_string\":\"console.log('x');\",\"new_string\":\"console.log('x');\\nit.skip('c', () => {});\"}]}}"
	run_hook "$SCAN_DIR/tamper-notice.sh" "$json"
	assert_rc 2 "t_quality_tamper_multiedit_reconstructs_pre_edit_content own-skip-rc"
	assert_contains "$ERR" "it.skip('c'" "t_quality_tamper_multiedit_reconstructs_pre_edit_content own-skip-line"
	assert_not_contains "$ERR" "it.skip('a'" "t_quality_tamper_multiedit_reconstructs_pre_edit_content spares-the-old-one"
	rm -rf "$repo" "$snap"
}

# ${TMPDIR}/claude-tamper-nosession is a guessable name: a symlink planted at
# the snapshot dir must not be followed, and the file is still judged.
t_quality_tamper_snapshot_dir_symlink_refused() {
	local repo snap victim
	repo=$(tmp_repo)
	snap="${TMPDIR:-/tmp}/claude-tamper-tam-link"
	rm -rf "$snap"
	victim=$(tmp_dir)
	printf 'VICTIM\n' >"$victim/secret"
	ln -s "$victim" "$snap"
	mkdir -p "$repo/tests"
	printf 'def test_a():\n    assert 1\n' >"$repo/tests/foo_test.py"
	_q_commit "$repo" e
	printf 'import pytest\n\n@pytest.mark.skip\ndef test_a():\n    assert 1\n' >"$repo/tests/foo_test.py"
	run_hook "$SCAN_DIR/tamper-notice.sh" "{\"session_id\":\"tam-link\",\"tool_input\":{\"file_path\":\"$repo/tests/foo_test.py\"}}"
	assert_rc 2 "t_quality_tamper_snapshot_dir_symlink_refused still-judges"
	assert_eq "$(cat "$victim/secret")" "VICTIM" "t_quality_tamper_snapshot_dir_symlink_refused victim-intact"
	assert_file_missing "$victim/$(_q_size_snapname "$repo/tests/foo_test.py")" \
		"t_quality_tamper_snapshot_dir_symlink_refused no-copy-through-the-link"
	rm -f "$snap"
	rm -rf "$repo" "$victim"
}

# ---------------------------------------------------------------------------
# stop-gate.sh — SPEC C10. The change set is find-newer over the turn stamp
# and nothing else (B6/FU-04), so every fixture that must be gated starts its
# turn with _qstop_stamp; one without a stamp has an empty Δ and is allowed.
# ---------------------------------------------------------------------------

# _qstop_stamp <sid> <repo> — start a turn: a stamp older than the fixture, and
# a clean per-session ladder. Ignore files are backdated with it, since
# hookout's turn-scoped rule reads one newer than the stamp as "written now".
_qstop_stamp() {
	rm -f "${TMPDIR:-/tmp}/claude-count-$1" "${TMPDIR:-/tmp}/claude-once-$1"
	: >"${TMPDIR:-/tmp}/claude-turn-$1"
	touch -t 202006010000 "${TMPDIR:-/tmp}/claude-turn-$1"
	touch -t 202001010000 "$2/.git/info/exclude" 2>/dev/null || true
	return 0
}

# _qstop_forget <sid> — drop this session's stamp, ladder and once-only state.
_qstop_forget() {
	rm -f "${TMPDIR:-/tmp}/claude-turn-$1" "${TMPDIR:-/tmp}/claude-count-$1" \
		"${TMPDIR:-/tmp}/claude-once-$1"
}

# _quality_gates_stamp_path <repo> — mirrors stop-gate.sh's own
# ${TMPDIR:-/tmp}/claude-gates-<repo-basename>-<8-char cksum hash of toplevel
# path> computation exactly, so tests can pre-seed or inspect the sweep stamp.
# Since FU-24 it holds the sha the last full sweep ran at, not an epoch.
_quality_gates_stamp_path() {
	local repo toplevel tmp hash_num hash8 base
	repo=$1
	toplevel=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
	[ -z "$toplevel" ] && toplevel="$repo"
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	hash_num=$(printf '%s' "$toplevel" | cksum | awk '{print $1}')
	hash8=$(printf '%s' "$hash_num" | tail -c 8)
	base=$(basename "$toplevel")
	printf '%s/claude-gates-%s-%s' "$tmp" "$base" "$hash8"
}

# _quality_baseline_path <repo> — stop-gate.sh's per-repo+branch record of
# which checks were already red at this HEAD.
_quality_baseline_path() {
	local repo toplevel tmp base branch
	repo=$1
	toplevel=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)
	[ -z "$toplevel" ] && toplevel="$repo"
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	base=$(basename "$toplevel")
	branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -c 'A-Za-z0-9_-' '_')
	printf '%s/claude-baseline-%s-%s' "$tmp" "$base" "$branch"
}

t_quality_stop_gate_stop_hook_active_rc0_instant() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/stop-gate.sh" '{"stop_hook_active":true}' CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_quality_stop_gate_stop_hook_active_rc0_instant rc"
	rm -rf "$repo"
}

t_quality_stop_gate_env_disabled_rc0() {
	local repo
	repo=$(tmp_repo)
	echo x >"$repo/f.txt"
	run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo" CC_NO_STOP_GATE=1
	assert_rc 0 "t_quality_stop_gate_env_disabled_rc0 rc"
	rm -rf "$repo"
}

t_quality_stop_gate_stopgate_false_rc0() {
	local repo shared sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-false-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": false}\n' >"$repo/.claude/flow.config.json"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	_qstop_stamp "$sid" "$repo"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_stopgate_false_rc0 rc"
	assert_eq "$OUT" "" "t_quality_stop_gate_stopgate_false_rc0 silent-on-a-red-suite"
	_qstop_forget "$sid"
	rm -rf "$repo"
}

t_quality_stop_gate_no_changes_rc0() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
	assert_rc 0 "t_quality_stop_gate_no_changes_rc0 rc"
	assert_eq "$OUT" "" "t_quality_stop_gate_no_changes_rc0 silent"
	rm -rf "$repo"
}

t_quality_stop_gate_not_git_repo_rc0() {
	local d
	d=$(tmp_dir)
	run_hook "$SCAN_DIR/stop-gate.sh" '{}' CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_quality_stop_gate_not_git_repo_rc0 rc"
	rm -rf "$d"
}

t_quality_stop_gate_both_shared_scripts_absent_rc0() {
	# R7: a gate that cannot run is not a pass. The turn is allowed, and the
	# hook says which tool is missing and how to fix it.
	local repo sid empty
	repo=$(tmp_repo)
	empty=$(tmp_dir)
	sid="quality-noscripts-$$"
	_qstop_stamp "$sid" "$repo"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$empty"
	assert_rc 0 "t_quality_stop_gate_both_shared_scripts_absent_rc0 rc"
	assert_contains "$OUT" "gate could not run" "t_quality_stop_gate_both_shared_scripts_absent_rc0 says-so"
	assert_not_contains "$OUT" '"decision"' "t_quality_stop_gate_both_shared_scripts_absent_rc0 does-not-block"
	_qstop_forget "$sid"
	rm -rf "$repo" "$empty"
}

t_quality_stop_gate_full_sweep_test_exit1_blocks() {
	local repo shared sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-exit1-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_qstop_stamp "$sid" "$repo"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_full_sweep_test_exit1_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_full_sweep_test_exit1_blocks decision"
	assert_contains "$OUT" "Gate(s) failed: test" "t_quality_stop_gate_full_sweep_test_exit1_blocks gate-name"
	assert_contains "$OUT" "To reproduce: cd " "t_quality_stop_gate_full_sweep_test_exit1_blocks reproduce-line"
	_qstop_forget "$sid"
	rm -f "$(_quality_gates_stamp_path "$repo")" "$(_quality_baseline_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_full_sweep_test_exit0_passes() {
	local repo shared sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-exit0-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_qstop_stamp "$sid" "$repo"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_full_sweep_test_exit0_passes rc"
	assert_eq "$OUT" "" "t_quality_stop_gate_full_sweep_test_exit0_passes no-block"
	_qstop_forget "$sid"
	rm -f "$(_quality_gates_stamp_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_wedge_valve_fourth_failure_rc2() {
	# The name is historical: the valve no longer ends in rc 2 (B9 — exit 2 on
	# Stop still blocks, so that "release" never released). The invariant it
	# was written for stands: the same red gate must not block a session for
	# ever. Here the SAME change set is on the table every turn, so the red is
	# this turn's to answer for and the baseline never claims it (R9 needs an
	# earlier turn that touched other files): it climbs the R14/R15 ladder
	# instead — block, block, soft, release. No /lesson prose anywhere.
	local repo shared sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-wedge-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_qstop_stamp "$sid" "$repo"
	rm -f "$(_quality_baseline_path "$repo")"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 first-rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 first-blocks"
	assert_not_contains "$OUT" "/lesson" "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 no-lesson-prose"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 rc-2"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 second-still-blocks"
	assert_not_contains "$OUT" "already failing before this turn" "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 second-does-not-claim-pre-existing"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 rc-3"
	assert_contains "$OUT" '"additionalContext"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 third-is-soft"
	assert_not_contains "$OUT" '"decision"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 third-does-not-block"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 rc-4"
	assert_contains "$OUT" "Nothing was verified" "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 fourth-releases"
	assert_not_contains "$OUT" '"decision"' "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 no-block-4"
	assert_not_contains "$OUT" "/lesson" "t_quality_stop_gate_wedge_valve_fourth_failure_rc2 no-lesson-prose-4"
	_qstop_forget "$sid"
	rm -f "$(_quality_gates_stamp_path "$repo")" "$(_quality_baseline_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_deleted_blocks() {
	# R6 needs a turn to attribute the deletion to: the stamp is written
	# BEFORE the `git rm`, so the project root is newer than it.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	(cd "$repo" && git add package.json .claude/flow.config.json && git commit -q -m addpkg) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-del" "$repo"
	(cd "$repo" && git rm -q package.json) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_deleted_blocks rc"
	assert_contains "$OUT" "manifest package.json is gone from the working tree" "t_quality_stop_gate_manifest_deleted_blocks message"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_manifest_deleted_blocks blocks"
	assert_contains "$OUT" "CC_NO_STOP_GATE=1" "t_quality_stop_gate_manifest_deleted_blocks names-its-escape-hatch"
	# Named is not enough: the hatch is USED here, because a block that prints
	# an escape it does not honour wedges whoever follows the instruction.
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared" CC_NO_STOP_GATE=1
	assert_rc 0 "t_quality_stop_gate_manifest_deleted_blocks env-hatch-rc"
	assert_not_contains "$OUT" '"decision"' "t_quality_stop_gate_manifest_deleted_blocks env-hatch-really-escapes"
	printf '{"stopGate": false}\n' >"$repo/.claude/flow.config.json"
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_not_contains "$OUT" '"decision"' "t_quality_stop_gate_manifest_deleted_blocks config-hatch-really-escapes"
	_qstop_forget "quality-manifest-del"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_replaced_by_a_directory_blocks() {
	# R6 skips a path that still holds the manifest, and "still holds" has to
	# mean a REGULAR FILE: `git rm package.json && mkdir package.json` leaves
	# an inode at the path with no manifest in it, which is the same dodge as
	# a plain delete and must not be waved through by a bare existence test.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	(cd "$repo" && git add package.json && git commit -q -m addpkg) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-dir" "$repo"
	(cd "$repo" && git rm -q package.json && mkdir package.json) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-dir"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_replaced_by_a_directory_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_manifest_replaced_by_a_directory_blocks blocks"
	assert_contains "$OUT" "manifest package.json is gone from the working tree" "t_quality_stop_gate_manifest_replaced_by_a_directory_blocks message"
	_qstop_forget "quality-manifest-dir"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_created_via_rename_not_blocked() {
	# A rename whose NEW side is a manifest (`git mv foo.json package.json`)
	# creates the manifest; it must never be mistaken for the manifest
	# disappearing, even though the resulting package.json (here: no
	# "scripts" block) still leaves check-all with no test to run.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	printf '{"name":"x"}\n' >"$repo/foo.json"
	(cd "$repo" && git add foo.json && git commit -q -m addfoo) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-rename-create" "$repo"
	(cd "$repo" && git mv foo.json package.json) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-create"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_created_via_rename_not_blocked rc"
	assert_not_contains "$OUT" "is gone from the working tree" "t_quality_stop_gate_manifest_created_via_rename_not_blocked no-block-message"
	_qstop_forget "quality-manifest-rename-create"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_renamed_away_blocks() {
	# A rename whose OLD side is the manifest (`git mv package.json
	# backup.json`) is the manifest disappearing from its path, same as a
	# plain delete — must still block.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	(cd "$repo" && git add package.json && git commit -q -m addpkg) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-rename-away" "$repo"
	(cd "$repo" && git mv package.json backup.json) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-away"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_renamed_away_blocks rc"
	assert_contains "$OUT" "manifest package.json is gone from the working tree" "t_quality_stop_gate_manifest_renamed_away_blocks message"
	_qstop_forget "quality-manifest-rename-away"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_lookalike_deleted_not_blocked() {
	# Deleting a file whose name merely contains "package.json" as a
	# substring (package.json.orig) must never be mistaken for the manifest
	# disappearing — matching is by exact basename, not substring.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	printf '{"name":"x"}\n' >"$repo/package.json.orig"
	(cd "$repo" && git add package.json.orig && git commit -q -m addorig) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-lookalike-del" "$repo"
	(cd "$repo" && git rm -q package.json.orig) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-lookalike-del"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_lookalike_deleted_not_blocked rc"
	assert_not_contains "$OUT" "is gone from the working tree" "t_quality_stop_gate_manifest_lookalike_deleted_not_blocked no-block-message"
	_qstop_forget "quality-manifest-lookalike-del"
	rm -rf "$repo"
}

t_quality_stop_gate_manifest_renamed_to_plain_name_blocks() {
	# `git mv package.json x` — a rename whose OLD side is the manifest —
	# still blocks even when the new name is a short, unrelated basename.
	local repo shared
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	(cd "$repo" && git add package.json && git commit -q -m addpkg) >/dev/null 2>&1
	_qstop_stamp "quality-manifest-rename-to-x" "$repo"
	(cd "$repo" && git mv package.json x) >/dev/null 2>&1
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"quality-manifest-rename-to-x"}' CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_manifest_renamed_to_plain_name_blocks rc"
	assert_contains "$OUT" "manifest package.json is gone from the working tree" "t_quality_stop_gate_manifest_renamed_to_plain_name_blocks message"
	_qstop_forget "quality-manifest-rename-to-x"
	rm -rf "$repo"
}

t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep() {
	# No flow.config.json => default "scoped" mode. The turn's only changed
	# file is package.json itself, which maps to no test file, so the scoped
	# run verifies nothing — and silence is reserved for checked-and-green, so
	# the full sweep runs and blocks on the real `npm run test`.
	local repo shared sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-fallthrough-$$"
	_qstop_stamp "$sid" "$repo"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep blocked-by-full-sweep"
	assert_contains "$OUT" "Gate(s) failed:" "t_quality_stop_gate_scoped_fallthrough_no_test_command_runs_full_sweep full-sweep-reason"
	_qstop_forget "$sid"
	rm -f "$(_quality_gates_stamp_path "$repo")" "$(_quality_baseline_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep() {
	# C10 "scoped" mode: a test file touched this turn whose suite fails is
	# blocked straight off test-changed's own passed:false JSON, without ever
	# running the check-all sweep. The reason is test-changed's own ("Gate
	# failed: test-changed (...)"), never the sweep's ("Gate(s) failed: ...").
	local repo shared stamp sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-tc-direct-$$"
	printf 'test("x", () => { expect(1).toBe(1); });\n' >"$repo/app.test.js"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	(cd "$repo" && git add app.test.js package.json && git commit -q -m tests) >/dev/null 2>&1
	stamp=$(_quality_gates_stamp_path "$repo")
	rm -f "$stamp" "$(_quality_baseline_path "$repo")"
	_qstop_stamp "$sid" "$repo"
	printf 'test("x", () => { expect(1).toBe(2); });\n' >"$repo/app.test.js"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep decision"
	assert_contains "$OUT" "test-changed (" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep reason-is-test-changed"
	assert_contains "$OUT" "app.test.js" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep names-test-file"
	assert_not_contains "$OUT" "Gate(s) failed:" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep no-full-sweep-reason"
	assert_file_missing "$stamp" "t_quality_stop_gate_scoped_test_changed_direct_block_no_full_sweep no-full-sweep-ran"
	_qstop_forget "$sid"
	rm -f "$(_quality_baseline_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks() {
	# R11: the sweep cadence is commits since the last sweep, not the clock.
	# The scoped run verifies nothing here (a source file with no test file),
	# so the sweep runs and blocks on its own failure — and the stamp records
	# the sha it ran at even though it found red (FU-24).
	local repo shared stamp sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-periodic-block-$$"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	(cd "$repo" && git add util.js package.json && git commit -q -m src) >/dev/null 2>&1
	stamp=$(_quality_gates_stamp_path "$repo")
	git -C "$repo" rev-parse HEAD~1 >"$stamp"
	rm -f "$(_quality_baseline_path "$repo")"
	_qstop_stamp "$sid" "$repo"
	printf 'module.exports = 2;\n' >"$repo/util.js"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks rc"
	assert_contains "$OUT" '"decision":"block"' "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks decision"
	assert_contains "$OUT" "Gate(s) failed:" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks full-sweep-reason"
	assert_not_contains "$OUT" "test-changed (" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks not-test-changed-reason"
	assert_eq "$(cat "$stamp")" "$(git -C "$repo" rev-parse HEAD)" "t_quality_stop_gate_scoped_periodic_full_sweep_promotes_and_blocks stamp-records-the-sweep"
	_qstop_forget "$sid"
	rm -f "$stamp" "$(_quality_baseline_path "$repo")"
	rm -rf "$repo"
}

t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass() {
	# Same promotion with a passing sweep: the turn is not blocked and the
	# stamp moves to the current sha, proving the sweep actually ran rather
	# than the turn passing because nothing was checked.
	local repo shared stamp sid
	repo=$(tmp_repo)
	shared="$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)"
	sid="quality-periodic-pass-$$"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	(cd "$repo" && git add util.js package.json && git commit -q -m src) >/dev/null 2>&1
	stamp=$(_quality_gates_stamp_path "$repo")
	git -C "$repo" rev-parse HEAD~1 >"$stamp"
	_qstop_stamp "$sid" "$repo"
	printf 'module.exports = 2;\n' >"$repo/util.js"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass rc"
	assert_eq "$OUT" "" "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass no-block"
	assert_eq "$(cat "$stamp")" "$(git -C "$repo" rev-parse HEAD)" "t_quality_stop_gate_scoped_periodic_full_sweep_rewrites_stamp_on_pass stamp-rewritten"
	_qstop_forget "$sid"
	rm -f "$stamp"
	rm -rf "$repo"
}

# C16: only a ROOT-level manifest deletion blocks; nested manifests never do.
t_quality_stop_gate_nested_manifest_deletion_does_not_block() {
	d=$(tmp_repo)
	_prev=$PWD
	cd "$d" || return 1
	mkdir -p node_modules/dep
	printf '{"name":"dep"}\n' >node_modules/dep/package.json
	git add -A -f && git commit -q -m "add nested manifest"
	git rm -q node_modules/dep/package.json
	run_hook "$SCAN_DIR/stop-gate.sh" '{"session_id":"nested-manifest","stop_hook_active":false}' \
		CLAUDE_PROJECT_DIR="$d" CC_SHARED_SCRIPTS="$SCAN_DIR/../skills/shared/scripts"
	cd "$_prev" || return 1
	assert_rc 0 "nested manifest deletion: rc 0"
	assert_not_contains "$OUT" "manifest disappeared" "nested manifest deletion: no block"
	_qstop_forget "nested-manifest"
	rm -rf "$d"
}
