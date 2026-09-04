#!/usr/bin/env bash
# test_lint.sh — tests for plan-lint and skills-lint (C8), t_lint_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.

FIX="$HERE/fixtures"
PLAN_LINT="$SCAN_DIR/plan-lint"
SKILLS_LINT="$SCAN_DIR/skills-lint"

# ---------------------------------------------------------------------------
# plan-lint
# ---------------------------------------------------------------------------

t_lint_plan_lint_help() {
	run_cmd "$PLAN_LINT" --help
	assert_rc 0 "plan-lint --help exits 0"
	assert_contains "$OUT" "Usage: plan-lint" "plan-lint --help shows usage"
}

t_lint_plan_lint_no_args() {
	run_cmd "$PLAN_LINT"
	assert_rc 1 "plan-lint with no args exits 1"
}

t_lint_plan_lint_missing_file() {
	run_cmd "$PLAN_LINT" "$FIX/does-not-exist.md"
	assert_rc 1 "plan-lint on a missing file exits 1"
	assert_contains "$OUT" "MISSING" "plan-lint on a missing file prints MISSING"
}

t_lint_plan_lint_good_ok() {
	run_cmd "$PLAN_LINT" "$FIX/plan-good.md"
	assert_rc 0 "plan-lint on plan-good.md exits 0"
	assert_eq "$OUT" "OK" "plan-lint on plan-good.md prints OK"
}

t_lint_plan_lint_good_fence_decoy_ignored() {
	# C7: a fenced "## Slice 9 — decoy" line inside plan-good.md's Slice 2
	# body must not be treated as a real heading. If it were, plan-lint
	# would demand RED/GREEN/REFACTOR for a "slice 9" that only the real
	# grammar (Slice 1, Slice 2) satisfies — plan-good.md stays OK either
	# way, but must never mention Slice 9 in its output.
	run_cmd "$PLAN_LINT" "$FIX/plan-good.md"
	assert_not_contains "$OUT" "Slice 9" "plan-lint never surfaces the fenced decoy slice"
}

t_lint_plan_lint_fence_decoy_breaks_naive_scan() {
	# A dedicated fixture where an un-fence-aware scanner would treat the
	# fenced "## Slice 9 — decoy" heading as real and then complain about
	# its (deliberately incomplete) sub-headings; a fence-aware scanner
	# must ignore it and report OK.
	d=$(tmp_dir)
	cat >"$d/plan.md" <<'PLANEOF'
## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | `test_thing` |

## Slice 1 — Thing

- **Files**: src/thing.ts

### Slice 1 — RED

Write the failing test.

Decoy block a naive line-scanner would misparse as a new slice:

```text
## Slice 9 — decoy
### Slice 9 — RED
```

### Slice 1 — GREEN

Make it pass.

### Slice 1 — REFACTOR

Clean it up.

## Gate Phases

1. Run check-all.
PLANEOF
	run_cmd "$PLAN_LINT" "$d/plan.md"
	assert_rc 0 "plan-lint ignores a fenced decoy slice heading"
	assert_eq "$OUT" "OK" "plan-lint prints OK despite the fenced decoy"
}

t_lint_plan_lint_bad_reports_problems() {
	run_cmd "$PLAN_LINT" "$FIX/plan-bad.md"
	assert_rc 1 "plan-lint on plan-bad.md exits 1"
}

t_lint_plan_lint_bad_missing_refactor() {
	run_cmd "$PLAN_LINT" "$FIX/plan-bad.md"
	assert_contains "$OUT" "REFACTOR" "plan-lint flags the missing REFACTOR sub-heading"
}

t_lint_plan_lint_bad_depends_on_higher_slice() {
	run_cmd "$PLAN_LINT" "$FIX/plan-bad.md"
	assert_contains "$OUT" "INVALID: Slice 1 Depends-on refers to Slice 2" "plan-lint flags a Depends-on pointing at a higher-numbered slice"
}

t_lint_plan_lint_bad_no_inventory_row() {
	run_cmd "$PLAN_LINT" "$FIX/plan-bad.md"
	assert_contains "$OUT" "Behavior Inventory table row" "plan-lint flags the missing Behavior Inventory data row"
}

