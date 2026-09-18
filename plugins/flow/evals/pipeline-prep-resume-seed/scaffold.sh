#!/usr/bin/env bash
set -euo pipefail
# This script ends in `git add -A; git commit`. Run by hand from a checkout
# instead of the eval runner's scratch copy, that would sweep the invoking
# repo's whole working tree into one commit under a fake author identity.
# `claude plugin eval --scaffold` nests this case's cwd inside its own
# throwaway HOME, which is itself an empty `git init` (no commits, user.email
# eval@example.invalid) so `--is-inside-work-tree` alone is true there too.
# Only refuse when that work tree already has a commit, which the real
# invoking checkout always does and the eval sandbox's placeholder never does.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1 &&
	git rev-parse --verify -q HEAD >/dev/null 2>&1; then
	echo "scaffold.sh: refusing to scaffold inside an existing git work tree: $PWD" >&2
	exit 1
fi
git init -q
git config user.email "eval@example.com"
git config user.name "eval-scaffold"
git config commit.gpgsign false
cat >README.md <<'MD'
# habits

A small habit-tracking app.
MD
mkdir -p .specs/001-habit-reminders
cat >.specs/001-habit-reminders/PREP.md <<'MD'
# Prep — Habit reminders
Gathered: 2026-09-18 · Questions: 0 of 12 · Route: dispatch · Status: interviewing

## Decisions
## Not this
- No social or sharing features.
## Discretion
## Assumptions
- A-01 The real problem is people forgetting a habit at the moment it matters, not tracking streaks — evidence: none — confidence: medium — unconfirmed
- A-02 The user is one person tracking 3-5 personal habits on their phone — evidence: none — confidence: low — unconfirmed
## Verify
## Open
- Q: push notification vs calendar event for the reminder? → deferred to spec
MD
git add -A
git commit -q -m scaffold
