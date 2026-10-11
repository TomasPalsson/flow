#!/usr/bin/env bash
# test_audit_web_guidelines.sh — the impeccable audit carries a pinned slice of
# vercel-labs/web-interface-guidelines (never fetched live) and does not restate
# rules that already live elsewhere in plugins/design.
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_audit_wig_.

AUDIT_WIG_FILE="$SCAN_DIR/../../design/skills/impeccable/reference/audit.md"

t_audit_wig_pins_full_source_sha() {
	assert_contains "$(grep -E 'web-interface-guidelines @ [0-9a-f]{40}' "$AUDIT_WIG_FILE" || true)" \
		'web-interface-guidelines @ ' "audit.md pins a 40-hex source sha"
}

t_audit_wig_names_the_added_rules() {
	local body
	body=$(cat "$AUDIT_WIG_FILE")
	assert_contains "$body" 'touch-action' "touch-action rule present"
	assert_contains "$body" 'Intl' "Intl rule present"
	assert_contains "$body" 'theme-color' "theme-color rule present"
	assert_contains "$body" 'translate="no"' "translate=no rule present"
}

t_audit_wig_points_at_tabular_nums_without_copying() {
	local body
	body=$(cat "$AUDIT_WIG_FILE")
	assert_contains "$body" 'vary/references/build-craft.md' "tabular-nums cites build-craft"
	assert_eq "$(printf '%s' "$body" | grep -c 'font-variant-numeric')" "0" "tabular-nums not restated"
}

t_audit_wig_credit_line_matches_attribution_regex() {
	assert_contains "$(cat "$AUDIT_WIG_FILE")" \
		'Credit: adapted from vercel-labs/web-interface-guidelines command.md @ 434b7f9 (MIT).' "credit line"
}
