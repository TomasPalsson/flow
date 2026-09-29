#!/usr/bin/env bash
# test_finish_gate.sh — tests for the Stop hook finish-gate.sh. Sourced by
# run.sh; every t_finish_gate_* function is discovered and run. Fakes
# CC_FLOW_BIN so these tests never depend on `flow finish` itself.
set -u

FINISH_GATE="$SCAN_DIR/finish-gate.sh"

_fg_fake_bin() {
	local d="$1" body="$2" f
	mkdir -p "$d"
	f="$d/flow"
	printf '#!/usr/bin/env bash\n%s\n' "$body" >"$f"
	chmod +x "$f"
	printf '%s' "$f"
}

t_finish_gate_unarmed_fast_path() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.specs/001-x"
	bindir=$(tmp_dir)
	fbin=$(_fg_fake_bin "$bindir" 'echo spawned >"'"$bindir"'/spawned"; exit 1')
	run_hook "$FINISH_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_finish_gate_unarmed_fast_path rc"
	assert_eq "$OUT" "" "t_finish_gate_unarmed_fast_path no-stdout"
	assert_file_missing "$bindir/spawned" "t_finish_gate_unarmed_fast_path no-spawn"
	rm -rf "$repo" "$bindir"
}

t_finish_gate_passes_block_json_through() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.specs/001-x"
	: >"$repo/.specs/001-x/FINISH.md"
	bindir=$(tmp_dir)
	fbin=$(_fg_fake_bin "$bindir" '
if [ "$1" = "finish" ] && [ "$2" = "check" ] && [ "$3" = "--hook" ] && [ "$4" = "--session" ] && [ "$5" = "s1" ]; then
  printf "%s\n" "{\"decision\":\"block\",\"reason\":\"R\"}"
  exit 0
fi
printf "wrong argv: %s\n" "$*" >&2
exit 3
')
	run_hook "$FINISH_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_finish_gate_passes_block_json_through rc"
	assert_eq "$OUT" '{"decision":"block","reason":"R"}' "t_finish_gate_passes_block_json_through stdout"
	rm -rf "$repo" "$bindir"
}

t_finish_gate_fails_open_on_cli_error() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.specs/001-x"
	: >"$repo/.specs/001-x/FINISH.md"
	bindir=$(tmp_dir)
	fbin=$(_fg_fake_bin "$bindir" 'exit 7')
	run_hook "$FINISH_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_finish_gate_fails_open_on_cli_error rc"
	assert_eq "$OUT" "" "t_finish_gate_fails_open_on_cli_error no-stdout"
	rm -rf "$repo" "$bindir"
}

t_finish_gate_wired_after_loop_gate() {
	local names
	names=$(jq -r '[.hooks.Stop[].hooks[].command | select(test("gate.sh"))] | map(sub(".*/";"")) | join(",")' "$SCAN_DIR/hooks.json")
	assert_eq "$names" "stop-gate.sh,loop-gate.sh,finish-gate.sh" "t_finish_gate_wired_after_loop_gate order"
	assert_eq "$(jq -r '.hooks.Stop[0].hooks[2].statusMessage' "$SCAN_DIR/hooks.json")" "flow: finish check…" "t_finish_gate_wired_after_loop_gate statusMessage"
	assert_eq "$(jq -r '.hooks.Stop[0].hooks[2].timeout' "$SCAN_DIR/hooks.json")" "30" "t_finish_gate_wired_after_loop_gate timeout"
}
