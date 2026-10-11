#!/usr/bin/env bash
# test_security_patterns.sh — F142: security-patterns.sh reports security sinks
# in the lines an Edit/Write ADDED, one line per hit, once per rule+file per
# session, and says nothing otherwise.

# _t_sp_esc <text> → the text escaped for a JSON string body.
_t_sp_esc() {
	local c=$1
	c=${c//\\/\\\\}
	c=${c//\"/\\\"}
	c=${c//$'\n'/\\n}
	printf '%s' "$c"
}

# _t_sp_write <sid> <dir> <name> <content> [VAR=val...] — write the file and
# run the hook as a Write of it.
_t_sp_write() {
	local sid=$1 dir=$2 name=$3 content=$4
	shift 4
	mkdir -p "$(dirname "$dir/$name")"
	printf '%s\n' "$content" >"$dir/$name"
	run_hook "$SCAN_DIR/security-patterns.sh" \
		"{\"session_id\":\"$sid\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$dir/$name\",\"content\":\"$(_t_sp_esc "$content")\"}}" \
		CLAUDE_PROJECT_DIR="$dir" "$@"
}

_t_sp_forget() { rm -f "${TMPDIR:-/tmp}/claude-once-$1" "${TMPDIR:-/tmp}/claude-count-$1"; }

# _t_sp_hit <rule> <name> <content> — the content in <name> reports <rule>.
_t_sp_hit() {
	local sid d
	sid="secpat-hit-$$-$1"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	_t_sp_write "$sid" "$d" "$2" "$3"
	assert_rc 2 "t_secpat $1 hit rc"
	assert_contains "$ERR" "$1:" "t_secpat $1 hit names the rule"
	assert_contains "$ERR" "$2:1 " "t_secpat $1 hit names file:line"
	assert_eq "$(printf '%s\n' "$ERR" | grep -c .)" "1" "t_secpat $1 hit is one line"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

# _t_sp_miss <rule> <name> <content> — a near miss stays silent.
_t_sp_miss() {
	local sid d
	sid="secpat-miss-$$-$1"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	_t_sp_write "$sid" "$d" "$2" "$3"
	assert_rc 0 "t_secpat $1 near-miss rc ($2)"
	assert_eq "$OUT$ERR" "" "t_secpat $1 near-miss silent ($2)"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

t_secpat_child_process_exec() {
	_t_sp_hit child_process_exec a.ts 'exec(`ls ${dir}`)'
	_t_sp_miss child_process_exec a.ts 'const m = re.exec(s)'
	_t_sp_miss child_process_exec a.py 'exec(code)'
}

t_secpat_new_function() {
	_t_sp_hit new_function a.js 'const f = new Function("a", body)'
	_t_sp_miss new_function a.js 'const f = new FunctionalThing()'
	_t_sp_miss new_function notes.md 'new Function("a", body)'
}

t_secpat_eval() {
	_t_sp_hit eval a.py 'x = eval(user)'
	_t_sp_miss eval a.py 'model.eval()'
	_t_sp_miss eval notes.md 'eval(user)'
}

t_secpat_dangerously_set_inner_html() {
	_t_sp_hit dangerouslySetInnerHTML a.tsx '<div dangerouslySetInnerHTML={{ __html: h }} />'
	_t_sp_miss dangerouslySetInnerHTML notes.md '<div dangerouslySetInnerHTML={{ __html: h }} />'
}

t_secpat_document_write() {
	_t_sp_hit document_write a.js 'document.write(x)'
	_t_sp_miss document_write a.js 'document.writeln(x)'
}

t_secpat_inner_html_tsx() {
	_t_sp_hit innerHTML a.tsx 'el.innerHTML = x'
	_t_sp_miss innerHTML a.tsx 'if (el.innerHTML === x) {}'
	_t_sp_miss innerHTML notes.md 'el.innerHTML = x'
}

t_secpat_outer_html() {
	_t_sp_hit outerHTML a.js 'el.outerHTML = x'
	_t_sp_miss outerHTML a.js 'const h = el.outerHTML'
}

t_secpat_insert_adjacent_html() {
	_t_sp_hit insertAdjacentHTML a.ts 'el.insertAdjacentHTML("beforeend", x)'
	_t_sp_miss insertAdjacentHTML a.ts 'el.insertAdjacentText("beforeend", x)'
}

t_secpat_pickle_load() {
	_t_sp_hit pickle_load a.py 'obj = pickle.load(f)'
	_t_sp_miss pickle_load a.py 'pickle.dump(obj, f)'
}

t_secpat_os_system() {
	_t_sp_hit os_system a.py 'os.system("ls " + d)'
	_t_sp_miss os_system a.py 'subprocess.run(["ls", d])'
}

t_secpat_subprocess_shell() {
	_t_sp_hit subprocess_shell a.py 'subprocess.run(cmd, shell=True)'
	_t_sp_miss subprocess_shell a.py 'subprocess.run(cmd, shell=False)'
}

t_secpat_yaml_load() {
	_t_sp_hit yaml_load a.py 'cfg = yaml.load(s)'
	_t_sp_miss yaml_load a.py 'cfg = yaml.safe_load(s)'
	_t_sp_miss yaml_load a.py 'cfg = yaml.load(s, Loader=yaml.SafeLoader)'
}

t_secpat_torch_load() {
	_t_sp_hit torch_load a.py 'w = torch.load(p)'
	_t_sp_miss torch_load a.py 'w = torch.load(p, weights_only=True)'
}

t_secpat_tls_verification_disabled() {
	_t_sp_hit tls_verification_disabled a.py 'requests.get(u, verify=False)'
	_t_sp_hit tls_verification_disabled a.ts 'new Agent({ rejectUnauthorized: false })'
	_t_sp_miss tls_verification_disabled a.py 'requests.get(u, verify=True)'
}

t_secpat_go_exec_shell() {
	_t_sp_hit go_exec_shell a.go 'exec.Command("sh", "-c", x)'
	_t_sp_miss go_exec_shell a.go 'exec.Command("ls", x)'
}

t_secpat_clean_edit_is_silent() {
	local sid d
	sid="secpat-clean-$$"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	_t_sp_write "$sid" "$d" src/a.tsx 'export const A = () => <div>hi</div>'
	assert_rc 0 "t_secpat_clean_edit_is_silent rc"
	assert_eq "$OUT$ERR" "" "t_secpat_clean_edit_is_silent silent"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

t_secpat_second_edit_of_the_same_file_adds_nothing() {
	local sid d
	sid="secpat-dedup-$$"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	_t_sp_write "$sid" "$d" a.tsx 'el.innerHTML = x'
	assert_rc 2 "t_secpat_second_edit_of_the_same_file_adds_nothing first edit reports"
	_t_sp_write "$sid" "$d" a.tsx 'el.innerHTML = y'
	assert_rc 0 "t_secpat_second_edit_of_the_same_file_adds_nothing second edit rc"
	assert_eq "$OUT$ERR" "" "t_secpat_second_edit_of_the_same_file_adds_nothing second edit silent"
	_t_sp_write "$sid" "$d" b.tsx 'el.innerHTML = y'
	assert_rc 2 "t_secpat_second_edit_of_the_same_file_adds_nothing another file reports"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

t_secpat_edit_reports_added_lines_not_context() {
	local sid d payload
	sid="secpat-edit-$$"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	printf 'el.innerHTML = old\nconst n = 2\n' >"$d/a.ts"
	# The innerHTML line is in both old_string and new_string: not added, not reported.
	payload="{\"session_id\":\"$sid\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/a.ts\",\"old_string\":\"el.innerHTML = old\\nconst n = 1\",\"new_string\":\"el.innerHTML = old\\nconst n = 2\"}}"
	run_hook "$SCAN_DIR/security-patterns.sh" "$payload" CLAUDE_PROJECT_DIR="$d"
	assert_rc 0 "t_secpat_edit_reports_added_lines_not_context rc"
	assert_eq "$OUT$ERR" "" "t_secpat_edit_reports_added_lines_not_context unchanged sink is silent"
	printf 'const n = 2\nel.innerHTML = x\n' >"$d/a.ts"
	payload="{\"session_id\":\"$sid\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$d/a.ts\",\"old_string\":\"const n = 2\",\"new_string\":\"const n = 2\\nel.innerHTML = x\"}}"
	run_hook "$SCAN_DIR/security-patterns.sh" "$payload" CLAUDE_PROJECT_DIR="$d"
	assert_rc 2 "t_secpat_edit_reports_added_lines_not_context added sink reports"
	assert_contains "$ERR" "a.ts:2 innerHTML:" "t_secpat_edit_reports_added_lines_not_context line number comes from the file"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

t_secpat_switches_silence_it() {
	local sid d
	sid="secpat-sw-$$"
	d=$(tmp_dir)
	_t_sp_forget "$sid"
	_t_sp_write "$sid" "$d" a.tsx 'el.innerHTML = x' CC_NO_SECURITY_PATTERNS=1
	assert_eq "$OUT$ERR" "" "t_secpat_switches_silence_it CC_NO_SECURITY_PATTERNS=1"
	mkdir -p "$d/.claude"
	: >"$d/.claude/flow.off"
	_t_sp_write "$sid" "$d" b.tsx 'el.innerHTML = x'
	assert_eq "$OUT$ERR" "" "t_secpat_switches_silence_it flow off"
	_t_sp_forget "$sid"
	rm -rf "$d"
}

t_secpat_registered_in_hooks_json_post_tool_use() {
	if command -v jq >/dev/null 2>&1; then
		assert_eq "$(jq -r '.hooks.PostToolUse[] | select(.matcher=="Edit|Write|NotebookEdit") | .hooks[].command' "$SCAN_DIR/hooks.json" | grep -c 'security-patterns.sh')" "1" "t_secpat_registered_in_hooks_json_post_tool_use"
	else
		assert_contains "$(cat "$SCAN_DIR/hooks.json")" "hooks/security-patterns.sh" "t_secpat_registered_in_hooks_json_post_tool_use"
	fi
}

t_secpat_credit_line_names_the_source_sha() {
	assert_contains "$(cat "$SCAN_DIR/security-patterns.sh")" "Credit: adapted from anthropics/claude-plugins-official plugins/security-guidance/hooks/patterns.py @ a9fd216 (Apache-2.0)." "t_secpat_credit_line_names_the_source_sha"
}
