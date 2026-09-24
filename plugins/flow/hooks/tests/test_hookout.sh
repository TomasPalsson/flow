#!/usr/bin/env bash
# lib/hookout.sh (spec 003 C-A) — the shared helper API every hook is built on.
# Each test drives a throwaway script that sources hookout.sh exactly the way a
# real hook does, so the sourcing path itself is under test.

_ho_lib() { printf '%s' "$SCAN_DIR/lib/hookout.sh"; }

# _ho_script <dir> <name> <body-line>... → path of a runnable driver script.
_ho_script() {
	local d=$1 name=$2
	shift 2
	{
		printf '#!/usr/bin/env bash\n'
		printf 'set -u\n'
		printf '. "$HOOKOUT_LIB"\n'
		printf '%s\n' "$@"
	} >"$d/$name"
	printf '%s' "$d/$name"
}

t_hookout_project_dir_is_physical() {
	local d s real
	d=$(tmp_dir)
	mkdir -p "$d/real"
	ln -s "$d/real" "$d/link"
	real=$(cd "$d/real" && pwd -P)
	s=$(_ho_script "$d" pd.sh 'hook_project_dir')
	run_hook "$s" '{}' HOOKOUT_LIB="$(_ho_lib)" CLAUDE_PROJECT_DIR="$d/link"
	assert_rc 0 "t_hookout_project_dir_is_physical rc"
	assert_eq "$OUT" "$real" "t_hookout_project_dir_is_physical symlinked project dir resolves to pwd -P"
	run_hook "$s" '{}' HOOKOUT_LIB="$(_ho_lib)" CLAUDE_PROJECT_DIR="$d/nope"
	assert_eq "$OUT" "$d/nope" "t_hookout_project_dir_is_physical unreachable dir falls back to the raw value"
	rm -rf "$d"
}

t_hookout_config_reads_flow_config_values() {
	local d s lib
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/.claude"
	printf '{"deny":["terraform destroy","task tf:destroy"],"stopGate":"scoped","maxFileLines":300}\n' >"$d/.claude/flow.config.json"
	s=$(_ho_script "$d" cfg.sh 'hook_config "$KEY"')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" KEY=deny
	assert_eq "$OUT" '["terraform destroy","task tf:destroy"]' "t_hookout_config_reads_flow_config_values array key is compact JSON"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" KEY=stopGate
	assert_eq "$OUT" "scoped" "t_hookout_config_reads_flow_config_values string key is raw"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" KEY=maxFileLines
	assert_eq "$OUT" "300" "t_hookout_config_reads_flow_config_values number key"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" KEY=nosuchkey
	assert_eq "$OUT" "" "t_hookout_config_reads_flow_config_values absent key is empty"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/real-nowhere" KEY=deny
	assert_eq "$OUT" "" "t_hookout_config_reads_flow_config_values no config file is empty"
	rm -rf "$d"
}

t_hookout_prune_dirs_and_ignore_patterns() {
	local d s lib
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/.claude"
	s=$(_ho_script "$d" prune.sh 'hook_prune_dirs')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c -x '\.next')" "1" "t_hookout_prune_dirs_and_ignore_patterns .next is pruned"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c -x '__pycache__')" "1" "t_hookout_prune_dirs_and_ignore_patterns __pycache__ is pruned"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c -x '\.flow-swarm')" "1" "t_hookout_prune_dirs_and_ignore_patterns .flow-swarm is pruned"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c .)" "24" "t_hookout_prune_dirs_and_ignore_patterns 24 prune dirs"
	s=$(_ho_script "$d" ign.sh 'hook_ignore_patterns')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_contains "$OUT" "migrations/" "t_hookout_prune_dirs_and_ignore_patterns default list"
	assert_contains "$OUT" "third_party/" "t_hookout_prune_dirs_and_ignore_patterns vendored list is always on"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c .)" "10" "t_hookout_prune_dirs_and_ignore_patterns 5 default + 5 vendored"
	printf '{"ignore":["fixtures/"]}\n' >"$d/.claude/flow.config.json"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_contains "$OUT" "fixtures/" "t_hookout_prune_dirs_and_ignore_patterns config ignore is used"
	assert_not_contains "$OUT" "migrations/" "t_hookout_prune_dirs_and_ignore_patterns config ignore replaces the default wholesale"
	assert_contains "$OUT" "vendor/" "t_hookout_prune_dirs_and_ignore_patterns config cannot switch off the vendored list"
	rm -rf "$d"
}

