#!/usr/bin/env bash
# agents/ and commands/ live in the dotfiles (user-level), not in the plugin; fall back there.
[ -d "$SCAN_DIR/../agents" ] || AGENTS_DIR="${AGENTS_DIR:-$HOME/.dotfiles/claude/.claude/agents}"
[ -d "$SCAN_DIR/../commands" ] || COMMANDS_DIR="${COMMANDS_DIR:-$HOME/.dotfiles/claude/.claude/commands}"
# test_commands.sh — unit W2 (commands) tests for claude/.claude/commands/.
# Sourced by run.sh; HERE (this dir) and SCAN_DIR (its parent, "scripts/")
# are already set. Tests prefixed t_commands_.

CMD_DIR="${COMMANDS_DIR:-$SCAN_DIR/../commands}"
NEW_CMDS="btw wrap ship memory-audit"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

# _commands_second_dash_line <file> → line number of the closing "---", or 0
_commands_second_dash_line() {
  awk '/^---$/ { n++; if (n == 2) { print NR; exit } }' "$1"
}

# _commands_body_line_count <file> → lines strictly after the closing "---"
_commands_body_line_count() {
  awk '
    /^---$/ { n++; if (n == 2) { start = 1; next } }
    start { count++ }
    END { print count + 0 }
  ' "$1"
}

# ---------------------------------------------------------------------------
# frontmatter: first line ---, closing ---, name: and description: present
# ---------------------------------------------------------------------------

t_commands_frontmatter_present() {
  local name f first close block
  for name in $NEW_CMDS; do
    f="$CMD_DIR/$name.md"
    first=$(head -1 "$f" 2>/dev/null)
    assert_eq "$first" "---" "$name.md starts with ---"
    close=$(_commands_second_dash_line "$f")
    if [ -z "$close" ] || [ "$close" -le 1 ]; then
      _fail "$name.md has a closing ---" "no second --- line found"
      continue
    fi
    _pass "$name.md has a closing ---"
    block=$(sed -n "1,${close}p" "$f")
    case "$block" in
    *$'\n'name:*) _pass "$name.md frontmatter has name:" ;;
    *) _fail "$name.md frontmatter has name:" "not found in frontmatter block" ;;
    esac
    case "$block" in
    *$'\n'description:*) _pass "$name.md frontmatter has description:" ;;
    *) _fail "$name.md frontmatter has description:" "not found in frontmatter block" ;;
    esac
  done
}

t_commands_disable_model_invocation() {
  local name f close block
  for name in $NEW_CMDS; do
    f="$CMD_DIR/$name.md"
    close=$(_commands_second_dash_line "$f")
    block=$(sed -n "1,${close}p" "$f")
    case "$block" in
    *$'\n'disable-model-invocation:\ true*) _pass "$name.md sets disable-model-invocation: true" ;;
    *) _fail "$name.md sets disable-model-invocation: true" "not found" ;;
    esac
  done
}

t_commands_btw_argument_hint() {
  assert_contains "$(cat "$CMD_DIR/btw.md")" "argument-hint: [the note]" "btw.md has argument-hint: [the note]"
}

t_commands_wrap_allowed_tools_exact() {
  assert_contains "$(cat "$CMD_DIR/wrap.md")" \
    "allowed-tools: Bash(git status *) Bash(git log *) Bash(git diff *) Read Write Edit" \
    "wrap.md allowed-tools matches C14 exactly"
}

t_commands_ship_allowed_tools_exact() {
  assert_contains "$(cat "$CMD_DIR/ship.md")" \
    "allowed-tools: Bash(git add *) Bash(git commit *) Bash(git status *) Bash(git diff *) Bash(git log *) Bash(git push *) Bash(gh pr create *) Bash(gh pr view *)" \
    "ship.md allowed-tools matches C14 exactly"
}

t_commands_arguments_expands_in_btw() {
  assert_contains "$(cat "$CMD_DIR/btw.md")" '$ARGUMENTS' "btw.md body expands \$ARGUMENTS"
}

# ---------------------------------------------------------------------------
# line caps (body lines strictly after the closing frontmatter ---)
# ---------------------------------------------------------------------------

t_commands_line_caps() {
  local name f cap n
  for name in $NEW_CMDS; do
    f="$CMD_DIR/$name.md"
    case "$name" in
    btw) cap=25 ;;
    wrap) cap=30 ;;
    ship) cap=35 ;;
    memory-audit) cap=30 ;;
    esac
    n=$(_commands_body_line_count "$f")
    if [ "$n" -le "$cap" ]; then
      _pass "$name.md body is <= $cap lines (got $n)"
    else
      _fail "$name.md body is <= $cap lines (got $n)" "over the C14 cap"
    fi
  done
}

# ---------------------------------------------------------------------------
# deletions: the 13 old commands/*.md files and commands/agents/ are gone
# ---------------------------------------------------------------------------

t_commands_old_files_deleted() {
  local old
  for old in cleanup cli comment document document-notion fix improve \
    improve-pr improve-workflow orchestrate readme sst test; do
    assert_file_missing "$CMD_DIR/$old.md" "old command $old.md is deleted"
  done
}

t_commands_agents_dir_deleted() {
  assert_file_missing "$CMD_DIR/agents" "commands/agents/ directory is deleted"
}

# ---------------------------------------------------------------------------
# no new command name collides with an existing skills/ directory
# ---------------------------------------------------------------------------

t_commands_no_skill_name_collision() {
  local skills_dir entry base hit
  skills_dir="$SCAN_DIR/../skills"
  hit=""
  for entry in "$skills_dir"/*; do
    [ -d "$entry" ] || continue
    base=${entry##*/}
    case "$base" in
    btw | wrap | ship | memory-audit) hit="$hit $base" ;;
    esac
  done
  assert_eq "$hit" "" "no new command name collides with an existing skills/ directory"
}

# ---------------------------------------------------------------------------
# skills-lint reports no MISSING under commands/, resolved as if deployed.
#
# ~/.claude/CLAUDE.md and ~/.claude/harness-templates/ are not symlinked on
# this box yet (deployment happens once at the very end, by the
# orchestrator; see repo facts). skills-lint's "~/.claude/..." resolution
# only ever looks under $HOME, with no repo-relative fallback, so running it
# against the real $HOME here would report both as MISSING regardless of
# whether btw.md / wrap.md are correct - a deployment-timing false red, not
# a defect in this unit's files. To get a real signal, fake $HOME with the
# same symlinks the orchestrator will create and run the real skills-lint
# binary against it (never touches the real ~/.claude).
# ---------------------------------------------------------------------------

t_commands_skills_lint_no_missing() {
  local fake_home claude_root
  fake_home=$(tmp_dir)
  claude_root=$(cd "$SCAN_DIR/.." && pwd -P)
  mkdir -p "$fake_home/.claude"
  ln -s "$claude_root/CLAUDE.md" "$fake_home/.claude/CLAUDE.md"
  ln -s "$claude_root/harness-templates" "$fake_home/.claude/harness-templates"
  run_cmd bash -c 'export HOME="$1"; shift; exec "$@"' \
    _ "$fake_home" bash "$SCAN_DIR/skills-lint" "$CMD_DIR"
  assert_not_contains "$OUT" "MISSING" "skills-lint reports no MISSING under commands/ (deployed HOME)"
}

t_commands_help_missing_files() {
  local name
  for name in $NEW_CMDS; do
    assert_file_exists "$CMD_DIR/$name.md" "$name.md exists"
  done
}
