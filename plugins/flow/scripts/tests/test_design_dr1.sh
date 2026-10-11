#!/usr/bin/env bash
# test_design_dr1.sh — design plugin text rules from the famous-repos round:
# polish fix loop, optimize.md measurement honesty, react-performance.csv
# refresh, anti-patterns P-5, ui-animation view transitions and state rules.
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_dr1_.

DR1_DESIGN="$SCAN_DIR/../../design/skills"
DR1_POLISH="$DR1_DESIGN/polish/SKILL.md"
DR1_OPT="$DR1_DESIGN/impeccable/reference/optimize.md"
DR1_CSV="$DR1_DESIGN/ui-ux-pro-max/data/react-performance.csv"
DR1_ANTI="$DR1_DESIGN/design/references/anti-patterns.md"
DR1_ANIM="$DR1_DESIGN/ui-animation/SKILL.md"
DR1_VT="$DR1_DESIGN/ui-animation/references/react-view-transitions.md"
DR1_DF="$DR1_DESIGN/ui-animation/references/decision-framework.md"

_dr1_count() { grep -c -- "$1" "$2" || true; }

t_dr1_polish_fix_loop_rules() {
	local t
	t=$(cat "$DR1_POLISH")
	assert_contains "$t" "## Fix loop" "polish has a Fix loop section"
	assert_contains "$t" "-- <paths>" "polish commits with a pathspec"
	assert_contains "$t" "best-effort" "polish names best-effort status"
	assert_contains "$t" "20%" "polish risk threshold"
	assert_contains "$t" "30 fixes" "polish hard cap"
	assert_contains "$t" "git revert <" "polish reverts a named sha"
	assert_contains "$t" "git status --porcelain" "polish checks for user edits first"
	assert_contains "$t" "adapted from garrytan/gstack design-review/SKILL.md.tmpl @ 5b9b837 (MIT)" "polish credit line"
}

t_dr1_polish_no_unsafe_git() {
	assert_eq "$(grep -n 'git add -A\|git add \.\|revert HEAD' "$DR1_POLISH" || true)" "" "polish has no blanket add or revert HEAD"
}

t_dr1_optimize_measurement_honesty() {
	local t
	t=$(cat "$DR1_OPT")
	assert_contains "$t" "not measured" "optimize marks unmeasured metrics"
	assert_contains "$t" "potential impact" "optimize labels unmeasured findings"
	assert_contains "$t" "React Compiler" "optimize carries the React Compiler caveat"
	assert_contains "$t" "adapted from addyosmani/agent-skills agents/web-performance-auditor.md @ 1be8e34 (MIT)" "optimize credit addy"
	assert_contains "$t" "adapted from vercel-labs/agent-skills skills/react-best-practices @ 063bee9 (MIT)" "optimize credit vercel"
	assert_eq "$(grep -n -i 'useMemo()` and `useCallback()` for expensive\|avoid inline function creation' "$DR1_OPT" || true)" "" "optimize dropped blanket memo advice"
}

t_dr1_csv_pruned_and_current() {
	assert_eq "$(grep -ci uselatest "$DR1_CSV" || true)" "0" "no useLatest wording"
	assert_eq "$(_dr1_count ',JS Perf,' "$DR1_CSV")" "2" "two JS Perf rows kept"
	local n
	n=$(_dr1_count 'React Compiler' "$DR1_CSV")
	if [ "$n" -ge 2 ]; then _pass "csv carries React Compiler caveat in >= 2 rows"; else _fail "csv React Compiler rows" "got $n"; fi
	assert_contains "$(cat "$DR1_CSV")" "useEffectEvent for Stable Callback Refs" "csv row renamed to upstream title"
}

t_dr1_csv_parses_contiguous() {
	local out
	out=$(python3 -I -c '
import csv, sys
rows = list(csv.reader(open(sys.argv[1], newline="")))
w = len(rows[0])
bad = [i + 1 for i, r in enumerate(rows) if len(r) != w]
nums = [r[0] for r in rows[1:]]
ok = nums == [str(i) for i in range(1, len(nums) + 1)]
print("width=%d bad=%s contiguous=%s" % (w, bad, ok))
' "$DR1_CSV")
	assert_eq "$out" "width=11 bad=[] contiguous=True" "csv is 11 columns everywhere and No. is contiguous"
}

t_dr1_csv_search_finds_module_state() {
	local out
	out=$(python3 "$DR1_DESIGN/ui-ux-pro-max/scripts/search.py" "module state" --domain react 2>&1 || true)
	assert_contains "$out" "Shared Module State" "search finds the module state row"
}

t_dr1_anti_patterns_p5() {
	assert_eq "$(_dr1_count 'P-5: Wrong-theme flash' "$DR1_ANTI")" "1" "P-5 appears once"
	assert_eq "$(_dr1_count 'leaked-render' "$DR1_ANTI")" "0" "leaked-render half left out"
	assert_contains "$(cat "$DR1_ANTI")" "suppressHydrationWarning" "P-5 names the hydration attribute"
}

t_dr1_view_transitions_reference() {
	assert_file_exists "$DR1_VT" "view transitions reference exists"
	local first
	first=$(sed -n '1,14p' "$DR1_VT" 2>/dev/null)
	assert_contains "$first" "react@canary" "first section names the React channel"
	assert_contains "$(cat "$DR1_ANIM")" "references/react-view-transitions.md" "ui-animation load table lists it"
	assert_contains "$(cat "$DR1_VT" 2>/dev/null)" "adapted from vercel-labs/agent-skills react-view-transitions @ 063bee9 (MIT)" "view transitions credit"
}

t_dr1_decision_framework_state_rules() {
	local t
	t=$(cat "$DR1_DF")
	assert_contains "$t" "constant slot" "slot padding principle"
	assert_contains "$t" "derive" "derived visuals principle"
	assert_eq "$(_dr1_count useSharedValue "$DR1_DF")" "0" "no RN API in the neutral rule"
}
