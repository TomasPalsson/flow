#!/usr/bin/env bash
# test_redact.sh — scripts/redact masks secrets and URL credentials. Sourced by
# run.sh; SCAN_DIR is already set. Tests prefixed t_redact_.

REDACT="$SCAN_DIR/redact"
HANDOFF_SH="$SCAN_DIR/../../flow-extras/skills/handoff/scripts/handoff.sh"

t_redact_masks_urls_and_keys() {
	local out s
	out=$(printf '%s\n' \
		'url https://b.s3.amazonaws.com/o.png?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIDEXAMPLE0000&X-Amz-Signature=deadbeef99887766 end' \
		'clone https://deploy:hunter22pw@git.example.com/x.git' \
		'gcs https://storage.googleapis.com/b/o?X-Goog-Signature=cafe1234beef5678&X-Goog-Date=20260101' \
		'cdn https://c.example.com/a.js?v=3&token=tok9988776655&sig=sigvalue1234&key=keyvalue5678' \
		'key sk-abcdefgh12345678 here' \
		'keep max_tokens: 4096 and https://example.com/docs?page=2' | "$REDACT")
	for s in deadbeef99887766 AKIDEXAMPLE0000 hunter22pw cafe1234beef5678 tok9988776655 sigvalue1234 keyvalue5678 sk-abcdefgh; do
		assert_not_contains "$out" "$s" "redact removes $s"
	done
	assert_contains "$out" "max_tokens: 4096" "redact leaves max_tokens: 4096"
	assert_contains "$out" "page=2" "redact leaves an ordinary query param"
	assert_contains "$out" "git.example.com/x.git" "redact keeps the host once credentials are masked"
}

# The sk- rule is anchored: hyphenated names in bug reports survive.
t_redact_keeps_hyphenated_words() {
	local out
	out=$(printf '%s\n' 'flask-sqlalchemy 3.1 breaks' 'Bulk task-scheduler crashes' 'risk-assessment page' 'key=x (sk-abcdefgh12345678)' | "$REDACT")
	assert_contains "$out" "flask-sqlalchemy 3.1 breaks" "flask-sqlalchemy survives"
	assert_contains "$out" "task-scheduler crashes" "task-scheduler survives"
	assert_contains "$out" "risk-assessment page" "risk-assessment survives"
	assert_not_contains "$out" "sk-abcdefgh" "a real sk- key after a paren is still masked"
}

# The user:pass@ rule must not cross ? or # into a query string and eat the host.
t_redact_keeps_host_when_email_in_query() {
	local out
	out=$(printf '%s\n' 'see https://example.com?email=a@b.com now' | "$REDACT")
	assert_contains "$out" "https://example.com?" "host survives an email in the query"
}

# flow-extras cannot depend on flow, so handoff.sh keeps its own copy; the two
# must not drift.
t_redact_matches_handoff_copy() {
	local a b
	a=$(sed -n '/^redact() {/,/^}/p' "$REDACT")
	b=$(sed -n '/^redact() {/,/^}/p' "$HANDOFF_SH")
	assert_eq "$a" "$b" "redact function body identical in flow and handoff"
	[ -n "$a" ] || _fail "redact function found"
}