t_hookout_excluded_path_rules() {
	local d s lib
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/lib/thirdparty"
	: >"$d/lib/thirdparty/VENDORED.md"
	s=$(_ho_script "$d" ex.sh 'if hook_excluded_path "$TARGET"; then printf excluded; else printf judged; fi')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/src/app.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_rules plain source file is judged"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/node_modules/pkg/index.js"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_rules prune dir component"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/app/.next/server/page.js"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_rules .next component"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/src/locales/en.ts"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_rules ignore pattern substring"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/api/vendor/guzzle/Client.php"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_rules always-on vendored pattern"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/lib/thirdparty/deep/x.ts"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_rules VENDORED.md marker above the file"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" TARGET="$d/node_modules/pkg/index.js" CC_HOOKS_ALL_FILES=1
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_rules CC_HOOKS_ALL_FILES=1 judges everything"
	rm -rf "$d"
}

t_hookout_excluded_path_turn_scoped_gitignore() {
	local repo s lib sid stamp
	repo=$(tmp_repo)
	lib=$(_ho_lib)
	sid="ho-ign-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	mkdir -p "$repo/logs" "$repo/sub/tmpx"
	printf 'logs/\n' >"$repo/.gitignore"
	printf 'tmpx/\n' >"$repo/sub/.gitignore"
	: >"$repo/logs/a.log"
	: >"$repo/sub/tmpx/b.ts"
	: >"$repo/sub/keep.ts"
	git -C "$repo" add -A >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ignores >/dev/null 2>&1
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	touch -t 202001010000 "$repo/.gitignore" "$repo/.git/info/exclude"
	touch -t 202101010000 "$repo/sub/.gitignore"
	s=$(_ho_script "$repo" ex.sh 'if hook_excluded_path "$TARGET"; then printf excluded; else printf judged; fi')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/logs/a.log"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_turn_scoped_gitignore ignore file older than the turn keeps the exemption"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/sub/tmpx/b.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_turn_scoped_gitignore ignore file newer than the turn voids the exemption"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/sub/keep.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_turn_scoped_gitignore tracked file beside a dirty ignore file is judged"
	touch -t 202101010000 "$repo/.git/info/exclude"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/logs/a.log"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_turn_scoped_gitignore .git/info/exclude newer than the turn voids the exemption"
	rm -f "$stamp"
	rm -rf "$repo"
}

# A linked worktree reads .git/info/exclude from the COMMON dir, so the
# turn-scoped rule has to look there too — otherwise appending a path to the
# main checkout's exclude file is a free dodge from inside a worktree.
t_hookout_excluded_path_turn_scoped_exclude_in_a_worktree() {
	local repo parent wt s lib sid stamp
	repo=$(tmp_repo)
	parent=$(tmp_dir)
	wt="$parent/wt"
	lib=$(_ho_lib)
	sid="ho-wtx-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	git -C "$repo" worktree add -q "$wt" >/dev/null 2>&1
	: >"$wt/scratch.ts"
	printf 'scratch.ts\n' >>"$repo/.git/info/exclude"
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	s=$(_ho_script "$parent" ex.sh 'if hook_excluded_path "$TARGET"; then printf excluded; else printf judged; fi')
	assert_eq "$(git -C "$wt" check-ignore -q -- "$wt/scratch.ts" && printf ignored || printf tracked)" "ignored" \
		"t_hookout_excluded_path_turn_scoped_exclude_in_a_worktree the common-dir exclude file does ignore the file"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$wt" TARGET="$wt/scratch.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_turn_scoped_exclude_in_a_worktree a fresh common-dir exclude file voids the exemption inside the worktree"
	touch -t 202001010000 "$repo/.git/info/exclude"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$wt" TARGET="$wt/scratch.ts"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_turn_scoped_exclude_in_a_worktree an old common-dir exclude file keeps the exemption"
	rm -f "$stamp"
	git -C "$repo" worktree remove --force "$wt" >/dev/null 2>&1 || true
	rm -rf "$parent" "$repo"
}

