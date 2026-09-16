#!/usr/bin/env bash
# test_stop_gate.sh — the Stop gate's decision table (SPEC C10, rows R0-R16).
# Sourced by run.sh; every t_stop_* function below is discovered and run.
#
# Every row here needs a TURN STAMP: the change set is find-newer over
# ${TMPDIR}/claude-turn-<session_id> and nothing else (B6/FU-04), so a fixture
# that does not stamp the turn has an empty Δ and is allowed in silence — which
# is itself one of the rows below (R3).
set -u

# _stop_shared — the repo's real shared gate scripts (check-all/test-changed).
_stop_shared() { (cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P); }

# _stop_scripts — the repo's real scripts/ dir (flow-lint).
_stop_scripts() { (cd "$SCAN_DIR/../scripts" && pwd -P); }

# _stop_tasks <repo> [extra task line] — the ACTIVE feature (spec 004 K-A):
# .specs/001-x/TASKS.md in the K-B grammar, plus the .specs/.current pointer.
# Base: is the repo's real HEAD so flow-lint's git joins resolve.
_stop_tasks() {
	local repo=$1 base
	base=$(git -C "$repo" rev-parse --short HEAD 2>/dev/null)
	mkdir -p "$repo/.specs/001-x"
	cat >"$repo/.specs/001-x/TASKS.md" <<EOF
# Tasks — X
Spec: spec.md · Design: none · Base: $base · Route: oneshot · Test: \`true\`
Approved: 2026-01-01 by user

## Phase 1 — Thing
Goal: the thing works.
Independent test: \`true\`
- [ ] T001 do the thing — files: src/a.ts — verify: \`true\`
${2:-}
EOF
	printf '001-x\n' >"$repo/.specs/.current"
}

# _stop_stamp <sid> <repo> — start the turn: a stamp older than everything in
# the fixture, so every file written by the test counts as changed this turn.
# The ignore files are backdated with it, because hookout's turn-scoped rule
# treats an ignore file newer than the stamp as "written this turn".
_stop_stamp() {
	rm -f "${TMPDIR:-/tmp}/claude-count-$1" "${TMPDIR:-/tmp}/claude-once-$1"
	: >"${TMPDIR:-/tmp}/claude-turn-$1"
	touch -t 202006010000 "${TMPDIR:-/tmp}/claude-turn-$1"
	touch -t 202001010000 "$2/.git/info/exclude" 2>/dev/null || true
	[ -f "$2/.gitignore" ] && touch -t 202001010000 "$2/.gitignore"
	return 0
}

# _stop_forget <sid> — drop this session's stamp, ladder and once-only state.
_stop_forget() {
	rm -f "${TMPDIR:-/tmp}/claude-turn-$1" "${TMPDIR:-/tmp}/claude-count-$1" \
		"${TMPDIR:-/tmp}/claude-once-$1"
}

# _stop_state_path <repo> <kind> — the gates (sweep) stamp or the baseline file
# for <repo>, computed exactly as stop-gate.sh computes them.
_stop_state_path() {
	local top tmp hash8 base branch
	top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)
	[ -z "$top" ] && top="$1"
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	base=$(basename "$top")
	if [ "$2" = "gates" ]; then
		hash8=$(printf '%s' "$top" | cksum | awk '{print $1}')
		hash8=$(printf '%s' "$hash8" | tail -c 8)
		printf '%s/claude-gates-%s-%s' "$tmp" "$base" "$hash8"
	else
		branch=$(git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -c 'A-Za-z0-9_-' '_')
		printf '%s/claude-baseline-%s-%s' "$tmp" "$base" "$branch"
	fi
}

# _stop_run <sid> <repo> [VAR=val ...] — one Stop with the real gate scripts.
_stop_run() {
	local sid=$1 repo=$2
	shift 2
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$(_stop_shared)" \
		CC_SCRIPTS_DIR="$(_stop_scripts)" "$@"
}

# _stop_node_repo <repo> <test-script> — a committed one-package node fixture.
_stop_node_repo() {
	printf '{"name":"x","scripts":{"test":"%s"}}\n' "$2" >"$1/package.json"
	printf 'test("x", () => {});\n' >"$1/app.test.js"
	git -C "$1" add package.json app.test.js >/dev/null 2>&1
	git -C "$1" -c user.email=t@t -c user.name=t commit -qm node >/dev/null 2>&1
}

# --- R1: an unrecognised stopGate is loud ---------------------------------
t_stop_r1_unknown_mode_notes_and_does_not_gate() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r1-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": "on"}\n' >"$repo/.claude/flow.config.json"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r1_unknown_mode_notes_and_does_not_gate rc"
	assert_contains "$OUT" '"systemMessage"' "t_stop_r1_unknown_mode_notes_and_does_not_gate notes"
	assert_contains "$OUT" 'stopGate=\"on\"' "t_stop_r1_unknown_mode_notes_and_does_not_gate names-the-value"
	assert_not_contains "$OUT" '"decision"' "t_stop_r1_unknown_mode_notes_and_does_not_gate does-not-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r1_known_modes_still_gate() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r1k-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r1_known_modes_still_gate rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r1_known_modes_still_gate blocks"
	# stopGate:true is the full-sweep path: it carries its own hatch too, and
	# the hatch is checked by USING it — a named escape that does not escape is
	# worse than none, and a grep for the string cannot tell the two apart.
	assert_contains "$OUT" "CC_NO_STOP_GATE=1" "t_stop_r1_known_modes_still_gate sweep-block-names-its-escape-hatch"
	assert_contains "$OUT" "To reproduce: cd " "t_stop_r1_known_modes_still_gate sweep-block-reproduce-line"
	_stop_run "$sid" "$repo" CC_NO_STOP_GATE=1
	assert_rc 0 "t_stop_r1_known_modes_still_gate env-hatch-rc"
	assert_not_contains "$OUT" '"decision"' "t_stop_r1_known_modes_still_gate env-hatch-really-escapes"
	printf '{"stopGate": false}\n' >"$repo/.claude/flow.config.json"
	touch -t 202001010000 "$repo/.claude/flow.config.json"
	_stop_run "$sid" "$repo"
	assert_not_contains "$OUT" '"decision"' "t_stop_r1_known_modes_still_gate config-hatch-really-escapes"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" gates)" "$(_stop_state_path "$repo" baseline)"
	rm -rf "$repo"
}

# --- R2: work in flight is not a turn to gate -----------------------------
t_stop_r2_background_tasks_allow_with_a_note() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r2-$$"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'module.exports = 1;\n' >"$repo/util.js"
	run_hook "$SCAN_DIR/stop-gate.sh" \
		"{\"session_id\":\"$sid\",\"background_tasks\":[{\"description\":\"dev server\"}]}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$(_stop_shared)"
	assert_rc 0 "t_stop_r2_background_tasks_allow_with_a_note rc"
	assert_contains "$OUT" "background task" "t_stop_r2_background_tasks_allow_with_a_note names-them"
	assert_not_contains "$OUT" '"decision"' "t_stop_r2_background_tasks_allow_with_a_note does-not-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# --- R3: nothing changed this turn ----------------------------------------
t_stop_r3_dirty_but_unchanged_turn_is_silent() {
	# The repo is dirty from before the turn AND on a flow/* branch with no
	# approved plan — a read-only turn must still end in silence (B6/FU-04).
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r3-$$"
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	touch "${TMPDIR:-/tmp}/claude-turn-$sid"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r3_dirty_but_unchanged_turn_is_silent rc"
	assert_eq "$OUT" "" "t_stop_r3_dirty_but_unchanged_turn_is_silent silent"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r3_pruned_and_ignored_paths_are_not_changes() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r3p-$$"
	git -C "$repo" checkout -qb flow/x
	printf 'scratch.ts\n' >"$repo/.gitignore"
	git -C "$repo" add .gitignore >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ig >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	mkdir -p "$repo/.next" "$repo/node_modules/p"
	printf 'x\n' >"$repo/.next/trace"
	printf 'x\n' >"$repo/node_modules/p/index.js"
	printf 'export const s = 1;\n' >"$repo/scratch.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r3_pruned_and_ignored_paths_are_not_changes rc"
	assert_eq "$OUT" "" "t_stop_r3_pruned_and_ignored_paths_are_not_changes silent"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r3_worktree_git_file_is_not_a_change() {
	# A linked worktree's .git is a FILE, and touching it must not open a gate
	# (B8): find prunes it by name, file or directory.
	local repo parent wt sid
	repo=$(tmp_repo)
	parent=$(tmp_dir)
	wt="$parent/wt"
	sid="stop-r3w-$$"
	git -C "$repo" worktree add -q "$wt" >/dev/null 2>&1
	_stop_stamp "$sid" "$wt"
	touch -t 202001010000 "$repo/.git/info/exclude" 2>/dev/null || true
	touch "$wt/.git"
	_stop_run "$sid" "$wt"
	assert_rc 0 "t_stop_r3_worktree_git_file_is_not_a_change rc"
	assert_eq "$OUT" "" "t_stop_r3_worktree_git_file_is_not_a_change silent"
	_stop_forget "$sid"
	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1
	rm -rf "$repo" "$parent"
}

# --- R4: docs and config only ---------------------------------------------
# --- R4: docs and config only ---------------------------------------------
# K-E(6): flow-lint is paid for only when the ACTIVE TASKS.md is in this turn's
# change set. A broken TASKS.md left behind by another turn is not linted, and a
# README edit ends the turn in silence.
t_stop_r4_docs_only_turn_does_not_lint_a_stale_tasks_file() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r4-$$"
	_stop_tasks "$repo" "- [ ] T002 no verify here — files: src/b.ts"
	_stop_stamp "$sid" "$repo"
	touch -t 202001010000 "$repo/.specs/001-x/TASKS.md" "$repo/.specs/.current"
	printf 'more docs\n' >>"$repo/README.md"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r4_docs_only_turn_does_not_lint_a_stale_tasks_file rc"
	assert_eq "$OUT" "" "t_stop_r4_docs_only_turn_does_not_lint_a_stale_tasks_file silent"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r4_active_tasks_file_in_delta_is_linted() {
	local repo sid repro
	repo=$(tmp_repo)
	sid="stop-r4p-$$"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$repo" "- [ ] T002 no verify here — files: src/b.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r4_active_tasks_file_in_delta_is_linted rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r4_active_tasks_file_in_delta_is_linted blocks"
	assert_contains "$OUT" "flow-lint" "t_stop_r4_active_tasks_file_in_delta_is_linted names-flow-lint"
	assert_contains "$OUT" "To reproduce:" "t_stop_r4_active_tasks_file_in_delta_is_linted reproduce-line"
	assert_contains "$OUT" "CC_NO_STOP_GATE=1" "t_stop_r4_active_tasks_file_in_delta_is_linted names-its-escape-hatch"
	# The reproduce line has to be runnable AS PRINTED: flow-lint ships in the
	# plugin's scripts/ dir and is on no PATH, so a bare `flow-lint <file>`
	# would exit 127 instead of reproducing the failure it claims to.
	repro=$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null | grep '^To reproduce: ')
	run_cmd bash -c "${repro#To reproduce: }"
	assert_rc 1 "t_stop_r4_active_tasks_file_in_delta_is_linted reproduce-command-reproduces-the-failure"
	assert_contains "$OUT" "T002 has no verify:" "t_stop_r4_active_tasks_file_in_delta_is_linted reproduce-command-prints-the-same-complaints"
	# The hatches this block names are RUN, not grepped: the round-1 version of
	# this test asserted the string "CC_NO_SPEC_GATE=1" while that variable
	# escaped nothing here, so the block told the reader a falsehood it passed.
	_stop_run "$sid" "$repo" CC_NO_STOP_GATE=1
	assert_rc 0 "t_stop_r4_active_tasks_file_in_delta_is_linted env-hatch-rc"
	assert_not_contains "$OUT" '"decision"' "t_stop_r4_active_tasks_file_in_delta_is_linted env-hatch-really-escapes"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": false}\n' >"$repo/.claude/flow.config.json"
	touch -t 202001010000 "$repo/.claude/flow.config.json"
	_stop_run "$sid" "$repo"
	assert_not_contains "$OUT" '"decision"' "t_stop_r4_active_tasks_file_in_delta_is_linted config-hatch-really-escapes"
	assert_not_contains "$OUT" "CC_NO_SPEC_GATE" "t_stop_r4_active_tasks_file_in_delta_is_linted claims-no-hatch-it-lacks"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r4_dot_current_is_the_active_feature() {
	# K-E(3)/(5): `.specs/.current` names the ACTIVE feature. The pointed-at
	# TASKS.md is linted; a second, broken feature on disk is not.
	local repo sid base
	repo=$(tmp_repo)
	sid="stop-r4j-$$"
	base=$(git -C "$repo" rev-parse --short HEAD)
	mkdir -p "$repo/.specs/002-y"
	{
		printf '# Tasks — Y\n'
		printf 'Spec: spec.md · Design: none · Base: %s · Route: oneshot · Test: `true`\n\n' "$base"
		printf '## Phase 1 — Y\nGoal: y.\nIndependent test: `true`\n'
		printf -- '- [ ] T009 broken, no verify — files: src/y.ts\n'
	} >"$repo/.specs/002-y/TASKS.md"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$repo" "- [ ] T002 also no verify — files: src/b.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r4_dot_current_is_the_active_feature rc"
	assert_contains "$OUT" "flow-lint (.specs/001-x/TASKS.md)" "t_stop_r4_dot_current_is_the_active_feature lints-the-pointed-at-feature"
	assert_not_contains "$OUT" "T009" "t_stop_r4_dot_current_is_the_active_feature ignores-the-other-feature"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# R7 (docs/research/16 stealth): .specs is a symlink to a private STORE repo.
# Plain `find` does not follow that symlink, so hook_changed_since used to
# never see a write inside it — R4's "only lint the file THIS turn touched"
# gate (_tasks_changed) stayed 0 and a lint ERROR written in the store never
# blocked the turn. (K-E(1)'s sha-less-tick check reads the active TASKS.md
# unconditionally, not gated on _tasks_changed, so it is not a fair test of
# this walk — R4 is.)
t_stop_r4_stealth_store_tasks_file_in_delta_is_linted() {
	local repo store sid
	repo=$(tmp_repo)
	store=$(tmp_repo)
	sid="stop-r4-stealth-$$"
	rm -rf "$repo/.specs"
	mkdir -p "$store/.specs"
	ln -s "$store/.specs" "$repo/.specs"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$store" "- [ ] T002 no verify here — files: src/b.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r4_stealth_store_tasks_file_in_delta_is_linted rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r4_stealth_store_tasks_file_in_delta_is_linted blocks"
	assert_contains "$OUT" "flow-lint" "t_stop_r4_stealth_store_tasks_file_in_delta_is_linted names-flow-lint"
	assert_contains "$OUT" "T002 has no verify" "t_stop_r4_stealth_store_tasks_file_in_delta_is_linted names-the-error"
	_stop_forget "$sid"
	rm -rf "$repo" "$store"
}

# --- K-E(1): a sha-less [x] is not a tick ---------------------------------
t_stop_ke_sha_less_tick_blocks_the_turn() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-ke1-$$"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$repo" "- [x] T002 claimed done — files: src/b.ts — verify: \`true\`"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_ke_sha_less_tick_blocks_the_turn rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_ke_sha_less_tick_blocks_the_turn blocks"
	assert_contains "$OUT" "T002 as [x] with no" "t_stop_ke_sha_less_tick_blocks_the_turn names-the-id"
	assert_contains "$OUT" "fix: run flow tick T002" "t_stop_ke_sha_less_tick_blocks_the_turn names-the-fix"
	# It really is escapable the way it says it is.
	_stop_run "$sid" "$repo" CC_NO_STOP_GATE=1
	assert_not_contains "$OUT" '"decision"' "t_stop_ke_sha_less_tick_blocks_the_turn env-hatch-really-escapes"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_ke_tick_with_a_sha_does_not_block() {
	local repo sid base sha
	repo=$(tmp_repo)
	sid="stop-ke2-$$"
	base=$(git -C "$repo" rev-parse --short HEAD)
	mkdir -p "$repo/src"
	printf 'export const b = 1;\n' >"$repo/src/b.ts"
	git -C "$repo" add src/b.ts >/dev/null 2>&1
	git -C "$repo" commit -q -m "b" >/dev/null 2>&1
	sha=$(git -C "$repo" rev-parse --short HEAD)
	_stop_stamp "$sid" "$repo"
	mkdir -p "$repo/.specs/001-x"
	cat >"$repo/.specs/001-x/TASKS.md" <<EOF
# Tasks — X
Spec: spec.md · Design: none · Base: $base · Route: oneshot · Test: \`true\`
Approved: 2026-01-01 by user

## Phase 1 — Thing
Goal: the thing works.
Independent test: \`true\`
- [x] T001 really done — files: src/b.ts — verify: \`true\` — done: $sha
EOF
	printf '001-x\n' >"$repo/.specs/.current"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_ke_tick_with_a_sha_does_not_block rc"
	assert_not_contains "$OUT" '"decision"' "t_stop_ke_tick_with_a_sha_does_not_block no-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# A fenced grammar example inside TASKS.md is an example, never a predicate:
# the template that teaches the line format must not block every turn.
t_stop_ke_sha_less_tick_inside_a_fence_is_not_a_tick() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-ke3-$$"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$repo"
	{
		printf '\n```\n'
		printf -- '- [x] T099 an example of the grammar — files: x — verify: `true`\n'
		printf '```\n'
	} >>"$repo/.specs/001-x/TASKS.md"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_ke_sha_less_tick_inside_a_fence_is_not_a_tick rc"
	assert_not_contains "$OUT" "T099" "t_stop_ke_sha_less_tick_inside_a_fence_is_not_a_tick no-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# flow off is still the master switch: the K-E rows are judging hooks too.
