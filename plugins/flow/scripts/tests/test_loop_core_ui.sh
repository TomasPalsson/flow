#!/usr/bin/env bash
# test_loop_core_ui.sh — regression tests for the ui-score loop-hardening
# changes to plugins/flow/bin/lib/loop/{verify,tamper,init,contract}.js:
# the ephemeral-port wedge-detector gap, the working-tree-deletion blind
# spot in countTestFiles, and the new targetSha byte-level freeze.
#
# Self-contained: run.sh's TEST_ONLY restricts a run to a single test_*.sh
# file, so this file must not depend on any other test_*.sh having been
# sourced in the same run. $HERE and $SCAN_DIR come from run.sh itself.
set -u

LU_LOOP_DIR=$(cd "$SCAN_DIR/../bin/lib/loop" && pwd -P)
export LU_LOOP_DIR

# _lu_node <js> — run node with LU_LOOP_DIR in the environment for require().
_lu_node() {
	run_cmd node -e "$1"
}

# _lu_repo — a tmp_repo (from lib.sh) with one tracked test file, so
# countTestFiles starts at 1. Equivalent of test_loop.sh's lp_repo, redefined
# here so this file has no cross-file dependency.
_lu_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/tests"
	printf 'echo test\n' >"$d/tests/foo_test.sh"
	(cd "$d" && git add tests/foo_test.sh && git commit -q -m "add test file") >/dev/null 2>&1
	printf '%s' "$d"
}

# ---------------------------------------------------------------------------
# verify.js signatureOf — port masking must not flatten real differences
# ---------------------------------------------------------------------------

t_ui_signature_equal_across_ports() {
	_lu_node '
const { signatureOf } = require(process.env.LU_LOOP_DIR + "/verify.js");
const a = signatureOf("listening on 127.0.0.1:53747\nok");
const b = signatureOf("listening on 127.0.0.1:53755\nok");
console.log(a === b ? "same" : "diff");
'
	assert_eq "$OUT" "same" "t_ui_signature_equal_across_ports"
}

t_ui_signature_differs_for_different_failures() {
	_lu_node '
const { signatureOf } = require(process.env.LU_LOOP_DIR + "/verify.js");
const a = signatureOf("assertion failed: expected 1 got 2");
const b = signatureOf("TypeError: cannot read property x");
console.log(a === b ? "same" : "diff");
'
	assert_eq "$OUT" "diff" "t_ui_signature_differs_for_different_failures"
}

t_ui_signature_preserves_line_numbers() {
	_lu_node '
const { signatureOf } = require(process.env.LU_LOOP_DIR + "/verify.js");
const a = signatureOf("at file.js:120");
const b = signatureOf("at file.js:340");
console.log(a === b ? "same" : "diff");
'
	assert_eq "$OUT" "diff" "t_ui_signature_preserves_line_numbers"
}

# ---------------------------------------------------------------------------
# tamper.js countTestFiles — working-tree deletions must drop the count
# ---------------------------------------------------------------------------

t_ui_count_test_files_drops_on_working_tree_delete() {
	local proj before after
	proj=$(_lu_repo)

	_lu_node "
const { countTestFiles } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(String(countTestFiles('$proj')));
"
	before="$OUT"

	rm "$proj/tests/foo_test.sh"

	_lu_node "
const { countTestFiles } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(String(countTestFiles('$proj')));
"
	after="$OUT"

	assert_eq "$before" "1" "t_ui_count_test_files_drops_on_working_tree_delete before"
	assert_eq "$after" "0" "t_ui_count_test_files_drops_on_working_tree_delete after"

	rm -rf "$proj"
}

# ---------------------------------------------------------------------------
# tamper.js targetSha — byte-level freeze over a target directory
# ---------------------------------------------------------------------------

