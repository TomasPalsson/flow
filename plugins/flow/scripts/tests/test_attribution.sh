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

# Repos whose credit lines are checked. Anthropic sources are Apache-2.0, so the
# licence is read from the line itself rather than assumed.
ATTR_REPOS='mattpocock/skills|cursor/plugins|cursor-team-kit|obra/superpowers|github/spec-kit|garrytan/gstack|addyosmani/agent-skills|vercel-labs/agent-skills|anthropics/(skills|claude-plugins-official)'

# attr_credit_lines <dir> — every credit line that names a checked repo.
attr_credit_lines() {
	grep -rInE -i "(adapted|borrowed|credit).*($ATTR_REPOS)" "$1" --exclude-dir=tests --exclude-dir=node_modules || true
}

attr_without_sha() { attr_credit_lines "$1" | grep -v '@ \{0,1\}[0-9a-f]\{7,\}' || true; }
attr_without_licence() { attr_credit_lines "$1" | grep -v '(\(MIT\|Apache-2\.0\))' || true; }

t_attribution_checks_every_borrowed_repo() {
	local d
	d=$(tmp_dir)
	printf 'Credit: adapted from obra/superpowers foo (MIT).\n' >"$d/a.md"
	assert_contains "$(attr_without_sha "$d")" "obra/superpowers" "a sha-less superpowers credit is caught"
	printf 'Credit: adapted from github/spec-kit foo (MIT).\n' >"$d/b.md"
	assert_contains "$(attr_without_sha "$d")" "github/spec-kit" "a sha-less spec-kit credit is caught"
	printf 'Credit: adapted from anthropics/skills foo @ abcdef1.\n' >"$d/c.md"
	assert_contains "$(attr_without_licence "$d")" "anthropics/skills" "a licence-less credit is caught"
	printf 'Credit: adapted from obra/superpowers foo @ abcdef1 (MIT).\n' >"$d/ok.md"
	assert_not_contains "$(attr_without_sha "$d")$(attr_without_licence "$d")" "ok.md" "a complete credit passes"
	rm -rf "$d"
}

t_attribution_every_credit_line_names_a_licence() {
	assert_eq "$(attr_without_licence "$ATTR_PLUGINS")" "" "every credit line names (MIT) or (Apache-2.0)"
}

t_attribution_every_checked_repo_credit_has_a_sha() {
	assert_eq "$(attr_without_sha "$ATTR_PLUGINS")" "" "every credit line for a checked repo carries @<sha>"
}

t_attribution_superpowers_and_spec_kit_borrows_are_credited() {
	local f
	for f in flow/scripts/review-package flow/scripts/task-brief flow/scripts/new-spec \
		flow/skills/spec/references/design.md flow/skills/fix/SKILL.md flow/skills/next/SKILL.md; do
		assert_contains "$(grep -E 'adapted from (obra/superpowers|github/spec-kit)' "$ATTR_PLUGINS/$f" 2>/dev/null)" "adapted from" "$f carries a superpowers or spec-kit credit"
	done
}

t_attribution_addyosmani_borrows_are_credited() {
	local f
	for f in flow-extras/skills/grill-with-docs/ADR-FORMAT.md flow/skills/no-slop/references/developer-block.md \
		flow/scripts/skills-lint-frontmatter.py; do
		assert_contains "$(grep -E 'adapted from addyosmani/agent-skills' "$ATTR_PLUGINS/$f" 2>/dev/null)" "@ 1be8e34 (MIT)" "$f carries an addyosmani credit with its sha and licence"
	done
}

t_attribution_grill_with_docs_continues_the_repo_adr_convention() {
	local fmt skill
	fmt=$(cat "$ATTR_PLUGINS/flow-extras/skills/grill-with-docs/ADR-FORMAT.md")
	skill=$(cat "$ATTR_PLUGINS/flow-extras/skills/grill-with-docs/SKILL.md")
	assert_contains "$fmt" ".adr-dir" "ADR-FORMAT looks for an .adr-dir file"
	assert_contains "$fmt" "match the existing convention first" "ADR-FORMAT leads with the match-first rule"
	assert_contains "$fmt" "Never start a third" "ADR-FORMAT stops and asks on conflicting conventions"
	assert_not_contains "$skill" "If no \`docs/adr/\` exists, create it when the first ADR is needed" "SKILL.md no longer creates docs/adr/ unconditionally"
	assert_contains "$skill" "ADR-FORMAT.md" "SKILL.md points at the ADR convention rule"
}
