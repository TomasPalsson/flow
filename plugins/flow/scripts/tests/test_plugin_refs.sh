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
	# skill is not the fix).
	hits=$(grep -rnE '\.claude/skills/|~/\.claude/|\$HOME/\.claude/' --include='*.md' "$SKILLS_DIR_PREF" "$SKILLS_DIR_EXTRAS" 2>/dev/null |
		grep -vF "/shared/agent-browser-reference.md:" |
		grep -vF "/qa/references/agent-prompts.md:" |
		grep -vF "/qa/SKILL.md:133:" |
		grep -vF "/claude-improver/" |
		grep -vF ".claude/skills/pr-reviewer" |
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
