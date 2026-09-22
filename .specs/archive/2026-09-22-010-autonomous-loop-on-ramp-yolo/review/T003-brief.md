# Brief — T003
Base: 7c2c820
Feature: /Users/tomas/Desktop/Projects/flow/.specs/010-autonomous-loop-on-ramp-yolo
Approved: 2026-09-22 by user
Spec: spec.md
Design: design.md
Route: dispatch
Test: `TEST_ONLY=test_loop.sh bash plugins/flow/scripts/tests/run.sh`

## Phase 2 — The arming safety net
Goal: no loop can be armed on a verifier that has not been shown to fail, and no failed bootstrap leaves anything behind.
Independent test: `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` — green with the driver untouched.

## Your task
- [ ] T003 The negative control, and init refuses to arm without it (B3, B4, FR-04, FR-05, FR-11) — files: plugins/flow/bin/lib/loop/negcontrol.js, plugins/flow/bin/lib/loop/init.js, plugins/flow/scripts/tests/test_loop_negcontrol.sh — verify: `TEST_ONLY=test_loop_negcontrol.sh bash plugins/flow/scripts/tests/run.sh` — after: T001


## Before you write
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

Before writing any new function, class, or helper: search the whole repository for an
existing implementation of the same behaviour. A name search is not enough — the helper
you need is usually named differently. Do all three: (1) list the helper packages
(`**/{utils,support,helpers,lib,common,shared,core}/**`) and open every small module
there; (2) grep the exact idiom you are about to write — the regex (`[^a-z0-9]+`), the
join, the format string, the arithmetic — an existing helper contains it; (3) grep the
verb and two synonyms (slug: kebab, dash, hyphen; format: render, label; validate:
check, verify; parse: load, decode; retry: backoff) plus the library you would import.
When an LSP tool is available, query workspace symbols for each term too. Reuse what
exists. State in one line what you searched and what you found before your first edit,
in the form: `searched: <terms and dirs>; found: <path:line | nothing>`.

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

## Contract for T003 — the negative control
CONTRACT   `plugins/flow/bin/lib/loop/contract.js` for field names; `verify.js` for `runVerify`.
NAMES      `negControl`, `inducedBreak`, `verdict`, `restored`. Banned: sanity check, canary, mutation, sabotage.
MODULE     `negcontrol.js` · layer 1 · may import: contract.js, verify.js, node builtins
           · exports: `runNegControl(toplevel, opts) -> { verdict, file, restored, ms }`
CALLS      `opts = { verify, verifyTimeout, file, env }`. `verdict` is one of the literals
           `'red-then-restored'`, `'survived'`, `'not-restored'`, `'timeout'`.
           Map to exit codes per §3: survived → 4, not-restored → 5, timeout → 6.
           Time bound: `2 * verifyTimeout` seconds (spec §5), measured across the whole call.
DUPLICATE  §6 bullets 1 and 3 — never fold this into `runVerify`, never reuse the tamper checksums.
THE FIVE   (1) NEVER invent an error type, field name or result shape that already exists in the
           contract — copy the literal declaration. (2) NEVER type a boundary function's parameter
           as the narrow type; the narrow type is only ever the RETURN of a fallible function.
           (3) NEVER add a mode, flag or extra required parameter to a shared abstraction the design
           handed you — duplicate it inside your task and say so. (4) NEVER refactor or rename
           outside the task's `files:` list — a change to an unlisted file is a defect.
           (5) NEVER abbreviate inside an identifier. Spell the word.

## Rules
Touch only the paths in files:. Failing test first, verify it fails, minimal
implementation, verify it passes, commit. Do not tick the box — the
orchestrator re-runs verify: and runs flow tick T003.
