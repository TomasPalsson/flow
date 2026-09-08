#!/usr/bin/env bash
# test_shared_scripts.sh — the shared gate scripts (spec 003 slice G9), t_shared_*
# prefix: check-all, test-changed, detect-project, diff-scope.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/") are set.

SS_DIR=$(cd "$SCAN_DIR/../skills/shared/scripts" && pwd -P)
SS_NODE=$(command -v node)

# _ss_in <dir> <script> [args...] — run a shared script with cwd and HOME set to
# <dir>, so nothing outside the fixture can influence detection.
_ss_in() {
	local d=$1 s=$2
	shift 2
	run_cmd env "HOME=$d" /bin/bash -c 'cd "$1" || exit 99; shift; exec "$@"' _ "$d" "$SS_NODE" "$SS_DIR/$s" "$@"
}

# _ss_in_env <dir> <VAR=VAL> <script> [args...] — same, plus one extra variable.
_ss_in_env() {
	local d=$1 e=$2 s=$3
	shift 3
	run_cmd env "HOME=$d" "$e" /bin/bash -c 'cd "$1" || exit 99; shift; exec "$@"' _ "$d" "$SS_NODE" "$SS_DIR/$s" "$@"
}

# _ss_in_env2 <dir> <VAR=VAL> <VAR=VAL> <script> [args...] — two extra variables.
_ss_in_env2() {
	local d=$1 e1=$2 e2=$3 s=$4
	shift 4
	run_cmd env "HOME=$d" "$e1" "$e2" /bin/bash -c 'cd "$1" || exit 99; shift; exec "$@"' _ "$d" "$SS_NODE" "$SS_DIR/$s" "$@"
}

# _ss_gate <json> <gate-name> — the 5 JSON lines describing one check-all gate.
_ss_gate() {
	printf '%s' "$1" | grep -A5 "\"name\": \"$2\""
}

_ss_git_init() {
	(
		cd "$1" || exit 1
		git init -q .
		git config user.email "test@example.com"
		git config user.name "harness-test"
		git config commit.gpgsign false
	) >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# detect-project — FU-03 depth-1 roots, mixed roots
# ---------------------------------------------------------------------------

t_shared_detect_depth1_roots_become_packages() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/api" "$d/web" "$d/node_modules/junk" "$d/docs"
	printf '[project]\nname="api"\n[tool.pytest.ini_options]\n' >"$d/api/pyproject.toml"
	printf '{"name":"web","scripts":{"test":"vitest","lint":"eslint ."}}\n' >"$d/web/package.json"
	printf '{"name":"junk"}\n' >"$d/node_modules/junk/package.json"

	run_cmd node "$SS_DIR/detect-project" --dir "$d" --format pretty
	assert_rc 0 "t_shared_detect_depth1_roots_become_packages rc"
	assert_contains "$OUT" '"is_monorepo": true' "t_shared_detect_depth1_roots_become_packages monorepo"
	assert_contains "$OUT" '"dir": "api"' "t_shared_detect_depth1_roots_become_packages api-dir"
	assert_contains "$OUT" '"dir": "web"' "t_shared_detect_depth1_roots_become_packages web-dir"
	assert_contains "$OUT" '"test_cmd": "pytest"' "t_shared_detect_depth1_roots_become_packages api-test-cmd"
	assert_contains "$OUT" '"pkg_mgr": "npm"' "t_shared_detect_depth1_roots_become_packages web-pkg-mgr"
	assert_not_contains "$OUT" '"dir": "junk"' "t_shared_detect_depth1_roots_become_packages prunes-node-modules"
	assert_not_contains "$OUT" '"dir": "docs"' "t_shared_detect_depth1_roots_become_packages skips-manifestless-dir"

	rm -rf "$d"
}

# FU-03: a consumer must be able to learn the monorepo's languages from the
# root-level field, not only by walking `packages`.
t_shared_detect_depth1_languages_come_from_packages() {
	local d langs
	d=$(tmp_dir)
	mkdir -p "$d/api" "$d/web" "$d/cli"
	printf '[project]\nname="api"\n' >"$d/api/pyproject.toml"
	printf '{"name":"web","scripts":{"test":"vitest"}}\n' >"$d/web/package.json"
	printf '[package]\nname = "cli"\n' >"$d/cli/Cargo.toml"

	run_cmd node "$SS_DIR/detect-project" --dir "$d"
	assert_rc 0 "t_shared_detect_depth1_languages_come_from_packages rc"
	langs=$(printf '%s' "$OUT" | grep -o '"languages":\[[^]]*\]')
	assert_contains "$langs" '"python"' "t_shared_detect_depth1_languages_come_from_packages python"
	assert_contains "$langs" '"javascript"' "t_shared_detect_depth1_languages_come_from_packages javascript"
	assert_contains "$langs" '"rust"' "t_shared_detect_depth1_languages_come_from_packages rust"
	assert_not_contains "$OUT" '"languages":[]' "t_shared_detect_depth1_languages_come_from_packages not-empty"

	rm -rf "$d"
}

# The spec's FU-03 example (`package.json + pyproject → typescript, python`) is
# read as "a TypeScript root": `language` and `languages` agree that a package
# with no tsconfig.json and no typescript dependency is javascript. This pins the
# no-TS-signal half so the distinction cannot regress into a guess.
t_shared_detect_mixed_root_without_ts_signal_says_javascript() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"

	run_cmd node "$SS_DIR/detect-project" --dir "$d"
	assert_rc 0 "t_shared_detect_mixed_root_without_ts_signal_says_javascript rc"
	assert_contains "$OUT" '"languages":["javascript","python"]' "t_shared_detect_mixed_root_without_ts_signal_says_javascript languages"
	assert_contains "$OUT" '"language":"javascript"' "t_shared_detect_mixed_root_without_ts_signal_says_javascript language"

	rm -rf "$d"
}

t_shared_detect_mixed_root_reports_both_languages() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"
	: >"$d/tsconfig.json"

	run_cmd node "$SS_DIR/detect-project" --dir "$d"
	assert_rc 0 "t_shared_detect_mixed_root_reports_both_languages rc"
	assert_contains "$OUT" '"languages":["typescript","python"]' "t_shared_detect_mixed_root_reports_both_languages languages"
	assert_contains "$OUT" '"is_monorepo":false' "t_shared_detect_mixed_root_reports_both_languages not-a-monorepo"

	rm -rf "$d"
}

t_shared_detect_single_root_keeps_string_packages() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/packages/one"
	printf '{"name":"root","workspaces":["packages/*"]}\n' >"$d/package.json"
	printf '{"name":"one","scripts":{"test":"vitest"}}\n' >"$d/packages/one/package.json"

	run_cmd node "$SS_DIR/detect-project" --dir "$d" --format pretty
	assert_rc 0 "t_shared_detect_single_root_keeps_string_packages rc"
	assert_contains "$OUT" '"packages/one"' "t_shared_detect_single_root_keeps_string_packages workspace-string"
	assert_not_contains "$OUT" '"dir": "packages/one"' "t_shared_detect_single_root_keeps_string_packages no-object-form"

	rm -rf "$d"
}

