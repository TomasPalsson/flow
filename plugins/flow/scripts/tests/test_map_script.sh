#!/usr/bin/env bash
# test_map_script.sh — unit W6 (codebase map) tests for the scripts/
# codebase-map generator (C15). Sourced by run.sh, which defines HERE
# (this dir) and SCAN_DIR (its parent, "scripts/"). Every t_mapscript_*
# function below is discovered and run.
#
# All functions run in the same shell as run.sh (no subshell), so any
# test that changes directory restores it before returning, matching the
# convention in test_flow.sh.
set -u

MAP_SCRIPT="$SCAN_DIR/codebase-map"

# _mapscript_seed_repo <dir> — a small repo with a package.json (main,
# bin, scripts.dev, scripts.start), a README, and a few files under
# distinct directories, including ones that should land in "Seams".
_mapscript_seed_repo() {
  local d="$1"
  mkdir -p "$d/src/routes" "$d/src/models" "$d/lib"
  cat >"$d/package.json" <<'JSON'
{
  "name": "fixture",
  "main": "src/index.js",
  "bin": "bin/cli.js",
  "scripts": { "dev": "node dev.js", "start": "node src/index.js" }
}
JSON
  printf 'console.log(1)\n' >"$d/src/index.js"
  printf 'exports.route = 1\n' >"$d/src/routes/user.route.js"
  printf 'exports.schema = 1\n' >"$d/src/models/user.schema.js"
  printf 'module.exports = {}\n' >"$d/lib/util.js"
  printf '# Fixture Project\n' >"$d/README.md"
  (
    cd "$d" || exit 1
    git add -A
    git commit -q -m "seed"
  ) >/dev/null 2>&1
}

t_mapscript_help() {
  run_cmd "$MAP_SCRIPT" --help
  assert_rc 0 "t_mapscript_help rc"
  assert_contains "$OUT" "Usage: codebase-map" "t_mapscript_help usage-text"
}

t_mapscript_not_git_repo_exit1() {
  local prevdir d
  prevdir=$(pwd)
  d=$(tmp_dir)
  cd "$d" || {
    _fail "t_mapscript_not_git_repo_exit1 setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  assert_rc 1 "t_mapscript_not_git_repo_exit1 rc1-outside-git-repo"
  cd "$prevdir" || true
}

t_mapscript_writes_map_with_stamp_and_sections() {
  local prevdir repo content
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_writes_map_with_stamp_and_sections setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  assert_rc 0 "t_mapscript_writes_map_with_stamp_and_sections rc"
  assert_contains "$OUT" "written .claude/codebase-map.md" "t_mapscript_writes_map_with_stamp_and_sections stdout-written"
  assert_file_exists ".claude/codebase-map.md" "t_mapscript_writes_map_with_stamp_and_sections file-exists"
  content=$(cat .claude/codebase-map.md)
  assert_contains "$content" "<!-- codebase-map: head=" "t_mapscript_writes_map_with_stamp_and_sections stamp-present"
  assert_contains "$content" "dirty=" "t_mapscript_writes_map_with_stamp_and_sections stamp-has-dirty"
  assert_contains "$content" "generated=" "t_mapscript_writes_map_with_stamp_and_sections stamp-has-generated"
  assert_contains "$content" "## Entry points" "t_mapscript_writes_map_with_stamp_and_sections entry-points-heading"
  assert_contains "$content" "## Layout" "t_mapscript_writes_map_with_stamp_and_sections layout-heading"
  assert_contains "$content" "## Seams" "t_mapscript_writes_map_with_stamp_and_sections seams-heading"
  assert_contains "$content" "## Recipes" "t_mapscript_writes_map_with_stamp_and_sections recipes-heading"
  cd "$prevdir" || true
}

t_mapscript_stamp_is_line_one() {
  local prevdir repo first_line
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_stamp_is_line_one setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  first_line=$(head -1 .claude/codebase-map.md)
  case "$first_line" in
  '<!-- codebase-map: head='*' dirty='*' generated='*' -->')
    _pass "t_mapscript_stamp_is_line_one exact-stamp-grammar"
    ;;
  *)
    _fail "t_mapscript_stamp_is_line_one exact-stamp-grammar" "got: $first_line"
    ;;
  esac
  cd "$prevdir" || true
}

