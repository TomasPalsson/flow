#!/usr/bin/env bash
# test_digest.sh — `flow digest` over fixture NOTES.md files, and the digest
# `flow finish off` prints. Sourced by run.sh; every t_digest_* is discovered.
set -u

DG_CLI_PATH="$SCAN_DIR/../bin/flow"

# dg_cli_in <project-dir> <home-dir> <args...>
dg_cli_in() {
	local dir home
	dir=$1
	home=$2
	shift 2
	run_cmd bash -c 'cd "$1" || exit 1; export HOME="$2"; shift 2; exec "$@"' \
		_ "$dir" "$home" node "$DG_CLI_PATH" "$@"
}

# dg_feature <repo> — a current feature with no NOTES.md yet.
dg_feature() {
	mkdir -p "$1/.specs/001-x"
	printf '# Spec\n' >"$1/.specs/001-x/spec.md"
	printf '001-x\n' >"$1/.specs/.current"
}

dg_notes() {
	cat >"$1/.specs/001-x/NOTES.md" <<'NOTES'
# Notes
- Ruling: kept the cap at 3 — reviewer disagreed
- Assumption: staging db is disposable — evidence: README.md:12
- Discovered: a.py:4 — swallowed error — defer
- Discovered: b.py:9 — wrong format string — defer → I-003
- Discovered: c.py — extra helper — fold into T004
- Discovered: d.py:2 — injectable query — defer
NOTES
}

t_digest_orders_and_numbers_lines() {
	local home proj order
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	dg_notes "$proj"
	dg_cli_in "$proj" "$home" digest
	assert_rc 0 "digest exits 0"
	assert_contains "$OUT" "NOTES.md:4 Discovered (unfiled defer): a.py:4" "first unfiled defer, line 4"
	assert_contains "$OUT" "NOTES.md:7 Discovered (unfiled defer): d.py:2" "second unfiled defer, line 7"
	assert_contains "$OUT" "NOTES.md:3 Assumption: staging db is disposable [evidence: README.md:12]" "assumption with evidence"
	assert_contains "$OUT" "NOTES.md:2 Ruling: kept the cap at 3" "ruling"
	assert_not_contains "$OUT" "b.py" "filed defer is excluded"
	assert_not_contains "$OUT" "c.py" "fold-into line is excluded"
	order=$(printf '%s\n' "$OUT" | grep -o 'Discovered\|Assumption\|Ruling' | tr '\n' ' ')
	assert_eq "Discovered Discovered Assumption Ruling " "$order" "order: defers, assumptions, rulings"
}

t_digest_json_shape() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	dg_notes "$proj"
	dg_cli_in "$proj" "$home" digest --json
	assert_rc 0 "digest --json exits 0"
	assert_contains "$OUT" '"line": 4' "json carries the line number"
	assert_contains "$OUT" '"evidence": "README.md:12"' "json carries evidence"
}

t_digest_silent_when_empty() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	dg_cli_in "$proj" "$home" digest
	assert_rc 0 "no NOTES.md exits 0"
	assert_eq "" "$OUT" "no NOTES.md prints nothing"
	printf '# Notes\n- Discovered: x.py — y — defer → I-001\n' >"$proj/.specs/001-x/NOTES.md"
	dg_cli_in "$proj" "$home" digest
	assert_rc 0 "only filed defers exits 0"
	assert_eq "" "$OUT" "only filed defers prints nothing"
}

t_digest_finish_off_prints_it() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	dg_notes "$proj"
	dg_cli_in "$proj" "$home" finish on
	dg_cli_in "$proj" "$home" finish off
	assert_rc 0 "finish off exits 0"
	assert_contains "$OUT" "finish: disarmed .specs/001-x" "finish off disarms"
	assert_contains "$OUT" "NOTES.md:4 Discovered (unfiled defer): a.py:4" "finish off prints the digest"
	printf '# Notes\n' >"$proj/.specs/001-x/NOTES.md"
	dg_cli_in "$proj" "$home" finish on
	dg_cli_in "$proj" "$home" finish off
	assert_not_contains "$OUT" "Attention" "empty digest adds no output"
}

# One unfiled defer and one filed defer: the --json digest carries exactly one
# entry of kind discovered (the unfiled one), which the PR body's Left out
# section is filled from.
t_digest_json_one_unfiled_defer_is_one_discovered_entry() {
	local home proj n
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	cat >"$proj/.specs/001-x/NOTES.md" <<'NOTES'
# Notes
- Discovered: a.py:4 — swallowed error — defer
- Discovered: b.py:9 — wrong format string — defer → I-003
NOTES
	dg_cli_in "$proj" "$home" digest --json
	assert_rc 0 "digest --json exits 0"
	n=$(printf '%s' "$OUT" | grep -c '"kind": "discovered"')
	assert_eq "1" "$n" "exactly one discovered entry in the digest JSON"
	assert_contains "$OUT" "a.py:4" "the entry is the unfiled defer"
	assert_not_contains "$OUT" "b.py" "the filed defer is not listed"
	rm -rf "$home" "$proj"
}

