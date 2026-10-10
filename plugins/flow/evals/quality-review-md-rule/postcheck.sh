#!/usr/bin/env bash
set -u
[ -f review-out.md ] || { echo "postcheck: review-out.md missing"; exit 1; }
grep -q 'REVIEW.md' review-out.md || { echo "postcheck: the review never cites REVIEW.md"; exit 1; }
grep -q 'console.log' review-out.md || { echo "postcheck: the review never names console.log"; exit 1; }
