#!/usr/bin/env bash
# test_flow_rules.sh — flow-rules.sh, spec 005 slice L1 (D-4 rule format, D-5 engine).
#
# Every case builds its own project under a temp dir and its own HOME, so the
# developer's real ~/.claude/flow.rules is never read and never written: these
# tests bump `hits:` in the files they fire, which is why fixtures are copied
# in and never used in place.

# _fr_install <dir> <fixture> [dest-name] — copy a fixture into <dir>'s rule store.
_fr_install() {
	local dest=${3:-$2}
	mkdir -p "$1/.claude/flow.rules"
	cp "$HERE/fixtures/flow-rules/$2" "$1/.claude/flow.rules/$dest"
}

# _fr_clean <dir>... — temp projects plus the session scratch files hookout writes.
_fr_clean() {
	local sid=$1
	shift
	rm -f "${TMPDIR:-/tmp}/claude-once-$sid" "${TMPDIR:-/tmp}/claude-count-$sid"
	rm -rf "$@"
}

# _fr_lock <repo> <home> <should> <input> — the real writer: `flow lesson
# propose` drafts the rule and `flow lesson lock` writes it into <repo>'s
# store, so what the round-trip cases fire against is the file the CLI wrote,
# never a fixture that agrees with the reader by hand.
_fr_lock() {
	local repo=$1 home=$2 should=$3 input=$4 id
	mkdir -p "$home/tmp"
	run_cmd env HOME="$home" TMPDIR="$home/tmp" \
		bash -c 'cd "$1" || exit 9; shift; exec node "$@"' _ "$repo" "$SCAN_DIR/../bin/flow" \
		lesson propose --did "$should" --should "$should" --input "$input" --json
	id=$(printf '%s\n' "$OUT" | awk -F'"' '/"id"/ { print $4; exit }')
	run_cmd env HOME="$home" TMPDIR="$home/tmp" \
		bash -c 'cd "$1" || exit 9; shift; exec node "$@"' _ "$repo" "$SCAN_DIR/../bin/flow" \
		lesson lock "$id" --choice block
}

t_flow_rules_deny_on_bash_pattern() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	json='{"session_id":"fr-deny","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "deny: rc 0"
	assert_contains "$OUT" '"permissionDecision":"deny"' "deny: permissionDecision deny"
	assert_contains "$OUT" 'flow lesson undo no-force-push' "deny: reason names the undo"
	_fr_clean fr-deny "$repo" "$home"
}

t_flow_rules_deny_ignores_unmatched_command() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	json='{"session_id":"fr-nomatch","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "unmatched: rc 0"
	assert_eq "$OUT" "" "unmatched: silent"
	_fr_clean fr-nomatch "$repo" "$home"
}

t_flow_rules_warn_on_edit_path() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-edit-generated.md
	json=$(printf '{"session_id":"fr-warn","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$repo/src/generated/api.ts")
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 2 "warn: rc 2"
	assert_contains "$ERR" "edit the generator instead" "warn: body on stderr"
	assert_contains "$ERR" 'flow lesson undo no-edit-generated' "warn: stderr names the undo"
	_fr_clean fr-warn "$repo" "$home"
}

t_flow_rules_note_on_stop() {
	local repo home
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" stop-worklog.md
	run_hook "$SCAN_DIR/flow-rules.sh" \
		'{"session_id":"fr-stop","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "stop note: rc 0"
	assert_contains "$OUT" '"systemMessage"' "stop note: systemMessage"
	assert_contains "$OUT" "Remember the worklog" "stop note: body"
	_fr_clean fr-stop "$repo" "$home"
}

t_flow_rules_warn_on_stop_blocks() {
	local repo home
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" stop-blocker.md
	run_hook "$SCAN_DIR/flow-rules.sh" \
		'{"session_id":"fr-stopwarn","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "stop warn: rc 0"
	assert_contains "$OUT" '"decision":"block"' "stop warn: blocks"
	_fr_clean fr-stopwarn "$repo" "$home"
}