t_lint_plan_lint_heading_order_invalid() {
	d=$(tmp_dir)
	cat >"$d/plan.md" <<'PLANEOF'
## Gate Phases

1. Run check-all.

## Behavior Inventory

| Behavior | Slice | Verified by |
|---|---|---|
| Thing happens | Slice 1 | `test_thing` |

## Slice 1 — Thing

### Slice 1 — RED

x

### Slice 1 — GREEN

x

### Slice 1 — REFACTOR

x
PLANEOF
	run_cmd "$PLAN_LINT" "$d/plan.md"
	assert_rc 1 "plan-lint rejects Gate Phases appearing before Behavior Inventory"
	assert_contains "$OUT" "INVALID: top-level headings must appear in order" "plan-lint names the heading-order problem"
}

# ---------------------------------------------------------------------------
# skills-lint
# ---------------------------------------------------------------------------

t_lint_skills_lint_help() {
	run_cmd "$SKILLS_LINT" --help
	assert_rc 0 "skills-lint --help exits 0"
	assert_contains "$OUT" "Usage: skills-lint" "skills-lint --help shows usage"
}

t_lint_skills_lint_good_skill_clean() {
	# Isolate good-skill so no other fixture skill can affect the result.
	# HOME is pointed at the fixtures dir (never the real ~/.claude/skills)
	# so the "~/.claude/skills/..." and ".claude/skills/..." references in
	# good-skill's SKILL.md resolve against fixtures/.claude/skills/.
	d=$(tmp_dir)
	mkdir -p "$d/skills"
	cp -r "$FIX/skills/good-skill" "$d/skills/"
	run_cmd env HOME="$FIX" "$SKILLS_LINT" "$d/skills"
	assert_rc 0 "skills-lint on the isolated good-skill fixture exits 0"
	assert_eq "$OUT" "" "skills-lint on the isolated good-skill fixture prints nothing"
}

t_lint_skills_lint_good_skill_placeholders_ignored() {
	d=$(tmp_dir)
	mkdir -p "$d/skills"
	cp -r "$FIX/skills/good-skill" "$d/skills/"
	run_cmd env HOME="$FIX" "$SKILLS_LINT" "$d/skills"
	assert_not_contains "$OUT" "NNN" "skills-lint ignores an NNN placeholder reference"
	assert_not_contains "$OUT" "<name>" "skills-lint ignores a <name> placeholder reference"
}

t_lint_skills_lint_broken_skill_missing() {
	run_cmd env HOME="$FIX" "$SKILLS_LINT" "$FIX/skills"
	assert_rc 1 "skills-lint on the fixtures skills dir exits 1 (broken-skill has a dead reference)"
	assert_contains "$OUT" "MISSING" "skills-lint reports the dead reference"
	assert_contains "$OUT" "references/does-not-exist.md" "skills-lint names the dead reference path"
}

t_lint_skills_lint_broken_skill_tool_report() {
	run_cmd env HOME="$FIX" "$SKILLS_LINT" "$FIX/skills"
	assert_contains "$OUT" "TOOL" "skills-lint reports the command -v better-plan mention"
	assert_contains "$OUT" "better-plan" "skills-lint names the tool in the TOOL line"
}

t_lint_skills_lint_tool_does_not_fail_exit() {
	# A skill with a TOOL mention but no dead reference must still exit 0:
	# TOOL lines are informational and never affect the exit code.
	d=$(tmp_dir)
	mkdir -p "$d/skills/tool-only"
	cat >"$d/skills/tool-only/SKILL.md" <<'SKILLEOF'
---
name: tool-only
description: fixture skill mentioning a tool but no dead reference.
---

# tool-only

Uses `rtk` when available.
SKILLEOF
	run_cmd "$SKILLS_LINT" "$d/skills"
	assert_rc 0 "skills-lint exits 0 when only a TOOL line is reported"
	assert_contains "$OUT" "TOOL" "skills-lint still prints the TOOL line"
	assert_contains "$OUT" "rtk" "skills-lint names rtk in the TOOL line"
}

