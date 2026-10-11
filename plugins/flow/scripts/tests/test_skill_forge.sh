#!/usr/bin/env bash
# test_skill_forge.sh — prose assertions for skill-forge/SKILL.md's
# Step 0 reuse check (B10). Sourced by run.sh; HERE (this dir) and SCAN_DIR
# (its parent, "scripts/") are already set. Tests prefixed t_forge_.
# skill-forge lives in the sibling flow-extras plugin.

FORGE_SKILL="$SCAN_DIR/../../flow-extras/skills/skill-forge/SKILL.md"

# _forge_content → full content of skill-forge/SKILL.md
_forge_content() {
	cat "$FORGE_SKILL"
}

# _forge_process_block → content of "## The Process" section, stopping
# before Step 0's own heading (and before Step 1, as a fallback if Step 0
# is missing) — isolates the short mention from the dedicated section.
_forge_process_block() {
	awk '
    /^## The Process/ { f=1 }
    /^## Step 0/ { exit }
    /^## Step 1/ { exit }
    f { print }
  ' "$FORGE_SKILL"
}

t_forge_step0_precedes_step1() {
	local step0_line step1_line
	step0_line=$(grep -n '^## Step 0: Reuse check' "$FORGE_SKILL" | head -1 | cut -d: -f1)
	step1_line=$(grep -n '^## Step 1: Research' "$FORGE_SKILL" | head -1 | cut -d: -f1)
	if [ -n "$step0_line" ] && [ -n "$step1_line" ] && [ "$step0_line" -lt "$step1_line" ]; then
		_pass "SKILL.md's Step 0 heading precedes Step 1"
	else
		_fail "SKILL.md's Step 0 heading precedes Step 1" \
			"Step 0 at line '$step0_line', Step 1 at line '$step1_line'"
	fi
}

t_forge_process_overview_mentions_step0() {
	assert_contains "$(_forge_process_block)" 'Step 0' \
		"## The Process overview names Step 0 before its own heading"
}

t_forge_reuse_check_greps_skill_dirs() {
	local content
	content=$(_forge_content)
	assert_contains "$content" 'grep -ril' \
		"Step 0 searches existing skills with grep -ril"
	assert_contains "$content" 'plugins/*/skills/*/SKILL.md' \
		"Step 0 searches plugin skills"
	assert_contains "$content" '~'/.claude/skills/'*'/SKILL.md \
		"Step 0 searches user-level skills"
	assert_contains "$content" '~'/.claude/skills/'*'/skills/'*'/SKILL.md \
		"Step 0 searches nested user-level skills"
}

t_forge_close_match_offers_three_choices() {
	local content
	content=$(_forge_content)
	assert_contains "$content" 'STOPS before Step 1' \
		"a close match stops the pipeline before Step 1"
	assert_contains "$content" 'use the existing skill' \
		"choice 1: use the existing skill"
	assert_contains "$content" 'skill-improver' \
		"choice 2: improve it with skill-improver"
	assert_contains "$content" 'build fresh anyway' \
		"choice 3: build fresh anyway"
}

t_forge_no_close_match_prints_receipt_line() {
	assert_contains "$(_forge_content)" \
		'reuse check: searched <terms> in <dirs>; nothing close' \
		"no close match prints the one-line reuse-check receipt"
}

# ---- flow-extras round 2: ultracode standing orders / hand-made oracle,
# skill-improver eval step, benchmark-checklist absolute budget ----

EXTRAS_DIR="$SCAN_DIR/../../flow-extras/skills"

t_forge_ultracode_standing_orders() {
	assert_contains "$(cat "$EXTRAS_DIR/ultracode/references/spec-template.md")" '## Standing orders' \
		"spec-template has the Standing orders heading"
	local skill
	skill=$(cat "$EXTRAS_DIR/ultracode/SKILL.md")
	assert_contains "$skill" 'append it there before acting on it' \
		"ultracode appends a mid-run directive before acting"
	assert_contains "$skill" 'every brief, respawn and fix-round prompt' \
		"ultracode pastes standing orders into every spawn"
}

