#!/usr/bin/env bash
# test_marketplace.sh — tests for the C21 marketplace migration layout
# (unit M1: plugin/skill copy + manifests). t_mkt_* prefix.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set.
#
# The marketplace repo lives outside the dotfiles tree per C21
# ("~/Desktop/Projects/flow"); REPO defaults to the checkout this file sits in
# (so a worktree tests itself); override with FLOW_REPO for a different checkout.

REPO="${FLOW_REPO:-$(git -C "$HERE" rev-parse --show-toplevel 2>/dev/null || printf %s "$HOME/Desktop/Projects/flow")}"
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
tooling icelandic'

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

# --- P02: plugin version drift (scripts/version-drift) ---------------------

# _mkt_drift_repo: temp repo shaped like the marketplace, on main.
_mkt_drift_repo() {
	local d
	d=$(tmp_repo)
	mkdir -p "$d/.claude-plugin" "$d/plugins/tooling/.claude-plugin"
	printf '{"name":"tooling","version":"1.0.0"}\n' >"$d/plugins/tooling/.claude-plugin/plugin.json"
	printf '{"plugins":[{"name":"tooling","source":"./plugins/tooling","version":"1.0.0"}]}\n' >"$d/.claude-plugin/marketplace.json"
	git -C "$d" add -A >/dev/null 2>&1
	git -C "$d" commit -q -m base
	git -C "$d" branch -M main
	printf '%s' "$d"
}

_mkt_set_version() { # <repo> <plugin.json version> <marketplace version>
	printf '{"name":"tooling","version":"%s"}\n' "$2" >"$1/plugins/tooling/.claude-plugin/plugin.json"
	printf '{"plugins":[{"name":"tooling","source":"./plugins/tooling","version":"%s"}]}\n' "$3" >"$1/.claude-plugin/marketplace.json"
}

_mkt_commit_version() { # <repo> <version>: set both files and commit (version-drift reads HEAD)
	_mkt_set_version "$1" "$2" "$2"
	git -C "$1" commit -q -am "version $2"
}

t_mkt_version_drift_cases() {
	local repo
	repo=$(_mkt_drift_repo)
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 0 "t_mkt_version_drift_cases on-main-skips-b"
	git -C "$repo" checkout -q -b feat
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 0 "t_mkt_version_drift_cases no-change"
	printf 'x\n' >"$repo/plugins/tooling/x"
	git -C "$repo" add -A >/dev/null 2>&1
	git -C "$repo" commit -q -m change
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 1 "t_mkt_version_drift_cases unbumped"
	assert_contains "$OUT" "tooling: " "t_mkt_version_drift_cases names-plugin"
	assert_contains "$OUT" "bump plugins/tooling/.claude-plugin/plugin.json and .claude-plugin/marketplace.json" "t_mkt_version_drift_cases message"
	_mkt_set_version "$repo" 1.0.0 1.0.1
	git -C "$repo" commit -q -am mismatch
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 1 "t_mkt_version_drift_cases entry-mismatch"
	_mkt_set_version "$repo" 1.0.1 1.0.1
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 1 "t_mkt_version_drift_cases uncommitted-bump-not-counted"
	git -C "$repo" commit -q -am bump
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 0 "t_mkt_version_drift_cases bumped"
	_mkt_commit_version "$repo" 0.9.9
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 1 "t_mkt_version_drift_cases lower-than-main"
	_mkt_commit_version "$repo" 1.0.0
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 1 "t_mkt_version_drift_cases equal-to-main"
	run_cmd "$SCAN_DIR/version-drift"
	assert_rc 2 "t_mkt_version_drift_cases usage-exits-2"
	run_cmd "$SCAN_DIR/version-drift" "$repo/nonexistent"
	assert_rc 2 "t_mkt_version_drift_cases missing-repo-exits-2"
	printf '{"plugins":[{"name":"tooling","source":{"source":"github","repo":"o/r"},"version":"1.0.0"}]}\n' >"$repo/.claude-plugin/marketplace.json"
	git -C "$repo" commit -q -am objsource
	run_cmd "$SCAN_DIR/version-drift" "$repo"
	assert_rc 2 "t_mkt_version_drift_cases object-source-exits-2"
	rm -rf "$repo"
}

t_mkt_version_drift_help() {
	run_cmd "$SCAN_DIR/version-drift" --help
	assert_rc 0 "version-drift --help exits 0"
	assert_contains "$OUT" "Usage: version-drift <repo>" "version-drift --help prints its usage"
}

t_mkt_version_drift_this_checkout() {
	run_cmd "$SCAN_DIR/version-drift" "$REPO"
	assert_rc 0 "t_mkt_version_drift_this_checkout rc ($OUT)"
}

t_mkt_repo_defaults_to_this_checkout() {
	local top
	top=$(git -C "$HERE" rev-parse --show-toplevel)
	if [ -z "${FLOW_REPO:-}" ]; then
		assert_eq "$REPO" "$top" "t_mkt_repo_defaults_to_this_checkout REPO"
	else
		assert_eq "$REPO" "$FLOW_REPO" "t_mkt_repo_defaults_to_this_checkout FLOW_REPO override"
	fi
}
