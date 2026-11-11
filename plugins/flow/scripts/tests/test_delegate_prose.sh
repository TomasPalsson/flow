#!/usr/bin/env bash
# test_delegate_prose.sh — prose assertions for skills/delegate/SKILL.md and
# its listing in the plugin docs. Sourced by run.sh; SCAN_DIR is already set.
# Tests prefixed t_delegate_.

DELEGATE_SKILL="$SCAN_DIR/../skills/delegate/SKILL.md"
DELEGATE_REPO="$SCAN_DIR/../../.."

_delegate_content() { cat "$DELEGATE_SKILL" 2>/dev/null; }

# FR-01: the skill must send small, iterative and uncheckable work back inline.
t_delegate_stay_inline_cases() {
	local content
	content=$(_delegate_content)
	assert_contains "$content" 'the brief would be longer than the edit' \
		"delegate keeps an edit shorter than its brief in the main session"
	assert_contains "$content" 'iterative' \
		"delegate keeps iterative work in the main session"
	assert_contains "$content" 'shares context across phases' \
		"delegate keeps context-sharing work in the main session"
	assert_contains "$content" 'cannot name the acceptance command' \
		"delegate keeps work with no acceptance command in the main session"
}

# FR-02: no worker may inherit the session model.
t_delegate_pins_model() {
	local content
	content=$(_delegate_content)
	assert_contains "$content" 'Pin `model` on every spawn' \
		"delegate pins model on every spawn"
	assert_contains "$content" 'A worker is never Fable' \
		"delegate forbids Fable as a worker"
	assert_not_contains "$content" 'never Fable when' \
		"delegate forbids Fable with no condition attached"
	assert_contains "$content" 'never a fork' \
		"delegate forbids forks"
}

# FR-03: cheapest model that fits, with a fallback when Haiku fails its check.
t_delegate_model_ladder() {
	local content
	content=$(_delegate_content)
	assert_contains "$content" 'a command or a quote can check' \
		"delegate gives Haiku the checkable work"
	assert_contains "$content" '| Haiku |' "delegate has a Haiku row"
	assert_contains "$content" 'short, single purpose' \
		"delegate gives Haiku a short single-purpose brief"
	assert_contains "$content" '| Sonnet | writing code, judging a diff' \
		"delegate gives Sonnet code and diff judgement"
	assert_contains "$content" '| Opus | a task Sonnet already failed with a good brief' \
		"delegate reserves Opus for what Sonnet already failed"
	assert_contains "$content" 'subtle concurrency or security review' \
		"delegate allows Opus for subtle concurrency or security review"
	assert_contains "$content" 're-run it on Sonnet' \
		"delegate re-runs a failed Haiku check on Sonnet"
}

# FR-04: the six fields of a worker brief.
t_delegate_brief_template() {
	local content field
	content=$(_delegate_content)
	for field in 'Objective:' 'Owned paths:' 'Signatures and edge cases:' \
		'Acceptance command:' 'Return format:' 'Tools allowed:'; do
		assert_contains "$content" "$field" "delegate brief template has $field"
	done
}

# FR-05: a short report, verified by a command and not by re-reading.
t_delegate_report_format() {
	local content
	content=$(_delegate_content)
	assert_contains "$content" 'verdict' "delegate report carries a verdict"
	assert_contains "$content" 'files changed' "delegate report lists files changed"
	assert_contains "$content" 'failing output only' \
		"delegate report carries failing output only"
	assert_contains "$content" '15 lines' "delegate report is capped near 15 lines"
	assert_contains "$content" 're-running the acceptance command' \
		"delegate verifies by re-running the acceptance command"
}

# FR-06: small waves, no over-splitting, no polling.
t_delegate_wave_cap() {
	local content
	content=$(_delegate_content)
	assert_contains "$content" 'Two to four workers per wave' \
		"delegate caps a wave at two to four workers"
	assert_contains "$content" 'same mental model' \
		"delegate sends same-mental-model work to one worker"
	assert_contains "$content" 'touches the same files' \
		"delegate sends overlapping-file work to one worker"
	assert_contains "$content" 'Do not poll' "delegate forbids polling workers"
	assert_contains "$content" 'More than four independent pieces is a Workflow' \
		"delegate hands more than four pieces to a Workflow"
	assert_not_contains "$content" 'Four or more independent pieces' \
		"delegate does not contradict its own four-worker cap"
}

# FR-07: short, valid frontmatter, and no trigger collision with another skill.
t_delegate_short_and_lints() {
	local lines out rc
	assert_file_exists "$DELEGATE_SKILL" "delegate SKILL.md exists"
	assert_contains "$(_delegate_content)" 'Do NOT use for fleet-scale orchestration' \
		"delegate description excludes fleet-scale work"
	lines=$(wc -l <"$DELEGATE_SKILL" 2>/dev/null | tr -d ' ')
	if [ -n "$lines" ] && [ "$lines" -le 80 ]; then
		_pass "delegate SKILL.md is 80 lines or fewer"
	else
		_fail "delegate SKILL.md is 80 lines or fewer" "got '${lines:-missing}'"
	fi
	out=$("$SCAN_DIR/skills-lint" --frontmatter "$SCAN_DIR/../skills/delegate" 2>&1)
	rc=$?
	assert_eq "$rc" "0" "delegate frontmatter lint exits 0"
	assert_not_contains "$out" 'delegate/SKILL.md' \
		"delegate frontmatter lint reports nothing for the skill"
	out=$("$SCAN_DIR/skills-lint" --collisions "$DELEGATE_REPO/plugins/flow/skills" 2>&1)
	assert_not_contains "$out" 'delegate/SKILL.md' \
		"delegate collides with no other flow skill"
}

# FR-08: the plugin docs list the skill.
t_delegate_listed_in_docs() {
	local plugins_md readme
	plugins_md=$(cat "$DELEGATE_REPO/docs/reference/plugins.md" 2>/dev/null)
	readme=$(cat "$SCAN_DIR/../README.md" 2>/dev/null)
	assert_contains "$plugins_md" '## flow (14 skills + shared)' \
		"delegate docs: plugins.md counts 14 flow skills"
	assert_contains "$plugins_md" '- delegate' \
		"delegate docs: plugins.md lists delegate"
	assert_contains "$readme" 'delegate' \
		"delegate docs: README skill list names delegate"
}