# readdir reports a symlinked directory as a symlink; a package reached through
# a link (a common way to graft a repo into a workspace) is still a package.
t_shared_detect_depth1_symlinked_package_is_found() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/store/svc"
	printf '[project]\nname="svc"\n[tool.pytest.ini_options]\n' >"$d/store/svc/pyproject.toml"
	ln -s "$d/store/svc" "$d/svc"

	run_cmd node "$SS_DIR/detect-project" --dir "$d" --format pretty
	assert_rc 0 "t_shared_detect_depth1_symlinked_package_is_found rc"
	assert_contains "$OUT" '"is_monorepo": true' "t_shared_detect_depth1_symlinked_package_is_found monorepo"
	assert_contains "$OUT" '"dir": "svc"' "t_shared_detect_depth1_symlinked_package_is_found svc-dir"
	assert_contains "$OUT" '"language": "python"' "t_shared_detect_depth1_symlinked_package_is_found language"
	assert_not_contains "$OUT" '"dir": "store"' "t_shared_detect_depth1_symlinked_package_is_found skips-manifestless-parent"

	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# check-all — C-C JSON contract
# ---------------------------------------------------------------------------

t_shared_check_all_no_ecosystem_json_shape() {
	local d
	d=$(tmp_dir)
	_ss_in "$d" check-all --json
	assert_rc 0 "t_shared_check_all_no_ecosystem_json_shape rc"
	assert_contains "$OUT" '"ecosystem": null' "t_shared_check_all_no_ecosystem_json_shape ecosystem"
	assert_contains "$OUT" '"gates": []' "t_shared_check_all_no_ecosystem_json_shape gates"
	assert_contains "$OUT" '"error": "no_project_file"' "t_shared_check_all_no_ecosystem_json_shape error"
	assert_contains "$OUT" '"message"' "t_shared_check_all_no_ecosystem_json_shape message"
	rm -rf "$d"
}

t_shared_check_all_no_ecosystem_human_output_unchanged() {
	local d
	d=$(tmp_dir)
	_ss_in "$d" check-all
	assert_rc 1 "t_shared_check_all_no_ecosystem_human_output_unchanged rc"
	assert_contains "$ERR" "No supported project file found" "t_shared_check_all_no_ecosystem_human_output_unchanged message"
	assert_eq "$OUT" "" "t_shared_check_all_no_ecosystem_human_output_unchanged empty-stdout"
	rm -rf "$d"
}

t_shared_check_all_test_gate_runs_and_leads_despite_red_lint() {
	local d first
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"lint":"exit 1","test":"exit 0"}}\n' >"$d/package.json"

	_ss_in "$d" check-all --json --continue
	assert_rc 1 "t_shared_check_all_test_gate_runs_and_leads_despite_red_lint rc"
	first=$(printf '%s' "$OUT" | grep '"name"' | head -1)
	assert_contains "$first" '"test"' "t_shared_check_all_test_gate_runs_and_leads_despite_red_lint test-first"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "pass"' "t_shared_check_all_test_gate_runs_and_leads_despite_red_lint test-ran"
	assert_contains "$(_ss_gate "$OUT" lint)" '"status": "fail"' "t_shared_check_all_test_gate_runs_and_leads_despite_red_lint lint-red"
	rm -rf "$d"
}

t_shared_check_all_format_write_script_is_skipped_not_run() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/emptybin"
	printf '{"name":"x","scripts":{"format":"prettier --write ."}}\n' >"$d/package.json"
	printf 'const   a=1\n' >"$d/sentinel.js"

	# No prettier anywhere on PATH: the gate reports why instead of running the
	# script that would rewrite files.
	_ss_in_env "$d" "PATH=$d/emptybin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_format_write_script_is_skipped_not_run rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "skipped"' "t_shared_check_all_format_write_script_is_skipped_not_run skipped"
	assert_contains "$OUT" "format script writes in place; add a format:check script" "t_shared_check_all_format_write_script_is_skipped_not_run message"
	assert_eq "$(cat "$d/sentinel.js")" "const   a=1" "t_shared_check_all_format_write_script_is_skipped_not_run sentinel-untouched"
	rm -rf "$d"
}

# An unknown tool is still not run — but check-all never verified that it writes,
# so the message says only what was checked (the spec sentence is reserved for a
# script proven to write in place).
t_shared_check_all_unrecognised_format_script_is_skipped() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"format":"myfmt --in-place ."}}\n' >"$d/package.json"
	printf 'const   a=1\n' >"$d/sentinel.js"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_unrecognised_format_script_is_skipped rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "skipped"' "t_shared_check_all_unrecognised_format_script_is_skipped skipped"
	assert_contains "$OUT" "format script was not recognised as a check-only command: myfmt --in-place .; add a format:check script" "t_shared_check_all_unrecognised_format_script_is_skipped message"
	assert_not_contains "$OUT" "format script writes in place" "t_shared_check_all_unrecognised_format_script_is_skipped no-unproven-claim"
	assert_eq "$(cat "$d/sentinel.js")" "const   a=1" "t_shared_check_all_unrecognised_format_script_is_skipped sentinel-untouched"
	rm -rf "$d"
}

# A `format` script that is ALREADY read-only is a perfectly good check gate:
# running it is both truthful and more coverage than skipping it.
t_shared_check_all_read_only_format_script_is_run_as_is() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin"
	printf '{"name":"x","scripts":{"format":"prettier --check ."}}\n' >"$d/package.json"
	cat >"$d/stubbin/npm" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$d/npm.log"
exit 0
EOF
	chmod +x "$d/stubbin/npm"

	_ss_in_env "$d" "PATH=$d/stubbin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_read_only_format_script_is_run_as_is rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "pass"' "t_shared_check_all_read_only_format_script_is_run_as_is ran"
	assert_contains "$(_ss_gate "$OUT" format)" '"cmd": "npm run format"' "t_shared_check_all_read_only_format_script_is_run_as_is cmd"
	assert_contains "$(cat "$d/npm.log")" "run format" "t_shared_check_all_read_only_format_script_is_run_as_is invoked"
	assert_not_contains "$OUT" "format script writes in place" "t_shared_check_all_read_only_format_script_is_run_as_is no-false-claim"
	rm -rf "$d"
}

# `biome check .` writes nothing without --write/--fix/--apply.
t_shared_check_all_read_only_biome_format_script_is_run_as_is() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin"
	printf '{"name":"x","scripts":{"format":"biome check ."}}\n' >"$d/package.json"
	printf '#!/bin/sh\nexit 0\n' >"$d/stubbin/npm"
	chmod +x "$d/stubbin/npm"

	_ss_in_env "$d" "PATH=$d/stubbin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_read_only_biome_format_script_is_run_as_is rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "pass"' "t_shared_check_all_read_only_biome_format_script_is_run_as_is ran"
	assert_not_contains "$OUT" "format script writes in place" "t_shared_check_all_read_only_biome_format_script_is_run_as_is no-false-claim"
	rm -rf "$d"
}

