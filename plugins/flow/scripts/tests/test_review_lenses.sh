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
	assert_contains "$out" "all five" "review.md names all five lenses at branch level"
}
