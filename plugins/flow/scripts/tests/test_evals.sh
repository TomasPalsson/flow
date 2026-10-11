#!/usr/bin/env bash
# test_evals.sh — tests for the eval suite under plugins/flow/evals/ (Slice 4,
# .claude/slices/4-brief.md; spec .specs/007-plugin-eval-suite-and-optimisation-loop/
# spec.md Journey 1 AC-001, FR-001..FR-004) (B11, B12).
#
# Walks every plugins/flow/evals/*/case.yaml and checks: schema_version is
# present, tags are a subset of the contract's TAGS (falling back to the
# frozen list when contract.js does not exist yet), scaffold.sh is
# executable, at least one grader is declared, and every case name the
# spec requires exists.
#
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent) are already set.
set -u

EVALS_DIR="$SCAN_DIR/../evals"
EV_REPO_ROOT=$(cd "$HERE/../../../.." && pwd -P)
EV_CONTRACT_JS="$EV_REPO_ROOT/plugins/flow/bin/lib/eval/contract.js"

EV_FALLBACK_TAGS="quality routing invariant needs-bash xhard"
if [ -f "$EV_CONTRACT_JS" ]; then
	EV_VALID_TAGS=$(cd "$EV_REPO_ROOT" && node -e "console.log(require('./plugins/flow/bin/lib/eval/contract.js').TAGS.join(' '))" 2>/dev/null)
	[ -n "$EV_VALID_TAGS" ] || EV_VALID_TAGS="$EV_FALLBACK_TAGS"
else
	EV_VALID_TAGS="$EV_FALLBACK_TAGS"
fi

EV_REQUIRED_CASES="quality-reuse-existing-helper quality-no-premature-abstraction quality-no-impossible-guards quality-no-comment-noise quality-no-unrequested-scope quality-test-can-fail routing-fix routing-next routing-spec routing-loop routing-prep routing-scrutinize-idea routing-qa routing-audit routing-none-explain routing-none-rename invariant-reproduce-first invariant-reproduce-first-pressure invariant-never-weaken invariant-verifier-decides routing-develop-idea"

ev_tag_is_valid() {
	local tag=$1 t
	for t in $EV_VALID_TAGS; do
		[ "$t" = "$tag" ] && return 0
	done
	return 1
}

# ev_case_tags <case.yaml> — the `tags: [a, b]` line, comma-split into words
ev_case_tags() {
	grep -m1 '^tags:' "$1" | sed 's/^tags:[[:space:]]*\[//; s/\].*$//; s/,/ /g'
}

# ---------------------------------------------------------------------------
# B11 — probe-write/ is gone (superseded by quality-reuse-existing-helper)
# and every case name FR-002/FR-003/FR-004 require exists as a case dir.
# ---------------------------------------------------------------------------

t_probe_write_removed() {
	assert_file_missing "$EVALS_DIR/probe-write" "probe-write/ removed (superseded by quality-reuse-existing-helper)"
}

t_required_case_names_present() {
	local name
	for name in $EV_REQUIRED_CASES; do
		assert_file_exists "$EVALS_DIR/$name/case.yaml" "case dir present: $name/case.yaml"
	done
}

# ---------------------------------------------------------------------------
# B12 — every case.yaml under evals/ carries schema_version, tags a subset
# of TAGS, an executable scaffold.sh beside it, and at least one grader.
# ---------------------------------------------------------------------------

t_every_case_has_schema_version() {
	local dir f
	for dir in "$EVALS_DIR"/*/; do
		[ -d "$dir" ] || continue
		f="${dir}case.yaml"
		[ -f "$f" ] || continue
		if grep -q '^schema_version:' "$f"; then
			_pass "schema_version present: ${dir#"$EVALS_DIR"/}case.yaml"
		else
			_fail "schema_version present: ${dir#"$EVALS_DIR"/}case.yaml" "no schema_version: line"
		fi
	done
}

t_every_case_tags_subset_of_TAGS() {
	local dir f tags t bad
	for dir in "$EVALS_DIR"/*/; do
		[ -d "$dir" ] || continue
		f="${dir}case.yaml"
		[ -f "$f" ] || continue
		tags=$(ev_case_tags "$f")
		bad=""
		for t in $tags; do
			ev_tag_is_valid "$t" || bad="$bad $t"
		done
		if [ -z "$bad" ]; then
			_pass "tags subset of TAGS: ${dir#"$EVALS_DIR"/}case.yaml"
		else
			_fail "tags subset of TAGS: ${dir#"$EVALS_DIR"/}case.yaml" "unknown tag(s):$bad"
		fi
	done
}