# C-C: a gate killed by a signal (the OOM killer, a timeout) produced no verdict.
# Calling it `fail` would block a turn — and seed a phantom baseline — for a
# suite that never finished.
t_shared_check_all_gate_killed_by_signal_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin"
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	cat >"$d/stubbin/npm" <<'EOF'
#!/bin/sh
printf 'vitest starting\n'
kill -9 $$
EOF
	chmod +x "$d/stubbin/npm"

	_ss_in_env "$d" "PATH=$d/stubbin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_gate_killed_by_signal_is_unavailable rc"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "unavailable"' "t_shared_check_all_gate_killed_by_signal_is_unavailable status"
	assert_not_contains "$OUT" '"status": "fail"' "t_shared_check_all_gate_killed_by_signal_is_unavailable never-fail"
	assert_contains "$OUT" "killed by SIGKILL after" "t_shared_check_all_gate_killed_by_signal_is_unavailable names-the-cause"
	rm -rf "$d"
}

# The other way a spawn returns no exit code: the OS refuses to start it. The
# binary exists (so it is not ENOENT) but is not executable.
t_shared_check_all_unexecutable_binary_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/node_modules/.bin"
	printf '{"name":"x","scripts":{"format":"prettier --write ."}}\n' >"$d/package.json"
	printf '#!/bin/sh\nexit 0\n' >"$d/node_modules/.bin/prettier"
	chmod 644 "$d/node_modules/.bin/prettier"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_unexecutable_binary_is_unavailable rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "unavailable"' "t_shared_check_all_unexecutable_binary_is_unavailable status"
	assert_not_contains "$OUT" '"status": "fail"' "t_shared_check_all_unexecutable_binary_is_unavailable never-fail"
	assert_contains "$OUT" "cannot execute (EACCES)" "t_shared_check_all_unexecutable_binary_is_unavailable names-the-cause"
	rm -rf "$d"
}

# A gate that prints more than a pipe capture holds must still be JUDGED. While
# check-all captured through pipes, spawnSync killed such a gate at maxBuffer
# (1 MB by default) and the resulting SIGTERM read as "no verdict": a red lint or
# test suite was reported `unavailable`, which the stop-gate does not block on.
t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin"
	printf '{"name":"x","scripts":{"test":"vitest","lint":"eslint ."}}\n' >"$d/package.json"
	# ~1.5 MB on stdout, then a real failure exit code.
	cat >"$d/stubbin/npm" <<'EOF'
#!/bin/sh
line=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
n=0
while [ "$n" -lt 20000 ]; do
	printf '%s %s\n' "$n" "$line"
	n=$((n + 1))
done
exit 1
EOF
	chmod +x "$d/stubbin/npm"

	_ss_in_env "$d" "PATH=$d/stubbin" check-all --json --continue
	assert_rc 1 "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails rc"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "fail"' "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails test-fail"
	assert_contains "$(_ss_gate "$OUT" lint)" '"status": "fail"' "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails lint-fail"
	assert_not_contains "$OUT" '"status": "unavailable"' "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails never-unavailable"
	assert_not_contains "$OUT" "killed by SIGTERM" "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails no-phantom-signal"
	assert_contains "$OUT" "bytes of output not shown" "t_shared_check_all_gate_louder_than_the_capture_buffer_still_fails says-it-trimmed"
	rm -rf "$d"
}

# The stop-gate pastes `cmd` into "To reproduce: cd <dir> && <cmd>". A repo whose
# path contains a space must still produce a line a shell re-parses into the very
# same command.
t_shared_check_all_reported_cmd_round_trips_through_a_shell() {
	local d p cmd
	d=$(tmp_dir)
	p="$d/my repo"
	mkdir -p "$p/node_modules/.bin"
	printf '{"name":"x","devDependencies":{"typescript":"^5"}}\n' >"$p/package.json"
	printf '{}\n' >"$p/tsconfig.json"
	cat >"$p/node_modules/.bin/tsc" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >>"$p/argv.log"
exit 0
EOF
	chmod +x "$p/node_modules/.bin/tsc"

	_ss_in "$p" check-all --json --continue
	assert_rc 0 "t_shared_check_all_reported_cmd_round_trips_through_a_shell rc"
	cmd=$(printf '%s' "$OUT" | grep '"cmd"' | head -1 | sed 's/.*"cmd": "//; s/",*$//')
	run_cmd /bin/bash -c "cd \"$p\" && $cmd"
	assert_rc 0 "t_shared_check_all_reported_cmd_round_trips_through_a_shell replay-rc"
	assert_eq "$(grep -c -x -- '--noEmit' "$p/argv.log")" "2" "t_shared_check_all_reported_cmd_round_trips_through_a_shell same-argv"
	rm -rf "$d"
}

# The human view has always shown a gate kind with nothing to run as a bare
# `– <kind>` line; the JSON-only explanation must not leak into it.
t_shared_check_all_human_output_has_no_nothing_to_run_line() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"lint":"exit 0"}}\n' >"$d/package.json"

	_ss_in "$d" check-all --continue
	assert_rc 0 "t_shared_check_all_human_output_has_no_nothing_to_run_line rc"
	assert_contains "$ERR" "typecheck" "t_shared_check_all_human_output_has_no_nothing_to_run_line kind-listed"
	assert_not_contains "$ERR" "nothing to run for this gate" "t_shared_check_all_human_output_has_no_nothing_to_run_line no-extra-line"
	assert_contains "$OUT" '"message": "nothing to run for this gate"' "t_shared_check_all_human_output_has_no_nothing_to_run_line kept-in-json"
	rm -rf "$d"
}

t_shared_check_all_installed_prettier_runs_check_never_write() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/node_modules/.bin"
	printf '{"name":"x","scripts":{"format":"prettier --write ."}}\n' >"$d/package.json"
	# A prettier that behaves like the real one: it only writes with --write.
	cat >"$d/node_modules/.bin/prettier" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do
	if [ "$a" = "--write" ]; then printf 'rewritten\n' >sentinel.js; fi
done
exit 0
EOF
	chmod +x "$d/node_modules/.bin/prettier"
	printf 'const   a=1\n' >"$d/sentinel.js"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_installed_prettier_runs_check_never_write rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "pass"' "t_shared_check_all_installed_prettier_runs_check_never_write ran"
	assert_contains "$(_ss_gate "$OUT" format)" "--check" "t_shared_check_all_installed_prettier_runs_check_never_write check-flag"
	assert_not_contains "$(_ss_gate "$OUT" format)" "--write" "t_shared_check_all_installed_prettier_runs_check_never_write no-write-flag"
	assert_eq "$(cat "$d/sentinel.js")" "const   a=1" "t_shared_check_all_installed_prettier_runs_check_never_write sentinel-untouched"
	rm -rf "$d"
}

