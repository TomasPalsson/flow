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
