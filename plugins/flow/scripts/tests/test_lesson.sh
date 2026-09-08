#!/usr/bin/env bash
# test_lesson.sh — `flow lesson` (spec 005 D-3/D-6): propose DECIDES the rung
# and drafts the guardrail, lock writes it plus one LEDGER ruling, and
# list/undo/off/on/stale manage what was locked.
#
# Every case runs with HOME and TMPDIR under a scratch dir, so --global and the
# draft store never touch the developer's real ~/.claude or /tmp.
set -u

LESSON_FLOW="$SCAN_DIR/../bin/flow"

# _lesson <repo> <home> [args...] — run `flow lesson …` with cwd inside <repo>
_lesson() {
	local repo=$1 home=$2
	shift 2
	mkdir -p "$home/tmp"
	run_cmd env HOME="$home" TMPDIR="$home/tmp" \
		bash -c 'cd "$1" || exit 9; shift; exec node "$@"' _ "$repo" "$LESSON_FLOW" lesson "$@"
}

# _field <json> <dotted.path> — one field out of `propose --json`
_field() {
	printf '%s' "$1" | node -e '
const j = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
let v = j;
for (const k of process.argv[1].split(".")) v = v[k];
console.log(Array.isArray(v) ? v.join(",") : String(v));
' "$2"
}

t_lesson_help_names_every_subcommand() {
	local d sub
	d=$(tmp_dir)
	_lesson "$d" "$d/home" --help
	assert_rc 0 "flow lesson --help exits 0"
	for sub in propose lock list undo off on stale; do
		assert_contains "$OUT" "  $sub" "flow lesson --help documents $sub"
	done
	rm -rf "$d"
}

t_lesson_propose_requires_all_three_fields() {
	local d
	d=$(tmp_dir)
	_lesson "$d" "$d/home" propose --did "x"
	assert_rc 1 "propose without --should and --input exits 1"
	assert_contains "$ERR" "--did, --should and --input are all required" "propose names the missing fields"
	rm -rf "$d"
}

t_lesson_propose_decides_rule_for_a_command() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	assert_rc 0 "propose exits 0"
	assert_eq "$(_field "$OUT" rung)" "rule" "a command string decides the rule rung"
	assert_eq "$(_field "$OUT" slug)" "never-force-push" "the slug is kebab-case from --should"
	assert_contains "$(_field "$OUT" files)" ".claude/flow.rules/never-force-push.md" "propose names the rule file it drafted"
	assert_contains "$(_field "$OUT" preview)" "blocked" "propose previews what the rule does"
	id=$(_field "$OUT" id)
	assert_file_exists "$repo/home/tmp/flow-lesson-$id.json" "propose wrote the draft under TMPDIR"
	assert_file_missing "$repo/.claude/flow.rules/never-force-push.md" "propose writes nothing permanent"
	rm -rf "$repo"
}

t_lesson_propose_decides_test_when_a_runner_exists() {
	local repo
	repo=$(tmp_repo)
	printf '{"name":"fx","scripts":{"test":"vitest run"}}\n' >"$repo/package.json"
	mkdir -p "$repo/tests"
	_lesson "$repo" "$repo/home" propose --did "returned undefined for the empty case" \
		--should "handle the empty list" --input "sum() returned undefined instead of 0" --json
	assert_rc 0 "propose exits 0 with a runner on disk"
	assert_eq "$(_field "$OUT" rung)" "test" "a reproducible mistake plus a vitest runner decides the test rung"
	assert_eq "$(_field "$OUT" tests)" "tests/handle-the-empty-list.test.js" "propose drafts the test under the project's test dir"
	rm -rf "$repo"
}

t_lesson_propose_decides_note_otherwise() {
	local repo
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file before answering" --input "you described the config file without opening it" --json
	assert_rc 0 "propose exits 0 with no runner"
	assert_eq "$(_field "$OUT" rung)" "note" "no command, no path and no runner decides the note rung"
	assert_eq "$(_field "$OUT" files)" "CLAUDE.md" "a note with no path scope falls back to CLAUDE.md"
	assert_eq "$(_field "$OUT" tests)" "" "a note drafts no tests"
	rm -rf "$repo"
}