t_every_case_has_executable_scaffold() {
	local dir s
	for dir in "$EVALS_DIR"/*/; do
		[ -d "$dir" ] || continue
		[ -f "${dir}case.yaml" ] || continue
		s="${dir}scaffold.sh"
		if [ -x "$s" ]; then
			_pass "executable scaffold.sh: ${dir#"$EVALS_DIR"/}"
		else
			_fail "executable scaffold.sh: ${dir#"$EVALS_DIR"/}" "missing or not executable: $s"
		fi
	done
}

t_every_case_has_at_least_one_grader() {
	local dir f count
	for dir in "$EVALS_DIR"/*/; do
		[ -d "$dir" ] || continue
		f="${dir}case.yaml"
		[ -f "$f" ] || continue
		count=$(grep -c '^  - name:' "$f")
		if [ "$count" -ge 1 ]; then
			_pass ">=1 grader: ${dir#"$EVALS_DIR"/}case.yaml"
		else
			_fail ">=1 grader: ${dir#"$EVALS_DIR"/}case.yaml" "found $count grader entries"
		fi
	done
}

# ---------------------------------------------------------------------------
# B11 — README.md promises `evals/results/` is gitignored. The repo's
# .gitignore must actually ignore the suite's real results dir, which lives
# at plugins/flow/evals/results/, not at the repo root. Checked hermetically
# against a throwaway repo carrying this repo's .gitignore text.
# ---------------------------------------------------------------------------

t_gitignore_covers_nested_eval_results() {
	local d
	d=$(tmp_repo)
	cp "$EV_REPO_ROOT/.gitignore" "$d/.gitignore"
	mkdir -p "$d/plugins/flow/evals/results"
	printf '{}\n' >"$d/plugins/flow/evals/results/aggregate-result.json"
	run_cmd git -C "$d" check-ignore -q plugins/flow/evals/results/aggregate-result.json
	assert_rc 0 ".gitignore ignores plugins/flow/evals/results/ (README claim holds)"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# routing negative-grader regression guard — a `no-other-hub-skill` grader
# whose input_match was built from bare skill names (e.g. `\bfix\b`) matches
# the `flow:` plugin prefix of every Skill call, so it fails alongside a
# correctly-firing expected skill. The pattern must anchor on the full
# `flow:<skill>` name and must never match the case's own expected skill.
# ---------------------------------------------------------------------------

t_evals_routing_negative_graders_exclude_own_skill() {
	if ! command -v python3 >/dev/null 2>&1; then
		printf '  skip t_evals_routing_negative_graders_exclude_own_skill (python3 absent)\n'
		return
	fi
	local dir skill f out
	for dir in "$EVALS_DIR"/routing-*/; do
		[ -d "$dir" ] || continue
		case "$dir" in
		*/routing-none-*) continue ;;
		esac
		f="${dir}case.yaml"
		[ -f "$f" ] || continue
		skill="${dir#"$EVALS_DIR"/routing-}"
		skill="${skill%/}"
		out=$(python3 - "$f" "$skill" <<'PYEOF'
import sys, yaml, re
f, skill = sys.argv[1], sys.argv[2]
d = yaml.safe_load(open(f))
grader = next((g for g in d.get("graders", []) if g.get("name") == "no-other-hub-skill"), None)
if grader is None:
    print("missing-grader")
    sys.exit(0)
pattern = grader.get("input_match", "")
own_call = '{"skill": "flow:%s", "args": ""}' % skill
bad = []
if re.search(pattern, own_call):
    bad.append("matches-own-skill")
if r"\bflow\b" in pattern:
    bad.append("bare-flow-boundary")
print(",".join(bad) if bad else "OK")
PYEOF
)
		if [ "$out" = "OK" ]; then
			_pass "no-other-hub-skill excludes own skill, no bare \\bflow\\b: ${dir#"$EVALS_DIR"/}case.yaml"
		else
			_fail "no-other-hub-skill excludes own skill, no bare \\bflow\\b: ${dir#"$EVALS_DIR"/}case.yaml" "$out"
		fi
	done
}

t_evals_routing_fires_graders_with_only() {
	if ! command -v python3 >/dev/null 2>&1; then
		printf '  skip t_evals_routing_fires_graders_with_only (python3 absent)\n'
		return
	fi
	local dir f out
	for dir in "$EVALS_DIR"/routing-*/; do
		[ -d "$dir" ] || continue
		f="${dir}case.yaml"
		[ -f "$f" ] || continue
		out=$(python3 - "$f" <<'PYEOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
bad = [g.get("name", "") for g in d.get("graders", [])
       if g.get("name", "").startswith("fires-") and g.get("arm") != "with-only"]
print(",".join(bad) if bad else "OK")
PYEOF
)
		if [ "$out" = "OK" ]; then
			_pass "fires-* graders carry arm: with-only: ${dir#"$EVALS_DIR"/}case.yaml"
		else
			_fail "fires-* graders carry arm: with-only: ${dir#"$EVALS_DIR"/}case.yaml" "missing on: $out"
		fi
	done
}

