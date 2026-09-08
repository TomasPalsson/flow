#!/usr/bin/env bash
# test_bash_write.sh — unit V6 (Bash-write coverage) tests for tool-stamp.sh
# and post-bash-write.sh. Sourced by run.sh; every t_bw_* function below is
# discovered and run. See SPEC C19.
set -u

# _bw_json_str <text> — a JSON string literal (with quotes), escaped. Test
# infrastructure only (builds the stdin JSON handed to run_hook); mirrors
# hookout.sh's own escaping strategy without depending on its private helper.
_bw_json_str() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -Rs .
	else
		printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
	fi
}

_bw_stamp_path() {
	local tmp
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	printf '%s/claude-turn-%s-tool' "$tmp" "$1"
}

# _bw_wide_body <n> — <n> lines of "    pass", used to build a function body
# that exceeds the 60-line default max-func threshold.
_bw_wide_body() {
	local n=$1 i=0
	while [ "$i" -lt "$n" ]; do
		printf '    pass\n'
		i=$((i + 1))
	done
}

# ---------------------------------------------------------------------------
# tool-stamp.sh
# ---------------------------------------------------------------------------

t_bw_tool_stamp_creates_file() {
	local sid path
	sid="bwstamp1"
	path=$(_bw_stamp_path "$sid")
	rm -f "$path"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	assert_rc 0 "t_bw_tool_stamp_creates_file rc"
	assert_file_exists "$path" "t_bw_tool_stamp_creates_file stamp"
	assert_eq "$OUT" "" "t_bw_tool_stamp_creates_file no-stdout"
	rm -f "$path"
}

# ---------------------------------------------------------------------------
# post-bash-write.sh
# ---------------------------------------------------------------------------

t_bw_heredoc_size_violation_rc2() {
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sid="bwsize1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	cat >"$repo/big.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_heredoc_size_violation_rc2 rc"
	assert_contains "$ERR" "post-bash-write:" "t_bw_heredoc_size_violation_rc2 prefix"
	assert_contains "$ERR" "newer than this command's start and dirty in git" "t_bw_heredoc_size_violation_rc2 wording"
	assert_contains "$ERR" "big_function" "t_bw_heredoc_size_violation_rc2 function name"
	assert_contains "$ERR" "CC_NO_POST_BASH_WRITE" "t_bw_heredoc_size_violation_rc2 escape hatch"
	rm -rf "$repo"
}

t_bw_read_only_command_rc0_no_find() {
	local repo sid fakebin marker cmdjson
	repo=$(tmp_repo)
	sid="bwread1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	fakebin=$(tmp_dir)
	marker="$fakebin/find-called"
	cat >"$fakebin/find" <<'EOF'
#!/usr/bin/env bash
: >"$FAKE_FIND_MARKER"
exit 1
EOF
	chmod +x "$fakebin/find"
	cmdjson=$(_bw_json_str "cat README.md")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo" PATH="$fakebin:$PATH" FAKE_FIND_MARKER="$marker"
	assert_rc 0 "t_bw_read_only_command_rc0_no_find rc"
	assert_file_missing "$marker" "t_bw_read_only_command_rc0_no_find find-not-called"
	rm -rf "$repo" "$fakebin"
}

t_bw_ignored_path_write_rc0() {
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/generated"
	sid="bwign1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	cat >"$repo/generated/big.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > generated/big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_ignored_path_write_rc0 rc"
	rm -rf "$repo"
}

t_bw_test_file_tamper_rc2() {
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sid="bwtamper1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content='it.skip("broken", () => {});'
	cat >"$repo/foo.test.js" <<JSEOF
$content
JSEOF
	cmdtext="cat > foo.test.js <<'JSEOF'
$content
JSEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_test_file_tamper_rc2 rc"
	assert_contains "$ERR" "disabled or weakened a check" "t_bw_test_file_tamper_rc2 message"
	rm -rf "$repo"
}