# D-5 step 5: deny has no channel outside PreToolUse, so it degrades to warn
# for the event it fired on — feedback on PostToolUse, a block on Stop.
t_flow_rules_deny_degrades_off_pretooluse() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" deny-post-edit.md
	json=$(printf '{"session_id":"fr-degrade","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$repo/vendor/lib.js")
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 2 "deny on PostToolUse: degrades to feedback (rc 2)"
	assert_contains "$ERR" "Vendored code is upstream" "deny on PostToolUse: body on stderr"
	assert_not_contains "$OUT" '"permissionDecision"' "deny on PostToolUse: no deny JSON"
	_fr_clean fr-degrade "$repo"
	repo=$(tmp_repo)
	_fr_install "$repo" deny-stop.md
	run_hook "$SCAN_DIR/flow-rules.sh" \
		'{"session_id":"fr-degrade2","hook_event_name":"Stop"}' CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "deny on Stop: rc 0"
	assert_contains "$OUT" '"decision":"block"' "deny on Stop: degrades to a block"
	_fr_clean fr-degrade2 "$repo" "$home"
}

t_flow_rules_disabled_rule_ignored() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" disabled-rule.md
	json='{"session_id":"fr-off1","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"rm -rf build"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "disabled: rc 0"
	assert_eq "$OUT" "" "disabled: no output"
	_fr_clean fr-off1 "$repo" "$home"
}

t_flow_rules_project_beats_global() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" precedence-project.md precedence.md
	_fr_install "$home" precedence-global.md precedence.md
	json='{"session_id":"fr-prec","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "precedence: rc 0"
	assert_contains "$OUT" "PROJECT rule fired" "precedence: project message wins"
	assert_not_contains "$OUT" "GLOBAL rule fired" "precedence: global message skipped"
	assert_eq "$(grep '^hits:' "$home/.claude/flow.rules/precedence.md")" "hits: 0" "precedence: global rule not charged a hit"
	_fr_clean fr-prec "$repo" "$home"
}

t_flow_rules_global_rule_fires_without_project_rule() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$home" precedence-global.md precedence.md
	json='{"session_id":"fr-glob","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"curl https://example.com"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_contains "$OUT" "GLOBAL rule fired" "global: fires with no project rule"
	_fr_clean fr-glob "$repo" "$home"
}

t_flow_rules_malformed_notes_and_allows() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" malformed-no-close.md
	json='{"session_id":"fr-bad","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls -la"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "malformed: rc 0"
	assert_contains "$OUT" '"systemMessage"' "malformed: systemMessage"
	assert_contains "$OUT" "malformed-no-close.md" "malformed: names the file"
	assert_not_contains "$OUT" '"permissionDecision":"deny"' "malformed: never denies"
	_fr_clean fr-bad "$repo" "$home"
}

# Fail open, but only for the broken file: malformed-no-close.md sorts before
# no-force-push.md, so the deny below proves a broken rule does not swallow the
# rules after it.
t_flow_rules_malformed_does_not_disarm_the_rest() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" malformed-no-close.md
	_fr_install "$repo" no-force-push.md
	json='{"session_id":"fr-bad2","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_contains "$OUT" '"permissionDecision":"deny"' "malformed neighbour: the sound rule still denies"
	_fr_clean fr-bad2 "$repo" "$home"
}

t_flow_rules_hits_increment() {
	local repo home json log
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	json='{"session_id":"fr-hits","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_contains "$OUT" '"permissionDecision":"deny"' "hits: rule fired"
	assert_eq "$(grep '^hits:' "$repo/.claude/flow.rules/no-force-push.md")" "hits: 1" "hits: bumped to 1"
	assert_contains "$(cat "$repo/.claude/flow.rules/no-force-push.md")" "pattern: git[[:space:]]+push[^;&|]*--force" "hits: rest of the file survives the rewrite"
	log="$repo/.claude/flow.rules/.hits.log"
	assert_file_exists "$log" "hits: log written"
	assert_eq "$(wc -l <"$log" | tr -d ' ')" "1" "hits: one log line"
	assert_contains "$(cat "$log")" "no-force-push PreToolUse Bash" "hits: log names slug, event, tool"
	_fr_clean fr-hits "$repo" "$home"
}

t_flow_rules_flow_off_honoured() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	: >"$repo/.claude/flow.off"
	json='{"session_id":"fr-flowoff","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "flow.off: rc 0"
	assert_eq "$OUT" "" "flow.off: silent"
	assert_eq "$(grep '^hits:' "$repo/.claude/flow.rules/no-force-push.md")" "hits: 0" "flow.off: no hit recorded"
	_fr_clean fr-flowoff "$repo" "$home"
}