t_stop_ke_flow_off_silences_the_sha_less_tick() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-ke4-$$"
	mkdir -p "$repo/.claude"
	: >"$repo/.claude/flow.off"
	_stop_stamp "$sid" "$repo"
	_stop_tasks "$repo" "- [x] T002 claimed done — files: src/b.ts — verify: \`true\`"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_ke_flow_off_silences_the_sha_less_tick rc"
	assert_eq "$OUT" "" "t_stop_ke_flow_off_silences_the_sha_less_tick silent"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# --- R5: no ecosystem ------------------------------------------------------
t_stop_r5_no_ecosystem_notes_once_per_session() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r5-$$"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r5_no_ecosystem_notes_once_per_session rc"
	assert_contains "$OUT" "no test/lint ecosystem here" "t_stop_r5_no_ecosystem_notes_once_per_session notes"
	assert_not_contains "$OUT" '"decision"' "t_stop_r5_no_ecosystem_notes_once_per_session does-not-block"
	_stop_run "$sid" "$repo"
	assert_eq "$OUT" "" "t_stop_r5_no_ecosystem_notes_once_per_session second-turn-silent"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# --- R7: a gate that could not run is never a pass ------------------------
t_stop_r7_missing_gate_scripts_note() {
	local repo sid empty
	repo=$(tmp_repo)
	empty=$(tmp_dir)
	sid="stop-r7-$$"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$empty"
	assert_rc 0 "t_stop_r7_missing_gate_scripts_note rc"
	assert_contains "$OUT" "gate could not run" "t_stop_r7_missing_gate_scripts_note says-so"
	assert_contains "$OUT" "Fix:" "t_stop_r7_missing_gate_scripts_note names-a-fix"
	_stop_forget "$sid"
	rm -rf "$repo" "$empty"
}

