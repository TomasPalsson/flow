#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_explorer.sh — unit W5 (explorer agent) tests for
# claude/.claude/agents/explorer.md. Sourced by run.sh; HERE (this dir) and
# SCAN_DIR (its parent, "scripts/") are already set. t_explorer_* prefix.
set -u

AGENTS_DIR=$(cd "${AGENTS_DIR:-$SCAN_DIR/../agents}" && pwd -P)
EXPLORER_MD="$AGENTS_DIR/explorer.md"

# _explorer_frontmatter <file> — prints the lines strictly between the first
# and second "---" delimiters (the YAML frontmatter body).
_explorer_frontmatter() {
  awk '/^---$/{c++; next} c==1{print} c==2{exit}' "$1"
}

# _explorer_body_lines <file> — counts lines after the closing "---" to EOF.
_explorer_body_lines() {
  local f total end2
  f=$1
  total=$(wc -l <"$f" | tr -d ' ')
  end2=$(awk '/^---$/{c++; if(c==2){print NR; exit}}' "$f")
  echo $((total - end2))
}

t_explorer_frontmatter_starts_and_closes() {
  local first second
  first=$(sed -n '1p' "$EXPLORER_MD")
  assert_eq "$first" "---" "explorer.md: first line is ---"
  second=$(awk '/^---$/{c++; if(c==2){print "yes"; exit}}' "$EXPLORER_MD")
  assert_eq "$second" "yes" "explorer.md: frontmatter closes with a second ---"
}

t_explorer_frontmatter_has_required_fields_exact() {
  # Exact-line equality (assert_eq), not substring containment
  # (assert_contains): "tools: Read, Grep, Glob, Bash" is a substring of
  # "tools: Read, Grep, Glob, Bash, Task", so a substring check here would
  # still pass after an unauthorized tool (e.g. Task) was appended to the
  # frontmatter. Extract each field's own line and compare it verbatim.
  local fm name_line model_line memory_line color_line tools_line
  fm=$(_explorer_frontmatter "$EXPLORER_MD")
  name_line=$(printf '%s\n' "$fm" | grep '^name:')
  model_line=$(printf '%s\n' "$fm" | grep '^model:')
  memory_line=$(printf '%s\n' "$fm" | grep '^memory:')
  color_line=$(printf '%s\n' "$fm" | grep '^color:')
  tools_line=$(printf '%s\n' "$fm" | grep '^tools:')
  assert_eq "$name_line" "name: explorer" "explorer.md: name line is exact"
  assert_eq "$model_line" "model: haiku" "explorer.md: model line is exact"
  assert_eq "$memory_line" "memory: project" "explorer.md: memory line is exact"
  assert_eq "$color_line" "color: cyan" "explorer.md: color line is exact"
  assert_eq "$tools_line" "tools: Read, Grep, Glob, Bash" "explorer.md: tools line is exact"
}

t_explorer_frontmatter_description_exact() {
  local fm desc_line desc_value expected
  fm=$(_explorer_frontmatter "$EXPLORER_MD")
  desc_line=$(printf '%s\n' "$fm" | grep '^description:')
  desc_value=${desc_line#description: }
  expected='Read-only codebase reader for flow step 1 and any "where does X live" question. Returns locations with path:line receipts it opened this run, never a plan and never an edit. Spawn up to three in parallel with distinct questions.'
  assert_eq "$desc_value" "$expected" "explorer.md: description is byte-exact (228 chars, includes the parallel fan-out clause)"
}

t_explorer_tools_has_no_edit_or_write() {
  local fm tools_line tools_value token bad
  fm=$(_explorer_frontmatter "$EXPLORER_MD")
  tools_line=$(printf '%s\n' "$fm" | grep '^tools:')
  assert_not_contains "$tools_line" "Edit" "explorer.md: tools line has no Edit"
  assert_not_contains "$tools_line" "Write" "explorer.md: tools line has no Write"

  # Token-level allowlist check: ruling out the literal substrings "Edit"
  # and "Write" alone would miss any OTHER unauthorized tool token (e.g.
  # "Task", which would let this read-only explorer spawn subagents).
  # Split the tools line on commas and require every token to be exactly
  # one of the four authorized tools.
  tools_value=${tools_line#tools: }
  bad=""
  IFS=','
  for token in $tools_value; do
    token=$(printf '%s' "$token" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    case "$token" in
    Read | Grep | Glob | Bash) ;;
    *) bad="$bad[$token]" ;;
    esac
  done
  unset IFS
  assert_eq "$bad" "" "explorer.md: tools line contains only Read, Grep, Glob, Bash (no unauthorized tokens)"
}

t_explorer_body_line_cap() {
  local n
  n=$(_explorer_body_lines "$EXPLORER_MD")
  if [ "$n" -le 45 ]; then
    _pass "explorer.md: body <= 45 lines ($n)"
  else
    _fail "explorer.md: body <= 45 lines" "got $n"
  fi
}

t_explorer_verbatim_before_exploring() {
  local content
  content=$(cat "$EXPLORER_MD")
  assert_contains "$content" "BEFORE exploring: read MEMORY.md. Treat every entry as a HINT, never as a fact. Any remembered path must be re-verified with one Glob or Read this run before you report it. If it no longer resolves, delete the line and report the new location." "explorer.md: verbatim BEFORE exploring requirement"
}

t_explorer_verbatim_return_shape() {
  local content
  content=$(cat "$EXPLORER_MD")
  assert_contains "$content" "entry_points: path:line — one clause" "explorer.md: return shape entry_points line"
  assert_contains "$content" "seams: path:line — the boundary this file owns" "explorer.md: return shape seams line"
  assert_contains "$content" "reusable: path:line — signature verbatim plus 3-6 lines of surrounding source" "explorer.md: return shape reusable line"
  assert_contains "$content" "recipe: the grep/glob that relocates each of the above if it moves" "explorer.md: return shape recipe line"
  assert_contains "$content" "dead_ends: paths that look relevant and are not, with why" "explorer.md: return shape dead_ends line"
  assert_contains "$content" "≤ 40 lines. Every line carries a path:line receipt you opened this run. No receipt, no line." "explorer.md: return shape cap sentence"
}

t_explorer_verbatim_after_exploring() {
  local content
  content=$(cat "$EXPLORER_MD")
  assert_contains "$content" "AFTER exploring, write back ONLY these four kinds of line, each dated YYYY-MM-DD: entry point | seam | search recipe | dead end. Never write file contents, line numbers, signatures, dependency graphs, or anything one Grep answers cheaply. Keep MEMORY.md under 200 lines; merge or drop the oldest rather than appending." "explorer.md: verbatim AFTER exploring requirement"
}

t_explorer_verbatim_no_mcp() {
  local content
  content=$(cat "$EXPLORER_MD")
  assert_contains "$content" "Never use MCP tools; Read/Grep/Glob and read-only git through Bash only (concurrent language servers on one workspace are a known failure)." "explorer.md: verbatim no-MCP requirement"
}
