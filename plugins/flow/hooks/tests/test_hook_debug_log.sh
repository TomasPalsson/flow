#!/usr/bin/env bash
# test_hook_debug_log.sh — F141: the on-demand decision log in lib/hookout.sh.
# Each exit helper appends one "<time> <hook> <decision> <reason80>" line when
# CLAUDE_HOOK_LOG is set or ~/.claude/flow-hooks.debug exists; otherwise it
# writes nothing anywhere and stdout/stderr are untouched.

# _hdl_script <dir> <name> <body> → runnable driver that sources hookout.sh.
_hdl_script() {
	{
		printf '#!/usr/bin/env bash\nset -u\n. "$HOOKOUT_LIB"\n%s\n' "$3"
	} >"$1/$2"
	printf '%s' "$1/$2"
}

_hdl_repeat() {
	local s='' i=0
	while [ "$i" -lt "$1" ]; do
		s="${s}x"
		i=$((i + 1))
	done
	printf '%s' "$s"
}

t_hdl_sentinel_one_line_per_helper() {
	local d s h want n
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	: >"$d/.claude/flow-hooks.debug"
	for h in 'hook_ok:ok' 'hook_deny "why not":deny' 'hook_block "why not":block' 'hook_feedback "why not":feedback' 'hook_note "why not":note' 'hook_soft "why not":soft'; do
		want=${h##*:}
		s=$(_hdl_script "$d" "h_$want.sh" "${h%:*}")
		rm -f "$d/.claude/flow-hooks.log"
		run_hook "$s" '{}' HOOKOUT_LIB="$SCAN_DIR/lib/hookout.sh" HOME="$d"
		n=$(grep -c . "$d/.claude/flow-hooks.log" 2>/dev/null || printf 0)
		assert_eq "$n" "1" "t_hdl_sentinel_one_line_per_helper $want appends exactly one line"
		assert_contains "$(cat "$d/.claude/flow-hooks.log" 2>/dev/null)" "h_$want.sh $want" "t_hdl_sentinel_one_line_per_helper $want line names hook and decision"
	done
	rm -rf "$d"
}

t_hdl_reason_is_one_line_and_80_chars() {
	local d s line
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	: >"$d/.claude/flow-hooks.debug"
	s=$(_hdl_script "$d" long.sh "hook_deny \"first
$(_hdl_repeat 120)\"")
	run_hook "$s" '{}' HOOKOUT_LIB="$SCAN_DIR/lib/hookout.sh" HOME="$d"
	line=$(cat "$d/.claude/flow-hooks.log")
	assert_eq "$(printf '%s\n' "$line" | grep -c .)" "1" "t_hdl_reason_is_one_line_and_80_chars single line"
	# 19-char ISO time + space + "long.sh deny " (13) + at most 80 reason chars
	assert_eq "$([ "${#line}" -le 113 ] && echo ok || echo "len ${#line}")" "ok" "t_hdl_reason_is_one_line_and_80_chars reason cut at 80"
	rm -rf "$d"
}

t_hdl_off_writes_nothing_and_output_is_identical() {
	local d s out_off err_off
	d=$(tmp_dir)
	mkdir -p "$d/.claude"
	s=$(_hdl_script "$d" same.sh 'hook_deny "same reason"')
	run_hook "$s" '{}' HOOKOUT_LIB="$SCAN_DIR/lib/hookout.sh" HOME="$d"
	out_off=$OUT
	err_off=$ERR
	assert_file_missing "$d/.claude/flow-hooks.log" "t_hdl_off_writes_nothing no sentinel, no log file"
	: >"$d/.claude/flow-hooks.debug"
	run_hook "$s" '{}' HOOKOUT_LIB="$SCAN_DIR/lib/hookout.sh" HOME="$d"
	assert_eq "$OUT" "$out_off" "t_hdl_off_writes_nothing stdout identical with the log on"
	assert_eq "$ERR" "$err_off" "t_hdl_off_writes_nothing stderr identical with the log on"
	rm -rf "$d"
}

t_hdl_env_var_alone_enables_the_log() {
	local d s
	d=$(tmp_dir)
	s=$(_hdl_script "$d" envlog.sh 'hook_ok')
	run_hook "$s" '{}' HOOKOUT_LIB="$SCAN_DIR/lib/hookout.sh" HOME="$d" CLAUDE_HOOK_LOG="$d/custom.log"
	assert_contains "$(cat "$d/custom.log" 2>/dev/null)" "envlog.sh ok" "t_hdl_env_var_alone_enables_the_log"
	rm -rf "$d"
}

t_hdl_spec_gate_run_appends_exactly_one_line() {
	local d repo
	d=$(tmp_dir)
	repo=$(tmp_repo)
	mkdir -p "$d/.claude"
	: >"$d/.claude/flow-hooks.debug"
	run_hook "$SCAN_DIR/spec-gate.sh" '{"tool_input":{"file_path":"'"$repo"'/a.py"}}' HOME="$d" CLAUDE_PROJECT_DIR="$repo"
	assert_eq "$(grep -c . "$d/.claude/flow-hooks.log" 2>/dev/null || printf 0)" "1" "t_hdl_spec_gate_run_appends_exactly_one_line count"
	assert_contains "$(cat "$d/.claude/flow-hooks.log" 2>/dev/null)" "spec-gate.sh ok" "t_hdl_spec_gate_run_appends_exactly_one_line names the hook"
	rm -rf "$d" "$repo"
}