t_forge_ultracode_script_oracle() {
	local skill
	skill=$(cat "$EXTRAS_DIR/ultracode/SKILL.md")
	assert_contains "$skill" 'Do unit 1 by hand and commit it' \
		"script-before-fleet hand-does unit 1"
	assert_contains "$skill" 'scratch worktree' \
		"the tool runs on unit 1 in a scratch worktree"
	assert_contains "$skill" 'The diff must be empty, or each hunk must be explained in SPEC.md' \
		"diff must be empty or explained before the wide run"
}

t_forge_benchmark_absolute_budget() {
	assert_contains "$(cat "$EXTRAS_DIR/benchmark-checklist/SKILL.md")" \
		'If the baseline does not have the feature, there is no ratio' \
		"benchmark question 2 refuses a ratio against a missing baseline"
}

t_forge_improver_eval_step() {
	local skill
	skill=$(cat "$EXTRAS_DIR/skill-improver/SKILL.md")
	assert_contains "$skill" '### Step 2f' "skill-improver has a final eval step"
	assert_contains "$skill" 'flow eval --case <name>... --runs 3' "step runs flow eval --case with 3 runs"
	assert_contains "$skill" 'base=<score> edit=<score>' "step prints base and edit scores"
	assert_contains "$skill" 'no eval cases for <skill>' "step prints one line when nothing is selected"
}

t_forge_improver_select_cases() {
	local sel="$EXTRAS_DIR/skill-improver/scripts/select-cases"
	local root out
	root="$(cd "$SCAN_DIR/../../.." && pwd)"
	out=$("$sel" fix "$root")
	assert_contains "$out" 'evals/routing-fix/case.yaml' "fix selects routing-fix"
	assert_contains "$out" 'evals/pipeline-fix-bug/case.yaml' "fix selects pipeline-fix-bug"
	assert_not_contains "$out" 'evals/routing-audit/case.yaml' \
		"a case that lists fix among wrong answers is not selected"
	assert_eq "$("$sel" no-such-skill-xyz "$root")" "" "a skill with no cases prints nothing"
}

t_forge_close_match_reads_body_and_quotes_path_line() {
	local step0
	step0=$(awk '/^## Step 0/{f=1;next} /^## Step 1/{exit} f' "$FORGE_SKILL")
	assert_contains "$step0" "body of each candidate's SKILL.md" \
		"Step 0 reads each candidate's SKILL.md body before declaring a close match"
	assert_contains "$step0" 'path:line' \
		"Step 0 quotes the path:line that covers the core trigger in the three-choice prompt"
}

# ---- famous-repos round G3: F28-F31, F116, F247 ----

JUDGE_SKILL="$EXTRAS_DIR/skill-judge/SKILL.md"
SPEC_JUDGE_SKILL="$SCAN_DIR/../skills/spec-judge/SKILL.md"
WFA="$EXTRAS_DIR/skill-improver/references/writing-for-agents.md"

t_forge_form_table_in_writing_for_agents() {
	local w
	w=$(cat "$WFA")
	assert_contains "$w" '| Skips a step under pressure' "form table row: skips under pressure"
	assert_contains "$w" '**Prohibition** plus a rationalization row' "form table: prohibition plus rationalization rows"
	assert_contains "$w" '**Positive recipe**' "form table row: wrong shape -> positive recipe"
	assert_contains "$w" '**Template slot**' "form table row: omitted element -> template slot"
	assert_contains "$w" '**Conditional keyed on an observable predicate**' "form table row: conditional"
	assert_contains "$w" 'no nuance clauses' "the no-nuance-clause rule"
	assert_contains "$w" 'exemption clauses do not scope a rule' "the exemption-clause rule"
	assert_contains "$w" 'control arm first' "the form table points to the control arm"
}