t_bw_stamp_absent_rc0() {
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sid="bwnostamp1"
	rm -f "$(_bw_stamp_path "$sid")"
	content=$(
		printf 'def f():\n'
		_bw_wide_body 68
	)
	cat >"$repo/x.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > x.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_stamp_absent_rc0 rc"
	rm -rf "$repo"
}

t_bw_disabled_env_rc0() {
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sid="bwdisabled1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	cat >"$repo/big.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo" CC_NO_POST_BASH_WRITE=1
	assert_rc 0 "t_bw_disabled_env_rc0 rc"
	rm -rf "$repo"
}

t_bw_not_git_repo_rc0() {
	local d sid content cmdtext cmdjson
	d=$(tmp_dir)
	sid="bwnogit1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def f():\n'
		_bw_wide_body 68
	)
	cat >"$d/x.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > x.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_bw_not_git_repo_rc0 rc"
	rm -rf "$d"
}

t_bw_cap_over_50_files_note() {
	local repo sid cmdjson logdir logf i
	repo=$(tmp_repo)
	sid="bwcap1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	i=1
	while [ "$i" -le 55 ]; do
		printf 'x' >"$repo/f$i.txt"
		i=$((i + 1))
	done
	cmdjson=$(_bw_json_str 'for i in $(seq 1 55); do printf "x" > "f$i.txt"; done')
	logdir=$(tmp_dir)
	logf="$logdir/hooklog.txt"
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo" CLAUDE_HOOK_LOG="$logf"
	assert_rc 0 "t_bw_cap_over_50_files_note rc"
	assert_contains "$(cat "$logf" 2>/dev/null)" "capped" "t_bw_cap_over_50_files_note log-note"
	rm -rf "$repo" "$logdir"
}

t_bw_gate_config_heredoc_tamper_rc2() {
	# C19 fatal finding: a Bash heredoc that rewrites .claude/flow.config.json to
	# weaken stopGate must be caught by tamper-notice.sh via post-bash-write.sh,
	# not silently pruned because it lives under .claude/.
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	sid="bwgateconf1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content='{"stopGate": false}'
	cat >"$repo/.claude/flow.config.json" <<JSONEOF
$content
JSONEOF
	cmdtext="cat > .claude/flow.config.json <<'JSONEOF'
$content
JSONEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_gate_config_heredoc_tamper_rc2 rc"
	assert_contains "$ERR" "disabled or weakened a check" "t_bw_gate_config_heredoc_tamper_rc2 message"
	assert_contains "$ERR" "flow.config.json" "t_bw_gate_config_heredoc_tamper_rc2 filename"
	rm -rf "$repo"
}

t_bw_no_indicator_command_rc0() {
	local repo sid cmdjson
	repo=$(tmp_repo)
	sid="bwnoindic1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	cmdjson=$(_bw_json_str "grep -r foo bar")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_no_indicator_command_rc0 rc"
	assert_eq "$OUT" "" "t_bw_no_indicator_command_rc0 no-stdout"
	rm -rf "$repo"
}

t_bw_gitignored_runtime_churn_rc0() {
	# Lesson 2026-09-05: a running container kept appending to a gitignored
	# services/*/logs/*.txt while read-only Bash commands ran, and every one of
	# them was blocked with "file is 8000 lines (max 400)". Gitignored files are
	# runtime state the command did not author; they are not the command's output.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/services/app/logs"
	printf '/services/app/*\n' >"$repo/.gitignore"
	sid="bwgitign1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/services/app/logs/app.debug.py"
	cmdjson=$(_bw_json_str "grep -n foo README.md | python3 -c 'import sys; print(len(sys.stdin.read()))'")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_gitignored_runtime_churn_rc0 rc"
	assert_not_contains "$ERR" "app.debug.py" "t_bw_gitignored_runtime_churn_rc0 not named"
	rm -rf "$repo"
}