t_hookout_git_managed_uses_the_turn_scoped_rule() {
	local repo s lib sid stamp
	repo=$(tmp_repo)
	lib=$(_ho_lib)
	sid="ho-gm-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	mkdir -p "$repo/logs"
	printf 'logs/\n' >"$repo/.gitignore"
	: >"$repo/logs/a.log"
	git -C "$repo" add -A >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ignores >/dev/null 2>&1
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	touch -t 202001010000 "$repo/.gitignore" "$repo/.git/info/exclude"
	s=$(_ho_script "$repo" gm.sh 'if hook_git_managed "$TARGET"; then printf managed; else printf skipped; fi')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/logs/a.log"
	assert_eq "$OUT" "skipped" "t_hookout_git_managed_uses_the_turn_scoped_rule a git-ignored file with old ignore files is not managed"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/README.md"
	assert_eq "$OUT" "managed" "t_hookout_git_managed_uses_the_turn_scoped_rule a tracked file is managed"
	touch "$repo/.gitignore"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/logs/a.log"
	assert_eq "$OUT" "managed" "t_hookout_git_managed_uses_the_turn_scoped_rule an ignore file newer than the turn stamp makes the file managed again"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="/tmp/nowhere-$$/x.ts"
	assert_eq "$OUT" "skipped" "t_hookout_git_managed_uses_the_turn_scoped_rule a path outside any work tree is not managed"
	# A Write names a file whose parent directories do not exist yet. `git -C`
	# cannot run in a missing directory; treating that as "not a work tree"
	# let spec-gate's PreToolUse half allow any unapproved source file simply
	# by putting it under a new directory.
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/src/new/deep/x.ts"
	assert_eq "$OUT" "managed" "t_hookout_git_managed_uses_the_turn_scoped_rule a file under a not-yet-created directory inside the repo is managed"
	# ... and the ignore rule still reaches such a path: check-ignore is
	# path-based, so asking from the nearest existing ancestor is equivalent.
	# (Re-backdate .gitignore: the touch above deliberately voided the
	# exemption for this turn.)
	touch -t 202001010000 "$repo/.gitignore"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" TARGET="$repo/logs/new/deep/a.log"
	assert_eq "$OUT" "skipped" "t_hookout_git_managed_uses_the_turn_scoped_rule a file under a not-yet-created directory that git ignores is not managed"
	rm -f "$stamp"
	rm -rf "$repo"
}

