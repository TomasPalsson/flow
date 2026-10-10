#!/usr/bin/env bash
# test_borrowed_scripts.sh — runs the self-tests of scripts borrowed in the
# mattpocock round (handoff, wizard template) and asserts they exit 0.
# Sourced by run.sh; SCAN_DIR is already set. Tests prefixed t_borrowed_.

_borrowed_run() {
	local script=$1 label=$2
	if [ ! -f "$script" ]; then
		_fail "$label self-test exists" "missing: $script"
		return
	fi
	run_cmd bash "$script"
	assert_rc 0 "$label self-test exits 0"
}

t_borrowed_handoff_selftest() {
	_borrowed_run "$SCAN_DIR/../../flow-extras/skills/handoff/scripts/test_handoff.sh" handoff
}

t_borrowed_wizard_template_selftest() {
	_borrowed_run "$SCAN_DIR/../../tooling/skills/wizard/scripts/test_template.sh" wizard-template
}