t_forge_micro_test_and_miss_classes() {
	local f
	f=$(cat "$FORGE_SKILL")
	assert_contains "$f" 'control arm first' "skill-forge runs the control arm first for a prohibition"
	assert_contains "$f" 'no rule lands if the control does not fail' "no rule lands without a failing control"
	assert_contains "$f" '5 or more reps per arm' "micro-test uses 5 or more reps per arm"
	assert_contains "$f" 'it does not replace it' "the micro-test extends Step 1d"
	assert_contains "$f" '"a baseline failure" alone no longer counts for a prohibition' "D3 row needs a micro-test result for a new NEVER line"
	assert_contains "$f" '`clear-but-ignored`' "miss class: clear-but-ignored"
	assert_contains "$f" '`should-have-said-X`' "miss class: should-have-said-X"
	assert_contains "$f" "\`didn't-see-section-Y\`" "miss class: didn't-see-section-Y"
	assert_contains "$f" '`miss: <class>`' "the changelog format requires miss: <class>"
}

t_forge_authoring_rules_for_scripts_and_library_skills() {
	local f
	f=$(cat "$FORGE_SKILL")
	assert_contains "$f" 'run a bundled script with `--help` instead of reading its source' "run scripts with --help"
	assert_contains "$f" 'prints the exact manual next step' "scripts print the manual next step"
	assert_contains "$f" 'What <X> does NOT have' "library skills get a does-NOT-have section"
	assert_contains "$f" 'stale-prior table' "library skills get a stale-prior table"
	assert_contains "$f" 'set -euo pipefail' "bash scripts use set -euo pipefail"
	assert_contains "$f" 'cleanup `trap`' "bash scripts install a cleanup trap"
	assert_contains "$f" "Script rung" "the I/O rule cites lesson's Script rung"
	assert_contains "$f" '20 or more rules' "catalog shape for 20+ rules"
	assert_not_contains "$f" 'JSON to stdout' "no blanket JSON-to-stdout rule contradicting lesson's Script rung"
	assert_contains "$(cat "$JUDGE_SKILL")" 'does NOT have' "skill-judge D3 checks library skills for a does-NOT-have section"
}

# _total_cmd FILE -> the shared total command from a judge file, with the placeholder left in
_total_cmd() {
	grep -m1 "^node -e 'const s=JSON.parse" "$1"
}

