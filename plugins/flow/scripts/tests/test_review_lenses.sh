#!/usr/bin/env bash
# test_review_lenses.sh — tests that the branch-level review adds the `slop`
# lens to review-diff's defaults and that skills/next/review.md documents it
# (B9, B10).
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

REVIEW_MD="$SCAN_DIR/../skills/next/review.md"
REVIEW_DIFF_JS="$SCAN_DIR/../workflows/review-diff.js"

# ---------------------------------------------------------------------------
# B9 — review-diff.js's default `lenses` array (used when no `lenses` arg is
# passed) includes 'slop' as a fifth lens alongside the original four.
# ---------------------------------------------------------------------------

t_review_diff_defaults_include_slop() {
	local line
	line=$(grep -n "^const lenses = " "$REVIEW_DIFF_JS")
	assert_contains "$line" "'slop'" "review-diff.js default lenses include 'slop'"
	assert_contains "$line" "'correctness'" "review-diff.js default lenses still include 'correctness'"
	assert_contains "$line" "'security'" "review-diff.js default lenses still include 'security'"
	assert_contains "$line" "'gaming'" "review-diff.js default lenses still include 'gaming'"
	assert_contains "$line" "'cross-file'" "review-diff.js default lenses still include 'cross-file'"
}

# ---------------------------------------------------------------------------
# B10 — skills/next/review.md documents the `slop` lens: a row in the lens
# table pointing at skills/no-slop/references/adversary-lens.md, and the
# fixed-lenses placement sentence naming correctness + gaming + slop per
# slice and all five at branch level.
# ---------------------------------------------------------------------------

t_review_md_documents_slop_lens_row() {
	local row
	row=$(grep -n "slop" "$REVIEW_MD" | grep -i "adversary-lens.md")
	assert_contains "$row" "no-slop/references/adversary-lens.md" "review.md lens table row for slop points at adversary-lens.md"
}

t_review_md_documents_slop_lens_placement() {
	local out
	out=$(cat "$REVIEW_MD")
	assert_contains "$out" "correctness + gaming + slop" "review.md names correctness + gaming + slop for the per-slice lens set"
	assert_contains "$out" "all seven" "review.md names all seven lenses at branch level (was all six; flipped by F82)"
}

# ---------------------------------------------------------------------------
# M04 — review.md: gating runs six lenses with structure advisory; building
# still runs the three. review-diff.js carries structure in its defaults.
# M23 — the correctness row carries the rerun / crash / half-applied clause.
# ---------------------------------------------------------------------------

t_review_diff_defaults_include_structure() {
	local line
	line=$(grep -n "^const lenses = " "$REVIEW_DIFF_JS")
	assert_contains "$line" "'structure'" "review-diff.js default lenses include 'structure'"
}

t_review_md_documents_structure_advisory() {
	local out
	out=$(cat "$REVIEW_MD")
	assert_contains "$out" "**structure**" "review.md lens table has a structure row"
	assert_contains "$out" "all seven" "review.md names all seven lenses at branch level"
	assert_contains "$out" "advisory" "review.md says structure findings are advisory"
	assert_contains "$out" "Could be smaller:" "review.md names the PR-body heading for structure findings"
	assert_not_contains "$out" "all five" "review.md no longer says all five"
	assert_contains "$out" "correctness + gaming + slop" "review.md still pins the per-task trio"
	assert_contains "$out" "Feature Envy" "review.md structure row names the smells so the Skill-only eval can reach them"
	assert_contains "$out" "possible <smell>" "review.md says smells are hedged"
}

t_review_md_gating_hands_over_repo_review_md() {
	local out
	out=$(cat "$REVIEW_MD")
	assert_contains "$out" "the repo's \`REVIEW.md\` when one exists at the repo root" "review.md hands reviewers the repo REVIEW.md at gating"
	assert_contains "$out" "\`reviewMd\` argument" "review.md names review-diff's reviewMd argument"
	assert_contains "$out" "cites the file and the rule" "review.md: a standards violation cites file and rule"
	assert_contains "$out" "a linter or hook already enforces is skipped" "review.md: enforced rules are skipped"
}