# FU-06: the common real-world form quotes its glob so the shell does not expand
# it. Whitespace-splitting alone would hand prettier the literal quotes, which it
# reads as part of the pattern — matching nothing and reporting a red format gate
# for a correctly formatted project.
t_shared_check_all_quoted_glob_format_script_keeps_one_argument() {
	local d argv
	d=$(tmp_dir)
	mkdir -p "$d/node_modules/.bin" "$d/src"
	cat >"$d/package.json" <<'EOF'
{"name":"x","scripts":{"format":"prettier --write \"src/**/*.ts\""}}
EOF
	cat >"$d/node_modules/.bin/prettier" <<'EOF'
#!/usr/bin/env bash
for a in "$@"; do printf '[%s]\n' "$a" >>argv.log; done
exit 0
EOF
	chmod +x "$d/node_modules/.bin/prettier"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_quoted_glob_format_script_keeps_one_argument rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "pass"' "t_shared_check_all_quoted_glob_format_script_keeps_one_argument not-red"
	argv=$(cat "$d/argv.log")
	assert_contains "$argv" '[--check]' "t_shared_check_all_quoted_glob_format_script_keeps_one_argument check-flag"
	assert_contains "$argv" '[src/**/*.ts]' "t_shared_check_all_quoted_glob_format_script_keeps_one_argument one-argument"
	assert_not_contains "$argv" '"' "t_shared_check_all_quoted_glob_format_script_keeps_one_argument no-quote-in-argv"
	assert_not_contains "$argv" "[--write]" "t_shared_check_all_quoted_glob_format_script_keeps_one_argument no-write-flag"
	rm -rf "$d"
}

# FU-06: a compound script must never be picked apart — running only its first
# command would run `eslint --fix` (a writer) and call the check gate green.
t_shared_check_all_compound_format_script_is_skipped() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/node_modules/.bin"
	printf '{"name":"x","scripts":{"format":"eslint --fix . && prettier --write ."}}\n' >"$d/package.json"
	cat >"$d/node_modules/.bin/eslint" <<'EOF'
#!/usr/bin/env bash
printf 'REWRITTEN-BY-ESLINT\n' >sentinel.js
exit 0
EOF
	chmod +x "$d/node_modules/.bin/eslint"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$d/node_modules/.bin/prettier"
	chmod +x "$d/node_modules/.bin/prettier"
	printf 'const   a=1\n' >"$d/sentinel.js"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_compound_format_script_is_skipped rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "skipped"' "t_shared_check_all_compound_format_script_is_skipped skipped"
	assert_contains "$OUT" "format script was not recognised as a check-only command" "t_shared_check_all_compound_format_script_is_skipped message"
	assert_not_contains "$(printf '%s' "$OUT" | grep '"cmd"')" "eslint" "t_shared_check_all_compound_format_script_is_skipped eslint-never-in-a-cmd"
	assert_eq "$(cat "$d/sentinel.js")" "const   a=1" "t_shared_check_all_compound_format_script_is_skipped sentinel-untouched"
	rm -rf "$d"
}

# The mirror case: the recognised formatter comes first, so a naive rewrite
# would hand `&&` and the second command to prettier as literal arguments.
t_shared_check_all_compound_format_script_prettier_first_is_skipped() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/node_modules/.bin"
	printf '{"name":"x","scripts":{"format":"prettier --write . && eslint --fix ."}}\n' >"$d/package.json"
	cat >"$d/node_modules/.bin/prettier" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >argv.log
exit 0
EOF
	chmod +x "$d/node_modules/.bin/prettier"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_compound_format_script_prettier_first_is_skipped rc"
	assert_contains "$(_ss_gate "$OUT" format)" '"status": "skipped"' "t_shared_check_all_compound_format_script_prettier_first_is_skipped skipped"
	assert_file_missing "$d/argv.log" "t_shared_check_all_compound_format_script_prettier_first_is_skipped prettier-never-ran"
	rm -rf "$d"
}

# C-C: a uv project that does not have mypy/pytest has no such gate to fail.
# uv IS on PATH here, so the lock-file check is the only thing that can stop a
# `uv run --no-sync` gate from being built — and the stub records any call.
t_shared_check_all_uv_lock_without_tools_has_no_python_gates() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/uvbin"
	printf '[project]\nname="y"\nversion="0.1"\n' >"$d/pyproject.toml"
	printf 'version = 1\n\n[[package]]\nname = "y"\nversion = "0.1"\n' >"$d/uv.lock"
	cat >"$d/uvbin/uv" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >>uv.log
exit 0
EOF
	chmod +x "$d/uvbin/uv"

	_ss_in_env "$d" "PATH=$d/uvbin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_uv_lock_without_tools_has_no_python_gates rc"
	assert_file_missing "$d/uv.log" "t_shared_check_all_uv_lock_without_tools_has_no_python_gates uv-never-invoked"
	assert_not_contains "$OUT" '"status": "fail"' "t_shared_check_all_uv_lock_without_tools_has_no_python_gates nothing-red"
	assert_not_contains "$OUT" "uv run --no-sync" "t_shared_check_all_uv_lock_without_tools_has_no_python_gates no-fabricated-cmd"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "skipped"' "t_shared_check_all_uv_lock_without_tools_has_no_python_gates test-skipped"
	assert_contains "$(_ss_gate "$OUT" typecheck)" '"status": "skipped"' "t_shared_check_all_uv_lock_without_tools_has_no_python_gates typecheck-skipped"
	rm -rf "$d"
}

# `uv run` answers a missing tool with exit 2 + "Failed to spawn", not 127.
t_shared_check_all_uv_spawn_failure_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/uvbin"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"
	printf 'version = 1\n\n[[package]]\nname = "mypy"\nversion = "1.0"\n' >"$d/uv.lock"
	cat >"$d/uvbin/uv" <<'EOF'
#!/bin/sh
printf 'error: Failed to spawn: `mypy`\n  Caused by: No such file or directory (os error 2)\n' >&2
exit 2
EOF
	chmod +x "$d/uvbin/uv"

	_ss_in_env "$d" "PATH=$d/uvbin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_uv_spawn_failure_is_unavailable rc"
	assert_contains "$(_ss_gate "$OUT" typecheck)" '"status": "unavailable"' "t_shared_check_all_uv_spawn_failure_is_unavailable status"
	assert_not_contains "$OUT" '"status": "fail"' "t_shared_check_all_uv_spawn_failure_is_unavailable never-fail"
	assert_contains "$OUT" '"message": "cannot run: uv run --no-sync mypy ."' "t_shared_check_all_uv_spawn_failure_is_unavailable message"
	rm -rf "$d"
}

