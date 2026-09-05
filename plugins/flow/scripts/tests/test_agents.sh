#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_agents.sh — unit W1 (agents) tests for claude/.claude/agents/{claim-check,triage}.md
# and the minimal fix/SKILL.md edit. Sourced by run.sh; HERE (this dir) and
# SCAN_DIR (its parent, "scripts/") are already set. t_agents_* prefix.
#
# C16 fix: pin exact frontmatter values with assert_eq on the extracted field
# (tools, model, maxTurns, effort, color) instead of substring containment,
# and assert the body contains each required section in order. Mutation-guard
# tests below prove the exact-value/order checks would actually catch a
# regression (extra tool, maxTurns drift, gutted body) — they exercise the
# extraction helpers against a MUTATED COPY under tmp_dir, never the real
# agent files.
set -u

AGENTS_DIR=$(cd "${AGENTS_DIR:-$SCAN_DIR/../agents}" && pwd -P)
REPO_ROOT=$(cd "$HERE/../../../.." && pwd -P)
FIX_SKILL="$SCAN_DIR/../skills/fix/SKILL.md"

# _agents_frontmatter <file> — prints the lines strictly between the first
# and second "---" delimiters (the YAML frontmatter body).
_agents_frontmatter() {
	awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$1"
}

# _agents_body_lines <file> — counts lines after the closing "---" to EOF.
_agents_body_lines() {
	local f total end2
	f=$1
	total=$(wc -l <"$f" | tr -d ' ')
	end2=$(awk '/^---$/{c++; if(c==2){print NR; exit}}' "$f")
	echo $((total - end2))
}

# _agents_body_text <file> — prints every line after the closing "---".
_agents_body_text() {
	awk '/^---$/{c++; next} c==2{print}' "$1"
}

# _agents_body_start_line <file> — line number of the closing "---".
_agents_body_start_line() {
	awk '/^---$/{c++; if(c==2){print NR; exit}}' "$1"
}

# _agents_field <file> <key> — exact value of the single-line frontmatter
# field "<key>: <value>" (the part after "key: "), "" if the field is absent.
# Requires the line to start with "<key>:" so "model" never matches a field
# whose name merely contains "model" as a substring.
_agents_field() {
	local file=$1 key=$2
	awk -v key="$key" '
    /^---$/ { c++; next }
    c == 1 {
      n = length(key) + 1
      if (substr($0, 1, n) == key ":") {
        print substr($0, n + 2)
        exit
      }
    }
    c == 2 { exit }
  ' "$file"
}

# _agents_body_line_no <file> <fixed-string> — line number (whole file, 1-based)
# of the first BODY line (after the closing "---") that contains the given
# fixed string, "" if not found. Uses grep -F (no regex escaping needed for
# headings like "## Anti-overreach" or backtick-laden text).
_agents_body_line_no() {
	local file=$1 pattern=$2 start
	start=$(_agents_body_start_line "$file")
	grep -nF -- "$pattern" "$file" | awk -F: -v s="$start" '$1 > s { print $1; exit }'
}

# _agents_assert_body_order <file> <name> <pattern1> [pattern2 ...] — asserts
# every pattern is present in the body AND appears in strictly increasing
# line order (i.e. the sections/lines occur in the given order).
_agents_assert_body_order() {
	local file=$1 name=$2
	shift 2
	local prev=0 pat ln all_ok=1
	for pat in "$@"; do
		ln=$(_agents_body_line_no "$file" "$pat")
		if [ -z "$ln" ]; then
			_fail "$name: contains '$pat'" "not found in body"
			all_ok=0
			continue
		fi
		if [ "$ln" -gt "$prev" ]; then
			prev=$ln
		else
			_fail "$name: '$pat' in order" "found at line $ln, not after previous section (line $prev)"
			all_ok=0
		fi
	done
	[ "$all_ok" -eq 1 ] && _pass "$name: required sections present in order"
}

# ---------------------------------------------------------------------------
# claim-check.md
# ---------------------------------------------------------------------------

t_agents_claim_check_frontmatter_starts_and_closes() {
	local first second
	first=$(sed -n '1p' "$AGENTS_DIR/claim-check.md")
	assert_eq "$first" "---" "claim-check.md: first line is ---"
	second=$(awk '/^---$/{c++; if(c==2){print "yes"; exit}}' "$AGENTS_DIR/claim-check.md")
	assert_eq "$second" "yes" "claim-check.md: frontmatter closes with a second ---"
}