t_review_md_correctness_row_asks_about_reruns() {
	local row
	row=$(grep "^| \*\*correctness\*\*" "$REVIEW_MD")
	assert_contains "$row" "second run" "review.md correctness row asks what a second run does"
	assert_contains "$row" "crash" "review.md correctness row asks about a crash after each write"
	assert_contains "$row" "half-applied" "review.md correctness row flags half-applied writes"
	assert_contains "$row" "queue consumer" "review.md correctness row names its trigger"
}

# ---------------------------------------------------------------------------
# F62 / F64 / F65 / F66 / F69 — severity clauses, agent-feature security
# checks, security predicates, sibling-path parity, mutation canary.
# ---------------------------------------------------------------------------

_lens_adversary_md() { cat "$SCAN_DIR/../agents/adversary.md"; }

t_review_lenses_security_llm_output_untrusted_both_files() {
	local f out
	for f in "$SCAN_DIR/../agents/adversary.md" "$REVIEW_MD"; do
		out=$(cat "$f")
		assert_contains "$out" "model output" "$f: names model output as untrusted"
		assert_contains "$out" "schema-validated" "$f: model output is schema-validated before a sink"
		assert_contains "$out" "not a security boundary" "$f: system prompt is not a security boundary"
		assert_contains "$out" "Destructive tools require confirmation" "$f: destructive tools need confirmation"
	done
}

t_review_lenses_security_predicates_in_adversary() {
	local out
	out=$(_lens_adversary_md)
	assert_contains "$out" "follows who wrote a value" "adversary.md: trust follows the writer"
	assert_contains "$out" "one level below" "adversary.md: computed-path deletes are confined"
	assert_contains "$out" "tempfile.mkdtemp" "adversary.md: a self-made temp dir is not flagged"
	assert_contains "$out" "loosens a security control" "adversary.md: loosened controls are findings"
	assert_contains "$out" "outbound host" "adversary.md: unnamed outbound hosts are findings"
}

t_review_lenses_security_sibling_parity() {
	local out row
	out=$(_lens_adversary_md)
	assert_contains "$out" "peer handler" "adversary.md: lists peer handlers for a new guard"
	assert_contains "$out" "state-changing or boundary-crossing sink" "adversary.md: parity needs a sink on both paths"
	assert_contains "$out" "different principal" "adversary.md: parity needs a different principal"
	row=$(grep "^| \*\*security\*\*" "$REVIEW_MD")
	assert_contains "$row" "peer" "review.md security row carries sibling parity"
	assert_contains "$row" "untrusted" "review.md security row names untrusted output"
}

t_review_lenses_severity_rules_in_review_md() {
	local out
	out=$(cat "$REVIEW_MD")
	assert_contains "$out" "plan-mandated" "review.md: brief-mandated defects are labelled plan-mandated"
	assert_contains "$out" "--amend" "review.md: plan-mandated goes to a Ruling or --amend"
	assert_contains "$out" "at head but not at Base" "review.md: new test-run warnings are findings"
	assert_contains "$out" "even when the brief is silent" "review.md: severity follows effect when the brief is silent"
}

t_review_lenses_mutation_canary_in_review_md() {
	local row
	row=$(grep "^| \*\*gaming\*\*" "$REVIEW_MD")
	assert_contains "$row" "mutation canary" "review.md gaming row names the mutation canary"
	assert_contains "$row" "NEEDS-TOOL" "review.md gaming row: unrunnable canary is NEEDS-TOOL"
}

# F82 - the docs lens: advisory, defined in adversary.md, documented in review.md.
t_review_lenses_docs_lens_defined_and_documented() {
	local line
	line=$(grep -n "^const lenses = " "$REVIEW_DIFF_JS")
	assert_contains "$line" "'docs'" "review-diff.js default lenses include 'docs'"
	assert_contains "$(cat "$REVIEW_MD")" "| **docs** |" "review.md lens table has a docs row"
	assert_contains "$(cat "$REVIEW_MD")" "## Docs drift" "review.md names the PR-body heading for docs findings"
	assert_contains "$(cat "$SCAN_DIR/../agents/adversary.md")" "- **docs** —" "adversary.md defines the docs lens so it is not read as correctness"
	assert_contains "$(cat "$SCAN_DIR/../agents/adversary.md")" "Never flag style" "adversary.md docs lens skips style"
}

