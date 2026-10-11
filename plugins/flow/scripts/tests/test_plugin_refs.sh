#!/usr/bin/env bash
# test_plugin_refs.sh — C21 M2: verifies the plugins/flow/skills
# reference rewrite, hooks.json, and skills-lint's ${CLAUDE_PLUGIN_ROOT}
# resolution. Sourced by tests/run.sh, which defines HERE (this dir) and
# SCAN_DIR (its parent, plugins/flow/scripts).

PLUGIN_ROOT_PREF="$SCAN_DIR/.."
SKILLS_DIR_PREF="$PLUGIN_ROOT_PREF/skills"
HOOKS_DIR_PREF="$PLUGIN_ROOT_PREF/hooks"
HOOKS_JSON_PREF="$HOOKS_DIR_PREF/hooks.json"

# Sibling flow-extras plugin (audit, pr-reviewer, claude-improver, skill-forge
# and 12 more moved out of flow) — the legacy-ref and CLAUDE_PLUGIN_ROOT scans
# below cover it too, since some of the documented exceptions now live there.
PLUGIN_ROOT_EXTRAS="$PLUGIN_ROOT_PREF/../flow-extras"
SKILLS_DIR_EXTRAS="$PLUGIN_ROOT_EXTRAS/skills"

t_pref_no_legacy_refs_outside_documented_exceptions() {
	# Every ".claude/skills/<x>/", "~/.claude/<x>" and "$HOME/.claude/<x>"
	# under plugins/flow/skills and its sibling plugins/flow-extras/skills
	# must have been rewritten to ${CLAUDE_PLUGIN_ROOT} (C21), except a
	# short, documented list: a cross-plugin reference to agent-browser in
	# qa/SKILL.md (a skill that lives in the "web" plugin, not this one, so
	# ${CLAUDE_PLUGIN_ROOT} cannot resolve it — it names the live-loading
	# path ~/.claude/skills/web/skills/agent-browser/SKILL.md explicitly,
	# which skills-lint must still resolve; see
	# t_pref_skills_lint_zero_missing_over_plugin), the same corrected
	# post-migration path (with the web/skills/ segment, not the stale
	# pre-migration flat path) in shared/agent-browser-reference.md and
	# qa/references/agent-prompts.md (fenced prompt template, never checked
	# by skills-lint per C16 — its content is instead pinned by
	# t_pref_agent_prompts_no_stale_agent_browser_path below, since a fence-blind
	# linter cannot tell a corrected reference from a stale one) worded as
	# "the project's own local
	# copy" since it is inherently project-relative, generic
	# Claude-Code-convention prose in claude-improver (now in flow-extras; it
	# describes an arbitrary TARGET project's ~/.claude layout while it
	# audits that project, never this plugin's own files), a mention in
	# pr-reviewer (now in flow-extras) of the project's own (unlikely to
	# exist) ".claude/skills/pr-reviewer" directory (contrasted with the
	# plugin's static helper-script path, which now resolves via
	# ${CLAUDE_PLUGIN_ROOT} — see
	# t_pref_pr_reviewer_uses_plugin_root_for_post_review), a bare
	# "`.claude/skills/`" mention in project-detection.md (flow's shared/
	# copy and flow-extras' pr-reviewer/references/ copy alike) with no path
	# segment after it (nothing for ${CLAUDE_PLUGIN_ROOT} to substitute,
	# matching skills-lint's own bare-prefix exemption), and skill-forge's
	# (now in flow-extras) Step 0 reuse-check sentence, which names
	# `~/.claude/skills/*/SKILL.md` and `~/.claude/skills/*/skills/*/SKILL.md`
	# as places to grep for an existing skill before building fresh (the same
	# category as the claude-improver exception above — it names the USER's
	# personal skill directories as a search target, never this plugin's own
	# files; test_skill_forge.sh pins that literal path, so rewording the
	# skill is not the fix). Same category: flow-extras verify-skill writes a
	# generated skill into the TARGET project's `.claude/skills/verify-<name>/`,
	# and shared/verification.md prefers that project-local skill when present;
	# both name the project's own directory, never this plugin's files. Same
	# category again: next's done-audit and lesson --retro read the user's own
	# session transcripts under `~/.claude/projects/`, never plugin files.
	hits=$(grep -rnE '\.claude/skills/|~/\.claude/|\$HOME/\.claude/' --include='*.md' "$SKILLS_DIR_PREF" "$SKILLS_DIR_EXTRAS" 2>/dev/null |
		grep -vF "/shared/agent-browser-reference.md:" |
		grep -vF "/qa/references/agent-prompts.md:" |
		grep -vE "/qa/SKILL\.md:[0-9]+:.*agent-browser skill" |
		grep -vF "/claude-improver/" |
		grep -vF ".claude/skills/pr-reviewer" |
		grep -vF ".claude/skills/verify-" |
		grep -vF "~/.claude/projects" |
		grep -vF 'Check for `.claude/skills/` in the project' |
		grep -vE '/skill-forge/SKILL\.md:[0-9]+:.*`grep -ril`')
	assert_eq "$hits" "" "no legacy .claude/skills, ~/.claude, or \$HOME/.claude references remain under skills/ (flow or flow-extras) outside the documented exceptions"
}

