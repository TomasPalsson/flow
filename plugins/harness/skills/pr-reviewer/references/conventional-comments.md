---
name: conventional-comments
description: Severity taxonomy, confidence gating, Conventional Comments labels, framing rules, and the comment-or-not decision tree. Load at Stage 5 (Consolidation) of the pr-reviewer pipeline.
---

# Conventional Comments, Severity, and Framing

Load this file at **Stage 5 (Consolidation)**. It contains the rules that convert
raw specialist findings into postable, well-framed review comments.

## The Label Taxonomy (Conventional Comments)

Every posted comment MUST start with one of these labels, optionally followed by
decorations in parentheses, then a colon, then the subject:

```
<label> [decorations]: <subject>

[body discussion]
```

### Primary Labels

| Label | Use When | Blocking by Default |
|-------|----------|---------------------|
| `issue` | Flagging a defect — correctness bug, security flaw, data loss, broken contract. MUST include a concrete failure scenario. | Yes (if no decoration) |
| `suggestion` | Proposing a better approach. MUST explain WHY it's better. | Depends on decoration |
| `nitpick` | Trivial preference — naming, micro-style. NEVER blocks. | No |
| `question` | Uncertain concern. Asking for author context before asserting a problem. | No |
| `thought` | Idea that emerged during review; not for this PR. | No |
| `todo` | Small required change that isn't a defect (add CHANGELOG, remove debug line). | Yes |
| `chore` | Procedural task (run migration, notify team). | Yes |
| `note` | Pure informational FYI — no action requested. | No |
| `praise` | Acknowledge a specific, non-obvious good decision. Never generic. | N/A |

### Decorations

- **`(blocking)`** — must be resolved before merge. Only apply to `issue` or `todo`.
- **`(non-blocking)`** — merge may proceed regardless. Explicit override of label default.
- **`(if-minor)`** — author's discretion: fix if the change is small, defer if not.

Domain-specific decorations are allowed: `(security)`, `(perf)`, `(a11y)`, `(breaking)`.

### Examples (Copy These Shapes)

```
issue (blocking): `parseInt(undefined)` returns NaN, which passes the `> 0` guard
on line 47 and allows negative IDs to reach the DB query.

The failure scenario: a POST with missing `id` field results in querying user -1.
```

```
suggestion (non-blocking): Consider `Promise.allSettled` here instead of
`Promise.all` — if one repository fetch fails, the other results are still
useful for the partial-render path below.
```

```
question: Is there a reason we fetch the user on every request rather than
caching post-authentication? Want to understand the invariant before flagging
as a perf concern.
```

```
nitpick: Variable name `data` is a bit generic — `userProfile` would match the
existing pattern in src/user/*.
```

```
praise: Using a sentinel value here instead of nullable avoids an entire class
of null-propagation bugs downstream — nice call.
```

## The Severity × Confidence Matrix

Severity and confidence are **orthogonal axes**. Both matter.

| Confidence | Severity→ | Critical | Major | Minor | Nitpick |
|------------|-----------|----------|-------|-------|---------|
| **≥0.85** | label: | `issue (blocking)` | `issue` or `todo` | `suggestion (non-blocking)` | `nitpick` |
| **0.60–0.85** | label: | `suggestion (blocking)` w/ hedging | `suggestion` | `suggestion (non-blocking)` | skip |
| **<0.60** | label: | `question` | `question` | `question` | skip |

**The rule**: confidence below 0.60 NEVER gets a direct assertion label. Always
use `question` framing. LLMs calibrated to sound confident will blow past this
unless you enforce it explicitly.

### Why confidence matters more than severity for LLM reviewers

Research (arXiv:2603.18740) found LLMs assign high-severity labels based on
pattern matching, not data-flow analysis. The false-positive rates that matter:

| Category | Untuned FP rate | Tuned FP rate | Implication |
|----------|-----------------|---------------|-------------|
| SAST security | 60–90% | 10–20% | Default to `question` unless data-flow confirmed |
| Dead code (framework) | ~70% | lower | Default to `question` in dynamic languages |
| Type errors (strict) | ~5% | ~2% | High confidence, direct assertion OK |
| Logic bugs | unmeasurable | unmeasurable | Require demonstrable failure scenario |
| Performance | very high | very high | NEVER blocking without benchmark |

## The "Is This Worth Commenting?" Decision Tree

Run every candidate finding through this tree in order:

