#!/usr/bin/env bash
# test_no_slop.sh — tests for the no-slop skill's scripts/slop-check
# against the planted-slop fixture in fixtures/no-slop/make-fixture.sh
# (B1 to B5). t_noslop_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

SKILL_DIR="$SCAN_DIR/../skills/no-slop"
SLOP_CHECK="$SKILL_DIR/scripts/slop-check"
MAKE_FIXTURE="$HERE/fixtures/no-slop/make-fixture.sh"

PLANTED_IDS='NS-03 NS-04 NS-05 NS-06 NS-08 NS-09 NS-10 NS-13 NS-15'

# run_slop <repo-dir> [slop-check args...] — runs slop-check with its cwd
# set to <repo-dir>, since it resolves the repo root via `git rev-parse`.
run_slop() {
	local repo=$1
	shift
	run_cmd bash -c 'cd "$1" || exit 1; shift; exec "$@"' _ "$repo" "$SLOP_CHECK" "$@"
}

# ---------------------------------------------------------------------------
# B1 — make-fixture.sh builds a "base"-tagged clean commit and a HEAD
# commit planted on top of it.
# ---------------------------------------------------------------------------

t_noslop_fixture_builds_base_tag() {
	d=$(tmp_dir)
	run_cmd bash "$MAKE_FIXTURE" "$d"
	assert_rc 0 "make-fixture.sh exits 0"
	run_cmd bash -c 'cd "$1" && git rev-parse --verify --quiet base' _ "$d"
	assert_rc 0 "make-fixture.sh tags the clean commit 'base'"
}

t_noslop_fixture_base_is_clean() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --head base --no-tools
	assert_eq "$OUT" "" "slop-check finds nothing between base and itself"
}

# ---------------------------------------------------------------------------
# B2 — slop-check --no-tools reports every planted NS id on the fixture's
# HEAD commit.
# ---------------------------------------------------------------------------

t_noslop_reports_planted_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools
	assert_rc 0 "slop-check exits 0 (advisory) despite findings"
	for id in $PLANTED_IDS; do
		assert_contains "$OUT" "$id" "slop-check reports $id on the fixture"
	done
}

# NS-06 covers the whole rubric row, not just function names: the fixture's
# generic class (`Manager`) and generic variables (`data`, `item`) must be
# reported too, in Python and in JS/TS.
t_noslop_reports_generic_variable_and_class_names() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools
	assert_contains "$OUT" "generic class name 'Manager'" \
		"NS-06 reports a generic Python class name"
	assert_contains "$OUT" "generic variable name 'data'" \
		"NS-06 reports a generic Python variable name"
	assert_contains "$OUT" "generic variable name 'item'" \
		"NS-06 reports a generic JS/TS variable name"
}

# NS-06 does not judge lifetime (rubric.md): a test's act-phase local
# (`result = fn()`) is not scanned, in Python or JS; the same name in a
# source file still is.
t_noslop_skips_act_phase_locals_in_test_files() {
	d=$(tmp_dir)
	mkdir -p "$d/tests" "$d/src"
	printf 'def test_add():\n    result = 1 + 2\n    assert result == 3\n' >"$d/tests/test_calc.py"
	printf 'test("x", () => {\n  const result = add(1, 2);\n  expect(result).toBe(3);\n});\n' >"$d/tests/calc.test.js"
	printf 'def add(a, b):\n    result = a + b\n    return result\n' >"$d/src/calc.py"
	run_slop "$d" --all-lines --no-tools --files tests/test_calc.py tests/calc.test.js src/calc.py
	assert_not_contains "$OUT" "tests/test_calc.py" \
		"NS-06 skips a plain assignment in a Python test file"
	assert_not_contains "$OUT" "tests/calc.test.js" \
		"NS-06 skips a const in a JS test file"
	assert_contains "$OUT" "src/calc.py:2: NS-06 generic variable name 'result'" \
		"NS-06 still reports the same name in a source file"
}

# NS-16 (name similarity) runs without external tools, as SKILL.md says:
# the fixture's duplicated src/text_helpers.py::slugify must be reported
# under --no-tools.
# NS-13 is a test-files-only detector (rubric.md: "slop-check (test files
# only)"). A non-test file with an assertion removed and none added back in
# the same hunk (src/guard.py in the fixture) must not trip it, even though
# the hunk-level shape matches the test-file case.
t_noslop_ns13_only_in_test_files() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools
	test_ns13=$(printf '%s\n' "$OUT" | grep "tests/test_text.py" | grep -c "NS-13")
	guard_ns13=$(printf '%s\n' "$OUT" | grep "src/guard.py" | grep -c "NS-13")
	if [ "$test_ns13" -gt 0 ]; then _pass "NS-13 still fires on the test file"; else
		_fail "NS-13 still fires on the test file" "no NS-13 line for tests/test_text.py in: $OUT"
	fi
	assert_eq "$guard_ns13" "0" "NS-13 does not fire on the non-test file src/guard.py"
}

