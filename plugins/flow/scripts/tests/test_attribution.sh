#!/usr/bin/env bash
# test_attribution.sh — every borrowed-file credit line names the upstream
# commit it was taken from, and the borrow-review rubric re-diffs it.
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_attribution_.

ATTR_PLUGINS="$SCAN_DIR/../.."
ATTR_RUBRIC="$SCAN_DIR/../../../docs/research/23-pstack-rubric.md"

t_attribution_every_credit_line_has_a_sha() {
	local bad
	bad=$(grep -rInE -i '(adapted|borrowed|credit).*(mattpocock/skills|cursor/plugins|cursor-team-kit)' "$ATTR_PLUGINS" \
		--exclude-dir=tests --exclude-dir=node_modules | grep -v '@ \{0,1\}[0-9a-f]\{7,\}' || true)
	assert_eq "$bad" "" "every credit line carries @<sha>"
}

t_attribution_rubric_rediffs_borrowed_files() {
	assert_contains "$(cat "$ATTR_RUBRIC")" \
		'diff <sha>..HEAD -- <cited path>' \
		"rubric re-diffs each borrowed file against upstream"
}