t_lint_skills_lint_no_skills_dir_ok() {
	d=$(tmp_dir)
	run_cmd "$SKILLS_LINT" "$d/no-such-skills-dir"
	assert_rc 0 "skills-lint on a non-existent skills dir exits 0"
	assert_eq "$OUT" "" "skills-lint on a non-existent skills dir prints nothing"
}

t_lint_skills_lint_real_skills_dir() {
	# Sanity check against the real deployment, per the unit's task notes:
	# only assert the process behaves (exit 0 or 1) and every printed line
	# is well-formed. This intentionally does not assert on the specific
	# findings, which depend on the live content of ~/.claude/skills.
	real_dir="$HOME/.claude/skills"
	if [ ! -d "$real_dir" ]; then
		printf '  skip real ~/.claude/skills not present\n'
		return 0
	fi
	run_cmd "$SKILLS_LINT" "$real_dir"
	case "$RC" in
	0 | 1) rc_status="ok" ;;
	*) rc_status="bad" ;;
	esac
	assert_eq "$rc_status" "ok" "skills-lint against the real skills dir exits 0 or 1"

	bad_lines=$(printf '%s\n' "$OUT" | grep -vE '^(MISSING|TOOL) ' | grep -vc '^$')
	assert_eq "$bad_lines" "0" "every line skills-lint prints against the real skills dir is MISSING/TOOL-prefixed"
}

t_lint_skills_lint_dotclaude_ref_resolves_against_skills_dir() {
	# C8's second ".claude/skills/..." resolution candidate must resolve
	# against the skills dir actually being scanned (skills_dir/<rest>),
	# not a doubled "<dirname(skills_dir)>/.claude/skills/<rest>" path
	# that can never exist. Point HOME at a directory that does not exist
	# so the first ($HOME) candidate cannot mask a broken second candidate.
	d=$(tmp_dir)
	mkdir -p "$d/skills/dotref-skill/references"
	cat >"$d/skills/dotref-skill/SKILL.md" <<'SKILLEOF'
---
name: dotref-skill
description: fixture verifying the .claude/skills/... second resolution candidate.
---

# dotref-skill

Dotted skills-dir form: `.claude/skills/dotref-skill/references/note.md`
SKILLEOF
	echo "note" >"$d/skills/dotref-skill/references/note.md"
	run_cmd env HOME=/nonexistent-home-for-skills-lint-test "$SKILLS_LINT" "$d/skills"
	assert_rc 0 "skills-lint resolves .claude/skills/... via the scanned skills dir when HOME has no mirror"
	assert_not_contains "$OUT" "MISSING" "skills-lint does not report the .claude/skills/... reference as missing"
}

t_lint_skills_lint_command_v_non_allowlisted_no_tool_line() {
	# C8: TOOL lines are only for the allowlisted tools (better-plan, rtk,
	# gh, bun, uv). A "command -v <other>" mention must never produce a
	# TOOL line, even when <other> is absent on this machine.
	d=$(tmp_dir)
	mkdir -p "$d/skills/nonallowlist"
	cat >"$d/skills/nonallowlist/SKILL.md" <<'SKILLEOF'
---
name: nonallowlist
description: fixture verifying non-allowlisted command -v mentions are not reported.
---

# nonallowlist

Check availability: `command -v zzznonexistentcmd12345`
SKILLEOF
	run_cmd "$SKILLS_LINT" "$d/skills"
	assert_rc 0 "skills-lint exits 0 for a non-allowlisted command -v mention"
	assert_not_contains "$OUT" "TOOL" "skills-lint does not report a TOOL line for a non-allowlisted command"
	assert_not_contains "$OUT" "zzznonexistentcmd12345" "skills-lint does not name a non-allowlisted command"
}