t_flow_rules_no_rules_is_silent_and_fast() {
	local repo home json t0 t1
	repo=$(tmp_repo)
	home=$(tmp_dir)
	json='{"session_id":"fr-none","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	t0=$(date +%s)
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	t1=$(date +%s)
	assert_rc 0 "no rules: rc 0"
	assert_eq "$OUT" "" "no rules: empty stdout"
	assert_eq "$ERR" "" "no rules: empty stderr"
	# 5 ms is not measurable from shell; a second-granularity ceiling still
	# catches the failure mode that matters — a jq/python spawn per event.
	if [ "$((t1 - t0))" -lt 2 ]; then
		_pass "no rules: returns immediately"
	else
		_fail "no rules: returns immediately" "took $((t1 - t0))s"
	fi
	_fr_clean fr-none "$repo" "$home"
}

t_flow_rules_wrong_event_and_tool_skipped() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	# Right pattern, wrong event: a PreToolUse rule must not fire on PostToolUse.
	json='{"session_id":"fr-ev","hook_event_name":"PostToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "wrong event: rc 0"
	assert_eq "$OUT" "" "wrong event: silent"
	# Right event, wrong tool.
	json='{"session_id":"fr-ev","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 0 "wrong tool: rc 0"
	assert_eq "$OUT" "" "wrong tool: silent"
	_fr_clean fr-ev "$repo" "$home"
}

t_flow_rules_ancestor_project_rules_are_read() {
	local repo home json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	mkdir -p "$repo/sub/deeper"
	_fr_install "$repo" no-force-push.md
	json='{"session_id":"fr-anc","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo/sub/deeper" HOME="$home"
	assert_contains "$OUT" '"permissionDecision":"deny"' "ancestor: rule above the cwd still fires"
	_fr_clean fr-anc "$repo" "$home"
}