```
1. Is this caught by existing linter/CI?
   YES → skip (suggest adding the rule to CI, don't comment)
   NO → continue

2. Is this within the PR's diff?
   NO → create issue/ticket, don't comment
   YES → continue

3. Would this still matter in 6 months if unaddressed?
   NO → skip or `nitpick` at most
   YES → continue

4. Is my confidence ≥ 0.60?
   NO → use `question` regardless of potential severity
   YES → continue

5. Is this a rule violation or a judgment call?
   RULE (style guide, spec, documented decision) → direct label, cite the rule
   JUDGMENT → `suggestion` or `thought`, explain the trade-off

6. Is the same issue present 3+ times?
   YES → ONE pattern-level comment referencing all instances
   NO → continue

7. Does addressing this require more than minor changes?
   YES + not critical → `suggestion (non-blocking)` or `thought`
   YES + critical → `issue (blocking)` with clear justification
   NO → proceed with chosen label
```

## Framing Rules (Every Comment Body)

### Rule 1: Never Say "You"

The word "you" triggers defensiveness. Replace with:
- **"we"**: "Can we handle null here?"
- **passive voice**: "The null case isn't handled."
- **subjectless**: "Missing null check on line 42."
- **question**: "Is null possible here?"

| Bad | Good |
|-----|------|
| You forgot to handle null here. | This should handle null. |
| You should use structuredClone. | Could we use structuredClone here? |
| You're leaking a goroutine. | The goroutine isn't cancelled on shutdown. |

### Rule 2: Tie to a Principle, Not Opinion

Weak: "I found this hard to understand."
Strong: "This class handles both downloading and parsing. Per SRP, split into
a Downloader and Parser so each has one reason to change."

When no principle applies, state observations, not judgments:
- OBSERVATION: "I found this hard to follow on first read."
- JUDGMENT: "This is confusing." ← don't do this.

### Rule 3: Request, Not Command

| Command (combative) | Request (cooperative) |
|---------------------|------------------------|
| Move this to a separate file. | Can we move this to a separate file? |
| Use `const` here. | Consider `const` here. |
| Rename this variable. | Rename suggestion: `userProfile` |

### Rule 4: Always Include a Failure Scenario for `issue`

An `issue` without a concrete failure scenario is a vague concern. Every `issue`
body MUST include the input, condition, or execution path that breaks the code.

```
issue (blocking): This loop doesn't break on empty results, causing an
infinite retry.

Failure scenario: if the `search()` call returns an empty array (e.g., no
matches for a valid query), the outer `while (results.length === 0)` loop
never exits.
```

### Rule 5: Suggest Only What Fits in 2-3 Lines

If the fix requires rewriting a function or refactoring multiple files, describe
the end state instead of writing the fix. Reviewers who write more code than the
author will are overstepping.

Exception: the ````suggestion` code block for 1-3 line mechanical replacements
(rename, add guard, reorder).

### Rule 6: Low-Confidence Findings Are Questions

If your confidence is below 0.85, hedge the language:
- "might be" / "could be" / "I wonder if"
- "worth verifying that..."
- "Is there a reason we..."

NEVER pair direct assertive language ("This is wrong") with low-confidence labels.
The combination trains authors to treat all your comments as uncertain.

## Comment Budget Enforcement

After all filters, the final comment count **must not exceed**:
- Small PRs (≤400 LOC): 8 inline comments
- Medium PRs (401–1000 LOC): 5 inline comments
- Large PRs (>1000 LOC): 5 inline comments

**The ranking function**: `severity_weight × confidence`
- critical: 4, major: 3, minor: 2, nitpick: 1, info: 0

**Tiebreaker**: prefer findings with lower `pattern_count` (already-aggregated
pattern comments have lower marginal value than isolated ones).

**What to do with dropped findings**: if dropping 5+ findings, add ONE top-level
summary line to the review body: "N additional observations omitted for brevity."
This is honest signaling without individually cluttering the diff.

## Praise Guidelines

The only rule: **specific or silent**.

Generic praise ("great work!") is measurably low-value and gets filtered by
authors as decoration. Specific praise on a non-obvious good decision is
measurably high-value for mentoring and motivation.

Valid praise examples:
- "Using a sentinel value instead of nullable avoids null-propagation — nice."
- "The state machine pattern here makes the retry logic testable in isolation."
- "Extracting this into a pure function made the cyclomatic complexity drop by half."

Invalid (skip these):
- "Great PR!"
- "Nice work on this."
- "Looks good overall."
- "I like the structure."

## Verdict Computation

After filtering, assign verdict:

| Condition | Verdict |
|-----------|---------|
| ≥1 finding with `blocking=true` AND `confidence≥0.85` | **REQUEST_CHANGES** |
| 0 findings at all | **APPROVE** |
| Otherwise (findings but none blocking-confident) | **COMMENT** |

**Important**: the default verdict for a review with only suggestions and nits
is **COMMENT**, not REQUEST_CHANGES. Google explicitly endorses "LGTM with
comments" — approving while leaving unresolved non-blocking feedback.
REQUEST_CHANGES is reserved for actual blockers.