t_lesson_propose_decides_script_for_bookkeeping() {
	local repo
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "forgot to update PROGRESS.md after the slice" \
		--should "keep the ledger current" --input "the slice landed but PROGRESS.md still said in progress" --json
	assert_eq "$(_field "$OUT" rung)" "script" "bookkeeping decides the script rung"
	rm -rf "$repo"
}

t_lesson_propose_forces_rule_for_an_irreversible_class() {
	local repo
	repo=$(tmp_repo)
	printf '{"name":"fx","scripts":{"test":"vitest run"}}\n' >"$repo/package.json"
	_lesson "$repo" "$repo/home" propose --did "ran the migration against prod" \
		--should "never touch prod data" --input "the migration dropped the users table and returned no error" --json
	assert_eq "$(_field "$OUT" rung)" "rule" "an irreversible class wins over the test rung"
	rm -rf "$repo"
}

t_lesson_lock_writes_the_rule_file() {
	local repo id f
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "lock --choice block exits 0"
	f="$repo/.claude/flow.rules/never-force-push.md"
	assert_file_exists "$f" "lock wrote the rule file"
	assert_eq "$(sed -n '1p' "$f")" "---" "rule file opens with frontmatter"
	assert_eq "$(sed -n '2,9p' "$f" | cut -d: -f1 | tr '\n' ' ')" "event tool pattern action enabled created source hits " "rule frontmatter carries the D-4 keys in order"
	assert_eq "$(sed -n '10p' "$f")" "---" "rule frontmatter closes"
	assert_eq "$(grep '^event:' "$f")" "event: PreToolUse" "a command rule fires on PreToolUse"
	assert_eq "$(grep '^tool:' "$f")" "tool: Bash" "a command rule matches the Bash tool"
	assert_eq "$(grep '^pattern:' "$f")" "pattern: git[[:space:]]+push[[:space:]]+--force" "the pattern is an ERE over the command, generalised past its operands"
	assert_eq "$(grep '^action:' "$f")" "action: deny" "a command rule denies"
	assert_eq "$(grep '^enabled:' "$f")" "enabled: true" "a fresh rule is enabled"
	assert_eq "$(grep '^hits:' "$f")" "hits: 0" "a fresh rule has zero hits"
	assert_contains "$(grep '^created:' "$f")" "created: 20" "created is an ISO date"
	assert_contains "$(grep '^source:' "$f")" 'source: "ran git push --force on main"' "source quotes the Did line"
	assert_contains "$(sed -n '11,$p' "$f")" "flow lesson undo never-force-push" "the message names its own undo"
	rm -rf "$repo"
}

t_lesson_lock_prints_the_receipt_and_one_ledger_ruling() {
	local repo id led
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_eq "$OUT" "flow: lesson locked — never force-push (.claude/flow.rules/never-force-push.md, 0 tests). Undo: flow lesson undo never-force-push" "lock prints exactly the one-line receipt"
	led="$repo/.specs/LEDGER.md"
	assert_file_exists "$led" "lock created .specs/LEDGER.md"
	assert_eq "$(grep -c '^Ruling: ' "$led")" "1" "one ruling appended"
	assert_contains "$(cat "$led")" "never-force-push — never force-push — .claude/flow.rules/never-force-push.md (deny)" "the ruling names the slug, the what and the mechanism"
	# undo, then lock the identical ruling again: the ledger line is never doubled
	_lesson "$repo" "$repo/home" undo never-force-push
	assert_rc 0 "undo exits 0"
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "the second lock exits 0 after the undo"
	assert_eq "$(grep -c '^Ruling: ' "$led")" "1" "an exact-duplicate ruling is never appended twice"
	rm -rf "$repo"
}