t_pref_hooks_json_parses() {
	if ! command -v python3 >/dev/null 2>&1; then
		printf '  skip t_pref_hooks_json_parses (python3 absent)\n'
		return 0
	fi
	run_cmd python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$HOOKS_JSON_PREF"
	assert_rc 0 "hooks.json parses as valid JSON"
}

t_pref_hooks_json_lists_every_hook_file_and_it_exists() {
	if ! command -v python3 >/dev/null 2>&1; then
		printf '  skip t_pref_hooks_json_lists_every_hook_file_and_it_exists (python3 absent)\n'
		return 0
	fi
	missing=$(python3 -c '
import json, os, sys
d = json.load(open(sys.argv[1]))
hooks_dir = sys.argv[2]
prefix = "\"${CLAUDE_PLUGIN_ROOT}\"/hooks/"
problems = []
seen = 0
for _event, entries in d.get("hooks", {}).items():
    for entry in entries:
        for h in entry.get("hooks", []):
            cmd = h.get("command", "")
            if not cmd.startswith(prefix):
                problems.append("bad-prefix:" + cmd)
                continue
            rel = cmd[len(prefix):]
            seen += 1
            if not os.path.isfile(os.path.join(hooks_dir, rel)):
                problems.append("missing-file:" + rel)
if seen == 0:
    problems.append("NO-HOOKS-FOUND")
print("\n".join(problems))
' "$HOOKS_JSON_PREF" "$HOOKS_DIR_PREF")
	assert_eq "$missing" "" 'every hooks.json command references "${CLAUDE_PLUGIN_ROOT}"/hooks/<file> and that file exists'
}

t_pref_hooks_json_covers_every_c5_event() {
	if ! command -v python3 >/dev/null 2>&1; then
		printf '  skip t_pref_hooks_json_covers_every_c5_event (python3 absent)\n'
		return 0
	fi
	run_cmd python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
print(",".join(sorted(d.get("hooks", {}).keys())))
' "$HOOKS_JSON_PREF"
	for ev in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop PreCompact; do
		assert_contains "$OUT" "$ev" "hooks.json covers the $ev event"
	done
}

t_pref_plugin_root_references_exist_and_resolve() {
	count=$(grep -rlF '${CLAUDE_PLUGIN_ROOT}/' --include='*.md' "$SKILLS_DIR_PREF" 2>/dev/null | wc -l | tr -d ' ')
	found=no
	[ "$count" -gt 0 ] && found=yes
	assert_eq "$found" "yes" "at least one \${CLAUDE_PLUGIN_ROOT}/ reference exists under skills/ (sanity check that the rewrite ran)"

	run_cmd "$SCAN_DIR/skills-lint" "$SKILLS_DIR_PREF"
	bad=$(printf '%s\n' "$OUT" | grep 'MISSING' | grep 'CLAUDE_PLUGIN_ROOT' || true)
	assert_eq "$bad" "" "skills-lint reports no MISSING \${CLAUDE_PLUGIN_ROOT} reference under plugins/flow/skills"

	# pr-reviewer (moved to flow-extras) carries its own ${CLAUDE_PLUGIN_ROOT}
	# references (post-review.sh, its project-detection.md copy) — same check,
	# sibling plugin.
	count_extras=$(grep -rlF '${CLAUDE_PLUGIN_ROOT}/' --include='*.md' "$SKILLS_DIR_EXTRAS" 2>/dev/null | wc -l | tr -d ' ')
	found_extras=no
	[ "$count_extras" -gt 0 ] && found_extras=yes
	assert_eq "$found_extras" "yes" "at least one \${CLAUDE_PLUGIN_ROOT}/ reference exists under flow-extras/skills/"

	run_cmd "$SCAN_DIR/skills-lint" "$SKILLS_DIR_EXTRAS"
	bad_extras=$(printf '%s\n' "$OUT" | grep 'MISSING' | grep 'CLAUDE_PLUGIN_ROOT' || true)
	assert_eq "$bad_extras" "" "skills-lint reports no MISSING \${CLAUDE_PLUGIN_ROOT} reference under plugins/flow-extras/skills"
}

t_pref_skills_lint_zero_missing_over_plugin() {
	# Hermetic (fix round 1, finding 1): must NOT depend on this developer's
	# ambient $HOME. On this machine $HOME/.claude/skills still holds the
	# pre-migration flat dotfiles layout (including a bare skills/agent-browser/
	# dir), which made this check pass by accident regardless of whether the
	# in-repo references actually resolve under C21's target layout. Build a
	# fake $HOME containing only the per-plugin symlinks that C21's "Live
	# loading" section describes (one symlink per plugin, nothing else) and
	# require zero MISSING there — that is the actual post-cutover shape.
	fake_home=$(tmp_dir)
	mkdir -p "$fake_home/.claude/skills"
	plugin_root_abs=$(cd "$PLUGIN_ROOT_PREF" && pwd -P)
	ln -s "$plugin_root_abs" "$fake_home/.claude/skills/flow"
	web_plugin_abs="$plugin_root_abs/../web"
	if [ -d "$web_plugin_abs" ]; then
		ln -s "$(cd "$web_plugin_abs" && pwd -P)" "$fake_home/.claude/skills/web"
	else
		printf '  note: plugins/web absent from this checkout — agent-browser cross-plugin ref cannot be fully exercised\n'
	fi

	run_cmd env HOME="$fake_home" "$SCAN_DIR/skills-lint" "$SKILLS_DIR_PREF"
	assert_rc 0 "skills-lint exits 0 (zero MISSING) over plugins/flow/skills in an isolated HOME mirroring C21 post-cutover live loading, not this machine's ambient dotfiles state"
	assert_not_contains "$OUT" "MISSING" "no MISSING line under the isolated post-cutover HOME"
	assert_not_contains "$OUT" "agent-browser" "the qa/SKILL.md and shared/agent-browser-reference.md cross-plugin agent-browser references resolve under the isolated HOME (finding 3)"
}

t_pref_agent_prompts_no_stale_agent_browser_path() {
	# Fix round 2, findings 1+2: qa/references/agent-prompts.md is inside
	# ``` fences (C16 exempts fenced content from skills-lint's fence-blind
	# scan — see scripts/skills-lint's blanking logic), so a stale
	# pre-migration path there is invisible to skills-lint and to
	# t_pref_skills_lint_zero_missing_over_plugin above. This test reads the
	# file's prose directly instead of relying on skills-lint. Both the
	# Browser Tester and Accessibility Auditor prompt templates in this file
	# told an agent to read the agent-browser skill at the OLD flat path
	# ~/.claude/skills/agent-browser/SKILL.md (no web/skills/ segment) — dead
	# under C21's live-loading layout, where agent-browser now ships in the
	# separate "web" plugin. qa/SKILL.md:133, one paragraph away in the same
	# skill, already names the corrected path; this file must match it.
	agent_prompts="$SKILLS_DIR_PREF/qa/references/agent-prompts.md"
	assert_file_exists "$agent_prompts" "qa/references/agent-prompts.md exists"

	stale=$(grep -n '[~]/.claude/skills/agent-browser/SKILL.md' "$agent_prompts" 2>/dev/null || true)
	assert_eq "$stale" "" "qa/references/agent-prompts.md contains no stale pre-migration agent-browser/SKILL.md path (missing web/skills/ segment)"

	correct_count=$(grep -c '[~]/.claude/skills/web/skills/agent-browser/SKILL.md' "$agent_prompts" 2>/dev/null || echo 0)
	assert_eq "$correct_count" "2" "both the Browser Tester and Accessibility Auditor prompt templates point agent-browser at the corrected web/skills/ path"
}

t_pref_pr_reviewer_uses_plugin_root_for_post_review() {
	# Fix round 1, finding 2: the primary path must resolve post-review.sh
	# via ${CLAUDE_PLUGIN_ROOT} at its static, plugin-relative location, not
	# a runtime `find ~/.claude/skills -name post-review.sh -path */pr-reviewer/*`
	# — plain `find` (no -L) does not traverse a symlinked directory, so
	# under Live Loading (~/.claude/skills/flow-extras -> the plugin repo)
	# that lookup silently resolves to empty and the skill permanently falls
	# back to the documented lower-quality path ("no preflight validation").
	# pr-reviewer moved to flow-extras; same invariant, new home.
	skill_md="$SKILLS_DIR_EXTRAS/pr-reviewer/SKILL.md"
	assert_file_exists "$skill_md" "pr-reviewer/SKILL.md exists"

	hits=$(grep -c 'find ~/.claude/skills' "$skill_md" 2>/dev/null || true)
	assert_eq "${hits:-0}" "0" "pr-reviewer/SKILL.md no longer resolves post-review.sh via a runtime find"

	contains_line=no
	grep -qF 'SKILL_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/pr-reviewer/scripts/post-review.sh"' "$skill_md" && contains_line=yes
	assert_eq "$contains_line" "yes" "pr-reviewer/SKILL.md resolves post-review.sh via \${CLAUDE_PLUGIN_ROOT}"

	assert_file_exists "$SKILLS_DIR_EXTRAS/pr-reviewer/scripts/post-review.sh" "post-review.sh ships at the referenced plugin-relative path"

	# Reproduce the finding's exact scenario: a symlinked ~/.claude/skills/flow-extras
	# (Live Loading, C21) must let the ${CLAUDE_PLUGIN_ROOT}-substituted path
	# resolve and stay executable.
	fake_home=$(tmp_dir)
	mkdir -p "$fake_home/.claude/skills"
	plugin_root_abs=$(cd "$PLUGIN_ROOT_EXTRAS" && pwd -P)
	ln -s "$plugin_root_abs" "$fake_home/.claude/skills/flow-extras"
	resolved="$fake_home/.claude/skills/flow-extras/skills/pr-reviewer/scripts/post-review.sh"
	assert_file_exists "$resolved" "the \${CLAUDE_PLUGIN_ROOT}-substituted post-review.sh path resolves through the Live Loading symlink"
	run_cmd test -x "$resolved"
	assert_rc 0 "post-review.sh is executable through the symlinked plugin root"
}

t_pref_skill_tool_pointer_form() {
	local f
	for f in "$SKILLS_DIR_PREF/no-slop/SKILL.md" "$SKILLS_DIR_PREF/shared/pr-body.md" "$SKILLS_DIR_PREF/fix/SKILL.md"; do
		run_cmd grep -Eq 'call the Skill tool with "[a-z0-9-]+:[a-z0-9-]+"' "$f"
		assert_rc 0 "$(basename "$(dirname "$f")")/$(basename "$f") uses the Skill-tool pointer form with a plugin:skill name"
	done
}

t_pref_skill_calls_resolve_in_marketplace() {
	# Every cross-plugin call written as `skill: "<plugin>:<name>"` or
	# `Skill tool with "<plugin>:<name>"` must name a plugin listed in
	# marketplace.json and a skill that exists in this repo. A call to an
	# outside plugin only works on machines that happen to have it installed.
	local plugins_dir mkt bad pair plugin name
	plugins_dir="$PLUGIN_ROOT_PREF/.."
	mkt="$plugins_dir/../.claude-plugin/marketplace.json"
	assert_file_exists "$mkt" "marketplace.json exists"
	bad=""
	for pair in $(grep -rhoE 'skill: "[a-z0-9-]+:[a-z0-9-]+"|Skill tool with "[a-z0-9-]+:[a-z0-9-]+"' --include='*.md' "$plugins_dir" 2>/dev/null |
		grep -oE '"[a-z0-9-]+:[a-z0-9-]+"' | tr -d '"' | sort -u); do
		plugin=${pair%%:*}
		name=${pair#*:}
		if ! grep -qF "\"source\": \"./plugins/$plugin\"" "$mkt" || [ ! -f "$plugins_dir/$plugin/skills/$name/SKILL.md" ]; then
			bad="$bad $pair"
		fi
	done
	assert_eq "$bad" "" "every plugin:skill call resolves to a marketplace plugin's skills/<name>/SKILL.md"
}

t_pref_no_frontend_design_calls() {
	# brainstorm and explainer route aesthetics to flow's own design:design.
	# Credit lines may name the upstream path anthropics/skills .../frontend-design/.
	local hits
	hits=$(grep -rn 'frontend-design' --include='*.md' "$PLUGIN_ROOT_PREF/.." 2>/dev/null |
		grep -vF '/skill-judge/SKILL.md:' |
		grep -v 'adapted from ')
	assert_eq "$hits" "" "no frontend-design reference remains outside skill-judge's example table and credit lines"
}

# ---------------------------------------------------------------------------
# skills-lint --frontmatter / --orphans / --collisions / --claude-md (F18-F23)
# ---------------------------------------------------------------------------

# fm_skill <root> <dir> <name> <description> [extra frontmatter line]
fm_skill() {
	mkdir -p "$1/skills/$2"
	printf -- '---\nname: %s\ndescription: %s\n%s\n---\nbody\n' "$3" "$4" "${5:-}" >"$1/skills/$2/SKILL.md"
}

fm_lint() { run_cmd bash "$SCAN_DIR/skills-lint" "$@"; }

t_fm_clean_fixture_passes() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" good-one good-one "Does a thing when asked. Not for X (use Y)."
	fm_lint --frontmatter "$d"
	assert_rc 0 "t_fm_clean clean fixture exits 0"
	rm -rf "$d"
}

t_fm_each_violation_exits_1() {
	local d long
	long=$(printf 'a%.0s' $(seq 1 1100))
	d=$(tmp_dir)
	fm_skill "$d" long-desc long-desc "$long"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm long description exits 1"
	assert_contains "$OUT" "DESC-LEN" "t_fm long description prints DESC-LEN"
	assert_contains "$OUT" " 1100" "t_fm DESC-LEN carries the length"
	rm -rf "$d"
	d=$(tmp_dir)
	local n65
	n65=$(printf 'n%.0s' $(seq 1 65))
	fm_skill "$d" "$n65" "$n65" "fine"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm 65-char name exits 1"
	assert_contains "$OUT" "64 chars" "t_fm 65-char name is rejected for its length"
	rm -rf "$d"
	d=$(tmp_dir)
	fm_skill "$d" dir-name other-name "fine"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm name != dir exits 1"
	assert_contains "$OUT" "NAME" "t_fm name != dir prints NAME"
	rm -rf "$d"
	d=$(tmp_dir)
	fm_skill "$d" has-model has-model "fine" "model: bogus"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm model bogus exits 1"
	assert_contains "$OUT" "MODEL" "t_fm model bogus prints MODEL"
	rm -rf "$d"
	d=$(tmp_dir)
	fm_skill "$d" colon-desc colon-desc "Triggers on: foo bar"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm unquoted ': ' in description exits 1"
	assert_contains "$OUT" "YAML" "t_fm unquoted colon prints YAML"
	rm -rf "$d"
}

t_fm_duplicate_name_exits_1() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" same-name same-name "one"
	mkdir -p "$d/other/skills/same-name"
	printf -- '---\nname: same-name\ndescription: two\n---\n' >"$d/other/skills/same-name/SKILL.md"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm duplicate name exits 1"
	assert_contains "$OUT" "DUP-NAME" "t_fm duplicate prints DUP-NAME"
	rm -rf "$d"
}