t_noslop_reports_name_similarity_without_tools() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools
	assert_rc 0 "slop-check exits 0 with a name-similarity finding"
	assert_contains "$OUT" "NS-16" "slop-check reports NS-16 under --no-tools"
	assert_contains "$OUT" "src/text_helpers.py" "NS-16 names the duplicated helper's file"
}

# NS-16 must never compare dunder names or names under 4 characters: every
# class's __init__ is "100% similar" to every other class's __init__, which
# is noise, not a reinvention signal.
t_noslop_ns16_ignores_dunder_names() {
	local d
	d=$(tmp_dir)
	git -C "$d" init -q
	git -C "$d" config user.email "fixture@example.com"
	git -C "$d" config user.name "no-slop fixture"
	git -C "$d" config commit.gpgsign false
	mkdir -p "$d/src"
	cat >"$d/src/alpha.py" <<'EOF'
class Alpha:
    def __init__(self, value):
        self.value = value
EOF
	git -C "$d" add -A
	git -C "$d" commit -q -m "base: Alpha with __init__"
	git -C "$d" tag base
	cat >"$d/src/beta.py" <<'EOF'
class Beta:
    def __init__(self, value):
        self.value = value
EOF
	git -C "$d" add -A
	git -C "$d" commit -q -m "head: Beta with __init__"

	run_slop "$d" --base base --no-tools
	assert_rc 0 "slop-check exits 0 on the dunder fixture"
	dunder_hits=$(printf '%s\n' "$OUT" | grep -c "NS-16.*__init__" || true)
	assert_eq "$dunder_hits" "0" "NS-16 does not fire on identical __init__ across files"
}

# ---------------------------------------------------------------------------
# B3 — advisory by default; --strict turns findings into a non-zero exit.
# ---------------------------------------------------------------------------

t_noslop_strict_exits_nonzero_on_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools --strict
	assert_rc 1 "slop-check --strict exits 1 when findings exist"
}

t_noslop_strict_exits_zero_with_no_findings() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --head base --no-tools --strict
	assert_rc 0 "slop-check --strict exits 0 when there are no findings"
}

# ---------------------------------------------------------------------------
# --all-lines: a postcheck.sh's usage — a directory with no git at all,
# still reports findings by treating every line of the listed files as
# added; --base/--head are ignored and no repo lookup happens.
# ---------------------------------------------------------------------------

# plain_copy_of_planted_text_py <dest-dir> — extracts the fixture's planted
# src/text.py (NS-03/04/05/06 all present in that one file) into <dest-dir>,
# which is never `git init`-ed.
plain_copy_of_planted_text_py() {
	local fixture_repo=$1 plain=$2
	mkdir -p "$plain/src"
	git -C "$fixture_repo" show HEAD:src/text.py >"$plain/src/text.py"
}

t_noslop_all_lines_reports_findings_with_no_git() {
	local d plain
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	plain=$(tmp_dir)
	plain_copy_of_planted_text_py "$d" "$plain"
	run_cmd bash -c 'cd "$1" && exec "$2" --all-lines --files src/text.py --no-tools' \
		_ "$plain" "$SLOP_CHECK"
	assert_rc 0 "slop-check --all-lines exits 0 (advisory) with no git repo present"
	for id in NS-03 NS-04 NS-05 NS-06; do
		assert_contains "$OUT" "$id" "slop-check --all-lines reports $id with no git"
	done
}

t_noslop_all_lines_strict_exits_nonzero() {
	local d plain
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	plain=$(tmp_dir)
	plain_copy_of_planted_text_py "$d" "$plain"
	run_cmd bash -c 'cd "$1" && exec "$2" --all-lines --files src/text.py --no-tools --strict' \
		_ "$plain" "$SLOP_CHECK"
	assert_rc 1 "slop-check --all-lines --strict exits 1 on a plain dir with findings"
}

# ---------------------------------------------------------------------------
# B4 — --json emits a findings array plus a summary.
# ---------------------------------------------------------------------------

