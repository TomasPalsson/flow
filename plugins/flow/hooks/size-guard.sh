#!/usr/bin/env bash
# size-guard.sh — PostToolUse/Edit|Write|NotebookEdit hook.
#
# Measures the file as it is now AND as it was before this edit (for a TRACKED
# file: the copy the last run for this repo snapshotted, whatever session that
# was, else its HEAD content; for an untracked file: nothing at all, per the
# spec's frozen contract), then speaks only about what this edit did: crossing
# a limit, or growing something already over it. An oversized file you left
# alone or shrank is not this edit's fault and gets no message. Only source
# extensions are measured — a long JSON fixture or lock file is data, not code.
# python3 does the counting; without it the check is skipped entirely (exit 0).
#
# The snapshot directory is keyed by the repo toplevel, so it must not outlive
# the repo that filled it: it carries the repo's root commit and path, is wiped
# whole when the root commit no longer matches (a repo deleted and re-created at
# the same path — worktrees, /tmp fixtures, CI checkouts all reuse paths), and
# a directory whose repo path is gone (or that predates this stamping) is pruned
# the next time a new repo needs one. Untracked files are never snapshotted, so
# deleting a file and writing a new one at the same path is judged from the
# empty baseline the spec specifies.
#
# Accepted trade (deliberate, do not "fix" blindly): for a tracked file the
# snapshot outranks HEAD once it exists, so a change made outside the edit hooks
# (`git checkout -- f`, `git stash`) leaves a stale, larger baseline behind and
# the next crossing of a limit in that file stays silent. It is not detectable
# here — "snapshot 700 / HEAD 390 / now 450" is the same evidence whether the
# agent shrank the file or reverted it — and the missed case always follows an
# earlier report for that same file, so the agent has already been told once.
# Re-firing instead would re-nag every shrink, which is what FU-30 is about.
# t_quality_size_snapshot_outranks_head_after_out_of_band_revert pins this.
#
# Escape hatches: CC_NO_SIZE_GUARD=1 for one command, `sizeGuard: false` in
# .claude/flow.config.json, or `flow off` for the directory.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"
hook_skip_if_off # `flow off` wrote .claude/flow.off here: no judging hooks

file_path=$(hook_field '.tool_input.file_path')
[ -z "$file_path" ] && hook_ok
[ -f "$file_path" ] || hook_ok

have python3 || hook_ok

[ "${CC_NO_SIZE_GUARD:-}" = "1" ] && hook_ok
[ "$(hook_config sizeGuard)" = "false" ] && hook_ok

# Source files only. Everything else — data, markup, config, generated
# blobs — has no meaningful line budget.
case "$file_path" in
*.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.py | *.rs | *.go | *.rb | \
	*.php | *.java | *.kt | *.swift | *.sh | *.bash | *.fish | *.c | *.cc | \
	*.cpp | *.h | *.hpp | *.cs | *.tf) ;;