t_fm_angle_brackets_only_under_claude_ai() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" angle angle "Run with <x> given."
	fm_lint --frontmatter "$d"
	assert_rc 0 "t_fm angle brackets pass by default (Claude Code accepts them)"
	fm_lint --frontmatter --claude-ai "$d"
	assert_rc 1 "t_fm angle brackets exit 1 under --claude-ai"
	rm -rf "$d"
}

t_fm_agent_name_must_match_filename() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/agents"
	printf -- '---\nname: other\ndescription: x\nmodel: sonnet\n---\n' >"$d/agents/mine.md"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm agent name != filename exits 1"
	rm -rf "$d"
}

t_fm_repo_frontmatter_is_clean() {
	fm_lint --frontmatter "$SCAN_DIR/../.."
	assert_eq "$OUT" "$(printf '%s' "$OUT" | grep -E '^KEY ' || true)" "t_fm repo has no frontmatter errors (only KEY warnings allowed)"
	assert_rc 0 "t_fm repo plugins exit 0"
}

t_fm_repo_frontmatter_parses_with_pyyaml() {
	if ! python3 -I -c 'import yaml' 2>/dev/null; then
		printf '  note: PyYAML absent, skipping the strict-parse cross-check\n'
		return 0
	fi
	run_cmd python3 -I -c '
import glob, re, sys, yaml
bad = []
for f in glob.glob(sys.argv[1] + "/*/skills/*/SKILL.md") + glob.glob(sys.argv[1] + "/*/agents/*.md"):
    m = re.match(r"---\n(.*?)\n---", open(f).read(), re.S)
    try:
        yaml.safe_load(m.group(1))
    except Exception:
        bad.append(f)
print("\n".join(bad))
' "$SCAN_DIR/../.."
	assert_eq "$OUT" "" "t_fm PyYAML safe_load parses every plugin skill and agent frontmatter"
}