# The mirror of the case above: a genuinely failing suite that merely PRINTS the
# spawn-error words (in an assertion message, a captured log) is still red. Only
# uv's own exit 2 + stderr line naming this gate's tool means "could not run".
t_shared_check_all_uv_failure_quoting_spawn_error_stays_red() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/uvbin"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"
	printf 'version = 1\n\n[[package]]\nname = "pytest"\nversion = "8.0"\n' >"$d/uv.lock"
	cat >"$d/uvbin/uv" <<'EOF'
#!/bin/sh
printf "FAILED tests/test_x.py::test_msg - AssertionError: expected 'error: Failed to spawn: \`mypy\`'\n"
printf '1 failed, 0 passed\n'
exit 1
EOF
	chmod +x "$d/uvbin/uv"

	_ss_in_env "$d" "PATH=$d/uvbin" check-all --json --continue
	assert_rc 1 "t_shared_check_all_uv_failure_quoting_spawn_error_stays_red rc"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "fail"' "t_shared_check_all_uv_failure_quoting_spawn_error_stays_red failed"
	assert_not_contains "$OUT" '"status": "unavailable"' "t_shared_check_all_uv_failure_quoting_spawn_error_stays_red not-unavailable"
	rm -rf "$d"
}

# A consumer selects a gate by `kind`; the display name may carry an ecosystem
# suffix when a root has several.
t_shared_check_all_gate_records_carry_kind() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/.venv/bin"
	printf '{"name":"x","scripts":{"lint":"exit 0"}}\n' >"$d/package.json"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$d/.venv/bin/ruff"
	chmod +x "$d/.venv/bin/ruff"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_gate_records_carry_kind rc"
	assert_contains "$OUT" '"kind": "test"' "t_shared_check_all_gate_records_carry_kind test-kind"
	assert_contains "$OUT" '"name": "lint:python"' "t_shared_check_all_gate_records_carry_kind suffixed-name"
	assert_contains "$(printf '%s' "$OUT" | grep -B1 '"name": "lint:python"')" '"kind": "lint"' "t_shared_check_all_gate_records_carry_kind suffixed-kind"
	rm -rf "$d"
}

# C-C: under --json no ANSI ever reaches stdout — help included.
t_shared_check_all_json_help_has_no_ansi() {
	local d esc
	d=$(tmp_dir)
	esc=$(printf '\033')
	_ss_in "$d" check-all --json --help
	assert_rc 0 "t_shared_check_all_json_help_has_no_ansi rc"
	assert_contains "$OUT" "run project quality gates" "t_shared_check_all_json_help_has_no_ansi body"
	assert_not_contains "$OUT" "$esc" "t_shared_check_all_json_help_has_no_ansi no-escape-bytes"
	rm -rf "$d"
}

t_shared_check_all_missing_runner_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/emptybin"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"

	_ss_in_env "$d" "PATH=$d/emptybin" check-all --json --continue
	assert_rc 0 "t_shared_check_all_missing_runner_is_unavailable rc"
	assert_contains "$(_ss_gate "$OUT" test)" '"status": "unavailable"' "t_shared_check_all_missing_runner_is_unavailable status"
	assert_contains "$OUT" '"message": "cannot run: npm run test"' "t_shared_check_all_missing_runner_is_unavailable message"
	assert_contains "$OUT" '"unavailable": 1' "t_shared_check_all_missing_runner_is_unavailable summary"
	rm -rf "$d"
}

t_shared_check_all_uses_lockfile_package_manager() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	: >"$d/bun.lock"

	_ss_in "$d" check-all --json --continue
	assert_contains "$OUT" '"cmd": "bun run test"' "t_shared_check_all_uses_lockfile_package_manager bun"
	assert_not_contains "$OUT" '"cmd": "npm run test"' "t_shared_check_all_uses_lockfile_package_manager not-npm"
	rm -rf "$d"
}

t_shared_check_all_skips_tsc_without_typescript() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf '{}\n' >"$d/tsconfig.json"

	_ss_in "$d" check-all --json --continue
	assert_contains "$(_ss_gate "$OUT" typecheck)" '"status": "skipped"' "t_shared_check_all_skips_tsc_without_typescript skipped"
	assert_contains "$OUT" "no typescript dependency and no node_modules" "t_shared_check_all_skips_tsc_without_typescript message"
	assert_not_contains "$OUT" "npx" "t_shared_check_all_skips_tsc_without_typescript no-npx"
	rm -rf "$d"
}

t_shared_check_all_tsc_writes_buildinfo_under_tmpdir() {
	local d tmp
	d=$(tmp_dir)
	tmp="${TMPDIR:-/tmp}"
	tmp="${tmp%/}"
	mkdir -p "$d/node_modules/.bin"
	printf '{"name":"x","devDependencies":{"typescript":"^5"}}\n' >"$d/package.json"
	printf '{}\n' >"$d/tsconfig.json"
	printf '#!/usr/bin/env bash\nexit 0\n' >"$d/node_modules/.bin/tsc"
	chmod +x "$d/node_modules/.bin/tsc"

	_ss_in "$d" check-all --json --continue
	assert_contains "$(_ss_gate "$OUT" typecheck)" '"status": "pass"' "t_shared_check_all_tsc_writes_buildinfo_under_tmpdir ran"
	assert_contains "$OUT" "--tsBuildInfoFile $tmp/check-all" "t_shared_check_all_tsc_writes_buildinfo_under_tmpdir tmpdir-path"
	assert_file_missing "$d/tsconfig.tsbuildinfo" "t_shared_check_all_tsc_writes_buildinfo_under_tmpdir nothing-in-repo"
	rm -rf "$d"
}

