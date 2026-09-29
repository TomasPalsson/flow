#!/usr/bin/env bash
# test_case_selfcheck.sh — tests for scripts/case-selfcheck against three tiny
# fixture cases. Sourced by run.sh (HERE and SCAN_DIR are set).
set -u

CSC="$SCAN_DIR/case-selfcheck"
CSC_FIX="$HERE/fixtures/case-selfcheck"

t_case_selfcheck_fixtures() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_case_selfcheck_fixtures (PyYAML absent)\n'
		return
	fi
	run_cmd "$CSC" --root "$CSC_FIX"
	assert_rc 1 "case-selfcheck exits 1 when a fixture fails"
	assert_contains "$OUT" "PASS xhard-good (pristine fails: 1 checks; solution: 1 graders + postcheck ok; skipped: 0)" "good fixture passes"
	assert_contains "$OUT" "FAIL xhard-noop: pristine scaffold passes" "noop fixture fails"
	assert_contains "$OUT" "PASS xhard-routing (shape+scaffold only)" "routing fixture is shape-only"
	assert_contains "$OUT" "case-selfcheck: 2 passed, 1 failed" "summary line"
}

t_case_selfcheck_named_case() {
	if ! python3 -c 'import yaml' >/dev/null 2>&1; then
		printf '  skip t_case_selfcheck_named_case (PyYAML absent)\n'
		return
	fi
	run_cmd "$CSC" --root "$CSC_FIX" xhard-good
	assert_rc 0 "case-selfcheck on xhard-good alone exits 0"
}

# _csc_mkcase <root> <name> <grader-yaml-lines> <scaffold-body>: minimal gradeable case.
_csc_mkcase() {
	local d="$1/$2"
	mkdir -p "$d"
	printf 'schema_version: "1.1"\nname: %s\ntags: [pipeline]\nruns: 1\nexecution:\n  prompt: "p"\n  max_turns: 5\ngraders:\n%s\n' "$2" "$3" >"$d/case.yaml"
	printf '#!/usr/bin/env bash\nset -eu\n%s\n' "$4" >"$d/scaffold.sh"
	printf '#!/usr/bin/env bash\nset -eu\nprintf "x = 2\\n" > a.py\n' >"$d/solution.sh"
	chmod +x "$d/scaffold.sh" "$d/solution.sh"
}

_csc_no_yaml() {
	python3 -c 'import yaml' >/dev/null 2>&1 && return 1
	printf '  skip %s (PyYAML absent)\n' "$1"
	return 0
}

t_case_selfcheck_bad_regex_cleans_up() {
	_csc_no_yaml t_case_selfcheck_bad_regex_cleans_up && return
	local root tmp
	root=$(mktemp -d)
	tmp=$(mktemp -d)
	_csc_mkcase "$root" xhard-badre '  - name: bad
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = ("
    match: contains' 'printf "x = 1\n" > a.py'
	run_cmd env TMPDIR="$tmp" "$CSC" --root "$root"
	assert_rc 1 "invalid regex fails the case, not the run"
	assert_contains "$OUT" "FAIL xhard-badre: grader bad: invalid regex" "invalid regex reported per grader"
	assert_eq "$(find "$tmp" -maxdepth 1 -name 'case-selfcheck.*' | wc -l | tr -d ' ')" "0" "no tmp dirs leaked"
	rm -rf "$root" "$tmp"
}

t_case_selfcheck_bad_match_and_root() {
	_csc_no_yaml t_case_selfcheck_bad_match_and_root && return
	local root
	root=$(mktemp -d)
	_csc_mkcase "$root" xhard-badmatch '  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: matches' 'printf "x = 1\n" > a.py'
	run_cmd "$CSC" --root "$root"
	assert_contains "$OUT" "unknown match" "typo'd match value rejected"
	rm -rf "$root"
	run_cmd "$CSC" --root "$root/does-not-exist"
	assert_rc 2 "nonexistent --root exits 2"
	assert_contains "$OUT" "cannot read root" "nonexistent --root explained"
}

t_case_selfcheck_isolates_git_env() {
	_csc_no_yaml t_case_selfcheck_isolates_git_env && return
	local root seen
	root=$(mktemp -d)
	seen="$root/seen"
	_csc_mkcase "$root" xhard-iso '  - name: g
    type: regex
    target: { source: file, path: a.py }
    pattern: "x = 2"
    match: contains' "printf 'x = 1\\n' > a.py
printf '%s|%s\\n' \"\${GIT_CONFIG_GLOBAL:-unset}\" \"\${GIT_DIR:-unset}\" > \"$seen\""
	run_cmd env GIT_CONFIG_GLOBAL=/tmp/should-not-leak GIT_DIR=/tmp/nope "$CSC" --root "$root"
	assert_rc 0 "isolation fixture passes"
	assert_eq "$(head -1 "$seen")" "/dev/null|unset" "scaffold sees neutral git env"
	rm -rf "$root"
}