t_bw_gitignored_gate_config_still_rc2() {
	# The gitignore filter must not reopen the C19 hole: .claude/ is commonly
	# gitignored, and a heredoc weakening .claude/flow.config.json is still tamper.
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	printf '.claude/\n' >"$repo/.gitignore"
	sid="bwgitign2"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content='{"stopGate": false}'
	printf '%s\n' "$content" >"$repo/.claude/flow.config.json"
	cmdtext="cat > .claude/flow.config.json <<'JSONEOF'
$content
JSONEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_gitignored_gate_config_still_rc2 rc"
	assert_contains "$ERR" "flow.config.json" "t_bw_gitignored_gate_config_still_rc2 filename"
	rm -rf "$repo"
}

t_bw_same_command_gitignore_edit_rc2() {
	# Adversary 2026-09-05: appending an ignore rule for the file just written
	# must not hide it. Any ignore-file change in the same command disables the
	# gitignore filter for that command.
	local repo sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sid="bwgitign3"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '/evil.py\n' >>"$repo/.gitignore"
	printf '%s\n' "$content" >"$repo/evil.py"
	cmdtext="printf '/evil.py\\n' >> .gitignore; cat > evil.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_same_command_gitignore_edit_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_same_command_gitignore_edit_rc2 function name"
	rm -rf "$repo"
}

# _bw_repo_with_oversized_file <sid> — a fresh repo whose big.py holds a
# 69-line function written AFTER the tool stamp, i.e. a file size-guard
# really does fire on. Every "this command is NOT a writer" test must use
# it: asserting rc 0 in a repo whose only dirty file is README.md passes no
# matter how the command is classified (the .md extension is not a source
# extension, so size-guard never measures it and tamper-notice never flags
# it), which makes the test blind to the code path it names.
_bw_repo_with_oversized_file() {
	local repo
	repo=$(tmp_repo)
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$1\"}"
	sleep 1
	{
		printf 'def big_function():\n'
		_bw_wide_body 68
	} >"$repo/big.py"
	printf '%s' "$repo"
}

# _bw_assert_not_a_writer <name> <sid> <command> — the command must leave
# post-bash-write silent even though an oversized file is newer than the
# tool stamp and dirty in git.
_bw_assert_not_a_writer() {
	local name=$1 sid=$2 cmd=$3 repo cmdjson
	repo=$(_bw_repo_with_oversized_file "$sid")
	cmdjson=$(_bw_json_str "$cmd")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "$name rc"
	assert_eq "$OUT" "" "$name no-stdout"
	assert_eq "$ERR" "" "$name no-stderr"
	rm -rf "$repo"
}

t_bw_stderr_redirect_dirty_tracked_rc0() {
	# B2/FU-02: a read-only command whose only redirect is 2>/dev/null must
	# not be classified as a writer, even when an oversized file is dirty and
	# newer than the tool stamp.
	_bw_assert_not_a_writer t_bw_stderr_redirect_dirty_tracked_rc0 bwstderr1 \
		"grep -n node big.py 2>/dev/null"
}

t_bw_quoted_dev_null_redirect_rc0() {
	# A quoted /dev/null target is still /dev/null, still not a write.
	_bw_assert_not_a_writer t_bw_quoted_dev_null_redirect_rc0 bwqdevnull1 \
		'grep -n node big.py 2>"/dev/null"'
}

t_bw_dev_null_redirect_rc0() {
	# `>` targeting /dev/null is not a write.
	_bw_assert_not_a_writer t_bw_dev_null_redirect_rc0 bwdevnull1 \
		"echo hi > /dev/null"
}

t_bw_format_lint_never_invoked() {
	# post-bash-write.sh must never re-dispatch to format-lint.sh (only
	# size-guard.sh and tamper-notice.sh are re-run against a Bash write).
	assert_not_contains "$(cat "$SCAN_DIR/post-bash-write.sh")" "format-lint.sh" \
		"t_bw_format_lint_never_invoked no-format-lint-reference"
}