t_stop_r7_crashed_check_all_notes_and_allows() {
	# check-all exits non-zero with nothing on stdout: unparseable is not
	# "all gates passed" (D2/D3).
	local repo sid shared
	repo=$(tmp_repo)
	shared=$(tmp_dir)
	sid="stop-r7c-$$"
	printf '#!/usr/bin/env node\nprocess.exit(2);\n' >"$shared/check-all"
	chmod +x "$shared/check-all"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_stop_r7_crashed_check_all_notes_and_allows rc"
	assert_contains "$OUT" "gate could not run" "t_stop_r7_crashed_check_all_notes_and_allows says-so"
	assert_contains "$OUT" "no parseable JSON" "t_stop_r7_crashed_check_all_notes_and_allows names-the-symptom"
	assert_not_contains "$OUT" '"decision"' "t_stop_r7_crashed_check_all_notes_and_allows does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo" "$shared"
}

# --- R8-R10: the scoped run ------------------------------------------------
t_stop_r8_scoped_green_is_silent_and_skips_a_sweep_not_due() {
	# The scoped run is green and the last sweep was at this HEAD, so the red
	# lint gate is never reached: a sweep costs one per commit, not per turn.
	local repo sid stamp
	repo=$(tmp_repo)
	sid="stop-r8-$$"
	printf '{"name":"x","scripts":{"test":"exit 0","lint":"exit 1"}}\n' >"$repo/package.json"
	printf 'test("x", () => {});\n' >"$repo/app.test.js"
	git -C "$repo" add package.json app.test.js >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm node >/dev/null 2>&1
	stamp=$(_stop_state_path "$repo" gates)
	git -C "$repo" rev-parse HEAD >"$stamp"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r8_scoped_green_is_silent_and_skips_a_sweep_not_due rc"
	assert_eq "$OUT" "" "t_stop_r8_scoped_green_is_silent_and_skips_a_sweep_not_due silent"
	_stop_forget "$sid"
	rm -f "$stamp" "$(_stop_state_path "$repo" baseline)"
	rm -rf "$repo"
}