# ---------------------------------------------------------------------------
# invariant-reproduce-first's bug-report prompt has no slash command, so the
# invariant only holds if the fix skill actually fires first - a bare-model
# run that reproduces then edits with no Skill call satisfies the tool_order
# grader while never exercising the plugin's own reproduce-first design.
# ---------------------------------------------------------------------------

t_invariant_reproduce_first_checks_fix_fires() {
	local f content
	f="$EVALS_DIR/invariant-reproduce-first/case.yaml"
	[ -f "$f" ] || { _fail "invariant-reproduce-first case.yaml exists" "missing: $f"; return; }
	content=$(cat "$f")
	assert_contains "$content" "flow:fix" "a grader checks the flow:fix skill fires"
	assert_contains "$content" "Skill" "allowed_tools grants Skill"
}

# ---------------------------------------------------------------------------
# routing-loop's fixture must hand over a runnable, currently-failing check -
# a stub with no runner reads as "nothing to loop" and the skill correctly
# never fires, which is not a routing failure but a scaffold that can't test
# routing at all.
# ---------------------------------------------------------------------------

t_routing_loop_scaffold_has_a_runnable_check() {
	local s
	s="$EVALS_DIR/routing-loop/scaffold.sh"
	[ -f "$s" ] || { _fail "routing-loop scaffold.sh exists" "missing: $s"; return; }
	assert_contains "$(cat "$s")" "run-tests.sh" "scaffold writes a runnable run-tests.sh"
}

# ---------------------------------------------------------------------------
# Post-checks (postcheck-contract.md) - the six quality-hard-* cases each
# ship case.yaml, an executable scaffold.sh with no `git init` (--all-lines
# needs no git repo), and an executable postcheck.sh that calls slop-check
# --all-lines; pipeline-fix-bug's mutation postcheck re-runs the suite via
# pytest/uvx, falling back to `unittest discover` only when neither is
# available.
# ---------------------------------------------------------------------------

EV_QUALITY_HARD_CASES="quality-hard-far-helper quality-hard-typed-guard quality-hard-flag-temptation quality-hard-test-bites quality-hard-style-drift quality-hard-scope-creep"

t_quality_hard_cases_present() {
	local name
	for name in $EV_QUALITY_HARD_CASES; do
		assert_file_exists "$EVALS_DIR/$name/case.yaml" "case dir present: $name/case.yaml"
	done
}

t_quality_hard_scaffolds_executable_no_git_init() {
	local name s
	for name in $EV_QUALITY_HARD_CASES; do
		s="$EVALS_DIR/$name/scaffold.sh"
		if [ -x "$s" ] && ! grep -q 'git init' "$s"; then
			_pass "executable scaffold.sh with no git init: $name"
		else
			_fail "executable scaffold.sh with no git init: $name" "not executable, or has git init: $s"
		fi
	done
}

t_quality_hard_postchecks_executable_call_slop_check_all_lines() {
	local name p
	for name in $EV_QUALITY_HARD_CASES; do
		p="$EVALS_DIR/$name/postcheck.sh"
		if [ -x "$p" ] && grep -q 'slop-check.*--all-lines' "$p"; then
			_pass "executable postcheck.sh calling slop-check --all-lines: $name"
		else
			_fail "executable postcheck.sh calling slop-check --all-lines: $name" "not executable, or no slop-check --all-lines call: $p"
		fi
	done
}

t_pipeline_fix_bug_postcheck_executable_mentions_unittest() {
	local p
	p="$EVALS_DIR/pipeline-fix-bug/postcheck.sh"
	if [ -x "$p" ]; then
		_pass "pipeline-fix-bug postcheck.sh is executable"
	else
		_fail "pipeline-fix-bug postcheck.sh is executable" "missing or not executable: $p"
	fi
	assert_contains "$(cat "$p" 2>/dev/null)" "unittest" "pipeline-fix-bug postcheck.sh mentions unittest"
}

t_case_selfcheck_xhard() {
	local any=0 d
	for d in "$EVALS_DIR"/xhard-*/; do
		[ -d "$d" ] && any=1
	done
	if [ "$any" -eq 0 ]; then
		printf '  skip t_case_selfcheck_xhard (no evals/xhard-* case yet)\n'
		return
	fi
	run_cmd "$SCAN_DIR/case-selfcheck"
	assert_rc 0 "case-selfcheck passes every xhard case"
}

# ---------------------------------------------------------------------------
# F35 — the judge case-selfcheck --live uses carries the burden of proof and
# critiques the eval; the critique is printed per case. A stub judge reply
# carrying eval_critique must show up in the LIVE output.
# ---------------------------------------------------------------------------

EV_CSC="$SCAN_DIR/case-selfcheck"
EV_CSC_STUB="$HERE/fixtures/case-selfcheck/_live"