t_bw_gitignored_unicode_name_rc0() {
	# Adversary 2026-09-05: git check-ignore C-quotes non-ASCII paths by
	# default, so "café.py" never matched find's output and was linted anyway.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/logs"
	printf '/logs/\n' >"$repo/.gitignore"
	sid="bwgitign4"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/logs/café separação.py"
	cmdjson=$(_bw_json_str "grep -n foo README.md | python3 -c 'import sys; print(len(sys.stdin.read()))'")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_gitignored_unicode_name_rc0 rc"
	rm -rf "$repo"
}

t_bw_project_dir_is_git_subdir_rc2() {
	# Fix round 1 fatal finding: CLAUDE_PROJECT_DIR set to a subdirectory of
	# the git repo (e.g. `cd repo/backend && claude` in a monorepo) must
	# still find the dirty/changed intersection. `git status --porcelain`
	# paths are relative to the TOPLEVEL, never to CLAUDE_PROJECT_DIR.
	local repo sub sid content cmdtext cmdjson
	repo=$(tmp_repo)
	sub="$repo/sub"
	mkdir -p "$sub"
	sid="bwsubdir1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	cat >"$sub/big.py" <<PYEOF
$content
PYEOF
	cmdtext="cat > big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$sub"
	assert_rc 2 "t_bw_project_dir_is_git_subdir_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_project_dir_is_git_subdir_rc2 function name"
	rm -rf "$repo"
}

t_bw_quoted_arrow_not_a_write_rc0() {
	# Significant finding: a quote-unaware redirect scan mistook the `>` in
	# `'foo->bar'` for a write redirect and blocked a read-only command
	# whenever an oversized file happened to be dirty and newer than the
	# tool stamp.
	_bw_assert_not_a_writer t_bw_quoted_arrow_not_a_write_rc0 bwarrow1 \
		"grep -n 'foo->bar' big.py"
}

t_bw_single_quoted_gt_not_a_write_rc0() {
	# Significant finding (round 2): the redirect scan special-cased only
	# `->`/`=>`, so any other literal `>` inside a quoted argument counted as
	# a write redirect and blocked a command that wrote nothing.
	_bw_assert_not_a_writer t_bw_single_quoted_gt_not_a_write_rc0 bwsqgt1 \
		"grep -n 'a > b' big.py"
}

t_bw_double_quoted_gt_not_a_write_rc0() {
	_bw_assert_not_a_writer t_bw_double_quoted_gt_not_a_write_rc0 bwdqgt1 \
		'echo "x>y"'
}

t_bw_awk_program_gt_not_a_write_rc0() {
	# A `>` inside a double-quoted string nested in the single-quoted awk
	# program: the mask must handle nesting, not just the outermost quote.
	_bw_assert_not_a_writer t_bw_awk_program_gt_not_a_write_rc0 bwawkgt1 \
		'awk '"'"'{print $1 ">" $2}'"'"' big.py'
}