t_lesson_duplicate_slug_is_refused() {
	local repo a b
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	a=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	b=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$a" --choice block
	assert_rc 0 "the first lock exits 0"
	_lesson "$repo" "$repo/home" lock "$b" --choice block
	assert_rc 1 "a second lock of the same slug exits 1"
	assert_contains "$ERR" "already locked; undo first" "the refusal says how to get past it"
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	assert_rc 1 "propose refuses a slug that is already locked"
	assert_contains "$ERR" "already locked; undo first" "propose refuses with the same message"
	rm -rf "$repo"
}

t_lesson_list_reports_one_row_per_lesson() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" list
	assert_rc 0 "list on an empty project exits 0"
	assert_contains "$OUT" "no lessons" "list says so when there are none"
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	_lesson "$repo" "$repo/home" list
	assert_rc 0 "list exits 0"
	assert_contains "$OUT" "slug" "list heads the slug column"
	assert_contains "$OUT" "rung" "list heads the rung column"
	assert_contains "$OUT" "action" "list heads the action column"
	assert_contains "$OUT" "created" "list heads the created column"
	assert_contains "$OUT" "hits" "list heads the hits column"
	assert_contains "$OUT" "enabled" "list heads the enabled column"
	assert_contains "$OUT" "never-force-push" "list names the locked slug"
	assert_contains "$OUT" "deny" "list reports the action"
	assert_eq "$(printf '%s' "$OUT" | grep -c 'never-force-push')" "1" "one row per lesson"
	rm -rf "$repo"
}

t_lesson_off_and_on_toggle_enabled() {
	local repo id f
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	f="$repo/.claude/flow.rules/never-force-push.md"
	_lesson "$repo" "$repo/home" off never-force-push
	assert_rc 0 "off exits 0"
	assert_eq "$(grep '^enabled:' "$f")" "enabled: false" "off sets enabled: false"
	_lesson "$repo" "$repo/home" list
	assert_contains "$OUT" "false" "list reports the disabled rule"
	_lesson "$repo" "$repo/home" on never-force-push
	assert_rc 0 "on exits 0"
	assert_eq "$(grep '^enabled:' "$f")" "enabled: true" "on sets enabled: true"
	assert_eq "$(grep -c '^enabled:' "$f")" "1" "toggling never duplicates the key"
	_lesson "$repo" "$repo/home" off nosuchslug
	assert_rc 1 "off on an unknown slug exits 1"
	rm -rf "$repo"
}

t_lesson_undo_removes_the_rule() {
	local repo id f
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	f="$repo/.claude/flow.rules/never-force-push.md"
	_lesson "$repo" "$repo/home" undo never-force-push
	assert_rc 0 "undo exits 0"
	assert_file_missing "$f" "undo deleted the rule file"
	_lesson "$repo" "$repo/home" list
	assert_contains "$OUT" "no lessons" "the undone lesson is gone from list"
	_lesson "$repo" "$repo/home" undo never-force-push
	assert_rc 1 "undo of an unknown slug exits 1"
	rm -rf "$repo"
}

t_lesson_undo_of_a_test_lesson_prints_the_file_and_keeps_it() {
	local repo id t
	repo=$(tmp_repo)
	printf '{"name":"fx","scripts":{"test":"vitest run"}}\n' >"$repo/package.json"
	mkdir -p "$repo/tests"
	_lesson "$repo" "$repo/home" propose --did "returned undefined for the empty case" \
		--should "handle the empty list" --input "sum() returned undefined instead of 0" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "locking a test lesson exits 0"
	t="$repo/tests/handle-the-empty-list.test.js"
	assert_file_exists "$t" "lock wrote the drafted test"
	assert_contains "$(cat "$t")" "vitest" "the draft imports the detected runner"
	assert_contains "$OUT" ", 1 tests)" "the receipt counts the drafted test"
	_lesson "$repo" "$repo/home" undo handle-the-empty-list
	assert_rc 0 "undo of a test lesson exits 0"
	assert_contains "$OUT" "tests/handle-the-empty-list.test.js" "undo prints the test file to delete"
	assert_file_exists "$t" "undo never deletes code"
	rm -rf "$repo"
}