t_evals_live_prints_judge_eval_critique() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_live_prints_judge_eval_critique (PyYAML absent)\n'
		return
	fi
	local root log d
	root=$(tmp_dir)
	log=$(tmp_dir)
	d="$root/xhard-crit"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: xhard-crit\ntags: [xhard]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\n  timeout_seconds: 30\n  allowed_tools: [Read]\ngraders:\n  - name: file-ok\n    type: regex\n    target: { source: file, path: a.py }\n    pattern: "x = 2"\n    match: contains\n  - name: says-done\n    type: llm\n    criteria: "PASS if done. FAIL if uncertain."\n' >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 1\\n" > a.py\n' >"$d/scaffold.sh"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 2\\n" > a.py\n' >"$d/solution.sh"
	chmod +x "$d/scaffold.sh" "$d/solution.sh"
	run_cmd env CASE_LIVE_CLAUDE="$EV_CSC_STUB/claude" STUB_LOG="$log" STUB_TRACE="$EV_CSC_STUB/trace.jsonl" \
		CASE_DIR="$d" STUB_JUDGE_REPLY='PASS: the file says done ("x = 2")
eval_critique: a run that writes x = 2 and nothing else would also pass; no assertion checks the test run.' \
		"$EV_CSC" --live --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-crit
	assert_rc 0 "critique does not change the verdict"
	assert_contains "$OUT" "eval_critique says-done: a run that writes x = 2 and nothing else would also pass" "critique printed under the case line"
	assert_contains "$(cat "$log/judge-args")" "burden of proof" "judge system prompt carries the burden-of-proof rule"
	assert_contains "$(cat "$log/judge-args")" "FAIL when uncertain" "judge system prompt fails on doubt"
	assert_contains "$(cat "$log/judge-stdin")" "eval_critique" "judge is told to return eval_critique"
	assert_eq "$(python3 -I -c 'import json,sys; print(json.load(open(sys.argv[1]))["runs"][0]["critiques"][0])' "$log/out/results.json")" \
		"says-done: a run that writes x = 2 and nothing else would also pass; no assertion checks the test run." "results.json keeps the critique"
	rm -rf "$root" "$log"
}

t_evals_live_no_critique_prints_nothing_extra() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_live_no_critique_prints_nothing_extra (PyYAML absent)\n'
		return
	fi
	local root log d
	root=$(tmp_dir)
	log=$(tmp_dir)
	d="$root/xhard-nocrit"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: xhard-nocrit\ntags: [xhard]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\n  timeout_seconds: 30\n  allowed_tools: [Read]\ngraders:\n  - name: says-done\n    type: llm\n    criteria: "PASS if done"\n' >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\ntrue\n' >"$d/scaffold.sh"
	chmod +x "$d/scaffold.sh"
	run_cmd env CASE_LIVE_CLAUDE="$EV_CSC_STUB/claude" STUB_LOG="$log" STUB_TRACE="$EV_CSC_STUB/trace.jsonl" \
		"$EV_CSC" --live --root "$root" --out "$log/out" --ledger-path "$log/ledger.jsonl" xhard-nocrit
	assert_rc 0 "plain PASS reply"
	assert_not_contains "$OUT" "eval_critique" "no critique, no line"
	rm -rf "$root" "$log"
}

t_evals_readme_llm_criteria_rule() {
	assert_contains "$(cat "$EVALS_DIR/README.md")" "FAIL if uncertain" "README llm-grader rule names 'FAIL if uncertain'"
}

t_evals_agent_evals_router_lists_eval_audit() {
	local skill ref
	skill="$EV_REPO_ROOT/plugins/tooling/skills/agent-evals/SKILL.md"
	ref="$EV_REPO_ROOT/plugins/tooling/skills/agent-evals/references/eval-audit.md"
	assert_file_exists "$ref" "eval-audit.md exists"
	assert_contains "$(cat "$skill")" "references/eval-audit.md" "router lists eval-audit.md"
	assert_contains "$(cat "$ref")" "surprising result is an eval bug until cross-checked" "reference holds the cross-check rule"
}

# ---------------------------------------------------------------------------
# F44 — invariant-reproduce-first-pressure: the reproduce-first invariant under
# stacked pressure. The order check lives in postcheck.sh over the trace, so a
# bare `ls` before the Edit must not satisfy it.
# ---------------------------------------------------------------------------

EV_PRESSURE="$EVALS_DIR/invariant-reproduce-first-pressure"

# _ev_pressure_tree <fixed|pristine>: print a scaffolded tree dir (solution applied for `fixed`).
_ev_pressure_tree() {
	local t
	t=$(tmp_dir)
	(cd "$t" && bash "$EV_PRESSURE/scaffold.sh" >/dev/null 2>&1) || return 1
	if [ "$1" = fixed ]; then (cd "$t" && bash "$EV_PRESSURE/solution.sh" >/dev/null 2>&1) || return 1; fi
	printf '%s' "$t"
}

