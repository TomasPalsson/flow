#!/usr/bin/env bash
# test_marketplace.sh — tests for the C21 marketplace migration layout
# (unit M1: plugin/skill copy + manifests). t_mkt_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.
#
# The marketplace repo lives outside the dotfiles tree per C21
# ("~/Desktop/Projects/flow"); override with FLOW_REPO for testing
# against a different checkout.

REPO="${FLOW_REPO:-$HOME/Desktop/Projects/flow}"
MKT_JSON="$REPO/.claude-plugin/marketplace.json"

# bundle<space>skill pairs, per C21's target layout.
_MKT_SKILL_LIST='flow next
flow spec
flow flow-deepen
flow spec-judge
flow shared
flow qa
flow fix
flow prep
flow develop-idea
flow-extras audit
flow-extras ultracode
flow-extras overkill
flow-extras pr-reviewer
flow-extras claude-md
flow-extras skill-forge
flow-extras skill-improver
flow-extras skill-judge
flow-extras claude-improver
flow-extras find-skills
flow-extras prompt-engineer
flow-extras better-plan
flow-extras grill-me
flow-extras grill-with-docs
flow-extras brainstorm
flow-extras scrutinize-idea
design design
design impeccable
design ui-ux-pro-max
design mobile-design
design polish
design showcase
design ui-animation
design explainer
finance alpha-hunt
finance portfolio
finance investment
finance etoro
aws aws-explore
aws aws-lambda-microvms
aws strands-agentcore
aws strands-steering-hooks
aws agui-strands
aws sst
web seo-audit
web google-ads
web figma-to-strapi
web website-cloner
web api-explorer
web agent-browser
tooling new-project
tooling node-cli-builder
tooling python-code-style
tooling clean-code
tooling gh-cli
tooling version-audit
tooling agent-architecture
tooling agent-evals
tooling rag-guide
tooling cocoindex
tooling pentest
tooling prompt-injection-tester
tooling slack
tooling worklog
tooling icelandic-professor'

t_mkt_repo_present() {
	assert_file_exists "$REPO" "t_mkt_repo_present marketplace repo checked out"
	assert_file_exists "$MKT_JSON" "t_mkt_repo_present marketplace.json present"
}

t_mkt_marketplace_parses_seven_plugins() {
	local py_out count names
	if [ ! -f "$MKT_JSON" ]; then
		_fail "t_mkt_marketplace_parses_seven_plugins" "no marketplace.json at $MKT_JSON"
		return 0
	fi
	py_out=$(
		python3 - "$MKT_JSON" <<'PYEOF'
import json, sys
with open(sys.argv[1]) as f:
    data = json.load(f)
plugins = data.get("plugins", [])
print(len(plugins))
for p in plugins:
    print(p.get("name", ""))
PYEOF
	)
	count=$(printf '%s\n' "$py_out" | head -1)
	names=$(printf '%s\n' "$py_out" | tail -n +2)
	assert_eq "$count" "7" "t_mkt_marketplace_parses_seven_plugins plugin-count"
	assert_contains "$names" "flow" "t_mkt_marketplace_parses_seven_plugins has-flow"
	assert_contains "$names" "flow-extras" "t_mkt_marketplace_parses_seven_plugins has-flow-extras"
	assert_contains "$names" "design" "t_mkt_marketplace_parses_seven_plugins has-design"
	assert_contains "$names" "finance" "t_mkt_marketplace_parses_seven_plugins has-finance"
	assert_contains "$names" "aws" "t_mkt_marketplace_parses_seven_plugins has-aws"
	assert_contains "$names" "web" "t_mkt_marketplace_parses_seven_plugins has-web"
	assert_contains "$names" "tooling" "t_mkt_marketplace_parses_seven_plugins has-tooling"
}

t_mkt_plugin_json_name_matches_dir() {
	local p pj name
	for p in flow flow-extras design finance aws web tooling; do
		pj="$REPO/plugins/$p/.claude-plugin/plugin.json"
		if [ ! -f "$pj" ]; then
			_fail "t_mkt_plugin_json_name_matches_dir:$p" "missing $pj"
			continue
		fi
		name=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('name',''))" "$pj" 2>/dev/null)
		assert_eq "$name" "$p" "t_mkt_plugin_json_name_matches_dir:$p"
	done
}

t_mkt_skills_exist_with_skillmd() {
	local bundle skill dir
	while read -r bundle skill; do
		[ -z "$bundle" ] && continue
		dir="$REPO/plugins/$bundle/skills/$skill"
		assert_file_exists "$dir" "t_mkt_skills_exist_with_skillmd:$bundle/$skill dir"
		# shared/ is reference material + scripts consumed by other skills;
		# it ships no SKILL.md of its own in the dotfiles source.
		if [ "$skill" != "shared" ]; then
			assert_file_exists "$dir/SKILL.md" "t_mkt_skills_exist_with_skillmd:$bundle/$skill SKILL.md"
		fi
	done <<EOF
$_MKT_SKILL_LIST
EOF
}

t_mkt_no_skill_in_two_bundles() {
	local names dup
	if [ ! -d "$REPO/plugins" ]; then
		_fail "t_mkt_no_skill_in_two_bundles" "no plugins dir at $REPO/plugins"
		return 0
	fi
	# a symlinked plugin dir is an alias of another bundle, not a second bundle
	names=$(cd "$REPO/plugins" && for d in */skills/*/; do
		[ -L "${d%%/*}" ] && continue
		basename "$d"
	done | sort)
	dup=$(printf '%s\n' "$names" | uniq -d)
	assert_eq "$dup" "" "t_mkt_no_skill_in_two_bundles no-duplicate-skill-names"
}

# Spec 004 deleted skills/feature (its execution-prompt.md moved into
# skills/next/); the third dir this pins is now skills/spec, the other half of
# the two-command surface. Same test, retargeted, not weakened.
t_mkt_harness_plugin_has_next_shared_spec() {
	assert_file_exists "$REPO/plugins/flow/skills/next" "t_mkt_harness_plugin_has_next_shared_spec next"
	assert_file_exists "$REPO/plugins/flow/skills/shared" "t_mkt_harness_plugin_has_next_shared_spec shared"
	assert_file_exists "$REPO/plugins/flow/skills/spec" "t_mkt_harness_plugin_has_next_shared_spec spec"
}

t_mkt_claude_plugin_validate_marketplace() {
	if ! command -v claude >/dev/null 2>&1; then
		printf '  skip t_mkt_claude_plugin_validate_marketplace (claude CLI not installed)\n'
		return 0
	fi
	run_cmd claude plugin validate "$MKT_JSON"
	assert_rc 0 "t_mkt_claude_plugin_validate_marketplace rc"
}

t_mkt_claude_plugin_validate_each_plugin() {
	local p
	if ! command -v claude >/dev/null 2>&1; then
		printf '  skip t_mkt_claude_plugin_validate_each_plugin (claude CLI not installed)\n'
		return 0
	fi
	for p in flow flow-extras design finance aws web tooling; do
		run_cmd claude plugin validate "$REPO/plugins/$p"
		assert_rc 0 "t_mkt_claude_plugin_validate_each_plugin:$p rc"
	done
}
