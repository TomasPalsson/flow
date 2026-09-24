---
name: pr-reviewer-gh-api-recipes
description: Runnable `gh api` commands to post inline review comments, suggested changes, multi-line comments, and batch reviews. Load at Stage 7 (Post Review) of the pr-reviewer pipeline.
---

# GitHub Review API Recipes

Load this file at **Stage 7 (Post Review)**. It contains the exact `gh api`
commands needed to post inline comments. `gh pr review` does NOT natively support
inline comments — you MUST use `gh api` for anything beyond top-level review text.

## The Critical Distinction: 3 Different Comment Types

| Type | Endpoint | Purpose |
|------|----------|---------|
| **PR Review** | `POST /repos/{o}/{r}/pulls/{n}/reviews` | Top-level verdict (APPROVE/REQUEST_CHANGES/COMMENT) + optional `comments[]` inline batch |
| **Review Comment** (inline) | `POST /repos/{o}/{r}/pulls/{n}/comments` | Standalone inline comment on one diff line |
| **Issue Comment** | `POST /repos/{o}/{r}/issues/{n}/comments` | Plain conversation comment — NOT a review comment |

**The pipeline's default path is Recipe 5** (batch review) — one atomic call
that posts the verdict and all inline comments together. That's what
`scripts/post-review.sh` uses.

## Recipe 1: Top-Level PR Comment (No Inline)

For when there's no diff context to attach — e.g., Stage 1 returning the PR
due to inadequate description.

```bash
gh pr review "$PR_NUMBER" \
  --comment \
  --body-file .pr-review/context-request.md
```

Alternatives:
```bash
gh pr review "$PR_NUMBER" --approve --body "LGTM"
gh pr review "$PR_NUMBER" --request-changes --body "Blocker inline"
```

**Note**: `gh pr review` only accepts `--body` / `--body-file` — it cannot
attach inline annotations.

## Recipe 2: Batch Review (The Default — ALWAYS use this at Stage 7)

Single atomic POST with verdict + all inline comments. Counts as ONE
content-generating request regardless of comment count.

```bash
HEAD_SHA=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.head.sha')

cat > /tmp/review-payload.json <<JSONEOF
{
  "commit_id": "$HEAD_SHA",
  "body": "Top-level summary of the review. Required when event is COMMENT or REQUEST_CHANGES.",
  "event": "COMMENT",
  "comments": [
    {
      "path": "src/auth/session.ts",
      "line": 42,
      "side": "RIGHT",
      "body": "issue (blocking): \`parseInt(undefined)\` returns NaN — the \`> 0\` guard on line 47 passes and allows negative IDs.\n\nFailure scenario: POST without id field results in querying user -1."
    },
    {
      "path": "src/utils.ts",
      "line": 15,
      "side": "RIGHT",
      "body": "suggestion (non-blocking): Consider Promise.allSettled — partial success is acceptable here."
    }
  ]
}
JSONEOF

gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --input /tmp/review-payload.json
```

**Required fields**:
- `commit_id`: fresh head SHA. If the author force-pushed since you fetched it,
  this is stale and will 422.
- `body`: required when `event` is `COMMENT` or `REQUEST_CHANGES`. Optional for APPROVE.
- `event`: `APPROVE`, `REQUEST_CHANGES`, `COMMENT`, or omit for PENDING.
- `comments[]`: optional. Each element requires `path`, `line`, `side`, `body`.

## Recipe 3: Single-Line Inline Comment (Without a Review)

Use this only for ad-hoc annotations that don't need a verdict. The pipeline
uses Recipe 2 instead because it's atomic.

```bash
gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
  --input - <<JSONEOF
{
  "body": "nitpick: prefer structuredClone over JSON.parse(JSON.stringify(x))",
  "commit_id": "$HEAD_SHA",
  "path": "src/utils.ts",
  "line": 30,
  "side": "RIGHT"
}
JSONEOF
```

## Recipe 4: Multi-Line Inline Comment (Range)