t_mapscript_default_within_150_lines() {
  local prevdir repo total
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_default_within_150_lines setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  total=$(wc -l <.claude/codebase-map.md | tr -d ' ')
  if [ "$total" -le 150 ]; then
    _pass "t_mapscript_default_within_150_lines total-le-150"
  else
    _fail "t_mapscript_default_within_150_lines total-le-150" "total=$total"
  fi
  cd "$prevdir" || true
}

t_mapscript_second_run_prints_unchanged() {
  local prevdir repo
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_second_run_prints_unchanged setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  run_cmd "$MAP_SCRIPT"
  assert_rc 0 "t_mapscript_second_run_prints_unchanged rc"
  assert_eq "$OUT" "unchanged" "t_mapscript_second_run_prints_unchanged stdout-unchanged"
  cd "$prevdir" || true
}

t_mapscript_edit_changes_dirty_hash_triggers_rewrite() {
  local prevdir repo stamp1 stamp2
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_edit_changes_dirty_hash_triggers_rewrite setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  stamp1=$(head -1 .claude/codebase-map.md)
  printf 'more code\n' >>src/index.js
  run_cmd "$MAP_SCRIPT"
  assert_rc 0 "t_mapscript_edit_changes_dirty_hash_triggers_rewrite rc"
  assert_contains "$OUT" "written .claude/codebase-map.md" "t_mapscript_edit_changes_dirty_hash_triggers_rewrite stdout-written-again"
  stamp2=$(head -1 .claude/codebase-map.md)
  if [ "$stamp1" != "$stamp2" ]; then
    _pass "t_mapscript_edit_changes_dirty_hash_triggers_rewrite stamp-changed"
  else
    _fail "t_mapscript_edit_changes_dirty_hash_triggers_rewrite stamp-changed" "stamp unchanged: $stamp1"
  fi
  cd "$prevdir" || true
}

t_mapscript_force_rewrites_even_when_unchanged() {
  local prevdir repo before after
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_force_rewrites_even_when_unchanged setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  before=$(head -1 .claude/codebase-map.md)
  run_cmd "$MAP_SCRIPT" --force
  assert_rc 0 "t_mapscript_force_rewrites_even_when_unchanged rc"
  assert_contains "$OUT" "written .claude/codebase-map.md" "t_mapscript_force_rewrites_even_when_unchanged stdout-written-not-unchanged"
  after=$(head -1 .claude/codebase-map.md)
  assert_eq "$after" "$before" "t_mapscript_force_rewrites_even_when_unchanged same-stamp-content-unchanged-repo"
  cd "$prevdir" || true
}

t_mapscript_max_lines_20_truncates_with_marker() {
  local prevdir repo total last
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_max_lines_20_truncates_with_marker setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT" --max-lines 20
  assert_rc 0 "t_mapscript_max_lines_20_truncates_with_marker rc"
  total=$(wc -l <.claude/codebase-map.md | tr -d ' ')
  assert_eq "$total" "20" "t_mapscript_max_lines_20_truncates_with_marker exactly-max-lines"
  last=$(tail -1 .claude/codebase-map.md)
  assert_eq "$last" "<!-- truncated -->" "t_mapscript_max_lines_20_truncates_with_marker truncation-marker"
  cd "$prevdir" || true
}

t_mapscript_entry_points_from_package_json() {
  local prevdir repo content
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_entry_points_from_package_json setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  content=$(cat .claude/codebase-map.md)
  assert_contains "$content" "package.json main: src/index.js" "t_mapscript_entry_points_from_package_json main"
  assert_contains "$content" "package.json bin: bin/cli.js" "t_mapscript_entry_points_from_package_json bin"
  assert_contains "$content" "package.json scripts.dev: node dev.js" "t_mapscript_entry_points_from_package_json scripts-dev"
  assert_contains "$content" "package.json scripts.start: node src/index.js" "t_mapscript_entry_points_from_package_json scripts-start"
  assert_contains "$content" "README.md: # Fixture Project" "t_mapscript_entry_points_from_package_json readme-heading"
  cd "$prevdir" || true
}

