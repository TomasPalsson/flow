#!/usr/bin/env bash
# test_loop_gate.sh — unit K-K tests for the Stop hook loop-gate.sh (spec
# 006 K-K). Sourced by run.sh; every t_loop_gate_* function below is
# discovered and run. Fakes CC_FLOW_BIN so these tests never depend on
# node or `flow loop` existing (that is Slice 1's contract).
set -u

LOOP_GATE="$SCAN_DIR/loop-gate.sh"

# _fake_flow_bin <dir> <body> — write an executable "flow" fake at
# <dir>/flow with <body> as its script content, and echo its path.
_fake_flow_bin() {
	local d="$1" body="$2" f
	mkdir -p "$d"
	f="$d/flow"
	printf '#!/usr/bin/env bash\n%s\n' "$body" >"$f"
	chmod +x "$f"
	printf '%s' "$f"
}

t_loop_gate_no_contract_fast_path() {
	local repo bindir fbin
	repo=$(tmp_repo)
	bindir=$(tmp_dir)
	fbin=$(_fake_flow_bin "$bindir" 'echo spawned >"'"$bindir"'/spawned"; exit 1')
	run_hook "$LOOP_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_loop_gate_no_contract_fast_path rc"
	assert_eq "$OUT" "" "t_loop_gate_no_contract_fast_path no-stdout"
	assert_file_missing "$bindir/spawned" "t_loop_gate_no_contract_fast_path no-spawn"
	rm -rf "$repo" "$bindir"
}

t_loop_gate_passes_block_json_through() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude/loop"
	: >"$repo/.claude/loop/loop.md"
	bindir=$(tmp_dir)
	fbin=$(_fake_flow_bin "$bindir" '
if [ "$1" = "loop" ] && [ "$2" = "tick" ] && [ "$3" = "--hook" ] && [ "$4" = "--session" ] && [ "$5" = "s1" ]; then
  printf "%s\n" "{\"decision\":\"block\",\"reason\":\"R\"}"
  exit 0
fi
printf "wrong argv: %s\n" "$*" >&2
exit 3
')
	run_hook "$LOOP_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_loop_gate_passes_block_json_through rc"
	assert_eq "$OUT" '{"decision":"block","reason":"R"}' "t_loop_gate_passes_block_json_through stdout"
	rm -rf "$repo" "$bindir"
}

t_loop_gate_allows_on_empty_output() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude/loop"
	: >"$repo/.claude/loop/loop.md"
	bindir=$(tmp_dir)
	fbin=$(_fake_flow_bin "$bindir" 'exit 0')
	run_hook "$LOOP_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_loop_gate_allows_on_empty_output rc"
	assert_eq "$OUT" "" "t_loop_gate_allows_on_empty_output no-stdout"
	rm -rf "$repo" "$bindir"
}

t_loop_gate_allows_when_flow_fails() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude/loop"
	: >"$repo/.claude/loop/loop.md"
	bindir=$(tmp_dir)
	fbin=$(_fake_flow_bin "$bindir" 'echo "should not surface" >&2; exit 1')
	run_hook "$LOOP_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_loop_gate_allows_when_flow_fails rc"
	assert_eq "$OUT" "" "t_loop_gate_allows_when_flow_fails no-stdout"
	rm -rf "$repo" "$bindir"
}

t_loop_gate_off_marker_skips() {
	local repo bindir fbin
	repo=$(tmp_repo)
	mkdir -p "$repo/.claude/loop"
	: >"$repo/.claude/loop/loop.md"
	: >"$repo/.claude/flow.off"
	bindir=$(tmp_dir)
	fbin=$(_fake_flow_bin "$bindir" 'echo spawned >"'"$bindir"'/spawned"; exit 1')
	run_hook "$LOOP_GATE" '{"session_id":"s1","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" CC_FLOW_BIN="$fbin"
	assert_rc 0 "t_loop_gate_off_marker_skips rc"
	assert_eq "$OUT" "" "t_loop_gate_off_marker_skips no-stdout"
	assert_file_missing "$bindir/spawned" "t_loop_gate_off_marker_skips no-spawn"
	rm -rf "$repo" "$bindir"
}

t_loop_gate_wired() {
	local hooks_json
	hooks_json="$SCAN_DIR/hooks.json"
	assert_file_exists "$hooks_json" "t_loop_gate_wired hooks.json-exists"
	if command -v python3 >/dev/null 2>&1; then
		if python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
stop = d["hooks"]["Stop"]
found = False
for group in stop:
    for h in group.get("hooks", []):
        if "loop-gate.sh" in h.get("command", "") and "statusMessage" in h:
            found = True
sys.exit(0 if found else 1)
' "$hooks_json"; then
			_pass "t_loop_gate_wired loop-gate-in-stop-with-statusMessage"
		else
			_fail "t_loop_gate_wired loop-gate-in-stop-with-statusMessage" "loop-gate.sh not found in Stop group with statusMessage"
		fi
	else
		if grep -q 'loop-gate.sh' "$hooks_json" && grep -q 'statusMessage' "$hooks_json"; then
			_pass "t_loop_gate_wired loop-gate-in-stop-with-statusMessage"
		else
			_fail "t_loop_gate_wired loop-gate-in-stop-with-statusMessage" "grep fallback failed"
		fi
	fi
}
