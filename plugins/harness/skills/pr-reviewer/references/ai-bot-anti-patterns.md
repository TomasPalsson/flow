---
name: pr-reviewer-anti-patterns
description: The 9 documented failure modes of AI PR review bots, each expressed as a forbidden behavior with its recovery rule. Load at Stage 4 (Parallel Specialist Review) — every specialist prompt must include the "forbidden behaviors" block from this file.
---

# Forbidden Behaviors — The AI Review Bot Failure Modes

This file encodes the 9 failure modes that make AI PR review bots get disabled
by teams. Every specialist agent prompt in Stage 4 must include the forbidden-
behaviors block. Every finding must be checked against these rules at Stage 5.

## Why These Rules Exist

Independent benchmarks of CodeRabbit, Greptile, Graphite Diamond, Copilot,
Sourcery, and others show the same pattern: detection rates vary 6–82%, but
precision is usually under 50%. Teams disable bots not because they miss
bugs, but because **70–90% of AI comments are noise**. The failure modes below
are the specific mechanisms producing that noise.

## Failure Mode 1: Nitpick / Comment Overwhelm

**What happens**: Bot leaves 10–20 comments per PR; 60–80% are style issues,
naming preferences, or "consider adding null checks" that don't represent
real bugs.

**Why**: LLMs are trained to be helpful and are penalized for missing issues,
creating a perverse incentive toward exhaustiveness. Vendors tune for recall,
not precision.

**Forbidden behavior**:
- NEVER emit more than 10 findings from a single specialist (consolidation has
  a final budget of 8).
- NEVER emit a finding whose `severity` is `nitpick` and whose `category` is
  `style` or `formatting` — those are out of scope.
- NEVER emit a finding with body like "consider adding null checks here"
  without a demonstrated null path.

**Recovery rule**: if a finding's severity is `nitpick` AND the body describes
something a linter would catch, DROP IT in the specialist itself.

## Failure Mode 2: Confident Wrong — Hallucinated Issues

**What happens**: Bot flags code that has no real problem, sometimes inventing
missing methods, claiming type errors that don't exist, or misreading the diff.
Delivered with authoritative tone.

**Real example**: "Claude regularly says to use one method over another... the
method doesn't actually exist in that language. Seems to get rather confused
between C# and C++." (HN)

**Forbidden behavior**:
- NEVER assert a bug without citing the exact input or condition that triggers it.
- NEVER reference a function, variable, or import without verifying it exists
  in the diff or retrievable context.
- NEVER claim "this is wrong" without `failure_scenario` populated.

**Recovery rule**: if a finding has no `failure_scenario`, downgrade its label
to `question` and its blocking to false at Stage 5.

## Failure Mode 3: Missing Codebase Context — "Linter with Better Prose"

**What happens**: Bot flags intentional code patterns as bugs, suggests renames
that would break downstream, recommends architectural patterns the team
explicitly avoided, because it sees only the diff.

**Real example**: Bot suggested renaming `user_ctx` to `user_context`, not
knowing `user_ctx` is enforced across 30 services.

**Forbidden behavior**:
- NEVER flag a naming convention without verifying the convention used elsewhere
  in the repo.
- NEVER suggest architectural alternatives without checking what's already in
  the adjacent code.
- NEVER flag missing error handling when the project uses a global error boundary.

**Recovery rule**: when in doubt about intent, emit a `question` label asking
for clarification, not an `issue` asserting a problem.

## Failure Mode 4: Missed the Point — Syntax Over Intent

**What happens**: Bot catches style/formatting issues competently but misses:
should this change exist at all? Is the design correct? Does it break
anything downstream?

**Real example**: Graphite Diamond caught 0% of high-severity bugs in the
Greptile benchmark across 50 real-world PRs.

**Forbidden behavior**:
- NEVER focus exclusively on line-level issues. Every specialist's prompt
  includes the PR intent from Stage 1 — read it, and judge whether the diff
  achieves it.
- NEVER skip the PR description.

**Recovery rule**: the Design Reviewer specifically exists to catch intent
mismatches. If PR ≥ 100 lines, Design Reviewer runs.

## Failure Mode 5: Junior Developer Harm — Misplaced Trust

**What happens**: Junior engineers treat bot comments as authoritative,
follow rabbit holes into non-issues, skip reviewing sections the bot
"covered".

**Real example** (HN): "The AI directs junior engineers into time-wasting
rabbit holes around things that are actually non-issues while actual issues
go completely unnoticed. Approximately 30% of the time."

**Forbidden behavior**:
- NEVER present a finding without its confidence level.
- NEVER let a user skip the approval gate — the user is the human judgment that
  catches the bot's overconfidence.
- NEVER auto-approve a PR based on AI review alone.

**Recovery rule**: Stage 6 user approval is NON-SKIPPABLE. No flag exempts it.

## Failure Mode 6: Alert Fatigue — The "Ignored by Team" Threshold

**What happens**: Once FP rate becomes high enough, developers stop reading any
comments. The bot continues running but provides zero value.

**Real example** (low confidence, HN summary): a credentials leak reached
production because the warning was comment #43 in a PR with 60 AI-generated
nitpicks about variable naming.