t_bw_quoted_lshift_then_heredoc_write_rc2() {
	# Significant finding (round 2): a line containing `<<` in a NON-heredoc
	# sense (here, inside a quoted string) used to set the heredoc-strip flag
	# with a bogus delimiter, so every following line — including the real
	# oversized heredoc write — was discarded as body and the hook exited 0.
	local repo sid content cmdtext cmdjson
	sid="bwlshift1"
	repo=$(_bw_repo_with_oversized_file "$sid")
	content=$(cat "$repo/big.py")
	cmdtext="echo \"shift << 2\"
cat > big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_quoted_lshift_then_heredoc_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_quoted_lshift_then_heredoc_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_here_string_then_heredoc_write_rc2() {
	# Same class: `<<<` is a here-string, not a heredoc opener.
	local repo sid content cmdtext cmdjson
	sid="bwherestr1"
	repo=$(_bw_repo_with_oversized_file "$sid")
	content=$(cat "$repo/big.py")
	cmdtext="grep foo <<< \"\$data\"
cat > big.py <<'PYEOF'
$content
PYEOF"
	cmdjson=$(_bw_json_str "$cmdtext")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_here_string_then_heredoc_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_here_string_then_heredoc_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_no_sed_newline_replacement() {
	# Portability (spec 003 "bash 3.2 + BSD coreutils"): `\n` in a sed
	# REPLACEMENT is a GNU extension — BSD sed emits a literal `n`, which
	# silently collapsed the part split so every writer token outside the
	# head position (`| sponge`, `&& tee`, `; cp`) was missed on macOS.
	local hits
	# A sed replacement carrying \n reads as `<delim>\n<delim>` in the script
	# text (`s/(&&|\|\|)/\n/g`); `tr ';&|' '\n\n\n'` and printf formats do not
	# put a delimiter on both sides of the escape, so they are not matched.
	hits=$(grep -nE '[/#|]\\n[/#|]' "$SCAN_DIR/post-bash-write.sh" |
		grep -v ':[[:space:]]*#' || true)
	assert_eq "$hits" "" "t_bw_no_sed_newline_replacement no-backslash-n-in-sed-rhs"
}

t_bw_digit_prefix_write_redirect_rc2() {
	# Significant finding: `1>file` (fd number immediately before the arrow,
	# target a real path) is a genuine write redirect, not a file-descriptor
	# form; only `N>&M` duplication and a `/dev/null` target are non-writes.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwdigit1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "printf 'x' 1> big.py")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_digit_prefix_write_redirect_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_digit_prefix_write_redirect_rc2 function name"
	rm -rf "$repo"
}

t_bw_arith_context_not_a_write_rc0() {
	# Improvable finding: the `$(( ))` arithmetic-masking branch that makes
	# `echo $((1>0))` a non-writer had no direct test.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwarith1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str 'echo $((1>0))')
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_arith_context_not_a_write_rc0 rc"
	rm -rf "$repo"
}

t_bw_large_command_fast_rc0() {
	# Significant finding: the old per-character redirect scan was O(n^2)
	# and stalled for over a minute on a >=16 KB single-line command. This
	# must return well within the hook timeout.
	local repo sid big cmdjson start elapsed
	repo=$(tmp_repo)
	sid="bwbig1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	big=$(head -c 20000 /dev/zero | tr '\0' 'x')
	cmdjson=$(_bw_json_str "python3 -c 'x = \"$big\"'")
	start=$SECONDS
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	elapsed=$((SECONDS - start))
	assert_rc 0 "t_bw_large_command_fast_rc0 rc"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_bw_large_command_fast_rc0 latency"
	else
		_fail "t_bw_large_command_fast_rc0 latency" "took ${elapsed}s (want <=5s)"
	fi
	rm -rf "$repo"
}

t_bw_sudo_tee_write_rc2() {
	# Improvable finding: `sudo tee big.py` still starts with a writer token
	# underneath the wrapper.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwsudo1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "sudo tee big.py")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_sudo_tee_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_sudo_tee_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_sed_inplace_long_flag_write_rc2() {
	# Improvable finding: `sed --in-place` (long flag) is a writer, same as
	# `sed -i`.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwsedlong1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "sed --in-place 's/a/b/' big.py")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_sed_inplace_long_flag_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_sed_inplace_long_flag_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_quoted_semicolon_not_a_writer_rc0() {
	# Significant finding (fix round): a quote-unaware part-splitter ran on
	# the RAW command, not quote-masked text, so `;`/`|`/`&` inside a quoted
	# argument floated a bogus part out whose head token could be a writer.
	# `git commit -m "wip; touch base"` used to split into a part starting
	# with `touch`, a writer token, and got blocked for writing nothing.
	_bw_assert_not_a_writer t_bw_quoted_semicolon_not_a_writer_rc0 bwqsemi1 \
		'git commit -m "wip; touch base"'
}

t_bw_shell_dash_c_write_rc2() {
	# Companion to the fix above: masking quoted separators means `sh -c
	# 'cp a b'` no longer accidentally splits into a `cp`-headed part, so the
	# `sh`/`bash`/`zsh` wrapper itself must be treated as a writer to keep
	# this class of wrapper-invoked write detected.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwshc1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "sh -c 'cp a b'")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_shell_dash_c_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_shell_dash_c_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_many_ignored_files_fast_rc0() {
	# Significant finding: the git-dirty set was built by appending to a
	# bash string one line at a time (O(n^2)). `--ignored=matching` emits one
	# porcelain line PER glob-ignored file (a `*.log` rule does not collapse
	# the way a directory ignore does), so a repo with a few thousand such
	# files added multi-second latency to every writer command.
	local repo sid content cmdjson i start elapsed
	repo=$(tmp_repo)
	printf '*.log\n' >"$repo/.gitignore"
	mkdir -p "$repo/logs"
	i=1
	while [ "$i" -le 3000 ]; do
		: >"$repo/logs/f$i.log"
		i=$((i + 1))
	done
	sid="bwmanyign1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "printf 'x' > big.py")
	start=$SECONDS
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	elapsed=$((SECONDS - start))
	assert_rc 2 "t_bw_many_ignored_files_fast_rc0 rc"
	if [ "$elapsed" -le 5 ]; then
		_pass "t_bw_many_ignored_files_fast_rc0 latency"
	else
		_fail "t_bw_many_ignored_files_fast_rc0 latency" "took ${elapsed}s (want <=5s)"
	fi
	rm -rf "$repo"
}

t_bw_claude_non_gate_config_ignored_not_flagged_rc0() {
	# Improvable finding: the .claude/ carve-out used to union in EVERY
	# regular file under .claude/ (minus skills/prune dirs) by raw mtime,
	# bypassing hook_changed_since's gitignore filtering entirely and
	# claiming "gate config ... changed" for a file that is not gate config
	# at all. Narrowed to the exact basenames tamper-notice.sh recognises as
	# gate config, so a gitignored, oversized, NON-gate-config file under
	# .claude/ is invisible to both the frozen intersection (gitignored) and
	# the carve-out (wrong basename), and the command is silent.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude/scripts"
	printf '.claude/\n' >"$repo/.gitignore"
	sid="bwclaudenongate1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/.claude/scripts/big.py"
	cmdjson=$(_bw_json_str "printf 'x' > dummy.txt")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "t_bw_claude_non_gate_config_ignored_not_flagged_rc0 rc"
	rm -rf "$repo"
}

t_bw_sponge_pipeline_write_rc2() {
	# Improvable finding: `sponge` as a pipeline stage is a writer.
	local repo sid content cmdjson
	repo=$(tmp_repo)
	sid="bwsponge1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	content=$(
		printf 'def big_function():\n'
		_bw_wide_body 68
	)
	printf '%s\n' "$content" >"$repo/big.py"
	cmdjson=$(_bw_json_str "cat big.py | sponge big.py")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_sponge_pipeline_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_sponge_pipeline_write_rc2 function name"
	rm -rf "$repo"
}

# _bw_assert_writer <name> <sid> <cmd> — the mirror of _bw_assert_not_a_writer:
# the command MUST be classified as a write, so the oversized big.py newer than
# the tool stamp is reported by size-guard (rc 2, function name in stderr).
_bw_assert_writer() {
	local name=$1 sid=$2 cmd=$3 repo cmdjson
	repo=$(_bw_repo_with_oversized_file "$sid")
	cmdjson=$(_bw_json_str "$cmd")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "$name rc"
	assert_contains "$ERR" "big_function" "$name function name"
	rm -rf "$repo"
}

t_bw_comment_apostrophe_then_write_rc2() {
	# Significant fix-round finding: an unbalanced quote inside a `#` comment
	# flipped the quote masker into "inside a quote" for the rest of the
	# command, so the real `>` on the next line was masked to Q and the
	# oversized write was missed entirely (silent rc 0).
	_bw_assert_writer t_bw_comment_apostrophe_then_write_rc2 bwcomquote1 \
		"# don't clobber
printf 'x' > big.py"
}

t_bw_comment_dquote_then_heredoc_write_rc2() {
	# Same masker bug via an unbalanced double quote plus a heredoc write.
	_bw_assert_writer t_bw_comment_dquote_then_heredoc_write_rc2 bwcomquote2 \
		'# say "hi to the user
cat > big.py <<PYEOF
x
PYEOF'
}

t_bw_gt_in_comment_not_a_writer_rc0() {
	# Mirror image of the same gap: a `>` that lives inside a shell comment
	# is not a redirect, so a read-only command must stay silent.
	_bw_assert_not_a_writer t_bw_gt_in_comment_not_a_writer_rc0 bwcomgt1 \
		"grep foo big.py # results > here"
}

t_bw_hash_in_word_not_a_comment_rc2() {
	# The comment rule must require a line start or leading whitespace: a `#`
	# inside a word (`${z#pre}`, `http://a#b`) is data, and treating it as a
	# comment would drop the real write that follows it on the same line.
	_bw_assert_writer t_bw_hash_in_word_not_a_comment_rc2 bwhashword1 \
		'echo ${z#pre} && printf x > big.py'
}

t_bw_escaped_gt_not_a_writer_rc0() {
	# Improvable fix-round finding: `\>` is an escaped literal, not a
	# redirect — real bash writes nothing for `echo a \> b`.
	_bw_assert_not_a_writer t_bw_escaped_gt_not_a_writer_rc0 bwescgt1 \
		'echo a \> b'
}

t_bw_nested_paren_arith_not_a_write_rc0() {
	# Improvable fix-round finding: the regex-based `$(( … ))` stripper could
	# not match a nested paren, so `echo $(( (1) > 0 ))` still read as a
	# redirect and blocked a command that writes nothing.
	_bw_assert_not_a_writer t_bw_nested_paren_arith_not_a_write_rc0 bwarith2 \
		'echo $(( (1) > 0 ))'
}

t_bw_dquote_in_filename_write_rc2() {
	# Improvable fix-round finding: git C-quotes a path containing `"` (or a
	# backslash) even under core.quotePath=false, so stripping the outer
	# quotes without un-escaping never matched hook_changed_since's raw path
	# and the write was missed. Parsed from `--porcelain -z` now.
	local repo sid cmdjson
	repo=$(tmp_repo)
	sid="bwdq1"
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	{
		printf 'def big_function():\n'
		_bw_wide_body 68
	} >"$repo/a\"b.py"
	cmdjson=$(_bw_json_str "printf x > 'a\"b.py'")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_dquote_in_filename_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_dquote_in_filename_write_rc2 function name"
	rm -rf "$repo"
}

t_bw_renamed_file_write_rc2() {
	# The `-z` porcelain form prints a rename as `XY <to>` followed by a bare
	# `<from>` record; the from-record must be skipped, and the to-path must
	# still be reported.
	local repo sid cmdjson
	repo=$(tmp_repo)
	sid="bwren1"
	{
		printf 'def big_function():\n'
		_bw_wide_body 68
	} >"$repo/orig.py"
	git -C "$repo" add orig.py >/dev/null 2>&1
	git -C "$repo" commit -q -m add >/dev/null 2>&1
	run_hook "$SCAN_DIR/tool-stamp.sh" "{\"session_id\":\"$sid\"}"
	sleep 1
	git -C "$repo" mv orig.py big.py >/dev/null 2>&1
	printf '    pass\n' >>"$repo/big.py"
	cmdjson=$(_bw_json_str "printf '    pass\\n' >> big.py")
	run_hook "$SCAN_DIR/post-bash-write.sh" \
		"{\"session_id\":\"$sid\",\"tool_input\":{\"command\":$cmdjson}}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "t_bw_renamed_file_write_rc2 rc"
	assert_contains "$ERR" "big_function" "t_bw_renamed_file_write_rc2 function name"
	rm -rf "$repo"
}
