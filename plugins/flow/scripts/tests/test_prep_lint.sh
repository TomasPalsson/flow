#!/usr/bin/env bash
# test_prep_lint.sh — tests for prep-lint, t_prep_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

FIX="$HERE/fixtures"
PREP_LINT="$SCAN_DIR/prep-lint"

# _prep_base_file — writes a clean, minimal, well-formed PREP.md (dispatch /
# ready for spec) into a fresh tmp_dir and echoes its path. Every rule test
# below derives its variant from this file via sed, per the unit's
# "prefer sed-generated variants over new fixture files" guidance.
_prep_base_file() {
	d=$(tmp_dir)
	cat >"$d/prep.md" <<'PREPEOF'
# Prep — Widget dispatch

Gathered: 2026-09-01 · Questions: 3 of 12 · Route: dispatch · Status: ready for spec

## Decisions
- D-01 Use SQLite for local cache — user, Q1
- D-02 Ship behind a feature flag — user, Q2

## Not this
- Does not support multi-tenant mode yet

## Discretion
- Log level defaults to info

## Assumptions
- A-01 The cache is single-writer — evidence: src/cache.ts:42 — confidence: high — confirmed Q3
- A-02 No external dependency needed — evidence: none — confidence: medium — unconfirmed

## Verify
- `npm test` passes with the new cache path exercised

## Open
- Q: Should we cap cache size? → deferred to spec
PREPEOF
	printf '%s' "$d/prep.md"
}

# ---------------------------------------------------------------------------
# basics
# ---------------------------------------------------------------------------

t_prep_help() {
	run_cmd "$PREP_LINT" --help
	assert_rc 0 "prep-lint --help exits 0"
	assert_contains "$OUT" "Usage: prep-lint" "prep-lint --help shows usage"
}

t_prep_no_args() {
	run_cmd "$PREP_LINT"
	assert_rc 1 "prep-lint with no args exits 1"
}

t_prep_missing_file() {
	run_cmd "$PREP_LINT" "$FIX/prep-does-not-exist.md"
	assert_rc 1 "prep-lint on a missing file exits 1"
	assert_contains "$OUT" "MISSING" "prep-lint on a missing file prints MISSING"
}

t_prep_good_dispatch_ok() {
	run_cmd "$PREP_LINT" "$FIX/prep-good.md"
	assert_rc 0 "prep-lint on prep-good.md exits 0"
	assert_eq "$OUT" "OK" "prep-lint on prep-good.md prints exactly OK"
}

t_prep_good_fence_decoy_ignored() {
	# prep-good.md embeds a fenced block containing a decoy "## Open" heading
	# and four "- Q:" bullets; a fence-aware scanner must ignore all of it
	# and still report a clean OK (the real ## Open section has one bullet).
	run_cmd "$PREP_LINT" "$FIX/prep-good.md"
	assert_eq "$OUT" "OK" "prep-lint ignores the fenced decoy Open section"
}

t_prep_interviewing_empty_sections_ok() {
	# Status: interviewing — rules 7/8 (Not this / Verify need >=1 bullet)
	# never fire while interviewing, so empty sections stay clean.
	run_cmd "$PREP_LINT" "$FIX/prep-interviewing.md"
	assert_rc 0 "prep-lint on prep-interviewing.md exits 0"
	assert_eq "$OUT" "OK" "prep-lint on prep-interviewing.md prints exactly OK"
}

t_prep_bounded_done_empty_decisions_ok() {
	run_cmd "$PREP_LINT" "$FIX/prep-bounded-done.md"
	assert_rc 0 "prep-lint on prep-bounded-done.md exits 0"
	assert_eq "$OUT" "OK" "prep-lint on prep-bounded-done.md prints exactly OK"
}

# ---------------------------------------------------------------------------
# ERROR rules 1-12
# ---------------------------------------------------------------------------

t_prep_rule1_gathered_missing() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed '/^Gathered:/d' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects a missing Gathered header"
	assert_contains "$OUT" "unparsable" "prep-lint names rule 1 (header missing/unparsable)"
}

t_prep_rule2_questions_exceeds_total() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/Questions: 3 of 12/Questions: 13 of 12/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects Questions N > M"
	assert_contains "$OUT" "exceeds" "prep-lint names rule 2 (N exceeds M)"
}

t_prep_rule3_bad_route() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/Route: dispatch/Route: bogus/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects an invalid Route"
	assert_contains "$OUT" "Route must be spike, bounded, oneshot or dispatch" "prep-lint names rule 3 (bad route)"
}

t_prep_rule4_bad_status() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/Status: ready for spec/Status: bogus/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects an invalid Status"
	assert_contains "$OUT" "Status must be interviewing, ready for spec, or done in chat" "prep-lint names rule 4 (bad status)"
}