**Forbidden behavior**:
- NEVER exceed the COMMENT_BUDGET (8 inline for small, 5 for medium/large).
- NEVER let specialist output pass straight to the PR without consolidation.

**Recovery rule**: comment budget is a HARD CAP at Stage 5. Drop everything
beyond it; don't post 9 comments "because all 9 matter." If all 9 seem to
matter, your confidence calibration is wrong.

## Failure Mode 7: Scale Problem — Large PRs Overwhelm Authors

**What happens**: On PRs with hundreds of lines, bots generate 30–60+ comments.
Authors prioritize randomly or dismiss everything.

**Real example**: CodeRabbit the "most talkative", leaving highest comment
volume per PR. Lychee project found 15% of CodeRabbit comments useless.

**Forbidden behavior**:
- NEVER bypass the size gate at Stage 3.
- NEVER increase the COMMENT_BUDGET beyond 8.
- NEVER emit comments proportional to PR size. A 1000-line PR gets at most
  5 comments from this pipeline.

**Recovery rule**: Stage 3 refuses large PRs outright unless the user overrides.
Cap stays at 5 when overridden.

## Failure Mode 8: Hallucinating Non-Existent Code

**What happens**: Bot references variables, functions, files, or imports that
don't exist in the codebase, suggesting fixes for bugs that aren't there.

**Real example**: Graphite's own blog — "GPT-4 would invent a concern to
mention" when reviewing simple flawless code rather than remaining silent.

**Forbidden behavior**:
- NEVER cite a line that isn't in the diff.
- NEVER reference a function name that doesn't appear in the diff or imports.
- NEVER suggest fixes based on code you can't point to.

**Recovery rule**: Filter 5a at Stage 5 (Scope Gate) drops all findings whose
`file:line` isn't in `gh pr diff`. Hallucinations die there.

## Failure Mode 9: Same-AI Reviewing Same-AI — The Blind Spot Loop

**What happens**: When AI assists code authoring AND reviews its own output,
it systematically misses the same categories of flaws it introduced. The
reviewing model has the same gaps as the writing model.

**Research**: arXiv:2603.18740 — LLMs fail to correct errors in their own
output 64.5% of the time, but successfully flag identical errors when
attributed to external sources.

**Forbidden behavior**:
- NEVER frame the diff as "the user's code" in specialist prompts.
- NEVER present findings without first routing through the "competitor LLM
  framing" technique.

**Recovery rule**: every specialist prompt at Stage 4 starts with:

> The diff below was written by ANOTHER AI coding assistant (treat it as
> ChatGPT, Gemini, or Cursor output — NOT as your own, NOT as a trusted
> human's). Review it SKEPTICALLY for the classes of issues in your scope only.

This is a **prompting technique**, not a factual claim. It neutralizes the
self-correction blind spot. The code's actual authorship is irrelevant — what
matters is the framing puts the specialist in "critical reviewer of external
output" mode rather than "polite reviewer of collaborative work" mode.

## The Forbidden-Behaviors Block (Paste into Every Specialist Prompt)

```
## Forbidden Behaviors (enforced; violations dropped at consolidation)

You are NOT allowed to:

1. Emit more than 10 findings (hard cap — ranked at consolidation, extras dropped).
2. Emit a finding whose category is style, formatting, or naming convention —
   those are out of scope and caught by linters.
3. Emit a finding without a `failure_scenario` populated when label is `issue`.
4. Use "you" in any comment body — use "we", passive voice, or subjectless.
5. Comment on code outside the diff visible in `gh pr diff`.
6. Flag missing null checks, error handling, or validation without a
   demonstrated path through the code that reaches the unhandled state.
7. Suggest a rename or architectural alternative without verifying the existing
   convention or pattern in the adjacent code.
8. Assign confidence ≥ 0.85 to any finding based on pattern matching alone
   (SAST/security patterns without data-flow tracing, regex-based style checks).
9. Emit findings about your OWN scope overlap — each specialist stays in its lane.
10. Emit generic praise — praise only specific, non-obvious good decisions.

If you find zero issues in your scope, write `{"findings": []}`. An empty
review is strictly better than a noisy one.
```

## Checking Findings Against These Rules at Stage 5

At consolidation, the orchestrator re-reads this file and applies each rule
as a filter. Specialists are sonnet-powered and may violate rules despite
the prompt — the orchestrator is the safety net.

| Rule | Filter | Action |
|------|--------|--------|
| 1 | Comment budget | Rank, drop below budget cutoff |
| 2 | Tool overlap gate | Drop |
| 3 | Missing failure_scenario | Downgrade label to `question` |
| 4 | Contains "you" | Rewrite or drop |
| 5 | Scope gate | Drop |
| 6 | No demonstrated path | Downgrade to `question`, mark non-blocking |
| 7 | Unverified convention claim | Downgrade to `question` |
| 8 | High confidence pattern-match | Downgrade confidence to 0.60, relabel to `question` |
| 9 | Out-of-scope finding | Drop (should not have been emitted) |
| 10 | Generic praise | Drop |
