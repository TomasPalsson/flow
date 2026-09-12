---
name: no-slop-developer-block
description: The verbatim instruction block a developer agent receives before writing a slice. Paste it whole into the slice brief or the implement prompt; do not paraphrase. Load when assembling a brief for a developer agent.
---

# Developer block (paste verbatim)

Measured on 2026-09-12 with `claude plugin eval` (Sonnet, 3 runs per case): the first paragraph alone left a reuse case at 0 of 3; adding the search step took it to 3 of 3. Keep both.

```
Avoid over-engineering. Only make changes that are directly requested or clearly
necessary. Keep solutions simple and focused:

- Scope: Don't add features, refactor code, or make "improvements" beyond what was
  asked. A bug fix doesn't need surrounding code cleaned up. A simple feature doesn't
  need extra configurability.
- Documentation: Don't add docstrings, comments, or type annotations to code you
  didn't change. Only add comments where the logic isn't self-evident.
- Defensive coding: Don't add error handling, fallbacks, or validation for scenarios
  that can't happen. Trust internal code and framework guarantees. Only validate at
  system boundaries (user input, external APIs).
- Abstractions: Don't create helpers, utilities, or abstractions for one-time
  operations. Don't design for hypothetical future requirements. The right amount of
  complexity is the minimum needed for the current task.

Before writing any new function, class, or helper: search the repository for an
existing implementation of the same behaviour — by name, by verb synonyms, by the
library you would import, and by the error string you would raise. Reuse what exists.
State in one line what you searched and what you found before your first edit, in the
form: `searched: <terms>; found: <path:line | nothing>`.

Two rules that are not the same rule:
- An existing helper is reused, always. Re-implementing one is a defect.
- A new helper is extracted at the third similar block, or in a measured hot path,
  never at the second. Three similar lines beat a premature abstraction.

Comments: default to none. Add one short line only when the WHY is non-obvious — a
hidden constraint, an invariant, a workaround for a specific bug, behaviour that would
surprise a reader. Never explain WHAT the code does, and never reference the current
task, fix, ticket, or callers; those belong in the report and rot in the code.
No docstring on a function shorter than five lines unless the file already documents
every sibling.

Match the surrounding file exactly: quote style, naming case, indent, import style,
error types. Read the three functions above and below your insertion point first.

Tests: the new test must fail against the unchanged code before you make it pass, and
you report that exit code. Expected values come from the spec or hand computation,
never from running the implementation. No `assert True`, no `toBeDefined()` alone, no
asserting a mock was called with the input you just passed, no `raises(Exception)`,
no sleeps, no snapshot as the only assertion. Never skip, weaken, or delete a test.

Write a high-quality, general-purpose solution. Do not hard-code values or special-case
the test inputs. If the task is unreasonable or a test is wrong, say so in the report
instead of working around it.

Before reporting done, run `scripts/slop-check --base <base>` and either fix each
finding or justify it in one line in the report.
```

## Why each paragraph is there

| Paragraph | Evidence |
|---|---|
| Scope / documentation / defensive / abstractions | Anthropic's own countermeasure text for Opus 4.5 and 4.6 over-engineering, quoted verbatim (platform.claude.com, "Overeagerness"). |
| Search step with receipt | The only mitigation for semantic reinvention that any source supports; measured 0/3 → 3/3 on the reuse case. |
| Two rules | Cross-validation ruling A: reuse is zero-tolerance, extraction is Rule of Three. |
| Comments | Anthropic and Claude Code convention; Codex's "no comments at all" rejected for Claude models inside TDD. |
| Style match | Codex's official prompt and CodeRabbit's 2.66x formatting finding. |
| Tests | LLM oracles capture actual, not expected, behaviour; Red must be a real gate. |
| General solution | Anthropic's "avoid focusing on passing tests and hardcoding" block, condensed. |
| slop-check | Advisory mechanical pass; the developer fixes or justifies, the adversary confirms. |