t_noslop_json_output_shape() {
	d=$(tmp_dir)
	bash "$MAKE_FIXTURE" "$d" >/dev/null 2>&1
	run_slop "$d" --base base --no-tools --json
	assert_rc 0 "slop-check --json exits 0"
	assert_contains "$OUT" '"findings"' "slop-check --json emits a findings array"
	assert_contains "$OUT" '"summary"' "slop-check --json emits a summary"
	assert_contains "$OUT" '"NS-03"' "slop-check --json findings carry NS ids"
}

# ---------------------------------------------------------------------------
# B5 — the skill package itself is present and well-formed.
# ---------------------------------------------------------------------------

t_noslop_skill_files_present() {
	assert_file_exists "$SKILL_DIR/SKILL.md" "SKILL.md exists"
	assert_file_exists "$SKILL_DIR/references/rubric.md" "references/rubric.md exists"
	assert_file_exists "$SKILL_DIR/references/developer-block.md" "references/developer-block.md exists"
	assert_file_exists "$SKILL_DIR/references/adversary-lens.md" "references/adversary-lens.md exists"
	assert_file_exists "$SKILL_DIR/references/evidence.md" "references/evidence.md exists"
	assert_file_exists "$SKILL_DIR/references/integration-seams.md" "references/integration-seams.md exists"
	assert_file_exists "$SKILL_DIR/scripts/slop_tools.py" "scripts/slop_tools.py exists"
}

t_noslop_skill_md_frontmatter() {
	run_cmd head -5 "$SKILL_DIR/SKILL.md"
	assert_contains "$OUT" "name: no-slop" "SKILL.md declares name: no-slop"
}

t_noslop_slop_check_is_executable() {
	if [ -x "$SLOP_CHECK" ]; then
		_pass "scripts/slop-check is executable"
	else
		_fail "scripts/slop-check is executable" "not executable: $SLOP_CHECK"
	fi
}

# ---------------------------------------------------------------------------
# NS-17 — complexity growth only fires for a function that already existed
# at base, grew, and ended above the limit; new functions and untouched or
# simplified functions stay silent (ImpactGate: growing already-complex code
# costs more than adding new code).
# ---------------------------------------------------------------------------

# gen_fn <name> <n-if-branches> — an n-branch if-ladder function; CC = n + 1.
gen_fn() {
	python3 -c '
import sys
name, n = sys.argv[1], int(sys.argv[2])
lines = [f"def {name}(x):"]
for i in range(n):
    lines.append(f"    if x == {i}:")
    lines.append(f"        return {i}")
lines.append("    return -1")
print("\n".join(lines))
' "$1" "$2"
}

t_noslop_ns17_flags_growth_in_existing_function_only() {
	command -v uvx >/dev/null || return 0
	local d
	d=$(tmp_dir)
	git -C "$d" init -q
	git -C "$d" config user.email "fixture@example.com"
	git -C "$d" config user.name "no-slop fixture"
	git -C "$d" config commit.gpgsign false
	mkdir -p "$d/src"
	{
		gen_fn grows 8      # CC 9 at base
		echo
		gen_fn stays_big 14 # CC 15, never touched
		echo
		gen_fn shrinks 11   # CC 12 at base
	} >"$d/src/calc.py"
	git -C "$d" add -A
	git -C "$d" commit -q -m "base: calc.py"
	git -C "$d" tag base
	{
		gen_fn grows 11     # CC 12: grows past the limit
		echo
		gen_fn stays_big 14 # unchanged
		echo
		gen_fn shrinks 10   # CC 11: shrank, still above the limit but must not fire
		echo
		gen_fn fresh 3      # new function, CC 4
		echo
		gen_fn fresh_big 11 # new function, CC 12: new, must not fire
	} >"$d/src/calc.py"
	git -C "$d" add -A
	git -C "$d" commit -q -m "head: calc.py"

	run_cmd bash -c 'cd "$1" && python3 -c "import sys; sys.path.insert(0, sys.argv[1]); import slop_diff, slop_tools; a,_,_ = slop_diff.parse_diff(\".\", \"base\", \"HEAD\", [\"*.py\"]); print(slop_tools.run_lizard(\".\", \"base\", list(a), a))" "$2"' _ "$d" "$SKILL_DIR/scripts"
	assert_contains "$OUT" "NS-17" "run_lizard flags NS-17"
	assert_contains "$OUT" "grows" "NS-17 names the grown function"
	assert_contains "$OUT" "9->12" "NS-17 reports the CC before->after"
	assert_not_contains "$OUT" "stays_big" "NS-17 stays silent on an untouched function"
	assert_not_contains "$OUT" "shrinks" "NS-17 stays silent on a function that got simpler"
	assert_not_contains "$OUT" "fresh" "NS-17 stays silent on new functions"
}

