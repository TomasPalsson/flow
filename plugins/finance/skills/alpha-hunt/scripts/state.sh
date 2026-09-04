#!/usr/bin/env bash
# alpha-hunt persistent cross-run memory.
#
# WHY THIS EXISTS: the scheduled routine runs with persist_session=false in a fresh
# container every week, so ~/.cache/alpha-hunt/ (picks-log.jsonl, signal-perf.json,
# holdings.json) is WIPED between runs. Without this, the learning loop reads an empty
# log every Monday and never compounds — the single biggest silent failure of the
# whole memory system. This syncs those state files to a dedicated git branch
# (alpha-hunt-state) using pure git plumbing: it never checks out, never touches the
# routine's working tree, and never pollutes code history or conflicts with code PRs.
#
# Usage (wired into execution-prompt.md):
#   bash scripts/state.sh load   # at run start, before Stage 1 — populate ~/.cache from the branch
#   bash scripts/state.sh save   # at run end, Stage 8 — push updated state back to the branch
#
# Deliberately NOT `set -e`: individual missing files must degrade gracefully, not abort.
set -uo pipefail

CACHE="$HOME/.cache/alpha-hunt"
BRANCH="alpha-hunt-state"
# news-seen.json and sentiment-history.json are HISTORY-ACCUMULATING caches, not derived data:
# cross-week rehash detection (Tetlock 2011 staleness fade) and the sentiment z-score baseline both
# compare against prior WEEKS. If they reset with the weekly container, every story looks fresh
# forever and the z-score never leaves "history accumulating" — the features silently no-op rather
# than fail loudly, which is the worst kind of broken.
FILES=(picks-log.jsonl signal-perf.json holdings.json news-seen.json sentiment-history.json)

# Fallback identity so commit-tree works even if git user.* is unset in the run env.
: "${GIT_AUTHOR_NAME:=alpha-hunt}"    "${GIT_AUTHOR_EMAIL:=alpha-hunt@localhost}"
: "${GIT_COMMITTER_NAME:=alpha-hunt}" "${GIT_COMMITTER_EMAIL:=alpha-hunt@localhost}"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

remote_tip() { git ls-remote --heads origin "$BRANCH" 2>/dev/null | awk '{print $1}'; }

case "${1:-}" in
  load)
    mkdir -p "$CACHE"
    tip="$(remote_tip)"
    if [ -z "$tip" ]; then
      echo "state: no '$BRANCH' branch yet (first run) — starting with empty memory" >&2
      exit 0
    fi
    git fetch origin "$BRANCH" --quiet 2>/dev/null || true
    for f in "${FILES[@]}"; do
      if git show "$tip:$f" >"$CACHE/$f" 2>/dev/null; then
        echo "state: loaded $f" >&2
      else
        rm -f "$CACHE/$f"   # nothing stored yet — ensure no stale local copy
      fi
    done
    ;;

  save)
    git rev-parse --show-toplevel >/dev/null 2>&1 || {
      echo "state: not in a git repo — cannot persist memory" >&2; exit 1; }

    tip="$(remote_tip)"
    tmpidx="$(mktemp)"; rm -f "$tmpidx"   # git needs a NON-existent path to build a fresh index
    export GIT_INDEX_FILE="$tmpidx"; parent=""
    if [ -n "$tip" ]; then
      git fetch origin "$BRANCH" --quiet 2>/dev/null || true
      git read-tree "$tip" 2>/dev/null && parent="-p $tip"   # build on prior state
    fi

    n=0
    for f in "${FILES[@]}"; do
      if [ -f "$CACHE/$f" ]; then
        blob="$(git hash-object -w "$CACHE/$f" 2>/dev/null)" \
          && git update-index --add --cacheinfo 100644 "$blob" "$f" \
          && n=$((n+1))
      fi
    done

    if [ "$n" -gt 0 ]; then
      tree="$(git write-tree)"
      commit="$(printf 'persist alpha-hunt state %s\n' "$(date -u +%FT%TZ)" | git commit-tree "$tree" $parent)"
      if git push origin "$commit:refs/heads/$BRANCH" --quiet 2>/dev/null; then
        echo "state: persisted $n file(s) to '$BRANCH'" >&2
      else
        echo "state: push to '$BRANCH' FAILED — check the run has push creds; memory will not persist" >&2
      fi
    else
      echo "state: no state files present in $CACHE to save" >&2
    fi
    unset GIT_INDEX_FILE; rm -f "$tmpidx"
    ;;

  *)
    echo "usage: state.sh load|save" >&2; exit 1 ;;
esac
