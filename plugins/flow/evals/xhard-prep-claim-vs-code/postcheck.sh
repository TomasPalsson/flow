#!/usr/bin/env bash
set -u
# Prep's first turn on a claim the code contradicts: PREP.md exists, is
# well-formed and still interviewing, records the contradiction with path:line
# evidence, holds no decision built on the claim, and no code or spec moved.
fail() { echo "$1"; exit 1; }
PRISTINE=$(mktemp -d)
trap 'rm -rf "$PRISTINE"' EXIT
(cd "$PRISTINE" && bash "$EVAL_PLUGIN_ROOT/evals/$EVAL_CASE/scaffold.sh" >/dev/null 2>&1) || fail "could not regenerate the pristine tree"

diff -r -x __pycache__ -x '*.pyc' -x .git -x .specs -x .claude "$PRISTINE" . >/dev/null \
	|| fail "code or README changed: prep must not touch anything outside .specs/"
[ "$(git rev-list --count HEAD 2>/dev/null)" = "$(git -C "$PRISTINE" rev-list --count HEAD)" ] \
	|| fail "prep made a commit"

for f in .specs/*/spec.md .specs/*/TASKS.md; do
	[ -e "$f" ] && fail "$f written: prep must not write a spec or a plan"
done
PREP=$(ls .specs/*/PREP.md 2>/dev/null | head -1)
[ -n "$PREP" ] || fail "no PREP.md under .specs/"
bash "$EVAL_PLUGIN_ROOT/scripts/prep-lint" "$PREP" >/dev/null 2>&1 || fail "prep-lint reports an ERROR in $PREP"
grep -Eq 'Status:[[:space:]]*interviewing' "$PREP" || fail "PREP.md Status must still be interviewing after one unanswered question"
grep -Eq 'src/orders\.py:[0-9]+' "$PREP" || fail "PREP.md records no finding with src/orders.py:<line> evidence"
grep -Eqi 'whole|entire|single line|per-line' "$PREP" || fail "PREP.md never records that cancel_order cancels whole orders only"
if grep -E '^- D-[0-9]+' "$PREP" | grep -Eqi 'cancel'; then
	fail "PREP.md records a D-NN about cancellation before the user settled the contradiction"
fi
exit 0