# ---------------------------------------------------------------------------
# --prose — NP-04 to NP-08 on markdown; code fences and inline code skipped.
# ---------------------------------------------------------------------------

write_prose_tells() {
	cat >"$1" <<'MD'
# Title

It is important to note that the change is small.
We leverage a pivotal helper here.
The cache might possibly be stale.
This is not just a rename, but a rewrite.
The loader reads the config file and then validates every key against the schema and then writes the merged result to the output directory before it reports success to the caller.
MD
}

t_noslop_prose_reports_known_tells() {
	local f
	f=$(tmp_dir)/pr.md
	write_prose_tells "$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_rc 0 "slop-check --prose exits 0 (advisory) despite findings"
	assert_contains "$OUT" "pr.md:3: NP-07" "NP-07 opener on line 3"
	assert_contains "$OUT" "pr.md:4: NP-04" "NP-04 AI-tell word on line 4"
	assert_contains "$OUT" "pr.md:5: NP-05" "NP-05 stacked hedges on line 5"
	assert_contains "$OUT" "pr.md:6: NP-06" "NP-06 not-just-but on line 6"
	assert_contains "$OUT" "pr.md:7: NP-08" "NP-08 long sentence on line 7"
}

t_noslop_prose_clean_fixture_has_no_findings() {
	local f
	f=$(tmp_dir)/clean.md
	printf '# Summary\n\nThe parser rejects a bad date and exits with code 2.\nMeasured: `make test` passes, 12 of 12.\n\n- Use the existing helper.\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_rc 0 "clean prose exits 0"
	assert_eq "$OUT" "" "clean prose prints no findings"
	run_cmd "$SLOP_CHECK" --prose "$f" --strict
	assert_rc 0 "clean prose exits 0 under --strict"
}

t_noslop_prose_ignores_code() {
	local f
	f=$(tmp_dir)/code.md
	printf 'Run `leverage pivotal` now.\n\n```\nIt is important to note that this might possibly leverage x.\n```\n\n~~~\nIn conclusion, crucial.\n~~~\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_eq "$OUT" "" "fenced and inline code are not scanned"
}

t_noslop_prose_strict_and_json() {
	local f
	f=$(tmp_dir)/pr.md
	write_prose_tells "$f"
	run_cmd "$SLOP_CHECK" --prose "$f" --strict
	assert_rc 1 "slop-check --prose --strict exits 1 on findings"
	run_cmd "$SLOP_CHECK" --prose "$f" --json
	assert_rc 0 "slop-check --prose --json exits 0"
	assert_contains "$OUT" '"findings"' "--prose --json emits findings"
	assert_contains "$OUT" '"NP-05"' "--prose --json carries NP ids"
}

t_noslop_prose_list_items_are_separate_sentences() {
	local f
	f=$(tmp_dir)/bullets.md
	printf -- '- one short bullet here\n- another short bullet here\n- a third short bullet here\n- a fourth short bullet here\n- a fifth short bullet here\n- a sixth short bullet here\n- In conclusion the tests pass\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_not_contains "$OUT" "NP-08" "bullets without periods are not one long sentence"
	assert_contains "$OUT" "bullets.md:7: NP-07" "closer at the start of a bullet is flagged"
}

t_noslop_prose_heading_is_its_own_boundary() {
	local f
	f=$(tmp_dir)/head.md
	printf '## Summary\nIt is important to note that the fix is small.\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_contains "$OUT" "head.md:2: NP-07" "opener right after a heading is flagged"
}

t_noslop_prose_fence_char_and_length() {
	local f
	f=$(tmp_dir)/nested.md
	printf '````\n```\nIt is important to note this.\n```\n````\n\n```\n~~~\nIn conclusion, crucial.\n~~~\n```\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_eq "$OUT" "" "nested and mixed fences stay fenced"
}

t_noslop_prose_bad_input_files() {
	local d
	d=$(tmp_dir)
	run_cmd "$SLOP_CHECK" --prose "$d/nope.md" --strict
	assert_rc 1 "missing --prose path fails under --strict"
	printf 'caf\xe9 is fine.\n' >"$d/latin1.md"
	run_cmd "$SLOP_CHECK" --prose "$d/latin1.md"
	assert_not_contains "$OUT" "Traceback" "non-UTF-8 file does not crash"
	assert_rc 0 "non-UTF-8 file exits 0 without --strict"
}

