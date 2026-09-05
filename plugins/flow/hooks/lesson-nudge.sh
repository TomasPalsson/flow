#!/usr/bin/env bash
# lesson-nudge.sh — UserPromptSubmit hook.
#
# When the prompt reads as a correction of something the agent just did
# ("you deleted the wrong file", "don't do that again", "why did you push…"),
# print one context line suggesting /lesson be OFFERED after the current
# step. Deterministic phrase match, no judgement; advisory only — the model
# proposes, the user decides — exit 0 always, no stdout when nothing
# matches. CC_NO_LESSON_NUDGE=1 disables it.
set -u
HERE=$(cd "$(dirname "$0")" && pwd -P)
# shellcheck source=lib/hookout.sh
. "$HERE/lib/hookout.sh"

[ "${CC_NO_LESSON_NUDGE:-}" = "1" ] && hook_ok

prompt=$(hook_field .prompt)
[ -z "$prompt" ] && hook_ok
case "$prompt" in /*) hook_ok ;; esac   # a slash command is never a correction

# Lower-case without ${var,,} (bash 4): tr is enough for the phrases below.
p=$(printf '%s' "$prompt" | tr 'A-Z' 'a-z' | tr '\n' ' ')

# Second person + a verb that is only ever a complaint (deleted, broke,
# overwrote), or a neutral verb with a "wrong/again/without" tail, or an
# explicit "that was wrong / not what I asked" marker. Plain instructions
# ("don't forget the tests"), praise ("you added a great feature") and
# questions ("why did you choose this?") do not match.
if printf '%s' "$p" | grep -qE \
  -e "you (just |also |again )?(deleted|removed|broke|ignored|forgot|skipped|overwrote|reverted|clobbered|nuked|wiped) " \
  -e "you (just |also |again )?(did|changed|edited|pushed|committed|touched|modified) (it|that|this|the|my|our) .*(wrong|again|without|instead|not )" \
  -e "you (keep|kept) (doing|editing|changing|pushing|deleting|ignoring|adding|removing|using)" \
  -e "you (always|still|again) (do|did|edit|change|push|delete|ignore|add|remove|use|forget) " \
  -e "you (should not|shouldn'?t|were not|weren'?t) (have|supposed)" \
  -e "(don'?t|do not|stop) (do|doing) (that|this|it)( again)?" \
  -e "why did you (delete|remove|change|edit|push|commit|touch|revert|skip|ignore|overwrite|break|modify|add|run) " \
  -e "(not what i asked|i told you|i said not|that was wrong|that'?s wrong|wrong (file|branch|directory|repo)|you got it wrong|same mistake|not again|once again|that'?s not what)"; then
  printf 'flow: this prompt may be a correction. If Claude got something wrong, finish the current step and then offer /lesson in one line (a test, hook or script beats a promise); run it only if the user agrees. Say nothing if this was not a mistake.\n'
fi
hook_ok