t_ui_target_sha_changes_on_byte_diff() {
	local d h1 h2
	d=$(tmp_dir)
	printf '\x89PNG\x01' >"$d/a.png"

	_lu_node "
const { targetSha } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(targetSha('$d', '.', []));
"
	h1="$OUT"

	printf '\x89PNG\x02' >"$d/a.png"

	_lu_node "
const { targetSha } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(targetSha('$d', '.', []));
"
	h2="$OUT"

	if [ -n "$h1" ] && [ "$h1" != "$h2" ]; then
		_pass "t_ui_target_sha_changes_on_byte_diff"
	else
		_fail "t_ui_target_sha_changes_on_byte_diff" "h1='$h1' h2='$h2'"
	fi

	rm -rf "$d"
}

t_ui_target_sha_missing_dir() {
	local d
	d=$(tmp_dir)

	_lu_node "
const { targetSha } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(targetSha('$d', 'does-not-exist', []));
"
	assert_eq "$OUT" "MISSING" "t_ui_target_sha_missing_dir"

	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# tamper.js tamperCheck — no target_sha in the contract means no finding
# ---------------------------------------------------------------------------

t_ui_tamper_check_no_target_sha_no_finding() {
	local proj count
	proj=$(_lu_repo)

	_lu_node "
const { countTestFiles } = require(process.env.LU_LOOP_DIR + '/tamper.js');
console.log(String(countTestFiles('$proj')));
"
	count="$OUT"

	_lu_node "
const { tamperCheck } = require(process.env.LU_LOOP_DIR + '/tamper.js');
const front = { test_files: '$count', base: '', verify_sha: '', target: '', target_sha: '' };
console.log(JSON.stringify(tamperCheck('$proj', front)));
"
	assert_not_contains "$OUT" "target changed" "t_ui_tamper_check_no_target_sha_no_finding"

	rm -rf "$proj"
}

# ---------------------------------------------------------------------------
# F1/F2 — target_sha must be hashed off --target too (verify_script/
# target_script), and must freeze EVERY existing-file token in `verify`, not
# just the first one. Own CLI helper: this file must stay self-contained.
# ---------------------------------------------------------------------------

UI_CLI_PATH=$(cd "$HERE/../../../.." && pwd -P)
UI_CLI_PATH="$UI_CLI_PATH/bin/.local/bin/flow"
[ -x "$SCAN_DIR/../bin/flow" ] && UI_CLI_PATH="$SCAN_DIR/../bin/flow"

# ui_cli_in <project-dir> <home-dir> <cli-args...>
ui_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$UI_CLI_PATH" "$@"
}