t_lint_skills_lint_prose_reference_trailing_punctuation_resolves() {
	# A path reference mentioned in prose without backticks (e.g. "See
	# references/a.md.", "references/b.md, in detail", "references/c.md?"
	# or "references/d.md!") must resolve: trailing sentence punctuation
	# ('.', ',', ';', ':', '?', '!') is not part of the path.
	d=$(tmp_dir)
	mkdir -p "$d/skills"
	cp -r "$FIX/skills/prose-skill" "$d/skills/"
	run_cmd "$SKILLS_LINT" "$d/skills"
	assert_rc 0 "skills-lint resolves prose references despite trailing punctuation"
	assert_not_contains "$OUT" "MISSING" "skills-lint reports no MISSING for prose references with trailing punctuation"
}

# ---------------------------------------------------------------------------
# skills-lint --usage (C14/C15 W4)
# ---------------------------------------------------------------------------

# _lint_usage_home <dir> — populates <dir>/.claude/{skills,commands} with the
# names the shared fixtures/history.jsonl fixture references: skills alpha,
# beta, gamma (gamma is installed but never mentioned) and commands shipit,
# deploy.
_lint_usage_home() {
	home_dir=$1
	mkdir -p "$home_dir/.claude/skills/alpha" "$home_dir/.claude/skills/beta" "$home_dir/.claude/skills/gamma"
	mkdir -p "$home_dir/.claude/commands"
	: >"$home_dir/.claude/commands/shipit.md"
	: >"$home_dir/.claude/commands/deploy.md"
}

t_lint_usage_help_mentions_usage() {
	run_cmd "$SKILLS_LINT" --help
	assert_contains "$OUT" "--usage" "skills-lint --help documents --usage"
}

t_lint_usage_header_line_total_and_date_range() {
	d=$(tmp_dir)
	_lint_usage_home "$d"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$FIX/history.jsonl"
	assert_rc 0 "skills-lint --usage exits 0"
	assert_contains "$OUT" "12 prompts, 2026-06-01..2026-07-01" "skills-lint --usage prints total prompts and date range"
}

t_lint_usage_whole_token_counts_exclude_substring_match() {
	# fixtures/history.jsonl mentions "/alpha" 3 times and "/alphabet" once;
	# the latter must not count toward alpha (whole-token match only).
	d=$(tmp_dir)
	_lint_usage_home "$d"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$FIX/history.jsonl"
	assert_contains "$OUT" "3 alpha skill 2026-06-15" "skills-lint --usage counts alpha 3 times, ignoring the /alphabet substring, with the correct last-used date"
}

t_lint_usage_command_counts_and_kind_column() {
	d=$(tmp_dir)
	_lint_usage_home "$d"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$FIX/history.jsonl"
	assert_contains "$OUT" "2 shipit command 2026-07-01" "skills-lint --usage counts the shipit command and tags it kind=command"
	assert_contains "$OUT" "1 deploy command 2026-06-15" "skills-lint --usage counts the deploy command"
}

t_lint_usage_never_used_skill_sorts_first() {
	# gamma is installed but never mentioned in fixtures/history.jsonl: it
	# must report 0 uses / "never" and sort ascending (before every used name).
	d=$(tmp_dir)
	_lint_usage_home "$d"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$FIX/history.jsonl"
	assert_contains "$OUT" "0 gamma skill never" "skills-lint --usage reports gamma as never-used"

	gamma_line=$(printf '%s\n' "$OUT" | grep -n -F "0 gamma skill never" | head -1 | cut -d: -f1)
	alpha_line=$(printf '%s\n' "$OUT" | grep -n -F "3 alpha skill" | head -1 | cut -d: -f1)
	order_ok=no
	if [ -n "$gamma_line" ] && [ -n "$alpha_line" ] && [ "$gamma_line" -lt "$alpha_line" ]; then order_ok=yes; fi
	assert_eq "$order_ok" "yes" "skills-lint --usage sorts ascending by uses (never-used gamma before the more-used alpha)"
}

t_lint_usage_missing_history_file_prints_notice() {
	d=$(tmp_dir)
	_lint_usage_home "$d"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$d/does-not-exist.jsonl"
	assert_rc 0 "skills-lint --usage exits 0 when the history file is missing"
	assert_contains "$OUT" "no history file at" "skills-lint --usage notes the missing history file"
}

