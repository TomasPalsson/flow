#!/usr/bin/env bash
# test_case_selfcheck.sh — tests for scripts/case-selfcheck against three tiny
# fixture cases. Sourced by run.sh (HERE and SCAN_DIR are set).
set -u

CSC="$SCAN_DIR/case-selfcheck"
CSC_FIX="$HERE/fixtures/case-selfcheck"

t_case_selfcheck_fixtures() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_case_selfcheck_fixtures (PyYAML absent)\n'
		return
	fi
	run_cmd "$CSC" --root "$CSC_FIX"
	assert_rc 1 "case-selfcheck exits 1 when a fixture fails"
	assert_contains "$OUT" "PASS xhard-good (pristine fails: 1 checks; solution: 1 graders + postcheck ok; skipped: 0)" "good fixture passes"
	assert_contains "$OUT" "FAIL xhard-noop: pristine scaffold passes" "noop fixture fails"
	assert_contains "$OUT" "PASS xhard-routing (shape+scaffold only)" "routing fixture is shape-only"
	assert_contains "$OUT" "case-selfcheck: 2 passed, 1 failed" "summary line"
}

t_case_selfcheck_named_case() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_case_selfcheck_named_case (PyYAML absent)\n'
		return
	fi
	run_cmd "$CSC" --root "$CSC_FIX" xhard-good
	assert_rc 0 "case-selfcheck on xhard-good alone exits 0"
}

# _csc_mkcase <root> <name> <grader-yaml-lines> <scaffold-body>: minimal gradeable case.
_csc_mkcase() {
	local d="$1/$2"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: %s\ntags: [pipeline]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\ngraders:\n%s\n' "$2" "$3" >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\n%s\n' "$4" >"$d/scaffold.sh"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 2\\n" > a.py\n' >"$d/solution.sh"
	chmod +x "$d/scaffold.sh" "$d/solution.sh"
}

_csc_no_yaml() {
	python3 -c 'import yaml' >/dev/null 2>&1 && return 1
	printf '  skip %s (PyYAML absent)\n' "$1"
	return 0
}

