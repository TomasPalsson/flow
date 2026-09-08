#!/usr/bin/env bash
# session-context.sh — SessionStart hook.
#
# Prints, in order: the "Next:" block from `flow next` (max 2 lines), repo
# state, mismatch/override notes, then PROGRESS.md with whatever budget is
# left of a hard 20-line cap (C10). Silent (exit 0, no output) when the
# project dir is not a git repo.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

dir=$(hook_project_dir)

if hook_off_here; then
	printf 'flow: hooks are OFF in this directory (.claude/flow.off, from `flow off`) — no format, size, tamper, spec, stop or git guards; `flow on` re-enables them.\n'
	hook_ok
fi

if ! git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	hook_ok
fi

# _sc_print <line> — print one line, but never more than 20 lines total
# across the whole hook (C10 hard cap). Lines past the budget are dropped
# silently; earlier sections (Next:, then repo state, then mismatch/override
# notes, then PROGRESS.md) always win the remaining budget.
_sc_line_count=0
_sc_print() {
	if [ "$_sc_line_count" -ge 20 ]; then
		return 0
	fi
	printf '%s\n' "$1"
	_sc_line_count=$((_sc_line_count + 1))
}

# --- Next: block (FIRST) -----------------------------------------------
# via the CLI at $HERE/../bin/flow when present, else print nothing (a
# missing/broken CLI never fails the session). No `timeout` binary here —
# GNU-only and banned by the portability scan; `next` only reads local git
# state and small files, so it returns fast enough that a hard guard is
# unnecessary.
_sc_next_cli=""
if [ -x "$HERE/../bin/flow" ]; then
	_sc_next_cli="$HERE/../bin/flow"
fi
if [ -n "$_sc_next_cli" ]; then
	# --peek: a session-start banner is a passive read. Without it the hook,
	# not the /flow:next turn, is what drives the consecutive-call counter.
	_sc_next_out=$(cd "$dir" 2>/dev/null && "$_sc_next_cli" next --peek 2>/dev/null || true)
	if [ -n "$_sc_next_out" ]; then
		while IFS= read -r _sc_next_line; do
			_sc_print "$_sc_next_line"
		done <<EOF
$_sc_next_out
EOF
	fi
fi

# --- Repo state (4 lines + up to 3 commits) -----------------------------
branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
[ -z "$branch" ] && branch="(unknown)"

uncommitted=$(git -C "$dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')

_sc_print "## Repo state"
_sc_print "branch: $branch"
_sc_print "uncommitted files: $uncommitted"
_sc_print "last 3 commits:"
# Read via a heredoc (not a piped `| while`) so the loop runs in the current
# shell and _sc_line_count increments persist past the loop.
commits=$(git -C "$dir" log -3 --oneline 2>/dev/null)
if [ -n "$commits" ]; then
	while IFS= read -r commit_line; do
		_sc_print "  $commit_line"
	done <<EOF
$commits
EOF
fi

# --- Mismatch / override notes (each 1 line) ----------------------------
if [ -f "$dir/REVIEW.md" ]; then
	_sc_print "note: REVIEW.md present"
fi

harness_json="$dir/.claude/flow.config.json"
if [ -f "$harness_json" ] && have jq; then
	for key in maxFileLines maxFuncLines stopGate stopGateBudgetSec sizeGuard formatOnEdit ignore; do
		default=""
		case "$key" in
		maxFileLines) default="400" ;;
		maxFuncLines) default="60" ;;
		stopGate) default="scoped" ;;
		stopGateBudgetSec) default="150" ;;
		sizeGuard) default="true" ;;
		formatOnEdit) default="true" ;;
		ignore) default="migrations/,generated/,locales/,i18n/,.generated." ;;
		esac
		present=$(jq -r --arg k "$key" 'has($k)' "$harness_json" 2>/dev/null)
		if [ "$present" = "true" ]; then
			val=$(jq -r --arg k "$key" 'if (.[$k] | type) == "array" then (.[$k] | join(",")) else (.[$k] | tostring) end' "$harness_json" 2>/dev/null)
			if [ "$val" != "$default" ]; then
				_sc_print "note: harness override: $key=$val"
			fi
		fi
	done