t_agents_claim_check_frontmatter_has_required_fields() {
	local fm
	fm=$(_agents_frontmatter "$AGENTS_DIR/claim-check.md")
	assert_contains "$fm" "name:" "claim-check.md: frontmatter has name:"
	assert_contains "$fm" "description:" "claim-check.md: frontmatter has description:"
	assert_contains "$fm" "tools:" "claim-check.md: frontmatter has tools:"
	assert_contains "$fm" "model:" "claim-check.md: frontmatter has model:"
}

t_agents_claim_check_body_line_cap() {
	local n
	n=$(_agents_body_lines "$AGENTS_DIR/claim-check.md")
	if [ "$n" -le 60 ]; then
		_pass "claim-check.md: body <= 60 lines ($n)"
	else
		_fail "claim-check.md: body <= 60 lines" "got $n"
	fi
}

# C16: exact field extraction + assert_eq, per C14 W1's frozen values.
t_agents_claim_check_frontmatter_exact_values() {
	local f="$AGENTS_DIR/claim-check.md"
	assert_eq "$(_agents_field "$f" "name")" "claim-check" "claim-check.md: name == claim-check"
	assert_eq "$(_agents_field "$f" "tools")" "Read, Grep, Glob, Bash" "claim-check.md: tools == Read, Grep, Glob, Bash"
	assert_eq "$(_agents_field "$f" "model")" "sonnet" "claim-check.md: model == sonnet"
	assert_eq "$(_agents_field "$f" "maxTurns")" "25" "claim-check.md: maxTurns == 25"
	assert_eq "$(_agents_field "$f" "color")" "red" "claim-check.md: color == red"
}

# C16: body sections present AND in the required order — Protocol, then
# Anti-overreach, then Output format, then the .claude/claim-check.md
# write-back line.
t_agents_claim_check_body_sections_in_order() {
	_agents_assert_body_order "$AGENTS_DIR/claim-check.md" "claim-check.md" \
		"## Protocol" "## Anti-overreach" "## Output format" \
		"Write these findings to \`.claude/claim-check.md\`"
}

t_agents_claim_check_body_has_required_content() {
	local body
	body=$(_agents_body_text "$AGENTS_DIR/claim-check.md")
	assert_contains "$body" "List every claim" "claim-check.md: protocol lists claims first"
	assert_contains "$body" "adversary" "claim-check.md: body says it complements adversary"
}

# ---------------------------------------------------------------------------
# triage.md
# ---------------------------------------------------------------------------

t_agents_triage_frontmatter_starts_and_closes() {
	local first second
	first=$(sed -n '1p' "$AGENTS_DIR/triage.md")
	assert_eq "$first" "---" "triage.md: first line is ---"
	second=$(awk '/^---$/{c++; if(c==2){print "yes"; exit}}' "$AGENTS_DIR/triage.md")
	assert_eq "$second" "yes" "triage.md: frontmatter closes with a second ---"
}

t_agents_triage_frontmatter_has_required_fields() {
	local fm
	fm=$(_agents_frontmatter "$AGENTS_DIR/triage.md")
	assert_contains "$fm" "name:" "triage.md: frontmatter has name:"
	assert_contains "$fm" "description:" "triage.md: frontmatter has description:"
	assert_contains "$fm" "tools:" "triage.md: frontmatter has tools:"
	assert_contains "$fm" "model:" "triage.md: frontmatter has model:"
}

t_agents_triage_body_line_cap() {
	local n
	n=$(_agents_body_lines "$AGENTS_DIR/triage.md")
	if [ "$n" -le 50 ]; then
		_pass "triage.md: body <= 50 lines ($n)"
	else
		_fail "triage.md: body <= 50 lines" "got $n"
	fi
}

# C16: exact field extraction + assert_eq, per C14 W1's frozen values.
t_agents_triage_frontmatter_exact_values() {
	local f="$AGENTS_DIR/triage.md"
	assert_eq "$(_agents_field "$f" "name")" "triage" "triage.md: name == triage"
	assert_eq "$(_agents_field "$f" "tools")" "Read, Grep, Glob, Bash" "triage.md: tools == Read, Grep, Glob, Bash"
	assert_eq "$(_agents_field "$f" "model")" "sonnet" "triage.md: model == sonnet"
	assert_eq "$(_agents_field "$f" "effort")" "medium" "triage.md: effort == medium"
	assert_eq "$(_agents_field "$f" "maxTurns")" "30" "triage.md: maxTurns == 30"
	assert_eq "$(_agents_field "$f" "color")" "yellow" "triage.md: color == yellow"
}

