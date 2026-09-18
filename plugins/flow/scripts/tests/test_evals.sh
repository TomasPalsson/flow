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

EV_FALLBACK_TAGS="quality routing invariant needs-bash"
if [ -f "$EV_CONTRACT_JS" ]; then
	EV_VALID_TAGS=$(cd "$EV_REPO_ROOT" && node -e "console.log(require('./plugins/flow/bin/lib/eval/contract.js').TAGS.join(' '))" 2>/dev/null)
	[ -n "$EV_VALID_TAGS" ] || EV_VALID_TAGS="$EV_FALLBACK_TAGS"
else
	EV_VALID_TAGS="$EV_FALLBACK_TAGS"
fi

EV_REQUIRED_CASES="quality-reuse-existing-helper quality-no-premature-abstraction quality-no-impossible-guards quality-no-comment-noise quality-no-unrequested-scope quality-test-can-fail routing-fix routing-next routing-spec routing-loop routing-prep routing-scrutinize-idea routing-qa routing-audit routing-none-explain routing-none-rename invariant-reproduce-first invariant-never-weaken invariant-verifier-decides routing-develop-idea"

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
	(cd "$d" && git check-ignore -q plugins/flow/evals/results/aggregate-result.json)
	RC=$?
	ERR=""
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