*) hook_ok ;;
esac
case "${file_path##*/}" in
*.min.* | *.lock) hook_ok ;;
esac
case "$file_path" in
*_test.* | *.test.* | *.spec.* | */tests/* | */__tests__/* | tests/* | __tests__/*) hook_ok ;;
esac

# Vendored, generated, git-ignored and pruned paths are not ours to judge;
# git is still the enforcement boundary for everything else.
hook_excluded_path "$file_path" && hook_ok
hook_git_managed "$file_path" || hook_ok

# Env overrides win over flow.config.json, which wins over the 400/60 defaults.
_max_file=$(hook_config maxFileLines)
_max_func=$(hook_config maxFuncLines)
[ -n "${CC_MAX_FILE_LINES:-}" ] && _max_file="$CC_MAX_FILE_LINES"
[ -n "${CC_MAX_FUNC_LINES:-}" ] && _max_func="$CC_MAX_FUNC_LINES"
case "$_max_file" in '' | *[!0-9]*) _max_file=400 ;; esac
case "$_max_func" in '' | *[!0-9]*) _max_func=60 ;; esac

# The pre-edit content, best evidence first. The copy the last size-guard run
# saw IS what the file looked like before this edit, so it wins over HEAD:
# without it, one uncommitted oversized file makes every later edit fire again,
# including the shrinking edits this hook just asked for. That copy is keyed by
# the repo and the path, NOT by the session — uncommitted work outlives a
# /clear, a resume and a new session, and a baseline that resets with the
# session brings the whole FU-30 nag back on the next shrink. With no snapshot
# yet, HEAD's copy of a tracked file; an untracked file has no baseline at all,
# so every limit it breaks is this edit's doing.
_sg_dir=$(dirname "$file_path")
_sg_top=$(git -C "$_sg_dir" rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$_sg_top" ] && _sg_top="$_sg_dir"
# The repo's identity, not just its path: a repo re-created at the same path has
# a different root commit and must not inherit the old one's baselines.
_sg_root=$(git -C "$_sg_dir" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)
[ -z "$_sg_root" ] && _sg_root="no-commit"
_sg_tmp="${TMPDIR:-/tmp}"
_sg_snapdir="${_sg_tmp%/}/claude-size-$(printf '%s' "$_sg_top" | cksum | awk '{print $1}')"
_sg_snap="$_sg_snapdir/$(printf '%s' "$file_path" | cksum | awk '{print $1}')"
_sg_stamp="$_sg_snapdir/.repo"

# _sg_prune — drop snapshot dirs of repos that no longer exist, and any dir
# written before this stamping existed. Runs only when this repo needs a new
# directory, i.e. at most once per repo, so it never costs a per-edit scan.
_sg_prune() {
	local d p
	for d in "${_sg_tmp%/}"/claude-size-*; do
		[ -d "$d" ] || continue
		[ -L "$d" ] && continue
		[ -O "$d" ] || continue
		p=$(tail -1 "$d/.repo" 2>/dev/null || true)
		if [ -z "$p" ] || [ ! -d "$p" ]; then rm -rf "$d"; fi
	done
}

# The dir name is a checksum of a known path, so on a shared /tmp it is
# guessable: refuse one that is a symlink or that someone else owns, and wipe
# one whose stamp belongs to a different repo.
_sg_snapdir_ok=1
if [ -L "$_sg_snapdir" ]; then
	_sg_snapdir_ok=0
elif [ -d "$_sg_snapdir" ]; then
	if [ -O "$_sg_snapdir" ]; then
		if [ "$(head -1 "$_sg_stamp" 2>/dev/null || true)" != "$_sg_root" ]; then
			rm -rf "$_sg_snapdir"
		fi
	else
		_sg_snapdir_ok=0
	fi
fi
[ "$_sg_snapdir_ok" -eq 1 ] && [ ! -d "$_sg_snapdir" ] && _sg_prune

# core.quotePath=false: without it git C-quotes any non-ASCII name
# ("caf\303\251.py"), `git show HEAD:<that>` fails, and a file that only
# shrank looks brand new.
_sg_rel=$(git -C "$_sg_dir" -c core.quotePath=false ls-files --full-name -- "$file_path" 2>/dev/null | head -1)

_sg_base=""
_sg_tempbase=0
if [ -n "$_sg_rel" ]; then
	if [ "$_sg_snapdir_ok" -eq 1 ] && [ -f "$_sg_snap" ] && [ ! -L "$_sg_snap" ] && [ -O "$_sg_snap" ]; then
		_sg_base="$_sg_snap"
	else
		# No writable TMPDIR: no baseline, and not one word on stderr —
		# stderr is the channel the model reads when this hook exits 2.
		_sg_base=$(mktemp "${_sg_tmp%/}/claude-sg-base.XXXXXX" 2>/dev/null) || _sg_base=""
		if [ -n "$_sg_base" ]; then
			_sg_tempbase=1
			git -C "$_sg_dir" show "HEAD:$_sg_rel" >"$_sg_base" 2>/dev/null || : >"$_sg_base"
		fi
	fi
fi

python3 "$HERE/size_guard.py" "$file_path" "$_max_file" "$_max_func" --baseline "$_sg_base"
_sg_rc=$?
[ "$_sg_tempbase" -eq 1 ] && rm -f "$_sg_base"

# Record the file as it is now — after the measurement, so the snapshot this
# run read is never the one it just wrote. The next edit is judged against it.
# Tracked files only: an untracked file's baseline is empty by contract, and a
# snapshot nobody reads is litter. The name is unlinked before the copy so a
# symlink planted there is replaced rather than written through, and the
# directory is private to its owner.
if [ -n "$_sg_rel" ] && [ "$_sg_snapdir_ok" -eq 1 ] && mkdir -p "$_sg_snapdir" 2>/dev/null; then
	chmod 700 "$_sg_snapdir" 2>/dev/null || true
	if [ -O "$_sg_snapdir" ] && [ ! -L "$_sg_snapdir" ]; then
		printf '%s\n%s\n' "$_sg_root" "$_sg_top" >"$_sg_stamp" 2>/dev/null || true
		rm -f "$_sg_snap" 2>/dev/null || true
		cp "$file_path" "$_sg_snap" 2>/dev/null && chmod 600 "$_sg_snap" 2>/dev/null || true
	fi
fi

exit "$_sg_rc"