# C16: body sections present AND in the required order — Dispatch contract,
# then Protocol, then Output format.
t_agents_triage_body_sections_in_order() {
	_agents_assert_body_order "$AGENTS_DIR/triage.md" "triage.md" \
		"## Dispatch contract" "## Protocol" "## Output format"
}

t_agents_triage_body_has_required_content() {
	local body
	body=$(_agents_body_text "$AGENTS_DIR/triage.md")
	assert_contains "$body" "caller pastes the actual error text and what changed recently" "triage.md: dispatch contract wording present"
	assert_contains "$body" "Never edit a file" "triage.md: body states it never edits"
}

# ---------------------------------------------------------------------------
# deletions
# ---------------------------------------------------------------------------

t_agents_deleted_files_absent() {
	local name
	for name in cleanup cli comment document orchestrate readme sst test; do
		assert_file_missing "$AGENTS_DIR/$name.md" "agents/$name.md is deleted"
	done
}

# ---------------------------------------------------------------------------
# fix/SKILL.md edit
# ---------------------------------------------------------------------------

t_agents_fix_skill_mentions_triage() {
	local content
	content=$(cat "$FIX_SKILL")
	assert_contains "$content" "triage" "fix/SKILL.md mentions the triage agent"
}

t_agents_fix_skill_diff_within_cap() {
	local stat_line insertions deletions total
	stat_line=$(git -C "$REPO_ROOT" diff HEAD --stat -- claude/.claude/skills/fix/SKILL.md | tail -1)
	insertions=$(printf '%s' "$stat_line" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+' || true)
	deletions=$(printf '%s' "$stat_line" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+' || true)
	[ -z "$insertions" ] && insertions=0
	[ -z "$deletions" ] && deletions=0
	total=$((insertions + deletions))
	if [ "$total" -le 6 ]; then
		_pass "fix/SKILL.md: git diff --stat <= 6 changed lines ($total)"
	else
		_fail "fix/SKILL.md: git diff --stat <= 6 changed lines" "got $total: $stat_line"
	fi
}

# ---------------------------------------------------------------------------
# mutation guards — prove the exact-value / order checks above would fail on
# a real regression. Each test mutates a COPY of the real agent file under
# tmp_dir and re-runs the extraction helpers against the copy; the real
# agents/*.md files are only ever read (cp / sed with stdout redirected to
# the copy), never written.
# ---------------------------------------------------------------------------

t_agents_mutation_tools_add_write_detected() {
	local td src f got
	td=$(tmp_dir)
	src="$AGENTS_DIR/claim-check.md"
	f="$td/claim-check.md"
	sed 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob, Bash, Write/' "$src" >"$f"
	got=$(_agents_field "$f" "tools")
	if [ "$got" != "Read, Grep, Glob, Bash" ]; then
		_pass "mutation guard: adding Write to tools would fail the C14 exact-value assertion"
	else
		_fail "mutation guard: adding Write to tools would fail the C14 exact-value assertion" "extraction returned unchanged '$got' — mutation not applied or not detected"
	fi
	rm -rf "$td"
}

t_agents_mutation_maxturns_250_detected() {
	local td src f got
	td=$(tmp_dir)
	src="$AGENTS_DIR/claim-check.md"
	f="$td/claim-check.md"
	sed 's/^maxTurns: 25$/maxTurns: 250/' "$src" >"$f"
	got=$(_agents_field "$f" "maxTurns")
	if [ "$got" != "25" ]; then
		_pass "mutation guard: maxTurns=250 would fail the C14 exact-value assertion"
	else
		_fail "mutation guard: maxTurns=250 would fail the C14 exact-value assertion" "extraction returned unchanged '$got'"
	fi
	rm -rf "$td"
}

t_agents_mutation_gutted_body_detected() {
	local td src f got
	td=$(tmp_dir)
	src="$AGENTS_DIR/claim-check.md"
	f="$td/claim-check.md"
	# Gut the body: drop everything from "## Anti-overreach" onward, exactly
	# the kind of body-gutting the order check must catch.
	awk '/^## Anti-overreach$/{exit} {print}' "$src" >"$f"
	got=$(_agents_body_line_no "$f" "## Anti-overreach")
	if [ -z "$got" ]; then
		_pass "mutation guard: gutting the body removes Anti-overreach and the order check would fail to find it"
	else
		_fail "mutation guard: gutting the body removes Anti-overreach and the order check would fail to find it" "still found at line $got"
	fi
	rm -rf "$td"
}
