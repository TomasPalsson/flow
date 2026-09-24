---
name: pr-reviewer-planning
description: Review plan template for the pr-reviewer skill. Used when the orchestrator needs to externalize the plan before executing (large PRs or when user asks to preview the plan).
---

# PR Review Plan Template

Write this template to `.pr-review/plan.md` after Stage 3 (size gate) and before
launching specialists. The plan is the contract between orchestrator and user
for what will be reviewed and how.

## Template

```markdown
# PR Review Plan — PR #<N>: <title>

## Context
- **Repo**: <owner>/<repo>
- **Head SHA**: <sha>
- **Base**: <base branch>
- **Author**: <github handle>
- **Size**: <LINES_CHANGED> lines changed in <N> files
- **Size tier**: small / medium / large
- **Comment budget**: <N> (hard cap)

## Intent (from PR description + commits + linked issues)
<1-2 sentence summary of what this PR is trying to accomplish>

## Risk Triage

| File | Tier | Lines | Notes |
|------|------|-------|-------|
| src/auth/session.ts | T1 | +42 / -8 | Authentication logic |
| src/utils/clock.ts | T3 | +12 / -0 | Internal helper |
...

**Blast radius**: <low | medium | high>
**Rationale**: <why this tier, what the worst case failure would look like>

## Specialist Assignments

- [ ] **Correctness Reviewer**: T1 + T2 files for logic/nullability/edge cases
- [ ] **Security Reviewer**: ENABLED because of <files/reasons>
- [ ] **Tests Reviewer**: check coverage of new behavior in <file>
- [ ] **Design Reviewer**: DISABLED because PR is <100 lines and no API changes

Each specialist runs with the "competitor LLM framing" to avoid the same-AI blind spot.
Each writes findings to `.pr-review/findings/<agent>.json`.

## Filters to Apply at Consolidation

1. **Scope Gate**: drop findings outside the diff
2. **Tool Overlap**: drop findings a linter/type-checker catches
3. **Pattern Merge**: apply Rule of Three for ≥3 occurrences
4. **Confidence Gating**: downgrade <0.60 confidence to `question`
5. **Comment Budget**: cap at <N>, rank by severity × confidence
6. **Targeted Praise**: add 0 or 1 specific praise comment

## Expected Verdict Criteria

- **APPROVE**: 0 findings after filters, OR only `nitpick`/`thought`/`praise` labels
- **COMMENT**: some findings but none with `blocking=true` at confidence ≥0.85
- **REQUEST_CHANGES**: ≥1 finding with `blocking=true` AND confidence ≥0.85

## User Approval Gate

Before posting, present the final plan to the user for approval/edit/drop/cancel.
Do NOT post without explicit user approval.

## Posting Strategy

Single atomic `gh api POST /reviews` call with all comments[] in one request.
Batch is ONE content-generating request (vs N for individual /comments POSTs).
This respects the 80/min content rate limit and keeps the review atomic.
```

## When to Use This Template

- **Large PRs (>400 LOC)**: write the plan before Stage 4 and show it to the user
  before spawning specialists. Lets them veto scope before you burn sonnet tokens.
- **High blast radius PRs**: always write, always show. The user should see the
  triage before review proceeds.
- **Small PRs**: skip — the plan overhead isn't worth it. Just run the pipeline.

## What NOT to Put in the Plan

- Specific code-level findings — those come out of Stage 4 specialists
- Verdict — that's computed at Stage 5, not planned
- Comment bodies — those are drafts from specialists, not preplanned
- File-level reviews — scope the plan to WHAT gets reviewed, not HOW it gets reviewed

## Plan Validation Checklist

Before accepting the plan:

- [ ] Intent is a specific 1-2 sentence summary, not a copy of the PR title
- [ ] Every changed file appears in the triage table with a tier assignment
- [ ] Blast radius matches the highest-tier file
- [ ] Specialist assignments have explicit enable/disable decisions (no vague "maybe")
- [ ] Comment budget matches size tier (small=8, medium/large=5)
- [ ] Verdict criteria reference the filters, not raw counts