t_hookout_changed_since_prunes_noise_and_ignored() {
	local repo s lib sid stamp
	repo=$(tmp_repo)
	lib=$(_ho_lib)
	sid="ho-cs-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	printf 'ignored.log\n' >"$repo/.gitignore"
	git -C "$repo" add .gitignore >/dev/null 2>&1
	git -C "$repo" -c user.email=t@t -c user.name=t commit -qm ignore >/dev/null 2>&1
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	touch -t 202001010000 "$repo/.gitignore" "$repo/.git/info/exclude"
	mkdir -p "$repo/src" "$repo/.next/server" "$repo/__pycache__" "$repo/build" "$repo/node_modules/pkg"
	: >"$repo/src/a.ts"
	: >"$repo/.next/server/trace"
	: >"$repo/__pycache__/x.pyc"
	: >"$repo/build/out.js"
	: >"$repo/node_modules/pkg/index.js"
	: >"$repo/ignored.log"
	s=$(_ho_script "$repo" cs.sh 'hook_changed_since "$STAMP"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" STAMP="$stamp"
	assert_rc 0 "t_hookout_changed_since_prunes_noise_and_ignored rc"
	assert_contains "$OUT" "$repo/src/a.ts" "t_hookout_changed_since_prunes_noise_and_ignored lists the changed source file"
	assert_not_contains "$OUT" "/.next/" "t_hookout_changed_since_prunes_noise_and_ignored prunes .next"
	assert_not_contains "$OUT" "__pycache__" "t_hookout_changed_since_prunes_noise_and_ignored prunes __pycache__"
	assert_not_contains "$OUT" "/build/" "t_hookout_changed_since_prunes_noise_and_ignored prunes build"
	assert_not_contains "$OUT" "node_modules" "t_hookout_changed_since_prunes_noise_and_ignored prunes node_modules"
	assert_not_contains "$OUT" "ignored.log" "t_hookout_changed_since_prunes_noise_and_ignored drops git-ignored files"
	rm -f "$stamp"
	rm -rf "$repo"
}

t_hookout_changed_since_worktree_git_file_and_missing_stamp() {
	local d s lib sid stamp
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-wt-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	mkdir -p "$d/src"
	printf 'gitdir: /nowhere/.git/worktrees/wt\n' >"$d/.git"
	: >"$d/src/a.ts"
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	s=$(_ho_script "$d" cs.sh 'hook_changed_since "$STAMP"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" STAMP="$stamp"
	assert_contains "$OUT" "$d/src/a.ts" "t_hookout_changed_since_worktree_git_file_and_missing_stamp lists the source file"
	assert_not_contains "$OUT" "$d/.git" "t_hookout_changed_since_worktree_git_file_and_missing_stamp skips a worktree .git file"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d" STAMP="$d/no-such-stamp"
	assert_rc 0 "t_hookout_changed_since_worktree_git_file_and_missing_stamp missing stamp rc 0"
	assert_eq "$OUT" "" "t_hookout_changed_since_worktree_git_file_and_missing_stamp missing stamp prints nothing"
	rm -f "$stamp"
	rm -rf "$d"
}

t_hookout_note_and_soft_json_shape() {
	local d lib s msg
	d=$(tmp_dir)
	lib=$(_ho_lib)
	msg='gate could not run: "npm test" not found
second line'
	s=$(_ho_script "$d" note.sh 'hook_note "$MSG"')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" MSG="$msg"
	assert_rc 0 "t_hookout_note_and_soft_json_shape note rc 0"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.systemMessage')" "$msg" "t_hookout_note_and_soft_json_shape systemMessage round-trips"
	assert_eq "$(printf '%s' "$OUT" | jq -r 'has("decision")')" "false" "t_hookout_note_and_soft_json_shape a note never carries a decision"
	s=$(_ho_script "$d" soft.sh 'hook_soft "$MSG"')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" MSG="$msg"
	assert_rc 0 "t_hookout_note_and_soft_json_shape soft rc 0"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')" "Stop" "t_hookout_note_and_soft_json_shape soft is a Stop event"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext')" "$msg" "t_hookout_note_and_soft_json_shape additionalContext round-trips"
	assert_eq "$(printf '%s' "$OUT" | jq -r 'has("decision")')" "false" "t_hookout_note_and_soft_json_shape soft never blocks"
	rm -rf "$d"
}

t_hookout_once_is_per_key_and_per_session() {
	local d lib s sid
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-once-$$"
	rm -f "${TMPDIR:-/tmp}/claude-once-$sid" "${TMPDIR:-/tmp}/claude-once-${sid}b"
	s=$(_ho_script "$d" once.sh 'if hook_once "$KEY"; then printf first; else printf again; fi')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" KEY=no-ecosystem
	assert_eq "$OUT" "first" "t_hookout_once_is_per_key_and_per_session first sighting"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" KEY=no-ecosystem
	assert_eq "$OUT" "again" "t_hookout_once_is_per_key_and_per_session second sighting"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" KEY=other-key
	assert_eq "$OUT" "first" "t_hookout_once_is_per_key_and_per_session a different key is its own counter"
	run_hook "$s" "{\"session_id\":\"${sid}b\"}" HOOKOUT_LIB="$lib" KEY=no-ecosystem
	assert_eq "$OUT" "first" "t_hookout_once_is_per_key_and_per_session a different session starts over"
	rm -f "${TMPDIR:-/tmp}/claude-once-$sid" "${TMPDIR:-/tmp}/claude-once-${sid}b"
	rm -rf "$d"
}

t_hookout_count_counts_identical_signatures() {
	local d lib s sid
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-count-$$"
	rm -f "${TMPDIR:-/tmp}/claude-count-$sid"
	s=$(_ho_script "$d" count.sh 'hook_count "$SIG"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="stop-gate test"
	assert_eq "$OUT" "1" "t_hookout_count_counts_identical_signatures first"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="stop-gate test"
	assert_eq "$OUT" "2" "t_hookout_count_counts_identical_signatures second"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="stop-gate test"
	assert_eq "$OUT" "3" "t_hookout_count_counts_identical_signatures third"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="stop-gate lint"
	assert_eq "$OUT" "1" "t_hookout_count_counts_identical_signatures a different signature is its own counter"
	rm -f "${TMPDIR:-/tmp}/claude-count-$sid"
	rm -rf "$d"
}

t_hookout_blocking_helpers_emit_the_reason_unchanged() {
	local d lib s sid cf reason
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-deny-$$"
	cf="${TMPDIR:-/tmp}/claude-count-$sid"
	rm -f "$cf"
	reason='force-pushing to a shared branch is blocked'
	s=$(_ho_script "$d" deny.sh 'hook_deny "$REASON"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	assert_rc 0 "t_hookout_blocking_helpers_emit_the_reason_unchanged deny rc 0"
	assert_not_contains "$OUT" "/lesson" "t_hookout_blocking_helpers_emit_the_reason_unchanged first deny has no prose"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	assert_not_contains "$OUT" "/lesson" "t_hookout_blocking_helpers_emit_the_reason_unchanged second identical deny has no prose"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason')" "$reason" "t_hookout_blocking_helpers_emit_the_reason_unchanged deny reason is verbatim"
	s=$(_ho_script "$d" block.sh 'hook_block "$REASON"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	assert_not_contains "$OUT" "/lesson" "t_hookout_blocking_helpers_emit_the_reason_unchanged second identical block has no prose"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.reason')" "$reason" "t_hookout_blocking_helpers_emit_the_reason_unchanged block reason is verbatim"
	s=$(_ho_script "$d" fb.sh 'hook_feedback "$REASON"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" REASON="$reason"
	assert_rc 2 "t_hookout_blocking_helpers_emit_the_reason_unchanged feedback rc 2"
	assert_eq "$ERR" "$reason" "t_hookout_blocking_helpers_emit_the_reason_unchanged feedback text is verbatim"
	assert_contains "$(cat "$cf" 2>/dev/null)" "deny.sh $reason" "t_hookout_blocking_helpers_emit_the_reason_unchanged the counter still records silently"
	assert_eq "$(grep -c . "$cf")" "6" "t_hookout_blocking_helpers_emit_the_reason_unchanged six blocks recorded"
	rm -f "$cf"
	rm -rf "$d"
}

t_hookout_excluded_path_matches_relative_to_the_project() {
	local d s lib
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/build/app/src" "$d/build/app/node_modules/pkg" "$d/i18n/site/src" "$d/build/other/dist"
	s=$(_ho_script "$d" ex.sh 'if hook_excluded_path "$TARGET"; then printf excluded; else printf judged; fi')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/build/app" TARGET="$d/build/app/src/app.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_matches_relative_to_the_project a checkout under build/ still judges its own sources"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/i18n/site" TARGET="$d/i18n/site/src/app.ts"
	assert_eq "$OUT" "judged" "t_hookout_excluded_path_matches_relative_to_the_project an ignore pattern in the checkout path is not a match"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/build/app" TARGET="$d/build/app/node_modules/pkg/index.js"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_matches_relative_to_the_project a prune dir inside that checkout is still excluded"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/build/app" TARGET="$d/build/other/dist/bundle.js"
	assert_eq "$OUT" "excluded" "t_hookout_excluded_path_matches_relative_to_the_project a file outside the project is matched on its whole path"
	rm -rf "$d"
}

t_hookout_changed_since_survives_a_prune_named_project_dir() {
	local d s lib sid stamp
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-pdir-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	mkdir -p "$d/build/app/src" "$d/dist/src"
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	: >"$d/build/app/src/app.ts"
	: >"$d/dist/src/app.ts"
	s=$(_ho_script "$d" cs.sh 'hook_changed_since "$STAMP"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/build/app" STAMP="$stamp"
	assert_contains "$OUT" "app/src/app.ts" "t_hookout_changed_since_survives_a_prune_named_project_dir a project under build/ still reports its changes"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d/dist" STAMP="$stamp"
	assert_contains "$OUT" "dist/src/app.ts" "t_hookout_changed_since_survives_a_prune_named_project_dir find does not prune its own start point"
	rm -f "$stamp"
	rm -rf "$d"
}

t_hookout_once_and_count_accept_option_shaped_keys() {
	local d lib s sid
	d=$(tmp_dir)
	lib=$(_ho_lib)
	sid="ho-opt-$$"
	rm -f "${TMPDIR:-/tmp}/claude-once-$sid" "${TMPDIR:-/tmp}/claude-count-$sid"
	s=$(_ho_script "$d" once.sh 'if hook_once "$KEY"; then printf first; else printf again; fi')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" KEY="-v no-ecosystem"
	assert_eq "$OUT" "first" "t_hookout_once_and_count_accept_option_shaped_keys a dash-leading key is a pattern, first sighting"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" KEY="-v no-ecosystem"
	assert_eq "$OUT" "again" "t_hookout_once_and_count_accept_option_shaped_keys a dash-leading key is remembered"
	s=$(_ho_script "$d" count.sh 'hook_count "$SIG"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="-e something"
	assert_eq "$OUT" "1" "t_hookout_once_and_count_accept_option_shaped_keys a dash-leading signature counts once"
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" SIG="-e something"
	assert_eq "$OUT" "2" "t_hookout_once_and_count_accept_option_shaped_keys a dash-leading signature counts twice"
	rm -f "${TMPDIR:-/tmp}/claude-once-$sid" "${TMPDIR:-/tmp}/claude-count-$sid"
	rm -rf "$d"
}

t_hookout_ignore_patterns_keep_defaults_for_a_malformed_config() {
	local d s lib
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/.claude"
	s=$(_ho_script "$d" ign.sh 'hook_ignore_patterns')
	printf '{"ignore":"migrations/"}\n' >"$d/.claude/flow.config.json"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_contains "$OUT" "generated/" "t_hookout_ignore_patterns_keep_defaults_for_a_malformed_config a string ignore keeps the C4 defaults"
	assert_contains "$OUT" "vendor/" "t_hookout_ignore_patterns_keep_defaults_for_a_malformed_config a string ignore keeps the vendored list"
	printf '{"ignore":[]}\n' >"$d/.claude/flow.config.json"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_contains "$OUT" "generated/" "t_hookout_ignore_patterns_keep_defaults_for_a_malformed_config an empty ignore array keeps the defaults"
	printf '{"ignore":["fixtures/",7]}\n' >"$d/.claude/flow.config.json"
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$d"
	assert_contains "$OUT" "generated/" "t_hookout_ignore_patterns_keep_defaults_for_a_malformed_config a mixed-type ignore array keeps the defaults"
	rm -rf "$d"
}

t_hookout_json_fallback_escapes_control_characters() {
	local d lib s msg t
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/bin"
	for t in bash cat sed awk tr; do
		ln -s "$(command -v "$t")" "$d/bin/$t" 2>/dev/null || true
	done
	msg="say \"hi\"$(printf '\t')tab
second line"
	s=$(_ho_script "$d" note.sh 'hook_note "$MSG"')
	run_hook "$s" '{}' HOOKOUT_LIB="$lib" MSG="$msg" PATH="$d/bin"
	assert_rc 0 "t_hookout_json_fallback_escapes_control_characters note rc 0 without jq or python3"
	assert_eq "$(printf '%s' "$OUT" | jq -r '.systemMessage' 2>/dev/null)" "$msg" "t_hookout_json_fallback_escapes_control_characters the hand-escaped JSON parses and round-trips a tab"
	rm -rf "$d"
}

# Contract addition: with neither jq nor python3 on PATH, hook_field must
# still return "" (its stdout is almost always captured via `$(hook_field
# ...)`, so any notice printed there would corrupt the caller's field) and
# must warn exactly once per process, on stderr, no matter how many fields
# the hook asks for.
t_hookout_field_no_parser_notice_once_and_still_empty() {
	local d lib s
	d=$(tmp_dir)
	lib=$(_ho_lib)
	mkdir -p "$d/bin"
	for t in bash cat sed awk tr; do
		ln -s "$(command -v "$t")" "$d/bin/$t" 2>/dev/null || true
	done
	s=$(_ho_script "$d" field.sh 'a=$(hook_field ".x"); b=$(hook_field ".y"); printf "a=[%s] b=[%s]" "$a" "$b"')
	run_hook "$s" '{"x":1,"y":2}' HOOKOUT_LIB="$lib" PATH="$d/bin"
	assert_rc 0 "t_hookout_field_no_parser_notice_once_and_still_empty rc 0 without jq or python3"
	assert_eq "$OUT" "a=[] b=[]" "t_hookout_field_no_parser_notice_once_and_still_empty hook_field still returns '' for every call"
	assert_contains "$ERR" "field.sh: jq and python3 are both missing" "t_hookout_field_no_parser_notice_once_and_still_empty the notice names the hook and the missing tools"
	local notice_count
	notice_count=$(printf '%s\n' "$ERR" | grep -c "jq and python3 are both missing")
	assert_eq "$notice_count" "1" "t_hookout_field_no_parser_notice_once_and_still_empty the notice fires exactly once per process, not once per hook_field call"
	rm -rf "$d"
}

t_hookout_changed_since_parses_the_config_once() {
	local repo lib s sid stamp log i njq ngit njudged budget
	repo=$(tmp_repo)
	lib=$(_ho_lib)
	sid="ho-perf-$$"
	stamp="${TMPDIR:-/tmp}/claude-turn-$sid"
	log="$repo/calls.log"
	mkdir -p "$repo/bin" "$repo/.claude" "$repo/src" "$repo/logs"
	printf '{"ignore":["fixtures/"]}\n' >"$repo/.claude/flow.config.json"
	printf 'logs/\n' >"$repo/.gitignore"
	{
		printf '#!/bin/sh\n'
		printf 'echo jq >>"%s"\n' "$log"
		printf 'exec %s "$@"\n' "$(command -v jq)"
	} >"$repo/bin/jq"
	{
		printf '#!/bin/sh\n'
		printf 'echo git >>"%s"\n' "$log"
		printf 'exec %s "$@"\n' "$(command -v git)"
	} >"$repo/bin/git"
	chmod +x "$repo/bin/jq" "$repo/bin/git"
	: >"$stamp"
	touch -t 202006010000 "$stamp"
	i=0
	while [ "$i" -lt 20 ]; do
		: >"$repo/src/f$i.ts"
		: >"$repo/logs/f$i.log"
		i=$((i + 1))
	done
	# Older than the stamp, so the git-ignore exemption survives this turn and
	# the 20 log files really take the ignored path (check-ignore, then the
	# turn-scoped rule's toplevel + common-dir lookups).
	touch -t 202001010000 "$repo/.gitignore" "$repo/.git/info/exclude"
	: >"$log"
	s=$(_ho_script "$repo" cs.sh 'hook_changed_since "$STAMP"')
	run_hook "$s" "{\"session_id\":\"$sid\"}" HOOKOUT_LIB="$lib" CLAUDE_PROJECT_DIR="$repo" STAMP="$stamp" PATH="$repo/bin:$PATH"
	assert_eq "$(printf '%s\n' "$OUT" | grep -c '/src/f')" "20" "t_hookout_changed_since_parses_the_config_once lists all 20 changed files"
	assert_not_contains "$OUT" "/logs/" "t_hookout_changed_since_parses_the_config_once the 20 git-ignored files stay excluded"
	njq=$(grep -c '^jq$' "$log" 2>/dev/null || printf 0)
	ngit=$(grep -c '^git$' "$log" 2>/dev/null || printf 0)
	# Budget: one check-ignore per judged file, plus check-ignore + the two
	# rev-parse lookups for each of the 20 ignored ones. A fourth git process on
	# the ignored path breaks this.
	njudged=$(printf '%s\n' "$OUT" | grep -c . || printf 0)
	budget=$((njudged + 3 * 20))
	# 3 jq for the config parse + 1 for the session id, each once per process.
	if [ "$njq" -le 4 ]; then njq=ok; fi
	if [ "$ngit" -le "$budget" ]; then ngit=ok; fi
	assert_eq "$njq" "ok" "t_hookout_changed_since_parses_the_config_once flow.config.json is parsed once, not once per file"
	assert_eq "$ngit" "ok" "t_hookout_changed_since_parses_the_config_once one git call per judged file and three per git-ignored file"
	rm -f "$stamp"
	rm -rf "$repo"
}