t_lesson_note_choice_then_recurrence_promotes_to_a_rule() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 0 "lock --choice note exits 0"
	assert_file_exists "$repo/CLAUDE.md" "the note landed in CLAUDE.md"
	assert_contains "$(cat "$repo/CLAUDE.md")" "flow lesson undo read-the-file-first" "the note names its own undo"
	assert_file_missing "$repo/.claude/flow.rules/read-the-file-first.md" "a note writes no rule file"
	# Second lock of the same slug. The recurrence gate (D-3) lives in propose:
	# it returns the promoted rung, so the promotion is on the block label
	# BEFORE the question is asked — never sprung on the user by lock.
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file first" --input "you described the config file without opening it" --json
	assert_rc 0 "a noted slug can be proposed again"
	assert_eq "$(_field "$OUT" rung)" "rule" "the second propose returns the promoted rung"
	assert_contains "$(_field "$OUT" block)" "second time" "the block label says this is the second time"
	assert_contains "$(_field "$OUT" block)" "a rule will be installed" "the block label discloses the promotion before the question"
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "the second lock exits 0"
	assert_file_exists "$repo/.claude/flow.rules/read-the-file-first.md" "accepting the promoted block writes the rule"
	assert_contains "$OUT" ".claude/flow.rules/read-the-file-first.md" "the receipt names the promoted rule"
	assert_eq "$(grep -c '^Ruling: ' "$repo/.specs/LEDGER.md")" "2" "each lock records its own ruling"
	rm -rf "$repo"
}

t_lesson_note_is_path_scoped_when_the_input_has_a_path() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "hand-edited the api client" \
		--should "leave the client alone" --input "src/client/api.ts" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 0 "lock --choice note exits 0 for a path input"
	assert_file_exists "$repo/.claude/rules/client.md" "the note is scoped to the input's directory"
	assert_file_missing "$repo/CLAUDE.md" "a path-scoped note never touches CLAUDE.md"
	_lesson "$repo" "$repo/home" undo leave-the-client-alone
	assert_rc 0 "undo of a note exits 0"
	assert_not_contains "$(cat "$repo/.claude/rules/client.md" 2>/dev/null || printf '')" "leave the client alone" "undo removed the note line"
	rm -rf "$repo"
}

t_lesson_discard_writes_nothing() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice discard
	assert_rc 0 "lock --choice discard exits 0"
	assert_file_missing "$repo/.claude/flow.rules/never-force-push.md" "discard writes no rule"
	assert_file_missing "$repo/.specs/LEDGER.md" "discard records no ruling"
	assert_file_missing "$repo/home/tmp/flow-lesson-$id.json" "discard drops the draft"
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 1 "a dropped draft cannot be locked"
	rm -rf "$repo"
}

t_lesson_global_scope_writes_under_home() {
	local repo id home
	repo=$(tmp_repo)
	# node normalises the doubled slash a TMPDIR ending in / leaves behind
	home=$(printf '%s' "$repo/home" | sed 's|//*|/|g')
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" \
		--input "git push --force origin main" --global --json
	assert_rc 0 "propose --global exits 0"
	assert_contains "$(_field "$OUT" files)" "$home/.claude/flow.rules/never-force-push.md" "--global drafts an absolute path under HOME"
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "locking a global draft exits 0"
	assert_file_exists "$repo/home/.claude/flow.rules/never-force-push.md" "the rule landed in ~/.claude/flow.rules"
	assert_file_missing "$repo/.claude/flow.rules/never-force-push.md" "the project store is untouched"
	_lesson "$repo" "$repo/home" list --global
	assert_contains "$OUT" "never-force-push" "list --global reads the global store"
	rm -rf "$repo"
}

