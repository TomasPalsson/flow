#!/usr/bin/env bash
# post-review.sh — atomic single-call batch PR review poster
#
# Usage:
#   post-review.sh <owner> <repo> <pr_number> <consolidated.json>
#
# The consolidated.json file must contain the full payload shape expected
# by POST /repos/{owner}/{repo}/pulls/{pr_number}/reviews:
#
#   {
#     "commit_id": "<sha>",    // if absent, this script fetches and injects head SHA
#     "body": "<summary>",
#     "event": "APPROVE" | "REQUEST_CHANGES" | "COMMENT",
#     "comments": [
#       {"path": "...", "line": N, "side": "RIGHT", "body": "..."},
#       ...
#     ]
#   }
#
# Exit codes:
#   0  success, review posted
#   1  usage error
#   2  payload file missing or invalid JSON
#   3  gh api call failed (see stderr for details)
#   4  gh or jq not installed

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF >&2
Usage: $SCRIPT_NAME <owner> <repo> <pr_number> <payload.json>

Posts an atomic batched PR review (verdict + all inline comments in one API call).
Refreshes the head SHA before posting to avoid stale commit_id 422 errors.
EOF
  exit 1
}

die() {
  local code="$1"; shift
  echo "$SCRIPT_NAME: $*" >&2
  exit "$code"
}

# Dependency checks
command -v gh >/dev/null 2>&1 || die 4 "gh CLI not installed (https://cli.github.com)"
command -v jq >/dev/null 2>&1 || die 4 "jq not installed (brew install jq)"

# Arg parsing
[ "$#" -eq 4 ] || usage
OWNER="$1"
REPO="$2"
PR_NUMBER="$3"
PAYLOAD_FILE="$4"

[ -f "$PAYLOAD_FILE" ] || die 2 "payload file not found: $PAYLOAD_FILE"
jq empty "$PAYLOAD_FILE" 2>/dev/null || die 2 "payload file is not valid JSON: $PAYLOAD_FILE"

# Validate required fields
EVENT=$(jq -r '.event // empty' "$PAYLOAD_FILE")
case "$EVENT" in
  APPROVE|REQUEST_CHANGES|COMMENT) ;;
  "") die 2 "payload missing required 'event' field" ;;
  *) die 2 "payload 'event' must be APPROVE, REQUEST_CHANGES, or COMMENT (got: $EVENT)" ;;
esac

BODY=$(jq -r '.body // empty' "$PAYLOAD_FILE")
if [ "$EVENT" != "APPROVE" ] && [ -z "$BODY" ]; then
  die 2 "payload 'body' is required when event is $EVENT"
fi

COMMENT_COUNT=$(jq '.comments | length' "$PAYLOAD_FILE")
echo "$SCRIPT_NAME: posting review with event=$EVENT, $COMMENT_COUNT inline comments" >&2

# Refresh head SHA — critical to avoid stale commit_id 422
echo "$SCRIPT_NAME: fetching current head SHA for $OWNER/$REPO#$PR_NUMBER" >&2
HEAD_SHA=$(gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER" --jq '.head.sha' 2>/dev/null) \
  || die 3 "failed to fetch PR head SHA — does PR #$PR_NUMBER exist in $OWNER/$REPO?"

if [ -z "$HEAD_SHA" ] || [ "${#HEAD_SHA}" -lt 40 ]; then
  die 3 "fetched head SHA looks invalid: $HEAD_SHA"
fi

echo "$SCRIPT_NAME: head SHA $HEAD_SHA" >&2

# Inject fresh commit_id into the payload (overrides any stale one already present)
REFRESHED_PAYLOAD=$(mktemp /tmp/pr-review-payload.XXXXXX.json)
trap 'rm -f "$REFRESHED_PAYLOAD"' EXIT

jq --arg sha "$HEAD_SHA" '.commit_id = $sha' "$PAYLOAD_FILE" > "$REFRESHED_PAYLOAD"

# Post the review
echo "$SCRIPT_NAME: posting to repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" >&2

RESPONSE=$(mktemp /tmp/pr-review-response.XXXXXX.json)
trap 'rm -f "$REFRESHED_PAYLOAD" "$RESPONSE"' EXIT

HTTP_CODE=$(gh api \
  --method POST \
  "repos/$OWNER/$REPO/pulls/$PR_NUMBER/reviews" \
  --input "$REFRESHED_PAYLOAD" \
  > "$RESPONSE" 2>&1 && echo "200" || echo "error")

if [ "$HTTP_CODE" != "200" ]; then
  echo "$SCRIPT_NAME: gh api failed — response:" >&2
  cat "$RESPONSE" >&2
  die 3 "review POST failed (see error above)"
fi

# Extract review id from the response for confirmation
REVIEW_ID=$(jq -r '.id // "unknown"' "$RESPONSE")
REVIEW_STATE=$(jq -r '.state // "unknown"' "$RESPONSE")
REVIEW_URL=$(jq -r '.html_url // "unknown"' "$RESPONSE")

echo "$SCRIPT_NAME: ✓ review posted (id=$REVIEW_ID, state=$REVIEW_STATE)" >&2
echo "$REVIEW_URL"
