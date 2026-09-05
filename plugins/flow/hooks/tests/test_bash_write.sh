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
	assert_contains "$ERR" "big_function" "t_bw_heredoc_size_violation_rc2 function name"
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