fi

# flow worktree / branch mismatch: agent-view sessions start in the main checkout,
# so a flow that lives in a worktree or on another branch is invisible from here.
if [ -f "$dir/.claude/flow.json" ] && have jq; then
	_fw=$(jq -r '.worktree // empty' "$dir/.claude/flow.json" 2>/dev/null)
	_fb=$(jq -r '.branch // empty' "$dir/.claude/flow.json" 2>/dev/null)
	_top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
	_cur=$(git -C "$dir" branch --show-current 2>/dev/null)
	_top_phys=""
	[ -n "$_top" ] && _top_phys=$(cd "$_top" 2>/dev/null && pwd -P) || _top_phys="$_top"
	_fw_phys=""
	if [ -n "$_fw" ]; then
		_fw_phys=$(cd "$_fw" 2>/dev/null && pwd -P) || _fw_phys="$_fw"
	fi
	if [ -n "$_fw" ] && [ "$_fw_phys" != "$_top_phys" ]; then
		_sc_print "note: flow worktree mismatch — this flow lives in $_fw (branch $_fb); this session is in $_top. Start the session there (agents $_fw) or cd before touching it."
	elif [ -n "$_fb" ] && [ "$_fb" != "$_cur" ]; then
		_sc_print "note: this checkout is on $_cur; .claude/flow.json says $_fb — run: git checkout $_fb"
	fi
fi

# --- PROGRESS.md (LAST — whatever budget of 20 remains) ------------------
# Skipped entirely when it still equals the init template (ignoring
# whitespace): a freshly-scaffolded repo has nothing to say yet.
_sc_progress_is_template() {
	local f=$1 tmpl norm_a norm_b
	tmpl="$HERE/../flow-templates/PROGRESS.md"
	[ -f "$tmpl" ] || return 1
	norm_a=$(tr -d '[:space:]' <"$f" 2>/dev/null)
	norm_b=$(tr -d '[:space:]' <"$tmpl" 2>/dev/null)
	[ -n "$norm_a" ] && [ "$norm_a" = "$norm_b" ]
}

progress_path="$dir/PROGRESS.md"
if [ -f "$progress_path" ] && ! _sc_progress_is_template "$progress_path"; then
	progress_full=$(cat "$progress_path" 2>/dev/null)
	progress_total=0
	[ -n "$progress_full" ] && progress_total=$(printf '%s\n' "$progress_full" | wc -l | tr -d ' ')
	_sc_avail=$((20 - _sc_line_count))
	if [ "$_sc_avail" -ge 1 ]; then
		_sc_print "## PROGRESS.md"
		_sc_avail=$((20 - _sc_line_count))
		if [ "$progress_total" -le "$_sc_avail" ]; then
			_sc_progress_budget=$progress_total
			_sc_progress_truncated=0
		else
			_sc_progress_budget=$((_sc_avail - 1))
			[ "$_sc_progress_budget" -lt 0 ] && _sc_progress_budget=0
			_sc_progress_truncated=1
		fi
		_sc_progress_n=0
		if [ "$progress_total" -gt 0 ]; then
			while IFS= read -r progress_line; do
				[ "$_sc_progress_n" -ge "$_sc_progress_budget" ] && break
				_sc_print "$progress_line"
				_sc_progress_n=$((_sc_progress_n + 1))
			done <<EOF
$progress_full
EOF
		fi
		if [ "$_sc_progress_truncated" -eq 1 ]; then
			_sc_progress_more=$((progress_total - _sc_progress_n))
			_sc_print "… (PROGRESS.md truncated; $_sc_progress_more more lines)"
		fi
	fi
fi

hook_ok