t_lint_usage_default_history_path_is_home_history_jsonl() {
	# No <history.jsonl> argument: must default to $HOME/.claude/history.jsonl.
	d=$(tmp_dir)
	_lint_usage_home "$d"
	mkdir -p "$d/.claude"
	cp "$FIX/history.jsonl" "$d/.claude/history.jsonl"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage
	assert_rc 0 "skills-lint --usage with no argument exits 0"
	assert_contains "$OUT" "12 prompts, 2026-06-01..2026-07-01" "skills-lint --usage with no argument reads HOME/.claude/history.jsonl"
}

t_lint_usage_no_python3_prints_notice_and_exits_0() {
	d=$(tmp_dir)
	narrowbin="$d/bin"
	mkdir -p "$narrowbin"
	for tool in bash mkdir mktemp rm cat grep cut find sort tr env; do
		if cmdpath=$(command -v "$tool" 2>/dev/null); then
			ln -s "$cmdpath" "$narrowbin/$tool"
		fi
	done
	homedir="$d/home"
	_lint_usage_home "$homedir"
	run_cmd env PATH="$narrowbin" HOME="$homedir" "$SKILLS_LINT" --usage "$FIX/history.jsonl"
	assert_rc 0 "skills-lint --usage exits 0 when python3 is absent"
	assert_contains "$OUT" "python3" "skills-lint --usage notes python3 is missing"
}

t_lint_usage_millisecond_timestamp_computes_date_and_last_used() {
	# Real $HOME/.claude/history.jsonl records carry a "timestamp" field in
	# Unix MILLISECONDS (13 digits), never a "date" string key. Feeding that
	# straight into datetime.fromtimestamp() (which assumes seconds) used to
	# raise ValueError/OverflowError (year ~58006), silently caught, leaving
	# the header "n/a" and every last-used column "never" even for a name
	# with a nonzero use count on the same line. 1781524800000 ms is exactly
	# 2026-06-15T12:00:00Z.
	d=$(tmp_dir)
	_lint_usage_home "$d"
	hist="$d/ms-history.jsonl"
	printf '{"display":"/alpha go","timestamp":1781524800000}\n' >"$hist"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$hist"
	assert_rc 0 "skills-lint --usage exits 0 with millisecond timestamps"
	assert_contains "$OUT" "1 prompts, 2026-06-15..2026-06-15" "skills-lint --usage computes the header date range from millisecond timestamps"
	assert_contains "$OUT" "1 alpha skill 2026-06-15" "skills-lint --usage computes last-used from millisecond timestamps instead of reporting never"
}

t_lint_usage_non_ascii_prompt_survives_c_locale() {
	# A real history.jsonl (chat prompts) is virtually guaranteed to contain
	# non-ASCII text (curly quotes, emoji, accents, CJK). open() with no
	# encoding= falls back to locale.getpreferredencoding(), which is ASCII
	# under LC_ALL=C/LANG=C -- a standard, deliberately-set locale for
	# deterministic CI/test environments, not a contrived edge case. That
	# used to raise UnicodeDecodeError inside the embedded python3, produce
	# empty stdout, and still report rc 0 (fake success).
	d=$(tmp_dir)
	_lint_usage_home "$d"
	hist="$d/utf8-history.jsonl"
	printf '{"display":"/alpha caf\xc3\xa9 \xf0\x9f\x9a\x80 done","date":"2026-06-20"}\n' >"$hist"
	run_cmd env LC_ALL=C LANG=C HOME="$d" "$SKILLS_LINT" --usage "$hist"
	assert_rc 0 "skills-lint --usage exits 0 under LC_ALL=C with non-ASCII history content"
	assert_contains "$OUT" "1 prompts, 2026-06-20..2026-06-20" "skills-lint --usage prints the header despite non-ASCII content under LC_ALL=C"
	assert_contains "$OUT" "1 alpha skill 2026-06-20" "skills-lint --usage counts a non-ASCII prompt under LC_ALL=C instead of producing empty output"
}