t_lesson_stale_reports_unhit_and_unmatched_rules() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	_lesson "$repo" "$repo/home" stale --days 30
	assert_rc 0 "stale exits 0"
	assert_not_contains "$OUT" "never-force-push" "a rule created today is not stale at 30 days"
	_lesson "$repo" "$repo/home" stale --days 0
	assert_contains "$OUT" "never-force-push" "a rule with zero hits is stale once it is old enough"
	assert_contains "$OUT" "0 hits" "stale says why"
	# a path rule whose pattern matches nothing tracked in the repo
	_lesson "$repo" "$repo/home" propose --did "hand-edited generated code" \
		--should "never edit generated files" --input "src/generated/api.ts" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	_lesson "$repo" "$repo/home" stale --days 30
	assert_contains "$OUT" "never-edit-generated-files" "a pattern matching nothing in the repo is stale"
	assert_contains "$OUT" "matches nothing" "stale says why"
	rm -rf "$repo"
}

# The mkdir lock the retired lesson-record carried: research §6 keeps it, so it
# keeps its regression test. Six locks of six DIFFERENT slugs at once must lose
# neither a ruling (the LEDGER append) nor an index row — list, undo, off and
# the recurrence gate all read that index back.
t_lesson_concurrent_locks_lose_no_ruling_and_no_index_row() {
	local repo i id ids
	repo=$(tmp_repo)
	mkdir -p "$repo/home/tmp"
	ids=""
	i=0
	while [ $i -lt 6 ]; do
		_lesson "$repo" "$repo/home" propose --did "d$i" --should "never force-push $i" \
			--input "git push --force origin br$i" --json
		ids="$ids $(_field "$OUT" id)"
		i=$((i + 1))
	done
	for id in $ids; do
		(cd "$repo" && env HOME="$repo/home" TMPDIR="$repo/home/tmp" \
			node "$LESSON_FLOW" lesson lock "$id" --choice block) >/dev/null 2>&1 &
	done
	wait
	assert_eq "$(grep -c '^Ruling: ' "$repo/.specs/LEDGER.md")" "6" "six concurrent locks: six rulings, none lost"
	assert_eq "$(grep -c '"slug":' "$repo/.claude/flow.rules/.lessons.json")" "6" "six concurrent locks: six index rows, none clobbered"
	assert_eq "$(ls -d "$repo"/.specs/LEDGER.md.lock "$repo"/.claude/flow.rules/.lessons.json.lock 2>/dev/null | wc -l | tr -d ' ')" "0" "every lock was released"
	_lesson "$repo" "$repo/home" list
	assert_eq "$(printf '%s' "$OUT" | grep -c 'never-force-push')" "6" "list finds all six"
	rm -rf "$repo"
}

t_lesson_a_failed_ledger_append_locks_nothing() {
	local repo id
	repo=$(tmp_repo)
	mkdir -p "$repo/.specs"
	# a LEDGER that ends inside an open fence: the append refuses to bury the
	# ruling in a code block, so the whole lock has to come back off disk
	printf '# Ledger\n\n```\nunclosed\n' >"$repo/.specs/LEDGER.md"
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 1 "lock exits 1 when the ruling cannot be recorded"
	assert_contains "$ERR" "unclosed code fence" "the failure names what refused the write"
	assert_not_contains "$(cat "$repo/CLAUDE.md" 2>/dev/null || printf '')" "flow lesson undo read-the-file-first" "no note is left live behind a failed lock"
	assert_file_exists "$repo/home/tmp/flow-lesson-$id.json" "the draft survives, so the lock can be retried"
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 1 "a rule lock exits 1 on the same LEDGER"
	assert_file_missing "$repo/.claude/flow.rules/never-force-push.md" "no rule file is left live behind a failed lock"
	_lesson "$repo" "$repo/home" list
	assert_contains "$OUT" "no lessons" "a failed lock records no lesson"
	rm -rf "$repo"
}

