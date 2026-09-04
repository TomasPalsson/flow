---
name: fix-diagnosis
description: Template for bug diagnosis reports — classification, reproduction, root cause analysis, fix strategy, and regression test plan
---

# Bug Diagnosis Template

Create `.claude/fix-diagnosis.local.md` with the following structure. Fill in all sections based on the triage investigation.

```markdown
# Bug Fix: [title]

## Bug Description
[From user's input — what is broken and when does it happen]

## Classification
- **Type**: frontend / backend / integration / infrastructure
- **Severity**: critical / high / medium / low

## Reproduction
- **Reproduced**: Yes / No
- **Method**: agent-browser / code analysis / test script / log analysis
- **Steps**:
  1. [numbered reproduction steps]
  2. [step 2]
  3. [step 3]
- **Before screenshot**: ./bug-before.png (if UI bug)
- **Console errors**: [any JS errors found, or "none"]
- **Server logs**: [relevant log lines, or "not checked"]
- **Reproduction script**: [path, if created]

## Production Logs (if available)
- **Log source**: [log groups / files checked]
- **Time window**: last [N] minutes
- **Relevant entries**: [key error lines, stack traces]
- **Correlation**: [do timestamps match when bug was reported?]

> Skip this section if no log-fetching capability exists in the project.

## Root Cause Analysis
- **Affected files**: [list with line numbers]
- **Additional files**: [files discovered during fix that also need changes — document why for each]
- **Root cause**: [clear description of WHY the bug happens]
- **Introduced by**: [commit hash if identifiable, or "unknown"]
- **Code path**: [trace from trigger to failure]

## Fix Strategy
- **Approach**: [what to change and why]
- **Files to modify**:
  | File | Change |
  |------|--------|
  | [path] | [specific change] |
  | [path] | [specific change] |
- **Risk**: low / medium / high — [what else could break and why]

## Regression Tests
- **Existing tests**: [tests that relate to this area — are they passing?]
- **New tests needed**: [tests to add that would catch this bug]
- **Tests to update**: [tests that need changes due to the fix]
```