t_orph_unlinked_reference_fails() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" has-refs has-refs "fine"
	mkdir -p "$d/skills/has-refs/references"
	printf 'x\n' >"$d/skills/has-refs/references/lonely.md"
	fm_lint --orphans "$d"
	assert_rc 1 "t_orph unlinked reference exits 1"
	assert_contains "$OUT" "ORPHAN" "t_orph prints ORPHAN"
	assert_contains "$OUT" "lonely.md" "t_orph names the file"
	rm -rf "$d"
}

t_orph_script_named_by_backticked_path_and_tests_pass() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" has-scripts has-scripts "fine"
	printf 'Run `scripts/tool.sh` first. See references/a-ref.md.\n' >>"$d/skills/has-scripts/SKILL.md"
	mkdir -p "$d/skills/has-scripts/scripts" "$d/skills/has-scripts/references"
	printf 'x\n' >"$d/skills/has-scripts/scripts/tool.sh"
	printf 'x\n' >"$d/skills/has-scripts/scripts/test_tool.sh"
	printf 'see deeper.md\n' >"$d/skills/has-scripts/references/a-ref.md"
	printf 'x\n' >"$d/skills/has-scripts/references/deeper.md"
	fm_lint --orphans "$d"
	assert_rc 0 "t_orph backticked script, transitive reference and test_ file are not orphans"
	assert_not_contains "$OUT" "test_tool.sh" "t_orph test_ files are never reported"
	rm -rf "$d"
}

