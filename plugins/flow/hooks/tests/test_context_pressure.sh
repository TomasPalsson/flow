#!/usr/bin/env bash
# test_context_pressure.sh — context-pressure.sh, spec 009 B4.
#
# One additionalContext note per 60k-token bucket past a window-scaled
# threshold (160k on 200k, 250k on 1M); silent below threshold, on a repeat
# bucket, on a missing/unreadable transcript, or under `flow off`.

# _cp_json_str <text> — a JSON string literal (with quotes). Test
# infrastructure only (builds the stdin JSON handed to run_hook); mirrors
# hookout.sh's own escaping strategy without depending on its private helper.
_cp_json_str() {
	if command -v jq >/dev/null 2>&1; then
		printf '%s' "$1" | jq -Rs .
	else
		printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
	fi
}

# _cp_append_usage <transcript-file> <tokens> <model> — appends one JSONL
# record carrying a message.usage block whose input_tokens alone sums to
# <tokens> (the other two usage fields are 0; only the sum is under test).
_cp_append_usage() {
	printf '{"message":{"model":%s,"usage":{"input_tokens":%s,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}\n' \
		"$(_cp_json_str "$3")" "$2" >>"$1"
}

_cp_state_file() { printf '%s/claude-context-%s' "${TMPDIR:-/tmp}" "$1"; }

_cp_run() {
	local sid=$1 transcript=$2
	run_hook "$SCAN_DIR/context-pressure.sh" \
		"{\"session_id\":\"$sid\",\"transcript_path\":$(_cp_json_str "$transcript")}"
}

t_context_pressure_200k_model_progression() {
	local d transcript sid model
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-200k"
	model="claude-sonnet-4-5"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 150000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "200k@150k rc"
	assert_not_contains "$OUT" "additionalContext" "200k@150k below threshold is silent"

	_cp_append_usage "$transcript" 170000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "200k@170k rc"
	assert_contains "$OUT" "PreToolUse" "200k@170k hookEventName"
	assert_contains "$OUT" "~170k tokens of a ~200k window" "200k@170k message"

	_cp_append_usage "$transcript" 175000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "200k@175k rc"
	assert_not_contains "$OUT" "additionalContext" "200k@175k same bucket is silent"

	_cp_append_usage "$transcript" 230000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "200k@230k rc"
	assert_not_contains "$OUT" "additionalContext" "200k@230k now 1M window, below its 250k threshold, is silent"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$d"
}

t_context_pressure_opus_family_below_threshold_is_silent() {
	local d transcript sid
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-opus"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 170000 "claude-opus-5"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "opus@170k rc"
	assert_not_contains "$OUT" "additionalContext" "opus@170k below its 1M-window 250k threshold is silent"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$d"
}

t_context_pressure_1m_session_progression() {
	local d transcript sid model
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-1m"
	model="claude-sonnet-4-5[1m]"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 260000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "1m@260k rc"
	assert_contains "$OUT" "~260k tokens of a ~1000k window" "1m@260k message names the 1000k window"

	_cp_append_usage "$transcript" 300000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "1m@300k rc"
	assert_not_contains "$OUT" "additionalContext" "1m@300k same bucket is silent"

	_cp_append_usage "$transcript" 320000 "$model"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "1m@320k rc"
	assert_contains "$OUT" "~320k tokens of a ~1000k window" "1m@320k bucket advanced, fires again"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$d"
}

t_context_pressure_missing_transcript_is_silent() {
	local sid
	sid="cp-missing"
	rm -f "$(_cp_state_file "$sid")"

	_cp_run "$sid" "/nonexistent/path/does-not-exist.jsonl"
	assert_rc 0 "missing transcript rc"
	assert_eq "$OUT" "" "missing transcript no stdout"

	rm -f "$(_cp_state_file "$sid")"
}

t_context_pressure_malformed_last_line_uses_previous_usage() {
	local d transcript sid
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-malformed"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 170000 "claude-sonnet-4-5"
	printf 'not json at all {{{\n' >>"$transcript"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "malformed tail rc"
	assert_contains "$OUT" "~170k tokens of a ~200k window" "malformed last line falls back to the previous usage line"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$d"
}

t_context_pressure_malformed_middle_line_uses_latest_valid() {
	local d transcript sid
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-malformed-middle"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 170000 "claude-sonnet-4-5"
	printf 'garbage {{{\n' >>"$transcript"
	_cp_append_usage "$transcript" 320000 "claude-sonnet-4-5"
	_cp_run "$sid" "$transcript"
	assert_rc 0 "malformed middle rc"
	assert_contains "$OUT" "~320k tokens of a ~1000k window" "a malformed middle line does not hide the later valid record"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$d"
}

t_context_pressure_flow_off_marker_is_silent() {
	local repo d transcript sid
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/flow.off"
	d=$(tmp_dir)
	transcript="$d/transcript.jsonl"
	sid="cp-off"
	rm -f "$(_cp_state_file "$sid")"

	_cp_append_usage "$transcript" 300000 "claude-sonnet-4-5"
	run_hook "$SCAN_DIR/context-pressure.sh" \
		"{\"session_id\":\"$sid\",\"transcript_path\":$(_cp_json_str "$transcript")}" \
		CLAUDE_PROJECT_DIR="$repo"
	assert_rc 0 "flow off rc"
	assert_eq "$OUT" "" "flow off no stdout"

	rm -f "$(_cp_state_file "$sid")"
	rm -rf "$repo" "$d"
}