t_case_selfcheck_bad_regex_cleans_up() {
	_csc_no_yaml t_case_selfcheck_bad_regex_cleans_up && return
	local root tmp
	root=$(mktemp -d)
	tmp=$(mktemp -d)
	_csc_mkcase "$root" xhard-badre '  - name: bad
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = ("
    match: contains' 'printf "x = 1\n" > a.py'
	run_cmd env TMPDIR="$tmp" "$CSC" --root "$root"
	assert_rc 1 "invalid regex fails the case, not the run"
	assert_contains "$OUT" "FAIL xhard-badre: grader bad: invalid regex" "invalid regex reported per grader"
	assert_eq "$(find "$tmp" -maxdepth 1 -name 'case-selfcheck.*' | wc -l | tr -d ' ')" "0" "no tmp dirs leaked"
	rm -rf "$root" "$tmp"
}

t_case_selfcheck_bad_match_and_root() {
	_csc_no_yaml t_case_selfcheck_bad_match_and_root && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-badmatch '  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: matches' 'printf "x = 1\n" > a.py'
	run_cmd "$CSC" --root "$root"
	assert_contains "$OUT" "unknown match" "typo'd match value rejected"
	rm -rf "$root"
	run_cmd "$CSC" --root "$root/does-not-exist"
	assert_rc 2 "nonexistent --root exits 2"
	assert_contains "$OUT" "cannot read root" "nonexistent --root explained"
}

t_case_selfcheck_isolates_git_env() {
	_csc_no_yaml t_case_selfcheck_isolates_git_env && return
	local root seen
	root=$(mktemp -d)
	seen="$root/seen"
	_csc_mkcase "$root" xhard-iso '  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: contains' "printf 'x = 1\\n' > a.py
printf '%s|%s\\n' \"\${GIT_CONFIG_GLOBAL:-unset}\" \"\${GIT_DIR:-unset}\" > \"$seen\""
	run_cmd env GIT_CONFIG_GLOBAL=/tmp/should-not-leak GIT_DIR=/tmp/nope "$CSC" --root "$root"
	assert_rc 0 "isolation fixture passes"
	assert_eq "$(head -1 "$seen")" "/dev/null|unset" "scaffold sees neutral git env"
	rm -rf "$root"
}

# ---------- --live (stub claude, no spend) ----------

# _csc_live_case <root> <name> <extra-grader-yaml> [timeout]: a case whose file grader needs x = 2.
_csc_live_case() {
	local d="$1/$2"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: %s\ntags: [xhard]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\n  timeout_seconds: %s\n  allowed_tools: [Read, Bash]\ngraders:\n  - name: file-ok\n    type: regex\n    target: { source: file, path: a.py }\n    pattern: "x = 2"\n    match: contains\n%s\n' "$2" "${4:-30}" "$3" >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 1\\n" > a.py\n' >"$d/scaffold.sh"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 2\\n" > a.py\n' >"$d/solution.sh"
	chmod +x "$d/scaffold.sh" "$d/solution.sh"
}

# _csc_live <root> <log> <case> [K=V ...]: run --live against the stub claude.
_csc_live() {
	local root="$1" log="$2" name="$3"
	shift 3
	run_cmd env CASE_LIVE_CLAUDE="$CSC_FIX/_live/claude" STUB_LOG="$log" STUB_TRACE="$CSC_FIX/_live/trace.jsonl" \
		CASE_DIR="$root/$name" "$@" "$CSC" --live --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" "$name"
}

t_case_selfcheck_live_pass_line_and_results() {
	_csc_no_yaml t_case_selfcheck_live_pass_line_and_results && return
	local root log
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-lv '  - name: saw-router
    type: regex
    target: trace
    pattern: "flow next"
    match: contains
  - name: bash-twice
    type: tool_used
    tool: Bash
    input_match: "flow next|ls"
    min: 1
    max: 2
  - name: says-done
    type: llm
    criteria: "PASS if done"'
	_csc_live "$root" "$log" xhard-lv
	assert_rc 0 "all graders pass -> exit 0"
	assert_contains "$OUT" 'LIVE xhard-lv score=1.00 post=ok turns=3 cost=$0.25' "per-case line"
	assert_contains "$OUT" 'case-selfcheck --live: 1/1 runs passed, mean score 1.00, cost $0.25' "final line"
	assert_eq "$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); r=d["runs"][0]; print(d["passed"], d["total"], r["case"], r["run"], r["score"], r["post"], r["timed_out"])' "$log/out/results.json")" "1 1 xhard-lv 1 1.0 True False" "results.json shape"
	assert_eq "$(cat "$log/mds")" "1" "CLAUDE.md loading disabled for the agent"
	assert_eq "$(cat "$log/flow-path")" "$(cd "$SCAN_DIR/.." && pwd -P)/bin/flow" "PATH puts this plugin's bin first"
	assert_contains "$(cat "$log/agent-args")" "--permission-mode dontAsk --allowedTools Read Bash --max-turns 5 --output-format stream-json" "agent argv"
	assert_contains "$(cat "$log/judge-args")" "--max-turns 1 --output-format json" "judge argv"
	if [ -f "$log/out/xhard-lv/run-1/trace.jsonl" ]; then _pass "trace kept"; else _fail "trace kept" "missing"; fi
	if [ -d "$log/out/xhard-lv/run-1/tree" ]; then _fail "tree deleted without --keep" "still there"; else _pass "tree deleted without --keep"; fi
	rm -rf "$root" "$log"
}

t_case_selfcheck_live_failures_reported() {
	_csc_no_yaml t_case_selfcheck_live_failures_reported && return
	local root log
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-lf '  - name: no-router
    type: regex
    target: trace
    pattern: "flow next"
    match: not_contains
  - name: bash-once
    type: tool_used
    tool: Bash
    min: 0
    max: 1
  - name: judged
    type: llm
    criteria: "PASS if done"'
	_csc_live "$root" "$log" xhard-lf STUB_JUDGE=FAIL
	assert_rc 1 "failed graders -> exit 1"
	assert_contains "$OUT" "LIVE xhard-lf score=0.25 post=ok" "score counts weights"
	assert_contains "$OUT" "  - no-router: trace not_contains /flow next/" "regex failure line"
	assert_contains "$OUT" "  - bash-once: Bash used 2 times (min 0, max 1)" "tool_used failure line"
	assert_contains "$OUT" "  - judged: FAIL: nope" "judge sentence"
	assert_contains "$OUT" "0/1 runs passed" "final line counts failure"
	rm -rf "$root" "$log"
}

# A trace regex holding a plain `"` or `—` must match the JSON-escaped trace, and
# a no-focus llm judge must see the user's prompt (a pre-approval lives there).
t_case_selfcheck_live_decoded_trace_and_prompt() {
	_csc_no_yaml t_case_selfcheck_live_decoded_trace_and_prompt && return
	run_cmd python3 - "$CSC" <<'PY'
import importlib.machinery, importlib.util, json, sys
loader = importlib.machinery.SourceFileLoader("csc", sys.argv[1])
spec = importlib.util.spec_from_loader("csc", loader)
csc = importlib.util.module_from_spec(spec)
loader.exec_module(csc)
ev = [{"type": "user", "message": {"content": [{"type": "tool_result", "content": 'Next: reply "approved" — full plan'}]}},
      {"type": "result", "result": "done"}]
raw = "\n".join(json.dumps(e) for e in ev)
import re
print("decoded", bool(re.search('Next: reply "approved" — full', csc.decoded_trace(ev, raw))))
print("raw", bool(re.search('Next: reply "approved"', raw)))
print("prompt", "treat this as go" in csc.transcript(ev, "treat this as go"))
PY
	assert_contains "$OUT" "decoded True" "decoded trace matches a plain-quote pattern"
	assert_contains "$OUT" "raw False" "the raw JSONL alone would not"
	assert_contains "$OUT" "prompt True" "transcript carries the user prompt"
}

t_case_selfcheck_live_refuses_out_under_claude_home() {
	_csc_no_yaml t_case_selfcheck_live_refuses_out_under_claude_home && return
	local root home
	root=$(mktemp -d)
	home=$(mktemp -d)
	_csc_live_case "$root" xhard-lh ''
	run_cmd env HOME="$home" CASE_LIVE_CLAUDE="$CSC_FIX/_live/claude" "$CSC" --live --root "$root" --out "$home/.claude/out" xhard-lh
	assert_rc 2 "out under ~/.claude refuses with exit 2"
	assert_contains "$OUT" "is under ~/.claude" "refusal names the reason"
	assert_eq "$(ls "$home/.claude" 2>/dev/null | wc -l | tr -d ' ')" "0" "nothing created under ~/.claude"
	rm -rf "$root" "$home"
}

t_case_selfcheck_live_timeout_kills() {
	_csc_no_yaml t_case_selfcheck_live_timeout_kills && return
	local root log
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-lt '' 2
	_csc_live "$root" "$log" xhard-lt STUB_SLEEP=30
	assert_rc 1 "timed-out run exits 1"
	assert_contains "$OUT" "[timed out]" "hang flagged on the line"
	assert_contains "$OUT" "  - file-ok:" "graders still score a timed-out run"
	assert_eq "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["runs"][0]["timed_out"])' "$log/out/results.json")" "True" "results.json records timed_out"
	rm -rf "$root" "$log"
}

t_case_selfcheck_live_ledger_line() {
	_csc_no_yaml t_case_selfcheck_live_ledger_line && return
	local root log
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-ll ''
	_csc_live "$root" "$log" xhard-ll
	assert_rc 0 "run without --ledger passes"
	if [ -e "$log/ledger.jsonl" ]; then _fail "no ledger without --ledger" "written"; else _pass "no ledger without --ledger"; fi
	run_cmd env CASE_LIVE_CLAUDE="$CSC_FIX/_live/claude" STUB_LOG="$log" STUB_TRACE="$CSC_FIX/_live/trace.jsonl" \
		CASE_DIR="$root/xhard-ll" "$CSC" --live --ledger --root "$root" --out "$log/out2" --ledger-path "$log/ledger.jsonl" xhard-ll
	assert_rc 0 "ledger run passes"
	assert_eq "$(wc -l <"$log/ledger.jsonl" | tr -d ' ')" "1" "exactly one ledger line"
	assert_eq "$(python3 -c '
import json, sys
d = json.loads(open(sys.argv[1]).readline())
print(list(d), d["model"], d["judgeModel"], d["tags"], d["meanDelta"], d["partial"], d["reason"], len(d["sha"]))' "$log/ledger.jsonl")" \
		"['ts', 'sha', 'model', 'judgeModel', 'tags', 'meanDelta', 'costUsd', 'partial', 'reason', 'graders'] claude-sonnet-5 claude-haiku-4-5 {'xhard': {'score': 1.0, 'delta': 0, 'cases': 1, 'post': {'pass': 1, 'total': 1}}} 0 False live runner (outside the eval sandbox) 40" "ledger line shape"
	rm -rf "$root" "$log"
}

# R1: the agent's CLAUDE_PLUGIN_ROOT is the plugin under test.
t_case_selfcheck_live_sets_plugin_root() {
	_csc_no_yaml t_case_selfcheck_live_sets_plugin_root && return
	local root log
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-pr ''
	_csc_live "$root" "$log" xhard-pr
	assert_eq "$(cat "$log/plugin-root")" "$(cd "$SCAN_DIR/.." && pwd -P)" "CLAUDE_PLUGIN_ROOT is the plugin under test"
	rm -rf "$root" "$log"
}

# R1: a Bash call naming an installed plugin/skill copy contaminates the run.
# R2: a scaffold that names $HOME is serialized; one that does not is not.
# R3: a long run's clipped middle becomes one ordered line per tool call.
t_case_selfcheck_live_runner_faults_and_digest() {
	_csc_no_yaml t_case_selfcheck_live_runner_faults_and_digest && return
	local d
	d=$(mktemp -d)
	printf 'echo "$HOME/.flow/stealth/x"\n' >"$d/scaffold.sh"
	run_cmd python3 - "$CSC" "$d" <<'PY'
import importlib.machinery, importlib.util, os, sys
loader = importlib.machinery.SourceFileLoader("csc", sys.argv[1])
spec = importlib.util.spec_from_loader("csc", loader)
csc = importlib.util.module_from_spec(spec)
loader.exec_module(csc)
def bash(cmd):
    return {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Bash", "input": {"command": cmd}}]}}
home = os.path.expanduser("~")
print("tilde", csc.installed_copy_use([bash("ls ~/.claude/plugins/marketplaces/x/bin/task-brief")]))
print("abs", csc.installed_copy_use([bash("cat %s/.claude/skills/y/SKILL.md" % home)]))
print("clean", csc.installed_copy_use([bash("ls ~/.claude/projects"), bash("flow next")]))
print("home", csc.scaffold_uses_home(sys.argv[2]))
open(sys.argv[2] + "/scaffold.sh", "w").write('# $HOME in a comment\nprintf x\n')
print("comment", csc.scaffold_uses_home(sys.argv[2]))
ev = []
for i in range(400):
    ev.append(bash("step-%03d %s" % (i, "x" * 300)))
    ev.append({"type": "user", "message": {"content": [{"type": "tool_result", "content": "r" * 500}]}})
ev.append({"type": "result", "result": "done"})
t = csc.transcript(ev, "p")
print("condensed", "middle of the run condensed" in t)
print("digest", "#200 Bash step-199 " in t, "step-000" in t)
print("order", t.index("#200 Bash") < t.index("#201 Bash"))
print("bounded", len(t) < csc.TRANSCRIPT_CAP + 400 * 190)
PY
	assert_contains "$OUT" "tilde ~/.claude/plugins/marketplaces/x/bin/task-brief" "tilde path flagged"
	assert_contains "$OUT" "abs $HOME/.claude/skills/y/SKILL.md" "expanded path flagged"
	assert_contains "$OUT" "clean None" "other ~/.claude paths are fine"
	assert_contains "$OUT" "home True" "scaffold naming \$HOME is serialized"
	assert_contains "$OUT" "comment False" "a comment naming HOME is not"
	assert_contains "$OUT" "condensed True" "long run condensed"
	assert_contains "$OUT" "digest True True" "digest line per call, head kept"
	assert_contains "$OUT" "order True" "digest is ordered"
	assert_contains "$OUT" "bounded True" "transcript stays bounded"
	rm -rf "$d"
}

# R1: a contaminated run fails and is labelled as a runner fault.
t_case_selfcheck_live_contaminated_run_fails() {
	_csc_no_yaml t_case_selfcheck_live_contaminated_run_fails && return
	local root log tr
	root=$(mktemp -d)
	log=$(mktemp -d)
	tr=$(mktemp)
	cp "$CSC_FIX/_live/trace.jsonl" "$tr"
	printf '%s\n' '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls ~/.claude/plugins/marketplaces/flow/scripts"}}]}}' >>"$tr"
	_csc_live_case "$root" xhard-ct ''
	run_cmd env CASE_LIVE_CLAUDE="$CSC_FIX/_live/claude" STUB_LOG="$log" STUB_TRACE="$tr" \
		CASE_DIR="$root/xhard-ct" "$CSC" --live --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-ct
	assert_rc 1 "contaminated run exits 1"
	assert_contains "$OUT" "used an installed plugin copy: ~/.claude/plugins/marketplaces/flow/scripts" "labelled failure"
	assert_eq "$(python3 -c 'import json,sys; r=json.load(open(sys.argv[1]))["runs"][0]; print(r["contaminated"], r["passed"])' "$log/out/results.json")" "True False" "results.json flags contaminated"
	rm -rf "$root" "$log" "$tr"
}

# M17: a candidate must not see that it is graded. The static pass scans the
# scaffold's identity, the case prompt and the names the scaffold creates.
_csc_meta_case() { # <root> <name> <prompt> <scaffold-body>
	_csc_mkcase "$1" "$2" '  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: contains' "$4"
	sed "s|prompt: \"p\"|prompt: \"$3\"|" "$1/$2/case.yaml" >"$1/$2/case.yaml.new" && mv "$1/$2/case.yaml.new" "$1/$2/case.yaml"
}

t_case_selfcheck_meta_word_in_prompt_fails() {
	_csc_no_yaml t_case_selfcheck_meta_word_in_prompt_fails && return
	local root
	root=$(mktemp -d)
	_csc_meta_case "$root" xhard-pe "Fix the bug so the eval passes" 'printf "x = 1\n" > a.py'
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "a prompt naming the eval fails the case"
	assert_contains "$OUT" "FAIL xhard-pe: candidate can see it is graded (prompt 'eval')" "prompt hit named"
	rm -rf "$root"
}

t_case_selfcheck_meta_word_in_identity_and_path_fails() {
	_csc_no_yaml t_case_selfcheck_meta_word_in_identity_and_path_fails && return
	local root
	root=$(mktemp -d)
	_csc_meta_case "$root" xhard-id "Fix it" 'git init -q; git config user.name "eval-scaffold"; git config user.email "dev@example.com"; printf "x = 1\n" > a.py'
	_csc_meta_case "$root" xhard-path "Fix it" 'mkdir benchmark; printf "x = 1\n" > a.py'
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "identity or path naming the grading fails"
	assert_contains "$OUT" "FAIL xhard-id: candidate can see it is graded (git user.name 'eval')" "identity hit named"
	assert_contains "$OUT" "FAIL xhard-path: candidate can see it is graded (path benchmark 'benchmark')" "path hit named"
	rm -rf "$root"
}

t_case_selfcheck_meta_scan_is_whole_word() {
	_csc_no_yaml t_case_selfcheck_meta_scan_is_whole_word && return
	local root
	root=$(mktemp -d)
	_csc_meta_case "$root" xhard-ok "Evaluate the retrieval score field" 'git init -q; git config user.name "Dev"; git config user.email "dev@example.com"; mkdir src; printf "x = 1\n" > a.py; : > src/score.py'
	run_cmd "$CSC" --root "$root"
	assert_not_contains "$OUT" "candidate can see" "evaluate, retrieval and score are not meta words"
	assert_contains "$OUT" "PASS xhard-ok" "neutral case passes"
	rm -rf "$root"
}

# Every shipped scaffold uses a neutral identity (closes I-003).
t_case_selfcheck_shipped_cases_are_neutral() {
	_csc_no_yaml t_case_selfcheck_shipped_cases_are_neutral && return
	local names d
	names=$(for d in "$SCAN_DIR"/../evals/*/; do [ -f "$d/scaffold.sh" ] && basename "$d"; done)
	# shellcheck disable=SC2086
	run_cmd "$CSC" $names
	assert_not_contains "$OUT" "candidate can see it is graded" "no shipped scaffold names the grading"
}

# ---------- F34: scaffold HEAD guard and self-assertions ----------

_CSC_GUARD='if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "refusing to scaffold inside an existing work tree" >&2
	exit 1
fi'
_CSC_COMMIT='git init -q
git config user.email dev@example.com
git config user.name Dev
git config commit.gpgsign false
printf "x = 1\n" > a.py
git add -A
git commit -q -m "init"'
_CSC_FILE_GRADER='  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: contains'

t_csc_commit_scaffold_without_guard_fails() {
	_csc_no_yaml t_csc_commit_scaffold_without_guard_fails && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-noguard "$_CSC_FILE_GRADER" "$_CSC_COMMIT"
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "an unguarded git commit scaffold fails selfcheck"
	assert_contains "$OUT" "FAIL xhard-noguard: scaffold.sh runs git add/commit without the HEAD guard" "failure names the missing guard"
	rm -rf "$root"
}

t_csc_commit_scaffold_with_guard_passes() {
	_csc_no_yaml t_csc_commit_scaffold_with_guard_passes && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-guard "$_CSC_FILE_GRADER" "$_CSC_GUARD
$_CSC_COMMIT"
	run_cmd "$CSC" --root "$root"
	assert_rc 0 "a guarded git commit scaffold passes"
	assert_not_contains "$OUT" "WARN" "a guarded scaffold draws no warning"
	rm -rf "$root"
}

t_csc_guard_after_the_first_commit_does_not_count() {
	_csc_no_yaml t_csc_guard_after_the_first_commit_does_not_count && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-late "$_CSC_FILE_GRADER" "$_CSC_COMMIT
$_CSC_GUARD"
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "a guard placed after the commit is no guard"
	assert_contains "$OUT" "without the HEAD guard" "late guard reported"
	rm -rf "$root"
}

t_csc_unguarded_file_writer_warns_but_passes() {
	_csc_no_yaml t_csc_unguarded_file_writer_warns_but_passes && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-writer "$_CSC_FILE_GRADER" 'printf "x = 1\n" > a.py'
	run_cmd "$CSC" --root "$root"
	assert_rc 0 "a plain file-writing scaffold still passes"
	assert_contains "$OUT" "WARN xhard-writer: scaffold.sh writes files before any HEAD guard" "warning printed"
	assert_contains "$OUT" "PASS xhard-writer" "case still passes"
	rm -rf "$root"
}

t_csc_scaffold_self_assertion_failure_is_a_scaffold_error() {
	_csc_no_yaml t_csc_scaffold_self_assertion_failure_is_a_scaffold_error && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-selfassert "$_CSC_FILE_GRADER" 'printf "x = 1\n" > a.py
test -f trap.txt || { echo "trap.txt was not planted" >&2; exit 1; }'
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "a failing self-assertion fails the run"
	assert_contains "$OUT" "FAIL xhard-selfassert: scaffold error (exit 1): trap.txt was not planted" "reported as a scaffold error"
	assert_not_contains "$OUT" "pristine scaffold" "never reaches the pass/fail verdict on the case"
	rm -rf "$root"
}

# ---------- F33: routing negatives name the skill they near-miss ----------

_csc_routing_neg() { # <root> <name> <description>
	local d="$1/$2"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: %s\ndescription: %s\ntags: [routing]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\ngraders:\n  - name: no-skill\n    type: tool_used\n    tool: Skill\n    input_match: "flow:"\n    min: 0\n    max: 0\n' "$2" "$3" >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 1\\n" > a.py\n' >"$d/scaffold.sh"
	chmod +x "$d/scaffold.sh"
}

t_csc_untagged_routing_negative_warns() {
	_csc_no_yaml t_csc_untagged_routing_negative_warns && return
	local root
	root=$(mktemp -d)
	_csc_routing_neg "$root" routing-none-a "A trivial rename must not fire any skill"
	_csc_routing_neg "$root" routing-none-b "Mentions the word fix but is not a defect (near-miss of flow:fix)"
	_csc_routing_neg "$root" routing-none-c "A pure chat turn, no-territory"
	run_cmd "$CSC" --root "$root" routing-none-a routing-none-b routing-none-c
	assert_rc 0 "the warning never fails the run"
	assert_contains "$OUT" "WARN routing-none-a: negative routing case names no skill" "untagged negative warned"
	assert_not_contains "$OUT" "WARN routing-none-b: negative" "near-miss tag accepted"
	assert_not_contains "$OUT" "WARN routing-none-c: negative" "no-territory tag accepted"
	rm -rf "$root"
}

t_csc_positive_routing_case_does_not_warn() {
	_csc_no_yaml t_csc_positive_routing_case_does_not_warn && return
	local root
	root=$(mktemp -d)
	_csc_routing_neg "$root" routing-pos "Fires fix"
	printf '  - name: fires-fix\n    type: tool_used\n    tool: Skill\n    input_match: "flow:fix"\n    min: 1\n' >>"$root/routing-pos/case.yaml"
	_csc_routing_neg "$root" routing-bad "Bad max"
	sed "s/max: 0/max: none/" "$root/routing-bad/case.yaml" >"$root/routing-bad/c.new" && mv "$root/routing-bad/c.new" "$root/routing-bad/case.yaml"
	run_cmd "$CSC" --root "$root" routing-pos routing-bad
	assert_not_contains "$OUT" "WARN routing-pos: negative" "a case with a min>=1 Skill grader is positive"
	assert_not_contains "$OUT" "Traceback" "a malformed max never crashes the run"
	assert_contains "$OUT" "routing-bad" "the malformed case is still reported"
	rm -rf "$root"
}

t_csc_git_global_options_do_not_hide_an_unguarded_commit() {
	_csc_no_yaml t_csc_git_global_options_do_not_hide_an_unguarded_commit && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-gopt "$_CSC_FILE_GRADER" 'git init -q
printf "x = 1\n" > a.py
git -c user.email=a@b -c user.name=a add -A
git -c user.email=a@b -c user.name=a commit -qm init'
	run_cmd "$CSC" --root "$root"
	assert_rc 1 "an unguarded commit with -c options fails"
	assert_contains "$OUT" "without the HEAD guard" "reported as a missing guard"
	rm -rf "$root"
}

# ---------- F37: --probe-judges ----------

_csc_stub_judge() { # <dir>: a stub claude that answers $STUB_REPLY
	printf '#!/usr/bin/env bash\nprintf '"'"'{"result":"%%s","total_cost_usd":0.001}\\n'"'"' "$STUB_REPLY"\n' >"$1/claude"
	chmod +x "$1/claude"
}

_csc_llm_case() { # <root> <name>
	_csc_mkcase "$1" "$2" '  - name: says-done
    type: llm
    criteria: "PASS if the run finished the task"' 'printf "x = 1\n" > a.py'
}

t_csc_probe_judges_flags_a_grader_that_passes_noise() {
	_csc_no_yaml t_csc_probe_judges_flags_a_grader_that_passes_noise && return
	local root bin
	root=$(mktemp -d)
	bin=$(mktemp -d)
	_csc_stub_judge "$bin"
	_csc_llm_case "$root" q-probe
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" STUB_REPLY='PASS: ok' "$CSC" --probe-judges --root "$root"
	assert_rc 1 "a judge that passes empty input exits 1"
	assert_contains "$OUT" "q-probe/says-done passed" "names case and grader"
	assert_contains "$OUT" "empty" "names the probe input"
	rm -rf "$root" "$bin"
}

t_csc_probe_judges_clean_when_judge_fails_noise() {
	_csc_no_yaml t_csc_probe_judges_clean_when_judge_fails_noise && return
	local root bin
	root=$(mktemp -d)
	bin=$(mktemp -d)
	_csc_stub_judge "$bin"
	_csc_llm_case "$root" q-probe
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" STUB_REPLY='FAIL: x' "$CSC" --probe-judges --root "$root" q-probe
	assert_rc 0 "a judge that fails every probe exits 0"
	assert_contains "$OUT" "1 llm grader(s) probed, 0 passed noise" "summary line"
	rm -rf "$root" "$bin"
}

t_csc_probe_judges_negative_ok_skips_and_is_validated() {
	_csc_no_yaml t_csc_probe_judges_negative_ok_skips_and_is_validated && return
	local root bin
	root=$(mktemp -d)
	bin=$(mktemp -d)
	_csc_stub_judge "$bin"
	_csc_mkcase "$root" q-skip '  - name: file-ok
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: contains
  - name: not-scope-creep
    type: llm
    negative_ok: file-ok
    criteria: "PASS if no extra files were added"' 'printf "x = 1\n" > a.py'
	_csc_mkcase "$root" q-bad '  - name: not-scope-creep
    type: llm
    negative_ok: missing-name
    criteria: "PASS if no extra files were added"' 'printf "x = 1\n" > a.py'
	_csc_mkcase "$root" q-llm-sibling '  - name: other-llm
    type: llm
    criteria: "PASS if done"
  - name: not-scope-creep
    type: llm
    negative_ok: other-llm
    criteria: "PASS if no extra files were added"' 'printf "x = 1\n" > a.py'
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" STUB_REPLY='PASS: ok' "$CSC" --probe-judges --root "$root" q-skip
	assert_rc 0 "a grader with a valid negative_ok is not probed"
	assert_contains "$OUT" "skip q-skip/not-scope-creep (negative_ok: file-ok)" "skip reported"
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" STUB_REPLY='PASS: ok' "$CSC" --probe-judges --root "$root" q-bad
	assert_rc 1 "negative_ok naming a missing grader fails the shape check"
	assert_contains "$OUT" "negative_ok names 'missing-name'" "shape failure explains"
	run_cmd "$CSC" --root "$root" q-llm-sibling
	assert_rc 1 "negative_ok naming an llm sibling fails the shape check"
	assert_contains "$OUT" "file_exists/regex/tool_used" "only deterministic siblings count"
	rm -rf "$root" "$bin"
}

# ---------- F38: errored live runs ----------

# A stub claude whose agent call number $STUB_ERROR_ON ends in an is_error usage-limit result.
_csc_flaky_claude() { # <dir>
	cat >"$1/claude" <<'STUB'
#!/usr/bin/env bash
case " $* " in
*" --output-format json "*)
	printf '{"result":"PASS: ok","total_cost_usd":0.001}\n'
	exit 0
	;;
esac
n=$(cat "$STUB_LOG/count" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s' "$n" >"$STUB_LOG/count"
if [ "$n" = "$STUB_ERROR_ON" ]; then
	printf '%s\n' '{"type":"result","subtype":"success","is_error":true,"result":"You have hit your session limit - resets 2:30am","num_turns":1,"total_cost_usd":0}'
	exit 1
fi
printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"done","num_turns":2,"total_cost_usd":0.25}'
bash "$CASE_DIR/solution.sh"
STUB
	chmod +x "$1/claude"
}

t_csc_live_errored_run_is_listed_and_not_averaged() {
	_csc_no_yaml t_csc_live_errored_run_is_listed_and_not_averaged && return
	local root log bin
	root=$(mktemp -d)
	log=$(mktemp -d)
	bin=$(mktemp -d)
	_csc_flaky_claude "$bin"
	_csc_live_case "$root" xhard-er ''
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" STUB_LOG="$log" STUB_ERROR_ON=2 CASE_DIR="$root/xhard-er" \
		"$CSC" --live --ledger --runs 3 --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-er
	assert_contains "$OUT" "ERRORED xhard-er run-2: hit your session limit" "errored run printed"
	assert_not_contains "$OUT" "LIVE xhard-er score=0.00" "the errored run is not graded as a zero"
	assert_eq "$(wc -l <"$log/out/errors.jsonl" | tr -d ' ')" "1" "errors.jsonl has one row"
	assert_eq "$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(d["meanScore"], d["total"], d["passed"])' "$log/out/results.json")" "1.0 3 2" "meanScore is the mean of the two measured runs"
	assert_eq "$(python3 -c '
import json, sys
d = json.loads(open(sys.argv[1]).readline())
print(d["partial"], d["errored"], d["tags"]["xhard"]["score"], d["tags"]["xhard"]["post"]["total"])' "$log/ledger.jsonl")" "True 1 1.0 2" "ledger: partial, errored count, score over measured runs"
	rm -rf "$root" "$log" "$bin"
}

t_csc_live_no_result_event_is_errored_but_timeout_is_not() {
	_csc_no_yaml t_csc_live_no_result_event_is_errored_but_timeout_is_not && return
	local root log bin
	root=$(mktemp -d)
	log=$(mktemp -d)
	bin=$(mktemp -d)
	printf '#!/usr/bin/env bash\ncase " $* " in *" --output-format json "*) printf '"'"'{"result":"PASS: ok"}\\n'"'"'; exit 0;; esac\nexit 1\n' >"$bin/claude"
	chmod +x "$bin/claude"
	_csc_live_case "$root" xhard-nr ''
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" "$CSC" --live --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-nr
	assert_contains "$OUT" "ERRORED xhard-nr run-1: no result event" "a crash with no result event is errored"
	assert_contains "$OUT" "mean score n/a" "nothing measured, no mean"
	rm -rf "$log/out"
	_csc_live_case "$root" xhard-to '' 2
	_csc_live "$root" "$log" xhard-to STUB_SLEEP=30
	assert_not_contains "$OUT" "ERRORED" "a timed-out run is graded, not errored"
	rm -rf "$root" "$log" "$bin"
}

t_csc_live_unmeasured_cost_is_n_a_not_zero() {
	_csc_no_yaml t_csc_live_unmeasured_cost_is_n_a_not_zero && return
	local root log bin
	root=$(mktemp -d)
	log=$(mktemp -d)
	bin=$(mktemp -d)
	printf '#!/usr/bin/env bash\ncase " $* " in *" --output-format json "*) printf '"'"'{"result":"PASS: ok"}\\n'"'"'; exit 0;; esac\nprintf '"'"'%%s\\n'"'"' '"'"'{"type":"result","is_error":false,"result":"done","num_turns":1}'"'"'\nbash "$CASE_DIR/solution.sh"\n' >"$bin/claude"
	chmod +x "$bin/claude"
	_csc_live_case "$root" xhard-nc ''
	run_cmd env CASE_LIVE_CLAUDE="$bin/claude" CASE_DIR="$root/xhard-nc" "$CSC" --live --ledger --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-nc
	assert_rc 0 "run passes"
	assert_contains "$OUT" "cost=n/a" "per-run line says n/a"
	assert_contains "$OUT" "cost: n/a" "summary says n/a"
	assert_eq "$(python3 -c '
import json, sys
print(json.loads(open(sys.argv[1]).readline())["costUsd"], json.load(open(sys.argv[2]))["costUsd"])' "$log/ledger.jsonl" "$log/out/results.json")" "None None" "null in the ledger and results.json"
	rm -rf "$root" "$log" "$bin"
}

# ---------- F39: grader hash in ledger lines ----------

t_csc_live_ledger_carries_grader_hash() {
	_csc_no_yaml t_csc_live_ledger_carries_grader_hash && return
	local root log want
	root=$(mktemp -d)
	log=$(mktemp -d)
	_csc_live_case "$root" xhard-gh ''
	printf '#!/usr/bin/env bash\nexit 0\n' >"$root/xhard-gh/postcheck.sh"
	chmod +x "$root/xhard-gh/postcheck.sh"
	want=$(python3 -c '
import hashlib, sys
print(hashlib.sha256(b"".join(open(p, "rb").read() for p in sys.argv[1:])).hexdigest())' "$root/xhard-gh/case.yaml" "$root/xhard-gh/postcheck.sh")
	run_cmd env CASE_LIVE_CLAUDE="$CSC_FIX/_live/claude" STUB_LOG="$log" STUB_TRACE="$CSC_FIX/_live/trace.jsonl" \
		CASE_DIR="$root/xhard-gh" "$CSC" --live --ledger --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-gh
	assert_eq "$(python3 -c '
import json, sys
print(json.loads(open(sys.argv[1]).readline())["graders"])' "$log/ledger.jsonl")" "{'xhard-gh': '$want'}" "sha256 of case.yaml + postcheck.sh per case"
	rm -rf "$root" "$log"
}

# ---------- text pins ----------

t_csc_docs_pin_the_new_rules() {
	local readme lesson
	readme=$(cat "$SCAN_DIR/../evals/README.md")
	lesson=$(cat "$SCAN_DIR/../skills/lesson/SKILL.md")
	assert_contains "$readme" "near miss that shares a keyword with one named skill" "README: negatives are near misses"
	assert_contains "$readme" "near-miss of <plugin:skill>" "README: description tag"
	assert_contains "$readme" "one-step ask" "README: one-step asks are not valid positives"
	assert_contains "$readme" "most variance" "README: iterate on high-variance cases"
	assert_contains "$readme" "spread \`GIT_AUTHOR_DATE\`" "README: fixture commit dates"
	assert_contains "$readme" "ends with self-assertions" "README: scaffold self-assertions"
	assert_contains "$readme" "decision only" "README: decision-only prompts"
	assert_contains "$readme" "--probe-judges" "README: probe documented"
	assert_contains "$readme" "negative_ok" "README: opt-out documented"
	assert_contains "$readme" "errors.jsonl" "README: errored runs documented"
	assert_contains "$readme" "graders changed" "README: grader hash documented"
	assert_contains "$readme" "Credit: adapted from anthropics/skills claude-api/shared/evals/eval-audit.md @ " "README: probe credit line"
	assert_contains "$lesson" "one-step ask" "lesson: one-step asks are not a description bug"
}