t_lint_usage_shared_name_skill_and_command_not_double_counted() {
	# A skill directory and a command file sharing a basename used to double
	# the reported count on BOTH rows: the embedded Python's patterns/uses/
	# last_used dicts were keyed by name only, while the counting loop
	# iterated once per (name, kind) entry in "items", so a single real
	# match incremented the shared counter twice. One real prompt mentioning
	# "/dup" must report exactly 1 use on both the skill and command line.
	d=$(tmp_dir)
	mkdir -p "$d/.claude/skills/dup" "$d/.claude/commands"
	: >"$d/.claude/commands/dup.md"
	hist="$d/dup-history.jsonl"
	printf '{"display":"/dup once","date":"2026-06-01"}\n' >"$hist"
	run_cmd env HOME="$d" "$SKILLS_LINT" --usage "$hist"
	assert_rc 0 "skills-lint --usage exits 0 when a skill and command share a name"
	assert_contains "$OUT" "1 prompts, 2026-06-01..2026-06-01" "skills-lint --usage counts exactly one prompt"
	assert_contains "$OUT" "1 dup skill 2026-06-01" "skills-lint --usage reports 1 (not 2) use for the shared-name skill row"
	assert_contains "$OUT" "1 dup command 2026-06-01" "skills-lint --usage reports 1 (not 2) use for the shared-name command row"
	assert_not_contains "$OUT" "2 dup" "skills-lint --usage never doubles the shared-name count"
}

t_lint_skills_lint_default_dir_uses_home() {
	# No <skills-dir> argument: must default to $HOME/.claude/skills.
	d=$(tmp_dir)
	mkdir -p "$d/.claude/skills/tool-only"
	cat >"$d/.claude/skills/tool-only/SKILL.md" <<'SKILLEOF'
---
name: tool-only
description: fixture for the default-skills-dir test.
---
Uses `rtk`.
SKILLEOF
	run_cmd env HOME="$d" "$SKILLS_LINT"
	assert_rc 0 "skills-lint with no argument exits 0 for a clean HOME/.claude/skills"
	assert_contains "$OUT" "TOOL" "skills-lint with no argument still scans HOME/.claude/skills"
}

t_lint_plugin_root_reference_resolves() {
	# C21 M2: a "${CLAUDE_PLUGIN_ROOT}/..." reference resolves against the
	# nearest ancestor of the scanned file that carries .claude-plugin/plugin.json.
	d=$(tmp_dir)
	mkdir -p "$d/plugin-root/.claude-plugin" "$d/plugin-root/skills/foo/references"
	printf '{"name":"fixture-plugin"}' >"$d/plugin-root/.claude-plugin/plugin.json"
	cat >"$d/plugin-root/skills/foo/SKILL.md" <<'SKILLEOF'
---
name: foo
description: fixture skill exercising ${CLAUDE_PLUGIN_ROOT} resolution.
---
See `${CLAUDE_PLUGIN_ROOT}/skills/foo/references/note.md` for details.
SKILLEOF
	echo "note" >"$d/plugin-root/skills/foo/references/note.md"
	run_cmd "$SKILLS_LINT" "$d/plugin-root/skills"
	assert_rc 0 "skills-lint resolves a \${CLAUDE_PLUGIN_ROOT}/... reference against the plugin root"
	assert_not_contains "$OUT" "MISSING" "skills-lint reports no MISSING for a resolvable \${CLAUDE_PLUGIN_ROOT} reference"
}

t_lint_plugin_root_dead_reference_reports_missing() {
	d=$(tmp_dir)
	mkdir -p "$d/plugin-root/.claude-plugin" "$d/plugin-root/skills/foo"
	printf '{"name":"fixture-plugin"}' >"$d/plugin-root/.claude-plugin/plugin.json"
	cat >"$d/plugin-root/skills/foo/SKILL.md" <<'SKILLEOF'
---
name: foo
description: fixture skill with a dead ${CLAUDE_PLUGIN_ROOT} reference.
---
See `${CLAUDE_PLUGIN_ROOT}/skills/foo/does-not-exist.md` for details.
SKILLEOF
	run_cmd "$SKILLS_LINT" "$d/plugin-root/skills"
	assert_rc 1 "skills-lint exits 1 for a dead \${CLAUDE_PLUGIN_ROOT}/... reference"
	assert_contains "$OUT" "MISSING" "skills-lint reports MISSING for a dead \${CLAUDE_PLUGIN_ROOT} reference"
	assert_contains "$OUT" "does-not-exist.md" "skills-lint names the dead \${CLAUDE_PLUGIN_ROOT} reference path"
}