t_lesson_promotion_removes_the_note_it_replaces() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 0 "the first lock notes it"
	_lesson "$repo" "$repo/home" propose --did "answered from memory again" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "the second lock promotes it"
	assert_not_contains "$(cat "$repo/CLAUDE.md")" "flow lesson undo read-the-file-first" "promotion takes the note line with it"
	_lesson "$repo" "$repo/home" undo read-the-file-first
	assert_rc 0 "undo of the promoted rule exits 0"
	assert_not_contains "$(cat "$repo/CLAUDE.md")" "read the file first" "undo leaves no orphaned note line"
	rm -rf "$repo"
}

# "Just note it — one line in CLAUDE.md" may never install a live deny rule.
# The recurrence gate promotes the RUNG in propose, where the label can say so;
# the answer the user gives to that question is final, so --choice note writes
# a note on the second lock exactly as it did on the first.
t_lesson_choice_note_is_final_on_a_promoted_draft() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 0 "the first lock notes it"
	_lesson "$repo" "$repo/home" propose --did "answered from memory again" \
		--should "read the file first" --input "you described the config file without opening it" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice note
	assert_rc 0 "the second lock exits 0"
	assert_file_missing "$repo/.claude/flow.rules/read-the-file-first.md" "--choice note installs no rule, promoted or not"
	assert_contains "$OUT" "note in CLAUDE.md" "the receipt names the note it wrote"
	assert_eq "$(grep -c 'flow lesson undo read-the-file-first' "$repo/CLAUDE.md")" "1" "the second note replaces the first instead of stacking beside it"
	assert_contains "$(cat "$repo/CLAUDE.md")" "answered from memory again" "the note kept is the one just locked"
	_lesson "$repo" "$repo/home" list
	assert_eq "$(printf '%s' "$OUT" | awk '$1 == "read-the-file-first" { print $3 }')" "note" "list reports the lesson as a note, not a deny"
	rm -rf "$repo"
}

# D-2(c): the skill fills the first option's label from propose's `block` field
# verbatim, so the label has to say what --choice block actually writes. On a
# note or script rung that is a note — and it must not read as enforcement.
t_lesson_propose_block_label_names_what_it_writes() {
	local repo label
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "answered from memory" \
		--should "read the file before answering" --input "you described the config file without opening it" --json
	assert_eq "$(_field "$OUT" rung)" "note" "the draft is a note rung"
	label=$(_field "$OUT" block)
	assert_contains "$label" "a note in CLAUDE.md" "the block label names the artefact and the file it writes"
	assert_contains "$label" "not enforced" "the block label says the note enforces nothing"
	assert_not_contains "$label" "block" "a note-rung draft's block label never claims to block anything"
	_lesson "$repo" "$repo/home" propose --did "ran git push --force on main" \
		--should "never force-push" --input "git push --force origin main" --json
	label=$(_field "$OUT" block)
	assert_contains "$label" "are blocked" "a rule-rung block label reads as enforcement"
	assert_contains "$label" "the rule .claude/flow.rules/never-force-push.md" "a rule-rung block label names the rule file"
	rm -rf "$repo"
}

# D-3's fourth rung, end to end: flow cannot write your bookkeeping script, so
# the artefact is a note that says a script is wanted — and never reports as an
# ordinary note in the receipt, in list or in the ruling.
t_lesson_script_rung_locks_a_script_wanted_note() {
	local repo id
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "forgot to update PROGRESS.md after the slice" \
		--should "keep the ledger current" --input "the slice landed but PROGRESS.md still said in progress" --json
	assert_eq "$(_field "$OUT" rung)" "script" "bookkeeping decides the script rung"
	assert_contains "$(_field "$OUT" block)" "a script-wanted note in CLAUDE.md" "the block label names the script-wanted note"
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	assert_rc 0 "locking a script-rung draft exits 0"
	assert_contains "$OUT" "script-wanted note in CLAUDE.md" "the receipt reports the script rung, not a block"
	assert_contains "$(cat "$repo/CLAUDE.md")" "script wanted: keep the ledger current" "the note says a script is wanted"
	assert_contains "$(cat "$repo/CLAUDE.md")" "automate the bookkeeping in \"forgot to update PROGRESS.md after the slice\"" "the note names the bookkeeping to automate"
	assert_contains "$(cat "$repo/.specs/LEDGER.md")" "(script)" "the ruling records the script rung"
	_lesson "$repo" "$repo/home" list
	assert_eq "$(printf '%s' "$OUT" | awk '$1 == "keep-the-ledger-current" { print $2, $3 }')" "script script" "list reports the lesson as script, not note"
	_lesson "$repo" "$repo/home" undo keep-the-ledger-current
	assert_rc 0 "undo of a script lesson exits 0"
	assert_not_contains "$(cat "$repo/CLAUDE.md")" "script wanted" "undo removed the script-wanted note"
	rm -rf "$repo"
}

