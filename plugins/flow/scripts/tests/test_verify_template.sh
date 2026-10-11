#!/usr/bin/env bash
# test_verify_template.sh — the verify-skill template keeps its sandbox and
# readiness rules where a generated skill will copy them from.
set -u

VT_FILE="$(cd "$SCAN_DIR/../.." && pwd -P)/flow-extras/skills/verify-skill/references/skill-template.md"

# vt_section <heading> — the lines of one "## " section of the template.
vt_section() {
	awk -v h="## $1" '/^## /{on=($0==h)} on' "$VT_FILE"
}

t_verify_template_sandbox_in_launch() {
	local launch
	launch=$(vt_section Launch)
	assert_contains "$launch" 'XDG_CONFIG_HOME=$SANDBOX/.config' "Launch sets a sandboxed XDG config home"
	assert_contains "$launch" 'HOME=$SANDBOX' "Launch sets a sandboxed HOME"
	assert_contains "$launch" "Copy in only the named config" "carrying config over is an explicit choice"
}

t_verify_template_sandbox_evidence() {
	assert_contains "$(vt_section Evidence)" 'find $SANDBOX' "Evidence captures the sandbox tree before and after"
}

t_verify_template_readiness_poll() {
	local line
	line=$(vt_section Launch | grep 'Readiness poll')
	assert_contains "$line" "000" "the poll names curl 000"
	assert_contains "$line" "5xx" "the poll names 5xx"
	assert_contains "$line" "000\` is never ready" "000 is stated as not ready"
	assert_contains "$line" "could not verify: not ready after" "running out of time reports could-not-verify"
}