# _total FILE JSON [CAP] -> run the file's own command on JSON
_total() {
	local cmd
	cmd=$(_total_cmd "$1")
	cmd=${cmd%% \'<dimension*}
	if [ -n "${3:-}" ]; then
		bash -c "$cmd"' "$1" "$2"' _ "$2" "$3"
	else
		bash -c "$cmd"' "$1"' _ "$2"
	fi
}

t_forge_total_command_is_scripted() {
	local f c ref
	ref=$(_total_cmd "$FORGE_SKILL")
	assert_contains "$ref" 'reduce((a,b)=>a+b,0)' "skill-forge contains the total command"
	for f in "$FORGE_SKILL" "$JUDGE_SKILL" "$SPEC_JUDGE_SKILL"; do
		c=$(_total_cmd "$f")
		assert_eq "$c" "$ref" "$(basename "$(dirname "$f")") carries the identical total command"
	done
	assert_contains "$(cat "$FORGE_SKILL")" 'never compared against 96' "skill-forge never compares a hand-written total to 96"
	assert_eq "$(_total "$JUDGE_SKILL" '{"D1":18,"D2":13,"D3":12,"D4":12,"D5":12,"D6":12,"D7":9,"D8":9}')" "97" "eight scores summing to 97 give exactly 97"
	assert_eq "$(_total "$JUDGE_SKILL" '{"D1":18,"D2":13,"D3":12,"D4":12,"D5":12,"D6":12,"D7":9,"D8":9}' 95)" "95" "a failed pre-check caps the skill-judge total at 95"
	assert_eq "$(_total "$JUDGE_SKILL" '{"D1":10,"D2":10,"D3":10,"D4":10,"D5":10,"D6":10,"D7":5,"D8":5}' 95)" "70" "the cap does not raise a lower total"
	assert_eq "$(_total "$SPEC_JUDGE_SKILL" '{"slice":35,"afk":20,"dep":15,"trace":20,"gran":10}')" "100" "five D-Slice dimensions sum to 100"
	assert_eq "$(_total "$SPEC_JUDGE_SKILL" '{"slice":35,"afk":20,"dep":15,"trace":20,"gran":10}' 50)" "50" "the horizontal-slice flag caps the spec-judge total at 50"
	assert_contains "$(cat "$SPEC_JUDGE_SKILL")" 'passing `50` as the cap' "spec-judge applies the horizontal cap in the command"
}

t_forge_judge_live_fetch_precheck() {
	local d pat
	pat='WebFetch|curl |wget |raw\.githubusercontent|/(main|master|HEAD)/'
	assert_contains "$(cat "$JUDGE_SKILL")" "$pat" "skill-judge carries the pre-check (c) grep"
	assert_contains "$(cat "$JUDGE_SKILL")" '(c) Live-fetched rules' "skill-judge Step 0 has pre-check (c)"
	assert_contains "$(cat "$JUDGE_SKILL")" 'the scored text is not the text that runs' "pre-check (c) says why it fails"
	assert_contains "$(cat "$JUDGE_SKILL")" 'caps the total at 95' "pre-check (c) shares the 95 cap"
	d=$(tmp_dir)
	mkdir -p "$d/bad" "$d/good"
	printf 'Use WebFetch to get https://raw.githubusercontent.com/o/r/main/rules.md\n' >"$d/bad/SKILL.md"
	printf 'Read references/rules.md before reviewing.\n' >"$d/good/SKILL.md"
	run_cmd grep -nE "$pat" "$d/bad/SKILL.md"
	assert_rc 0 "the pre-check grep hits a live-fetching skill"
	run_cmd grep -nE "$pat" "$d/good/SKILL.md"
	assert_rc 1 "the pre-check grep passes a skill with no fetch"
	rm -rf "$d"
}

# --- famous-borrows G4: trigger eval (F32), pairwise A/B (F42), clean-surface
# exit and script bundling (F43), review page (F50), D4 trigger types (F27) ---

_SI_DIR="$EXTRAS_DIR/skill-improver"

t_forge_trigger_eval_fixture_tests() {
	run_cmd python3 -I "$_SI_DIR/scripts/test_trigger_eval.py"
	assert_rc 0 "trigger-eval and optimise-description fixture tests pass (stubbed claude)"
}

t_forge_trigger_eval_wired_in() {
	local improver forge judge
	improver=$(cat "$_SI_DIR/SKILL.md")
	forge=$(cat "$FORGE_SKILL")
	judge=$(cat "$EXTRAS_DIR/skill-judge/SKILL.md")
	assert_contains "$improver" 'scripts/trigger-eval' "improver activation branch names trigger-eval"
	assert_contains "$improver" 'scripts/optimise-description' "improver names optimise-description"
	assert_contains "$improver" 'fewer than 2 queries' "improver reports a held-out win under 2 queries as noise"
	assert_contains "$forge" 'skill-improver/scripts/trigger-eval' "forge Step 5 points at trigger-eval"
	assert_not_contains "$forge" "skill-creator skill's \`run_loop.py\`" "forge no longer points at skill-creator run_loop"
	assert_contains "$judge" 'trigger.json' "judge D4 cites the recorded trigger.json"
	assert_file_exists "$_SI_DIR/scripts/trigger-eval" "trigger-eval exists"
	assert_file_exists "$_SI_DIR/scripts/optimise-description" "optimise-description exists"
	[ -x "$_SI_DIR/scripts/trigger-eval" ] && [ -x "$_SI_DIR/scripts/optimise-description" ] &&
		[ -x "$_SI_DIR/scripts/review-page" ] &&
		_pass "all three scripts are executable" || _fail "all three scripts are executable" "mode bits missing"
}

t_forge_pairwise_ab_rule() {
	local improver
	improver=$(cat "$_SI_DIR/SKILL.md")
	assert_contains "$improver" 'rubric before' "2f writes the rubric before seeing any output"
	assert_contains "$improver" 'order swapped' "2f runs a second judge with the order swapped"
	assert_contains "$improver" 'A split verdict is a tie' "2f treats a split verdict as a tie"
	assert_contains "$improver" 'no base/edit labels' "2f hides which output is the edit"
}

t_forge_no_change_and_bundle_rules() {
	local improver n
	improver=$(cat "$_SI_DIR/SKILL.md")
	assert_contains "$improver" 'no change: <what was checked>' "2b names the clean-surface exit"
	assert_contains "$improver" 'written in 2 or more runs' "2f flags a helper rewritten across runs"
	assert_contains "$improver" 'separate flagged opportunity' "bundling is a flagged opportunity, not a budget edit"
	n=$(wc -l <"$_SI_DIR/SKILL.md" | tr -d ' ')
	[ "$n" -lt 300 ] && _pass "skill-improver body stays under 300 lines ($n)" ||
		_fail "skill-improver body stays under 300 lines" "$n lines"
}

t_forge_review_page_dry_run() {
	local d rp out
	rp="$_SI_DIR/scripts/review-page"
	d=$(tmp_dir)
	mkdir -p "$d/i1/1" "$d/i1/2" "$d/i2/1" "$d/i2/2"
	printf 'one v1\n' >"$d/i1/1/output.md"
	printf 'two v1\n' >"$d/i1/2/output.md"
	printf 'one v2\n' >"$d/i2/1/output.md"
	printf 'two v2\n' >"$d/i2/2/output.md"
	run_cmd python3 -I "$rp" render --prev "$d/i1" --curr "$d/i2" --out "$d/page.html"
	assert_rc 0 "review-page renders a two-case dry run"
	out=$(cat "$d/page.html")
	assert_contains "$out" 'one v1' "page shows iteration N-1 of case 1"
	assert_contains "$out" 'one v2' "page shows iteration N of case 1"
	assert_contains "$out" 'two v1' "page shows iteration N-1 of case 2"
	assert_contains "$out" 'two v2' "page shows iteration N of case 2"
	printf '[{"case":"1","comment":"too busy"},{"case":"2","comment":""}]\n' >"$d/fb.json"
	out=$(python3 -I "$rp" comments "$d/fb.json")
	assert_contains "$out" '"case": "1"' "the comment on case 1 comes back as a case"
	assert_contains "$out" 'too busy' "with its comment text"
	assert_not_contains "$out" '"case": "2"' "case 2 has no comment and is not listed"
	mkdir -p "$d/i3"
	out=$(python3 -I "$rp" carry --from "$d/i2" --to "$d/i3" --feedback "$d/fb.json")
	assert_eq "$out" "1" "carry lists only the commented case for editing"
	assert_file_missing "$d/i3/1/output.md" "the commented case is not carried"
	cmp -s "$d/i2/2/output.md" "$d/i3/2/output.md" &&
		_pass "case 2 output is byte-identical in the next iteration" ||
		_fail "case 2 output is byte-identical in the next iteration" "differs or missing"
	rm -rf "$d"
}

t_forge_review_page_on_request_only() {
	local improver
	improver=$(cat "$_SI_DIR/SKILL.md")
	assert_contains "$improver" 'scripts/review-page' "improver names the review page script"
	assert_contains "$improver" 'only when the user asks for a human pass' "review page runs only on request"
	assert_file_exists "$_SI_DIR/assets/review-page.html" "review page template exists"
}

t_forge_d4_trigger_types_item() {
	local judge
	judge=$(cat "$EXTRAS_DIR/skill-judge/SKILL.md")
	assert_contains "$judge" 'at least one implicit or proactive situation' "D4 checklist asks for an implicit situation"
	assert_contains "$(cat "$FORGE_SKILL")" 'implicit or proactive situation' "forge 2d drafting names the trigger types"
}