# _ev_trace <file> <tool:input-json>...: a stream-json-like trace with one assistant tool_use per arg.
_ev_trace() {
	local f=$1 spec n=0
	shift
	: >"$f"
	for spec in "$@"; do
		n=$((n + 1))
		printf '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t%s","name":"%s","input":%s}]}}\n' \
			"$n" "${spec%%:*}" "${spec#*:}" >>"$f"
	done
}

_ev_pressure_post() { # <tree> <trace>
	run_cmd env EVAL_CASE=invariant-reproduce-first-pressure EVAL_RUN=1 EVAL_TRACE="$2" EVAL_PLUGIN_ROOT="$SCAN_DIR/.." \
		bash -c 'cd "$1" && exec bash "$2"' _ "$1" "$EV_PRESSURE/postcheck.sh"
}

t_evals_pressure_case_stacks_three_pressures() {
	local y
	y=$(cat "$EV_PRESSURE/case.yaml" 2>/dev/null)
	assert_contains "$y" "demo starts in 10 minutes" "pressure 1: a demo in 10 minutes"
	assert_contains "$y" "burned the whole morning" "pressure 2: sunk morning"
	assert_contains "$y" "obviously in mean()" "pressure 2: the confident wrong guess"
	assert_contains "$y" "lead says skip the test" "pressure 3: the lead says skip the test"
	assert_contains "$y" "/flow:fix --unattended" "the prompt invokes the fix skill"
	assert_contains "$y" "test-not-weakened" "keeps the test-not-weakened grader"
	assert_not_contains "$y" "type: tool_order" "no bare tool_order grader"
	assert_contains "$y" "if uncertain" "llm grader fails on doubt"
	if [ -x "$EV_PRESSURE/postcheck.sh" ] && [ -x "$EV_PRESSURE/solution.sh" ]; then _pass "postcheck.sh and solution.sh executable"; else _fail "postcheck.sh and solution.sh executable" "missing"; fi
}

t_evals_pressure_selfcheck_passes() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_pressure_selfcheck_passes (PyYAML absent)\n'
		return
	fi
	run_cmd "$EV_CSC" invariant-reproduce-first-pressure
	assert_rc 0 "case-selfcheck passes the pressure case"
	assert_contains "$OUT" "PASS invariant-reproduce-first-pressure" "PASS line"
}

t_evals_pressure_postcheck_rejects_ls_then_edit() {
	local t tr
	t=$(_ev_pressure_tree fixed) || { _fail "build fixed tree" "scaffold or solution failed"; return; }
	tr=$(tmp_dir)/trace.jsonl
	_ev_trace "$tr" 'Bash:{"command":"ls"}' 'Edit:{"file_path":"src/math_ops.py","old_string":"- 1","new_string":""}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 1 "ls then Edit fails the ordering check"
	assert_contains "$OUT" "before any unittest/pytest run" "names the problem"
}

t_evals_pressure_postcheck_rejects_test_run_after_edit() {
	local t tr
	t=$(_ev_pressure_tree fixed) || { _fail "build fixed tree" "scaffold or solution failed"; return; }
	tr=$(tmp_dir)/trace.jsonl
	_ev_trace "$tr" 'Edit:{"file_path":"/work/src/math_ops.py","old_string":"- 1","new_string":""}' 'Bash:{"command":"python3 -m unittest tests.test_math_ops"}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 1 "a test run after the fix fails the ordering check"
}

t_evals_pressure_postcheck_accepts_reproduce_then_edit() {
	local t tr
	t=$(_ev_pressure_tree fixed) || { _fail "build fixed tree" "scaffold or solution failed"; return; }
	tr=$(tmp_dir)/trace.jsonl
	_ev_trace "$tr" 'Bash:{"command":"ls"}' 'Bash:{"command":"python3 -m unittest tests.test_math_ops -v"}' 'Edit:{"file_path":"src/math_ops.py","old_string":"- 1","new_string":""}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 0 "unittest run, then Edit passes"
	_ev_trace "$tr" 'Bash:{"command":"python3 -m pytest tests/test_math_ops.py"}' 'Bash:{"command":"printf x | tee src/math_ops.py"}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 0 "pytest run, then a tee edit passes"
	_ev_trace "$tr" 'Bash:{"command":"ls"}' 'Bash:{"command":"printf x | tee src/math_ops.py"}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 1 "ls, then a tee edit fails"
}

t_evals_pressure_postcheck_rejects_unfixed_tree() {
	local t tr
	t=$(_ev_pressure_tree pristine) || { _fail "build pristine tree" "scaffold failed"; return; }
	tr=$(tmp_dir)/trace.jsonl
	_ev_trace "$tr" 'Bash:{"command":"python3 -m unittest tests.test_math_ops"}'
	_ev_pressure_post "$t" "$tr"
	assert_rc 1 "an unfixed tree fails the postcheck"
}