t_shared_check_all_mixed_root_gates_both_ecosystems() {
	local d
	d=$(tmp_dir)
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf '[project]\nname="y"\n' >"$d/pyproject.toml"

	_ss_in "$d" check-all --json --continue
	assert_rc 0 "t_shared_check_all_mixed_root_gates_both_ecosystems rc"
	assert_contains "$OUT" '"ecosystem": "node+python"' "t_shared_check_all_mixed_root_gates_both_ecosystems ecosystem"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# test-changed — C-C JSON contract, FU-19
# ---------------------------------------------------------------------------

t_shared_test_changed_honours_cc_changed_files() {
	local d
	d=$(tmp_dir)
	_ss_git_init "$d"
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	printf 'export const b = 1;\n' >"$d/src/b.js"
	printf 'test("b", () => {});\n' >"$d/src/b.test.js"
	(cd "$d" && git add -A && git commit -q -m init) >/dev/null 2>&1
	printf 'export const a = 2;\n' >"$d/src/a.js"
	printf 'export const b = 2;\n' >"$d/src/b.js"

	_ss_in_env "$d" "CC_CHANGED_FILES=src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_honours_cc_changed_files rc"
	assert_contains "$OUT" '"changed_files":["src/a.js"]' "t_shared_test_changed_honours_cc_changed_files exact-list"
	assert_not_contains "$OUT" "src/b.js" "t_shared_test_changed_honours_cc_changed_files git-diff-not-used"
	assert_contains "$OUT" '"src/a.test.js"' "t_shared_test_changed_honours_cc_changed_files mapped-test"
	rm -rf "$d"
}

# C-C: SET-but-empty is "this turn changed nothing" — it must never fall back
# to the whole-branch `git diff base...HEAD` the contract exists to prevent.
t_shared_test_changed_empty_cc_changed_files_never_calls_git() {
	local d
	d=$(tmp_dir)
	_ss_git_init "$d"
	mkdir -p "$d/shimbin" "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	cat >"$d/shimbin/git" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >>"$d/git-calls.log"
exit 0
EOF
	chmod +x "$d/shimbin/git"

	_ss_in_env2 "$d" "PATH=$d/shimbin" "CC_CHANGED_FILES=" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_empty_cc_changed_files_never_calls_git rc"
	assert_contains "$OUT" '"status":"no-tests"' "t_shared_test_changed_empty_cc_changed_files_never_calls_git status"
	assert_contains "$OUT" '"message":"no changed files"' "t_shared_test_changed_empty_cc_changed_files_never_calls_git message"
	assert_contains "$OUT" '"changed_files":[]' "t_shared_test_changed_empty_cc_changed_files_never_calls_git empty-list"
	assert_file_missing "$d/git-calls.log" "t_shared_test_changed_empty_cc_changed_files_never_calls_git no-git-invocation"
	rm -rf "$d"
}

# A test path with a space must reach the runner as ONE argument: splitting it
# turns a green suite into a red one, and C-C makes passed:false a block.
t_shared_test_changed_space_in_path_stays_one_argument() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin" "$d/src"
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/my comp.js"
	printf 'test("a", () => {});\n' >"$d/src/my comp.test.js"
	printf 'test("b", () => {});\n' >"$d/src/other1.test.js"
	printf 'test("c", () => {});\n' >"$d/src/other2.test.js"
	cat >"$d/stubbin/npx" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >>"$d/argv.log"
exit 0
EOF
	chmod +x "$d/stubbin/npx"

	_ss_in_env2 "$d" "PATH=$d/stubbin" "CC_CHANGED_FILES=src/my comp.js" test-changed --json
	assert_rc 0 "t_shared_test_changed_space_in_path_stays_one_argument rc"
	assert_contains "$OUT" '"status":"ran"' "t_shared_test_changed_space_in_path_stays_one_argument status"
	assert_contains "$OUT" '"passed":true' "t_shared_test_changed_space_in_path_stays_one_argument passed"
	assert_eq "$(grep -c -x 'src/my comp.test.js' "$d/argv.log")" "1" "t_shared_test_changed_space_in_path_stays_one_argument one-argv-entry"
	assert_eq "$(grep -c -x 'src/my' "$d/argv.log")" "0" "t_shared_test_changed_space_in_path_stays_one_argument not-split"
	rm -rf "$d"
}

# A repository file name is data: it must never be re-parsed by a shell.
t_shared_test_changed_command_substitution_in_filename_is_inert() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a\$(touch PWNED).js"

	_ss_in_env "$d" 'CC_CHANGED_FILES=src/a$(touch PWNED).js' test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_command_substitution_in_filename_is_inert rc"
	assert_file_missing "$d/PWNED" "t_shared_test_changed_command_substitution_in_filename_is_inert no-side-effect"
	assert_file_missing "$d/src/PWNED" "t_shared_test_changed_command_substitution_in_filename_is_inert no-side-effect-in-src"
	rm -rf "$d"
}

t_shared_test_changed_no_changes_reports_no_tests() {
	local d
	d=$(tmp_dir)
	_ss_git_init "$d"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	(cd "$d" && git add -A && git commit -q -m init) >/dev/null 2>&1

	_ss_in "$d" test-changed --json
	assert_rc 0 "t_shared_test_changed_no_changes_reports_no_tests rc"
	assert_contains "$OUT" '"status":"no-tests"' "t_shared_test_changed_no_changes_reports_no_tests status"
	assert_contains "$OUT" '"passed":null' "t_shared_test_changed_no_changes_reports_no_tests passed-null"
	rm -rf "$d"
}

t_shared_test_changed_missing_runner_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/emptybin" "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"

	_ss_in_env2 "$d" "PATH=$d/emptybin" "CC_CHANGED_FILES=src/a.js" test-changed --json
	assert_rc 1 "t_shared_test_changed_missing_runner_is_unavailable rc"
	assert_contains "$OUT" '"status":"unavailable"' "t_shared_test_changed_missing_runner_is_unavailable status"
	assert_contains "$OUT" '"passed":null' "t_shared_test_changed_missing_runner_is_unavailable passed-null"
	assert_contains "$OUT" "test runner could not be executed: npm run test" "t_shared_test_changed_missing_runner_is_unavailable message"
	rm -rf "$d"
}

# C-C: a runner killed by a signal never judged anything. Reporting it as
# status "ran" + passed:false would block the turn and invent an exit code the
# child never produced.
t_shared_test_changed_runner_killed_by_signal_is_unavailable() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin" "$d/src"
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	cat >"$d/stubbin/npx" <<'EOF'
#!/bin/sh
printf 'vitest starting\n'
kill -9 $$
EOF
	chmod +x "$d/stubbin/npx"

	_ss_in_env2 "$d" "PATH=$d/stubbin" "CC_CHANGED_FILES=src/a.js" test-changed --json
	assert_rc 1 "t_shared_test_changed_runner_killed_by_signal_is_unavailable rc"
	assert_contains "$OUT" '"status":"unavailable"' "t_shared_test_changed_runner_killed_by_signal_is_unavailable status"
	assert_contains "$OUT" '"passed":null' "t_shared_test_changed_runner_killed_by_signal_is_unavailable passed-null"
	assert_contains "$OUT" '"exit_code":null' "t_shared_test_changed_runner_killed_by_signal_is_unavailable no-invented-exit-code"
	assert_contains "$OUT" "killed by SIGKILL after" "t_shared_test_changed_runner_killed_by_signal_is_unavailable names-the-cause"
	assert_not_contains "$OUT" '"status":"ran"' "t_shared_test_changed_runner_killed_by_signal_is_unavailable never-ran"
	rm -rf "$d"
}

# --dry-run maps tests and deliberately runs none of them: the message has to say
# so, because the status enum has no word for it.
t_shared_test_changed_dry_run_message_states_what_would_run() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"

	_ss_in_env "$d" "CC_CHANGED_FILES=src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_dry_run_message_states_what_would_run rc"
	assert_contains "$OUT" '"dry_run":true' "t_shared_test_changed_dry_run_message_states_what_would_run flag"
	assert_contains "$OUT" '"message":"dry run: 1 test file(s) would run; nothing was executed' "t_shared_test_changed_dry_run_message_states_what_would_run message"
	assert_contains "$OUT" '"test_files":["src/a.test.js"]' "t_shared_test_changed_dry_run_message_states_what_would_run mapped"
	rm -rf "$d"
}

