#!/usr/bin/env bash
# portfolio skill persistent cross-run memory.
#
# WHY THIS EXISTS: this skill is invoked on a recurring (weekly) schedule, and the
# scheduled routine runs with persist_session=false in a fresh container every week, so
# ~/.cache/portfolio-skill/ (portfolio.json, decision-log.jsonl, thesis-registry.json,
# fx-cache.json) is WIPED between runs. Without this, REVIEW mode has no book to review,
# no invalidation conditions to check, and no history of what was already decided — the
# skill would silently fall back to BUILD mode every Monday and either re-construct the
# portfolio from scratch or ask the user to re-answer context-elicitation questions it
# already has answers to. That is the single biggest silent failure of the whole
# recurring-review design, and the entire "weekly hazard-scan / monthly drift / quarterly
# re-score" cadence model (see SKILL.md's Prime Directive) is meaningless without state
# that actually survives across runs. This syncs those state files to a dedicated git
# branch (portfolio-state) using pure git plumbing: it never checks out, never touches
# the routine's working tree, and never pollutes code history or conflicts with code PRs.
#
# Usage (wired into execution-prompt-build.md / execution-prompt-review.md):
#   bash scripts/state.sh load   # preflight, before Stage 1 — populate ~/.cache from the branch
#   bash scripts/state.sh save   # end-of-run discipline — push updated state back to the branch
#
# Deliberately NOT `set -e`: individual missing files must degrade gracefully (e.g. a
# first-ever run has no fx-cache.json yet), not abort the whole load/save.
set -uo pipefail

CACHE="$HOME/.cache/portfolio-skill"
BRANCH="portfolio-state"
# portfolio.json: current holdings, target weights, cluster map, conviction tiers — the
#   book itself. Without this REVIEW mode has nothing to review and no targets to drift
#   against.
# decision-log.jsonl: append-only record of every run's outcome (including "no action,
#   logged" weekly passes). This is what lets a quarterly re-score, a cooldown window, or
#   a "was this already flagged last week" check look backward at all — an append-only
#   log that resets weekly can never accumulate the history those checks depend on.
# thesis-registry.json: per-name thesis text plus the PRE-REGISTERED invalidation
#   conditions written at BUILD time or the last quarterly re-score. The review doctrine's
#   asymmetric evidence bars (SKILL.md references/03-review-doctrine.md) depend on
#   comparing today's evidence against a thesis that was committed to *before* today's
#   price action — a thesis reconstructed after the fact from a wiped cache is exactly the
#   sycophancy/hindsight failure mode the skill is designed to avoid.
# fx-cache.json: last-known FX rates used for currency-normalized reconciliation and
#   return decomposition (references/08-multi-currency.md) — not strictly irreplaceable
#   (can be refetched), but caching it avoids re-deriving same-day rates mid-run and keeps
#   the local-vs-FX return decomposition consistent across a single run's multiple stages.
# preferences.json: the owner's STANDING preferences (autonomy level, jurisdiction, drawdown
#   tolerance, exclusions, target name count, cash sleeve, deployment style). This is what stops
#   the skill re-interrogating the owner about settled questions on every run — the single
#   biggest source of unnecessary owner workload. If it is lost, the skill reverts to asking
#   the full elicitation battery again, which is precisely the behaviour it exists to prevent.
#   Schema and staleness rules: references/09-autonomy-and-communication.md.
# <jurisdiction>-tax-research.md: the owner's tax-position research, with every claim tagged
#   by source tier and an explicit confirmed/uncertain split. Persisted because tax treatment
#   is jurisdiction-specific, slow-changing, and expensive to re-derive — and because the
#   UNCERTAIN items are questions the owner is meant to put to a professional, which would be
#   silently lost on a container wipe. Rename per jurisdiction; the skill never assumes US rules.
FILES=(portfolio.json decision-log.jsonl thesis-registry.json fx-cache.json preferences.json iceland-tax-research.md)

# Fallback identity so commit-tree works even if git user.* is unset in the run env.
: "${GIT_AUTHOR_NAME:=portfolio-skill}"    "${GIT_AUTHOR_EMAIL:=portfolio-skill@localhost}"
: "${GIT_COMMITTER_NAME:=portfolio-skill}" "${GIT_COMMITTER_EMAIL:=portfolio-skill@localhost}"
export GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL

remote_tip() { git ls-remote --heads origin "$BRANCH" 2>/dev/null | awk '{print $1}'; }

case "${1:-}" in
  load)
    mkdir -p "$CACHE"
    tip="$(remote_tip)"
    if [ -z "$tip" ]; then
      echo "state: no '$BRANCH' branch yet (first run) — starting with empty memory, BUILD mode expected" >&2
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
      commit="$(printf 'persist portfolio state %s\n' "$(date -u +%FT%TZ)" | git commit-tree "$tree" $parent)"
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