t_noslop_prose_rubric_present() {
	assert_file_exists "$SKILL_DIR/references/prose-rubric.md" "references/prose-rubric.md exists"
	assert_file_exists "$SKILL_DIR/scripts/slop_prose.py" "scripts/slop_prose.py exists"
}

# ---------------------------------------------------------------------------
# NP-09 (unvetted perf number), NP-12 (jargon metaphor), NS-30 (TS partiality)
# and the lens rows NP-10, NP-11, NS-31 to NS-33. Prose cases write one
# markdown file; TS cases run --all-lines on a plain directory.
# ---------------------------------------------------------------------------

prose_out_for() {
	local f
	f=$(tmp_dir)/p.md
	printf '%s\n' "$1" >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
}

t_noslop_np09_flags_unvetted_perf_claim() {
	prose_out_for 'The export is now 40% faster than before.'
	assert_contains "$OUT" "NP-09" "perf number plus comparison flags NP-09"
	assert_contains "$OUT" "run benchmark-checklist" "NP-09 names benchmark-checklist"
	prose_out_for 'Latency went from 120 ms to 80 ms after the change.'
	assert_contains "$OUT" "NP-09" "'from X to Y' with ms flags NP-09"
}

t_noslop_np09_passes_vetted_or_non_perf() {
	prose_out_for 'The p50 went from 41 ms to 33 ms, median of 7 runs per side.'
	assert_not_contains "$OUT" "NP-09" "run count clears NP-09"
	prose_out_for 'Export is 40% faster, measured with `./bench.sh --runs 7`.'
	assert_not_contains "$OUT" "NP-09" "inline command clears NP-09"
	prose_out_for 'The retry delay is set to 500 ms.'
	assert_not_contains "$OUT" "NP-09" "number without a comparison passes (config value)"
	prose_out_for 'This is much faster and cleaner.'
	assert_not_contains "$OUT" "NP-09" "comparison without a number passes"
}

t_noslop_np09_rejects_fake_proof() {
	prose_out_for 'The export now runs 40% faster.'
	assert_contains "$OUT" "NP-09" "verb 'runs' is not a run count"
	prose_out_for 'Builds run 3x faster after caching.'
	assert_contains "$OUT" "NP-09" "verb 'run' is not a run count"
	prose_out_for '`parseRows` is now 3x faster.'
	assert_contains "$OUT" "NP-09" "backticked identifier is not a command"
	prose_out_for 'p95 dropped from 200 ms to 90 ms, see [the dashboard](https://x.y/z).'
	assert_contains "$OUT" "NP-09" "a link is not proof"
	prose_out_for 'Export is 40% faster over 7 runs.'
	assert_not_contains "$OUT" "NP-09" "'7 runs' is a run count"
}

t_noslop_np09_ignores_fenced_code() {
	local f
	f=$(tmp_dir)/f.md
	printf '```\nexport is now 40%% faster\n```\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_not_contains "$OUT" "NP-09" "fenced code is never flagged by NP-09"
}

t_noslop_np12_flags_jargon_metaphor() {
	prose_out_for 'The flywheel keeps spinning after each release.'
	assert_contains "$OUT" "NP-12" "'flywheel' flags NP-12"
	assert_contains "$OUT" "flywheel" "NP-12 names the word"
	prose_out_for 'Our north star is fewer round trips.'
	assert_contains "$OUT" "NP-12" "'north star' flags NP-12"
}

t_noslop_np12_misses_code_and_ratchet() {
	local f
	f=$(tmp_dir)/f.md
	printf '```\nthe flywheel substrate\n```\n\nRun `flywheel` now.\n' >"$f"
	run_cmd "$SLOP_CHECK" --prose "$f"
	assert_not_contains "$OUT" "NP-12" "jargon inside code is not flagged"
	prose_out_for 'The ratchet is one-way, so a passing gate stays passing.'
	assert_eq "$OUT" "" "'ratchet' is flow's own term and is not flagged"
}

t_noslop_prose_rubric_new_rows() {
	local r
	r=$(cat "$SKILL_DIR/references/prose-rubric.md")
	for id in NP-09 NP-10 NP-11 NP-12; do
		assert_contains "$r" "| $id |" "prose-rubric has a $id row"
	done
	assert_contains "$r" "makes a sentence worse" "prose-rubric header: fix it another way"
}