# Bookkeeping must never speak over the message. The shell reports a failed
# redirection *open* on the stderr it had before the redirection list ran, so a
# `2>/dev/null` written after its target leaks a raw permission error into the
# very stderr hook_feedback uses as the correction channel.
t_flow_rules_readonly_store_keeps_the_correction_clean() {
	local repo home json rules
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-edit-generated.md
	rules="$repo/.claude/flow.rules"
	chmod 555 "$rules" # a read-only store: no .hits.log, no temp file
	json=$(printf '{"session_id":"fr-ro","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$repo/src/generated/api.ts")
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	chmod 755 "$rules"
	assert_rc 2 "read-only store: still corrects"
	assert_eq "$ERR" "That file is generated; edit the generator instead.
Undo: flow lesson undo no-edit-generated" "read-only store: stderr is the correction and nothing else"
	_fr_clean fr-ro "$repo" "$home"
}

# The same leak one level in: a rule file its owner cannot write hands its mode
# to the temp file through cp -p, and the awk redirection onto it then fails.
t_flow_rules_readonly_rule_file_keeps_the_correction_clean() {
	local repo home json rules
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-edit-generated.md
	rules="$repo/.claude/flow.rules"
	chmod 444 "$rules/no-edit-generated.md"
	json=$(printf '{"session_id":"fr-ro2","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$repo/src/generated/api.ts")
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	chmod 644 "$rules/no-edit-generated.md"
	assert_rc 2 "read-only rule file: still corrects"
	assert_eq "$ERR" "That file is generated; edit the generator instead.
Undo: flow lesson undo no-edit-generated" "read-only rule file: stderr is the correction and nothing else"
	assert_eq "$(find "$rules" -name '.flow-rules.*' | wc -l | tr -d ' ')" "0" "read-only rule file: no temp file left behind"
	_fr_clean fr-ro2 "$repo" "$home"
}

# Parallel tool calls in one turn hit the same rule at the same time, and `hits`
# is a read-modify-write: unlocked, N fires collapse to one.
t_flow_rules_concurrent_hits_are_all_counted() {
	local repo home json i n=8 rule
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-force-push.md
	rule="$repo/.claude/flow.rules/no-force-push.md"
	json='{"session_id":"fr-conc","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push --force origin main"}}'
	i=0
	while [ "$i" -lt "$n" ]; do
		printf '%s' "$json" | env CLAUDE_PROJECT_DIR="$repo" HOME="$home" \
			bash "$SCAN_DIR/flow-rules.sh" >/dev/null 2>&1 &
		i=$((i + 1))
	done
	wait
	assert_eq "$(grep '^hits:' "$rule")" "hits: $n" "concurrent: every fire counted"
	assert_eq "$(wc -l <"$repo/.claude/flow.rules/.hits.log" | tr -d ' ')" "$n" "concurrent: one log line per fire"
	assert_contains "$(cat "$rule")" "pattern: git[[:space:]]+push[^;&|]*--force" "concurrent: the rule survives the rewrites"
	_fr_clean fr-conc "$repo" "$home"
}

# A hook killed mid-write leaves .hits.lock behind with nobody to release it.
# The wait for a live holder is patient, so a lock whose owner is gone has to be
# broken rather than waited out: otherwise every later fire pays the whole
# budget and then loses its count anyway.
t_flow_rules_stale_lock_is_broken() {
	local repo home json lock dead
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_install "$repo" no-edit-generated.md
	lock="$repo/.claude/flow.rules/.hits.lock"
	mkdir -p "$lock"
	(exit 0) &
	dead=$!
	wait "$dead" 2>/dev/null
	printf '%s\n' "$dead" >"$lock/pid" # a pid that has already exited
	json=$(printf '{"session_id":"fr-stale","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$repo/src/generated/api.ts")
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_rc 2 "stale lock: still corrects"
	assert_file_missing "$lock" "stale lock: broken and released, not left to wedge the store"
	assert_eq "$(grep '^hits:' "$repo/.claude/flow.rules/no-edit-generated.md")" "hits: 1" "stale lock: the hit still lands"
	_fr_clean fr-stale "$repo" "$home"
}

# D-4: `pattern` is an ERE stored RAW — the writer never quotes it and the
# reader never dequotes it. An --input that is itself quoted drafts an ERE that
# begins and ends with a literal double quote, and if the reader shed that pair
# the rule enforced would be two characters shorter than the rule the user was
# shown and the rule on disk. End to end, through the real CLI: the original
# input is denied, and the same text WITHOUT its quotes is not.
t_flow_rules_quoted_pattern_survives_the_round_trip() {
	local repo home rule json
	repo=$(tmp_repo)
	home=$(tmp_dir)
	_fr_lock "$repo" "$home" "never send the build log to devnull" '"npm run build > /dev/null"'
	rule="$repo/.claude/flow.rules/never-send-the-build-log-to-devnull.md"
	assert_file_exists "$rule" "round trip: lock wrote the rule the CLI drafted"
	assert_eq "$(grep '^pattern: ' "$rule")" \
		'pattern: "npm[[:space:]]+run[[:space:]]+build[[:space:]]+>[[:space:]]+/dev/null"' \
		"round trip: the pattern is stored raw, both quotes included"
	json='{"session_id":"fr-rt","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\"npm run build > /dev/null\""}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_contains "$OUT" '"permissionDecision":"deny"' "round trip: the input that drafted the rule is denied"
	assert_contains "$OUT" 'flow lesson undo never-send-the-build-log-to-devnull' "round trip: the denial names its undo"
	json='{"session_id":"fr-rt","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm run build > /dev/null"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_eq "$OUT" "" "round trip: the stored quotes are enforced, not trimmed off the ends"

	# Same round trip with a regex metacharacter hard against the quote.
	_fr_lock "$repo" "$home" "never pipe env files to the clipboard" '"*.env | pbcopy"'
	rule="$repo/.claude/flow.rules/never-pipe-env-files-to-the-clipboard.md"
	assert_eq "$(grep '^pattern: ' "$rule")" \
		'pattern: "\*\.env[[:space:]]+\|[[:space:]]+pbcopy"' \
		"round trip: an escaped metacharacter beside a quote is stored as drafted"
	json='{"session_id":"fr-rt","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"\"*.env | pbcopy\""}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_contains "$OUT" 'flow lesson undo never-pipe-env-files-to-the-clipboard' "round trip: the metacharacter pattern denies its own input"
	json='{"session_id":"fr-rt","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"*.env | pbcopy"}}'
	run_hook "$SCAN_DIR/flow-rules.sh" "$json" CLAUDE_PROJECT_DIR="$repo" HOME="$home"
	assert_eq "$OUT" "" "round trip: the metacharacter pattern keeps its quotes too"
	_fr_clean fr-rt "$repo" "$home"
}