t_orph_repo_has_none() {
	fm_lint --orphans "$SCAN_DIR/../.."
	assert_eq "$OUT" "" "t_orph repo plugins have no orphan reference or script"
}

t_fm_continuation_lines_are_measured_and_checked() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/skills/wrap-long" "$d/skills/wrap-colon" "$d/skills/wrap-junk"
	printf -- '---\nname: wrap-long\ndescription: start\n  %s\n---\n' "$(printf 'a%.0s' $(seq 1 1100))" >"$d/skills/wrap-long/SKILL.md"
	printf -- '---\nname: wrap-colon\ndescription: start\n  key: value here\n---\n' >"$d/skills/wrap-colon/SKILL.md"
	printf -- '---\nname: wrap-junk\ndescription: "quoted" trailing junk\n---\n' >"$d/skills/wrap-junk/SKILL.md"
	fm_lint --frontmatter "$d"
	assert_rc 1 "t_fm continuation and trailing-junk hazards exit 1"
	assert_contains "$OUT" "DESC-LEN $d/skills/wrap-long/SKILL.md 1106" "t_fm wrapped description is measured whole"
	assert_contains "$OUT" "wrap-colon/SKILL.md:4" "t_fm continuation-line ': ' is flagged"
	assert_contains "$OUT" "wrap-junk/SKILL.md:3" "t_fm text after a closing quote is flagged"
	rm -rf "$d"
}

