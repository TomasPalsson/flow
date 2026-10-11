#!/usr/bin/env bash
# test_method_rules.sh — prose pins for the famous-repos borrow round, slice Z1:
# free text reaches git and gh through a file (F05), secrets never pass through
# chat (F16), and the small method rules each have a home (F188, F26 markers).
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_methrule_.

MR_PLUGINS="$SCAN_DIR/../.."
MR_SKILLS="$MR_PLUGINS/flow/skills"

mr_has() { # <file> <fixed string> <label>
	assert_contains "$(cat "$1" 2>/dev/null)" "$2" "$3"
}

t_methrule_no_inline_commit_message_or_body_in_flow_skills() {
	local bad
	bad=$(grep -rnE 'commit -m "|--body "' "$MR_SKILLS" "$MR_PLUGINS/flow/agents" || true)
	assert_eq "$bad" "" "no 'commit -m \"' or '--body \"' in flow skills or agents"
}

t_methrule_commit_prescribes_quoted_heredoc() {
	mr_has "$MR_SKILLS/next/SKILL.md" "git commit -F - -- <each path in files:> <<'EOF'" "next SKILL commit via -F -"
	mr_has "$MR_SKILLS/next/execution-prompt.md" "git commit -F - -- <each path in files:> <<'EOF'" "execution-prompt commit via -F -"
}

t_methrule_pr_and_issue_bodies_come_from_a_file() {
	mr_has "$MR_SKILLS/shared/pr-body.md" "--body-file" "pr-body prescribes --body-file"
	mr_has "$MR_SKILLS/issue/SKILL.md" "--body-file - <<'EOF'" "issue create reads the body from a quoted heredoc"
	mr_has "$MR_SKILLS/fix/SKILL.md" "--body-file" "fix opens its PR with --body-file"
}

t_methrule_secrets_never_in_chat() {
	local f="$MR_SKILLS/shared/secrets.md"
	assert_file_exists "$f" "shared/secrets.md exists"
	mr_has "$f" "Never ask for a secret in chat" "secrets: never in chat"
	mr_has "$f" "never echo" "secrets: never echo"
	mr_has "$f" "AWS_ACCESS_KEY_ID" "secrets: AWS shadowing names the key variable"
	mr_has "$f" "AWS_PROFILE" "secrets: AWS shadowing names AWS_PROFILE"
	mr_has "$f" "only to the host that issued it" "secrets: token check goes to its own host"
}

t_methrule_secrets_rule_is_referenced() {
	mr_has "$MR_SKILLS/shared/verification.md" "secrets.md" "verification references secrets.md"
	mr_has "$MR_SKILLS/spec/SKILL.md" "secrets.md" "spec references secrets.md"
	mr_has "$MR_SKILLS/next/SKILL.md" "secrets.md" "next references secrets.md"
	mr_has "$MR_PLUGINS/tooling/skills/new-project/SKILL.md" "secrets.md" "new-project references the secrets rule"
}

t_methrule_vertical_slice_span_is_tagged_in_spec_and_next() {
	mr_has "$MR_SKILLS/spec/SKILL.md" "<!-- shared:vertical-slice -->" "spec opens the shared span"
	mr_has "$MR_SKILLS/spec/SKILL.md" "<!-- /shared:vertical-slice -->" "spec closes the shared span"
	mr_has "$MR_SKILLS/next/SKILL.md" "<!-- shared:vertical-slice -->" "next opens the shared span"
	mr_has "$MR_SKILLS/next/SKILL.md" "<!-- /shared:vertical-slice -->" "next closes the shared span"
}

t_methrule_f188_lines_are_present() {
	mr_has "$MR_PLUGINS/flow-extras/skills/grill-me/SKILL.md" "When agreement took several rounds, restate the final version in one message and get a yes before building on it." "grill-me restates"
	mr_has "$MR_SKILLS/spec/SKILL.md" "Draft the section with the most unknowns first; summary last." "spec drafting order"
	mr_has "$MR_SKILLS/fix/SKILL.md" "With several causes, judge each fix by whether its own failing signal disappears; do not revert a fix only because the end-to-end test still fails while other causes remain." "fix keeps a correct partial fix"
	mr_has "$MR_SKILLS/no-slop/references/developer-block.md" "Scratch checks verify; they do not become committed test files unless the task or repo convention asks." "developer-block scratch checks"
}

t_methrule_handoff_summary_and_provenance() {
	local f="$MR_PLUGINS/flow-extras/skills/handoff/SKILL.md"
	mr_has "$f" "exact user wording" "handoff keeps exact user wording"
	mr_has "$f" "tried and rejected" "handoff keeps rejected options"
	mr_has "$f" "Verify first:" "handoff has a Verify first group"
	mr_has "$f" "(assumed)" "handoff marker: assumed"
	mr_has "$f" "(state checked)" "handoff marker: state checked"
	mr_has "$f" "(code read)" "handoff marker: code read"
	mr_has "$f" "read-only" "handoff verification is read-only"
	mr_has "$f" "garrytan/gstack" "handoff credits gstack"
}

t_methrule_pr_titles_are_plain_text() {
	mr_has "$MR_SKILLS/fix/SKILL.md" 'no backticks, `$` or double quotes' "fix keeps the PR title plain"
	mr_has "$MR_SKILLS/shared/pr-body.md" 'no backticks, `$` or double quotes' "pr-body keeps the PR title plain"
}