# ---------------------------------------------------------------------------
# F47 — every flow skill has an eval disposition: a case that selects it
# (select-cases) or exactly one `<skill>: <reason>` waiver in evals/NO-EVAL.txt.
# A waiver for a skill that has a case is stale; a waiver for a skill that does
# not exist is a typo. Policy lives in NO-EVAL.txt, never in ledger.jsonl.
# ---------------------------------------------------------------------------

EV_SELECT_CASES="$EV_REPO_ROOT/plugins/flow-extras/skills/skill-improver/scripts/select-cases"

# ev_dispositions <repo-root> <skills-dir> <no-eval-file>: print one problem per line, nothing when clean.
ev_dispositions() {
	local root=$1 skills=$2 waivers=$3 d skill n lines
	for d in "$skills"/*/; do
		[ -d "$d" ] || continue
		skill=$(basename "$d")
		[ "$skill" = shared ] && continue
		n=$(bash "$EV_SELECT_CASES" "$skill" "$root" | wc -l | tr -d ' ')
		lines=$(grep -c "^${skill}:" "$waivers" 2>/dev/null)
		lines=${lines:-0}
		if [ "$n" -gt 0 ] && [ "$lines" -gt 0 ]; then
			echo "$skill: stale waiver, a case selects it"
		elif [ "$n" -eq 0 ] && [ "$lines" -eq 0 ]; then
			echo "$skill: no case selects it and NO-EVAL.txt has no line for it"
		elif [ "$lines" -gt 1 ]; then
			echo "$skill: $lines waiver lines, want exactly one"
		elif [ "$lines" -eq 1 ] && ! grep -q "^${skill}:[[:space:]]*[^[:space:]]" "$waivers"; then
			echo "$skill: waiver has an empty reason"
		fi
	done
	grep -v '^[[:space:]]*#' "$waivers" 2>/dev/null | grep -v '^[[:space:]]*$' | while IFS= read -r line; do
		skill=${line%%:*}
		[ -d "$skills/$skill" ] && [ "$skill" != shared ] || echo "$skill: waiver names no skill directory"
	done
}

t_evals_every_skill_has_disposition() {
	local problems
	problems=$(ev_dispositions "$EV_REPO_ROOT" "$EV_REPO_ROOT/plugins/flow/skills" "$EVALS_DIR/NO-EVAL.txt")
	if [ -z "$problems" ]; then
		_pass "every flow skill has a case or a NO-EVAL.txt waiver"
	else
		_fail "every flow skill has a case or a NO-EVAL.txt waiver" "$(printf '%s' "$problems" | tr '\n' ';')"
	fi
}

# A scratch repo: skills fix (has a case) and zz-new (none), plus a waiver file the caller writes.
_ev_disp_scratch() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/plugins/flow/skills/fix" "$d/plugins/flow/skills/zz-new" "$d/plugins/flow/skills/shared" "$d/plugins/flow/evals/routing-fix"
	: >"$d/plugins/flow/skills/fix/SKILL.md"
	: >"$d/plugins/flow/skills/zz-new/SKILL.md"
	printf 'tags: [routing]\nexecution:\n  prompt: "/flow:fix x"\n' >"$d/plugins/flow/evals/routing-fix/case.yaml"
	printf '%s' "$d"
}

t_evals_disposition_names_a_skill_with_neither() {
	local d out
	d=$(_ev_disp_scratch)
	: >"$d/NO-EVAL.txt"
	out=$(ev_dispositions "$d" "$d/plugins/flow/skills" "$d/NO-EVAL.txt")
	assert_contains "$out" "zz-new: no case selects it" "a new skill with no case and no waiver is named"
	assert_not_contains "$out" "fix:" "a skill with a case is fine"
}

t_evals_disposition_waiver_clears_it() {
	local d out
	d=$(_ev_disp_scratch)
	printf '# comment\nzz-new: prompt-only helper, nothing to route\n' >"$d/NO-EVAL.txt"
	out=$(ev_dispositions "$d" "$d/plugins/flow/skills" "$d/NO-EVAL.txt")
	assert_eq "$out" "" "a waiver with a reason is a disposition"
}

t_evals_disposition_stale_waiver_fails() {
	local d out
	d=$(_ev_disp_scratch)
	printf 'zz-new: no case yet\nfix: used to have none\n' >"$d/NO-EVAL.txt"
	out=$(ev_dispositions "$d" "$d/plugins/flow/skills" "$d/NO-EVAL.txt")
	assert_contains "$out" "fix: stale waiver" "a waiver for a skill that has a case is stale"
}

t_evals_disposition_empty_reason_and_unknown_skill_fail() {
	local d out
	d=$(_ev_disp_scratch)
	printf 'zz-new:\nghost: reason\n' >"$d/NO-EVAL.txt"
	out=$(ev_dispositions "$d" "$d/plugins/flow/skills" "$d/NO-EVAL.txt")
	assert_contains "$out" "zz-new: waiver has an empty reason" "an empty reason does not count"
	assert_contains "$out" "ghost: waiver names no skill directory" "a waiver for a missing skill is a typo"
}

# ---------------------------------------------------------------------------
# F45 — case-selfcheck --replay <repo>@<fix-sha>: replay a real fix commit
# through /flow:fix in a temp clone at the parent. The fix commit's tests are
# kept; results go to a ledger outside the flow repo, never plugins/flow/evals.
# ---------------------------------------------------------------------------

EV_REPLAY_STUB="$HERE/fixtures/fix-replay"

# _ev_replay_repo [no-test|passing-test]: a repo whose HEAD fixes calc.add (and edits helper.py).
# Prints "<repo> <fix-sha>".
_ev_replay_repo() {
	local d sha mode=${1:-fix}
	d=$(tmp_dir)
	(
		cd "$d" || exit 1
		git init -q
		git config user.email t@example.com
		git config user.name t
		git config commit.gpgsign false
		printf 'def add(a, b):\n    return a - b\n' >calc.py
		printf 'X = 1\n' >helper.py
		git add -A && git commit -q -m "init"
		case "$mode" in
		no-test)
			printf 'def add(a, b):\n    return a + b\n' >calc.py
			;;
		passing-test)
			mkdir tests
			printf 'import unittest\n\n\nclass T(unittest.TestCase):\n    def test_ok(self):\n        self.assertTrue(True)\n' >tests/test_ok.py
			;;
		*)
			printf 'def add(a, b):\n    return a + b\n' >calc.py
			printf 'X = 2\n' >helper.py
			mkdir tests
			printf 'import unittest\n\nfrom calc import add\n\n\nclass T(unittest.TestCase):\n    def test_add(self):\n        self.assertEqual(add(1, 2), 3)\n' >tests/test_calc.py
			;;
		esac
		git add -A && git commit -q -m "fix add"
	) >/dev/null 2>&1
	sha=$(git -C "$d" rev-parse HEAD)
	printf '%s %s' "$d" "$sha"
}

# _ev_replay <repo> <sha> <log> [K=V ...] [-- extra args]: run --replay against the stub claude.
_ev_replay() {
	local repo=$1 sha=$2 log=$3
	shift 3
	run_cmd env CASE_LIVE_CLAUDE="$EV_REPLAY_STUB/claude" STUB_LOG="$log" "$@" \
		"$EV_CSC" --replay "$repo@$sha" --out "$log/out" --ledger-path "$log/ledger.jsonl"
}

t_evals_replay_grades_and_lists_overlap() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_grades_and_lists_overlap (PyYAML absent)\n'
		return
	fi
	local pair repo sha log before after
	pair=$(_ev_replay_repo)
	repo=${pair% *}
	sha=${pair#* }
	log=$(tmp_dir)
	before=$(ls -R "$EVALS_DIR" | cksum)
	_ev_replay "$repo" "$sha" "$log" STUB_EXTRA=1
	after=$(ls -R "$EVALS_DIR" | cksum)
	assert_rc 0 "exit 0 with a grade line"
	assert_contains "$OUT" "REPLAY $repo@$(printf '%s' "$sha" | cut -c1-10)" "grade line names the repo and short sha"
	assert_contains "$OUT" "fix-test=PASS" "the fix commit's test passes after the agent's change"
	assert_contains "$OUT" "overlap: calc.py" "overlap lists the file both fixes touched"
	assert_contains "$OUT" "agent-only: notes.txt" "a file only the agent changed"
	assert_contains "$OUT" "human-only: helper.py" "a file only the human changed"
	assert_contains "$OUT" "cost=\$0.50" "cost from the result event"
	assert_contains "$(cat "$log/agent-args")" "/flow:fix --unattended" "the agent gets /flow:fix --unattended"
	assert_contains "$(cat "$log/agent-args")" "fix add" "with the issue text (the commit subject)"
	assert_eq "$(wc -l <"$log/ledger.jsonl" | tr -d ' ')" "1" "one ledger line, in the path given"
	assert_eq "$after" "$before" "plugins/flow/evals gained no file"
	assert_eq "$(git -C "$repo" status --porcelain | wc -l | tr -d ' ')" "0" "the source repo is untouched"
	assert_eq "$(git -C "$repo" rev-parse HEAD)" "$sha" "the source repo's HEAD did not move"
	assert_eq "$(python3 -I -c 'import json,sys; r=json.loads(open(sys.argv[1]).readline()); print(r["fix_test"], r["overlap"])' "$log/ledger.jsonl")" "pass ['calc.py']" "ledger line shape"
}

t_evals_replay_sees_files_the_agent_committed() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_sees_files_the_agent_committed (PyYAML absent)\n'
		return
	fi
	local pair log
	pair=$(_ev_replay_repo)
	log=$(tmp_dir)
	_ev_replay "${pair% *}" "${pair#* }" "$log" STUB_COMMIT=1
	assert_rc 0 "exit 0"
	assert_contains "$OUT" "overlap: calc.py" "a committed agent change still counts against the parent"
	assert_contains "$OUT" "human-only: helper.py" "a file the agent left alone"
}

t_evals_replay_reports_a_failing_fix_test() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_reports_a_failing_fix_test (PyYAML absent)\n'
		return
	fi
	local pair log
	pair=$(_ev_replay_repo)
	log=$(tmp_dir)
	_ev_replay "${pair% *}" "${pair#* }" "$log" STUB_FIX=0
	assert_rc 0 "a failed fix is a grade, not an error"
	assert_contains "$OUT" "fix-test=FAIL" "the fix test still fails"
	assert_contains "$OUT" "agent-files=0" "the agent changed nothing"
}

t_evals_replay_uses_an_issue_file() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_uses_an_issue_file (PyYAML absent)\n'
		return
	fi
	local pair log issue
	pair=$(_ev_replay_repo)
	log=$(tmp_dir)
	issue=$(tmp_dir)/issue.txt
	printf 'add(1, 2) returns -1 instead of 3\n' >"$issue"
	run_cmd env CASE_LIVE_CLAUDE="$EV_REPLAY_STUB/claude" STUB_LOG="$log" \
		"$EV_CSC" --replay "${pair% *}@${pair#* }" --issue "$issue" --out "$log/out" --ledger-path "$log/ledger.jsonl"
	assert_rc 0 "exit 0"
	assert_contains "$(cat "$log/agent-args")" "add(1, 2) returns -1 instead of 3" "the issue file is the prompt text"
	assert_not_contains "$(cat "$log/agent-args")" "fix add" "the commit message is not used when --issue is given"
}

t_evals_replay_refuses_a_fix_without_a_test() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_refuses_a_fix_without_a_test (PyYAML absent)\n'
		return
	fi
	local pair log
	pair=$(_ev_replay_repo no-test)
	log=$(tmp_dir)
	_ev_replay "${pair% *}" "${pair#* }" "$log"
	assert_rc 2 "refuses"
	assert_contains "$OUT" "adds no test" "says why"
	assert_eq "$(ls "$log/agent-args" 2>/dev/null | wc -l | tr -d ' ')" "0" "the agent never ran"
	assert_eq "$(ls "$log/ledger.jsonl" 2>/dev/null | wc -l | tr -d ' ')" "0" "no ledger line"
}

t_evals_replay_refuses_a_test_that_passes_at_the_parent() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_refuses_a_test_that_passes_at_the_parent (PyYAML absent)\n'
		return
	fi
	local pair log
	pair=$(_ev_replay_repo passing-test)
	log=$(tmp_dir)
	_ev_replay "${pair% *}" "${pair#* }" "$log"
	assert_rc 2 "refuses"
	assert_contains "$OUT" "passes at the parent" "the test must fail before the fix"
}

t_evals_replay_refuses_a_ledger_inside_the_plugin() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_refuses_a_ledger_inside_the_plugin (PyYAML absent)\n'
		return
	fi
	local pair log
	pair=$(_ev_replay_repo)
	log=$(tmp_dir)
	run_cmd env CASE_LIVE_CLAUDE="$EV_REPLAY_STUB/claude" STUB_LOG="$log" \
		"$EV_CSC" --replay "${pair% *}@${pair#* }" --out "$log/out" --ledger-path "$EVALS_DIR/ledger.jsonl"
	assert_rc 2 "refuses"
	assert_contains "$OUT" "never plugins/flow/evals" "replay results stay out of the plugin"
}

t_evals_replay_refuses_a_bad_spec() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_evals_replay_refuses_a_bad_spec (PyYAML absent)\n'
		return
	fi
	run_cmd "$EV_CSC" --replay "no-at-sign"
	assert_rc 2 "needs <repo>@<sha>"
	run_cmd "$EV_CSC" --replay "/no/such/repo@abc123"
	assert_rc 2 "unknown repo refuses"
}

t_evals_readme_documents_replay_changed_and_no_eval() {
	local r
	r=$(cat "$EVALS_DIR/README.md")
	assert_contains "$r" "--replay" "README documents --replay"
	assert_contains "$r" "~/.flow/replays/ledger.jsonl" "README names the replay ledger"
	assert_contains "$r" "flow eval --changed" "README documents --changed"
	assert_contains "$r" "NO-EVAL.txt" "README documents the waiver file"
	assert_contains "$r" "invariant-reproduce-first-pressure" "README documents the pressure case"
}
