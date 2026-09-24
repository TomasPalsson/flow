---
name: pr-reviewer-execution-prompt
description: Execution-machine delta for the pr-reviewer pipeline. Contains ONLY what SKILL.md does not — preflight bash, portable diff-stat, state schema, context-capacity recovery, ralph-loop completion signal. Load ONLY for ralph-loop accelerated execution, never on the manual path.
---

# PR Reviewer — Execution-Machine Delta

**This file is intentionally minimal.** The authoritative stage logic lives in
SKILL.md. This file contains only what the orchestrator needs beyond SKILL.md
when executing the pipeline unattended via ralph-loop:

- State schema (what to persist between loop iterations)
- Preflight bash that SKILL.md hints at but doesn't spell out
- Context-capacity recovery rule (the one-time-only instruction)
- Portable awk replacement for `diffstat` (macOS doesn't ship it)
- ralph-loop completion signal

**For the full pipeline** — stages, rules, filters, anti-patterns, framing rules —
read SKILL.md. Do NOT duplicate its content in your own plans.

---

## State Schema (serialize to `.pr-review/state.local.md`)

Preserve these keys across iterations:

```yaml
type: pr-review
pipeline_version: 1
owner: <github_owner>
repo: <github_repo>
pr_number: <n>
head_sha: <40-char SHA>
base_branch: <base>
title: <PR title>
body_excerpt: <first 500 chars of PR body>
changed_files: [<file1>, <file2>, ...]
commits_summary: <first-line of each commit, joined>
linked_issues: [<#123>, ...]
size_tier: small|medium|large
lines_changed: <int>
comment_budget: 8|5
top_level_intent: <1-2 sentence summary from Stage 1>
blast_radius: low|medium|high
detected_lint_cmd: <from project detection, may be empty>
detected_typecheck_cmd: <from project detection, may be empty>
detected_test_cmd: <from project detection, may be empty>
current_stage: 0|1|2|3|4|5|6|7|8
stages_completed:
  - "0: Setup"
  - "1: Intent Pass"
  ...
```

Jump to `current_stage` on every iteration; re-read state first.

## Context-Capacity Recovery (THE rule that's not in SKILL.md)

At ~70% context capacity: **complete the current stage, write state, then
compress**. NEVER mid-stage compression — it corrupts specialist findings and
filter state. The stage boundary is the only safe compression point.

## Stage 0: Preflight Bash (what SKILL.md skips)

```bash
# Preflight: verify gh auth
if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: gh CLI not authenticated. Run 'gh auth login' and retry." >&2
  exit 1
fi

# Resolve PR number from args or current branch
if [ -z "$PR_NUMBER" ]; then
  PR_DATA=$(gh pr view --json number,headRefOid 2>/dev/null) || {
    echo "ERROR: no PR arg and current branch has no open PR." >&2
    echo "Usage: /pr-reviewer <pr-number>" >&2
    exit 1
  }
  PR_NUMBER=$(echo "$PR_DATA" | jq -r .number)
fi

OWNER=$(gh repo view --json owner -q .owner.login)
REPO=$(gh repo view --json name -q .name)

# Fail loud if PR is inaccessible
if ! PR_JSON=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" 2>&1); then
  echo "ERROR fetching PR #$PR_NUMBER from $OWNER/$REPO: $PR_JSON" >&2
  echo "Check: (1) PR number correct, (2) read access, (3) gh auth status shows the right account" >&2
  exit 1
fi
```

## Stage 2: Portable Per-File Diff Stats (NOT `diffstat`)

`diffstat` isn't installed by default on macOS. Use this awk pipeline instead:

```bash
gh pr diff "$PR_NUMBER" | awk '
  /^diff --git/ { if (file) print file, added, removed; file=""; added=0; removed=0 }
  /^\+\+\+ b\// { file = substr($0, 7) }
  /^[+][^+]/ { added++ }
  /^[-][^-]/ { removed++ }
  END { if (file) print file, added, removed }
'
```

Output format: `<file> <added> <removed>` per line. Feed this into your Stage 2
triage table.

## Stage 7: Script Resolution (the skill path fix)

```bash
SKILL_SCRIPT="${CLAUDE_PLUGIN_ROOT}/skills/pr-reviewer/scripts/post-review.sh"

if [ -x "$SKILL_SCRIPT" ]; then
  bash "$SKILL_SCRIPT" "$OWNER" "$REPO" "$PR_NUMBER" ".pr-review/consolidated.json"
else
  # Inline fallback — always works
  FRESH_SHA=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.head.sha')
  jq --arg sha "$FRESH_SHA" '.commit_id = $sha' .pr-review/consolidated.json > /tmp/pr-review-payload.json
  gh api --method POST \
    "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
    --input /tmp/pr-review-payload.json
fi
```

## Error Recovery (the delta — NOT the rules already in SKILL.md)

These specific recoveries apply to loop-mode execution where a naive retry loop
would burn iterations without fixing the root cause:

| Signal | Recovery |
|--------|----------|
| Specialist subagent returns empty JSON | retry ONCE as foreground, then skip that specialist (don't loop) |
| Stage 5 produces 0 findings after filters | verdict APPROVE, STILL run Stage 6 (empty review is a valid outcome) |
| Stage 7 returns 422 on commit_id | refetch head SHA, retry ONCE. If 422 again → STOP, report to user |
| Stage 7 returns 429 / "spammed" | sleep 60s, retry ONCE. If 429 again → STOP, respect GitHub's cooldown |
| User rejects all comments at Stage 6 | cleanup `.pr-review/` and exit 0 (0 comments is a valid review) |
| Context at ~70% capacity | complete current stage, write state, compress. NEVER mid-stage |

## Completion Signal (ralph-loop only)

After Stage 8 cleanup, emit:

```
<promise>REVIEW POSTED</promise>
```

ralph-loop uses this as the `--completion-promise` match. Emit it verbatim,
including the tags. Emit ONLY if a review was actually posted OR the user
explicitly cancelled at Stage 6 (in which case emit
`<promise>REVIEW CANCELLED</promise>` instead).

## Manual Execution

If ralph-loop is not the execution path, do NOT load this file — just follow
SKILL.md stage by stage. This file adds nothing for manual execution other
than the preflight bash and the portable `awk` command, which you can always
copy from here if needed.