t_coll_lists_near_duplicates_not_distinct() {
	local d
	d=$(tmp_dir)
	fm_skill "$d" pdf-a pdf-a "Extracts text and tables from PDF documents. Use when the user asks to read a PDF, parse a PDF invoice or pull tables out of a PDF."
	fm_skill "$d" pdf-b pdf-b "Extracts text and tables from PDF documents. Use when the user asks to read a PDF, parse a PDF invoice or pull tables out of PDF files."
	fm_skill "$d" fin-c fin-c "Builds a concentrated equity portfolio from earnings catalysts and valuation, then sizes positions as percentages of equity."
	fm_skill "$d" web-d web-d "Drives a headless browser to click buttons, fill forms and capture screenshots of a running web page."
	fm_lint --collisions "$d"
	assert_rc 0 "t_coll report exits 0 even with a collision"
	assert_contains "$OUT" "COLLISION" "t_coll near-identical pair is listed"
	assert_contains "$OUT" "pdf-a" "t_coll names the first path"
	assert_contains "$OUT" "pdf-b" "t_coll names the second path"
	assert_not_contains "$OUT" "fin-c" "t_coll finance skill is not listed against anything"
	assert_not_contains "$OUT" "web-d" "t_coll browser skill is not listed against anything"
	rm -rf "$d"
}