t_mapscript_layout_section_lists_directories() {
  local prevdir repo content
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_layout_section_lists_directories setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  content=$(cat .claude/codebase-map.md)
  assert_contains "$content" "src/routes/ (1 files)" "t_mapscript_layout_section_lists_directories routes-dir"
  assert_contains "$content" "src/models/ (1 files)" "t_mapscript_layout_section_lists_directories models-dir"
  cd "$prevdir" || true
}

t_mapscript_seams_section_matches_pattern_files() {
  local prevdir repo content
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_seams_section_matches_pattern_files setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  content=$(cat .claude/codebase-map.md)
  assert_contains "$content" "src/routes/user.route.js" "t_mapscript_seams_section_matches_pattern_files route-file"
  assert_contains "$content" "src/models/user.schema.js" "t_mapscript_seams_section_matches_pattern_files schema-file"
  assert_not_contains "$content" "lib/util.js" "t_mapscript_seams_section_matches_pattern_files excludes-non-seam-file"
  cd "$prevdir" || true
}

t_mapscript_recipes_section_has_three_fixed_lines() {
  local prevdir repo content
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_recipes_section_has_three_fixed_lines setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT"
  content=$(cat .claude/codebase-map.md)
  assert_contains "$content" "Find a route:" "t_mapscript_recipes_section_has_three_fixed_lines route-recipe"
  assert_contains "$content" "Find a schema:" "t_mapscript_recipes_section_has_three_fixed_lines schema-recipe"
  assert_contains "$content" "Find where an env var is read:" "t_mapscript_recipes_section_has_three_fixed_lines env-recipe"
  cd "$prevdir" || true
}

t_mapscript_out_flag_custom_path() {
  local prevdir repo outpath
  prevdir=$(pwd)
  repo=$(tmp_repo)
  _mapscript_seed_repo "$repo"
  cd "$repo" || {
    _fail "t_mapscript_out_flag_custom_path setup cd"
    cd "$prevdir" || true
    return
  }
  outpath="notes/map.md"
  run_cmd "$MAP_SCRIPT" --out "$outpath"
  assert_rc 0 "t_mapscript_out_flag_custom_path rc"
  assert_contains "$OUT" "written $outpath" "t_mapscript_out_flag_custom_path stdout-names-custom-path"
  assert_file_exists "$outpath" "t_mapscript_out_flag_custom_path file-exists-at-custom-path"
  cd "$prevdir" || true
}

t_mapscript_unknown_option_exit1() {
  local prevdir repo
  prevdir=$(pwd)
  repo=$(tmp_repo)
  cd "$repo" || {
    _fail "t_mapscript_unknown_option_exit1 setup cd"
    cd "$prevdir" || true
    return
  }
  run_cmd "$MAP_SCRIPT" --bogus-flag
  assert_rc 1 "t_mapscript_unknown_option_exit1 rc"
  cd "$prevdir" || true
}

t_mapscript_is_well_formed() {
  if [ -x "$MAP_SCRIPT" ]; then
    _pass "t_mapscript_is_well_formed executable"
  else
    _fail "t_mapscript_is_well_formed executable" "not executable: $MAP_SCRIPT"
  fi
  if head -1 "$MAP_SCRIPT" | grep -q '^#!/usr/bin/env bash$'; then
    _pass "t_mapscript_is_well_formed portable-shebang"
  else
    _fail "t_mapscript_is_well_formed portable-shebang"
  fi
  if grep -q '^set -u' "$MAP_SCRIPT"; then
    _pass "t_mapscript_is_well_formed sets-u"
  else
    _fail "t_mapscript_is_well_formed sets-u"
  fi
  run_cmd bash -n "$MAP_SCRIPT"
  assert_rc 0 "t_mapscript_is_well_formed bash-n"
}