t_lens_cross_file_first_use_api_needs_a_receipt() {
	local out
	out=$(_lens_adversary_md)
	assert_contains "$out" "first-use third-party call" "adversary.md cross-file: a first-use third-party call needs an api: line"
	assert_contains "$out" "api: version" "adversary.md cross-file: an api: version that differs from the lockfile is a finding"
}

# --- Z3 (F72, F76, F81, F60): review.md and adversary.md pin the new rules ---------------
t_review_lenses_z3_nested_review_is_never_a_self_review() {
	local rm
	rm=$(cat "$REVIEW_MD")
	assert_contains "$rm" "review not run: nested" "review.md: a reviewer that cannot spawn a fresh one stops with 'review not run: nested'"
	assert_contains "$rm" "write no PASS file" "review.md: a nested review writes no PASS file"
	assert_not_contains "$rm" "degraded: self-review" "review.md: no degraded self-review path"
	assert_not_contains "$(_lens_adversary_md)" "degraded: self-review" "adversary.md: no degraded self-review path"
}

t_review_lenses_z3_predates_and_coverage_rules() {
	local rm
	rm=$(cat "$REVIEW_MD")
	assert_contains "$rm" ".anchors" "review.md: review-package's anchors file decides in-diff"
	assert_contains "$rm" "enabling_line" "review.md: an off-diff finding survives only through an enabling line"
	assert_contains "$rm" "predates[]" "review.md: predating flaws come back in predates[]"
	assert_contains "$rm" "- Discovered: <file>:<line> — <what> — predates change — defer" "review.md: the caller logs a predating flaw as a Discovered line"
	assert_contains "$rm" "filesRead" "review.md: lenses report which changed files they read"
	assert_contains "$rm" "incomplete" "review.md: an unread-file lens makes the review incomplete"
	assert_contains "$rm" "- Minor: T### <finding>" "review.md: minors are written to NOTES.md by the caller"
	assert_not_contains "$rm" "Recorded, never blocking; at most 3 per review." "review.md: the old 'recorded' claim that nothing wrote is gone"
}

t_review_lenses_z3_process_rules_are_not_findings() {
	local a
	a=$(_lens_adversary_md)
	assert_contains "$a" "rule about process (how to run tools" "adversary.md: a process-only rule is not a finding"
	assert_contains "$a" "checkable against the diff text" "adversary.md: only rules the diff text can break count"
}

# famous-borrows F68: the correctness lens reasons about what a catch or fallback hides
t_review_lenses_z5_correctness_names_what_a_catch_hides() {
	local out row evid
	out=$(_lens_adversary_md)
	assert_contains "$out" "name the concrete error it could hide" "adversary.md: each added catch or fallback names the error it hides"
	assert_contains "$out" "what the caller then sees" "adversary.md: the caller-visible result is stated"
	assert_contains "$out" "mock, stub or empty data on a production path" "adversary.md: fake-data fallbacks on production paths are significant"
	assert_contains "$out" "forces the error" "adversary.md: such a finding is CONFIRMED only with a run that forces the error"
	assert_contains "$out" "no catch, except, fallback or default" "adversary.md: a diff with none of them yields no such finding"
	row=$(grep '^| NS-03 |' "$SCAN_DIR/../skills/no-slop/references/rubric.md")
	assert_contains "$row" ".catch(() =>" "NS-03 covers a promise .catch returning a default"
	assert_contains "$row" "mock or fixture import" "NS-03 covers mock or fixture imports reachable from non-test code"
	evid=$(cat "$SCAN_DIR/../skills/no-slop/references/adversary-lens.md")
	assert_contains "$evid" "NS-03: the catch" "adversary-lens.md carries an NS-03 evidence line"
	assert_contains "$(cat "$REVIEW_MD")" "correctness + gaming + slop" "review.md per-task trio unchanged"
	assert_contains "$(cat "$SCAN_DIR/../agents/adversary.md")" "default = correctness" "no new lens was added to adversary.md"
}
