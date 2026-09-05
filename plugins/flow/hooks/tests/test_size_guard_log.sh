#!/usr/bin/env bash
# size-guard.sh must exempt *.log files (e.g. .claude/lesson-fires.log) from
# the file-length heuristic: git is the enforcement boundary for what gets
# measured, and a growing bookkeeping log is not code to split up.

_sgl_lines() {
	: >"$1"
	local i=0
	while [ $i -lt "$2" ]; do
		printf 'line %s\n' "$i" >>"$1"
		i=$((i + 1))
	done
}

t_size_guard_skips_log_files() {
	local repo json
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	_sgl_lines "$repo/.claude/lesson-fires.log" 500
	json=$(printf '{"session_id":"sgl-1","tool_input":{"file_path":"%s"}}' "$repo/.claude/lesson-fires.log")
	run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "log: size-guard rc 0"
	assert_eq "$ERR" "" "log: size-guard silent stderr"
	rm -rf "$repo"
}

t_size_guard_still_reports_oversized_code() {
	if ! command -v python3 >/dev/null 2>&1; then
		_pass "code: skipped (python3 not installed)"
		return
	fi
	local repo json
	repo=$(tmp_repo)
	_sgl_lines "$repo/big.sh" 500
	json=$(printf '{"session_id":"sgl-2","tool_input":{"file_path":"%s"}}' "$repo/big.sh")
	run_hook "$SCAN_DIR/size-guard.sh" "$json" CLAUDE_PROJECT_DIR="$repo"
	assert_rc 2 "code: size-guard still reports oversized files"
	assert_contains "$ERR" "max 400" "code: stderr names the limit"
	rm -rf "$repo"
}