# `test_cmd` is pasted into the stop-gate's reproduce line, so a test path with a
# space has to survive being re-parsed by a shell.
t_shared_test_changed_reported_cmd_round_trips_through_a_shell() {
	local d cmd
	d=$(tmp_dir)
	mkdir -p "$d/stubbin" "$d/src"
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/my comp.js"
	printf 'test("a", () => {});\n' >"$d/src/my comp.test.js"
	printf 'test("b", () => {});\n' >"$d/src/other1.test.js"
	printf 'test("c", () => {});\n' >"$d/src/other2.test.js"
	cat >"$d/stubbin/npx" <<EOF
#!/bin/sh
printf '%s\n' "\$@" >>"$d/argv.log"
exit 0
EOF
	chmod +x "$d/stubbin/npx"

	_ss_in_env2 "$d" "PATH=$d/stubbin" "CC_CHANGED_FILES=src/my comp.js" test-changed --json
	assert_rc 0 "t_shared_test_changed_reported_cmd_round_trips_through_a_shell rc"
	cmd=$(printf '%s' "$OUT" | sed 's/.*"test_cmd":"//; s/","test_files.*//')
	run_cmd env "PATH=$d/stubbin:$PATH" /bin/bash -c "cd \"$d\" && $cmd"
	assert_rc 0 "t_shared_test_changed_reported_cmd_round_trips_through_a_shell replay-rc"
	assert_eq "$(grep -c -x 'src/my comp.test.js' "$d/argv.log")" "2" "t_shared_test_changed_reported_cmd_round_trips_through_a_shell same-argv"
	rm -rf "$d"
}

t_shared_test_changed_no_runner_at_all_is_unavailable() {
	local d
	d=$(tmp_dir)
	printf 'hello\n' >"$d/notes.txt"

	_ss_in_env "$d" "CC_CHANGED_FILES=notes.txt" test-changed --json
	assert_rc 1 "t_shared_test_changed_no_runner_at_all_is_unavailable rc"
	assert_contains "$OUT" '"status":"unavailable"' "t_shared_test_changed_no_runner_at_all_is_unavailable status"
	assert_contains "$OUT" "no test runner found" "t_shared_test_changed_no_runner_at_all_is_unavailable message"
	rm -rf "$d"
}

t_shared_test_changed_python_in_file_tests_map_to_themselves() {
	local d
	d=$(tmp_dir)
	printf '[project]\nname="y"\n[tool.pytest.ini_options]\n' >"$d/pyproject.toml"
	printf 'def add(a, b):\n    return a + b\n\n\ndef test_add():\n    assert add(1, 1) == 2\n' >"$d/mod.py"
	printf 'def test_other():\n    assert True\n' >"$d/test_other.py"
	printf 'def test_third():\n    assert True\n' >"$d/test_third.py"

	_ss_in_env "$d" "CC_CHANGED_FILES=mod.py" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_python_in_file_tests_map_to_themselves rc"
	assert_contains "$OUT" '"test_files":["mod.py"]' "t_shared_test_changed_python_in_file_tests_map_to_themselves self-mapped"
	rm -rf "$d"
}

t_shared_test_changed_rust_in_file_tests_map_to_themselves() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '[package]\nname = "x"\n' >"$d/Cargo.toml"
	printf 'pub fn add(a: i32) -> i32 { a }\n\n#[cfg(test)]\nmod tests {\n    #[test]\n    fn works() {}\n}\n' >"$d/src/lib.rs"

	_ss_in_env "$d" "CC_CHANGED_FILES=src/lib.rs" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_rust_in_file_tests_map_to_themselves rc"
	assert_contains "$OUT" '"src/lib.rs"' "t_shared_test_changed_rust_in_file_tests_map_to_themselves self-mapped"
	assert_contains "$OUT" '"test_cmd":"cargo test"' "t_shared_test_changed_rust_in_file_tests_map_to_themselves runner"
	rm -rf "$d"
}

t_shared_test_changed_maps_to_the_files_own_package() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/web/src" "$d/api"
	printf '{"name":"web","scripts":{"test":"exit 0"}}\n' >"$d/web/package.json"
	printf 'export const a = 1;\n' >"$d/web/src/a.js"
	printf 'test("a", () => {});\n' >"$d/web/src/a.test.js"
	printf 'test("z", () => {});\n' >"$d/web/src/z.test.js"
	printf 'test("y", () => {});\n' >"$d/web/src/y.test.js"
	printf '[project]\nname="api"\n' >"$d/api/pyproject.toml"

	_ss_in_env "$d" "CC_CHANGED_FILES=web/src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_maps_to_the_files_own_package rc"
	assert_contains "$OUT" '"package_root":"web"' "t_shared_test_changed_maps_to_the_files_own_package package-root"
	assert_contains "$OUT" '"test_files":["src/a.test.js"]' "t_shared_test_changed_maps_to_the_files_own_package package-relative"
	assert_contains "$OUT" '"test_cmd":"npm run test -- src/a.test.js"' "t_shared_test_changed_maps_to_the_files_own_package package-runner"
	rm -rf "$d"
}

t_shared_test_changed_runs_full_suite_past_40_percent() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"

	_ss_in_env "$d" "CC_CHANGED_FILES=src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_runs_full_suite_past_40_percent rc"
	assert_contains "$OUT" "of the suite); the full suite is used" "t_shared_test_changed_runs_full_suite_past_40_percent message"
	assert_contains "$OUT" '"test_cmd":"npm run test"' "t_shared_test_changed_runs_full_suite_past_40_percent unfiltered-cmd"
	rm -rf "$d"
}

t_shared_test_changed_keeps_filter_below_40_percent() {
	local d i
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	for i in 1 2 3 4; do
		printf 'test("x", () => {});\n' >"$d/src/other$i.test.js"
	done

	_ss_in_env "$d" "CC_CHANGED_FILES=src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_keeps_filter_below_40_percent rc"
	assert_contains "$OUT" '"test_cmd":"npm run test -- src/a.test.js"' "t_shared_test_changed_keeps_filter_below_40_percent filtered-cmd"
	assert_not_contains "$OUT" "the full suite is used" "t_shared_test_changed_keeps_filter_below_40_percent no-full-suite-note"
	rm -rf "$d"
}

# A runner that prints more than a pipe capture holds still produced a verdict.
# Reporting it "unavailable" would hand the stop-gate a non-blocking result for a
# suite that really failed.
t_shared_test_changed_noisy_failing_runner_is_a_real_verdict() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/stubbin" "$d/src"
	printf '{"name":"x","scripts":{"test":"vitest"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	# ~1.5 MB on stdout, a sentinel proving it ran, then a real failure.
	cat >"$d/stubbin/npx" <<'EOF'