t_cmdpaths_dead_path_in_claude_md_fails() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf 'x\n' >"$d/src/real.ts"
	printf '# Proj\nSee `src/gone.ts` for the entry point.\n' >"$d/CLAUDE.md"
	fm_lint --claude-md "$d"
	assert_rc 1 "t_cmdpaths missing backticked path exits 1"
	assert_contains "$OUT" "MISSING" "t_cmdpaths prints MISSING"
	assert_contains "$OUT" "src/gone.ts" "t_cmdpaths names the path"
	rm -rf "$d"
}

t_cmdpaths_globs_placeholders_and_existing_pass() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/src"
	printf 'x\n' >"$d/src/real.ts"
	printf '# Proj\nGlob `src/**/*.ts`, placeholder `<path>/x.md`, real `src/real.ts:12`, cmd `npm run build`, prose `and/or`.\n```\n`src/in-fence.ts`\n```\n' >"$d/CLAUDE.md"
	fm_lint --claude-md "$d"
	assert_rc 0 "t_cmdpaths globs, placeholders, real paths, commands and fences are ignored"
	rm -rf "$d"
}

t_cmdpaths_dot_slash_and_ellipsis_are_not_dead_paths() {
	local d
	d=$(tmp_dir)
	mkdir -p "$d/sub/src/lib"
	printf 'x\n' >"$d/sub/src/lib/real.ts"
	printf 'Import `./real.ts`, prefixes `feat/...` and `fix/\xe2\x80\xa6`.\n' >"$d/CLAUDE.md"
	fm_lint --claude-md "$d"
	assert_rc 0 "t_cmdpaths ./ prefix resolves below the root and ellipsis placeholders skip"
	assert_not_contains "$OUT" "MISSING" "t_cmdpaths no MISSING for ./ or ..."
	rm -rf "$d"
}

t_cmdpaths_progress_ruling_line_is_checked() {
	local d
	d=$(tmp_dir)
	printf 'Ruling: keep scripts/old.sh\nNote: see scripts/other-gone.sh\n' >"$d/PROGRESS.md"
	fm_lint --claude-md "$d"
	assert_rc 1 "t_cmdpaths a Ruling line citing a missing path exits 1"
	assert_contains "$OUT" "scripts/old.sh" "t_cmdpaths names the Ruling path"
	assert_not_contains "$OUT" "other-gone" "t_cmdpaths only Ruling lines are read in PROGRESS.md"
	rm -rf "$d"
}

t_cmdpaths_claude_md_skill_runs_the_lint() {
	assert_contains "$(cat "$SCAN_DIR/../../flow-extras/skills/claude-md/SKILL.md")" "skills-lint --claude-md" "t_cmdpaths claude-md audit step runs the dead-path lint"
}

t_fm_skill_judge_step0_calls_frontmatter_lint() {
	local sj
	sj=$(cat "$SCAN_DIR/../../flow-extras/skills/skill-judge/SKILL.md")
	assert_contains "$sj" "skills-lint --frontmatter" "t_fm skill-judge Step 0(b) runs the frontmatter lint"
	assert_contains "$sj" "--orphans" "t_fm skill-judge Step 0 runs the orphan check"
	assert_contains "$sj" "--collisions" "t_fm skill-judge points at the collision report"
}