t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r10-$$"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch blocks"
	assert_contains "$OUT" "test-changed (npm run test" "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch names-the-gate"
	assert_contains "$OUT" "To reproduce: cd " "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch reproduce-line"
	assert_contains "$OUT" "Do not delete, skip, xfail, or weaken a test" "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch no-weakening-sentence"
	assert_contains "$OUT" "CC_NO_STOP_GATE=1" "t_stop_r10_scoped_red_blocks_with_reproduce_and_hatch names-its-escape-hatch"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

t_stop_scoped_run_uses_the_turns_change_set() {
	# C-C: the turn's files go to test-changed in CC_CHANGED_FILES. Here the
	# tree is committed and clean, so `git diff` finds nothing — only the turn
	# stamp knows app.test.js was touched, and the run must still happen.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-ccf-$$"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	touch "$repo/app.test.js"
	assert_eq "$(git -C "$repo" status --porcelain)" "" "t_stop_scoped_run_uses_the_turns_change_set fixture-is-clean"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" "test-changed (npm run test" "t_stop_scoped_run_uses_the_turns_change_set ran-the-scoped-suite"
	assert_contains "$OUT" "app.test.js" "t_stop_scoped_run_uses_the_turns_change_set scoped-to-the-touched-file"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- R9/R12: the baseline --------------------------------------------------
t_stop_r9_failure_already_in_the_baseline_releases() {
	# The baseline is only allowed to say "already failing before this turn"
	# about a red it can PROVE this turn did not cause: one that was red at
	# the end of an earlier turn which touched none of this turn's files.
	# Turn 1 changes src/a.ts and blocks; turn 2 changes only src/b.ts (a.ts
	# backdated behind the stamp, so it is out of Δ) and the identical red is
	# released with a note. Turn 3 repeats turn 2: once proven pre-existing at
	# this HEAD, it stays proven.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r9-$$"
	mkdir -p "$repo/.claude" "$repo/src"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	rm -f "$(_stop_state_path "$repo" baseline)"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r9_failure_already_in_the_baseline_releases first-red-blocks"
	# Turn 2: everything turn 1 touched goes behind the stamp, so Δ is exactly
	# src/b.ts and shares no file with the change set the red was recorded with.
	touch -t 202001010000 "$repo/src/a.ts" "$repo/package.json" \
		"$repo/app.test.js" "$repo/README.md" "$repo/.claude/flow.config.json"
	printf 'export const b = 1;\n' >"$repo/src/b.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r9_failure_already_in_the_baseline_releases second-rc"
	assert_contains "$OUT" "already failing before this turn" "t_stop_r9_failure_already_in_the_baseline_releases second-notes"
	assert_contains "$OUT" "touched none of the files you changed this turn" "t_stop_r9_failure_already_in_the_baseline_releases second-states-the-proof"
	assert_not_contains "$OUT" '"decision"' "t_stop_r9_failure_already_in_the_baseline_releases second-does-not-block"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" "already failing before this turn" "t_stop_r9_failure_already_in_the_baseline_releases third-stays-known"
	assert_not_contains "$OUT" '"decision"' "t_stop_r9_failure_already_in_the_baseline_releases third-does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

t_stop_r9_red_this_turn_caused_is_never_called_a_baseline() {
	# The fatal case the baseline must not swallow: the turn that BREAKS the
	# suite is not allowed to record its own breakage as "pre-existing" and
	# walk out on the next Stop. The same change set is on the table every
	# time, so the red climbs the ladder — block, block, soft, release —
	# instead of being excused after one block.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r9n-$$"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	rm -f "$(_stop_state_path "$repo" baseline)"
	printf 'test("x", () => {});\n// broken this turn\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline first-blocks"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline second-blocks"
	assert_not_contains "$OUT" "already failing before this turn" "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline second-claims-nothing"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"additionalContext"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline third-is-soft"
	assert_not_contains "$OUT" '"decision"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline third-does-not-block"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" "Nothing was verified" "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline fourth-releases"
	assert_not_contains "$OUT" '"decision"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline fourth-has-no-decision"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline fifth-rc"
	assert_not_contains "$OUT" '"decision"' "t_stop_r9_red_this_turn_caused_is_never_called_a_baseline fifth-has-no-decision"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- R11: the sweep cadence is commits, not the clock ---------------------
t_stop_r11_sweep_runs_after_a_commit_and_records_the_sha() {
	local repo sid stamp
	repo=$(tmp_repo)
	sid="stop-r11-$$"
	printf '{"name":"x","scripts":{"test":"exit 0","lint":"exit 1"}}\n' >"$repo/package.json"
	printf 'test("x", () => {});\n' >"$repo/app.test.js"
	git -C "$repo" add package.json app.test.js >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm node >/dev/null 2>&1
	stamp=$(_stop_state_path "$repo" gates)
	git -C "$repo" rev-parse HEAD~1 >"$stamp"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r11_sweep_runs_after_a_commit_and_records_the_sha rc"
	assert_contains "$OUT" "Gate(s) failed: lint" "t_stop_r11_sweep_runs_after_a_commit_and_records_the_sha swept"
	assert_eq "$(cat "$stamp")" "$(git -C "$repo" rev-parse HEAD)" "t_stop_r11_sweep_runs_after_a_commit_and_records_the_sha stamp-holds-head"
	_stop_forget "$sid"
	rm -f "$stamp" "$(_stop_state_path "$repo" baseline)"
	rm -rf "$repo"
}

# --- R14/R15: the ladder ---------------------------------------------------
t_stop_r14_third_identical_block_is_soft_and_fifth_releases() {
	local repo sid i
	repo=$(tmp_repo)
	sid="stop-r14-$$"
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	i=1
	while [ "$i" -le 2 ]; do
		_stop_run "$sid" "$repo"
		assert_contains "$OUT" '"decision":"block"' "t_stop_r14_third_identical_block_is_soft_and_fifth_releases block-$i"
		i=$((i + 1))
	done
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r14_third_identical_block_is_soft_and_fifth_releases third-rc"
	assert_contains "$OUT" '"additionalContext"' "t_stop_r14_third_identical_block_is_soft_and_fifth_releases third-is-soft"
	assert_contains "$OUT" "This is the 3rd identical block" "t_stop_r14_third_identical_block_is_soft_and_fifth_releases third-says-so"
	assert_not_contains "$OUT" '"decision"' "t_stop_r14_third_identical_block_is_soft_and_fifth_releases third-does-not-block"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"systemMessage"' "t_stop_r14_third_identical_block_is_soft_and_fifth_releases fourth-releases"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r14_third_identical_block_is_soft_and_fifth_releases fifth-rc"
	assert_contains "$OUT" "Nothing was verified" "t_stop_r14_third_identical_block_is_soft_and_fifth_releases fifth-states-nothing-verified"
	assert_not_contains "$OUT" '"decision"' "t_stop_r14_third_identical_block_is_soft_and_fifth_releases fifth-has-no-decision"
	_stop_forget "$sid"
	rm -rf "$repo"
}

t_stop_r14_a_different_failure_never_inherits_another_reds_count() {
	# R14 counts "a BLOCK whose signature already blocked twice". The signature
	# has to identify the FAILURE, not the gate that reported it: with a
	# per-gate counter, two blocks over t1.test.js made the very first block
	# over t2.test.js soft, and the third distinct regression walked out
	# entirely — the gate failing open exactly when a new thing broke.
	local repo sid i
	repo=$(tmp_repo)
	sid="stop-r14d-$$"
	printf '{"name":"x","scripts":{"test":"exit 1"}}\n' >"$repo/package.json"
	i=1
	while [ "$i" -le 10 ]; do
		printf 'test("x", () => {});\n' >"$repo/t$i.test.js"
		i=$((i + 1))
	done
	git -C "$repo" add -A >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ten >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	rm -f "$(_stop_state_path "$repo" baseline)"
	# Δ is find-newer over the stamp, so everything the fixture wrote goes
	# behind it and each turn below touches exactly one test file.
	touch -t 202001010000 "$repo"/*.test.js "$repo/package.json" "$repo/README.md"
	i=1
	while [ "$i" -le 2 ]; do
		touch "$repo/t1.test.js"
		_stop_run "$sid" "$repo"
		assert_contains "$OUT" '"decision":"block"' "t_stop_r14_a_different_failure_never_inherits_another_reds_count t1-block-$i"
		assert_contains "$OUT" "t1.test.js" "t_stop_r14_a_different_failure_never_inherits_another_reds_count t1-named-$i"
		i=$((i + 1))
	done
	touch -t 202001010000 "$repo/t1.test.js"
	touch "$repo/t2.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r14_a_different_failure_never_inherits_another_reds_count t2-rc"
	assert_contains "$OUT" "t2.test.js" "t_stop_r14_a_different_failure_never_inherits_another_reds_count t2-named"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r14_a_different_failure_never_inherits_another_reds_count t2-first-block-is-a-block"
	assert_not_contains "$OUT" '"additionalContext"' "t_stop_r14_a_different_failure_never_inherits_another_reds_count t2-not-soft"
	assert_not_contains "$OUT" "3rd identical block" "t_stop_r14_a_different_failure_never_inherits_another_reds_count t2-not-called-identical"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- block reasons stay under the platform's output cap -------------------
t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines() {
	# The no-weakening sentence and the reproduce command are printed LAST, so
	# an unclipped gate (60 lines of 900 characters here) pushes exactly the
	# two load-bearing lines past the platform's ~10k hook-output cap. Lines
	# AND characters are bounded; both fixed lines survive.
	local repo sid reason
	repo=$(tmp_repo)
	sid="stop-clip-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGate": true}\n' >"$repo/.claude/flow.config.json"
	printf '{"name":"x","scripts":{"test":"node long.js"}}\n' >"$repo/package.json"
	cat >"$repo/long.js" <<'LONGEOF'
for (let i = 0; i < 60; i++) console.log("x".repeat(900));
process.exit(1);
LONGEOF
	printf 'test("x", () => {});\n' >"$repo/app.test.js"
	git -C "$repo" add -A >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm long >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines rc"
	assert_contains "$OUT" '"decision":"block"' "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines blocks"
	reason=$(printf '%s' "$OUT" | jq -r '.reason' 2>/dev/null)
	if [ "${#reason}" -lt 10000 ]; then
		_pass "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines under-the-cap"
	else
		_fail "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines under-the-cap" "reason is ${#reason} chars"
	fi
	assert_contains "$reason" "Do not delete, skip, xfail, or weaken a test" "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines keeps-the-fixed-sentence"
	assert_contains "$reason" "To reproduce: cd " "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines keeps-the-reproduce-line"
	assert_contains "$reason" "clipped here to 25 lines" "t_stop_r13_long_gate_output_is_clipped_and_keeps_the_fixed_lines says-it-clipped"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- R16: the budget -------------------------------------------------------
t_stop_r16_over_budget_releases_and_says_nothing_was_verified() {
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r16-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGateBudgetSec": 0}\n' >"$repo/.claude/flow.config.json"
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r16_over_budget_releases_and_says_nothing_was_verified rc"
	assert_contains "$OUT" "exceeded its 0s budget" "t_stop_r16_over_budget_releases_and_says_nothing_was_verified names-the-budget"
	assert_contains "$OUT" "NOT verified" "t_stop_r16_over_budget_releases_and_says_nothing_was_verified says-nothing-verified"
	assert_not_contains "$OUT" '"decision"' "t_stop_r16_over_budget_releases_and_says_nothing_was_verified does-not-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# --- the project dir may be a symlink (B17) -------------------------------
t_stop_symlinked_project_dir_still_sees_the_change() {
	local repo link sid
	repo=$(tmp_repo)
	link="$(tmp_dir)/link"
	sid="stop-sym-$$"
	ln -s "$repo" "$link"
	git -C "$repo" checkout -qb flow/x
	mkdir -p "$repo/src"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/src/a.ts"
	_stop_run "$sid" "$link"
	assert_rc 0 "t_stop_symlinked_project_dir_still_sees_the_change rc"
	assert_contains "$OUT" "src/a.ts changed this turn" "t_stop_symlinked_project_dir_still_sees_the_change relative-to-the-real-dir"
	_stop_forget "$sid"
	rm -rf "$repo" "$link"
}

# --- R7: half a toolchain is still a turn nothing verified ----------------
t_stop_r7_missing_check_all_with_test_changed_present_notes() {
	# Only check-all is gone. The scoped run resolves no suite here, so the
	# fall-through lands on a sweep that cannot happen — and a source-changing
	# turn must never end silently on that path.
	local repo sid shared
	repo=$(tmp_repo)
	shared=$(tmp_dir)
	sid="stop-r7half-$$"
	cp "$(_stop_shared)/test-changed" "$shared/test-changed"
	chmod +x "$shared/test-changed"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$shared"
	assert_rc 0 "t_stop_r7_missing_check_all_with_test_changed_present_notes rc"
	assert_contains "$OUT" "gate could not run" "t_stop_r7_missing_check_all_with_test_changed_present_notes says-so"
	assert_contains "$OUT" "check-all is not in $shared" "t_stop_r7_missing_check_all_with_test_changed_present_notes names-check-all"
	assert_not_contains "$OUT" '"decision"' "t_stop_r7_missing_check_all_with_test_changed_present_notes does-not-block"
	_stop_forget "$sid"
	rm -rf "$repo" "$shared"
}

t_stop_r7_missing_tool_note_is_not_once_per_session() {
	# R5 ("this repo has no gates") is a standing property and is said once.
	# A missing TOOL leaves every turn unverified, so it is said every turn:
	# silence from the second Stop on would be a whole session judged by
	# nothing, without a word about it.
	local repo sid empty
	repo=$(tmp_repo)
	empty=$(tmp_dir)
	sid="stop-r7rep-$$"
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$empty"
	assert_contains "$OUT" "gate could not run" "t_stop_r7_missing_tool_note_is_not_once_per_session first-turn"
	run_hook "$SCAN_DIR/stop-gate.sh" "{\"session_id\":\"$sid\"}" \
		CLAUDE_PROJECT_DIR="$repo" CC_SHARED_SCRIPTS="$empty"
	assert_rc 0 "t_stop_r7_missing_tool_note_is_not_once_per_session second-rc"
	assert_contains "$OUT" "gate could not run" "t_stop_r7_missing_tool_note_is_not_once_per_session second-turn-also-says-so"
	_stop_forget "$sid"
	rm -rf "$repo" "$empty"
}

# --- R5: a manifest with nothing runnable in it ---------------------------
t_stop_r5_manifest_with_every_gate_skipped_notes() {
	# package.json with only a `build` script: check-all finds an ecosystem
	# but runs nothing, so "pass" would be a lie about a turn in which no gate
	# executed.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r5skip-$$"
	printf '{"name":"x","scripts":{"build":"exit 0"}}\n' >"$repo/package.json"
	git -C "$repo" add package.json >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm build >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	printf 'export const a = 1;\n' >"$repo/a.ts"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r5_manifest_with_every_gate_skipped_notes rc"
	assert_contains "$OUT" "no gate ran here" "t_stop_r5_manifest_with_every_gate_skipped_notes says-so"
	assert_contains "$OUT" "nothing verified it" "t_stop_r5_manifest_with_every_gate_skipped_notes says-nothing-verified"
	assert_not_contains "$OUT" '"decision"' "t_stop_r5_manifest_with_every_gate_skipped_notes does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- R6: a deletion this turn cannot be dated is not this turn's ----------
t_stop_r6_manifest_deleted_before_the_turn_is_not_this_turns_doing() {
	# git status shows a deleted package.json whenever it happened. Here it
	# happened before the turn started (the project root is older than the
	# stamp) and the turn changed nothing, so this read-only Stop is silent —
	# and nothing claims a deletion "this turn" that the hook cannot date.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r6old-$$"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$repo/package.json"
	git -C "$repo" add package.json >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm pkg >/dev/null 2>&1
	git -C "$repo" rm -q package.json >/dev/null 2>&1
	touch -t 202001010000 "$repo/README.md"
	touch -t 202001010000 "$repo"
	_stop_stamp "$sid" "$repo"
	touch -t 202001010000 "$repo"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r6_manifest_deleted_before_the_turn_is_not_this_turns_doing rc"
	assert_not_contains "$OUT" "this turn" "t_stop_r6_manifest_deleted_before_the_turn_is_not_this_turns_doing claims-nothing-about-the-turn"
	assert_not_contains "$OUT" '"decision"' "t_stop_r6_manifest_deleted_before_the_turn_is_not_this_turns_doing does-not-block"
	_stop_forget "$sid"
	rm -rf "$repo"
}

# --- every printed command must be runnable as printed --------------------
t_stop_reproduce_line_quotes_a_project_dir_with_a_space() {
	local parent repo sid
	parent=$(tmp_dir)
	repo="$parent/pr obe dir"
	sid="stop-space-$$"
	mkdir -p "$repo"
	(
		cd "$repo" || exit 1
		git init -q
		git config user.email t@t
		git config user.name t
		git config commit.gpgsign false
	) >/dev/null 2>&1
	_stop_node_repo "$repo" "exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_contains "$OUT" '"decision":"block"' "t_stop_reproduce_line_quotes_a_project_dir_with_a_space blocks"
	assert_contains "$OUT" "To reproduce: cd '$repo'" "t_stop_reproduce_line_quotes_a_project_dir_with_a_space quotes-the-path"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$parent"
}

# --- R16: the budget bounds the turn, not just the phase count ------------
t_stop_r16_budget_passed_during_the_run_releases_the_red() {
	# The budget was still intact when the scoped run started and gone by the
	# time it came back red. The knob is named for wall clock, so the turn is
	# released with the overrun named rather than blocked after the fact.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r16b-$$"
	mkdir -p "$repo/.claude"
	printf '{"stopGateBudgetSec": 2}\n' >"$repo/.claude/flow.config.json"
	_stop_node_repo "$repo" "sleep 3; exit 1"
	_stop_stamp "$sid" "$repo"
	printf 'test("x", () => {});\n// touched\n' >"$repo/app.test.js"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r16_budget_passed_during_the_run_releases_the_red rc"
	assert_contains "$OUT" "exceeded its 2s budget" "t_stop_r16_budget_passed_during_the_run_releases_the_red names-the-budget"
	assert_contains "$OUT" "overran it" "t_stop_r16_budget_passed_during_the_run_releases_the_red says-the-run-overran"
	assert_not_contains "$OUT" '"decision"' "t_stop_r16_budget_passed_during_the_run_releases_the_red does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" baseline)" "$(_stop_state_path "$repo" gates)"
	rm -rf "$repo"
}

# --- R6: the index is not the working tree --------------------------------
# `git status` reporting a deleted manifest is not proof the manifest is gone,
# and R6's whole claim is that it IS gone. Both rows below leave package.json
# on disk, so nothing was removed and there is no gate to dodge.
t_stop_r6_manifest_renamed_away_and_recreated_is_not_gone() {
	# A manifest migration: `git mv package.json package.json.bak` and write a
	# fresh one. Porcelain says `R  package.json -> package.json.bak`, the
	# manifest is right there, so a block would state a provable falsehood.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r6mv-$$"
	printf '{"name":"x"}\n' >"$repo/package.json"
	git -C "$repo" add package.json >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm pkg >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	git -C "$repo" mv package.json package.json.bak >/dev/null 2>&1
	printf '{"name":"x","private":true}\n' >"$repo/package.json"
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r6_manifest_renamed_away_and_recreated_is_not_gone rc"
	assert_not_contains "$OUT" "is gone from the working tree" "t_stop_r6_manifest_renamed_away_and_recreated_is_not_gone claims-nothing-false"
	assert_not_contains "$OUT" '"decision"' "t_stop_r6_manifest_renamed_away_and_recreated_is_not_gone does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" gates)" "$(_stop_state_path "$repo" baseline)"
	rm -rf "$repo"
}

t_stop_r6_manifest_removed_from_the_index_only_is_not_gone() {
	# `git rm --cached package.json`: porcelain shows `D  package.json` plus an
	# untracked `?? package.json` for the same file, which is still on disk.
	local repo sid
	repo=$(tmp_repo)
	sid="stop-r6rc-$$"
	printf '{"name":"x"}\n' >"$repo/package.json"
	git -C "$repo" add package.json >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm pkg >/dev/null 2>&1
	_stop_stamp "$sid" "$repo"
	git -C "$repo" rm -q --cached package.json >/dev/null 2>&1
	_stop_run "$sid" "$repo"
	assert_rc 0 "t_stop_r6_manifest_removed_from_the_index_only_is_not_gone rc"
	assert_not_contains "$OUT" "is gone from the working tree" "t_stop_r6_manifest_removed_from_the_index_only_is_not_gone claims-nothing-false"
	assert_not_contains "$OUT" '"decision"' "t_stop_r6_manifest_removed_from_the_index_only_is_not_gone does-not-block"
	_stop_forget "$sid"
	rm -f "$(_stop_state_path "$repo" gates)" "$(_stop_state_path "$repo" baseline)"
	rm -rf "$repo"
}