# Tagged assumptions: text hides [mechanical], shows taste, challenge (first)
# and untagged lines; --json keeps all four with their tag.
t_digest_tagged_assumptions_text_hides_only_mechanical() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	cat >"$proj/.specs/001-x/NOTES.md" <<'NOTES'
# Notes
- Assumption: [mechanical] used the existing lint config
- Assumption: [taste] chose the shorter flag name
- Assumption: [challenge] kept REST; GraphQL would change spec.md
- Assumption: staging db is disposable — evidence: transcript:12 (audit)
NOTES
	dg_cli_in "$proj" "$home" digest
	assert_rc 0 "digest exits 0"
	assert_not_contains "$OUT" "existing lint config" "mechanical is omitted from text"
	assert_contains "$OUT" "Assumption [taste]: chose the shorter flag name" "taste is shown"
	assert_contains "$OUT" "Assumption [challenge]: kept REST" "challenge is shown"
	assert_contains "$OUT" "Assumption: staging db is disposable" "untagged line is shown"
	case $OUT in
	*"[challenge]"*"[taste]"*) _pass "challenge is listed before taste" ;;
	*) _fail "challenge before taste" "$OUT" ;;
	esac
	rm -rf "$home" "$proj"
}

t_digest_tagged_assumptions_json_keeps_all_with_tags() {
	local home proj n
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	cat >"$proj/.specs/001-x/NOTES.md" <<'NOTES'
# Notes
- Assumption: [mechanical] used the existing lint config
- Assumption: [taste] chose the shorter flag name
- Assumption: [challenge] kept REST; GraphQL would change spec.md
- Assumption: staging db is disposable
NOTES
	dg_cli_in "$proj" "$home" digest --json
	assert_rc 0 "digest --json exits 0"
	n=$(printf '%s' "$OUT" | grep -c '"kind": "assumption"')
	assert_eq "4" "$n" "all four assumptions are in the JSON"
	assert_contains "$OUT" '"tag": "mechanical"' "mechanical tag"
	assert_contains "$OUT" '"tag": "taste"' "taste tag"
	assert_contains "$OUT" '"tag": "challenge"' "challenge tag"
	assert_contains "$OUT" '"tag": null' "untagged is null"
	rm -rf "$home" "$proj"
}

# famous-borrows F143: `flow digest` reports, per security rule, how many logged
# hits are fixed (the matched text is gone from the file) and how many are open.
dg_sec_log() {
	printf '%s\t%s\t%s\n' "$2" "$3" "$4" >>"$1/.git/flow-security-hits.tsv"
}

t_digest_security_hit_removed_is_fixed() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	printf 'const x = 1;\n' >"$proj/a.js"
	dg_sec_log "$proj" innerHTML "$proj/a.js" 'el.innerHTML = s;'
	dg_cli_in "$proj" "$home" digest
	assert_rc 0 "digest exits 0"
	assert_contains "$OUT" "security rules: innerHTML fixed=1 open=0" "removed line counts as fixed"
	rm -rf "$home" "$proj"
}

t_digest_security_hit_left_is_open() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	printf 'el.innerHTML = s;\n' >"$proj/a.js"
	dg_sec_log "$proj" innerHTML "$proj/a.js" 'el.innerHTML = s;'
	dg_cli_in "$proj" "$home" digest
	assert_contains "$OUT" "security rules: innerHTML fixed=0 open=1" "line left in place counts as open"
	rm -f "$proj/a.js"
	dg_cli_in "$proj" "$home" digest
	assert_contains "$OUT" "security rules: innerHTML fixed=1 open=0" "a deleted file counts as fixed"
	rm -rf "$home" "$proj"
}

t_digest_security_mixed_and_duplicate_hits() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	printf 'el.innerHTML = s;\n' >"$proj/a.js"
	dg_sec_log "$proj" innerHTML "$proj/a.js" 'el.innerHTML = s;'
	dg_sec_log "$proj" innerHTML "$proj/a.js" 'el.innerHTML = s;'
	dg_sec_log "$proj" innerHTML "$proj/a.js" 'b.innerHTML = t;'
	dg_cli_in "$proj" "$home" digest
	assert_contains "$OUT" "security rules: innerHTML fixed=1 open=1" "a repeated hit counts once"
	rm -rf "$home" "$proj"
}

t_digest_no_security_state_prints_no_security_line() {
	local home proj
	home=$(tmp_dir)
	proj=$(tmp_repo)
	dg_feature "$proj"
	dg_notes "$proj"
	dg_cli_in "$proj" "$home" digest
	assert_not_contains "$OUT" "security rules" "no state file, no security line"
	rm -rf "$home" "$proj"
}