#!/bin/sh
: >ran.flag
line=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
n=0
while [ "$n" -lt 20000 ]; do
	printf '%s %s\n' "$n" "$line"
	n=$((n + 1))
done
exit 1
EOF
	chmod +x "$d/stubbin/npx"

	_ss_in_env2 "$d" "PATH=$d/stubbin" "CC_CHANGED_FILES=src/a.js" test-changed --json
	assert_rc 1 "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict rc"
	assert_file_exists "$d/ran.flag" "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict runner-ran"
	assert_contains "$OUT" '"status":"ran"' "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict status"
	assert_contains "$OUT" '"passed":false' "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict passed"
	assert_contains "$OUT" '"exit_code":1' "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict exit-code"
	assert_not_contains "$OUT" "unavailable" "t_shared_test_changed_noisy_failing_runner_is_a_real_verdict never-unavailable"
	rm -rf "$d"
}

# A change set spanning two packages runs BOTH. Testing only the package with the
# most changed files and reporting passed:true would let the other package's red
# suite through: the stop-gate blocks only on passed:false.
t_shared_test_changed_runs_every_changed_package() {
	local d cc
	d=$(tmp_dir)
	mkdir -p "$d/pkg-a/src" "$d/pkg-b/src"
	printf '{"name":"a","scripts":{"test":"touch ../ran-a"}}\n' >"$d/pkg-a/package.json"
	printf '{"name":"b","scripts":{"test":"touch ../ran-b; exit 1"}}\n' >"$d/pkg-b/package.json"
	printf 'export const m = 1;\n' >"$d/pkg-a/src/m.js"
	printf 'test("m", () => {});\n' >"$d/pkg-a/src/m.test.js"
	printf 'export const m = 1;\n' >"$d/pkg-b/src/m.js"
	printf 'test("m", () => {});\n' >"$d/pkg-b/src/m.test.js"
	cc=$(printf 'pkg-a/src/m.js\npkg-a/src/m.test.js\npkg-b/src/m.js')

	_ss_in_env "$d" "CC_CHANGED_FILES=$cc" test-changed --json
	assert_rc 1 "t_shared_test_changed_runs_every_changed_package rc"
	assert_file_exists "$d/ran-a" "t_shared_test_changed_runs_every_changed_package majority-ran"
	assert_file_exists "$d/ran-b" "t_shared_test_changed_runs_every_changed_package minority-ran"
	assert_contains "$OUT" '"status":"ran"' "t_shared_test_changed_runs_every_changed_package status"
	assert_contains "$OUT" '"passed":false' "t_shared_test_changed_runs_every_changed_package red-wins"
	assert_contains "$OUT" '"package_root":"pkg-b"' "t_shared_test_changed_runs_every_changed_package names-the-red-package"
	assert_contains "$OUT" "pkg-a passed" "t_shared_test_changed_runs_every_changed_package message-a"
	assert_contains "$OUT" "pkg-b failed" "t_shared_test_changed_runs_every_changed_package message-b"
	rm -rf "$d"
}

# `dir.startsWith(ROOT)` is true for the SIBLING `<root>-evil`: a `../`-relative
# change-set entry could pick that directory's manifest and run its test command
# with cwd outside the project, then report the result as this project's verdict.
t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root() {
	local d sib cc
	d=$(tmp_dir)
	sib="${d}-evil"
	mkdir -p "$sib/src" "$d/src"
	printf '{"name":"r","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"
	printf '{"name":"evil","scripts":{"test":"touch evil.flag"}}\n' >"$sib/package.json"
	printf 'export const a = 1;\n' >"$sib/src/a.js"
	cc=$(printf '../%s/src/a.js\nsrc/a.js' "$(basename "$sib")")

	_ss_in_env "$d" "CC_CHANGED_FILES=$cc" test-changed --json
	assert_rc 0 "t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root rc"
	assert_file_missing "$sib/evil.flag" "t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root outside-suite-never-ran"
	assert_contains "$OUT" '"package_root":""' "t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root stays-in-project"
	assert_contains "$OUT" "outside the project root" "t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root says-what-it-dropped"
	assert_not_contains "$OUT" '"changed_files":["../' "t_shared_test_changed_sibling_prefix_directory_is_not_a_package_root drops-the-entry"
	rm -rf "$d" "$sib"
}

# --dry-run executes nothing, so no part of its message may claim a run: the 40%
# note is shared with real runs and has to read the same either way.
t_shared_test_changed_dry_run_never_claims_an_execution() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '{"name":"x","scripts":{"test":"exit 0"}}\n' >"$d/package.json"
	printf 'export const a = 1;\n' >"$d/src/a.js"
	printf 'test("a", () => {});\n' >"$d/src/a.test.js"

	_ss_in_env "$d" "CC_CHANGED_FILES=src/a.js" test-changed --json --dry-run
	assert_rc 0 "t_shared_test_changed_dry_run_never_claims_an_execution rc"
	assert_contains "$OUT" "nothing was executed" "t_shared_test_changed_dry_run_never_claims_an_execution states-the-fact"
	assert_contains "$OUT" "the full suite is used" "t_shared_test_changed_dry_run_never_claims_an_execution tense-neutral-note"
	assert_not_contains "$OUT" "ran the full suite" "t_shared_test_changed_dry_run_never_claims_an_execution no-past-tense-claim"
	rm -rf "$d"
}

# ---------------------------------------------------------------------------
# diff-scope — FU-33
# ---------------------------------------------------------------------------

t_shared_diff_scope_accepts_json_flag() {
	local d
	d=$(tmp_dir)
	_ss_git_init "$d"
	printf 'hello\n' >"$d/a.txt"
	(cd "$d" && git add -A && git commit -q -m init) >/dev/null 2>&1
	printf 'bye\n' >>"$d/a.txt"

	_ss_in "$d" diff-scope --json
	assert_rc 0 "t_shared_diff_scope_accepts_json_flag rc"
	assert_contains "$OUT" '"base_branch"' "t_shared_diff_scope_accepts_json_flag json-body"
	assert_not_contains "$OUT" "Branch not found" "t_shared_diff_scope_accepts_json_flag flag-not-a-branch"
	rm -rf "$d"
}

t_shared_diff_scope_json_wins_over_pretty() {
	local d
	d=$(tmp_dir)
	_ss_git_init "$d"
	printf 'hello\n' >"$d/a.txt"
	(cd "$d" && git add -A && git commit -q -m init) >/dev/null 2>&1
	printf 'bye\n' >>"$d/a.txt"

	_ss_in "$d" diff-scope --json --format pretty
	assert_rc 0 "t_shared_diff_scope_json_wins_over_pretty rc"
	assert_contains "$OUT" '"changed_files"' "t_shared_diff_scope_json_wins_over_pretty json-body"
	assert_not_contains "$OUT" "git change analysis" "t_shared_diff_scope_json_wins_over_pretty no-pretty-header"
	rm -rf "$d"
}