t_lint_plugin_root_no_ancestor_plugin_json_reports_missing() {
	# No .claude-plugin/plugin.json anywhere above the scanned skills dir:
	# the "${CLAUDE_PLUGIN_ROOT}/..." reference cannot resolve and must be
	# MISSING, not silently ignored or crash the scan.
	d=$(tmp_dir)
	mkdir -p "$d/no-plugin-here/skills/foo"
	cat >"$d/no-plugin-here/skills/foo/SKILL.md" <<'SKILLEOF'
---
name: foo
description: fixture skill outside any plugin root.
---
See `${CLAUDE_PLUGIN_ROOT}/skills/foo/note.md` for details.
SKILLEOF
	run_cmd "$SKILLS_LINT" "$d/no-plugin-here/skills"
	assert_rc 1 "skills-lint exits 1 when no ancestor .claude-plugin/plugin.json exists"
	assert_contains "$OUT" "MISSING" "skills-lint reports MISSING when no plugin root is found"
}

t_lint_plugin_root_nested_reference_walks_up_past_skills_dir() {
	# The plugin root is TWO levels above the reference-bearing file
	# (skills/foo/references/deep.md -> skills/foo -> skills -> plugin root);
	# resolution must walk all the way up, not stop at the skill's own dir.
	d=$(tmp_dir)
	mkdir -p "$d/plugin-root/.claude-plugin" "$d/plugin-root/skills/foo/references"
	printf '{"name":"fixture-plugin"}' >"$d/plugin-root/.claude-plugin/plugin.json"
	cat >"$d/plugin-root/skills/foo/references/deep.md" <<'SKILLEOF'
Cross-reference: `${CLAUDE_PLUGIN_ROOT}/scripts/helper.sh`
SKILLEOF
	mkdir -p "$d/plugin-root/scripts"
	echo '#!/usr/bin/env bash' >"$d/plugin-root/scripts/helper.sh"
	run_cmd "$SKILLS_LINT" "$d/plugin-root/skills"
	assert_rc 0 "skills-lint walks up past skills/ to find the plugin root"
	assert_not_contains "$OUT" "MISSING" "skills-lint resolves a nested \${CLAUDE_PLUGIN_ROOT} reference via the plugin root"
}

t_lint_plugin_root_bare_prefix_ignored() {
	# A bare "${CLAUDE_PLUGIN_ROOT}/" mention with nothing after it (e.g. in
	# prose describing the convention) names no specific path and must not
	# be reported, matching the existing bare-prefix rules.
	d=$(tmp_dir)
	mkdir -p "$d/plugin-root/.claude-plugin" "$d/plugin-root/skills/foo"
	printf '{"name":"fixture-plugin"}' >"$d/plugin-root/.claude-plugin/plugin.json"
	cat >"$d/plugin-root/skills/foo/SKILL.md" <<'SKILLEOF'
---
name: foo
description: fixture skill mentioning the bare ${CLAUDE_PLUGIN_ROOT}/ prefix.
---
Paths under `${CLAUDE_PLUGIN_ROOT}/` are substituted by Claude Code.
SKILLEOF
	run_cmd "$SKILLS_LINT" "$d/plugin-root/skills"
	assert_rc 0 "skills-lint ignores a bare \${CLAUDE_PLUGIN_ROOT}/ prefix with no path segment"
	assert_not_contains "$OUT" "MISSING" "skills-lint does not report the bare \${CLAUDE_PLUGIN_ROOT}/ prefix as missing"
}

t_lint_plugin_root_help_documents_it() {
	run_cmd "$SKILLS_LINT" --help
	assert_contains "$OUT" "CLAUDE_PLUGIN_ROOT" "skills-lint --help documents \${CLAUDE_PLUGIN_ROOT} resolution"
	assert_contains "$OUT" "plugin.json" "skills-lint --help names the .claude-plugin/plugin.json anchor"
}
