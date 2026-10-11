#!/usr/bin/env bash
# test_claim_check.sh — prose pins for agents/claim-check.md: the deploy
# revision rule (F155) and doc mode (F167), plus the SST pointer.
# Sourced by run.sh; SCAN_DIR (scripts/) is already set. t_claimcheck_* prefix.

CC_FILE="$SCAN_DIR/../agents/claim-check.md"
SST_DEPLOY="$SCAN_DIR/../../aws/skills/sst/references/deployment.md"

t_claimcheck_deploy_needs_live_revision() {
	local b
	b=$(cat "$CC_FILE")
	assert_contains "$b" "live revision" "deployed claim compares the live revision"
	assert_contains "$b" "Lambda version" "names the Lambda version source"
	assert_contains "$b" "/version endpoint" "names the /version endpoint source"
	assert_contains "$b" "A 200 from an older revision is UNSUPPORTED" "an old revision answering 200 is UNSUPPORTED"
}

t_claimcheck_sst_deployment_points_at_it() {
	local b
	b=$(cat "$SST_DEPLOY")
	assert_contains "$b" "live revision" "sst deployment.md mentions the live revision"
	assert_contains "$b" "claim-check" "sst deployment.md points at claim-check"
}

# famous-borrows Z4 F03: an exit code is read before any pipe
t_z4_pipe_rule_in_all_three_files() {
	local f
	for f in "$SCAN_DIR/../skills/shared/verification.md" "$CC_FILE" "$SCAN_DIR/../skills/next/SKILL.md"; do
		assert_contains "$(cat "$f")" 'Never cite an exit code taken after a pipe' "pipe rule in ${f##*/}"
		assert_contains "$(cat "$f")" 'PIPESTATUS' "PIPESTATUS named in ${f##*/}"
	done
	assert_contains "$(cat "$CC_FILE")" 'UNSUPPORTED' "claim-check keeps UNSUPPORTED"
	assert_contains "$(cat "$CC_FILE")" '126 and 127' "claim-check treats 126 and 127 as red"
	assert_contains "$(cat "$SCAN_DIR/../skills/shared/verification.md")" '126 and 127' "verification.md treats 126 and 127 as red"
}

t_claimcheck_doc_mode_is_read_only_with_how() {
	local b
	b=$(cat "$CC_FILE")
	assert_contains "$b" "## Doc mode" "claim-check has a doc mode section"
	assert_contains "$b" "HOW:" "each doc claim carries a HOW: line"
	assert_contains "$b" "Never edit the doc" "doc mode never edits the document"
	assert_contains "$b" "read-only" "doc mode runs read-only checks"
	assert_contains "$b" "two passes" "doc mode stops after two passes that change no verdict"
	assert_contains "$b" "slop-check --prose --claims" "doc mode starts from the path claims scan"
	assert_contains "$b" "is not on PATH" "doc mode says slop-check is not on PATH and how to locate it"
}

# famous-borrows F164: an errored command is not a contradiction
t_claimcheck_z5_errored_command_is_inconclusive() {
	local b
	b=$(cat "$CC_FILE")
	assert_contains "$b" "errored or timed-out command" "claim-check names errored and timed-out commands"
	assert_contains "$b" "never UNSUPPORTED" "an errored command is never UNSUPPORTED"
	assert_contains "$b" "not usable" "an errored command is reported as not usable"
	assert_contains "$b" "never \"nothing found\"" "an errored command is never read as nothing found"
}
