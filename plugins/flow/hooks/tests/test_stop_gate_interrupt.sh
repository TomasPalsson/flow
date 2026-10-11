#!/usr/bin/env bash
# test_stop_gate_interrupt.sh — F144: a turn that ends without a Stop (the user
# interrupts) must not drop its edits from the next turn's change set.
#
# stop-gate.sh writes "<stamp>.consumed" once it has judged a turn (any row past
# R0); turn-stamp.sh resets the stamp only when the stamp is missing or that
# marker exists, and removes the marker when it resets.

_t_si_shared() { (cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P); }
_t_si_scripts() { (cd "$SCAN_DIR/../scripts" && pwd -P); }

# _t_si_repo → a committed node fixture whose test script always fails, so a
# Stop that sees changed files blocks and names them.
_t_si_repo() {
	local repo
	repo=$(tmp_repo)
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	printf 'test("a", () => {});\n' >"$repo/a.test.js"
	printf 'test("b", () => {});\n' >"$repo/b.test.js"
	git -C "$repo" add package.json a.test.js b.test.js >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm node >/dev/null 2>&1
	touch -t 202001010000 "$repo/.git/info/exclude" 2>/dev/null || true
	printf '%s' "$repo"
}

_t_si_prompt() {
	run_hook "$SCAN_DIR/turn-stamp.sh" "{\"session_id\":\"$1\"}"
}

# _t_si_backdate_stamp <sid> — the stamp as an older turn start, so files the
# test writes right now are strictly newer than it.
_t_si_backdate_stamp() { touch -t 202006010000 "${TMPDIR:-/tmp}/claude-turn-$1"; }

_t_si_stop() {
	local sid=$1 repo=$2
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$(_t_si_shared)" CC_SCRIPTS_DIR="$(_t_si_scripts)"
}

_t_si_forget() {
	rm -f "${TMPDIR:-/tmp}/claude-turn-$1" "${TMPDIR:-/tmp}/claude-turn-$1.consumed" \
		"${TMPDIR:-/tmp}/claude-count-$1" "${TMPDIR:-/tmp}/claude-once-$1"
}

t_stopint_interrupted_turn_edits_stay_in_the_change_set() {
	local repo sid
	repo=$(_t_si_repo)
	sid="stopint-a-$$"
	_t_si_forget "$sid"
	_t_si_prompt "$sid"
	_t_si_backdate_stamp "$sid"
	printf 'test("a", () => {}); // edited\n' >"$repo/a.test.js"
	# the first turn is interrupted: no Stop runs; the user sends another prompt
	touch -t 202101010000 "$repo/a.test.js"
	_t_si_prompt "$sid"
	printf 'test("b", () => {}); // edited\n' >"$repo/b.test.js"
	_t_si_stop "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stopint_interrupted_turn_edits_stay_in_the_change_set blocks"
	assert_contains "$OUT" "a.test.js" "t_stopint_interrupted_turn_edits_stay_in_the_change_set names the interrupted turn's file"
	assert_contains "$OUT" "b.test.js" "t_stopint_interrupted_turn_edits_stay_in_the_change_set names this turn's file"
	_t_si_forget "$sid"
	rm -f "${TMPDIR:-/tmp}"/claude-baseline-"$(basename "$repo")"-* "${TMPDIR:-/tmp}"/claude-gates-"$(basename "$repo")"-*
	rm -rf "$repo"
}

t_stopint_consumed_turn_resets_so_an_idle_turn_is_silent() {
	local repo sid
	repo=$(_t_si_repo)
	sid="stopint-b-$$"
	_t_si_forget "$sid"
	_t_si_prompt "$sid"
	_t_si_backdate_stamp "$sid"
	printf 'test("a", () => {}); // edited\n' >"$repo/a.test.js"
	_t_si_stop "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stopint_consumed_turn_resets_so_an_idle_turn_is_silent first Stop judged the edit"
	assert_file_exists "${TMPDIR:-/tmp}/claude-turn-$sid.consumed" "t_stopint_consumed_turn_resets_so_an_idle_turn_is_silent marker written"
	sleep 1
	_t_si_prompt "$sid"
	assert_file_missing "${TMPDIR:-/tmp}/claude-turn-$sid.consumed" "t_stopint_consumed_turn_resets_so_an_idle_turn_is_silent marker removed on reset"
	_t_si_stop "$sid" "$repo"
	assert_eq "$OUT" "" "t_stopint_consumed_turn_resets_so_an_idle_turn_is_silent no edits, silent"
	_t_si_forget "$sid"
	rm -rf "$repo"
}

t_stopint_first_prompt_creates_the_stamp() {
	local sid
	sid="stopint-c-$$"
	_t_si_forget "$sid"
	_t_si_prompt "$sid"
	assert_rc 0 "t_stopint_first_prompt_creates_the_stamp rc"
	assert_eq "$OUT$ERR" "" "t_stopint_first_prompt_creates_the_stamp silent"
	assert_file_exists "${TMPDIR:-/tmp}/claude-turn-$sid" "t_stopint_first_prompt_creates_the_stamp stamp exists"
	_t_si_forget "$sid"
}

t_stopint_stop_hook_active_does_not_consume() {
	local repo sid
	repo=$(_t_si_repo)
	sid="stopint-d-$$"
	_t_si_forget "$sid"
	_t_si_prompt "$sid"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\",\"stop_hook_active\":true}" CLAUDE_PROJECT_DIR="$repo"
	assert_file_missing "${TMPDIR:-/tmp}/claude-turn-$sid.consumed" "t_stopint_stop_hook_active_does_not_consume R0 leaves the stamp alone"
	_t_si_forget "$sid"
	rm -rf "$repo"
}