When a comment applies to a range of lines (e.g., "this entire block can be
replaced with X"). Requires `start_line` + `start_side` + `line` + `side`.

```bash
gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
  --input - <<JSONEOF
{
  "body": "suggestion: this whole loop can be replaced with Array.from({length: N}, (_, i) => ...)",
  "commit_id": "$HEAD_SHA",
  "path": "src/generator.ts",
  "start_line": 10,
  "start_side": "RIGHT",
  "line": 18,
  "side": "RIGHT"
}
JSONEOF
```

**Rules**:
- `start_line` must be strictly less than `line` (not ≤).
- `start_side` and `side` can differ (e.g., a deletion on LEFT spanning to an
  addition on RIGHT), but in practice both are usually RIGHT.
- Omit `start_line`/`start_side` for single-line comments.

## Recipe 5: Suggested Change (```suggestion block)

GitHub renders a `\`\`\`suggestion` fenced code block as an apply-able patch
button. It replaces the commented line(s) with the block contents.

### Single-line suggestion

```bash
cat > /tmp/suggestion.json <<'JSONEOF'
{
  "body": "suggestion: extract timeout with a default fallback\n\n```suggestion\n  const timeout = options.timeout ?? DEFAULT_TIMEOUT;\n```",
  "commit_id": "SHA_HERE",
  "path": "src/config.ts",
  "line": 23,
  "side": "RIGHT"
}
JSONEOF

gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
  --input /tmp/suggestion.json
```

### Multi-line suggestion (replaces lines 40–43 with new block)

```bash
cat > /tmp/suggestion-multi.json <<'JSONEOF'
{
  "body": "issue (blocking): Missing auth guard for unauthenticated users.\n\n```suggestion\n  if (!user) {\n    throw new AuthError('Unauthenticated');\n  }\n```",
  "commit_id": "SHA_HERE",
  "path": "src/auth.ts",
  "start_line": 40,
  "start_side": "RIGHT",
  "line": 43,
  "side": "RIGHT"
}
JSONEOF
```

**Suggestion rules**:
- The fenced block MUST start with triple-backtick + "suggestion".
- Content inside replaces ALL lines from `start_line..line` inclusive.
- For a single-line suggestion, omit `start_line`/`start_side`.
- Escape newlines as `\n` in JSON strings. Use heredoc files to avoid shell
  escaping pain with backticks.

## Field Reference (CRITICAL — memorize the gotchas)

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `commit_id` | SHA string | Required for /comments; defaults to head SHA for /reviews | ALWAYS refetch before posting. Force-pushes invalidate old SHAs. |
| `path` | string | Yes | Repo-relative, no leading slash. `src/foo.ts` not `/src/foo.ts`. |
| `line` | integer | Yes (or `subject_type: "file"`) | Line in the file, NOT position in the diff. |
| `side` | `LEFT`/`RIGHT` | Yes when using `line` | **RIGHT = additions + context (new version)**. **LEFT = deletions (old version)**. |
| `start_line` | integer | Only for multi-line | Strictly less than `line`. |
| `start_side` | `LEFT`/`RIGHT` | Only for multi-line | Required when `start_line` is used. |
| `body` | string (Markdown) | Yes | GFM. Use `\`\`\`suggestion` for suggested changes. |
| `event` | string | For reviews | `APPROVE`, `REQUEST_CHANGES`, `COMMENT`, or omit for PENDING. |
| `position` | integer | **DEPRECATED** | Number of lines below the first `@@` hunk header. Do NOT use — use `line`+`side` instead. |
| `subject_type` | string | No | `line` (default) or `file`. Use `file` to attach to the file header with no specific line. |

## The `line` vs `position` Gotcha

**`position` is deprecated. Do NOT use it.** `position` counts diff lines from
the first `@@` hunk header — it's a brittle number computed by parsing raw diffs.

**`line` + `side`** is the modern approach:
- `side: "RIGHT"` → `line` is the line number in the NEW version of the file
- `side: "LEFT"` → `line` is the line number in the OLD version of the file

The `line` MUST appear within a diff hunk (changed or context lines shown in
the diff output). You cannot comment on unchanged lines that are outside the
diff's visible range.

## Common 422 Errors and Fixes

| Error | Cause | Fix |
|-------|-------|-----|
| "Validation failed" on `line` | Line not visible in diff | Only comment on lines that appear in `gh pr diff` output |
| "Validation failed" on `commit_id` | SHA stale (force push) | Refetch: `gh api repos/$OWNER/$REPO/pulls/$PR --jq .head.sha` |
| "Validation failed" on `commit_id` | SHA doesn't touch `path` | Use head SHA; ensure the commit modified that file |
| "Validation failed" on `start_line` | `start_line >= line` | `start_line` must be strictly less than `line` |
| "Validation failed" — side missing | Using `line` without `side` | Always include `side` with `line` |
| "body required" | COMMENT/REQUEST_CHANGES with no body | Review-level `body` required for those events |
| "endpoint has been spammed" | Too many comments too fast | Batch via /reviews instead; or add `sleep 1` between /comments posts |

## Rate Limits

| Limit | Value | How to stay under |
|-------|-------|-------------------|
| Content-generating requests | **80/min, 500/hr** | Use batch /reviews — that's 1 request for N comments |
| Primary rate limit | 5000/hr authenticated | Not usually binding for review workflows |
| Abuse detection | unclear threshold | Never POST > 1/sec in loops |

**The pipeline uses Recipe 2 (batch /reviews) because it's the only approach
that scales without burning your content rate limit.**

## Debugging: See the Actual Response

When a 422 is confusing, add `--include` to see response headers:

```bash
gh api --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --include \
  --input /tmp/review-payload.json
```

Response body contains the specific field error. Fix and retry.

## Verifying the Review Posted

```bash
# List recent reviews on the PR
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" --jq '.[-1] | {id, state, submitted_at, body: (.body[:80])}'

# List recent inline comments
gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" --jq '.[-5:] | map({path, line, body: (.body[:80])})'
```

If the review ID appears, you're done. If not, check the error from the POST.

## Authentication

Required scopes:
- **Classic PAT**: `repo` scope
- **Fine-grained PAT**: `Pull requests — Write`
- **gh CLI**: default `gh auth login` grants the needed scope

Verify before Stage 7: `gh auth status`
