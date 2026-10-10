#!/usr/bin/env bash
set -u
[ -f review-out.md ] || { echo "postcheck: review-out.md missing"; exit 1; }
if grep -Eiq '(per|violat[a-z]*|breaks?|against|states)[^.]{0,30}REVIEW\.md' review-out.md; then echo "postcheck: the review cites a REVIEW.md that does not exist"; exit 1; fi
