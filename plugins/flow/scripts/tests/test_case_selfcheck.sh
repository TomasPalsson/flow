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
		"['ts', 'sha', 'model', 'judgeModel', 'tags', 'meanDelta', 'costUsd', 'partial', 'reason'] claude-sonnet-5 claude-haiku-4-5 {'xhard': {'score': 1.0, 'delta': 0, 'cases': 1, 'post': {'pass': 1, 'total': 1}}} 0 False live runner (outside the eval sandbox) 40" "ledger line shape"
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