# undo, off and on join the slug from argv into a path under the store, so a
# slug that is not the shape slugify produces would reach a file outside it.
t_lesson_undo_off_and_on_refuse_a_slug_that_is_a_path() {
	local repo id outside
	repo=$(tmp_repo)
	_lesson "$repo" "$repo/home" propose --did "d" --should "never force-push" --input "git push --force origin main" --json
	id=$(_field "$OUT" id)
	_lesson "$repo" "$repo/home" lock "$id" --choice block
	mkdir -p "$repo/elsewhere"
	outside="$repo/elsewhere/notes.md"
	printf 'not a lesson\n' >"$outside"
	_lesson "$repo" "$repo/home" undo ../../elsewhere/notes
	assert_rc 1 "undo of a traversing slug exits 1"
	assert_contains "$ERR" "is not a lesson slug" "undo says why it refused"
	assert_file_exists "$outside" "undo never reached the file outside the store"
	_lesson "$repo" "$repo/home" off ../../elsewhere/notes
	assert_rc 1 "off of a traversing slug exits 1"
	assert_contains "$ERR" "is not a lesson slug" "off says why it refused"
	_lesson "$repo" "$repo/home" on /etc/passwd
	assert_rc 1 "on of an absolute path exits 1"
	assert_contains "$ERR" "is not a lesson slug" "on says why it refused"
	assert_file_exists "$repo/.claude/flow.rules/never-force-push.md" "the refusals left the real lesson alone"
	rm -rf "$repo"
}

# The skill is the only caller of this CLI: it has to be shaped like a skill,
# name the two subcommands it drives, and carry none of the retired v1 surface.
t_lesson_skill_frontmatter_and_references() {
	local skill body
	skill="$SCAN_DIR/../skills/lesson/SKILL.md"
	assert_file_exists "$skill" "lesson skill exists"
	assert_eq "$(sed -n '1p' "$skill")" "---" "lesson skill starts its frontmatter"
	assert_contains "$(sed -n '2,5p' "$skill")" "name: lesson" "lesson skill is named lesson"
	assert_contains "$(sed -n '3p' "$skill")" "Use WHENEVER the user corrects" "description carries the trigger"
	body=$(cat "$skill")
	assert_contains "$body" "flow lesson propose" "skill invokes flow lesson propose"
	assert_contains "$body" "flow lesson lock" "skill invokes flow lesson lock"
	assert_not_contains "$body" '${CLAUDE_PLUGIN_ROOT}' "skill carries no CLAUDE_PLUGIN_ROOT literal"
	assert_not_contains "$body" "lesson-sites" "the retired lesson-sites script is gone from the skill"
	assert_not_contains "$body" "lesson-record" "the retired lesson-record script is gone from the skill"
	assert_not_contains "$body" "| Rung | Question | Site |" "the five-row rung table is gone"
	# A pathless mistake — the common case for a behavioural lesson — is noted
	# in CLAUDE.md, so the note option may not promise .claude/rules/ alone.
	assert_contains "$body" "Just note it  one line in CLAUDE.md" "the note option names the destination the CLI actually writes"
	assert_not_contains "$body" "the drafted rule" "the block option's label comes from propose, not a hardcoded promise of a rule"
}