# F1 reproduction: a UI loop with NO --target must still get a non-empty
# target_sha (it guards verify_script instead), and rewriting the verifier
# to always exit 0 must flip the next check to suspect, naming the file.
t_ui_f1_no_target_still_freezes_verify_script() {
	local proj home val
	proj=$(_lu_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/tests/ui"
	printf '#!/bin/sh\nexit 1\n' >"$proj/tests/ui/verify.sh"

	ui_cli_in "$proj" "$home" loop init "ui goal" --verify "sh tests/ui/verify.sh"
	assert_rc 0 "t_ui_f1_no_target_still_freezes_verify_script init rc"

	val=$(grep '^target_sha:' "$proj/.claude/loop/loop.md" | sed 's/^target_sha: *//')
	if [ -n "$val" ]; then
		_pass "t_ui_f1_no_target_still_freezes_verify_script target_sha non-empty"
	else
		_fail "t_ui_f1_no_target_still_freezes_verify_script target_sha non-empty" "target_sha line was empty"
	fi

	printf '#!/bin/sh\nexit 0\n' >"$proj/tests/ui/verify.sh"

	ui_cli_in "$proj" "$home" loop check --json
	assert_contains "$OUT" '"verdict": "suspect"' "t_ui_f1_no_target_still_freezes_verify_script verdict suspect"
	assert_contains "$OUT" "tests/ui/verify.sh" "t_ui_f1_no_target_still_freezes_verify_script tamper names verify.sh"

	rm -rf "$proj" "$home"
}

# A loop with neither --target nor any existing-file token in the verify
# string keeps target_sha "" and never produces a "guarded files changed"
# finding — every existing non-UI loop is unchanged by F1.
t_ui_no_target_no_file_token_stays_empty() {
	local proj home val
	proj=$(_lu_repo)
	home=$(tmp_dir)

	ui_cli_in "$proj" "$home" loop init "no target no tokens" --verify "false"
	assert_rc 0 "t_ui_no_target_no_file_token_stays_empty init rc"

	val=$(grep '^target_sha:' "$proj/.claude/loop/loop.md" | sed 's/^target_sha: *//')
	assert_eq "$val" "" "t_ui_no_target_no_file_token_stays_empty target_sha stays empty"

	ui_cli_in "$proj" "$home" loop check --json
	assert_not_contains "$OUT" "guarded files changed" "t_ui_no_target_no_file_token_stays_empty no tamper finding"

	rm -rf "$proj" "$home"
}

# F2: a verify string with two existing-file tokens ("cat README.md && sh
# tests/ui/verify.sh") must freeze both, and editing either (verify.sh here)
# must be caught.
t_ui_f2_multi_token_verify_freezes_both_files() {
	local proj home verify_line
	proj=$(_lu_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/tests/ui"
	printf '#!/bin/sh\nexit 1\n' >"$proj/tests/ui/verify.sh"

	ui_cli_in "$proj" "$home" loop init "multi token verify" --verify "cat README.md && sh tests/ui/verify.sh"
	assert_rc 0 "t_ui_f2_multi_token_verify_freezes_both_files init rc"

	verify_line=$(grep '^verify_script:' "$proj/.claude/loop/loop.md")
	assert_contains "$verify_line" "README.md" "t_ui_f2_multi_token_verify_freezes_both_files verify_script has README.md"
	assert_contains "$verify_line" "tests/ui/verify.sh" "t_ui_f2_multi_token_verify_freezes_both_files verify_script has verify.sh"

	printf '#!/bin/sh\nexit 0\n' >"$proj/tests/ui/verify.sh"

	ui_cli_in "$proj" "$home" loop check --json
	assert_contains "$OUT" '"verdict": "suspect"' "t_ui_f2_multi_token_verify_freezes_both_files verdict suspect"
	assert_contains "$OUT" "tests/ui/verify.sh" "t_ui_f2_multi_token_verify_freezes_both_files tamper names verify.sh"

	rm -rf "$proj" "$home"
}

# F2: a playwright invocation freezes the spec file token, not "npx" or
# "test" or the flag.
t_ui_f2_playwright_verify_freezes_spec_file() {
	local proj
	proj=$(tmp_dir)
	mkdir -p "$proj/tests/e2e"
	printf 'test("x", () => {});\n' >"$proj/tests/e2e/x.spec.ts"

	_lu_node "
const { findVerifyScript } = require(process.env.LU_LOOP_DIR + '/init.js');
console.log(findVerifyScript('$proj', 'npx playwright test tests/e2e/x.spec.ts --retries=0'));
"
	assert_eq "$OUT" "tests/e2e/x.spec.ts" "t_ui_f2_playwright_verify_freezes_spec_file"

	rm -rf "$proj"
}

# ---------------------------------------------------------------------------
# env_sha — ui-verify.sh's boot config (SERVE/PORT/HEALTH/BOOT/BASE_URL/
# FLOW_UI_SCORE) must be frozen at init the same way verify_sha freezes the
# --verify string: overriding SERVE alone at check time (to serve a
# pre-baked fixture instead of the real app) must flip the verdict to
# suspect, not pass silently with an untouched target_sha/verify_sha.
# ---------------------------------------------------------------------------

# ui_cli_in_serve <project-dir> <home-dir> <serve-cmd> <cli-args...> — like
# ui_cli_in but also sets SERVE/PORT/HEALTH/BOOT for a UI loop's boot config.
ui_cli_in_serve() {
	local dir home serve
	dir=$1
	home=$2
	serve=$3
	shift 3
	run_cmd env "SERVE=$serve" "PORT=58975" "HEALTH=/" "BOOT=10" \
		bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$UI_CLI_PATH" "$@"
}

t_ui_env_sha_catches_serve_override_at_check() {
	local proj home fakebin realsite fixture
	proj=$(_lu_repo)
	home=$(tmp_dir)
	fakebin=$(_ui_fakebin_stub)
	realsite=$(tmp_dir)
	fixture=$(tmp_dir)
	printf '<html><body>REAL BROKEN PAGE</body></html>' >"$realsite/index.html"
	printf '<html><body>Order confirmed</body></html>' >"$fixture/index.html"
	mkdir -p "$proj/tests/ui" "$proj/design"

	local ui_start ui_end
	ui_start=$(grep -n 'EDIT BELOW THIS LINE' "$SCAN_DIR/../skills/loop/templates/ui-verify.sh" | head -1 | cut -d: -f1)
	ui_end=$(grep -n 'EDIT ABOVE THIS LINE' "$SCAN_DIR/../skills/loop/templates/ui-verify.sh" | head -1 | cut -d: -f1)
	{
		sed -n "1,${ui_start}p" "$SCAN_DIR/../skills/loop/templates/ui-verify.sh"
		printf 'test "$(curl -s "$BASE_URL/")" = "<html><body>Order confirmed</body></html>" || { echo "ui-verify: FAIL"; exit 1; }\n'
		sed -n "${ui_end},\$p" "$SCAN_DIR/../skills/loop/templates/ui-verify.sh"
	} >"$proj/tests/ui/verify.sh"
	chmod +x "$proj/tests/ui/verify.sh"

	PATH="$fakebin:$PATH" ui_cli_in_serve "$proj" "$home" "python3 -m http.server 58975 --directory $realsite" \
		loop init "ui goal" --verify "sh tests/ui/verify.sh" --target design
	assert_rc 0 "t_ui_env_sha_catches_serve_override_at_check init rc"

	local val
	val=$(grep '^env_sha:' "$proj/.claude/loop/loop.md" | sed 's/^env_sha: *//')
	if [ -n "$val" ]; then
		_pass "t_ui_env_sha_catches_serve_override_at_check env_sha non-empty"
	else
		_fail "t_ui_env_sha_catches_serve_override_at_check env_sha non-empty" "env_sha line was empty"
	fi

	PATH="$fakebin:$PATH" ui_cli_in_serve "$proj" "$home" "python3 -m http.server 58975 --directory $fixture" \
		loop check --json
	assert_contains "$OUT" '"verdict": "suspect"' "t_ui_env_sha_catches_serve_override_at_check verdict suspect"
	assert_contains "$OUT" "ui-verify env overridden" "t_ui_env_sha_catches_serve_override_at_check names finding"

	rm -rf "$proj" "$home" "$fakebin" "$realsite" "$fixture"
}

# _ui_fakebin_stub — a no-op agent-browser stub, echoes the scratch dir.
_ui_fakebin_stub() {
	local d
	d=$(tmp_dir)
	printf '#!/bin/sh\nexit 0\n' >"$d/agent-browser"
	chmod +x "$d/agent-browser"
	printf '%s' "$d"
}

# F1 (load-bearing half): target_script must stay empty without --target, so
# a plugin update to ui-score never marks an unrelated loop suspect.
t_ui_f1_target_script_empty_without_target() {
	local proj home val
	proj=$(_lu_repo)
	home=$(tmp_dir)
	mkdir -p "$proj/tests/ui"
	printf '#!/bin/sh\nexit 1\n' >"$proj/tests/ui/verify.sh"

	ui_cli_in "$proj" "$home" loop init "no target script hash" --verify "sh tests/ui/verify.sh"
	assert_rc 0 "t_ui_f1_target_script_empty_without_target init rc"

	val=$(grep '^target_script:' "$proj/.claude/loop/loop.md" | sed 's/^target_script: *//')
	assert_eq "$val" "" "t_ui_f1_target_script_empty_without_target"

	rm -rf "$proj" "$home"
}