t_prep_rule5_spike_ready_for_spec() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/Route: dispatch/Route: spike/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects spike route with Status ready for spec"
	assert_contains "$OUT" "spike and bounded never get a spec" "prep-lint names rule 5 (spike/bounded + ready for spec)"
}

t_prep_rule6_missing_section() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed '/^## Discretion$/d' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects a missing required section"
	assert_contains "$OUT" 'the six sections are Decisions, Not this, Discretion, Assumptions, Verify, Open, in that order' "prep-lint names rule 6 (missing/out-of-order section)"
}

t_prep_rule7_not_this_needs_bullet() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed '/^- Does not support multi-tenant mode yet$/d' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects an empty Not this section outside interviewing"
	assert_contains "$OUT" "what should this explicitly NOT do" "prep-lint names rule 7 (Not this empty)"
}

t_prep_rule8_verify_needs_bullet() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed '/^- `npm test` passes with the new cache path exercised$/d' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects an empty Verify section outside interviewing"
	assert_contains "$OUT" "what single check would convince you this shipped" "prep-lint names rule 8 (Verify empty)"
}

t_prep_rule9_too_many_open_questions() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	cp "$base" "$d/prep.md"
	{
		printf -- '- Q: extra one? → deferred to spec\n'
		printf -- '- Q: extra two? → deferred to spec\n'
		printf -- '- Q: extra three? → deferred to spec\n'
	} >>"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects more than 3 Open bullets"
	assert_contains "$OUT" "more than 3 open questions means the scope is too large" "prep-lint names rule 9 (too many Open bullets)"
}

t_prep_rule10_decision_bullet_malformed() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/- D-01 Use SQLite for local cache — user, Q1/- D-01 Use SQLite for local cache/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects a malformed Decisions bullet"
	assert_contains "$OUT" 'every decision reads "- D-NN <text> — user, Q<n>"' "prep-lint names rule 10 (Decisions bullet grammar)"
}

t_prep_rule11_assumption_bullet_malformed() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's#- A-01 The cache is single-writer — evidence: src/cache.ts:42 — confidence: high — confirmed Q3#- A-01 The cache is single-writer — evidence: src/cache.ts:42#' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects an Assumptions bullet missing confidence"
	assert_contains "$OUT" "every assumption reads" "prep-lint names rule 11 (Assumptions bullet grammar)"
}

t_prep_rule12_duplicate_decision_id() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/D-02/D-01/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 1 "prep-lint rejects a duplicate D-NN id"
	assert_contains "$OUT" "duplicate id D-01" "prep-lint names rule 12 (duplicate id)"
}

# ---------------------------------------------------------------------------
# WARN rules 13-14
# ---------------------------------------------------------------------------

t_prep_rule13_ready_for_spec_zero_decisions() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed '/^- D-0[12] /d' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 0 "prep-lint only WARNs on ready-for-spec with zero Decisions"
	assert_contains "$OUT" "WARN" "prep-lint names rule 13 (zero Decisions at ready for spec)"
}

t_prep_rule14_counter_behind_receipts() {
	base=$(_prep_base_file)
	d=$(tmp_dir)
	sed 's/confirmed Q3/confirmed Q5/' "$base" >"$d/prep.md"
	run_cmd "$PREP_LINT" "$d/prep.md"
	assert_rc 0 "prep-lint only WARNs when the Questions counter is behind the receipts"
	assert_contains "$OUT" "WARN" "prep-lint names rule 14 (counter behind receipts)"
}

# ---------------------------------------------------------------------------
# adversary findings 2026-09-07: receipts, not prose, feed the counter check;
# Status parses when it is not the last header field
# ---------------------------------------------------------------------------

t_prep_rule14_ignores_q_in_prose() {
	local d
	d=$(tmp_dir)
	sed 's/- D-01 Use SQLite for local cache — user, Q1/- D-01 Use SQLite (see Q10 in the notes) — user, Q1/' "$FIX/prep-good.md" >"$d/p.md"
	run_cmd "$PREP_LINT" "$d/p.md"
	assert_rc 0 "Q10 in decision prose is not a receipt (rc)"
	assert_eq "$OUT" "OK" "Q10 in decision prose is not a receipt (OK)"
	rm -rf "$d"
}

t_prep_header_status_not_last_field() {
	local d
	d=$(tmp_dir)
	sed 's/^Gathered: .*$/Gathered: 2026-09-01 · Status: ready for spec · Questions: 3 of 12 · Route: dispatch/' "$FIX/prep-good.md" >"$d/p.md"
	run_cmd "$PREP_LINT" "$d/p.md"
	assert_rc 0 "Status before other header fields still parses (rc)"
	assert_eq "$OUT" "OK" "Status before other header fields still parses (OK)"
	rm -rf "$d"
}
