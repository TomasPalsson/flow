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
	assert_contains "$out" "all six" "review.md names all six lenses at branch level (was all five; flipped by M04)"
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
	assert_contains "$out" "all six" "review.md names all six lenses at branch level"
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
