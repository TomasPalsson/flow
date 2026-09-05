# Review guide

## Severity
- critical: wrong behavior, data loss, security.
- important: correctness risk or a missing test.
- minor: style; at most 3 minor comments per review.

## Every behavior claim cites file:line
Do not assert what code does without pointing at the line that does it.

## Always check first
- The test and CI config diff: skipped, xfail'd, weakened, or deleted tests.
- Lowered thresholds (line limits, complexity, coverage) in any config.

## Do not comment on
- Formatting — handled by tools, not reviewers.
- Naming preferences that don't change behavior.

## PR size
5+ unrelated files, or a change that can't be summarised in one sentence,
means asking the author to split the PR before reviewing it in depth.