ts_scan() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf '%s\n' "$1" >"$d/src/a.ts"
	run_cmd bash -c 'cd "$1" && exec "$2" --all-lines --files src/a.ts --no-tools' _ "$d" "$SLOP_CHECK"
}

t_noslop_ns30_flags_ts_partiality() {
	ts_scan 'const u = arr[0] as User;'
	assert_contains "$OUT" "NS-30" "index then 'as User' flags NS-30"
	ts_scan 'const id = x!.id;'
	assert_contains "$OUT" "NS-30" "non-null assertion before '.' flags NS-30"
	ts_scan "throw new Error('should never happen');"
	assert_contains "$OUT" "NS-30" "'should never happen' in a throw flags NS-30"
	ts_scan '// should never happen'
	assert_contains "$OUT" "NS-30" "'should never happen' in a comment flags NS-30"
}

t_noslop_ns30_leaves_legitimate_ts_alone() {
	ts_scan 'const k = ["a"] as const;'
	assert_not_contains "$OUT" "NS-30" "'as const' is not flagged"
	ts_scan 'if (a !== b) { run(); }'
	assert_not_contains "$OUT" "NS-30" "'!==' is not flagged"
	ts_scan 'inputRef.current!.focus();'
	assert_not_contains "$OUT" "NS-30" "React ref access is exempt"
	ts_scan 'const s = "hello!.";'
	assert_not_contains "$OUT" "NS-30" "'!.' inside a string is not flagged"
}

t_noslop_rubric_new_rows() {
	local r l id
	r=$(cat "$SKILL_DIR/references/rubric.md")
	l=$(cat "$SKILL_DIR/references/adversary-lens.md")
	for id in NS-30 NS-31 NS-32 NS-33; do
		assert_contains "$r" "| $id |" "rubric has a $id row"
		assert_contains "$l" "$id" "adversary-lens names $id"
	done
}

# M24: NS-26 gains the returns-nothing and fixture-asserts-fixture clauses.
t_noslop_ns26_has_strength_probes() {
	local row row33
	row=$(grep '^| NS-26 |' "$SKILL_DIR/references/rubric.md")
	row33=$(grep '^| NS-33 |' "$SKILL_DIR/references/rubric.md")
	assert_contains "$row" "returned undefined or None" "NS-26 has the returns-nothing probe"
	assert_contains "$row" "subject never runs" "NS-26 has the fixture-asserts-fixture clause"
	assert_contains "$row33" "shipped artifact" "NS-33 exempts skill and prompt text"
	assert_contains "$row33" "advise" "NS-33 is advise"
	assert_contains "$(cat "$SKILL_DIR/references/adversary-lens.md")" "returns-nothing probe" "lens carries the returns-nothing probe"
}

# M25: NS-23 and NS-31 must not contradict.
t_noslop_ns23_defers_to_ns31() {
	local row
	row=$(grep '^| NS-23 |' "$SKILL_DIR/references/rubric.md")
	assert_contains "$row" "no such check is practical" "NS-23 keeps a constraint comment only when no check is practical"
	row=$(grep '^| NS-31 |' "$SKILL_DIR/references/rubric.md")
	assert_contains "$row" "delete the comment" "NS-31 says to delete the comment once the check exists"
	assert_contains "$row" "advise" "NS-31 is advise"
	assert_contains "$row" "external" "NS-31 leaves external-behaviour constraints alone"
}

# M26: the domain-shape row names the finding and the fix.
t_noslop_ns32_domain_shape_row() {
	local row
	row=$(grep '^| NS-32 |' "$SKILL_DIR/references/rubric.md")
	assert_contains "$row" "discriminated union" "NS-32 suggests a discriminated union"
	assert_contains "$row" "must agree" "NS-32 names the must-agree field"
	assert_contains "$row" "advise" "NS-32 is advise"
}

# M03/M16: the PR body shape carries the new lines.
t_noslop_pr_body_new_lines() {
	local b
	b=$(cat "$SCAN_DIR/../skills/shared/pr-body.md")
	assert_contains "$b" "## Left out" "pr-body has a Left out section"
	assert_contains "$b" "flow digest --json" "pr-body names flow digest --json"
	assert_contains "$b" "link long logs" "pr-body says to link long logs"
	assert_contains "$b" "NP-09" "pr-body ties NP-09 to benchmark-checklist"
	assert_contains "$b" "benchmark-checklist" "pr-body names benchmark-checklist"
}
