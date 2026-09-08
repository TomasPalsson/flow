#!/usr/bin/env bash
# spec-gate.sh — PreToolUse/Edit|Write|NotebookEdit hook. SPEC C20.
#
# Deterministic "no build without an approved plan". Activated per-project via
# .claude/flow.config.json "requireSpec" (default "flow-branches": only on
# branches named flow/*), or CC_NO_SPEC_GATE=1 to disable for one session.
# Denies editing a source file when no approved, lint-clean plan exists.
#
# Everything this hook knows about plans and source files lives in
# lib/specgate.sh, which the Stop half of the same gate (stop-gate.sh) sources
# too — the two used to carry 110 duplicated lines between them.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
# shellcheck source=lib/specgate.sh
. "$HERE/lib/specgate.sh"
hook_skip_if_off # `flow off` wrote .claude/flow.off here: no judging hooks

dir=$(hook_project_dir)
git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || hook_ok

_sg_require_spec_active "$dir" || hook_ok

_file=$(hook_field '.tool_input.file_path')
[ -z "$_file" ] && hook_ok
# B8: a linked worktree's .git is a FILE, and every pruned/ignored path is the
# project's business, not the gate's.
hook_excluded_path "$_file" && hook_ok
hook_git_managed "$_file" || hook_ok

_rel=$_file
case "$_rel" in
"$dir"/*) _rel=${_rel#"$dir"/} ;;
esac

_sg20_is_source "$_rel" || hook_ok

_plan=$(_sg_plan_path "$dir")
_sg_approved_plan_ok "$_plan" && hook_ok

_plan_rel=$_plan
case "$_plan_rel" in
"$dir"/*) _plan_rel=${_plan_rel#"$dir"/} ;;
esac
_branch_disp=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
hook_deny "Spec gate: $_rel is a source file, this branch ($_branch_disp) requires an approved plan, and $_plan_rel is missing, has no 'Approved: <date>' line, or does not pass plan-lint. Run /flow to spec and plan the work, get the plan approved, then build. (escape: set requireSpec:false in .claude/flow.config.json, CC_NO_SPEC_GATE=1 for this session, or ask the user to approve the plan.)"
